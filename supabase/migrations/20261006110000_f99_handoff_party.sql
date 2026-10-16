-- =============================================================================
-- F-99 — only the two ends of a handoff (or an admin) change its time
--
-- Owner, 05/10/2026 (phase-3 chain): RESTRICT, do not notify. The
-- `handoff_time` of a day may be changed only by the two ends of that
-- handoff — the day's planned or real carer, and the previous day's effective
-- carer (who hands the child over) — or by an admin, whose direct write
-- already tells the people it touched (F-81). Everyone else uses the aviso.
-- Since the agenda (S-22) the day's note is frozen, so the time is the one
-- field of a day a third caregiver could still move behind both parents.
--
-- What stays as it is:
--   * INSERT (the wizard and a first plan) — the wizard is unchanged;
--   * `set_handoff_time_range` (admin only — an admin passes);
--   * the system: no caller profile (service role, the F-24 cron), the T-45
--     cascade (`app.handoff_cascade`), the purges (`app.deletion_context`) and
--     the F-07 mode switch;
--   * a write that does not change the time.
--
-- The refusal carries the marker `HANDOFF_PARTY:`, which `translateSaveError`
-- turns into the reader's language. An Android build older than this reads
-- the PT-BR sentence (owner: accepted).
--
-- `trigger_c_…`: after the family stamp, the lane and day protection, and
-- BEFORE `trigger_d_apply_handoff_transition_rule` — so it judges what the
-- caller asked for, not the T-27 parking that follows.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.enforce_handoff_party()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me        public.profiles%ROWTYPE;
	prev_carer bigint;
BEGIN
	IF NEW.handoff_time IS NOT DISTINCT FROM OLD.handoff_time THEN
		RETURN NEW;
	END IF;
	IF current_setting('app.handoff_cascade', true) = 'on'
	   OR current_setting('app.deletion_context', true) = 'on'
	   OR current_setting('app.schedule_mode_switch', true) = 'on' THEN
		RETURN NEW;
	END IF;

	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();
	IF me.id IS NULL OR me.is_admin THEN
		RETURN NEW;
	END IF;

	-- The two ends: whoever has (or was planned for) the day…
	IF me.id IN (OLD.scheduled_parent_id, OLD.actual_parent_id, NEW.actual_parent_id) THEN
		RETURN NEW;
	END IF;

	-- …and whoever has the day before, in the same lane (F-07).
	SELECT COALESCE(p.actual_parent_id, p.scheduled_parent_id) INTO prev_carer
	FROM public.care_schedules p
	WHERE p.family_id = OLD.family_id
	  AND p.child_id IS NOT DISTINCT FROM OLD.child_id
	  AND p.schedule_date = OLD.schedule_date - 1;
	IF prev_carer IS NOT NULL AND prev_carer = me.id THEN
		RETURN NEW;
	END IF;

	RAISE EXCEPTION 'HANDOFF_PARTY: Só quem entrega ou recebe a criança neste dia pode mudar o horário da entrega.'
		USING ERRCODE = 'check_violation';
END;
$$;

ALTER FUNCTION public.enforce_handoff_party() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.enforce_handoff_party() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_c_enforce_handoff_party ON public.care_schedules;
CREATE TRIGGER trigger_c_enforce_handoff_party
	BEFORE UPDATE ON public.care_schedules
	FOR EACH ROW
	EXECUTE FUNCTION public.enforce_handoff_party();

COMMENT ON FUNCTION public.enforce_handoff_party() IS
	'F-99: a day''s handoff_time changes only by its two ends (planned/real carer of the day, effective carer of D-1) or an admin.';
