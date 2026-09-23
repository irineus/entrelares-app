-- =============================================================================
-- F-70 (23/09/2026) — a family whose plan is running out is told so
--
-- Family 19 planned 365 days on 08/09 and has not touched the calendar since;
-- nothing in the product would speak to them until something broke. The first
-- trigger of the item is the most obviously useful one: the family's OWN plan
-- is ending. It is about the service the family uses, so it is transactional —
-- no opt-in, no marketing, nothing about price.
--
-- The plan's end is the LAST planned day, `max(schedule_date)` per family
-- (the UNIQUE (family_id, schedule_date) index serves it). Three moments, each
-- said once per plan end (owner, 23/09/2026):
--
--   d30    last day 8..30 days away   in-app + push
--   d7     last day 0..7 days away    in-app + push + e-mail
--   ended  last day already past      in-app + push + e-mail
--
-- `ended` is what reaches the families whose plan ran out BEFORE this item
-- (four in production on 23/09/2026, last days 17/08..22/09) — a D-30/D-7 rule
-- alone would never speak to them.
--
-- "Once" is keyed on the plan end itself: the ledger row is (family, last day,
-- stage). A family that plans further has a NEW last day, so the pending D-7 of
-- the old end simply never matches again (the card's "planning further cancels
-- the 7-day one") and the next cycle starts clean at the new D-30. Re-running
-- the job the same day sends nothing new.
--
-- Recipients: every active member with an account (`left_at IS NULL AND
-- user_id IS NOT NULL`) — any member may plan an empty day (the INSERT policy
-- on care_schedules is family-scoped, not admin-scoped), and the family-19
-- member who stopped opening the app is the one who pays. Pending placeholders
-- (F-56) have no account and no inbox. A family with a pending deletion request
-- is told nothing: planning months it asked to erase is the wrong advice.
--
-- The day is São Paulo's, like every other clock of the product (F-24, F-60).
-- =============================================================================

-- ── 1. The ledger ────────────────────────────────────────────────────────────

CREATE TABLE public.plan_end_reminders (
	family_id bigint NOT NULL REFERENCES public.families (id) ON DELETE CASCADE,
	plan_end  date   NOT NULL,
	stage     text   NOT NULL CHECK (stage IN ('d30', 'd7', 'ended')),
	sent_at   timestamp with time zone NOT NULL DEFAULT timezone('utc', now()),
	PRIMARY KEY (family_id, plan_end, stage)
);

COMMENT ON TABLE public.plan_end_reminders IS
	'F-70: one row per (family, last planned day, stage) already told. Service role only. '
	'Also the success measure: a reminded family whose max(schedule_date) later exceeds plan_end extended its plan.';

-- Nobody but the job reads or writes it: no policy, no grant.
ALTER TABLE public.plan_end_reminders ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.plan_end_reminders FROM anon, authenticated;

-- ── 2. The selection ─────────────────────────────────────────────────────────

-- `p_family_id` NULL (what the cron sends) scans every family. The DB gate
-- passes its throwaway family so a test never stamps or notifies a family
-- another suite is using in the shared dev project.
CREATE OR REPLACE FUNCTION public.plan_end_reminders_due(p_family_id bigint DEFAULT NULL)
RETURNS TABLE (profile_id bigint, stage text, plan_end date, send_email boolean)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	today   date := (timezone('America/Sao_Paulo', now()))::date;
	r       record;
	v_stage text;
BEGIN
	FOR r IN
		SELECT cs.family_id AS fam_id, max(cs.schedule_date) AS last_day
		  FROM public.care_schedules cs
		 WHERE p_family_id IS NULL OR cs.family_id = p_family_id
		 GROUP BY cs.family_id
	LOOP
		IF r.last_day < today THEN
			v_stage := 'ended';
		ELSIF r.last_day - today <= 7 THEN
			v_stage := 'd7';
		ELSIF r.last_day - today <= 30 THEN
			v_stage := 'd30';
		ELSE
			CONTINUE;
		END IF;

		-- Once per plan end and stage. A D-30 is also moot once the D-7 of the
		-- same end went out (a family first seen inside the last week gets the
		-- D-7 only, and must not get a late D-30 on top of it).
		IF EXISTS (
			SELECT 1 FROM public.plan_end_reminders x
			 WHERE x.family_id = r.fam_id
			   AND x.plan_end  = r.last_day
			   AND (x.stage = v_stage OR (v_stage = 'd30' AND x.stage = 'd7'))
		) THEN
			CONTINUE;
		END IF;

		IF EXISTS (
			SELECT 1 FROM public.family_deletion_requests d
			 WHERE d.family_id = r.fam_id AND d.status = 'pending'
		) THEN
			CONTINUE;
		END IF;

		-- No reader, no stamp: a family whose only members are placeholders or
		-- departed is left unmarked, so a member who joins later is still told.
		IF NOT EXISTS (
			SELECT 1 FROM public.profiles p
			 WHERE p.family_id = r.fam_id
			   AND p.left_at IS NULL
			   AND p.user_id IS NOT NULL
		) THEN
			CONTINUE;
		END IF;

		INSERT INTO public.plan_end_reminders (family_id, plan_end, stage)
		VALUES (r.fam_id, r.last_day, v_stage);

		-- The reliable channel, in the same transaction as the stamp. PT-BR
		-- sentences byte-identical to the catalog (U-13); the reader's device
		-- rebuilds them from `params` in its own language.
		INSERT INTO public.notifications (recipient_profile_id, type, title, message, params)
		SELECT p.id, 'plan_ending',
		       CASE WHEN v_stage = 'ended'
		            THEN 'O planejamento terminou'
		            ELSE 'O planejamento termina em breve' END,
		       CASE WHEN v_stage = 'ended'
		            THEN 'O último dia planejado foi ' || to_char(r.last_day, 'DD/MM/YYYY') ||
		                 '. Planeje os próximos meses no calendário.'
		            ELSE 'O planejamento da família vai até ' || to_char(r.last_day, 'DD/MM/YYYY') ||
		                 '. Planeje os próximos meses.' END,
		       jsonb_build_object(
		           'kind', CASE WHEN v_stage = 'ended' THEN 'ended' ELSE 'ending' END,
		           'date', to_char(r.last_day, 'YYYY-MM-DD'))
		  FROM public.profiles p
		 WHERE p.family_id = r.fam_id
		   AND p.left_at IS NULL
		   AND p.user_id IS NOT NULL;

		-- One row per recipient for the e-mail twin (D-7 and ended only).
		RETURN QUERY
		SELECT p.id, v_stage, r.last_day, v_stage <> 'd30'
		  FROM public.profiles p
		 WHERE p.family_id = r.fam_id
		   AND p.left_at IS NULL
		   AND p.user_id IS NOT NULL;
	END LOOP;
END;
$$;

ALTER FUNCTION public.plan_end_reminders_due(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.plan_end_reminders_due(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.plan_end_reminders_due(bigint) TO service_role;

-- ── 3. Push: the twelfth type ────────────────────────────────────────────────
-- It passes the "push only what the recipient did NOT just do" rule: nobody
-- did anything — the calendar is running out under them, and the person who
-- stopped opening the app is exactly who a notification row alone never
-- reaches. Copied VERBATIM from 20260918230000 with 'plan_ending' added.

CREATE OR REPLACE FUNCTION public.dispatch_push_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'vault'
AS $$
DECLARE
	base_url text;
	api_key  text;
BEGIN
	-- The cheap filter. Most inserts (receipts, family fan-out, membership,
	-- quota, billing) stop on this line and never touch pg_net.
	IF NEW.type NOT IN (
		'auto_reminder', 'auto_approved',
		'swap_requested', 'swap_approved', 'swap_rejected', 'swap_cancelled',
		'revert_requested', 'revert_approved', 'revert_rejected', 'revert_cancelled',
		'day_notice',
		'plan_ending'
	) THEN
		RETURN NULL;
	END IF;

	-- A row written before U-13 (or by a writer that forgot `params`) carries no
	-- render data, and the function would only drop it. Save the round trip.
	IF NEW.params IS NULL THEN
		RETURN NULL;
	END IF;

	SELECT decrypted_secret INTO base_url
	FROM vault.decrypted_secrets WHERE name = 'functions_base_url';

	SELECT decrypted_secret INTO api_key
	FROM vault.decrypted_secrets WHERE name = 'secret_key';

	-- Unarmed project: no Vault secrets, no push, no noise. This is the state of
	-- every environment until the runbook's § 11 is done.
	IF base_url IS NULL OR api_key IS NULL THEN
		RETURN NULL;
	END IF;

	-- S-16: the key goes on `apikey`, NEVER on Authorization — the new-model
	-- secret keys are not JWTs and the platform rejects them there.
	PERFORM net.http_post(
		url     := base_url || '/send-push-notification',
		headers := jsonb_build_object(
			'Content-Type', 'application/json',
			'apikey', api_key),
		body    := jsonb_build_object('notification_id', NEW.id),
		-- 30s, per the runbook's own cron rule: a cold isolate has taken over
		-- five seconds to boot (the send-auth-email incident), and a timeout
		-- here ABORTS the request — it would drop the push and log a failure
		-- for a function that was about to work. Nothing waits on this call.
		timeout_milliseconds := 30000
	);

	RETURN NULL;
EXCEPTION WHEN OTHERS THEN
	-- A push is never worth failing the write that earned it. The notification
	-- row, the badge and the e-mail all stand; only the interruption is lost.
	RAISE WARNING 'dispatch_push_notification failed for notification %: %', NEW.id, SQLERRM;
	RETURN NULL;
END;
$$;

-- ── 4. Schedule: daily at 09:00 in Brasília ──────────────────────────────────
-- 12:00 UTC. NOT inside `purge-deleted` (04:00 UTC = 01:00 BRT): this row
-- rings a phone, and a reminder that wakes a parent at one in the morning is
-- worse than none. The job only calls the Edge Function, which runs the RPC and
-- sends the e-mail twins; it reads the SAME Vault secrets the push trigger
-- reads, so both projects are armed already and no Dashboard job is needed.
-- An unarmed project (no secrets) makes the call fail in cron's own log and
-- nothing else. cron.schedule upserts by name, so a re-run is safe.

SELECT cron.schedule(
	'plan-end-reminders-daily',
	'0 12 * * *',
	$cron$
	SELECT net.http_post(
		url     := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'functions_base_url')
		           || '/plan-end-reminders',
		headers := jsonb_build_object(
			'Content-Type', 'application/json',
			'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'secret_key')),
		body    := '{}'::jsonb,
		timeout_milliseconds := 30000);
	$cron$
);
