-- =============================================================================
-- F-07 (PR 6) — the plan per child, live in production
--
-- `feature.per_child_schedule` was seeded false in PR 2 (T-84: every module is
-- born dark). Everything it gates is in place: the lanes and the day rules
-- (PR 2), the switch (PR 3), the calendar, the day, the swaps and Hoje per
-- child (PR 4a/4b), the aviso, the agenda and the plan's end (PR 5a), the
-- child in every swap notification (PR 5b), the PDF, the aviso and the plan's
-- end in the app (PR 5c).
--
-- ORDER (the S-22 trap, one module over): the lane guard refuses a day with
-- no child in a per-child family, and an Android build that predates the
-- lanes writes exactly that. So this migration merges only AFTER the owner
-- promoted a build carrying PR 4a–5c to Play Production — a family switched
-- before that would lock out its own members' older phones.
--
-- No policy change: the plan per child stores no new datum (the child's
-- first name exists since F-55; `child_id` links two rows the family already
-- has), so no `PolicyVersions` bump (§3, S-15).
-- =============================================================================

UPDATE public.app_settings
SET value = 'true'
WHERE key = 'feature.per_child_schedule';
