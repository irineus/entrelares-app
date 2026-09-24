-- =============================================================================
-- F-55 (PR 2, fix) — the observation guard runs as its owner
--
-- `freeze_day_observation` (20260924110000) reads the flag through
-- `setting_bool`, which no client role may execute. As a plain trigger function
-- it ran as the CALLER, so every client write to care_schedules failed with
-- "permission denied for function setting_bool" — flag on or off. SECURITY
-- DEFINER, like every other reader of app_settings, fixes it; the body is the
-- same.
--
-- A NEW migration on purpose: 20260924110000 was already applied to the dev
-- project by the PR's db-gate, and `db push` never re-runs an applied version.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.freeze_day_observation()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
	IF public.setting_bool('feature.child_agenda', false)
	   AND NEW.notes IS DISTINCT FROM (CASE WHEN TG_OP = 'UPDATE' THEN OLD.notes END) THEN
		RAISE EXCEPTION 'A observação do dia virou a agenda. Use a agenda do dia para escrever uma nota.'
			USING ERRCODE = 'check_violation';
	END IF;
	RETURN NEW;
END;
$$;

ALTER FUNCTION public.freeze_day_observation() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.freeze_day_observation() FROM PUBLIC, anon, authenticated;
