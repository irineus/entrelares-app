-- =============================================================================
-- S-22 — phase 6 goes live: the one material policy version, and the flags
--
-- The phase-6 chain (F-55 agenda, F-50 viewer, F-64 verifiable report, F-34
-- expenses, F-35 chat) shipped to main DARK: each module behind a `feature.*`
-- key seeded `false`, with the server refusing its writes while it is off.
-- This migration is the owner-reviewed switch, in the order that keeps every
-- step true:
--
--   1. the S-15 pair — `policy.current_version` / `policy.enforce_from` — for
--      the material version 2.0 of entrelares.app/privacidade (the landing is
--      promoted BEFORE this merge, so the text is visible when the app asks
--      for the accept). The client constants are the other half
--      (`PolicyVersions.current` / `.enforceFrom`), and the gate's reconsent
--      suite fails the build if the two drift. `enforce_from` = the
--      production publication + 15 days (legal review B-4);
--   2. the five flags ON — they stay afterwards as kill switches (T-84);
--   3. F-55's idempotent conversion of the days' observations into agenda
--      Notes, AFTER the agenda flag: with it on, the observation is frozen
--      (F-55's trigger), so nothing written between the two steps is lost.
--      Re-running is a no-op (ON CONFLICT on `source_schedule_id`).
--
-- The dates below are the publication the owner approved; if the publish
-- slips, the client constants, these two rows and the policy page's date move
-- together, in the same delivery.
-- =============================================================================

UPDATE public.app_settings
   SET value      = '2026-09-25',
       updated_at = timezone('utc'::text, now())
 WHERE key = 'policy.current_version';

UPDATE public.app_settings
   SET value      = '2026-10-10',
       updated_at = timezone('utc'::text, now())
 WHERE key = 'policy.enforce_from';

UPDATE public.app_settings
   SET value      = 'true',
       updated_at = timezone('utc'::text, now())
 WHERE key IN ('feature.child_agenda', 'feature.viewers', 'feature.report_attestation',
               'feature.expenses', 'feature.chat');

DO $$
DECLARE
	converted int;
BEGIN
	converted := public.convert_observations_to_agenda();
	RAISE NOTICE 'S-22: % observação(ões) do dia convertida(s) em Nota da agenda.', converted;
END $$;
