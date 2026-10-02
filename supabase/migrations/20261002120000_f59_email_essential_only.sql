-- F-59 — e-mail only where nothing else can reach the reader; everything else
-- by push and in-app (owner, 02/10/2026, to open the product to a wider
-- audience without the per-account Resend allowance becoming the ceiling).
--
-- What stays e-mail lives in the Edge Functions (`send-auth-email`,
-- `send-swap-email` for the invitation, `send-account-email` for the sudo
-- code, the family-deletion request and its D-3 reminder, the farewell, the
-- Premium grace warning and the leaver's own confirmation, `send-support-request`).
-- This migration does the two database halves of the change.
--
-- 1. The membership notices earn a push. `member_joined`, `member_returned`,
--    `account_deletion` (kind `other_left`) and `family_deletion` (kinds
--    `requested_other`, `refused`, `withdrawn`, `reminder`) were e-mail +
--    in-app; the e-mail is gone for most of them, so the phone takes its
--    place. The rows already exist — F-09's single-writer rule means the
--    dispatcher only has to let them through. The type filter keeps
--    its literal list shape: T-83's `app_settings_cross_check` and the push mirror read
--    the list out of it.
--
-- 2. The F-38 monthly e-mail quota retires. It counted the swap e-mails and
--    the invitation, and with the swap e-mails gone it would only ration
--    invitations. The counter, its two functions and its three keys go; the
--    in-app `email_cap_*` rows already written stay as history and still
--    render (`NotificationRenderer` keeps their copy).

-- ── 1. The dispatcher (body from 20260925130000, F-34) ───────────────────────

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
		'member_joined', 'member_returned', 'account_deletion', 'family_deletion'
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

-- ── 2. The cross-key check without the e-mail cap rule (body from 20260928200000, F-07) ──

CREATE OR REPLACE FUNCTION public.app_settings_cross_check()
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	months_free      int := public.setting_int('calendar_months_free', 6);
	months_premium   int := public.setting_int('calendar_months_premium', 24);
	free_seats       int := public.setting_int('free_caregivers', 2);
	max_seats        int := public.setting_int('max_caregivers', 4);
	grace            int := public.setting_int('billing.grace_days', 7);
	grace_warning    int := public.setting_int('billing.grace_warning_days', 2);
	price_monthly    int := public.setting_int('billing.price_monthly_cents', 549);
	price_annual     int := public.setting_int('billing.price_annual_cents', 5490);
	override_free    int := public.setting_int('override_free_days', 7);
	override_premium int := public.setting_int('override_premium_months', 6);
	poll_degraded    int := public.setting_int('sync.poll_seconds_degraded', 25);
	poll_healthy     int := public.setting_int('sync.poll_seconds_healthy', 120);
	muted            jsonb;
	pushable         text;
	muted_type       text;
	anon_hourly      int := public.setting_int('support.anon_hourly', 3);
	anon_daily       int := public.setting_int('support.anon_daily', 10);
	member_hourly    int := public.setting_int('support.member_hourly', 5);
	member_daily     int := public.setting_int('support.member_daily', 20);
	agenda_notes     int := public.setting_int('agenda.free_notes_per_day', 1);
	agenda_max       int := public.setting_int('agenda.max_events_per_day', 20);
	viewers_free     int := public.setting_int('free_viewers', 1);
	viewers_max      int := public.setting_int('max_viewers', 4);
	children_free    int := public.setting_int('children.free_max', 1);
	children_max     int := public.setting_int('children.max_per_family', 6);
BEGIN
	IF months_free > months_premium THEN
		RAISE EXCEPTION 'calendar_months_free (%) precisa ser no máximo calendar_months_premium (%): o plano gratuito não planeja mais longe que o Premium.',
			months_free, months_premium
			USING ERRCODE = 'check_violation';
	END IF;

	IF free_seats > max_seats THEN
		RAISE EXCEPTION 'free_caregivers (%) precisa ser no máximo max_caregivers (%): o gratuito não inclui mais responsáveis que o teto.',
			free_seats, max_seats
			USING ERRCODE = 'check_violation';
	END IF;

	IF grace_warning >= grace THEN
		RAISE EXCEPTION 'billing.grace_warning_days (%) precisa ser menor que billing.grace_days (%): o aviso sai antes do rebaixamento, nunca no mesmo dia.',
			grace_warning, grace
			USING ERRCODE = 'check_violation';
	END IF;

	IF price_annual > 12 * price_monthly THEN
		RAISE EXCEPTION 'billing.price_annual_cents (%) precisa ser no máximo 12 × billing.price_monthly_cents (%): o anual não pode custar mais que doze meses.',
			public.app_settings_format(price_annual, 'cents_brl'),
			public.app_settings_format(12 * price_monthly, 'cents_brl')
			USING ERRCODE = 'check_violation';
	END IF;

	IF override_free > override_premium * 28 THEN
		RAISE EXCEPTION 'override_free_days (%) precisa ser no máximo override_premium_months × 28 (% dias): o gratuito não corrige mais para trás que o Premium.',
			override_free, override_premium * 28
			USING ERRCODE = 'check_violation';
	END IF;
	-- T-83: with the socket up the poll is a safety net, so it is either off
	-- (0) or never MORE frequent than the poll that stands in for a dead socket.
	IF poll_healthy <> 0 AND poll_healthy < poll_degraded THEN
		RAISE EXCEPTION 'sync.poll_seconds_healthy (%) precisa ser 0 (desligado) ou pelo menos sync.poll_seconds_degraded (%): com o socket de pé o poll nunca fica mais frequente que sem ele.',
			poll_healthy, poll_degraded
			USING ERRCODE = 'check_violation';
	END IF;

	-- T-83: `push.disabled_types` may only name a type the dispatcher pushes.
	-- The list is read from the dispatcher's OWN filter, so the twelve types
	-- keep one home (the push mirror tests pin it against push.ts).
	muted := public.setting_text('push.disabled_types', '[]')::jsonb;
	IF jsonb_typeof(muted) <> 'array' THEN
		RAISE EXCEPTION 'push.disabled_types precisa ser uma lista JSON de tipos, como ["swap_requested"].'
			USING ERRCODE = 'check_violation';
	END IF;
	pushable := substring(pg_get_functiondef('public.dispatch_push_notification()'::regprocedure)
	                      from 'NEW\.type NOT IN \(([^)]*)\)');
	FOR muted_type IN SELECT jsonb_array_elements_text(muted) LOOP
		IF pushable IS NULL OR position(quote_literal(muted_type) in pushable) = 0 THEN
			RAISE EXCEPTION 'push.disabled_types: "%" não é um tipo que gera push. Os tipos são os do filtro de dispatch_push_notification.', muted_type
				USING ERRCODE = 'check_violation';
		END IF;
	END LOOP;

	-- T-83: a support limit per hour never exceeds the one per day it lives in.
	IF anon_hourly > anon_daily THEN
		RAISE EXCEPTION 'support.anon_hourly (%) precisa ser no máximo support.anon_daily (%).', anon_hourly, anon_daily
			USING ERRCODE = 'check_violation';
	END IF;
	IF member_hourly > member_daily THEN
		RAISE EXCEPTION 'support.member_hourly (%) precisa ser no máximo support.member_daily (%).', member_hourly, member_daily
			USING ERRCODE = 'check_violation';
	END IF;

	-- F-55 (T-84 rule 2): a free family's notes per day never exceed what any
	-- day may hold at all.
	IF agenda_notes > agenda_max THEN
		RAISE EXCEPTION 'agenda.free_notes_per_day (%) precisa ser no máximo agenda.max_events_per_day (%).', agenda_notes, agenda_max
			USING ERRCODE = 'check_violation';
	END IF;

	IF viewers_free > viewers_max THEN
		RAISE EXCEPTION 'free_viewers (%) precisa ser no máximo max_viewers (%): o gratuito não inclui mais visualizadores que o teto.', viewers_free, viewers_max
			USING ERRCODE = 'check_violation';
	END IF;

	-- F-07: the free plan never registers more children than any family may.
	IF children_free > children_max THEN
		RAISE EXCEPTION 'children.free_max (%) precisa ser no máximo children.max_per_family (%): o gratuito não inclui mais crianças que o teto.', children_free, children_max
			USING ERRCODE = 'check_violation';
	END IF;
END;
$$;

-- ── 3. The F-38 quota leaves ─────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.consume_email_quota(bigint);
DROP FUNCTION IF EXISTS public.notify_family_email_cap(bigint, text, text, text, jsonb);
DROP FUNCTION IF EXISTS public.notify_family_email_cap(bigint, text, text, text);
DROP TABLE IF EXISTS public.email_usage;

DELETE FROM public.app_settings
WHERE key IN ('email_cap_free', 'email_cap_premium', 'email_quota.warn_percent');
