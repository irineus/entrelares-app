-- =============================================================================
-- F-52 (PR 3) — an aviso reaches the phone, and only the kind that asks
--
-- The whole value of this item is *arriving before the person leaves the
-- house*, so the case for push here is stronger than for anything else in the
-- product. But `day_notice` carries FOUR wordings under one type — the aviso
-- itself (info / pickup / keep), the two answers, and the cancellation — and
-- push routes by TYPE alone: `PushRouting.landingFor` takes a type and nothing
-- else, on both channels, because the web worker has no Dart to call.
--
-- So every pushable `day_notice` lands on "Para você", the tab that means
-- *there is something here for YOU to do*. A receipt landing there would open
-- an empty tab under a notice that said something happened — the exact
-- complaint that produced `PushRouting` on F-09's first device round.
--
-- The split therefore has to happen HERE, in the cheap filter, before the
-- round trip: **only `pickup` and `keep` are pushed.** A courtesy note ("só
-- avisando") is information — it raises the badge and sits in the list; an
-- answer and a cancellation are receipts for somebody who is already waiting
-- and will open the app. `push_notification_mirror_test` still reads the TYPE
-- list out of this filter and compares it with `PUSH_TYPES`, so the two cannot
-- drift; the `kind` guard is an extra refusal on top, never a replacement.
--
-- Copied VERBATIM from 20260828120000_f09_push_subscriptions.sql with only the
-- F-52 lines changed — the rule the day-protection trigger taught (eight
-- rewrites, one silent loss).
-- =============================================================================

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
		'day_notice'
	) THEN
		RETURN NULL;
	END IF;

	-- A row written before U-13 (or by a writer that forgot `params`) carries no
	-- render data, and the function would only drop it. Save the round trip.
	IF NEW.params IS NULL THEN
		RETURN NULL;
	END IF;

	-- F-52: of the four wordings this type carries, only the two that ASK for
	-- something earn an interruption — and they are the only two for which
	-- "Para você", the tab a push of this type opens, is the right place.
	IF NEW.type = 'day_notice'
	   AND COALESCE(NEW.params ->> 'kind', '') NOT IN ('pickup', 'keep') THEN
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
