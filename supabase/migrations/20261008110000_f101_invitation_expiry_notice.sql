-- F-101 — the inviting admin is told, once, when an invitation expires.
--
-- Invitations expire in `invitation.valid_days` (7) and did so in silence: the
-- admin was never told the other parent had not joined, and after 30 days the
-- row was purged (S-15) and the card vanished. The second parent joining is
-- the activation step — the T-103 audit (04/10/2026) saw it stall quietly.
--
-- What this adds:
--   · `family_invitations.expiry_notified_at` — the ledger. Once per
--     invitation; a resend is a NEW row (create_invitation revokes the old
--     one), so a renewed link that expires again is told again, which is right.
--   · `invitation_expiry_notices_due(p_family_id)` — writes ONE `notifications`
--     row to the inviter (`invited_by`), when they still have an account and
--     have not left; the family's pending deletion silences it; nothing for an
--     accepted or revoked invitation, nor for one older than the 30-day purge
--     window (its card is gone — the notice would point at nothing).
--     Params: `name` = the placeholder's name (F-56) or the e-mail. No e-mail
--     twin (F-59): push + in-app, and the row's action is "Compartilhar de
--     novo" — a WhatsApp link from the co-parent is what gets opened.
--   · `dispatch_push_notification` with the new type (body copied VERBATIM
--     from 20261003120000, F-81; the literal list shape is what the push
--     mirror and T-83's cross-check read).
--   · pg_cron `invitation-expiry-notices-daily`, 12:00 UTC (09:00 BRT), plain
--     SQL like F-78 — no Edge Function in the loop.

ALTER TABLE public.family_invitations
	ADD COLUMN IF NOT EXISTS expiry_notified_at timestamptz;

COMMENT ON COLUMN public.family_invitations.expiry_notified_at IS
	'F-101: when the inviting admin was told this invitation expired (invitation_expiry_notices_due). Once per row.';

CREATE OR REPLACE FUNCTION public.invitation_expiry_notices_due(p_family_id bigint DEFAULT NULL)
RETURNS TABLE (invitation_id bigint, profile_id bigint)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	r      record;
	v_name text;
BEGIN
	FOR r IN
		SELECT i.id, i.family_id, i.email, i.invited_by, i.profile_id
		  FROM public.family_invitations i
		 WHERE (p_family_id IS NULL OR i.family_id = p_family_id)
		   AND i.accepted_at IS NULL
		   AND i.revoked_at IS NULL
		   AND i.expires_at <= now()
		   AND i.expiry_notified_at IS NULL
		   -- The S-15 purge window: past it the card is gone too.
		   AND i.created_at > now() - interval '30 days'
		 ORDER BY i.id
	LOOP
		-- The inviter, still a live member with an account. Nobody else is
		-- told: the invitation is their reach-out.
		IF r.invited_by IS NULL OR NOT EXISTS (
			SELECT 1 FROM public.profiles p
			 WHERE p.id = r.invited_by
			   AND p.family_id = r.family_id
			   AND p.left_at IS NULL
			   AND p.user_id IS NOT NULL
		) THEN
			-- No reader, no stamp: an admin who returns is still told.
			CONTINUE;
		END IF;

		IF EXISTS (
			SELECT 1 FROM public.family_deletion_requests d
			 WHERE d.family_id = r.family_id AND d.status = 'pending'
		) THEN
			CONTINUE;
		END IF;

		-- F-56: the placeholder's name when there is one; the address otherwise.
		SELECT NULLIF(btrim(p.full_name), '') INTO v_name
		  FROM public.profiles p WHERE p.id = r.profile_id;
		v_name := coalesce(v_name, r.email);

		UPDATE public.family_invitations
		   SET expiry_notified_at = now()
		 WHERE id = r.id;

		-- PT-BR sentence byte-identical to the catalog (U-13); the reader's
		-- device rebuilds it from `params` in its own language.
		INSERT INTO public.notifications (recipient_profile_id, type, title, message, params)
		VALUES (r.invited_by, 'invitation_expired',
		        'O convite expirou',
		        '' || v_name || ' não respondeu ao convite e o link expirou. Compartilhe de novo — um link pelo WhatsApp costuma funcionar melhor.',
		        jsonb_build_object('kind', 'expired', 'name', v_name,
		                           'invitation_id', r.id));

		invitation_id := r.id;
		profile_id    := r.invited_by;
		RETURN NEXT;
	END LOOP;
END;
$$;

ALTER FUNCTION public.invitation_expiry_notices_due(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.invitation_expiry_notices_due(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.invitation_expiry_notices_due(bigint) TO service_role;

COMMENT ON FUNCTION public.invitation_expiry_notices_due(bigint) IS
	'F-101: tells the inviting admin, once per invitation (expiry_notified_at), that an open invitation expired — push + in-app, no e-mail. Skips accepted/revoked rows, rows past the 30-day purge window, inviters who left, and families with a pending deletion.';


-- ── Push: `invitation_expired` ───────────────────────────────────────────────
-- Body copied VERBATIM from 20261003120000 (F-81) with the type added.

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
		'premium_trial',
		'referral_reward',
		'day_admin_change',
		'invitation_expired'
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


-- ── Daily, in plain SQL (the F-78 shape) ────────────────────────────────────
SELECT cron.schedule(
	'invitation-expiry-notices-daily',
	'0 12 * * *',
	$cron$ SELECT public.invitation_expiry_notices_due(); $cron$
);
