-- =============================================================================
-- F-56 — Solo mode: the pending-member placeholder (invited, not yet joined)
--
-- The closed alpha showed the real adoption sequence: one motivated parent
-- arrives first and the other refuses the app. Until now the app was useless
-- to that first parent — every co-caregiver had to be a signed-up user before
-- a single day could be planned for them.
--
-- A third member state, PENDING, fixes that: a `profiles` row with NO auth
-- user (`user_id IS NULL`, `left_at IS NULL`), authored by the family admin
-- (name, role — colour allocated by the system). It is assignable to days and
-- visible to the family like any member, but it is never the counterpart of a
-- swap (nothing to approve with), never an admin, and receives nothing. When
-- the person eventually joins through an invitation, the auth user attaches
-- to the SAME row — every day ever planned for the placeholder survives.
--
-- The shape already existed: S-11 made `user_id` nullable for the departure
-- tombstone (user_id NULL + left_at set). The placeholder is its mirror image
-- (user_id NULL + left_at NULL), which is why almost every rule below is a
-- predicate that used `user_id IS NOT NULL` as its definition of "member" and
-- now has to say which of the two NULL states it means.
--
-- LGPD (owner, 09/09/2026): the placeholder carries ONLY what the admin wrote
-- about their own family (name, role, colour) — family data under §3 of the
-- privacy policy. The invitee's e-mail lives ONLY on the invitation row, which
-- the S-15/A-4 purge still removes 30 days after issue; the placeholder is
-- founder content, not invitee data, and the invitation e-mail says so.
--
-- What changes, in order:
--   0. schema — profiles.email nullable; family_invitations.profile_id;
--   1. seat_count() — a placeholder HOLDS a seat and a colour (F-37 honest);
--   2. next_free_color_slot — a placeholder's colour is occupied;
--   3. set_joined_via_invite — a placeholder is, by construction, invited;
--   4. notify_member_joined — fires on the CLAIM, never on the placeholder;
--   5. add_pending_member / create_invitation / remove_pending_member — RPCs;
--   6. handle_new_user + claim_invitation_for_user — claim = UPDATE, not INSERT;
--   7. enforce_swap_counterpart — a swap needs two live accounts (closes the
--      gap for departed members too: nothing checked the counterpart before);
--   8. auto_approve_expired — the F-28 fan-out skips profiles with no account;
--   9. set_member_admin — a placeholder cannot hold the admin bit;
--  10. get_invite_info — the invitee sees the name the admin gave them.
--
-- Every replaced body is copied VERBATIM from its latest migration (named in
-- each section) with only the F-56 lines changed — the rule the day-protection
-- trigger taught (eight rewrites, one silent loss).
-- =============================================================================

-- ── 0. Schema ────────────────────────────────────────────────────────────────

ALTER TABLE public.profiles ALTER COLUMN email DROP NOT NULL;

COMMENT ON COLUMN public.profiles.user_id IS
	'The auth user behind this profile. NULL in two states: a departure tombstone (left_at set, S-11) and a PENDING member — invited, not yet joined (left_at NULL, F-56). The pair (user_id, left_at) is the member state.';
COMMENT ON COLUMN public.profiles.email IS
	'Denormalized copy of auth.users.email. NULL for a pending member (F-56): the invitee''s e-mail lives on the invitation only, which the 30-day purge removes.';

ALTER TABLE public.family_invitations
	ADD COLUMN IF NOT EXISTS profile_id bigint REFERENCES public.profiles (id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS family_invitations_profile_idx
	ON public.family_invitations (profile_id) WHERE profile_id IS NOT NULL;

COMMENT ON COLUMN public.family_invitations.profile_id IS
	'F-56: the pending member this invitation is for. Accepting it attaches the new auth user to THAT profile instead of creating one. NULL on legacy invitations (no placeholder).';

-- ── 1. seat_count — a placeholder holds a seat ───────────────────────────────
-- active_member_count keeps its meaning (live accounts: admin succession,
-- family-deletion unanimity, last-member purge). SEATS are a different
-- question — F-37 counts people the family has room for, and a pending
-- member is one of them, exactly like an open invitation used to be.

CREATE OR REPLACE FUNCTION public.seat_count(p_family_id bigint)
RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
	SELECT count(*)::int FROM public.profiles
	WHERE family_id = p_family_id
	  AND left_at IS NULL;
$$;

ALTER FUNCTION public.seat_count(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.seat_count(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.seat_count(bigint) TO authenticated, service_role;

COMMENT ON FUNCTION public.seat_count(bigint) IS
	'F-56: seats taken by ACTIVE and PENDING members (left_at NULL, any user_id). The F-37 gates use this plus the open legacy invitations; active_member_count stays the count of live accounts.';

-- ── 2. next_free_color_slot — a placeholder''s colour is taken ───────────────
-- Body VERBATIM from 20260720170000 minus `user_id IS NOT NULL`: the slot of
-- anyone still IN the family (active or pending) is occupied; a tombstone's
-- (left_at set) is free.

CREATE OR REPLACE FUNCTION public.next_free_color_slot(p_family_id bigint)
RETURNS smallint
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
	SELECT gs::smallint FROM generate_series(1, 4) gs
	WHERE gs NOT IN (
		SELECT color_slot FROM public.profiles
		WHERE family_id = p_family_id AND left_at IS NULL
		  AND color_slot IS NOT NULL)
	ORDER BY gs LIMIT 1;
$$;

-- ── 3. set_joined_via_invite — a placeholder is invited by construction ──────
-- Body VERBATIM from 20260730190000; the INSERT branch gains `user_id IS NULL`.
-- The flag decides which legal declaration the person accepts when they claim
-- the row; a placeholder has no e-mail to match an invitation by, and only the
-- add_pending_member RPC can insert a profile without an auth user.

CREATE OR REPLACE FUNCTION public.set_joined_via_invite()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
	IF TG_OP = 'UPDATE' THEN
		NEW.joined_via_invite := OLD.joined_via_invite;   -- immutable after creation
		RETURN NEW;
	END IF;

	NEW.joined_via_invite := NEW.user_id IS NULL OR EXISTS (
		SELECT 1 FROM public.family_invitations i
		 WHERE lower(i.email) = lower(NEW.email)
	);
	RETURN NEW;
END;
$$;

-- ── 4. notify_member_joined — on the claim, not on the placeholder ───────────
-- The function (20260806180000) is untouched. The INSERT trigger gains a WHEN
-- so adding a placeholder does not announce "X juntou-se à família", and an
-- UPDATE trigger announces the moment the auth user attaches.

DROP TRIGGER IF EXISTS trigger_notify_member_joined ON public.profiles;
CREATE TRIGGER trigger_notify_member_joined
	AFTER INSERT ON public.profiles
	FOR EACH ROW
	WHEN (NEW.user_id IS NOT NULL)
	EXECUTE FUNCTION public.notify_member_joined();

DROP TRIGGER IF EXISTS trigger_notify_member_claimed ON public.profiles;
CREATE TRIGGER trigger_notify_member_claimed
	AFTER UPDATE OF user_id ON public.profiles
	FOR EACH ROW
	WHEN (OLD.user_id IS NULL AND NEW.user_id IS NOT NULL AND NEW.left_at IS NULL)
	EXECUTE FUNCTION public.notify_member_joined();

-- ── 5a. create_invitation — optionally FOR a pending member ─────────────────
-- Body from 20260802170000 (F-41). New third argument p_profile_id: when set,
-- the invitation is issued for that placeholder (its role, its identity), the
-- placeholder's previous open invitation is revoked (resend keeps the row and
-- its days), and the seat gates are skipped — the placeholder already holds
-- the seat. Without it the legacy behaviour stands, with the seat count now
-- reading seat_count() + open invitations that have NO placeholder.
--
-- The 2-argument overload is dropped rather than kept: PostgREST resolves a
-- named-parameter call against defaults, so the deployed clients' 2-argument
-- call keeps working, and one body is one less to drift.

DROP FUNCTION IF EXISTS public.create_invitation(text, bigint);

CREATE OR REPLACE FUNCTION public.create_invitation(
	p_email      text,
	p_role_id    bigint,
	p_profile_id bigint DEFAULT NULL
)
RETURNS TABLE (invitation_id bigint, token uuid, expires_at timestamp with time zone)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
	me          public.profiles%ROWTYPE;
	target      public.profiles%ROWTYPE;
	inv         public.family_invitations%ROWTYPE;
	clean_email text := NULLIF(lower(trim(p_email)), '');
	role_to_use bigint;
	max_seats   int := public.setting_int('max_caregivers', 4);
	free_seats  int := public.setting_int('free_caregivers', 2);
	taken       int;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();

	IF me.id IS NULL OR NOT me.is_admin THEN
		RAISE EXCEPTION 'Somente administradores da família podem enviar convites.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF EXISTS (SELECT 1 FROM public.family_deletion_requests
	           WHERE family_id = me.family_id AND status = 'pending') THEN
		RAISE EXCEPTION 'Há uma solicitação de exclusão da família em andamento — convites ficam bloqueados até ela ser resolvida.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF clean_email IS NULL THEN
		RAISE EXCEPTION 'Informe o e-mail de quem você quer convidar.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF EXISTS (SELECT 1 FROM public.profiles
	           WHERE lower(email) = clean_email
	             AND user_id IS NOT NULL AND left_at IS NULL) THEN
		RAISE EXCEPTION 'Este e-mail já possui cadastro no aplicativo.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF p_profile_id IS NOT NULL THEN
		-- F-56: the invitation is for a placeholder of MY family that nobody
		-- has claimed yet. Its role is the invitation's role.
		SELECT * INTO target FROM public.profiles
		WHERE id = p_profile_id AND family_id = me.family_id;
		IF target.id IS NULL THEN
			RAISE EXCEPTION 'Perfil não encontrado na sua família.'
				USING ERRCODE = 'check_violation';
		END IF;
		IF target.user_id IS NOT NULL OR target.left_at IS NOT NULL THEN
			RAISE EXCEPTION 'Só é possível convidar um responsável que ainda não entrou no aplicativo.'
				USING ERRCODE = 'check_violation';
		END IF;
		role_to_use := target.role_id;

		-- Resend keeps the identity: the placeholder's previous open invitation
		-- dies, the row and its days stay.
		UPDATE public.family_invitations fi
		SET revoked_at = timezone('utc', now())
		WHERE fi.profile_id = target.id
		  AND fi.accepted_at IS NULL AND fi.revoked_at IS NULL;
	ELSE
		-- F-41: a role is assignable when built-in OR a custom role of MY family —
		-- another family's custom role id must not resolve.
		IF NOT EXISTS (SELECT 1 FROM public.roles
		               WHERE id = p_role_id
		                 AND (family_id IS NULL OR family_id = me.family_id)) THEN
			RAISE EXCEPTION 'Papel inválido.'
				USING ERRCODE = 'check_violation';
		END IF;
		role_to_use := p_role_id;
	END IF;

	-- Resend semantics: revoke this e-mail's previous open invitation BEFORE
	-- counting seats, so a resend never trips the cap it already occupies.
	UPDATE public.family_invitations fi
	SET revoked_at = timezone('utc', now())
	WHERE fi.family_id = me.family_id
	  AND lower(fi.email) = clean_email
	  AND fi.accepted_at IS NULL AND fi.revoked_at IS NULL;

	IF p_profile_id IS NULL THEN
		-- Seats taken = ACTIVE + PENDING members + open invitations that carry
		-- no placeholder (a placeholder's invitation is the placeholder's seat).
		SELECT public.seat_count(me.family_id)
		     + (SELECT count(*) FROM public.family_invitations fi
		        WHERE fi.family_id = me.family_id
		          AND fi.profile_id IS NULL
		          AND fi.accepted_at IS NULL AND fi.revoked_at IS NULL
		          AND fi.expires_at > timezone('utc', now()))
		INTO taken;

		-- F-37 (T-41: free_caregivers from settings) — the free tier includes N
		-- caregivers; adding beyond that is Premium. Add-only + grandfather (F-32).
		IF taken >= free_seats AND NOT public.is_premium(me.family_id) THEN
			RAISE EXCEPTION 'Famílias no plano gratuito incluem % responsáveis. Para adicionar mais (avós, babá, etc.), ative o Premium.', free_seats
				USING ERRCODE = 'check_violation';
		END IF;

		IF taken >= max_seats THEN
			RAISE EXCEPTION 'Esta família já atingiu o limite de % responsáveis (contando convites pendentes).', max_seats
				USING ERRCODE = 'check_violation';
		END IF;
	END IF;

	INSERT INTO public.family_invitations (family_id, email, role_id, invited_by, profile_id)
	VALUES (me.family_id, clean_email, role_to_use, me.id, p_profile_id)
	RETURNING * INTO inv;

	RETURN QUERY SELECT inv.id, inv.token, inv.expires_at;
END;
$$;

ALTER FUNCTION public.create_invitation(text, bigint, bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.create_invitation(text, bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_invitation(text, bigint, bigint) TO authenticated, service_role;

COMMENT ON FUNCTION public.create_invitation(text, bigint, bigint) IS
	'Issues an invitation (admin only). With p_profile_id (F-56) the invitation is for that pending member: its role, its previous open invitation revoked, no seat gate (the placeholder holds the seat). Without it: legacy invitation, gated by seat_count() + open placeholder-less invitations.';

-- ── 5b. add_pending_member — the admin describes a member who is not here ────
-- Name and role are the admin's own description of their family; the colour
-- is the system's. The e-mail is OPTIONAL: given, an invitation goes out at
-- once (through create_invitation, so the two rows are one transaction —
-- a refused e-mail leaves no orphan placeholder); absent, the admin plans
-- alone and invites later from the member's card.

CREATE OR REPLACE FUNCTION public.add_pending_member(
	p_full_name text,
	p_role_id   bigint,
	p_email     text DEFAULT NULL
)
RETURNS TABLE (profile_id bigint, invitation_id bigint, token uuid, expires_at timestamp with time zone)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
	me          public.profiles%ROWTYPE;
	clean_name  text := trim(p_full_name);
	clean_email text := NULLIF(lower(trim(p_email)), '');
	max_seats   int := public.setting_int('max_caregivers', 4);
	free_seats  int := public.setting_int('free_caregivers', 2);
	taken       int;
	new_id      bigint;
	inv         record;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();

	IF me.id IS NULL OR NOT me.is_admin THEN
		RAISE EXCEPTION 'Somente administradores da família podem adicionar responsáveis.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF EXISTS (SELECT 1 FROM public.family_deletion_requests
	           WHERE family_id = me.family_id AND status = 'pending') THEN
		RAISE EXCEPTION 'Há uma solicitação de exclusão da família em andamento — convites ficam bloqueados até ela ser resolvida.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF clean_name IS NULL OR length(clean_name) < 2 OR length(clean_name) > 80 THEN
		RAISE EXCEPTION 'Informe um nome entre 2 e 80 caracteres.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF NOT EXISTS (SELECT 1 FROM public.roles
	               WHERE id = p_role_id
	                 AND (family_id IS NULL OR family_id = me.family_id)) THEN
		RAISE EXCEPTION 'Papel inválido.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- Refuse BEFORE the placeholder exists: the e-mail check that
	-- create_invitation would make must not leave a row behind.
	IF clean_email IS NOT NULL AND EXISTS (
		SELECT 1 FROM public.profiles
		WHERE lower(email) = clean_email
		  AND user_id IS NOT NULL AND left_at IS NULL) THEN
		RAISE EXCEPTION 'Este e-mail já possui cadastro no aplicativo.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- Same seat arithmetic as a legacy invitation: the placeholder IS the seat.
	SELECT public.seat_count(me.family_id)
	     + (SELECT count(*) FROM public.family_invitations fi
	        WHERE fi.family_id = me.family_id
	          AND fi.profile_id IS NULL
	          AND fi.accepted_at IS NULL AND fi.revoked_at IS NULL
	          AND fi.expires_at > timezone('utc', now()))
	INTO taken;

	IF taken >= free_seats AND NOT public.is_premium(me.family_id) THEN
		RAISE EXCEPTION 'Famílias no plano gratuito incluem % responsáveis. Para adicionar mais (avós, babá, etc.), ative o Premium.', free_seats
			USING ERRCODE = 'check_violation';
	END IF;

	IF taken >= max_seats THEN
		RAISE EXCEPTION 'Esta família já atingiu o limite de % responsáveis (contando convites pendentes).', max_seats
			USING ERRCODE = 'check_violation';
	END IF;

	INSERT INTO public.profiles (user_id, full_name, role_id, email, family_id, is_admin, color_slot)
	VALUES (NULL, clean_name, p_role_id, NULL, me.family_id, false,
	        public.next_free_color_slot(me.family_id))
	RETURNING id INTO new_id;

	INSERT INTO public.account_logs (family_id, actor_profile_id, target_profile_id, action, new_value)
	VALUES (me.family_id, me.id, new_id, 'pending_member_added', clean_name);

	IF clean_email IS NOT NULL THEN
		SELECT * INTO inv FROM public.create_invitation(clean_email, p_role_id, new_id);
		RETURN QUERY SELECT new_id, inv.invitation_id, inv.token, inv.expires_at;
	ELSE
		RETURN QUERY SELECT new_id, NULL::bigint, NULL::uuid, NULL::timestamp with time zone;
	END IF;
END;
$$;

ALTER FUNCTION public.add_pending_member(text, bigint, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.add_pending_member(text, bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_pending_member(text, bigint, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.add_pending_member(text, bigint, text) IS
	'F-56: creates a PENDING member (profile with no auth user) from the admin''s description — name, role; colour by the system. Holds a seat and a colour. With p_email, issues the invitation in the same transaction.';

-- ── 5c. remove_pending_member — a typo must not hold a seat forever ─────────
-- Admin only, placeholder only. Without history the row is DELETED (the
-- invitation, if any, is revoked; its profile_id nulls through the FK). With
-- history — a day ever planned for them, an action in the audit trail — the
-- row becomes an S-11 tombstone: future days cleared (today included, the
-- S-11 decision), left_at stamped, name kept on the past. Either way the seat
-- and the colour free up.

CREATE OR REPLACE FUNCTION public.remove_pending_member(p_profile_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
	me          public.profiles%ROWTYPE;
	target      public.profiles%ROWTYPE;
	today       date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	has_history boolean;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();

	IF me.id IS NULL OR NOT me.is_admin THEN
		RAISE EXCEPTION 'Somente administradores da família podem remover responsáveis.'
			USING ERRCODE = 'check_violation';
	END IF;

	SELECT * INTO target FROM public.profiles
	WHERE id = p_profile_id AND family_id = me.family_id;
	IF target.id IS NULL THEN
		RAISE EXCEPTION 'Perfil não encontrado na sua família.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF target.user_id IS NOT NULL OR target.left_at IS NOT NULL THEN
		RAISE EXCEPTION 'Só é possível remover por aqui um responsável que ainda não entrou no aplicativo.'
			USING ERRCODE = 'check_violation';
	END IF;

	UPDATE public.family_invitations fi
	SET revoked_at = timezone('utc', now())
	WHERE fi.profile_id = target.id
	  AND fi.accepted_at IS NULL AND fi.revoked_at IS NULL;

	has_history := EXISTS (SELECT 1 FROM public.care_schedules
	                       WHERE scheduled_parent_id = target.id OR actual_parent_id = target.id)
	            OR EXISTS (SELECT 1 FROM public.activity_logs WHERE performed_by_id = target.id)
	            OR EXISTS (SELECT 1 FROM public.swap_requests
	                       WHERE target.id IN (requesting_profile_id, target_profile_id,
	                                           proposed_actual_parent_id, previous_actual_parent_id));

	INSERT INTO public.account_logs (family_id, actor_profile_id, target_profile_id, action, old_value)
	VALUES (me.family_id, me.id, target.id, 'pending_member_removed', target.full_name);

	-- S-11: the day-protection trigger lets the controlled cleanup through.
	PERFORM set_config('app.deletion_context', 'on', true);

	IF NOT has_history THEN
		DELETE FROM public.notifications WHERE recipient_profile_id = target.id;
		DELETE FROM public.profiles WHERE id = target.id;
		RETURN;
	END IF;

	-- Clear their FUTURE days — today included (the S-11 decision).
	UPDATE public.care_schedules
	SET actual_parent_id = NULL, updated_at = timezone('utc', now())
	WHERE family_id = me.family_id AND schedule_date >= today
	  AND actual_parent_id = target.id AND scheduled_parent_id <> target.id;

	DELETE FROM public.care_schedules
	WHERE family_id = me.family_id AND schedule_date >= today
	  AND scheduled_parent_id = target.id;

	-- Tombstone: name stays on the past, seat and colour free up. No
	-- deletion_scheduled_for — there is no account to purge.
	UPDATE public.profiles
	SET left_at = timezone('utc', now())
	WHERE id = target.id;
END;
$$;

ALTER FUNCTION public.remove_pending_member(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.remove_pending_member(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_pending_member(bigint) TO authenticated, service_role;

COMMENT ON FUNCTION public.remove_pending_member(bigint) IS
	'F-56: admin removes a PENDING member. Deleted outright when nothing references it; otherwise an S-11 tombstone (future days cleared, left_at stamped, name kept on history). Open invitations for it are revoked.';

-- ── 6a. handle_new_user — claiming a placeholder is an UPDATE ───────────────
-- Body VERBATIM from 20260827140000 (F-57 fix). Changes: the invitee branch
-- gains the placeholder claim (before the seat caps — the placeholder already
-- holds the seat), and the legacy caps read seat_count() instead of
-- active_member_count() so a pending member counts against a legacy invite.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	meta_name    text;
	meta_role    text;
	meta_token   text;
	meta_family  text;
	meta_policy  text;
	inv          public.family_invitations%ROWTYPE;
	fam_id       bigint;
	new_role_id  bigint;
	admin_flag   boolean;
	max_seats    int := public.setting_int('max_caregivers', 4);
	free_seats   int := public.setting_int('free_caregivers', 2);
BEGIN
	-- Idempotency: never duplicate a profile (e.g. trigger re-run).
	IF EXISTS (SELECT 1 FROM public.profiles WHERE user_id = NEW.id) THEN
		RETURN NEW;
	END IF;

	meta_name   := NULLIF(trim(NEW.raw_user_meta_data ->> 'full_name'), '');
	meta_role   := NULLIF(trim(NEW.raw_user_meta_data ->> 'role'), '');
	meta_token  := NULLIF(trim(NEW.raw_user_meta_data ->> 'invite_token'), '');
	meta_family := NULLIF(trim(NEW.raw_user_meta_data ->> 'family_name'), '');
	meta_policy := NULLIF(trim(NEW.raw_user_meta_data ->> 'policy_version'), '');

	-- F-57: a sign-up that carries neither an invite token nor a role did not
	-- come through our forms (they always send the metadata) — it is an OAuth
	-- sign-up, whose raw_user_meta_data is the PROVIDER's. Raising here would
	-- abort the auth.users INSERT and the account would never exist, so the
	-- profile is DEFERRED: the client routes the profile-less session to
	-- onboarding, and the profile is created by complete_oauth_onboarding
	-- (founder) or claim-invitation (invitee). Deliberately NOT keyed on
	-- raw_app_meta_data->>'provider': the Admin API cannot forge it, so a
	-- provider-based rule is one the db gate can never exercise.
	IF meta_token IS NULL AND meta_role IS NULL THEN
		RETURN NEW;
	END IF;

	IF meta_token IS NOT NULL THEN
		-- INVITEE: token must be valid, pending and issued for this e-mail.
		-- (a malformed token must fail with the friendly message, not a cast error)
		BEGIN
			SELECT * INTO inv
			FROM public.family_invitations
			WHERE token = meta_token::uuid
			  AND accepted_at IS NULL
			  AND revoked_at  IS NULL
			  AND expires_at  > timezone('utc', now())
			  AND lower(email) = lower(NEW.email);
		EXCEPTION WHEN invalid_text_representation THEN
			inv := NULL;
		END;

		IF inv.id IS NULL THEN
			RAISE EXCEPTION 'Convite inválido, expirado ou emitido para outro e-mail.'
				USING ERRCODE = 'check_violation';
		END IF;

		-- F-56: the invitation names a PLACEHOLDER — attach this auth user to
		-- that row instead of creating one. The name the person typed wins over
		-- the admin's description; role and colour stay (they are the seat).
		-- No seat gate: the placeholder already holds it (add-only + grandfather).
		IF inv.profile_id IS NOT NULL THEN
			UPDATE public.profiles p
			SET user_id                = NEW.id,
			    email                  = NEW.email,
			    full_name              = COALESCE(meta_name, p.full_name),
			    consent_accepted_at    = CASE WHEN meta_policy IS NOT NULL THEN timezone('utc', now()) END,
			    consent_policy_version = meta_policy
			WHERE p.id = inv.profile_id
			  AND p.family_id = inv.family_id
			  AND p.user_id IS NULL
			  AND p.left_at IS NULL;

			IF NOT FOUND THEN
				RAISE EXCEPTION 'Convite inválido, expirado ou emitido para outro e-mail.'
					USING ERRCODE = 'check_violation';
			END IF;

			UPDATE public.family_invitations
			SET accepted_at = timezone('utc', now())
			WHERE id = inv.id;

			INSERT INTO public.account_logs (family_id, actor_profile_id, target_profile_id, action, new_value)
			VALUES (inv.family_id, inv.profile_id, inv.profile_id, 'pending_member_claimed',
			        COALESCE(meta_name, split_part(NEW.email, '@', 1)));

			RETURN NEW;
		END IF;
	END IF;

	-- Fallback: e-mail local part (metadata should always carry the name).
	IF meta_name IS NULL THEN
		meta_name := split_part(NEW.email, '@', 1);
	END IF;

	IF meta_token IS NOT NULL THEN
		-- The family may have completed meanwhile (parallel invites racing).
		-- F-56: seat_count — a pending member holds a seat.
		IF public.seat_count(inv.family_id) >= max_seats THEN
			RAISE EXCEPTION 'Esta família já atingiu o limite de % responsáveis.', max_seats
				USING ERRCODE = 'check_violation';
		END IF;

		-- F-37 (T-41: free_caregivers from settings) backstop — a caregiver beyond
		-- the free tier joining a free family needs Premium. Primary guard is
		-- create_invitation; this covers the trial-expired / parallel-invite race.
		IF public.seat_count(inv.family_id) >= free_seats
		   AND NOT public.is_premium(inv.family_id) THEN
			RAISE EXCEPTION 'Esta família já atingiu o limite de % responsáveis do plano gratuito. Peça ao administrador para ativar o Premium e liberar novos cuidadores.', free_seats
				USING ERRCODE = 'check_violation';
		END IF;

		fam_id      := inv.family_id;
		new_role_id := inv.role_id;
		admin_flag  := false;

		UPDATE public.family_invitations
		SET accepted_at = timezone('utc', now())
		WHERE id = inv.id;
	ELSE
		-- FOUNDER: creates the family and becomes its admin (F-14 decision).
		IF meta_role IS NULL THEN
			RAISE EXCEPTION 'Selecione o seu papel para criar a conta.'
				USING ERRCODE = 'check_violation';
		END IF;

		-- F-27: catalog-driven lookup — the client sends the canonical slug;
		-- the PT-BR label is accepted as a fallback vocabulary.
		-- F-41: built-ins only — a founder has no family, so no custom row
		-- (from ANY family) may resolve here.
		SELECT id INTO new_role_id
		FROM public.roles
		WHERE family_id IS NULL
		  AND (lower(trim(role)) = lower(meta_role)
		    OR lower(trim(label_pt)) = lower(meta_role))
		ORDER BY id
		LIMIT 1;
		IF new_role_id IS NULL THEN
			RAISE EXCEPTION 'Papel inválido: %.', meta_role
				USING ERRCODE = 'check_violation';
		END IF;

		-- Family name chosen by the founder; neutral fallback for safety
		-- (the register form makes the field required).
		INSERT INTO public.families (name)
		VALUES (COALESCE(meta_family, 'Família ' || meta_name))
		RETURNING id INTO fam_id;

		admin_flag := true;
	END IF;

	-- S-11 QA: the color slot is assigned at join and belongs to the person —
	-- founder = 1; invitee = lowest slot free among the ACTIVE members (which
	-- naturally reuses a departed member's freed color).
	-- S-13: the LGPD consent (checkbox gated sign-up) is recorded with the
	-- policy version accepted, so it is demonstrable later (art. 8 §1).
	INSERT INTO public.profiles (user_id, full_name, role_id, email, family_id, is_admin, color_slot,
	                             consent_accepted_at, consent_policy_version)
	VALUES (NEW.id, meta_name, new_role_id, NEW.email, fam_id, admin_flag,
	        CASE WHEN admin_flag THEN 1 ELSE public.next_free_color_slot(fam_id) END,
	        CASE WHEN meta_policy IS NOT NULL THEN timezone('utc', now()) END,
	        meta_policy);

	RETURN NEW;
END;
$$;

-- ── 6b. claim_invitation_for_user — the OAuth twin claims the placeholder ───
-- Body VERBATIM from 20260827120000 (F-57). Same two changes as the trigger:
-- the placeholder claim after the S-11 migration step and before the caps,
-- and seat_count() in the legacy caps.

CREATE OR REPLACE FUNCTION public.claim_invitation_for_user(
	p_user_id           uuid,
	p_full_name         text,
	p_token             text,
	p_policy_version    text,
	p_confirm_migration boolean DEFAULT false
)
RETURNS TABLE (auth_uid uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	user_email  text;
	expected    text;
	the_name    text;
	inv         public.family_invitations%ROWTYPE;
	prev_family text;
	max_seats   int := public.setting_int('max_caregivers', 4);
	free_seats  int := public.setting_int('free_caregivers', 2);
BEGIN
	PERFORM pg_advisory_xact_lock(hashtext(p_user_id::text));

	SELECT u.email INTO user_email FROM auth.users u WHERE u.id = p_user_id;
	IF user_email IS NULL THEN
		RAISE EXCEPTION 'Sessão não autenticada.' USING ERRCODE = '42501';
	END IF;

	IF EXISTS (SELECT 1 FROM public.profiles p
	           WHERE p.user_id = p_user_id AND p.left_at IS NULL) THEN
		RAISE EXCEPTION 'Esta conta já está vinculada a uma família.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- S-15 posture — same validation as complete_oauth_onboarding.
	expected := public.setting_text('policy.current_version', NULL::text);
	IF expected IS NULL THEN
		RAISE EXCEPTION 'Configuração policy.current_version ausente — aceite não pode ser registrado.'
			USING ERRCODE = 'P0002';
	END IF;
	IF p_policy_version IS DISTINCT FROM expected THEN
		RAISE EXCEPTION 'Versão da política desatualizada (enviada: %, vigente: %). Atualize o aplicativo.',
			coalesce(p_policy_version, '(nula)'), expected USING ERRCODE = '22023';
	END IF;

	-- Token validation — verbatim mirror of the trigger's invitee branch.
	BEGIN
		SELECT * INTO inv
		FROM public.family_invitations i
		WHERE i.token = p_token::uuid
		  AND i.accepted_at IS NULL
		  AND i.revoked_at  IS NULL
		  AND i.expires_at  > timezone('utc', now())
		  AND lower(i.email) = lower(user_email);
	EXCEPTION WHEN invalid_text_representation THEN
		inv := NULL;
	END;

	IF inv.id IS NULL THEN
		RAISE EXCEPTION 'Convite inválido, expirado ou emitido para outro e-mail.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- S-11: a departed previous-family registration must be consciously erased
	-- before joining the new family (1 e-mail = 1 family until F-30).
	prev_family := public.departed_member_family(user_email);
	IF prev_family IS NOT NULL THEN
		IF NOT p_confirm_migration THEN
			RAISE EXCEPTION 'MIGRATION_REQUIRED:%', prev_family
				USING ERRCODE = 'check_violation';
		END IF;

		-- Same teardown register-invitee runs, but the caller's own auth user
		-- SURVIVES (it is the session making this claim): their tombstoned
		-- profile is detached instead, and only other freed users are handed
		-- back for GoTrue deletion (whole-family purge can free several).
		RETURN QUERY
			SELECT purged.auth_uid
			FROM public.purge_departed_member_by_email(user_email) AS purged
			WHERE purged.auth_uid IS DISTINCT FROM p_user_id;

		UPDATE public.profiles p
		SET user_id = NULL
		WHERE p.user_id = p_user_id AND p.left_at IS NOT NULL;
	END IF;

	the_name := NULLIF(trim(p_full_name), '');

	-- F-56: the invitation names a PLACEHOLDER — attach this auth user to it.
	-- Same rules as the trigger: typed name wins, role and colour stay, no
	-- seat gate (the placeholder holds the seat).
	IF inv.profile_id IS NOT NULL THEN
		UPDATE public.profiles p
		SET user_id                = p_user_id,
		    email                  = user_email,
		    full_name              = COALESCE(the_name, p.full_name),
		    consent_accepted_at    = timezone('utc', now()),
		    consent_policy_version = expected
		WHERE p.id = inv.profile_id
		  AND p.family_id = inv.family_id
		  AND p.user_id IS NULL
		  AND p.left_at IS NULL;

		IF NOT FOUND THEN
			RAISE EXCEPTION 'Convite inválido, expirado ou emitido para outro e-mail.'
				USING ERRCODE = 'check_violation';
		END IF;

		UPDATE public.family_invitations i
		SET accepted_at = timezone('utc', now())
		WHERE i.id = inv.id;

		INSERT INTO public.account_logs (family_id, actor_profile_id, target_profile_id, action, new_value)
		VALUES (inv.family_id, inv.profile_id, inv.profile_id, 'pending_member_claimed',
		        COALESCE(the_name, split_part(user_email, '@', 1)));

		RETURN;
	END IF;

	-- Seat caps — verbatim mirror of the trigger's invitee branch.
	-- F-56: seat_count — a pending member holds a seat.
	IF public.seat_count(inv.family_id) >= max_seats THEN
		RAISE EXCEPTION 'Esta família já atingiu o limite de % responsáveis.', max_seats
			USING ERRCODE = 'check_violation';
	END IF;

	IF public.seat_count(inv.family_id) >= free_seats
	   AND NOT public.is_premium(inv.family_id) THEN
		RAISE EXCEPTION 'Esta família já atingiu o limite de % responsáveis do plano gratuito. Peça ao administrador para ativar o Premium e liberar novos cuidadores.', free_seats
			USING ERRCODE = 'check_violation';
	END IF;

	UPDATE public.family_invitations i
	SET accepted_at = timezone('utc', now())
	WHERE i.id = inv.id;

	the_name := COALESCE(the_name, split_part(user_email, '@', 1));

	INSERT INTO public.profiles (user_id, full_name, role_id, email, family_id, is_admin, color_slot,
	                             consent_accepted_at, consent_policy_version)
	VALUES (p_user_id, the_name, inv.role_id, user_email, inv.family_id, false,
	        public.next_free_color_slot(inv.family_id),
	        timezone('utc', now()), expected);

	RETURN;
END;
$$;

-- ── 7. enforce_swap_counterpart — a swap needs two live accounts ─────────────
-- Until now NOTHING checked the counterpart's state: the INSERT policy only
-- asks that the target belong to the family. A pending member has nobody to
-- approve with; a departed one has nobody at all. Both refused here, with the
-- sentence the day sheet will show, so the rule lives in the database and the
-- client only mirrors it (§2).

CREATE OR REPLACE FUNCTION public.enforce_swap_counterpart()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	r record;
BEGIN
	FOR r IN
		SELECT p.user_id, p.left_at
		FROM public.profiles p
		WHERE p.id IN (NEW.target_profile_id, NEW.proposed_actual_parent_id)
	LOOP
		IF r.left_at IS NOT NULL THEN
			RAISE EXCEPTION 'Este responsável saiu da família e não pode participar de uma troca.'
				USING ERRCODE = 'check_violation';
		END IF;
		IF r.user_id IS NULL THEN
			RAISE EXCEPTION 'Este responsável ainda não entrou no aplicativo — a troca fica disponível quando a conta for criada.'
				USING ERRCODE = 'check_violation';
		END IF;
	END LOOP;
	RETURN NEW;
END;
$$;

ALTER FUNCTION public.enforce_swap_counterpart() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.enforce_swap_counterpart() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_b_enforce_swap_counterpart ON public.swap_requests;
CREATE TRIGGER trigger_b_enforce_swap_counterpart
	BEFORE INSERT ON public.swap_requests
	FOR EACH ROW
	EXECUTE FUNCTION public.enforce_swap_counterpart();

COMMENT ON FUNCTION public.enforce_swap_counterpart() IS
	'F-56: the target and the proposed parent of a swap must be ACTIVE members (auth user present, not departed). A pending member cannot approve; a departed one cannot participate.';

-- ── 8. auto_approve_expired — the F-28 fan-out skips accountless profiles ───
-- Body VERBATIM from 20260807000000 (U-24); ONLY the swap_family_info SELECT
-- gains `p.left_at IS NULL AND p.user_id IS NOT NULL`. A pending member has
-- no session to read a notification in, and a departed one is out.

CREATE OR REPLACE FUNCTION public.auto_approve_expired(p_env_prefix text DEFAULT '')
RETURNS TABLE (swap_request_id bigint, email_type text)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    rec           record;
    tz            constant text := 'America/Sao_Paulo';
    expiry        timestamptz;
    d             text;
    d_iso         text;   -- U-24: ISO for params; `d` stays PT-BR in the stored sentence
    proposed_name text;
    fanout_msg    text;
    fanout_kind   text;
BEGIN
    -- ── 24h reminders: expired between 24h and 48h ago, not yet reminded ──
    FOR rec IN
        SELECT * FROM public.swap_requests
        WHERE status IN ('pending', 'revert_pending') AND reminder_sent_at IS NULL
    LOOP
        expiry := (rec.schedule_date + COALESCE(rec.proposed_handoff_time, '00:00'::time)) AT TIME ZONE tz;
        IF now() >= expiry + interval '24 hours' AND now() < expiry + interval '48 hours' THEN
            d := to_char(rec.schedule_date, 'DD/MM');
            d_iso := to_char(rec.schedule_date, 'YYYY-MM-DD');
            INSERT INTO public.notifications (recipient_profile_id, type, title, message, params, swap_request_id, is_read, created_at)
            VALUES (
                rec.target_profile_id,
                'auto_reminder',
                p_env_prefix || '⏰ Solicitação pendente expira em 24h',
                'A solicitação do dia ' || d || ' será aprovada automaticamente em 24h se não houver resposta.',
                jsonb_build_object('date', d_iso),
                rec.id, false, now()
            );
            UPDATE public.swap_requests SET reminder_sent_at = now() WHERE id = rec.id;

            swap_request_id := rec.id; email_type := 'reminder'; RETURN NEXT;
        END IF;
    END LOOP;

    -- ── Auto-approve: expired more than 48h ago ──────────────────────────
    FOR rec IN
        SELECT * FROM public.swap_requests
        WHERE status IN ('pending', 'revert_pending')
    LOOP
        expiry := (rec.schedule_date + COALESCE(rec.proposed_handoff_time, '00:00'::time)) AT TIME ZONE tz;
        IF now() >= expiry + interval '48 hours' THEN
            d := to_char(rec.schedule_date, 'DD/MM');
            d_iso := to_char(rec.schedule_date, 'YYYY-MM-DD');

            -- The person the day lands on: the proposed parent (for a revert
            -- request that is the restored planned responsible).
            SELECT full_name INTO proposed_name
            FROM public.profiles WHERE id = rec.proposed_actual_parent_id;

            IF rec.status = 'pending' THEN
                IF rec.schedule_id IS NOT NULL THEN
                    UPDATE public.care_schedules
                    SET actual_parent_id = rec.proposed_actual_parent_id,
                        handoff_time     = rec.proposed_handoff_time,
                        updated_at       = timezone('utc', now())
                    WHERE id = rec.schedule_id;
                END IF;
                UPDATE public.swap_requests SET status = 'approved', resolved_by = 'system' WHERE id = rec.id;

                fanout_msg := COALESCE(proposed_name, 'Outro responsável')
                    || ' ficará com a criança no dia ' || d
                    || ' (troca aprovada automaticamente após 48h sem resposta).';
                fanout_kind := 'auto_swap';
            ELSE
                -- F-47: the requester's decision about the day observation.
                PERFORM public.restore_pre_edit_state(rec.schedule_id, rec.pre_edit_log_id, rec.revert_notes);
                UPDATE public.swap_requests SET status = 'revert_approved', resolved_by = 'system' WHERE id = rec.id;

                fanout_msg := 'A troca do dia ' || d || ' foi revertida automaticamente — '
                    || COALESCE(proposed_name, 'o responsável planejado')
                    || ' volta a ficar com a criança.';
                fanout_kind := 'auto_revert';
            END IF;

            -- Notify the requester and the approver (distinct copy).
            -- U-13: same `type`, two different wordings — so `role` is the
            -- discriminator the renderer branches on. Without it the reader
            -- would get the other party's sentence.
            INSERT INTO public.notifications (recipient_profile_id, type, title, message, params, swap_request_id, is_read, created_at)
            VALUES (
                rec.requesting_profile_id, 'auto_approved',
                p_env_prefix || '✅ Solicitação aprovada automaticamente',
                'A solicitação do dia ' || d || ' foi aprovada automaticamente após 48h sem resposta.',
                jsonb_build_object('date', d_iso, 'role', 'requester'),
                rec.id, false, now()
            );
            INSERT INTO public.notifications (recipient_profile_id, type, title, message, params, swap_request_id, is_read, created_at)
            VALUES (
                rec.target_profile_id, 'auto_approved',
                p_env_prefix || '✅ Solicitação aprovada automaticamente',
                'A solicitação do dia ' || d || ' foi aprovada automaticamente. Você não respondeu dentro do prazo.',
                jsonb_build_object('date', d_iso, 'role', 'approver'),
                rec.id, false, now()
            );

            -- F-28: family-info fan-out to uninvolved caregivers.
            -- U-13: `name` is USER DATA (a caregiver's own name) and is passed
            -- through untranslated, exactly like the role catalogue's custom
            -- roles. `kind` tells the renderer swap from revert.
            -- F-56: only caregivers with an account — a pending member has no
            -- session to read it in, and a departed one is out.
            INSERT INTO public.notifications (recipient_profile_id, type, title, message, params, swap_request_id, is_read, created_at)
            SELECT p.id, 'swap_family_info',
                   p_env_prefix || '📅 Calendário atualizado',
                   fanout_msg,
                   jsonb_build_object('date', d_iso, 'kind', fanout_kind, 'name', proposed_name),
                   rec.id, false, now()
            FROM public.profiles p
            WHERE p.family_id = rec.family_id
              AND p.left_at IS NULL AND p.user_id IS NOT NULL
              AND p.id NOT IN (rec.requesting_profile_id, rec.target_profile_id);

            swap_request_id := rec.id; email_type := 'auto_approved'; RETURN NEXT;
        END IF;
    END LOOP;
END;
$$;

-- ── 9. set_member_admin — a placeholder cannot hold the admin bit ───────────
-- Body VERBATIM from 20260718113000 (S-10) plus the pending refusal. The
-- ">= 1 admin" invariant counts admin rows; a placeholder admin would satisfy
-- it with nobody behind the bit.

CREATE OR REPLACE FUNCTION public.set_member_admin(p_profile_id bigint, p_is_admin boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me public.profiles%ROWTYPE;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();

	IF me.id IS NULL OR NOT me.is_admin THEN
		RAISE EXCEPTION 'Somente administradores da família podem alterar permissões.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- S-10: admin grants/revokes require a fresh password confirmation.
	IF NOT public.is_elevated() THEN
		RAISE EXCEPTION 'ELEVATION_REQUIRED: Confirme sua senha para alterar permissões de administrador.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	-- F-56: no account, no admin bit.
	IF p_is_admin AND EXISTS (SELECT 1 FROM public.profiles
	                          WHERE id = p_profile_id AND family_id = me.family_id
	                            AND user_id IS NULL AND left_at IS NULL) THEN
		RAISE EXCEPTION 'Um responsável que ainda não entrou no aplicativo não pode ser administrador.'
			USING ERRCODE = 'check_violation';
	END IF;

	UPDATE public.profiles
	SET is_admin = p_is_admin
	WHERE id = p_profile_id AND family_id = me.family_id;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'Perfil não encontrado na sua família.'
			USING ERRCODE = 'check_violation';
	END IF;
END;
$$;

-- ── 10. get_invite_info — the invitee sees the name they were given ─────────
-- Body from the baseline plus `invitee_name` (NULL on a legacy invitation).
-- A return-type change needs DROP + CREATE, so the grants are re-issued: anon
-- on purpose — the visitor has no session yet.

DROP FUNCTION IF EXISTS public.get_invite_info(uuid);

CREATE FUNCTION public.get_invite_info(p_token uuid)
RETURNS TABLE (family_name text, inviter_name text, invited_email text, role_name text, invitee_name text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
	SELECT f.name, p.full_name, i.email, r.role, pm.full_name
	FROM public.family_invitations i
	JOIN public.families f ON f.id = i.family_id
	JOIN public.profiles p ON p.id = i.invited_by
	JOIN public.roles    r ON r.id = i.role_id
	LEFT JOIN public.profiles pm ON pm.id = i.profile_id
	WHERE i.token = p_token
	  AND i.accepted_at IS NULL
	  AND i.revoked_at  IS NULL
	  AND i.expires_at  > timezone('utc', now());
$$;

ALTER FUNCTION public.get_invite_info(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_invite_info(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_invite_info(uuid) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_invite_info(uuid) IS
	'Anonymous read of a PENDING invitation (unknown, accepted, revoked and expired tokens are indistinguishable). F-56: invitee_name is the name the admin gave the placeholder, to prefill the sign-up form.';

-- ── 11. audit_profile_account_changes — the claim is not an e-mail change ───
-- Body VERBATIM from 20260719120000 (S-11); ONLY the e-mail branch gains
-- `OLD.email IS NOT NULL`. A placeholder has no e-mail, so the claim would
-- otherwise write an 'email_changed' row from nothing — the claim already
-- writes its own 'pending_member_claimed' row. A name the person typed over
-- the admin's description still logs as 'name_changed': that IS a change.

CREATE OR REPLACE FUNCTION public.audit_profile_account_changes()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	actor bigint;
BEGIN
	-- S-11: erasure cleanup is not an auditable account edit.
	IF current_setting('app.deletion_context', true) = 'on' THEN
		RETURN NEW;
	END IF;

	SELECT id INTO actor FROM public.profiles WHERE user_id = auth.uid();

	IF NEW.is_admin IS DISTINCT FROM OLD.is_admin THEN
		INSERT INTO public.account_logs (family_id, actor_profile_id, target_profile_id, action, old_value, new_value)
		VALUES (OLD.family_id, actor, OLD.id,
		        CASE WHEN NEW.is_admin THEN 'admin_granted' ELSE 'admin_revoked' END,
		        OLD.is_admin::text, NEW.is_admin::text);
	END IF;

	IF NEW.role_id IS DISTINCT FROM OLD.role_id THEN
		INSERT INTO public.account_logs (family_id, actor_profile_id, target_profile_id, action, old_value, new_value)
		VALUES (OLD.family_id, actor, OLD.id, 'role_changed',
		        (SELECT role FROM public.roles WHERE id = OLD.role_id),
		        (SELECT role FROM public.roles WHERE id = NEW.role_id));
	END IF;

	IF NEW.full_name IS DISTINCT FROM OLD.full_name THEN
		INSERT INTO public.account_logs (family_id, actor_profile_id, target_profile_id, action, old_value, new_value)
		VALUES (OLD.family_id, actor, OLD.id, 'name_changed', OLD.full_name, NEW.full_name);
	END IF;

	-- F-56: a placeholder's first e-mail is the claim, logged as such.
	IF NEW.email IS DISTINCT FROM OLD.email AND OLD.email IS NOT NULL THEN
		INSERT INTO public.account_logs (family_id, actor_profile_id, target_profile_id, action, old_value, new_value)
		VALUES (OLD.family_id, COALESCE(actor, OLD.id), OLD.id, 'email_changed', OLD.email, NEW.email);
	END IF;

	RETURN NEW;
END;
$$;
