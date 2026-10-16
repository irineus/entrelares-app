-- =============================================================================
-- F-77 (02/10/2026) — the Premium trial's end is told before it happens
--
-- Every new family gets the Premium trial (`families.trial_ends_at`, written by
-- the `trial.days` default since T-82) and falls back to the free plan in
-- silence: the badge "Premium até DD/MM" and the Histórico line "Período de
-- teste gratuito terminou" are the only traces, and the reader learns it when a
-- Premium gate appears. The days before the end are the best moment to sell,
-- and nothing spoke in them. Acquisition chain of October (owner, 02/10/2026).
--
-- Three moments, each said once per trial END (owner, 02/10/2026):
--
--   d7     the end's São Paulo day is 2..7 days away    in-app + push
--   d1     the end's day is today or tomorrow, still on  in-app + push
--   ended  the end instant has passed                    in-app + push
--
-- No e-mail (F-59, same day: e-mail only where nothing else reaches the
-- reader). Transactional — about the family's own service, no price, no
-- discount — so no opt-in, F-70's precedent.
--
-- NO BACKFILL (owner): `ended` is said only to a family that already heard a
-- `d7` or `d1` about the SAME end. A family whose trial ran out before this
-- migration has no ledger row and hears nothing; neither does one whose trial
-- the operator ends in the past by hand.
--
-- "Once" is keyed on the end itself: the ledger row is (family,
-- trial_ends_at, stage). The operator moving the end (console, `trial_ends_at`)
-- is a NEW end: the old D-1 never matches again and the new one is told from
-- its own D-7. A re-run the same day sends nothing new.
--
-- Recipients: the family's ADMINS with an account (`is_admin AND user_id IS
-- NOT NULL AND left_at IS NULL`). On both rails only an admin can subscribe:
-- `billing-checkout` refuses a non-admin with 403, and the plan page shows the
-- store offer to admins only (`premAdminOnly` otherwise). Telling a member
-- who cannot act is noise. A viewer (F-50) is never an admin.
--
-- Out: a family that pays on either rail — `plan = 'premium'` (the store rail
-- sets it through `set_family_plan`, Play's own free trial included) or a
-- subscription `active` / `scheduled` / `overdue` (F-46 lets a family pay
-- DURING the trial; that family already chose) — and a family with a pending
-- deletion request. `pending` (a checkout started, nobody paid) is still told:
-- that is the family closest to buying.
--
-- The day is São Paulo's, like every other clock of the product (F-24, F-60,
-- F-70). The job is pure SQL — no e-mail twin to send — so pg_cron calls the
-- function directly; no Edge Function, nothing for `functions.sh` to deploy.
-- =============================================================================

-- ── 1. The ledger ────────────────────────────────────────────────────────────

CREATE TABLE public.trial_end_reminders (
	family_id     bigint NOT NULL REFERENCES public.families (id) ON DELETE CASCADE,
	trial_ends_at timestamp with time zone NOT NULL,
	stage         text   NOT NULL CHECK (stage IN ('d7', 'd1', 'ended')),
	sent_at       timestamp with time zone NOT NULL DEFAULT timezone('utc', now()),
	PRIMARY KEY (family_id, trial_ends_at, stage)
);

COMMENT ON TABLE public.trial_end_reminders IS
	'F-77: one row per (family, trial end, stage) already told. Service role only. '
	'Also the success measure: a reminded family that subscribes by its trial end + 7 days converted.';

-- Nobody but the job reads or writes it: no policy, no grant.
ALTER TABLE public.trial_end_reminders ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.trial_end_reminders FROM anon, authenticated;

-- ── 2. The selection ─────────────────────────────────────────────────────────

-- `p_family_id` NULL (what the cron sends) scans every family. The DB gate
-- passes its throwaway family so a test never stamps or notifies another one.
CREATE OR REPLACE FUNCTION public.trial_end_reminders_due(p_family_id bigint DEFAULT NULL)
RETURNS TABLE (profile_id bigint, stage text, trial_end date)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	now_utc timestamp with time zone := now();
	today   date := (timezone('America/Sao_Paulo', now()))::date;
	r       record;
	v_stage text;
	v_date  text;
BEGIN
	FOR r IN
		SELECT f.id AS fam_id,
		       f.trial_ends_at AS ends_at,
		       (timezone('America/Sao_Paulo', f.trial_ends_at))::date AS end_day
		  FROM public.families f
		 WHERE f.trial_ends_at IS NOT NULL
		   AND f.plan <> 'premium'
		   -- Bounded: an `ended` is only ever owed to an end that a D-7 or D-1
		   -- already announced, so an end more than a week old has nothing left
		   -- to say and is not worth scanning.
		   AND f.trial_ends_at > now_utc - interval '7 days'
		   AND (p_family_id IS NULL OR f.id = p_family_id)
	LOOP
		IF r.ends_at <= now_utc THEN
			v_stage := 'ended';
		ELSIF r.end_day - today <= 1 THEN
			v_stage := 'd1';
		ELSIF r.end_day - today <= 7 THEN
			v_stage := 'd7';
		ELSE
			CONTINUE;
		END IF;

		-- Once per end and stage. A D-7 is also moot once the D-1 of the same
		-- end went out (a trial the operator shortened into its last day).
		IF EXISTS (
			SELECT 1 FROM public.trial_end_reminders x
			 WHERE x.family_id     = r.fam_id
			   AND x.trial_ends_at = r.ends_at
			   AND (x.stage = v_stage OR (v_stage = 'd7' AND x.stage = 'd1'))
		) THEN
			CONTINUE;
		END IF;

		-- No backfill: "ended" follows an announcement of the same end, or
		-- nothing.
		IF v_stage = 'ended' AND NOT EXISTS (
			SELECT 1 FROM public.trial_end_reminders x
			 WHERE x.family_id     = r.fam_id
			   AND x.trial_ends_at = r.ends_at
			   AND x.stage IN ('d7', 'd1')
		) THEN
			CONTINUE;
		END IF;

		-- A family that pays on the web rail during its trial (F-46) keeps
		-- `plan = 'free'` until the paid cycle starts; it already chose.
		IF EXISTS (
			SELECT 1 FROM public.subscriptions s
			 WHERE s.family_id = r.fam_id
			   AND s.status IN ('active', 'scheduled', 'overdue')
		) THEN
			CONTINUE;
		END IF;

		IF EXISTS (
			SELECT 1 FROM public.family_deletion_requests d
			 WHERE d.family_id = r.fam_id AND d.status = 'pending'
		) THEN
			CONTINUE;
		END IF;

		-- No admin with an account, no stamp: whoever claims the seat later is
		-- still told.
		IF NOT EXISTS (
			SELECT 1 FROM public.profiles p
			 WHERE p.family_id = r.fam_id
			   AND p.is_admin
			   AND p.left_at IS NULL
			   AND p.user_id IS NOT NULL
		) THEN
			CONTINUE;
		END IF;

		INSERT INTO public.trial_end_reminders (family_id, trial_ends_at, stage)
		VALUES (r.fam_id, r.ends_at, v_stage);

		v_date := to_char(r.end_day, 'DD/MM/YYYY');

		-- PT-BR sentences byte-identical to the catalog (U-13); the reader's
		-- device rebuilds them from `params` in its own language. The DATE,
		-- never the trial's length (U-57 / T-82).
		INSERT INTO public.notifications (recipient_profile_id, type, title, message, params)
		SELECT p.id, 'premium_trial',
		       CASE WHEN v_stage = 'ended'
		            THEN 'A avaliação Premium terminou'
		            ELSE 'A avaliação Premium termina em breve' END,
		       CASE WHEN v_stage = 'ended'
		            THEN 'A avaliação Premium da família terminou em ' || v_date ||
		                 '. A família segue no plano gratuito, e o Premium pode ser assinado a qualquer momento.'
		            ELSE 'A avaliação Premium da família vai até ' || v_date ||
		                 '. Para continuar com o Premium depois dessa data, veja o plano.' END,
		       jsonb_build_object(
		           'kind', CASE WHEN v_stage = 'ended' THEN 'ended' ELSE 'ending' END,
		           'date', to_char(r.end_day, 'YYYY-MM-DD'))
		  FROM public.profiles p
		 WHERE p.family_id = r.fam_id
		   AND p.is_admin
		   AND p.left_at IS NULL
		   AND p.user_id IS NOT NULL;

		RETURN QUERY
		SELECT p.id, v_stage, r.end_day
		  FROM public.profiles p
		 WHERE p.family_id = r.fam_id
		   AND p.is_admin
		   AND p.left_at IS NULL
		   AND p.user_id IS NOT NULL;
	END LOOP;
END;
$$;

ALTER FUNCTION public.trial_end_reminders_due(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.trial_end_reminders_due(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trial_end_reminders_due(bigint) TO service_role;


-- ── 3. Push: `premium_trial` ─────────────────────────────────────────────────
-- Nobody did anything: the trial is running out under the family, and the
-- admin who stopped opening the app is exactly who a row in the list never
-- reaches. Body copied VERBATIM from 20261002120000 (F-59) with the type
-- added; the filter keeps its literal list shape, which T-83's
-- `app_settings_cross_check` and the push mirror read.

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
	-- The cheap filter. Most inserts (receipts, family fan-out, billing) stop
	-- on this line and never touch pg_net.
	IF NEW.type NOT IN (
		'auto_reminder', 'auto_approved',
		'swap_requested', 'swap_approved', 'swap_rejected', 'swap_cancelled',
		'revert_requested', 'revert_approved', 'revert_rejected', 'revert_cancelled',
		'day_notice',
		'plan_ending',
		'agenda_notice', 'agenda_reminder',
		'expense_changed', 'settlement_requested', 'settlement_answered',
		'settlement_reminder',
		'chat_message',
		'member_joined', 'member_returned', 'account_deletion', 'family_deletion',
		'premium_trial'
	) THEN
		RETURN NULL;
	END IF;

	-- A row written before U-13 (or by a writer that forgot `params`) carries no
	-- render data, and the function would only drop it. Save the round trip.
	IF NEW.params IS NULL THEN
		RETURN NULL;
	END IF;

	-- F-59: the membership types carry several wordings under one type, and
	-- only the ones about SOMEONE ELSE ring a phone — "push only what the
	-- recipient did not just do". The leaver's own confirmation, the
	-- requester's own receipt and the answers that go to the requester stay
	-- in-app (the first two also have an e-mail).
	IF NEW.type = 'account_deletion'
	   AND (NEW.params ->> 'kind') IS DISTINCT FROM 'other_left' THEN
		RETURN NULL;
	END IF;
	IF NEW.type = 'family_deletion' THEN
		IF (NEW.params ->> 'kind') IS NULL
		   OR (NEW.params ->> 'kind') NOT IN ('requested_other', 'refused', 'withdrawn', 'reminder') THEN
			RETURN NULL;
		END IF;
		-- A refusal and a withdrawal are written to EVERY member, the one who
		-- acted included. The request row was resolved in this same
		-- transaction, so the newest one resolved with this outcome names the
		-- actor; their own copy stays in-app.
		IF (NEW.params ->> 'kind') IN ('refused', 'withdrawn') AND EXISTS (
			SELECT 1
			FROM (
				SELECT r.resolved_by
				FROM public.family_deletion_requests r
				JOIN public.profiles p ON p.family_id = r.family_id
				WHERE p.id = NEW.recipient_profile_id
				  AND r.status = NEW.params ->> 'kind'
				ORDER BY r.resolved_at DESC NULLS LAST, r.id DESC
				LIMIT 1
			) latest
			WHERE latest.resolved_by = NEW.recipient_profile_id
		) THEN
			RETURN NULL;
		END IF;
	END IF;

	-- F-55: the agenda's creator chose "no push" for this item — the row is
	-- the in-app notice alone.
	IF NEW.params ->> 'push' = 'false' THEN
		RETURN NULL;
	END IF;

	-- T-83: the per-type kill switch. A muted type keeps its in-app row and
	-- its badge — only the phone stays quiet.
	IF public.setting_text('push.disabled_types', '[]')::jsonb ? NEW.type THEN
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
	-- row and the badge stand; only the interruption is lost.
	RAISE WARNING 'dispatch_push_notification failed for notification %: %', NEW.id, SQLERRM;
	RETURN NULL;
END;
$$;

-- ── 4. Schedule: daily at 09:00 in Brasília ──────────────────────────────────
-- 12:00 UTC, beside `plan-end-reminders-daily`: this row rings a phone, and a
-- reminder that wakes a parent at night is worse than none. No e-mail twin to
-- send, so the job is the function itself — no Edge Function and no Vault
-- read here (the push trigger reads its own). cron.schedule upserts by name,
-- so a re-run is safe.

SELECT cron.schedule(
	'trial-end-reminders-daily',
	'0 12 * * *',
	$cron$ SELECT public.trial_end_reminders_due(); $cron$
);
