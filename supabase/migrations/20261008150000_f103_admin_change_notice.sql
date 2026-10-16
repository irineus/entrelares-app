-- F-103 (T-103 audit, 04/10/2026) — granting or removing admin is told to the
-- person it happens to.
--
-- Mom makes her ex admin so he can invite his mother; later he removes hers,
-- and she finds out when "Convidar" refuses her. The S-10 trigger writes the
-- change into `account_logs` and the Histórico (admin_granted/admin_revoked),
-- but nobody was TOLD.
--
-- What this changes:
--   · `set_member_admin` — copied VERBATIM from 20260909120000 (F-56, its
--     last definition), plus: when the bit actually CHANGES, for someone else
--     who has an account and has not left, ONE `notifications` row of type
--     `admin_changed` (params kind = granted|revoked, name = who did it).
--     PT-BR sentences byte-identical to the catalog (U-13); the reader's
--     device rebuilds them from `params` in its own language. No e-mail (F-59).
--   · `dispatch_push_notification` with the new type (body copied VERBATIM
--     from 20261008120000, F-102). It lands on "Todas" (PushRouting's
--     default), where the row is.

CREATE OR REPLACE FUNCTION public.set_member_admin(p_profile_id bigint, p_is_admin boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me     public.profiles%ROWTYPE;
	v_was  boolean;
	v_live boolean;
	v_name text;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();

	IF me.id IS NULL OR NOT me.is_admin THEN
		RAISE EXCEPTION 'Somente administradores da família podem alterar permissões.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- S-10: admin grants/revokes require a fresh password confirmation.
	IF NOT public.is_elevated() THEN
		RAISE EXCEPTION 'ELEVATION_REQUIRED: Confirme sua senha para alterar permissões de administrador.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	-- F-56: no account, no admin bit.
	IF p_is_admin AND EXISTS (SELECT 1 FROM public.profiles
	                          WHERE id = p_profile_id AND family_id = me.family_id
	                            AND user_id IS NULL AND left_at IS NULL) THEN
		RAISE EXCEPTION 'Um responsável que ainda não entrou no aplicativo não pode ser administrador.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- F-103: what the bit was, and whether there is someone to tell.
	SELECT is_admin, (user_id IS NOT NULL AND left_at IS NULL)
	  INTO v_was, v_live
	  FROM public.profiles
	 WHERE id = p_profile_id AND family_id = me.family_id;

	UPDATE public.profiles
	SET is_admin = p_is_admin
	WHERE id = p_profile_id AND family_id = me.family_id;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'Perfil não encontrado na sua família.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- F-103: the person it happened to is told — once per real change, never
	-- the actor themself (a self-revoke is their own act), never a seat with
	-- no account or a member who left.
	IF v_was IS DISTINCT FROM p_is_admin AND p_profile_id <> me.id AND v_live THEN
		v_name := coalesce(nullif(btrim(me.full_name), ''), 'Um membro da família');
		INSERT INTO public.notifications (recipient_profile_id, type, title, message, params)
		VALUES (
			p_profile_id, 'admin_changed',
			CASE WHEN p_is_admin THEN 'Você agora é administrador(a)'
			     ELSE 'Você deixou de ser administrador(a)' END,
			CASE WHEN p_is_admin
			     THEN v_name || ' tornou você administrador(a) da família.'
			     ELSE v_name || ' removeu a sua permissão de administrador(a) da família.' END,
			jsonb_build_object('kind', CASE WHEN p_is_admin THEN 'granted' ELSE 'revoked' END,
			                   'name', v_name));
	END IF;
END;
$$;


-- ── Push: `admin_changed` ────────────────────────────────────────────────────
-- Body copied VERBATIM from 20261008120000 (F-102) with the type added.

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
		'invitation_expired',
		'premium_request',
		'admin_changed'
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
