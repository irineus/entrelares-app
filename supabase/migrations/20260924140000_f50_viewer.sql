-- =============================================================================
-- F-50 (PR 1 of 2) — the Visualizador: a member who sees the plan and touches
-- nothing
--
-- Decisions locked by the owner (24/09/2026, F-50 Notes + card body):
--   · "Visualizador"/"Viewer" — a second membership category on `profiles`
--     (`membership_type` 'full' | 'viewer'), orthogonal to is_admin and role.
--   · OUTSIDE the F-37 caregiver pool, with its own caps: `free_viewers` 1
--     (0–4) and `max_viewers` 4 (1–10) — T-84, category `freemium` like the
--     caregiver caps; free ≤ max in T-80's DEFERRED cross-check.
--   · Never a day's planned or real parent, never a swap party, never admin,
--     no colour slot. It WRITES NOTHING: every family-plan table refuses a
--     viewer caller (one guard, attached to each table — not a check copied
--     into each RPC, so a future RPC cannot forget it).
--   · Reads the plan, the agenda and (F-35) the chat; does NOT read the swap
--     negotiation: `swap_requests` is invisible to a viewer (request message,
--     approval note, rejection reason — the two parties' words). The PDF a
--     viewer exports is built from what it can read, so it carries none of it.
--   · Notifications: in-app + push, only the INFORMATIVE ones (a calendar
--     change, the plan ending, the day's aviso, the agenda it is told about);
--     never e-mail (send-account-email skips viewers).
--   · Promotion viewer → full exists (admin, needs a caregiver seat AND a free
--     colour); demotion full → viewer is forbidden by design (F-28 reasoning).
--   · Exit is a complete delete, not a tombstone: nothing in the past refers
--     to a viewer. Guarded — if anything ever does, the S-11 tombstone path.
--   · Dark in production: `feature.viewers` seeded false; with it off no
--     viewer invitation and no promotion is accepted.
-- =============================================================================


-- ── 1. The keys (T-84 catalogue) ─────────────────────────────────────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, min_value, max_value, help)
VALUES
	('feature.viewers', 'false', 'bool', 'features',
	 'Liga o Visualizador (F-50): membro que só acompanha o plano. Desligado, o servidor recusa convites e promoções.',
	 true, 'flag', 'critical', NULL, NULL,
	 jsonb_build_object(
		'controls', 'Se create_viewer_invitation e promote_member_to_full aceitam chamadas. Visualizadores que já existem continuam lendo; ninguém novo entra como visualizador.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Ligado: o administrador convida visualizadores (avó, babá, advogado) e pode promovê-los a responsável.',
		'if_decreased', 'Desligado: o convite de visualizador some do app e o servidor o recusa; quem já é visualizador segue só lendo.',
		'takes_effect', 'Servidor na próxima chamada; app na próxima abertura da Família.',
		'caveats', 'Produção nasce desligada: o S-22 liga junto com a política que descreve o visualizador.')),
	('free_viewers', '1', 'int', 'freemium',
	 'Visualizadores incluídos numa família sem Premium (fora do limite de responsáveis).',
	 true, 'count', 'sensitive', 0, 4,
	 jsonb_build_object(
		'controls', 'Quantos visualizadores (e convites de visualizador abertos) uma família gratuita pode ter. Não consome as cadeiras de responsável nem as cores.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Mais visualizadores no gratuito; menos motivo para o Premium.',
		'if_decreased', 'Famílias acima do número novo NÃO perdem ninguém; só convites novos são recusados. Com 0, visualizador é só do Premium.',
		'takes_effect', 'Servidor no próximo convite ou cadastro; app na próxima abertura da Família.',
		'caveats', 'Precisa ser no máximo max_viewers (regra entre chaves).')),
	('max_viewers', '4', 'int', 'freemium',
	 'Teto de visualizadores por família, em qualquer plano.',
	 true, 'count', 'sensitive', 1, 10,
	 jsonb_build_object(
		'controls', 'O máximo de visualizadores (e convites de visualizador abertos) de uma família, Premium inclusive.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Mais gente lendo o plano da família — cada uma recebe as notificações informativas no app e no celular.',
		'if_decreased', 'Famílias acima do número novo NÃO perdem ninguém; só convites novos são recusados.',
		'takes_effect', 'Servidor no próximo convite ou cadastro; app na próxima abertura da Família.',
		'caveats', 'Precisa ser no mínimo free_viewers (regra entre chaves).'))
ON CONFLICT (key) DO NOTHING;


-- ── 2. The category ──────────────────────────────────────────────────────────

ALTER TABLE public.profiles
	ADD COLUMN IF NOT EXISTS membership_type text NOT NULL DEFAULT 'full'
		CHECK (membership_type IN ('full', 'viewer'));

-- A viewer never administers and never holds a colour. The guard below says
-- it in Portuguese first; these are the floor for every other writer.
ALTER TABLE public.profiles
	ADD CONSTRAINT profiles_viewer_not_admin CHECK (membership_type = 'full' OR NOT is_admin),
	ADD CONSTRAINT profiles_viewer_no_colour CHECK (membership_type = 'full' OR color_slot IS NULL);

ALTER TABLE public.family_invitations
	ADD COLUMN IF NOT EXISTS member_type text NOT NULL DEFAULT 'full'
		CHECK (member_type IN ('full', 'viewer'));

-- A viewer invitation never names a placeholder (placeholders are caregivers).
ALTER TABLE public.family_invitations
	ADD CONSTRAINT family_invitations_viewer_no_placeholder
		CHECK (member_type = 'full' OR profile_id IS NULL);

CREATE OR REPLACE FUNCTION public.is_viewer_caller()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
	SELECT EXISTS (
		SELECT 1 FROM public.profiles
		WHERE user_id = auth.uid() AND membership_type = 'viewer' AND left_at IS NULL);
$$;

ALTER FUNCTION public.is_viewer_caller() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.is_viewer_caller() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_viewer_caller() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.viewer_count(p_family_id bigint)
RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
	-- Viewers in the family plus open viewer invitations: the viewer caps'
	-- arithmetic, the same shape as the caregivers'.
	SELECT (SELECT count(*)::int FROM public.profiles
	        WHERE family_id = p_family_id AND membership_type = 'viewer' AND left_at IS NULL)
	     + (SELECT count(*)::int FROM public.family_invitations
	        WHERE family_id = p_family_id AND member_type = 'viewer'
	          AND accepted_at IS NULL AND revoked_at IS NULL
	          AND expires_at > timezone('utc', now()));
$$;

ALTER FUNCTION public.viewer_count(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.viewer_count(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.viewer_count(bigint) TO authenticated, service_role;


-- ── 3. The seat helpers count caregivers only ────────────────────────────────

CREATE OR REPLACE FUNCTION public.seat_count(p_family_id bigint)
RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
	SELECT count(*)::int FROM public.profiles
	WHERE family_id = p_family_id
	  AND left_at IS NULL
	  AND membership_type = 'full';
$$;

COMMENT ON FUNCTION public.seat_count(bigint) IS
	'F-56: seats taken by ACTIVE and PENDING caregivers (left_at NULL, any user_id). F-50: viewers hold no caregiver seat — they count in viewer_count(). The F-37 gates use this plus the open caregiver invitations without a placeholder.';

CREATE OR REPLACE FUNCTION public.active_member_count(p_family_id bigint)
RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
	-- F-50: the caregivers with an account. A viewer is never the last member
	-- standing, never a successor and never a voter in a family deletion.
	SELECT count(*)::int FROM public.profiles
	WHERE family_id = p_family_id
	  AND user_id IS NOT NULL
	  AND left_at IS NULL
	  AND membership_type = 'full';
$$;


-- ── 4. The profile: no admin, no colour, and the category moves one way ──────

CREATE OR REPLACE FUNCTION public.guard_viewer_profile()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
	IF NEW.membership_type = 'viewer' THEN
		IF NEW.is_admin THEN
			RAISE EXCEPTION 'Um visualizador não pode ser administrador da família. Promova-o a responsável antes.'
				USING ERRCODE = 'check_violation';
		END IF;
		NEW.color_slot := NULL;
	END IF;

	IF TG_OP = 'UPDATE' AND NEW.membership_type IS DISTINCT FROM OLD.membership_type THEN
		IF OLD.membership_type = 'full' THEN
			RAISE EXCEPTION 'Um responsável não vira visualizador. Para isso, a pessoa sai da família e volta como visualizador.'
				USING ERRCODE = 'check_violation';
		END IF;
		IF current_setting('app.viewer_promotion', true) IS DISTINCT FROM 'on' THEN
			RAISE EXCEPTION 'Só o administrador promove um visualizador, pela página da família.'
				USING ERRCODE = 'insufficient_privilege';
		END IF;
	END IF;
	RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.guard_viewer_profile() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_guard_viewer_profile ON public.profiles;
CREATE TRIGGER trigger_guard_viewer_profile
	BEFORE INSERT OR UPDATE ON public.profiles
	FOR EACH ROW EXECUTE FUNCTION public.guard_viewer_profile();


-- ── 5. A viewer writes nothing in the family's plan ──────────────────────────
-- ONE guard, attached to every table of the plan. It reads the CALLER
-- (auth.uid()), so it holds for direct writes and for every SECURITY DEFINER
-- RPC alike; the system (cron, service role — no auth.uid()) passes.

CREATE OR REPLACE FUNCTION public.refuse_viewer_write()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
	IF auth.uid() IS NOT NULL AND public.is_viewer_caller() THEN
		RAISE EXCEPTION 'Visualizadores acompanham o plano da família sem alterar nada.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;
	RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

ALTER FUNCTION public.refuse_viewer_write() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.refuse_viewer_write() FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
	t text;
BEGIN
	FOREACH t IN ARRAY ARRAY[
		'care_schedules', 'swap_requests', 'day_notices', 'day_accounts',
		'children', 'child_events', 'child_routines', 'family_invitations',
		'family_deletion_requests', 'family_deletion_responses', 'families', 'roles'
	] LOOP
		EXECUTE format('DROP TRIGGER IF EXISTS trigger_a_refuse_viewer_write ON public.%I', t);
		EXECUTE format(
			'CREATE TRIGGER trigger_a_refuse_viewer_write
			 BEFORE INSERT OR UPDATE OR DELETE ON public.%I
			 FOR EACH ROW EXECUTE FUNCTION public.refuse_viewer_write()', t);
	END LOOP;
END $$;


-- ── 6. Never on a day, never a swap party ────────────────────────────────────
-- The same block class as the departed member's (S-11), as its own trigger so
-- enforce_day_protection (rewritten eight times) is not copied a ninth.

CREATE OR REPLACE FUNCTION public.refuse_viewer_assignment()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
	IF (TG_OP = 'INSERT' OR NEW.scheduled_parent_id IS DISTINCT FROM OLD.scheduled_parent_id)
	   AND EXISTS (SELECT 1 FROM public.profiles
	               WHERE id = NEW.scheduled_parent_id AND membership_type = 'viewer') THEN
		RAISE EXCEPTION 'Um visualizador não pode ser responsável por um dia.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF (TG_OP = 'INSERT' OR NEW.actual_parent_id IS DISTINCT FROM OLD.actual_parent_id)
	   AND EXISTS (SELECT 1 FROM public.profiles
	               WHERE id = NEW.actual_parent_id AND membership_type = 'viewer') THEN
		RAISE EXCEPTION 'Um visualizador não pode ser responsável por um dia.'
			USING ERRCODE = 'check_violation';
	END IF;
	RETURN NEW;
END;
$$;

ALTER FUNCTION public.refuse_viewer_assignment() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.refuse_viewer_assignment() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_refuse_viewer_assignment ON public.care_schedules;
CREATE TRIGGER trigger_refuse_viewer_assignment
	BEFORE INSERT OR UPDATE OF scheduled_parent_id, actual_parent_id ON public.care_schedules
	FOR EACH ROW EXECUTE FUNCTION public.refuse_viewer_assignment();

CREATE OR REPLACE FUNCTION public.refuse_viewer_swap_party()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
	IF EXISTS (SELECT 1 FROM public.profiles
	           WHERE id IN (NEW.requesting_profile_id, NEW.target_profile_id,
	                        NEW.proposed_actual_parent_id)
	             AND membership_type = 'viewer') THEN
		RAISE EXCEPTION 'Um visualizador não participa de trocas.'
			USING ERRCODE = 'check_violation';
	END IF;
	RETURN NEW;
END;
$$;

ALTER FUNCTION public.refuse_viewer_swap_party() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.refuse_viewer_swap_party() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_b_refuse_viewer_swap_party ON public.swap_requests;
CREATE TRIGGER trigger_b_refuse_viewer_swap_party
	BEFORE INSERT ON public.swap_requests
	FOR EACH ROW EXECUTE FUNCTION public.refuse_viewer_swap_party();


-- ── 7. The negotiation stays between the two parties ─────────────────────────
-- A RESTRICTIVE policy: whatever else grants a read, a viewer reads no swap.

DROP POLICY IF EXISTS swap_requests_not_viewer ON public.swap_requests;
CREATE POLICY swap_requests_not_viewer ON public.swap_requests
	AS RESTRICTIVE FOR SELECT TO authenticated
	USING (NOT public.is_viewer_caller());


-- ── 8. What reaches a viewer: the informative notifications only ─────────────
-- ONE filter at the table, so a writer written before this item (or after it)
-- cannot hand a viewer something to act on. Allowed: a calendar change
-- (`swap_family_info` — approvals and reverts, no swap message in it), the plan
-- ending, the day's aviso, the agenda it was told about. F-35 adds the chat.

CREATE OR REPLACE FUNCTION public.filter_viewer_notifications()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
	IF EXISTS (SELECT 1 FROM public.profiles
	           WHERE id = NEW.recipient_profile_id AND membership_type = 'viewer')
	   AND NEW.type NOT IN ('swap_family_info', 'plan_ending', 'day_notice',
	                        'agenda_notice', 'agenda_reminder') THEN
		RETURN NULL;
	END IF;
	RETURN NEW;
END;
$$;

ALTER FUNCTION public.filter_viewer_notifications() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.filter_viewer_notifications() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_a_filter_viewer_notifications ON public.notifications;
CREATE TRIGGER trigger_a_filter_viewer_notifications
	BEFORE INSERT ON public.notifications
	FOR EACH ROW EXECUTE FUNCTION public.filter_viewer_notifications();


-- ── 9. Inviting a viewer ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.create_viewer_invitation(p_email text, p_role_id bigint)
RETURNS TABLE (invitation_id bigint, token uuid, expires_at timestamp with time zone)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me          public.profiles%ROWTYPE;
	inv         public.family_invitations%ROWTYPE;
	clean_email text := NULLIF(lower(trim(p_email)), '');
	max_v       int := public.setting_int('max_viewers', 4);
	free_v      int := public.setting_int('free_viewers', 1);
	taken       int;
BEGIN
	IF NOT public.setting_bool('feature.viewers', false) THEN
		RAISE EXCEPTION 'O convite de visualizador ainda não está disponível.'
			USING ERRCODE = 'feature_not_supported';
	END IF;

	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();
	IF me.id IS NULL OR NOT me.is_admin OR me.left_at IS NOT NULL THEN
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

	IF NOT EXISTS (SELECT 1 FROM public.roles
	               WHERE id = p_role_id
	                 AND (family_id IS NULL OR family_id = me.family_id)) THEN
		RAISE EXCEPTION 'Papel inválido.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- Resend semantics, as create_invitation: this e-mail's open invitation
	-- dies BEFORE counting, so a resend never trips the cap it occupies.
	UPDATE public.family_invitations fi
	SET revoked_at = timezone('utc', now())
	WHERE fi.family_id = me.family_id
	  AND lower(fi.email) = clean_email
	  AND fi.accepted_at IS NULL AND fi.revoked_at IS NULL;

	taken := public.viewer_count(me.family_id);

	IF taken >= free_v AND NOT public.is_premium(me.family_id) THEN
		RAISE EXCEPTION 'No plano gratuito, a família inclui % visualizador(es). Para convidar mais, ative o Premium.', free_v
			USING ERRCODE = 'check_violation';
	END IF;

	IF taken >= max_v THEN
		RAISE EXCEPTION 'Esta família já atingiu o limite de % visualizadores (contando convites pendentes).', max_v
			USING ERRCODE = 'check_violation';
	END IF;

	INSERT INTO public.family_invitations (family_id, email, role_id, invited_by, member_type)
	VALUES (me.family_id, clean_email, p_role_id, me.id, 'viewer')
	RETURNING * INTO inv;

	RETURN QUERY SELECT inv.id, inv.token, inv.expires_at;
END;
$$;

ALTER FUNCTION public.create_viewer_invitation(text, bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.create_viewer_invitation(text, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_viewer_invitation(text, bigint) TO authenticated, service_role;


-- ── 10. Promotion: viewer → caregiver ────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.promote_member_to_full(p_profile_id bigint)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me         public.profiles%ROWTYPE;
	target     public.profiles%ROWTYPE;
	max_seats  int := public.setting_int('max_caregivers', 4);
	free_seats int := public.setting_int('free_caregivers', 2);
	taken      int;
	slot       smallint;
BEGIN
	IF NOT public.setting_bool('feature.viewers', false) THEN
		RAISE EXCEPTION 'O visualizador ainda não está disponível.'
			USING ERRCODE = 'feature_not_supported';
	END IF;

	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();
	IF me.id IS NULL OR NOT me.is_admin OR me.left_at IS NOT NULL THEN
		RAISE EXCEPTION 'Somente administradores da família podem promover um visualizador.'
			USING ERRCODE = 'check_violation';
	END IF;

	SELECT * INTO target FROM public.profiles
	WHERE id = p_profile_id AND family_id = me.family_id
	FOR UPDATE;
	IF target.id IS NULL OR target.left_at IS NOT NULL THEN
		RAISE EXCEPTION 'Membro não encontrado na sua família.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF target.membership_type <> 'viewer' THEN
		RAISE EXCEPTION 'Este membro já é responsável.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- A caregiver seat (F-37 arithmetic, open caregiver invitations included)…
	SELECT public.seat_count(me.family_id)
	     + (SELECT count(*) FROM public.family_invitations fi
	        WHERE fi.family_id = me.family_id
	          AND fi.profile_id IS NULL
	          AND fi.member_type = 'full'
	          AND fi.accepted_at IS NULL AND fi.revoked_at IS NULL
	          AND fi.expires_at > timezone('utc', now()))
	INTO taken;

	IF taken >= free_seats AND NOT public.is_premium(me.family_id) THEN
		RAISE EXCEPTION 'Famílias no plano gratuito incluem % responsáveis. Para promover o visualizador, ative o Premium.', free_seats
			USING ERRCODE = 'check_violation';
	END IF;
	IF taken >= max_seats THEN
		RAISE EXCEPTION 'Esta família já atingiu o limite de % responsáveis (contando convites pendentes).', max_seats
			USING ERRCODE = 'check_violation';
	END IF;

	-- …AND a free colour.
	slot := public.next_free_color_slot(me.family_id);
	IF slot IS NULL THEN
		RAISE EXCEPTION 'Não há cor livre para um novo responsável nesta família.'
			USING ERRCODE = 'check_violation';
	END IF;

	PERFORM set_config('app.viewer_promotion', 'on', true);
	UPDATE public.profiles
	SET membership_type = 'full', color_slot = slot
	WHERE id = target.id;
	PERFORM set_config('app.viewer_promotion', 'off', true);

	INSERT INTO public.account_logs (family_id, actor_profile_id, target_profile_id, action, new_value)
	VALUES (me.family_id, me.id, target.id, 'viewer_promoted', 'full');
END;
$$;

ALTER FUNCTION public.promote_member_to_full(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.promote_member_to_full(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.promote_member_to_full(bigint) TO authenticated, service_role;


-- ── 11. Exit: a complete delete ──────────────────────────────────────────────
-- A viewer is referenced by no day, no log, no swap. Its own rows cascade or
-- set null — its notifications go first (that FK has no ON DELETE). If a
-- future feature ever makes a viewer referenced, the delete raises
-- foreign_key_violation and the S-11 tombstone path runs instead: `left_at`
-- now, erasure scheduled now for the purge job.

CREATE OR REPLACE FUNCTION public.erase_viewer(p_viewer public.profiles)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	uid uuid := p_viewer.user_id;
BEGIN
	BEGIN
		DELETE FROM public.notifications WHERE recipient_profile_id = p_viewer.id;
		DELETE FROM public.profiles WHERE id = p_viewer.id;
	EXCEPTION WHEN foreign_key_violation THEN
		PERFORM set_config('app.deletion_context', 'on', true);
		UPDATE public.profiles
		SET left_at = timezone('utc', now()),
		    deletion_scheduled_for = timezone('utc', now())
		WHERE id = p_viewer.id;
		PERFORM set_config('app.deletion_context', 'off', true);
		RETURN 'tombstone';
	END;

	-- The account goes with the profile: nothing of the viewer is kept.
	IF uid IS NOT NULL THEN
		DELETE FROM auth.users WHERE id = uid;
	END IF;
	RETURN 'deleted';
END;
$$;

ALTER FUNCTION public.erase_viewer(public.profiles) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.erase_viewer(public.profiles) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.erase_viewer(public.profiles) TO service_role;

-- The viewer leaves by itself (sudo, like every account deletion — S-10).
CREATE OR REPLACE FUNCTION public.leave_family_as_viewer()
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me public.profiles%ROWTYPE;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();
	IF me.id IS NULL OR me.left_at IS NOT NULL OR me.membership_type <> 'viewer' THEN
		RAISE EXCEPTION 'Só um visualizador sai da família por aqui.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF NOT public.is_elevated() THEN
		RAISE EXCEPTION 'ELEVATION_REQUIRED: Confirme sua senha para sair da família.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	INSERT INTO public.account_logs (family_id, actor_profile_id, target_profile_id, action)
	VALUES (me.family_id, NULL, NULL, 'viewer_left');
	RETURN public.erase_viewer(me);
END;
$$;

ALTER FUNCTION public.leave_family_as_viewer() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.leave_family_as_viewer() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.leave_family_as_viewer() TO authenticated, service_role;

-- The admin removes a viewer.
CREATE OR REPLACE FUNCTION public.remove_viewer(p_profile_id bigint)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me     public.profiles%ROWTYPE;
	target public.profiles%ROWTYPE;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();
	IF me.id IS NULL OR NOT me.is_admin OR me.left_at IS NOT NULL THEN
		RAISE EXCEPTION 'Somente administradores da família podem remover um visualizador.'
			USING ERRCODE = 'check_violation';
	END IF;

	SELECT * INTO target FROM public.profiles
	WHERE id = p_profile_id AND family_id = me.family_id AND left_at IS NULL;
	IF target.id IS NULL OR target.membership_type <> 'viewer' THEN
		RAISE EXCEPTION 'Visualizador não encontrado na sua família.'
			USING ERRCODE = 'check_violation';
	END IF;

	INSERT INTO public.account_logs (family_id, actor_profile_id, target_profile_id, action)
	VALUES (me.family_id, me.id, NULL, 'viewer_removed');
	RETURN public.erase_viewer(target);
END;
$$;

ALTER FUNCTION public.remove_viewer(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.remove_viewer(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_viewer(bigint) TO authenticated, service_role;


-- ── 12. The invitee sees what they are invited as ────────────────────────────
-- Body from 20260909120000 (F-56) plus `member_type`. A return-type change
-- needs DROP + CREATE; anon on purpose — the visitor has no session yet.

DROP FUNCTION IF EXISTS public.get_invite_info(uuid);

CREATE FUNCTION public.get_invite_info(p_token uuid)
RETURNS TABLE (family_name text, inviter_name text, invited_email text, role_name text,
               invitee_name text, member_type text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
	SELECT f.name, p.full_name, i.email, r.role, pm.full_name, i.member_type
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
	'Anonymous read of a PENDING invitation (unknown, accepted, revoked and expired tokens are indistinguishable). F-56: invitee_name prefills the sign-up form. F-50: member_type says whether the person is invited as a caregiver or a viewer — nobody discovers the limitation after signing up.';



-- ── 13. The caregiver gates count caregiver invitations only ────────────────
-- Bodies from 20260909120000 (create_invitation, add_pending_member) and
-- 20260909180000 (attach_pending_member); one line each: a viewer invitation
-- takes no caregiver seat.

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
		          AND fi.member_type = 'full'
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
		          AND fi.member_type = 'full'
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

CREATE OR REPLACE FUNCTION public.attach_pending_member(
	p_invitation_id bigint,
	p_full_name     text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
	me         public.profiles%ROWTYPE;
	inv        public.family_invitations%ROWTYPE;
	clean_name text := trim(p_full_name);
	max_seats  int := public.setting_int('max_caregivers', 4);
	free_seats int := public.setting_int('free_caregivers', 2);
	taken      int;
	new_id     bigint;
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

	-- MY family's invitation, still open, not yet somebody's.
	SELECT * INTO inv FROM public.family_invitations
	WHERE id = p_invitation_id AND family_id = me.family_id;
	IF inv.id IS NULL THEN
		RAISE EXCEPTION 'Convite não encontrado na sua família.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF inv.accepted_at IS NOT NULL THEN
		RAISE EXCEPTION 'Este convite já foi aceito — a pessoa já está na família.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF inv.revoked_at IS NOT NULL THEN
		RAISE EXCEPTION 'Este convite foi revogado. Adicione a pessoa pelo formulário e envie um convite novo.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF inv.profile_id IS NOT NULL THEN
		RAISE EXCEPTION 'Este convite já está ligado a um responsável no calendário.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- A valid invitation already holds the seat the placeholder will take:
	-- nothing to gate. An expired one holds none, so this is a NEW seat and the
	-- F-37 arithmetic applies (this invitation is outside it by construction).
	IF inv.expires_at <= timezone('utc', now()) THEN
		SELECT public.seat_count(me.family_id)
		     + (SELECT count(*) FROM public.family_invitations fi
		        WHERE fi.family_id = me.family_id
		          AND fi.profile_id IS NULL
		          AND fi.member_type = 'full'
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
	END IF;

	-- The placeholder, exactly as add_pending_member builds one: the
	-- invitation's role, the system's colour, no e-mail (that stays on the
	-- invitation row and its 30-day purge — LGPD, F-56).
	INSERT INTO public.profiles (user_id, full_name, role_id, email, family_id, is_admin, color_slot)
	VALUES (NULL, clean_name, inv.role_id, NULL, me.family_id, false,
	        public.next_free_color_slot(me.family_id))
	RETURNING id INTO new_id;

	INSERT INTO public.account_logs (family_id, actor_profile_id, target_profile_id, action, new_value)
	VALUES (me.family_id, me.id, new_id, 'pending_member_added', clean_name);

	-- Same row, same token: the link already sent now lands on this profile.
	UPDATE public.family_invitations
	SET profile_id = new_id
	WHERE id = inv.id;

	RETURN new_id;
END;
$$;


-- ── 14. The sign-up and the OAuth claim make a viewer out of a viewer invite ─
-- Bodies from 20260909120000; the invitee's caps branch on the invitation's
-- member_type, and the profile row carries it (no colour for a viewer).

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
		IF inv.member_type = 'viewer' THEN
			-- F-50: a viewer joins against the VIEWER caps, never a caregiver
			-- seat (the primary guard is create_viewer_invitation; this is the
			-- parallel-invite / lapsed-trial backstop).
			IF (SELECT count(*) FROM public.profiles
			    WHERE family_id = inv.family_id AND membership_type = 'viewer'
			      AND left_at IS NULL) >= public.setting_int('max_viewers', 4) THEN
				RAISE EXCEPTION 'Esta família já atingiu o limite de % visualizadores.', public.setting_int('max_viewers', 4)
					USING ERRCODE = 'check_violation';
			END IF;
			IF (SELECT count(*) FROM public.profiles
			    WHERE family_id = inv.family_id AND membership_type = 'viewer'
			      AND left_at IS NULL) >= public.setting_int('free_viewers', 1)
			   AND NOT public.is_premium(inv.family_id) THEN
				RAISE EXCEPTION 'Esta família já atingiu o limite de % visualizador(es) do plano gratuito. Peça ao administrador para ativar o Premium.', public.setting_int('free_viewers', 1)
					USING ERRCODE = 'check_violation';
			END IF;
		ELSE
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
	-- F-50: a viewer invitation makes a viewer — no colour (the palette is for
	-- the people who appear on a day).
	INSERT INTO public.profiles (user_id, full_name, role_id, email, family_id, is_admin, color_slot,
	                             consent_accepted_at, consent_policy_version, membership_type)
	VALUES (NEW.id, meta_name, new_role_id, NEW.email, fam_id, admin_flag,
	        CASE WHEN admin_flag THEN 1
	             WHEN inv.member_type = 'viewer' THEN NULL
	             ELSE public.next_free_color_slot(fam_id) END,
	        CASE WHEN meta_policy IS NOT NULL THEN timezone('utc', now()) END,
	        meta_policy,
	        COALESCE(inv.member_type, 'full'));

	RETURN NEW;
END;
$$;

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
	IF inv.member_type = 'viewer' THEN
		-- F-50: a viewer joins against the VIEWER caps, never a caregiver
		-- seat (the primary guard is create_viewer_invitation; this is the
		-- parallel-invite / lapsed-trial backstop).
		IF (SELECT count(*) FROM public.profiles
		    WHERE family_id = inv.family_id AND membership_type = 'viewer'
		      AND left_at IS NULL) >= public.setting_int('max_viewers', 4) THEN
			RAISE EXCEPTION 'Esta família já atingiu o limite de % visualizadores.', public.setting_int('max_viewers', 4)
				USING ERRCODE = 'check_violation';
		END IF;
		IF (SELECT count(*) FROM public.profiles
		    WHERE family_id = inv.family_id AND membership_type = 'viewer'
		      AND left_at IS NULL) >= public.setting_int('free_viewers', 1)
		   AND NOT public.is_premium(inv.family_id) THEN
			RAISE EXCEPTION 'Esta família já atingiu o limite de % visualizador(es) do plano gratuito. Peça ao administrador para ativar o Premium.', public.setting_int('free_viewers', 1)
				USING ERRCODE = 'check_violation';
		END IF;
	ELSE
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
	END IF;

	UPDATE public.family_invitations i
	SET accepted_at = timezone('utc', now())
	WHERE i.id = inv.id;

	the_name := COALESCE(the_name, split_part(user_email, '@', 1));

	INSERT INTO public.profiles (user_id, full_name, role_id, email, family_id, is_admin, color_slot,
	                             consent_accepted_at, consent_policy_version, membership_type)
	VALUES (p_user_id, the_name, inv.role_id, user_email, inv.family_id, false,
	        CASE WHEN inv.member_type = 'viewer' THEN NULL
	             ELSE public.next_free_color_slot(inv.family_id) END,
	        timezone('utc', now()), expected, inv.member_type);

	RETURN;
END;
$$;


-- ── 15. A viewer does not vote on a family deletion ─────────────────────────
-- Body from 20260721270000; the unanimity counts caregivers only.

CREATE OR REPLACE FUNCTION public.execute_family_deletion()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me      public.profiles%ROWTYPE;
	req     public.family_deletion_requests%ROWTYPE;
	waiting int;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();
	IF me.id IS NULL OR me.left_at IS NOT NULL THEN
		RAISE EXCEPTION 'Perfil não encontrado ou em processo de saída.' USING ERRCODE = 'check_violation';
	END IF;
	IF NOT me.is_admin THEN
		RAISE EXCEPTION 'Somente administradores podem executar a exclusão da família.'
			USING ERRCODE = 'check_violation';
	END IF;

	SELECT * INTO req FROM public.family_deletion_requests
	WHERE family_id = me.family_id AND status = 'pending';
	IF req.id IS NULL THEN
		RAISE EXCEPTION 'Não há solicitação de exclusão da família pendente.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- S-10: destructive final act — fresh password confirmation required.
	IF NOT public.is_elevated() THEN
		RAISE EXCEPTION 'ELEVATION_REQUIRED: Confirme sua senha para executar a exclusão da família.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	-- Unanimity: every active member other than the requester has an explicit
	-- AGREED response (silence is consent only at the 30-day deadline — the
	-- immediate path demands the explicit yes of everyone).
	SELECT count(*) INTO waiting
	FROM public.profiles p
	WHERE p.family_id = me.family_id AND p.left_at IS NULL AND p.user_id IS NOT NULL
	  AND p.membership_type = 'full'   -- F-50: a viewer does not vote
	  AND p.id <> req.requested_by
	  AND NOT EXISTS (SELECT 1 FROM public.family_deletion_responses r
	                  WHERE r.request_id = req.id AND r.profile_id = p.id AND r.agreed);

	IF waiting > 0 THEN
		RAISE EXCEPTION 'A exclusão imediata exige a concordância explícita de todos os responsáveis (% ainda não concordaram).', waiting
			USING ERRCODE = 'check_violation';
	END IF;

	UPDATE public.family_deletion_requests
	SET scheduled_for = timezone('utc', now())
	WHERE id = req.id;

	INSERT INTO public.account_logs (family_id, actor_profile_id, action)
	VALUES (me.family_id, me.id, 'family_deletion_executed');
END;
$$;


-- ── 16. The promotion is the one path that gives a viewer a colour ─────────
-- Body from 20260720170000; the colour lock lets promote_member_to_full through.

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

	-- DELETE: never remove the last admin of a family.
	IF OLD.is_admin AND NOT EXISTS (
		SELECT 1 FROM public.profiles
		WHERE family_id = OLD.family_id AND is_admin AND id <> OLD.id
	) THEN
		RAISE EXCEPTION 'A família precisa de pelo menos uma pessoa administradora.'
			USING ERRCODE = 'check_violation';
	END IF;
	RETURN OLD;
END;
$$;


-- ── 17. free_viewers ≤ max_viewers (T-80's DEFERRED cross-check) ────────────
-- Body from 20260924110000 (F-55 PR 2) plus the viewer rule.

CREATE OR REPLACE FUNCTION public.app_settings_cross_check()
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	months_free      int := public.setting_int('calendar_months_free', 6);
	months_premium   int := public.setting_int('calendar_months_premium', 24);
	free_seats       int := public.setting_int('free_caregivers', 2);
	max_seats        int := public.setting_int('max_caregivers', 4);
	grace            int := public.setting_int('billing.grace_days', 7);
	grace_warning    int := public.setting_int('billing.grace_warning_days', 2);
	cap_free         int := public.setting_int('email_cap_free', 100);
	cap_premium      int := public.setting_int('email_cap_premium', 10000);
	price_monthly    int := public.setting_int('billing.price_monthly_cents', 549);
	price_annual     int := public.setting_int('billing.price_annual_cents', 5490);
	override_free    int := public.setting_int('override_free_days', 7);
	override_premium int := public.setting_int('override_premium_months', 6);
	poll_degraded    int := public.setting_int('sync.poll_seconds_degraded', 25);
	poll_healthy     int := public.setting_int('sync.poll_seconds_healthy', 120);
	muted            jsonb;
	pushable         text;
	muted_type       text;
	anon_hourly      int := public.setting_int('support.anon_hourly', 3);
	anon_daily       int := public.setting_int('support.anon_daily', 10);
	member_hourly    int := public.setting_int('support.member_hourly', 5);
	member_daily     int := public.setting_int('support.member_daily', 20);
	agenda_notes     int := public.setting_int('agenda.free_notes_per_day', 1);
	agenda_max       int := public.setting_int('agenda.max_events_per_day', 20);
	viewers_free     int := public.setting_int('free_viewers', 1);
	viewers_max      int := public.setting_int('max_viewers', 4);
BEGIN
	IF months_free > months_premium THEN
		RAISE EXCEPTION 'calendar_months_free (%) precisa ser no máximo calendar_months_premium (%): o plano gratuito não planeja mais longe que o Premium.',
			months_free, months_premium
			USING ERRCODE = 'check_violation';
	END IF;

	IF free_seats > max_seats THEN
		RAISE EXCEPTION 'free_caregivers (%) precisa ser no máximo max_caregivers (%): o gratuito não inclui mais responsáveis que o teto.',
			free_seats, max_seats
			USING ERRCODE = 'check_violation';
	END IF;

	IF grace_warning >= grace THEN
		RAISE EXCEPTION 'billing.grace_warning_days (%) precisa ser menor que billing.grace_days (%): o aviso sai antes do rebaixamento, nunca no mesmo dia.',
			grace_warning, grace
			USING ERRCODE = 'check_violation';
	END IF;

	IF cap_free > cap_premium THEN
		RAISE EXCEPTION 'email_cap_free (%) precisa ser no máximo email_cap_premium (%).',
			cap_free, cap_premium
			USING ERRCODE = 'check_violation';
	END IF;

	IF price_annual > 12 * price_monthly THEN
		RAISE EXCEPTION 'billing.price_annual_cents (%) precisa ser no máximo 12 × billing.price_monthly_cents (%): o anual não pode custar mais que doze meses.',
			public.app_settings_format(price_annual, 'cents_brl'),
			public.app_settings_format(12 * price_monthly, 'cents_brl')
			USING ERRCODE = 'check_violation';
	END IF;

	IF override_free > override_premium * 28 THEN
		RAISE EXCEPTION 'override_free_days (%) precisa ser no máximo override_premium_months × 28 (% dias): o gratuito não corrige mais para trás que o Premium.',
			override_free, override_premium * 28
			USING ERRCODE = 'check_violation';
	END IF;
	-- T-83: with the socket up the poll is a safety net, so it is either off
	-- (0) or never MORE frequent than the poll that stands in for a dead socket.
	IF poll_healthy <> 0 AND poll_healthy < poll_degraded THEN
		RAISE EXCEPTION 'sync.poll_seconds_healthy (%) precisa ser 0 (desligado) ou pelo menos sync.poll_seconds_degraded (%): com o socket de pé o poll nunca fica mais frequente que sem ele.',
			poll_healthy, poll_degraded
			USING ERRCODE = 'check_violation';
	END IF;

	-- T-83: `push.disabled_types` may only name a type the dispatcher pushes.
	-- The list is read from the dispatcher's OWN filter, so the twelve types
	-- keep one home (the push mirror tests pin it against push.ts).
	muted := public.setting_text('push.disabled_types', '[]')::jsonb;
	IF jsonb_typeof(muted) <> 'array' THEN
		RAISE EXCEPTION 'push.disabled_types precisa ser uma lista JSON de tipos, como ["swap_requested"].'
			USING ERRCODE = 'check_violation';
	END IF;
	pushable := substring(pg_get_functiondef('public.dispatch_push_notification()'::regprocedure)
	                      from 'NEW\.type NOT IN \(([^)]*)\)');
	FOR muted_type IN SELECT jsonb_array_elements_text(muted) LOOP
		IF pushable IS NULL OR position(quote_literal(muted_type) in pushable) = 0 THEN
			RAISE EXCEPTION 'push.disabled_types: "%" não é um tipo que gera push. Os tipos são os do filtro de dispatch_push_notification.', muted_type
				USING ERRCODE = 'check_violation';
		END IF;
	END LOOP;

	-- T-83: a support limit per hour never exceeds the one per day it lives in.
	IF anon_hourly > anon_daily THEN
		RAISE EXCEPTION 'support.anon_hourly (%) precisa ser no máximo support.anon_daily (%).', anon_hourly, anon_daily
			USING ERRCODE = 'check_violation';
	END IF;
	IF member_hourly > member_daily THEN
		RAISE EXCEPTION 'support.member_hourly (%) precisa ser no máximo support.member_daily (%).', member_hourly, member_daily
			USING ERRCODE = 'check_violation';
	END IF;

	-- F-55 (T-84 rule 2): a free family's notes per day never exceed what any
	-- day may hold at all.
	IF agenda_notes > agenda_max THEN
		RAISE EXCEPTION 'agenda.free_notes_per_day (%) precisa ser no máximo agenda.max_events_per_day (%).', agenda_notes, agenda_max
			USING ERRCODE = 'check_violation';
	END IF;

	IF viewers_free > viewers_max THEN
		RAISE EXCEPTION 'free_viewers (%) precisa ser no máximo max_viewers (%): o gratuito não inclui mais visualizadores que o teto.', viewers_free, viewers_max
			USING ERRCODE = 'check_violation';
	END IF;
END;
$$;


-- ── 18. F-69: the category and the viewer counts — counts only ─────────────
-- Body from 20260924130000 (F-55 PR 4); `membership` per member, and the
-- viewers used / cap / open invitations per family.

CREATE OR REPLACE FUNCTION public.admin_family_usage_report(p_family_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	fam        public.families%ROWTYPE;
	today      date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	first_week date;
	weeks      int := public.setting_int('usage_report.weeks', 12);
	active_win int := public.setting_int('usage_report.active_days', 30);
	premium    boolean;
	result     jsonb;
BEGIN
	IF NOT public.is_platform_operator() THEN
		RAISE EXCEPTION 'Acesso restrito à operação da plataforma.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	SELECT * INTO fam FROM public.families WHERE id = p_family_id;

	INSERT INTO public.operator_audit_logs (operator_user_id, action, family_id, new_value)
	VALUES (auth.uid(), 'family_usage_report', fam.id, p_family_id::text);

	IF fam.id IS NULL THEN
		RETURN NULL;
	END IF;

	premium    := public.is_premium(fam.id);
	first_week := date_trunc('week', today)::date - 7 * (weeks - 1);

	WITH
	days AS (
		SELECT
			d.schedule_date                                       AS day,
			COALESCE(d.actual_parent_id, d.scheduled_parent_id)   AS carer,
			d.scheduled_parent_id                                 AS planned,
			d.actual_parent_id                                    AS actual,
			d.handoff_time,
			NULLIF(btrim(d.notes), '') IS NOT NULL                AS has_note,
			(p.id IS NULL
			 OR COALESCE(p.actual_parent_id, p.scheduled_parent_id)
			    IS DISTINCT FROM COALESCE(d.actual_parent_id, d.scheduled_parent_id))
			                                                      AS transition
		FROM public.care_schedules d
		LEFT JOIN public.care_schedules p
		       ON p.family_id = d.family_id AND p.schedule_date = d.schedule_date - 1
		WHERE d.family_id = fam.id
	),
	edits AS (
		SELECT
			(l.created_at AT TIME ZONE 'America/Sao_Paulo')::date AS day,
			l.performed_by_id,
			COALESCE(l.context ->> 'batch_id',
			         l.performed_by_id::text || '@' || l.created_at::text) AS unit,
			COALESCE((l.context ->> 'admin_override')::boolean, false) AS override
		FROM public.activity_logs l
		WHERE l.family_id = fam.id
		  AND l.created_at >= (first_week::timestamp AT TIME ZONE 'America/Sao_Paulo')
	),
	weeks AS (
		SELECT w::date AS week_start
		FROM generate_series(first_week, date_trunc('week', today)::date, interval '7 days') w
	)
	SELECT jsonb_build_object(
		'report_version', 1,
		'generated_at',   now(),
		'today',          today,
		'windows',        jsonb_build_object('weeks', weeks, 'active_days', active_win),

		'family', jsonb_build_object(
			'id',              fam.id,
			'created_at',      fam.created_at,
			'plan',            fam.plan,
			'is_premium',      premium,
			'trial_ends_at',   fam.trial_ends_at,
			'comp_premium_at', fam.comp_premium_at,
			'seats_used',      public.seat_count(fam.id),
			'seats_cap',       CASE WHEN premium
			                        THEN public.setting_int('max_caregivers', 4)
			                        ELSE public.setting_int('free_caregivers', 2) END,
			-- F-50: the viewers, outside the caregiver seats — counts only.
			'viewers_used',    (SELECT COUNT(*) FROM public.profiles v
			                    WHERE v.family_id = fam.id AND v.membership_type = 'viewer'
			                      AND v.left_at IS NULL),
			'viewers_cap',     CASE WHEN premium
			                        THEN public.setting_int('max_viewers', 4)
			                        ELSE public.setting_int('free_viewers', 1) END,
			'viewer_invitations_open', (SELECT COUNT(*) FROM public.family_invitations vi
			                    WHERE vi.family_id = fam.id AND vi.member_type = 'viewer'
			                      AND vi.accepted_at IS NULL AND vi.revoked_at IS NULL
			                      AND vi.expires_at > now()),
			'subscription', (
				SELECT jsonb_build_object(
					'gateway',            s.gateway,
					'status',             s.status,
					'cycle',              s.cycle,
					'current_period_end', s.current_period_end,
					'overdue_since',      s.overdue_since,
					'canceled_at',        s.canceled_at
				)
				FROM public.subscriptions s WHERE s.family_id = fam.id
			),
			'invitations', (
				SELECT jsonb_build_object(
					'open',     COUNT(*) FILTER (WHERE i.accepted_at IS NULL AND i.revoked_at IS NULL AND i.expires_at > now()),
					'accepted', COUNT(*) FILTER (WHERE i.accepted_at IS NOT NULL),
					'expired',  COUNT(*) FILTER (WHERE i.accepted_at IS NULL AND i.revoked_at IS NULL AND i.expires_at <= now()),
					'revoked',  COUNT(*) FILTER (WHERE i.accepted_at IS NULL AND i.revoked_at IS NOT NULL),
					'oldest_open_created_at',
					            MIN(i.created_at) FILTER (WHERE i.accepted_at IS NULL AND i.revoked_at IS NULL AND i.expires_at > now())
				)
				FROM public.family_invitations i WHERE i.family_id = fam.id
			)
		),

		'members', (
			SELECT COALESCE(jsonb_agg(jsonb_build_object(
				'profile_id',             p.id,
				'role',                   CASE WHEN r.family_id IS NULL THEN r.role ELSE 'custom' END,
				'is_admin',               p.is_admin,
				'membership',             p.membership_type,
				'state',                  CASE WHEN p.left_at IS NOT NULL THEN 'departed'
				                               WHEN p.user_id IS NULL     THEN 'pending'
				                               ELSE 'active' END,
				'created_at',             p.created_at,
				'joined_via_invite',      p.joined_via_invite,
				'left_at',                p.left_at,
				'has_password',           (SELECT COALESCE(u.encrypted_password, '') <> ''
				                           FROM auth.users u WHERE u.id = p.user_id),
				'has_google',             EXISTS (SELECT 1 FROM auth.identities i
				                                  WHERE i.user_id = p.user_id AND i.provider = 'google'),
				'language',               p.language_effective,
				'tour_seen_at',           p.onboarding_tour_seen_at,
				'consent_policy_version', p.consent_policy_version,
				'consent_accepted_at',    p.consent_accepted_at,
				'last_active_day',        la.last_day,
				'last_active_source',     la.last_source,
				'active_days_30', (
					SELECT COUNT(DISTINCT a.day) FROM public.member_activity_days a
					WHERE a.profile_id = p.id AND a.day > today - active_win
				),
				'channels_30', (
					SELECT COALESCE(jsonb_agg(DISTINCT a.channel), '[]'::jsonb)
					FROM public.member_activity_days a
					WHERE a.profile_id = p.id AND a.day > today - active_win
				),
				'devices', (
					SELECT COALESCE(jsonb_agg(jsonb_build_object(
						'platform',     ps.platform,
						'count',        ps.n,
						'last_seen_at', ps.last_seen
					) ORDER BY ps.platform), '[]'::jsonb)
					FROM (
						SELECT platform, COUNT(*) AS n, MAX(last_seen_at) AS last_seen
						FROM public.push_subscriptions
						WHERE profile_id = p.id
						GROUP BY platform
					) ps
				),
				'unread', (
					SELECT COALESCE(jsonb_agg(jsonb_build_object(
						'type',  un.type,
						'count', un.n
					) ORDER BY un.type), '[]'::jsonb)
					FROM (
						SELECT type, COUNT(*) AS n
						FROM public.notifications
						WHERE recipient_profile_id = p.id AND NOT COALESCE(is_read, false)
						GROUP BY type
					) un
				)
			) ORDER BY p.id), '[]'::jsonb)
			FROM public.profiles p
			LEFT JOIN public.roles r ON r.id = p.role_id
			LEFT JOIN LATERAL public.member_last_active(p.id) la ON true
			WHERE p.family_id = fam.id
		),

		'plan', (
			SELECT jsonb_build_object(
				'first_day',                   MIN(day),
				'last_day',                    MAX(day),
				'days_total',                  COUNT(*),
				'days_ahead',                  COUNT(*) FILTER (WHERE day >= today),
				'days_with_handoff_time',      COUNT(*) FILTER (WHERE handoff_time IS NOT NULL),
				'days_with_note',              COUNT(*) FILTER (WHERE has_note),
				'days_diverged',               COUNT(*) FILTER (WHERE actual IS NOT NULL AND actual IS DISTINCT FROM planned),
				'transitions_ahead',           COUNT(*) FILTER (WHERE day >= today AND transition),
				'transitions_ahead_with_time', COUNT(*) FILTER (WHERE day >= today AND transition AND handoff_time IS NOT NULL),
				'carers_ahead', (
					SELECT COALESCE(jsonb_agg(jsonb_build_object(
						'profile_id', c.carer,
						'days',       c.n
					) ORDER BY c.carer), '[]'::jsonb)
					FROM (
						SELECT carer, COUNT(*) AS n FROM days
						WHERE day >= today AND carer IS NOT NULL
						GROUP BY carer
					) c
				)
			)
			FROM days
		),

		'weeks', (
			SELECT COALESCE(jsonb_agg(jsonb_build_object(
				'week_start', wk.week_start,
				'edits', (
					SELECT COUNT(DISTINCT e.unit) FROM edits e
					WHERE e.day >= wk.week_start AND e.day < wk.week_start + 7
				),
				'edits_by_member', (
					SELECT COALESCE(jsonb_agg(jsonb_build_object(
						'profile_id', em.performed_by_id,
						'count',      em.n
					) ORDER BY em.performed_by_id), '[]'::jsonb)
					FROM (
						SELECT e.performed_by_id, COUNT(DISTINCT e.unit) AS n
						FROM edits e
						WHERE e.day >= wk.week_start AND e.day < wk.week_start + 7
						GROUP BY e.performed_by_id
					) em
				),
				'admin_overrides', (
					SELECT COUNT(DISTINCT e.unit) FROM edits e
					WHERE e.override AND e.day >= wk.week_start AND e.day < wk.week_start + 7
				),
				'swaps_opened', (
					SELECT COUNT(*) FROM public.swap_requests s
					WHERE s.family_id = fam.id
					  AND (s.created_at AT TIME ZONE 'America/Sao_Paulo')::date >= wk.week_start
					  AND (s.created_at AT TIME ZONE 'America/Sao_Paulo')::date <  wk.week_start + 7
				),
				'swaps_resolved', (
					SELECT COUNT(*) FROM public.swap_requests s
					WHERE s.family_id = fam.id
					  AND (s.resolved_at AT TIME ZONE 'America/Sao_Paulo')::date >= wk.week_start
					  AND (s.resolved_at AT TIME ZONE 'America/Sao_Paulo')::date <  wk.week_start + 7
				),
				'notices', (
					SELECT COUNT(*) FROM public.day_notices n
					WHERE n.family_id = fam.id
					  AND (n.created_at AT TIME ZONE 'America/Sao_Paulo')::date >= wk.week_start
					  AND (n.created_at AT TIME ZONE 'America/Sao_Paulo')::date <  wk.week_start + 7
				),
				'agenda_events', (
					SELECT COUNT(*) FROM public.child_events ce
					WHERE ce.family_id = fam.id AND ce.source_schedule_id IS NULL
					  AND ce.batch_id IS NULL
					  AND (ce.created_at AT TIME ZONE 'America/Sao_Paulo')::date >= wk.week_start
					  AND (ce.created_at AT TIME ZONE 'America/Sao_Paulo')::date <  wk.week_start + 7
				),
				'day_accounts', (
					SELECT COUNT(*) FROM public.day_accounts da
					WHERE da.family_id = fam.id
					  AND (da.created_at AT TIME ZONE 'America/Sao_Paulo')::date >= wk.week_start
					  AND (da.created_at AT TIME ZONE 'America/Sao_Paulo')::date <  wk.week_start + 7
				),
				'active_members', (
					SELECT COUNT(DISTINCT a.profile_id)
					FROM public.member_activity_days a
					JOIN public.profiles p ON p.id = a.profile_id
					WHERE p.family_id = fam.id
					  AND a.day >= wk.week_start AND a.day < wk.week_start + 7
				)
			) ORDER BY wk.week_start), '[]'::jsonb)
			FROM weeks wk
		),

		'swaps', jsonb_build_object(
			'by_status', (
				SELECT COALESCE(jsonb_agg(jsonb_build_object(
					'status',      bs.status,
					'resolved_by', bs.resolved_by,
					'count',       bs.n
				) ORDER BY bs.status, bs.resolved_by), '[]'::jsonb)
				FROM (
					SELECT status, resolved_by, COUNT(*) AS n
					FROM public.swap_requests
					WHERE family_id = fam.id
					GROUP BY status, resolved_by
				) bs
			),
			-- The COUNTERPART's answer: approved or rejected by a person. A
			-- cancellation is the requester's own act and an auto-approval
			-- (F-24, resolved_by 'system') is nobody's — both would skew it.
			'median_answer_hours', (
				SELECT round((percentile_cont(0.5) WITHIN GROUP (
					ORDER BY extract(epoch FROM s.resolved_at - s.created_at) / 3600.0))::numeric, 1)
				FROM public.swap_requests s
				WHERE s.family_id = fam.id
				  AND s.resolved_by = 'user'
				  AND s.status IN ('approved', 'rejected', 'revert_approved', 'revert_rejected')
				  AND s.resolved_at IS NOT NULL
			),
			'pending', (
				SELECT COUNT(*) FROM public.swap_requests s
				WHERE s.family_id = fam.id AND s.status IN ('pending', 'revert_pending')
			),
			'oldest_pending_created_at', (
				SELECT MIN(s.created_at) FROM public.swap_requests s
				WHERE s.family_id = fam.id AND s.status IN ('pending', 'revert_pending')
			)
		),

		'notices', jsonb_build_object(
			'total', (SELECT COUNT(*) FROM public.day_notices n WHERE n.family_id = fam.id),
			'by_outcome', (
				SELECT COALESCE(jsonb_agg(jsonb_build_object(
					'outcome', bo.outcome,
					'count',   bo.n
				) ORDER BY bo.outcome), '[]'::jsonb)
				FROM (
					SELECT COALESCE(o.outcome, 'none') AS outcome, COUNT(*) AS n
					FROM public.day_notices n
					LEFT JOIN public.day_notice_outcomes o ON o.notice_id = n.id
					WHERE n.family_id = fam.id
					GROUP BY COALESCE(o.outcome, 'none')
				) bo
			)
		),

		'day_accounts', jsonb_build_object(
			'total',       (SELECT COUNT(*) FROM public.day_accounts da WHERE da.family_id = fam.id),
			'corrections', (SELECT COUNT(*) FROM public.day_accounts da
			                WHERE da.family_id = fam.id AND da.corrects_id IS NOT NULL)
		),

		-- F-55: the child entity and the agenda — counts only, never a name
		-- or an event's text.
		'agenda', jsonb_build_object(
			'children',       (SELECT COUNT(*) FROM public.children c WHERE c.family_id = fam.id),
			'events_active',  (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.deleted_at IS NULL),
			'events_ahead',   (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.deleted_at IS NULL
			                     AND ce.event_date >= today),
			'events_deleted', (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.deleted_at IS NOT NULL),
			'notes_active',   (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.deleted_at IS NULL
			                     AND ce.kind = 'note'),
			'converted',      (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.source_schedule_id IS NOT NULL),
			'routines',       (SELECT COUNT(*) FROM public.child_routines cr
			                   WHERE cr.family_id = fam.id AND cr.stopped_at IS NULL),
			'events_from_routine', (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.deleted_at IS NULL
			                     AND ce.batch_id IS NOT NULL),
			'with_reminder',  (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.deleted_at IS NULL
			                     AND ce.remind_minutes IS NOT NULL),
			'reminders_sent', (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.reminded_at IS NOT NULL),
			'by_kind', (
				SELECT COALESCE(jsonb_agg(jsonb_build_object(
					'kind',  bk.kind,
					'count', bk.n
				) ORDER BY bk.kind), '[]'::jsonb)
				FROM (
					SELECT kind, COUNT(*) AS n FROM public.child_events
					WHERE family_id = fam.id AND deleted_at IS NULL
					GROUP BY kind
				) bk
			)
		)
	) INTO result;

	RETURN result;
END;
$$;


-- Grants and owners of the recreated functions are unchanged by CREATE OR
-- REPLACE; restated for the ones a reader would look for here.
ALTER FUNCTION public.create_invitation(text, bigint, bigint) OWNER TO postgres;
ALTER FUNCTION public.claim_invitation_for_user(uuid, text, text, text, boolean) OWNER TO postgres;
