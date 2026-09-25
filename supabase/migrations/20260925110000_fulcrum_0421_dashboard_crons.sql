-- Fulcrum 04.2.1 (25/09/2026) — the two cron jobs that were created BY HAND in
-- the Dashboard (supabase/README.md §4.4/§4.5, F-24 and S-11) are born here.
--
-- Why now: Fulcrum's daily backup (04.2) restores schema and data, but
-- `cron.job` is not in the CLI dump — the jobs come back only through the
-- migrations. Every other job already does (billing-grace-downgrade,
-- plan-end-reminders-daily, agenda-reminders-minutely,
-- report-attestations-purge-daily); these two did not. A restore, or the
-- backend switch of Fulcrum 07.2, would have lost them in silence: pending
-- swaps would stop auto-approving after 48 h, and deleted accounts and families
-- would stop being purged (LGPD).
--
-- Name, schedule, target function, headers, body and timeout are the ones in
-- production's cron.job on 25/09/2026 (read-only SELECT). ONE deliberate
-- difference: the URL is read from Vault (`functions_base_url`) instead of the
-- literal `https://jptqbwfziyzlhlmoekzu.supabase.co/functions/v1` the Dashboard
-- job carried — on prod that secret IS that string, so the call is the same;
-- on dev a literal would have called PRODUCTION. It also drops the double slash
-- (`.co//functions`) the purge job had. The key comes from Vault
-- (`secret_key`, on `apikey`), as it already did — no key is written here.
--
-- cron.schedule upserts by name: on a project that already has the job (prod,
-- dev) this replaces its command in place, keeping the jobid; on a restored or
-- new project it creates it. An unarmed project (no Vault secrets) fails the
-- call in cron's own log and nothing else, like plan-end-reminders-daily.

-- F-24: swaps nobody answered in 48 h are approved on the hour.
SELECT cron.schedule(
	'auto-approve-expired-hourly',
	'0 * * * *',
	$cron$
	SELECT net.http_post(
		url     := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'functions_base_url')
		           || '/auto-approve-expired',
		headers := jsonb_build_object(
			'Content-Type', 'application/json',
			'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'secret_key')),
		body    := '{}'::jsonb,
		timeout_milliseconds := 30000);
	$cron$
);

-- S-11: accounts and families past their 30-day grace are hard-deleted daily,
-- 04:00 UTC (01:00 in Brasília, off-peak).
SELECT cron.schedule(
	'purge-deleted-daily',
	'0 4 * * *',
	$cron$
	SELECT net.http_post(
		url     := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'functions_base_url')
		           || '/purge-deleted',
		headers := jsonb_build_object(
			'Content-Type', 'application/json',
			'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'secret_key')),
		body    := '{}'::jsonb,
		timeout_milliseconds := 30000);
	$cron$
);
