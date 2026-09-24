-- =============================================================================
-- F-55 (PR 3, fix) — no plan means no routine
--
-- `agenda_plan_end` (20260924120000) clamped the last planned day with
-- LEAST(last_day, horizon). Postgres' LEAST IGNORES a NULL argument, so a
-- family with no planned day at all got the whole tier horizon back, and a
-- routine was written over months nobody had planned. The gate caught it
-- ("with nothing planned from that day on, the routine is refused").
--
-- A NEW migration on purpose: 20260924120000 was already applied to the dev
-- project by the PR's db-gate, and `db push` never re-runs an applied version.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.agenda_plan_end(p_family_id bigint, p_from date)
RETURNS date
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	today   date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	months  int  := CASE WHEN public.is_premium(p_family_id)
	                     THEN public.setting_int('calendar_months_premium', 24)
	                     ELSE public.setting_int('calendar_months_free', 6) END;
	last_day date;
BEGIN
	SELECT max(schedule_date) INTO last_day
	FROM public.care_schedules
	WHERE family_id = p_family_id;

	-- Nothing planned: nothing to reach. Checked BEFORE the clamp, because
	-- LEAST(NULL, x) is x.
	IF last_day IS NULL THEN
		RETURN NULL;
	END IF;

	last_day := LEAST(last_day, (today + make_interval(months => months))::date);
	IF last_day < p_from THEN
		RETURN NULL;
	END IF;
	RETURN last_day;
END;
$$;

ALTER FUNCTION public.agenda_plan_end(bigint, date) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.agenda_plan_end(bigint, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.agenda_plan_end(bigint, date) TO service_role;
