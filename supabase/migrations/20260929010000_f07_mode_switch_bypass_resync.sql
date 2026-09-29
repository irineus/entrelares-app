-- =============================================================================
-- F-07 — resync: the plan-mode switch's bypass in `enforce_day_protection`
--
-- 20260928210000 (PR 2) was applied to the DEV project by its PR's first
-- run; the `app.schedule_mode_switch` bypass was added to that SAME file in a
-- second push, and a migration version already recorded is never re-applied —
-- so DEV kept the body WITHOUT the bypass while production (applied once, at
-- merge, from the final file) has it. On DEV, switching a family with an
-- approved swap from today on to a plan per child failed with "Alterações do
-- responsável real devem passar pelo fluxo de aprovação." (owner, QA,
-- 29/09/2026).
--
-- Idempotent: inserts the bypass only where it is missing, right before the
-- "System context" check, exactly as 20260928210000 places it. Production
-- already has it, so there it changes nothing. Fails loudly if the anchor is
-- gone (a later rewrite must carry the bypass itself).
-- =============================================================================

DO $$
DECLARE
	def    text := pg_get_functiondef('public.enforce_day_protection()'::regprocedure);
	anchor text := E'\t-- System context (service_role: F-24 auto-approval, migrations): unrestricted.\n';
	bypass text := E'\t-- F-07: the plan-mode switch (`set_schedule_mode`, PR 3) moves the plan\n'
	            || E'\t-- from today on between lanes as ONE admin act — an approved swap''s day\n'
	            || E'\t-- is copied with its real parent, which a direct write could never do.\n'
	            || E'\t-- The RPC has already checked the flag, the admin, and that no request is\n'
	            || E'\t-- pending from today on; a client cannot set a GUC through PostgREST.\n'
	            || E'\tIF current_setting(''app.schedule_mode_switch'', true) = ''on'' THEN\n'
	            || E'\t\tRETURN CASE WHEN TG_OP = ''DELETE'' THEN OLD ELSE NEW END;\n'
	            || E'\tEND IF;\n\n';
BEGIN
	IF position('app.schedule_mode_switch' IN def) > 0 THEN
		RETURN;   -- already there (production)
	END IF;
	IF position(anchor IN def) = 0 THEN
		RAISE EXCEPTION 'F-07 resync: enforce_day_protection no longer has the anchor this migration inserts before';
	END IF;
	EXECUTE replace(def, anchor, bypass || anchor);
END;
$$;
