-- =============================================================================
-- U-55 — one handoff time for every future transition day, in ONE statement.
--
-- Field evidence (21/09/2026): family 19 planned 365 days with no handoff
-- time at all, and only 5 of the 10 families with a schedule carry one on any
-- day. Without it the urgency (F-22), the F-24/F-60 deadline and the F-52
-- estimate are all anchored at MIDNIGHT of the day — never the real handoff.
-- The wizard now asks (U-55 PR 1); this is the one-step fix for the plans
-- already written: the admin picks a time, and every FUTURE TRANSITION day
-- that has none gets it.
--
-- The shape is F-51's (`clear_schedule_range`), on purpose:
--   · SECURITY INVOKER — `enforce_day_protection`, the T-35 guard and RLS
--     judge every row as the caller, exactly as a single-day edit;
--   · the floor is today (America/Sao_Paulo), for every tier: a bulk action
--     never rewrites the past;
--   · a frozen day (pending / revert_pending request) is spared by the WHERE
--     and reported by reason, never handed to the trigger;
--   · the batch announces itself through the transaction-local GUCs, so the
--     Histórico folds it into ONE entry (`batch_kind = 'handoff_range'`).
--
-- What it writes, decided with the owner (22/09/2026):
--   · ONLY transition days (T-27: the effective responsible differs from
--     D-1's, or there is no D-1 row) — a non-transition day is not touched at
--     all, so it gains neither a parked `handoff_time_backup` nor an audit row;
--   · ONLY days WITHOUT a time — a time someone set on purpose is kept and
--     counted (`kept_existing`), never overwritten;
--   · admin-only, WITHOUT the admin-mode bypass: `handoff_time` is not a
--     protected field (any member already sets it on a day or in the bulk
--     edit), so asking to turn the mode on would be ceremony. The check is
--     here, raised before any row is looked at, like F-51's.
--
-- The transition test reads the table BEFORE the UPDATE; writing a handoff
-- time never changes an effective responsible, so no row's transition status
-- moves during the statement and the T-45 cascade stays silent (it fires only
-- on a change of responsible). `trigger_d` still re-applies the rule to every
-- updated row — it remains the authority; the WHERE only avoids asking it.
--
-- T-35: an UPDATE by a client must echo the row's `revision_token`. The RPC
-- echoes the token of the row it is reading in the same statement — it writes
-- a value, not a read-modify-write of state the client held, so there is no
-- stale copy to protect.
--
-- p_to NULL = no upper bound ("all future transition days"); the F-39 horizon
-- already bounds what exists.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_handoff_time_range(p_from date, p_to date, p_time time)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public'
AS $$
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
			          AND s.status IN ('pending', 'revert_pending')) AS frozen
		FROM public.care_schedules d
		LEFT JOIN public.care_schedules p
		       ON p.family_id = d.family_id AND p.schedule_date = d.schedule_date - 1
		WHERE d.family_id = me.family_id
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
	  AND d.schedule_date >= v_from
	  AND (p_to IS NULL OR d.schedule_date <= p_to)
	  AND d.handoff_time IS NULL
	  AND NOT EXISTS (SELECT 1 FROM public.swap_requests s
	                  WHERE s.family_id = d.family_id AND s.schedule_date = d.schedule_date
	                    AND s.status IN ('pending', 'revert_pending'))
	  AND NOT EXISTS (SELECT 1 FROM public.care_schedules p
	                  WHERE p.family_id = d.family_id
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
$$;

REVOKE ALL ON FUNCTION public.set_handoff_time_range(date, date, time) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_handoff_time_range(date, date, time) TO authenticated, service_role;

COMMENT ON FUNCTION public.set_handoff_time_range(date, date, time) IS
	'U-55: sets p_time on the caller''s family''s TRANSITION days in [p_from, p_to] (p_to NULL = no bound; floored to today) that have no handoff time, in ONE statement, as the caller. Frozen days and days that already have a time are kept and counted. Admin-only, no admin-mode bypass needed. Returns {updated, kept_frozen, kept_existing, batch_id}.';
