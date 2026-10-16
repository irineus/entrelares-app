-- =============================================================================
-- F-88 (PR 2) — a founder who was invited elsewhere is offered the way in;
-- an invitation already accepted says so (fase 2 da auditoria T-103, 05/10/2026)
--
-- The ex says "baixa o Entrelares, te convidei"; the parent opens the app, taps
-- *Criar conta* and founds a family of their own. The invitation link then
-- answers "Este e-mail já possui cadastro" and only support could untangle it.
--
-- Owner's decision (04/10/2026): when a founder's VERIFIED e-mail has a pending
-- invitation and their family has no other member and nothing planned, OFFER
-- the way in ("Você tem um convite de X para a família Y — entrar nela?");
-- confirming takes the existing claim path and the empty family is discarded.
--
--   * family_is_empty_for_join — nobody else (pending, viewer or departed),
--     no planned day, no child, no subscription row: a family with any of it
--     is never discarded, whatever the client asks.
--   * my_pending_invitation() — the offer, for the caller only: verified
--     e-mail, empty family, an open invitation to that address in ANOTHER
--     family. Answers nothing otherwise.
--   * join_invitation_from_empty_family(token, policy_version) — re-checks
--     all of it, purges the empty family (purge_family_data, the
--     family-deletion teardown, which takes the caller's profile with it)
--     and claims through
--     claim_invitation_for_user, the SQL twin of the invitee sign-up. The
--     caller's auth user survives (it is the session making the call).
--   * invite_token_status(token) — `pending` / `accepted` / `unusable`, so an
--     accepted invitation reads "é só entrar" instead of "peça um novo". The
--     token is the capability; nothing else about the invitation leaks.
-- =============================================================================

-- ── enforce_profile_protection — latest body (20260924140000_f50_viewer.sql)
-- with ONE change: the last-admin guard on DELETE steps aside inside the
-- controlled purge, as every other guard of the teardown already does. The
-- family-deletion cron ran as the system (no auth.uid) and never met it.
CREATE OR REPLACE FUNCTION public.enforce_profile_protection()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
	actor_admin  boolean;
	actor_family bigint;
BEGIN
	-- System context (service_role / migrations): unrestricted.
	IF auth.uid() IS NULL THEN
		RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
	END IF;

	SELECT is_admin, family_id INTO actor_admin, actor_family
	FROM public.profiles WHERE user_id = auth.uid();

	IF TG_OP = 'UPDATE' THEN
		-- S-11: a departed member's profile is FROZEN — no edits at all.
		-- Exceptions: the erasure cleanup (deletion_context) and the owner
		-- cancelling their own exit (left_at set -> NULL).
		IF OLD.left_at IS NOT NULL
		   AND current_setting('app.deletion_context', true) IS DISTINCT FROM 'on'
		   AND NOT (OLD.user_id = auth.uid() AND NEW.left_at IS NULL) THEN
			RAISE EXCEPTION 'Este responsável saiu da família e não pode mais ser alterado.'
				USING ERRCODE = 'check_violation';
		END IF;

		-- S-11 QA: the color slot is system-managed (join / return reclaim) —
		-- never a direct client edit.
		IF NEW.color_slot IS DISTINCT FROM OLD.color_slot
		   AND NOT (OLD.left_at IS NOT NULL AND NEW.left_at IS NULL)
		   -- F-50: promote_member_to_full hands the new caregiver a colour.
		   AND current_setting('app.viewer_promotion', true) IS DISTINCT FROM 'on' THEN
			RAISE EXCEPTION 'A cor de um responsável é gerenciada pelo sistema.'
				USING ERRCODE = 'check_violation';
		END IF;

		IF NEW.family_id IS DISTINCT FROM OLD.family_id THEN
			RAISE EXCEPTION 'A família de um perfil não pode ser alterada.'
				USING ERRCODE = 'check_violation';
		END IF;

		IF NEW.is_admin IS DISTINCT FROM OLD.is_admin THEN
			-- Blocks self-promotion through the profiles_own_update policy.
			IF COALESCE(actor_admin, false) = false OR actor_family IS DISTINCT FROM OLD.family_id THEN
				RAISE EXCEPTION 'Somente administradores da família podem alterar permissões de administrador.'
					USING ERRCODE = 'check_violation';
			END IF;

			-- Demotion: keep the >= 1 admin per family invariant.
			IF OLD.is_admin AND NOT NEW.is_admin AND NOT EXISTS (
				SELECT 1 FROM public.profiles
				WHERE family_id = OLD.family_id AND is_admin AND id <> OLD.id
			) THEN
				RAISE EXCEPTION 'A família precisa de pelo menos uma pessoa administradora.'
					USING ERRCODE = 'check_violation';
			END IF;
		END IF;

		-- F-16/F-27: role changes are admin-only (set_member_role) — the
		-- own-row UPDATE policy must not be a side door for self role edits.
		IF NEW.role_id IS DISTINCT FROM OLD.role_id THEN
			IF COALESCE(actor_admin, false) = false OR actor_family IS DISTINCT FROM OLD.family_id THEN
				RAISE EXCEPTION 'Somente administradores da família podem alterar papéis.'
					USING ERRCODE = 'check_violation';
			END IF;
		END IF;

		RETURN NEW;
	END IF;

	-- DELETE: never remove the last admin of a family — except inside the
	-- controlled purge (app.deletion_context), which removes the WHOLE family:
	-- F-88's join from an empty family runs it as the user, not as the system.
	IF OLD.is_admin
	   AND current_setting('app.deletion_context', true) IS DISTINCT FROM 'on'
	   AND NOT EXISTS (
		SELECT 1 FROM public.profiles
		WHERE family_id = OLD.family_id AND is_admin AND id <> OLD.id
	) THEN
		RAISE EXCEPTION 'A família precisa de pelo menos uma pessoa administradora.'
			USING ERRCODE = 'check_violation';
	END IF;
	RETURN OLD;
END;
$$;

CREATE OR REPLACE FUNCTION public.family_is_empty_for_join(p_family_id bigint, p_profile_id bigint)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
	SELECT NOT EXISTS (SELECT 1 FROM public.profiles
	                   WHERE family_id = p_family_id AND id <> p_profile_id)
	   AND NOT EXISTS (SELECT 1 FROM public.care_schedules WHERE family_id = p_family_id)
	   AND NOT EXISTS (SELECT 1 FROM public.children WHERE family_id = p_family_id)
	   AND NOT EXISTS (SELECT 1 FROM public.subscriptions WHERE family_id = p_family_id)
	   AND NOT EXISTS (SELECT 1 FROM public.family_deletion_requests
	                   WHERE family_id = p_family_id AND status = 'pending');
$$;

ALTER FUNCTION public.family_is_empty_for_join(bigint, bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.family_is_empty_for_join(bigint, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.family_is_empty_for_join(bigint, bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.my_pending_invitation()
RETURNS TABLE (token uuid, family_name text, inviter_name text, member_type text)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me        public.profiles%ROWTYPE;
	the_email text;
	confirmed timestamptz;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid() AND left_at IS NULL;
	IF me.id IS NULL THEN
		RETURN;
	END IF;
	SELECT u.email, u.email_confirmed_at INTO the_email, confirmed
	FROM auth.users u WHERE u.id = auth.uid();
	IF the_email IS NULL OR confirmed IS NULL THEN
		RETURN;
	END IF;
	IF NOT public.family_is_empty_for_join(me.family_id, me.id) THEN
		RETURN;
	END IF;

	RETURN QUERY
	SELECT i.token, f.name, p.full_name, i.member_type
	FROM public.family_invitations i
	JOIN public.families f ON f.id = i.family_id
	JOIN public.profiles p ON p.id = i.invited_by
	WHERE lower(i.email) = lower(the_email)
	  AND i.family_id <> me.family_id
	  AND i.accepted_at IS NULL
	  AND i.revoked_at  IS NULL
	  AND i.expires_at  > timezone('utc', now())
	ORDER BY i.created_at DESC
	LIMIT 1;
END;
$$;

ALTER FUNCTION public.my_pending_invitation() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.my_pending_invitation() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_pending_invitation() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.join_invitation_from_empty_family(
	p_token          uuid,
	p_policy_version text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me        public.profiles%ROWTYPE;
	the_email text;
	confirmed timestamptz;
	old_family bigint;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid() AND left_at IS NULL;
	IF me.id IS NULL THEN
		RAISE EXCEPTION 'Sessão inválida. Entre novamente.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;
	SELECT u.email, u.email_confirmed_at INTO the_email, confirmed
	FROM auth.users u WHERE u.id = auth.uid();
	IF confirmed IS NULL THEN
		RAISE EXCEPTION 'Confirme seu e-mail antes de entrar em outra família.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- The same family the offer judged — and judged again, under the lock the
	-- claim takes, so nothing planned since the dialog opened is discarded.
	PERFORM pg_advisory_xact_lock(hashtext(auth.uid()::text));
	IF NOT public.family_is_empty_for_join(me.family_id, me.id) THEN
		RAISE EXCEPTION 'Sua família atual já tem outros membros ou dias planejados — ela não pode ser descartada.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF NOT EXISTS (SELECT 1 FROM public.family_invitations i
	               WHERE i.token = p_token
	                 AND lower(i.email) = lower(the_email)
	                 AND i.family_id <> me.family_id
	                 AND i.accepted_at IS NULL
	                 AND i.revoked_at  IS NULL
	                 AND i.expires_at  > timezone('utc', now())) THEN
		RAISE EXCEPTION 'Convite inválido, expirado ou emitido para outro e-mail.'
			USING ERRCODE = 'check_violation';
	END IF;

	old_family := me.family_id;

	-- The family-deletion teardown, under its own deletion context. It hands
	-- back the auth ids of the family's profiles for a caller to delete; this
	-- caller deletes none — the only one is this session's, which survives.
	PERFORM 1 FROM public.purge_family_data(old_family);
	PERFORM set_config('app.deletion_context', 'off', true);

	PERFORM 1 FROM public.claim_invitation_for_user(
		auth.uid(), me.full_name, p_token::text, p_policy_version, false);
END;
$$;

ALTER FUNCTION public.join_invitation_from_empty_family(uuid, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.join_invitation_from_empty_family(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.join_invitation_from_empty_family(uuid, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.invite_token_status(p_token uuid)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
	SELECT CASE
		WHEN i.id IS NULL THEN 'unusable'
		WHEN i.accepted_at IS NOT NULL THEN 'accepted'
		WHEN i.revoked_at IS NULL AND i.expires_at > timezone('utc', now()) THEN 'pending'
		ELSE 'unusable'
	END
	FROM (SELECT 1) AS one
	LEFT JOIN public.family_invitations i ON i.token = p_token;
$$;

ALTER FUNCTION public.invite_token_status(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.invite_token_status(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.invite_token_status(uuid) TO anon, authenticated, service_role;
