-- =============================================================================
-- F-51 — clear planned days in one action: two range RPCs, SECURITY INVOKER.
--
-- When the arrangement between the parents changes, the old plan has to go and
-- a new one has to be generated. Until now that was a per-day DELETE in a loop
-- (hundreds of round trips, no atomicity: a failure halfway leaves half a plan)
-- and the wizard KEPT existing days, so re-planning over the old plan answered
-- "0 dias criados" and read as a bug.
--
-- Two entry points share one server-side operation (owner, Aug 2026):
--   · "Limpar mês" on the calendar → clear_schedule_range(today, end of month);
--   · the wizard's "substituir os dias já planejados" checkbox →
--     replace_schedule_range(start, end, generated days), ONE transaction.
--
-- Both are SECURITY INVOKER on purpose: `enforce_day_protection` keeps firing
-- per row AS THE CALLER, so the bulk path obeys exactly the rules of the
-- single-day path (admin-only clear, past-day immutability, frozen days,
-- approved-swap days), and RLS keeps scoping every row to the caller's family.
-- Inside a SECURITY DEFINER function `current_user` is the owner, which is
-- what would silently exempt the range from the T-35 guard and from the S-11
-- deletion-context escape's intent.
--
-- Rows the trigger would refuse are EXCLUDED by the WHERE rather than handed to
-- it: a RAISE aborts the whole statement, so one frozen day would block a
-- year's re-plan. The RPC returns what it kept, by reason, and the client
-- renders those numbers instead of a generic "done". The trigger stays the
-- authority — the WHERE only avoids offering it rows it would reject.
--
-- The past is NEVER touched, for every tier: `p_from` is floored to today
-- (America/Sao_Paulo, the trigger's own clock). F-40 lets an admin correct
-- past days one by one within a tier-dependent window; a bulk action must not
-- be able to rewrite history by accident, and the single-day editor is still
-- there for an honest retroactive fix. Stricter than the trigger, so the F-40
-- free/premium window can never be reached — let alone bypassed — from here.
-- The F-39 planning horizon is enforced by the trigger on every INSERT the
-- replace performs, exactly as for the wizard's plain inserts.
--
-- T-45 boundary, and a second reason for the single DELETE: the D+1 cascade
-- (`trigger_d_sync_next_day_handoff`) is AFTER ROW, and Postgres queues AFTER
-- triggers to the END of the statement. In one range DELETE every D+1 inside
-- the range is already gone when the cascade looks for it (`IF NOT FOUND →
-- RETURN NULL`), and only the day just after the range is touched — once. The
-- per-day loop fired it N times, each time rewriting a day about to be deleted.
--
-- The replace's INSERT is `ON CONFLICT DO NOTHING`: a frozen or approved-swap
-- day the WHERE spared still exists, and the generated day for that date would
-- collide on UNIQUE (family_id, schedule_date) and abort the transaction. Those
-- days are reported as kept. DO NOTHING (not DO UPDATE) — the conflict branch
-- of an upsert is an UPDATE judged by RLS against the row already there.
-- Inserted in date order: the T-45 BEFORE trigger reads D-1, and in a
-- row-level BEFORE trigger the rows already processed by the same statement
-- ARE visible, so the transition rule sees the plan as it is being written.
--
-- T-35: DELETE needs no revision-token echo — the guard triggers are BEFORE
-- INSERT / BEFORE UPDATE only. Stated so nobody assumes the opposite.
--
-- Audit volume: `activity_logs` takes one trigger-written row per deleted and
-- per inserted day — semantically right (what is erased is the PLAN, never the
-- history), but a year's re-plan is ~730 rows. Each RPC therefore announces
-- itself through two transaction-local GUCs and the audit trigger stamps
-- `batch_id` / `batch_kind` into the F-61 `context` column of every row it
-- writes, so the history screen can fold the batch into one entry. No new
-- column: `context` is exactly the place for facts stamped at write time.
--
-- Idempotent on purpose (`CREATE OR REPLACE`), so a pre-application through
-- the MCP leaves nothing for CI's `db push` to trip on.
-- =============================================================================

-- ── 1. The audit trigger learns the batch stamp ─────────────────────────────
-- Body copied VERBATIM from 20260909160824 (F-61), the LATEST definition of
-- this function (the baseline defined it, F-61 rewrote it once). The only
-- additions are the two `batch_*` declarations and the block that stamps them.

CREATE OR REPLACE FUNCTION public.audit_care_schedule_changes()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	actor_id           bigint;
	actor_admin        boolean := false;
	is_target          boolean := false;
	fam                bigint;
	the_date           date;
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
		context
	) VALUES (
		CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE NEW.id END,
		the_date,
		TG_OP,
		CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE to_jsonb(OLD) END,
		CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE to_jsonb(NEW) END,
		actor_id,
		fam,
		ctx
	);

	IF TG_OP = 'DELETE' THEN
		RETURN OLD;
	END IF;
	RETURN NEW;
END;
$$;


ALTER FUNCTION public.audit_care_schedule_changes() OWNER TO postgres;

-- ── 2. clear_schedule_range ─────────────────────────────────────────────────
-- Deletes the caller's family's planned days in [p_from, p_to], never before
-- today, never a frozen day (pending or revert_pending request), never a day
-- holding an approved swap. Returns the counts the confirmation renders.
CREATE OR REPLACE FUNCTION public.clear_schedule_range(p_from date, p_to date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public'
AS $$
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
			          AND s.status IN ('pending', 'revert_pending')) AS frozen,
			(d.actual_parent_id IS NOT NULL AND d.actual_parent_id <> d.scheduled_parent_id) AS swapped
		FROM public.care_schedules d
		WHERE d.family_id = me.family_id
		  AND d.schedule_date BETWEEN v_from AND p_to
	) k;

	batch := gen_random_uuid();
	PERFORM set_config('app.schedule_batch', batch::text, true);
	PERFORM set_config('app.schedule_batch_kind', 'clear_range', true);

	DELETE FROM public.care_schedules d
	WHERE d.family_id = me.family_id
	  AND d.schedule_date BETWEEN v_from AND p_to
	  AND NOT EXISTS (SELECT 1 FROM public.swap_requests s
	                  WHERE s.family_id = d.family_id AND s.schedule_date = d.schedule_date
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
$$;

REVOKE ALL ON FUNCTION public.clear_schedule_range(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clear_schedule_range(date, date) TO authenticated, service_role;

COMMENT ON FUNCTION public.clear_schedule_range(date, date) IS
	'F-51: deletes the caller''s family''s planned days in [p_from, p_to] (floored to today; frozen and approved-swap days kept) in ONE statement, as the caller. Admin-only. Returns {deleted, kept_frozen, kept_swap, batch_id}.';

-- ── 3. replace_schedule_range ───────────────────────────────────────────────
-- The wizard's "substituir os dias já planejados": clears [p_from, p_to] with
-- the rules above and inserts p_days — a jsonb array of
-- {schedule_date, scheduled_parent_id, handoff_time?, notes?}, every date
-- inside the range — in the SAME transaction. If any insert fails, the
-- statement aborts and the old plan is still there: a family with NO plan is
-- strictly worse than one with a stale plan.
CREATE OR REPLACE FUNCTION public.replace_schedule_range(p_from date, p_to date, p_days jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public'
AS $$
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
				          AND s.status IN ('pending', 'revert_pending')) AS frozen,
				(d.actual_parent_id IS NOT NULL AND d.actual_parent_id <> d.scheduled_parent_id) AS swapped
			FROM public.care_schedules d
			WHERE d.family_id = me.family_id
			  AND d.schedule_date BETWEEN v_from AND p_to
		) k;
	END IF;

	batch := gen_random_uuid();
	PERFORM set_config('app.schedule_batch', batch::text, true);
	PERFORM set_config('app.schedule_batch_kind', 'replace_range', true);

	IF v_from <= p_to THEN
		DELETE FROM public.care_schedules d
		WHERE d.family_id = me.family_id
		  AND d.schedule_date BETWEEN v_from AND p_to
		  AND NOT EXISTS (SELECT 1 FROM public.swap_requests s
		                  WHERE s.family_id = d.family_id AND s.schedule_date = d.schedule_date
		                    AND s.status IN ('pending', 'revert_pending'))
		  AND (d.actual_parent_id IS NULL OR d.actual_parent_id = d.scheduled_parent_id);
		GET DIAGNOSTICS deleted = ROW_COUNT;
	END IF;

	-- Past days in p_days are dropped here, not refused: the wizard validates
	-- its start against the client's clock, and a plan generated at 23:59 must
	-- not fail at 00:00 over its first day. `family_id` is stamped by
	-- trigger_a from the scheduled parent's profile, as for every insert.
	SELECT COUNT(*) INTO offered
	FROM jsonb_to_recordset(p_days) AS x(schedule_date date)
	WHERE x.schedule_date >= today;

	INSERT INTO public.care_schedules (schedule_date, scheduled_parent_id, handoff_time, notes)
	SELECT x.schedule_date, x.scheduled_parent_id, x.handoff_time, x.notes
	FROM jsonb_to_recordset(p_days)
	     AS x(schedule_date date, scheduled_parent_id bigint, handoff_time time, notes text)
	WHERE x.schedule_date >= today
	ORDER BY x.schedule_date
	ON CONFLICT (family_id, schedule_date) DO NOTHING;
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
$$;

REVOKE ALL ON FUNCTION public.replace_schedule_range(date, date, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.replace_schedule_range(date, date, jsonb) TO authenticated, service_role;

COMMENT ON FUNCTION public.replace_schedule_range(date, date, jsonb) IS
	'F-51: the wizard''s overwrite — clears [p_from, p_to] with clear_schedule_range''s rules and inserts p_days in the SAME transaction (ON CONFLICT DO NOTHING for the days it kept). Admin-only, as the caller. Returns {deleted, kept_frozen, kept_swap, inserted, kept_existing, batch_id}.';
