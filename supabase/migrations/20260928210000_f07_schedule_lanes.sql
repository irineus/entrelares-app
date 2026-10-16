-- =============================================================================
-- F-07 (PR 2) — the plan per child: one LANE per child, dark
--
-- Until now a family had ONE plan: `care_schedules` was UNIQUE (family_id,
-- schedule_date), and every rule that looks at "the day" — the T-27/T-45
-- transition, the frozen day, the one pending swap per date, the audit's
-- admin-override stamp, the F-51/U-55 range operations — found it by
-- (family, date). This migration gives every schedule row a LANE:
--
--   · `families.schedule_mode` = 'single' (every family today, the default) or
--     'per_child'. In 'single' the lane is NULL, exactly the rows that exist;
--     in 'per_child' each row names its child (`care_schedules.child_id`).
--   · The key is (family_id, child_id, schedule_date) NULLS NOT DISTINCT, so a
--     single-mode family keeps one row per date and nothing it has changes.
--   · Every lookup that meant "the same day" now means "the same day IN THE
--     SAME LANE": D-1/D+1 for the handoff rule, the pending request that
--     freezes a day, the pending-per-date uniqueness, the audit's is_target,
--     the resolution log's newest row, the range RPCs.
--
-- Decisions locked with the owner (28/09/2026): the lane follows the child for
-- the whole workflow (one swap request = one child); switching modes rewrites
-- only from today on (the past is immutable) — the switch itself is PR 3. The
-- whole thing ships DARK: `feature.per_child_schedule` is seeded false, and
-- nothing but PR 3's RPC ever writes 'per_child', so no production family can
-- reach a lane before the flag.
--
-- Also decided here (engineering, recorded on the card): a child whose lane
-- holds any plan row cannot be removed — past rows are immutable, and the
-- history must keep naming the child it was about. `swap_requests.child_id`
-- and `activity_logs.child_id` are STAMPED facts with no FK (the shape of
-- `child_events.source_schedule_id`): history outlives the rows it describes.
-- =============================================================================

-- ── 1. The flag (T-84 catalogue) ─────────────────────────────────────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, help)
VALUES
	('feature.per_child_schedule', 'false', 'bool', 'features',
	 'Liga o plano por criança (F-07): cada criança com a própria escala. Desligado, ninguém muda o modo do plano.',
	 true, 'flag', 'critical',
	 jsonb_build_object(
		'controls', 'Se o administrador pode passar a família do plano único para o plano por criança (e voltar), e se o app mostra o seletor de criança no calendário.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Ligado: famílias com duas ou mais crianças podem ter uma escala para cada uma; trocas, horários e avisos passam a ser por criança.',
		'if_decreased', 'Desligado (chave de emergência): ninguém muda o modo. Famílias que já estão no plano por criança CONTINUAM nele — os dias gravados não se desfazem.',
		'takes_effect', 'Servidor na próxima troca de modo; app na próxima abertura.',
		'caveats', 'Nasce DESLIGADO em produção. Ligar em produção é o último PR do F-07, depois dos textos de notificação por criança.'))
ON CONFLICT (key) DO NOTHING;


-- ── 2. The mode and the lanes ────────────────────────────────────────────────

ALTER TABLE public.families
	ADD COLUMN IF NOT EXISTS schedule_mode text NOT NULL DEFAULT 'single'
		CHECK (schedule_mode IN ('single', 'per_child'));

-- NO ACTION (not RESTRICT): a family purge cascades children and deletes
-- care_schedules in the same teardown, and NO ACTION is judged at the end of
-- the statement. remove_child refuses first, in words (§6).
ALTER TABLE public.care_schedules
	ADD COLUMN IF NOT EXISTS child_id bigint REFERENCES public.children(id);

-- The NAMES stay: `translateSaveError` (core) recognises both by name, in
-- every Android build already on a phone — a new name would turn their
-- "este dia já existe" / "já há um pedido" into a generic failure.
ALTER TABLE public.care_schedules
	DROP CONSTRAINT IF EXISTS care_schedules_family_schedule_date_key;
ALTER TABLE public.care_schedules
	ADD CONSTRAINT care_schedules_family_schedule_date_key
		UNIQUE NULLS NOT DISTINCT (family_id, child_id, schedule_date);

ALTER TABLE public.swap_requests
	ADD COLUMN IF NOT EXISTS child_id bigint;

DROP INDEX IF EXISTS public.swap_requests_one_pending_per_date;
CREATE UNIQUE INDEX IF NOT EXISTS swap_requests_one_pending_per_date
	ON public.swap_requests (family_id, child_id, schedule_date) NULLS NOT DISTINCT
	WHERE status IN ('pending', 'revert_pending');

ALTER TABLE public.activity_logs
	ADD COLUMN IF NOT EXISTS child_id bigint;

COMMENT ON COLUMN public.care_schedules.child_id IS
	'F-07: the lane. NULL in a single-plan family (one plan for every child); the child in a per_child family. Immutable after insert.';
COMMENT ON COLUMN public.swap_requests.child_id IS
	'F-07: the lane of the day the request is about, stamped from schedule_id. No FK: history outlives the child row.';
COMMENT ON COLUMN public.activity_logs.child_id IS
	'F-07: the lane of the audited row, stamped by audit_care_schedule_changes. No FK: history outlives the child row.';


-- ── 3. The lane guard on care_schedules ──────────────────────────────────────
-- Runs after trigger_a_set_care_schedule_family (alphabetical), so family_id
-- is already the scheduled parent's.

CREATE OR REPLACE FUNCTION public.enforce_schedule_lane()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	mode text;
BEGIN
	IF current_setting('app.deletion_context', true) = 'on' THEN
		RETURN NEW;
	END IF;

	IF TG_OP = 'UPDATE' THEN
		-- A row never changes lane: the day of one child does not become the
		-- day of another (that would be a swap nobody approved).
		IF NEW.child_id IS DISTINCT FROM OLD.child_id THEN
			RAISE EXCEPTION 'O dia de uma criança não pode passar para outra.'
				USING ERRCODE = 'check_violation';
		END IF;
		RETURN NEW;
	END IF;

	SELECT schedule_mode INTO mode FROM public.families WHERE id = NEW.family_id;

	IF NEW.child_id IS NULL THEN
		IF mode = 'per_child' THEN
			RAISE EXCEPTION 'O plano desta família é por criança: escolha a criança do dia.'
				USING ERRCODE = 'check_violation';
		END IF;
	ELSE
		IF mode IS DISTINCT FROM 'per_child' THEN
			RAISE EXCEPTION 'O plano desta família é único para todas as crianças.'
				USING ERRCODE = 'check_violation';
		END IF;
		IF NOT EXISTS (SELECT 1 FROM public.children
		               WHERE id = NEW.child_id AND family_id = NEW.family_id) THEN
			RAISE EXCEPTION 'Criança não encontrada na sua família.'
				USING ERRCODE = 'no_data_found';
		END IF;
	END IF;

	-- One date is either the family's (NULL lane) or its children's, never
	-- both: a past single-plan day and a per-child day on the same date would
	-- make "who had the child that day" two answers.
	IF EXISTS (SELECT 1 FROM public.care_schedules
	           WHERE family_id = NEW.family_id AND schedule_date = NEW.schedule_date
	             AND (child_id IS NULL) <> (NEW.child_id IS NULL)) THEN
		RAISE EXCEPTION 'Este dia já está planejado no outro modo do plano.'
			USING ERRCODE = 'check_violation';
	END IF;

	RETURN NEW;
END;
$$;

ALTER FUNCTION public.enforce_schedule_lane() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.enforce_schedule_lane() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_a_z_enforce_schedule_lane ON public.care_schedules;
CREATE TRIGGER trigger_a_z_enforce_schedule_lane
	BEFORE INSERT OR UPDATE ON public.care_schedules
	FOR EACH ROW EXECUTE FUNCTION public.enforce_schedule_lane();


-- ── 4. The swap request carries its day's lane ───────────────────────────────
-- Stamped from schedule_id on INSERT (the client never decides the lane),
-- immutable afterwards. Runs after trigger_a_set_swap_request_family.

CREATE OR REPLACE FUNCTION public.stamp_swap_request_lane()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
	IF TG_OP = 'UPDATE' THEN
		NEW.child_id := OLD.child_id;
		RETURN NEW;
	END IF;

	IF NEW.schedule_id IS NOT NULL THEN
		NEW.child_id := (SELECT child_id FROM public.care_schedules WHERE id = NEW.schedule_id);
	ELSIF NEW.child_id IS NOT NULL
	      AND NOT EXISTS (SELECT 1 FROM public.children
	                      WHERE id = NEW.child_id AND family_id = NEW.family_id) THEN
		RAISE EXCEPTION 'Criança não encontrada na sua família.'
			USING ERRCODE = 'no_data_found';
	END IF;

	RETURN NEW;
END;
$$;

ALTER FUNCTION public.stamp_swap_request_lane() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.stamp_swap_request_lane() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_a_z_stamp_swap_request_lane ON public.swap_requests;
CREATE TRIGGER trigger_a_z_stamp_swap_request_lane
	BEFORE INSERT OR UPDATE ON public.swap_requests
	FOR EACH ROW EXECUTE FUNCTION public.stamp_swap_request_lane();


-- ── 5. The day rules, lane-aware ─────────────────────────────────────────────
-- Bodies from production (pg_get_functiondef, 28/09/2026); the only change in
-- each is the lane predicate `child_id IS NOT DISTINCT FROM …`, which is TRUE
-- between two NULL lanes — so a single-plan family behaves exactly as before.

-- 5a. T-27/T-45 — the transition rule looks at D-1 in the SAME lane.
CREATE OR REPLACE FUNCTION public.apply_handoff_transition_rule()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
	prev_effective bigint;
	prev_found     boolean := false;
	new_effective  bigint;
	is_transition  boolean;
BEGIN
	-- The parking slot is server-owned (same stance as T-35's submitted_token):
	-- a payload never decides what is parked.
	IF TG_OP = 'UPDATE' THEN
		NEW.handoff_time_backup := OLD.handoff_time_backup;

		-- An explicit write of handoff_time is the writer's INTENT and always
		-- wins over a parked value: a time cleared by hand must never be
		-- resurrected later by the restore branch below.
		IF NEW.handoff_time IS DISTINCT FROM OLD.handoff_time THEN
			NEW.handoff_time_backup := NULL;
		END IF;
	ELSE
		NEW.handoff_time_backup := NULL;
	END IF;

	new_effective := COALESCE(NEW.actual_parent_id, NEW.scheduled_parent_id);

	SELECT COALESCE(actual_parent_id, scheduled_parent_id), true
	INTO prev_effective, prev_found
	FROM public.care_schedules
	WHERE family_id = NEW.family_id
	  AND child_id IS NOT DISTINCT FROM NEW.child_id
	  AND schedule_date = NEW.schedule_date - 1;

	-- No previous day = custody starts here = transition (mirrors the editor).
	is_transition := NOT COALESCE(prev_found, false)
	                 OR prev_effective IS DISTINCT FROM new_effective;

	IF is_transition THEN
		IF NEW.handoff_time IS NULL AND NEW.handoff_time_backup IS NOT NULL THEN
			NEW.handoff_time        := NEW.handoff_time_backup;
			NEW.handoff_time_backup := NULL;
		END IF;
	ELSIF NEW.handoff_time IS NOT NULL THEN
		NEW.handoff_time_backup := NEW.handoff_time;
		NEW.handoff_time        := NULL;
	END IF;

	RETURN NEW;
END;
$function$;

-- 5b. T-45 — the cascade touches D+1 in the SAME lane.
CREATE OR REPLACE FUNCTION public.sync_next_day_handoff()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
	fam            bigint;
	the_date       date;
	lane           bigint;
	day_effective  bigint;   -- NULL when the day no longer exists (DELETE)
	nxt            public.care_schedules%ROWTYPE;
	next_effective bigint;
	is_transition  boolean;
	prev_flag      text;
BEGIN
	-- Only a change of the day's effective responsible can flip D+1's
	-- transition status. This is also what stops the recursion: the cascade
	-- below writes handoff_time, never the responsible.
	IF TG_OP = 'UPDATE'
	   AND NEW.schedule_date = OLD.schedule_date
	   AND COALESCE(NEW.actual_parent_id, NEW.scheduled_parent_id)
	       IS NOT DISTINCT FROM COALESCE(OLD.actual_parent_id, OLD.scheduled_parent_id) THEN
		RETURN NULL;
	END IF;

	IF TG_OP = 'DELETE' THEN
		fam := OLD.family_id;  the_date := OLD.schedule_date;  lane := OLD.child_id;
		day_effective := NULL;
	ELSE
		fam := NEW.family_id;  the_date := NEW.schedule_date;  lane := NEW.child_id;
		day_effective := COALESCE(NEW.actual_parent_id, NEW.scheduled_parent_id);
	END IF;

	SELECT * INTO nxt
	FROM public.care_schedules
	WHERE family_id = fam AND child_id IS NOT DISTINCT FROM lane
	  AND schedule_date = the_date + 1;
	IF NOT FOUND THEN
		RETURN NULL;
	END IF;

	next_effective := COALESCE(nxt.actual_parent_id, nxt.scheduled_parent_id);
	-- The day is gone (DELETE) → D+1 has no previous day → it is a transition.
	is_transition  := day_effective IS NULL OR day_effective IS DISTINCT FROM next_effective;

	-- Touch D+1 only when the rule would actually change it — an UPDATE here
	-- costs an activity_logs row and a new revision token for every client
	-- holding that day open.
	IF (NOT is_transition AND nxt.handoff_time IS NOT NULL)
	   OR (is_transition AND nxt.handoff_time IS NULL AND nxt.handoff_time_backup IS NOT NULL) THEN
		prev_flag := COALESCE(current_setting('app.handoff_cascade', true), 'off');
		PERFORM set_config('app.handoff_cascade', 'on', true);

		-- No column of substance: trigger_d recomputes handoff_time from the
		-- new state of day D.
		UPDATE public.care_schedules
		SET updated_at = timezone('utc', now())
		WHERE id = nxt.id;

		PERFORM set_config('app.handoff_cascade', prev_flag, true);
	END IF;

	RETURN NULL;
END;
$function$;

-- 5c. F-12 & co. — a day is frozen by a pending request of ITS lane.
CREATE OR REPLACE FUNCTION public.enforce_day_protection()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
	cur_profile_id bigint;
	cur_is_admin   boolean := false;
	today          date;
	the_date       date;
	fam            bigint;
	lane           bigint;
	is_frozen      boolean := false;
	is_target      boolean := false;
	horizon_months int;
BEGIN
	-- T-45: internal cascade of the handoff transition rule (sync_next_day_handoff).
	IF current_setting('app.handoff_cascade', true) = 'on' THEN
		RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
	END IF;

	-- S-11: controlled erasure cleanup — see 20260719120000.
	IF current_setting('app.deletion_context', true) = 'on' THEN
		RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
	END IF;

	-- F-07: the plan-mode switch (`set_schedule_mode`, PR 3) moves the plan
	-- from today on between lanes as ONE admin act — an approved swap's day
	-- is copied with its real parent, which a direct write could never do.
	-- The RPC has already checked the flag, the admin, and that no request is
	-- pending from today on; a client cannot set a GUC through PostgREST.
	IF current_setting('app.schedule_mode_switch', true) = 'on' THEN
		RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
	END IF;

	-- System context (service_role: F-24 auto-approval, migrations): unrestricted.
	SELECT id, is_admin INTO cur_profile_id, cur_is_admin
	FROM public.profiles WHERE user_id = auth.uid();
	IF cur_profile_id IS NULL THEN
		RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
	END IF;

	-- S-11: a departed member (left_at set) cannot be NEWLY assigned to a day,
	-- as the planned or the real parent. Past history keeps their name — only a
	-- CHANGE that puts a departed member on a day is blocked.
	IF TG_OP IN ('INSERT', 'UPDATE') THEN
		IF (TG_OP = 'INSERT' OR NEW.scheduled_parent_id IS DISTINCT FROM OLD.scheduled_parent_id)
		   AND EXISTS (SELECT 1 FROM public.profiles
		               WHERE id = NEW.scheduled_parent_id AND left_at IS NOT NULL) THEN
			RAISE EXCEPTION 'Não é possível atribuir dias a um responsável que saiu da família.'
				USING ERRCODE = 'check_violation';
		END IF;
		IF NEW.actual_parent_id IS NOT NULL
		   AND (TG_OP = 'INSERT' OR NEW.actual_parent_id IS DISTINCT FROM OLD.actual_parent_id)
		   AND EXISTS (SELECT 1 FROM public.profiles
		               WHERE id = NEW.actual_parent_id AND left_at IS NOT NULL) THEN
			RAISE EXCEPTION 'Não é possível atribuir dias a um responsável que saiu da família.'
				USING ERRCODE = 'check_violation';
		END IF;
	END IF;

	today    := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	the_date := COALESCE(NEW.schedule_date, OLD.schedule_date);
	-- F-07: the lane is immutable (enforce_schedule_lane), so NEW and OLD agree.
	lane     := CASE WHEN TG_OP = 'DELETE' THEN OLD.child_id ELSE NEW.child_id END;
	fam      := COALESCE(NEW.family_id, OLD.family_id,
	                     (SELECT family_id FROM public.profiles WHERE id = NEW.scheduled_parent_id));

	-- F-39 (T-41: horizons from app_settings). Free plans up to N months ahead;
	-- premium up to M, the hard ceiling for all (not admin-bypassable). Grandfather:
	-- only NEW far-future writes are blocked.
	IF the_date > today
	   AND (TG_OP = 'INSERT'
	        OR (TG_OP = 'UPDATE' AND NEW.schedule_date IS DISTINCT FROM OLD.schedule_date)) THEN
		horizon_months := CASE WHEN public.is_premium(fam)
		                       THEN public.setting_int('calendar_months_premium', 24)
		                       ELSE public.setting_int('calendar_months_free', 6) END;
		IF the_date > (today + make_interval(months => horizon_months))::date THEN
			IF public.is_premium(fam) THEN
				RAISE EXCEPTION 'O calendário permite agendar no máximo % meses à frente.', horizon_months
					USING ERRCODE = 'check_violation';
			ELSE
				RAISE EXCEPTION 'O plano gratuito permite agendar até % meses à frente. Ative o Premium para planejar mais longe.', horizon_months
					USING ERRCODE = 'check_violation';
			END IF;
		END IF;
	END IF;

	SELECT bool_or(true), bool_or(target_profile_id = cur_profile_id)
	INTO is_frozen, is_target
	FROM public.swap_requests
	WHERE family_id = fam AND schedule_date = the_date
	  AND child_id IS NOT DISTINCT FROM lane
	  AND status IN ('pending', 'revert_pending');
	is_frozen := COALESCE(is_frozen, false);
	is_target := COALESCE(is_target, false);

	-- F-12: frozen days are untouchable, except by the pending request's target
	-- (who legitimately applies the calendar change while approving) or an admin.
	-- (F-40: frozen override stays a free Gestor power — not retroactive.)
	IF TG_OP IN ('UPDATE', 'DELETE') AND is_frozen AND NOT is_target AND NOT cur_is_admin THEN
		RAISE EXCEPTION 'Este dia tem uma solicitação pendente e não pode ser alterado.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- F-13 + F-40: past days are immutable, except the pending request's target
	-- (overdue workflow completion). Admin OVERRIDE of a past day is the
	-- Administrador (Premium) power: a free admin (Gestor) may fix only the last
	-- `override_free_days`; premium reaches back `override_premium_months`, which is
	-- the hard retroactive cap for everyone (beyond it, blocked even for premium).
	IF the_date < today AND NOT is_target THEN
		IF NOT cur_is_admin THEN
			RAISE EXCEPTION 'Dias passados não podem ser alterados.'
				USING ERRCODE = 'check_violation';
		ELSIF public.is_premium(fam) THEN
			IF the_date < (today - make_interval(months => public.setting_int('override_premium_months', 6)))::date THEN
				RAISE EXCEPTION 'Correções retroativas vão até % meses atrás.', public.setting_int('override_premium_months', 6)
					USING ERRCODE = 'check_violation';
			END IF;
		ELSE   -- free admin (Gestor): only the honest-fix window
			IF the_date < (today - make_interval(days => public.setting_int('override_free_days', 7)))::date THEN
				RAISE EXCEPTION 'O plano gratuito corrige apenas os últimos % dias. Ative o Premium para corrigir dias mais antigos (até % meses).',
					public.setting_int('override_free_days', 7), public.setting_int('override_premium_months', 6)
					USING ERRCODE = 'check_violation';
			END IF;
		END IF;
	END IF;

	-- S-09: the PLANNED schedule is immutable for regular users — changing the
	-- scheduled parent of an assigned day requires an admin (explicit, audited)
	-- or the pending revert's target restoring the pre-edit snapshot (F-26).
	-- (F-40: changing a FUTURE planned parent stays a free Gestor power; a PAST one
	-- is already gated by the tier-aware past-day check above.)
	IF TG_OP = 'UPDATE'
	   AND NEW.scheduled_parent_id IS DISTINCT FROM OLD.scheduled_parent_id
	   AND NOT cur_is_admin AND NOT is_target THEN
		RAISE EXCEPTION 'O responsável planejado só pode ser alterado por administradores; para mudar quem fica com a criança, use o fluxo de troca.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF TG_OP = 'DELETE' THEN
		-- F-12: a day with an approved swap cannot be deleted (admin may — F-14).
		IF OLD.actual_parent_id IS NOT NULL AND OLD.actual_parent_id <> OLD.scheduled_parent_id
		   AND NOT cur_is_admin AND NOT is_target THEN
			RAISE EXCEPTION 'Dias com troca aprovada não podem ser apagados.'
				USING ERRCODE = 'check_violation';
		END IF;
		-- QA (July 2026): clearing an assigned day is admin-only — otherwise a
		-- regular member deletes + recreates the day with anyone, bypassing the
		-- S-09 planned-parent rule. The workflow target keeps its exemption.
		IF NOT cur_is_admin AND NOT is_target THEN
			RAISE EXCEPTION 'Um dia já planejado só pode ser limpo por um administrador.'
				USING ERRCODE = 'check_violation';
		END IF;
		RETURN OLD;
	END IF;

	-- Swap-workflow enforcement (applies to admins too — F-14 decision):
	-- creating or undoing a swap directly is forbidden; only the pending
	-- request's target (applying an approval) may write such a change.
	-- Exception: admins may correct the actual parent of PAST days (historical
	-- fixes — the workflow cannot exist for past dates), never future ones. The
	-- retroactive reach was already tier-gated by the past-day check above.
	IF cur_is_admin AND the_date < today THEN
		RETURN NEW;
	END IF;

	IF TG_OP = 'INSERT' THEN
		IF NEW.actual_parent_id IS NOT NULL AND NEW.actual_parent_id <> NEW.scheduled_parent_id THEN
			RAISE EXCEPTION 'Alterações do responsável real devem passar pelo fluxo de aprovação.'
				USING ERRCODE = 'check_violation';
		END IF;
	ELSIF NEW.actual_parent_id IS DISTINCT FROM OLD.actual_parent_id AND NOT is_target THEN
		IF (OLD.actual_parent_id IS NOT NULL AND OLD.actual_parent_id <> OLD.scheduled_parent_id)  -- undo/alter an approved swap
		   OR (NEW.actual_parent_id IS NOT NULL AND NEW.actual_parent_id <> NEW.scheduled_parent_id) -- create a swap directly
		THEN
			RAISE EXCEPTION 'Alterações do responsável real devem passar pelo fluxo de aprovação.'
				USING ERRCODE = 'check_violation';
		END IF;
	END IF;

	RETURN NEW;
END;
$function$;

-- 5d. F-61/F-51 — the audit row names its lane, and is_target reads the lane.
CREATE OR REPLACE FUNCTION public.audit_care_schedule_changes()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
	actor_id           bigint;
	actor_admin        boolean := false;
	is_target          boolean := false;
	fam                bigint;
	the_date           date;
	lane               bigint;
	sched_parent       bigint;
	actual_parent      bigint;
	sched_has_account  boolean;
	actual_has_account boolean;
	admin_override     boolean := false;
	ctx                jsonb;
	batch_id           text;
	batch_kind         text;
BEGIN
	SELECT id, is_admin INTO actor_id, actor_admin
	FROM public.profiles WHERE user_id = auth.uid();

	fam      := COALESCE(NEW.family_id, OLD.family_id);
	the_date := COALESCE(NEW.schedule_date, OLD.schedule_date);
	lane     := CASE WHEN TG_OP = 'DELETE' THEN OLD.child_id ELSE NEW.child_id END;

	-- The assignees the row names after the write — or, for a DELETE, the ones
	-- it named when it went (the fact is about the day as recorded).
	sched_parent  := CASE WHEN TG_OP = 'DELETE' THEN OLD.scheduled_parent_id ELSE NEW.scheduled_parent_id END;
	actual_parent := CASE WHEN TG_OP = 'DELETE' THEN OLD.actual_parent_id    ELSE NEW.actual_parent_id    END;

	SELECT (user_id IS NOT NULL) INTO sched_has_account
	FROM public.profiles WHERE id = sched_parent;
	IF actual_parent IS NOT NULL THEN
		SELECT (user_id IS NOT NULL) INTO actual_has_account
		FROM public.profiles WHERE id = actual_parent;
	END IF;

	-- The admin override, with the predicate enforce_day_protection uses to
	-- let the write through: an admin who is NOT the target of a pending
	-- request on this day (a target applying an approval, or restoring the
	-- pre-edit snapshot on a revert, acts inside the two-party workflow).
	IF actor_id IS NOT NULL AND actor_admin THEN
		SELECT COALESCE(bool_or(target_profile_id = actor_id), false) INTO is_target
		FROM public.swap_requests
		WHERE family_id = fam AND schedule_date = the_date
		  AND child_id IS NOT DISTINCT FROM lane
		  AND status IN ('pending', 'revert_pending');

		admin_override := NOT is_target AND (
			TG_OP = 'DELETE'
			OR (TG_OP = 'UPDATE'
			    AND (NEW.scheduled_parent_id IS DISTINCT FROM OLD.scheduled_parent_id
			         OR NEW.actual_parent_id IS DISTINCT FROM OLD.actual_parent_id)));
	END IF;

	-- A system write (service_role: auto-approval, migrations) has no actor,
	-- and the two actor facts stay NULL rather than false — "unknown" and
	-- "no" are different answers on a record.
	ctx := jsonb_strip_nulls(jsonb_build_object(
		'scheduled_parent_has_account', sched_has_account,
		'actual_parent_has_account',    actual_has_account,
		'actor_is_admin',               CASE WHEN actor_id IS NULL THEN NULL ELSE actor_admin END,
		'admin_override',               CASE WHEN actor_id IS NULL THEN NULL ELSE admin_override END));

	-- F-51: a range operation (clear_schedule_range / replace_schedule_range)
	-- announces itself through two transaction-local GUCs, so every row it
	-- writes carries the SAME batch id and the history can fold the batch into
	-- one entry. Absent for every other write — a single-day edit is not a
	-- batch of one. Clients cannot set a GUC through PostgREST, so a stamp here
	-- is always the RPC's own.
	batch_id   := NULLIF(current_setting('app.schedule_batch', true), '');
	batch_kind := NULLIF(current_setting('app.schedule_batch_kind', true), '');
	IF batch_id IS NOT NULL THEN
		ctx := ctx || jsonb_build_object('batch_id', batch_id, 'batch_kind', batch_kind);
	END IF;

	INSERT INTO public.activity_logs (
		schedule_id,
		affected_date,
		action,
		old_data,
		new_data,
		performed_by_id,
		family_id,
		context,
		child_id
	) VALUES (
		CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE NEW.id END,
		the_date,
		TG_OP,
		CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE to_jsonb(OLD) END,
		CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE to_jsonb(NEW) END,
		actor_id,
		fam,
		ctx,
		lane
	);

	IF TG_OP = 'DELETE' THEN
		RETURN OLD;
	END IF;
	RETURN NEW;
END;
$function$;

-- 5e. F-45 — the resolution log is the newest audit row of the SAME lane.
CREATE OR REPLACE FUNCTION public.stamp_swap_resolution_log()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    -- Trigger-owned column: whatever the client sent, carry the stored value
    -- through — a full-row PostgREST update can neither forge nor clear it.
    NEW.resolution_log_id := OLD.resolution_log_id;

    -- Stamp exactly once, on the resolution transition. The calendar write
    -- (care_schedules update / restore / delete-on-restore) already happened
    -- in both resolution paths, so its audit row exists and is the newest
    -- one for this family+date+lane since the request was created.
    IF OLD.status IN ('pending', 'revert_pending')
       AND NEW.status IN ('approved', 'revert_approved') THEN
        SELECT max(al.id) INTO NEW.resolution_log_id
        FROM public.activity_logs al
        WHERE al.family_id     = NEW.family_id
          AND al.affected_date = NEW.schedule_date
          AND al.child_id IS NOT DISTINCT FROM NEW.child_id
          AND al.created_at   >= OLD.created_at
          AND (OLD.pre_edit_log_id IS NULL OR al.id > OLD.pre_edit_log_id);
    END IF;

    RETURN NEW;
END;
$function$;


-- ── 6. remove_child refuses a child with a plan ─────────────────────────────
-- Body from 20260924100000 plus the refusal. A single-plan family's children
-- own no row, so nothing changes for them.

CREATE OR REPLACE FUNCTION public.remove_child(p_child_id bigint)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me public.profiles%ROWTYPE := public.child_admin_guard();
BEGIN
	IF EXISTS (SELECT 1 FROM public.care_schedules
	           WHERE child_id = p_child_id AND family_id = me.family_id) THEN
		RAISE EXCEPTION 'Esta criança tem dias no plano, e o histórico dela não pode ser apagado.'
			USING ERRCODE = 'check_violation';
	END IF;

	DELETE FROM public.children
	WHERE id = p_child_id AND family_id = me.family_id;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'Criança não encontrada na sua família.'
			USING ERRCODE = 'no_data_found';
	END IF;
END;
$$;

ALTER FUNCTION public.remove_child(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.remove_child(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_child(bigint) TO authenticated, service_role;


-- ── 7. The range operations take a lane ──────────────────────────────────────
-- `p_child_id` NULL = every lane of the family (in a single-plan family, the
-- only one); a child = that child's lane only. The frozen and D-1 predicates
-- read the row's own lane. New signatures, so the old ones are dropped: two
-- overloads would make PostgREST's named-argument call ambiguous.

DROP FUNCTION IF EXISTS public.clear_schedule_range(date, date);
CREATE OR REPLACE FUNCTION public.clear_schedule_range(p_from date, p_to date, p_child_id bigint DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
	me           public.profiles%ROWTYPE;
	today        date;
	v_from       date;
	batch        uuid;
	deleted      integer := 0;
	kept_frozen  integer := 0;
	kept_swap    integer := 0;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();
	IF me.id IS NULL THEN
		RAISE EXCEPTION 'Perfil não encontrado.' USING ERRCODE = 'check_violation';
	END IF;
	-- The same sentence the trigger raises for a single day, checked HERE so a
	-- non-admin is refused even over an empty range — a silent "0 deleted"
	-- would read as permission.
	IF NOT me.is_admin THEN
		RAISE EXCEPTION 'Um dia já planejado só pode ser limpo por um administrador.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
		RAISE EXCEPTION 'Intervalo de datas inválido.' USING ERRCODE = 'check_violation';
	END IF;

	today  := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	v_from := GREATEST(p_from, today);
	IF v_from > p_to THEN
		RETURN jsonb_build_object('deleted', 0, 'kept_frozen', 0, 'kept_swap', 0);
	END IF;

	-- What the WHERE below will spare, counted first so the numbers describe
	-- the same rows the DELETE saw. A frozen day counts as frozen even when it
	-- also holds an approved swap — the pending request is the stronger reason.
	SELECT
		COUNT(*) FILTER (WHERE frozen),
		COUNT(*) FILTER (WHERE NOT frozen AND swapped)
	INTO kept_frozen, kept_swap
	FROM (
		SELECT
			EXISTS (SELECT 1 FROM public.swap_requests s
			        WHERE s.family_id = d.family_id AND s.schedule_date = d.schedule_date
			          AND s.child_id IS NOT DISTINCT FROM d.child_id
			          AND s.status IN ('pending', 'revert_pending')) AS frozen,
			(d.actual_parent_id IS NOT NULL AND d.actual_parent_id <> d.scheduled_parent_id) AS swapped
		FROM public.care_schedules d
		WHERE d.family_id = me.family_id
		  AND (p_child_id IS NULL OR d.child_id = p_child_id)
		  AND d.schedule_date BETWEEN v_from AND p_to
	) k;

	batch := gen_random_uuid();
	PERFORM set_config('app.schedule_batch', batch::text, true);
	PERFORM set_config('app.schedule_batch_kind', 'clear_range', true);

	DELETE FROM public.care_schedules d
	WHERE d.family_id = me.family_id
	  AND (p_child_id IS NULL OR d.child_id = p_child_id)
	  AND d.schedule_date BETWEEN v_from AND p_to
	  AND NOT EXISTS (SELECT 1 FROM public.swap_requests s
	                  WHERE s.family_id = d.family_id AND s.schedule_date = d.schedule_date
	                    AND s.child_id IS NOT DISTINCT FROM d.child_id
	                    AND s.status IN ('pending', 'revert_pending'))
	  AND (d.actual_parent_id IS NULL OR d.actual_parent_id = d.scheduled_parent_id);
	GET DIAGNOSTICS deleted = ROW_COUNT;

	PERFORM set_config('app.schedule_batch', '', true);
	PERFORM set_config('app.schedule_batch_kind', '', true);

	RETURN jsonb_build_object(
		'deleted',     deleted,
		'kept_frozen', kept_frozen,
		'kept_swap',   kept_swap,
		'batch_id',    batch);
END;
$function$;

REVOKE ALL ON FUNCTION public.clear_schedule_range(date, date, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clear_schedule_range(date, date, bigint) TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.replace_schedule_range(date, date, jsonb);
CREATE OR REPLACE FUNCTION public.replace_schedule_range(p_from date, p_to date, p_days jsonb, p_child_id bigint DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
	me            public.profiles%ROWTYPE;
	today         date;
	v_from        date;
	batch         uuid;
	deleted       integer := 0;
	kept_frozen   integer := 0;
	kept_swap     integer := 0;
	inserted      integer := 0;
	offered       integer := 0;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();
	IF me.id IS NULL THEN
		RAISE EXCEPTION 'Perfil não encontrado.' USING ERRCODE = 'check_violation';
	END IF;
	IF NOT me.is_admin THEN
		RAISE EXCEPTION 'Um dia já planejado só pode ser limpo por um administrador.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
		RAISE EXCEPTION 'Intervalo de datas inválido.' USING ERRCODE = 'check_violation';
	END IF;
	IF p_days IS NULL OR jsonb_typeof(p_days) <> 'array' THEN
		RAISE EXCEPTION 'Lista de dias inválida.' USING ERRCODE = 'check_violation';
	END IF;
	-- A day outside the range would be planted on ground this call did not
	-- clear — a client bug, refused rather than half-honoured.
	IF EXISTS (
		SELECT 1 FROM jsonb_to_recordset(p_days) AS x(schedule_date date)
		WHERE x.schedule_date IS NULL OR x.schedule_date < p_from OR x.schedule_date > p_to
	) THEN
		RAISE EXCEPTION 'Todos os dias devem estar dentro do intervalo substituído.'
			USING ERRCODE = 'check_violation';
	END IF;
	-- F-07: the same rule for the lane — a day for another child would land
	-- in a lane this call did not clear.
	IF p_child_id IS NOT NULL AND EXISTS (
		SELECT 1 FROM jsonb_to_recordset(p_days) AS x(child_id bigint)
		WHERE x.child_id IS DISTINCT FROM p_child_id
	) THEN
		RAISE EXCEPTION 'Todos os dias devem ser da criança substituída.'
			USING ERRCODE = 'check_violation';
	END IF;

	today  := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	v_from := GREATEST(p_from, today);

	IF v_from <= p_to THEN
		SELECT
			COUNT(*) FILTER (WHERE frozen),
			COUNT(*) FILTER (WHERE NOT frozen AND swapped)
		INTO kept_frozen, kept_swap
		FROM (
			SELECT
				EXISTS (SELECT 1 FROM public.swap_requests s
				        WHERE s.family_id = d.family_id AND s.schedule_date = d.schedule_date
				          AND s.child_id IS NOT DISTINCT FROM d.child_id
				          AND s.status IN ('pending', 'revert_pending')) AS frozen,
				(d.actual_parent_id IS NOT NULL AND d.actual_parent_id <> d.scheduled_parent_id) AS swapped
			FROM public.care_schedules d
			WHERE d.family_id = me.family_id
			  AND (p_child_id IS NULL OR d.child_id = p_child_id)
			  AND d.schedule_date BETWEEN v_from AND p_to
		) k;
	END IF;

	batch := gen_random_uuid();
	PERFORM set_config('app.schedule_batch', batch::text, true);
	PERFORM set_config('app.schedule_batch_kind', 'replace_range', true);

	IF v_from <= p_to THEN
		DELETE FROM public.care_schedules d
		WHERE d.family_id = me.family_id
		  AND (p_child_id IS NULL OR d.child_id = p_child_id)
		  AND d.schedule_date BETWEEN v_from AND p_to
		  AND NOT EXISTS (SELECT 1 FROM public.swap_requests s
		                  WHERE s.family_id = d.family_id AND s.schedule_date = d.schedule_date
		                    AND s.child_id IS NOT DISTINCT FROM d.child_id
		                    AND s.status IN ('pending', 'revert_pending'))
		  AND (d.actual_parent_id IS NULL OR d.actual_parent_id = d.scheduled_parent_id);
		GET DIAGNOSTICS deleted = ROW_COUNT;
	END IF;

	-- Past days in p_days are dropped here, not refused: the wizard validates
	-- its start against the client's clock, and a plan generated at 23:59 must
	-- not fail at 00:00 over its first day. `family_id` is stamped by
	-- trigger_a from the scheduled parent's profile, as for every insert; the
	-- lane guard judges each day's `child_id` against the family's mode.
	SELECT COUNT(*) INTO offered
	FROM jsonb_to_recordset(p_days) AS x(schedule_date date)
	WHERE x.schedule_date >= today;

	INSERT INTO public.care_schedules (schedule_date, scheduled_parent_id, handoff_time, notes, child_id)
	SELECT x.schedule_date, x.scheduled_parent_id, x.handoff_time, x.notes, x.child_id
	FROM jsonb_to_recordset(p_days)
	     AS x(schedule_date date, scheduled_parent_id bigint, handoff_time time, notes text, child_id bigint)
	WHERE x.schedule_date >= today
	ORDER BY x.child_id NULLS FIRST, x.schedule_date
	ON CONFLICT (family_id, child_id, schedule_date) DO NOTHING;
	GET DIAGNOSTICS inserted = ROW_COUNT;

	PERFORM set_config('app.schedule_batch', '', true);
	PERFORM set_config('app.schedule_batch_kind', '', true);

	RETURN jsonb_build_object(
		'deleted',       deleted,
		'kept_frozen',   kept_frozen,
		'kept_swap',     kept_swap,
		'inserted',      inserted,
		'kept_existing', offered - inserted,
		'batch_id',      batch);
END;
$function$;

REVOKE ALL ON FUNCTION public.replace_schedule_range(date, date, jsonb, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.replace_schedule_range(date, date, jsonb, bigint) TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.set_handoff_time_range(date, date, time);
CREATE OR REPLACE FUNCTION public.set_handoff_time_range(p_from date, p_to date, p_time time without time zone, p_child_id bigint DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
	me             public.profiles%ROWTYPE;
	today          date;
	v_from         date;
	batch          uuid;
	updated        integer := 0;
	kept_frozen    integer := 0;
	kept_existing  integer := 0;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();
	IF me.id IS NULL THEN
		RAISE EXCEPTION 'Perfil não encontrado.' USING ERRCODE = 'check_violation';
	END IF;
	-- Refused before any row is read, even over an empty range: a silent
	-- "0 updated" would read as permission.
	IF NOT me.is_admin THEN
		RAISE EXCEPTION 'Só um administrador define o horário de troca de vários dias de uma vez.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF p_time IS NULL THEN
		RAISE EXCEPTION 'Informe o horário da troca.' USING ERRCODE = 'check_violation';
	END IF;
	IF p_from IS NULL OR (p_to IS NOT NULL AND p_to < p_from) THEN
		RAISE EXCEPTION 'Intervalo de datas inválido.' USING ERRCODE = 'check_violation';
	END IF;

	today  := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	v_from := GREATEST(p_from, today);
	IF p_to IS NOT NULL AND v_from > p_to THEN
		RETURN jsonb_build_object('updated', 0, 'kept_frozen', 0, 'kept_existing', 0);
	END IF;

	-- What the UPDATE below will leave alone, counted over the same rows it
	-- sees. A transition day that already has a time counts as existing even
	-- when it is also frozen — it would not be written either way.
	SELECT
		COUNT(*) FILTER (WHERE handoff_time IS NOT NULL),
		COUNT(*) FILTER (WHERE handoff_time IS NULL AND frozen)
	INTO kept_existing, kept_frozen
	FROM (
		SELECT
			d.handoff_time,
			EXISTS (SELECT 1 FROM public.swap_requests s
			        WHERE s.family_id = d.family_id AND s.schedule_date = d.schedule_date
			          AND s.child_id IS NOT DISTINCT FROM d.child_id
			          AND s.status IN ('pending', 'revert_pending')) AS frozen
		FROM public.care_schedules d
		LEFT JOIN public.care_schedules p
		       ON p.family_id = d.family_id AND p.schedule_date = d.schedule_date - 1
		      AND p.child_id IS NOT DISTINCT FROM d.child_id
		WHERE d.family_id = me.family_id
		  AND (p_child_id IS NULL OR d.child_id = p_child_id)
		  AND d.schedule_date >= v_from
		  AND (p_to IS NULL OR d.schedule_date <= p_to)
		  -- T-27, the trigger's own test: no D-1 row, or a different effective.
		  AND (p.id IS NULL
		       OR COALESCE(p.actual_parent_id, p.scheduled_parent_id)
		          IS DISTINCT FROM COALESCE(d.actual_parent_id, d.scheduled_parent_id))
	) k;

	batch := gen_random_uuid();
	PERFORM set_config('app.schedule_batch', batch::text, true);
	PERFORM set_config('app.schedule_batch_kind', 'handoff_range', true);

	UPDATE public.care_schedules d
	SET handoff_time    = p_time,
	    submitted_token = d.revision_token
	WHERE d.family_id = me.family_id
	  AND (p_child_id IS NULL OR d.child_id = p_child_id)
	  AND d.schedule_date >= v_from
	  AND (p_to IS NULL OR d.schedule_date <= p_to)
	  AND d.handoff_time IS NULL
	  AND NOT EXISTS (SELECT 1 FROM public.swap_requests s
	                  WHERE s.family_id = d.family_id AND s.schedule_date = d.schedule_date
	                    AND s.child_id IS NOT DISTINCT FROM d.child_id
	                    AND s.status IN ('pending', 'revert_pending'))
	  AND NOT EXISTS (SELECT 1 FROM public.care_schedules p
	                  WHERE p.family_id = d.family_id
	                    AND p.child_id IS NOT DISTINCT FROM d.child_id
	                    AND p.schedule_date = d.schedule_date - 1
	                    AND COALESCE(p.actual_parent_id, p.scheduled_parent_id)
	                        IS NOT DISTINCT FROM COALESCE(d.actual_parent_id, d.scheduled_parent_id));
	GET DIAGNOSTICS updated = ROW_COUNT;

	PERFORM set_config('app.schedule_batch', '', true);
	PERFORM set_config('app.schedule_batch_kind', '', true);

	RETURN jsonb_build_object(
		'updated',       updated,
		'kept_frozen',   kept_frozen,
		'kept_existing', kept_existing,
		'batch_id',      batch);
END;
$function$;

REVOKE ALL ON FUNCTION public.set_handoff_time_range(date, date, time, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_handoff_time_range(date, date, time, bigint) TO authenticated, service_role;
