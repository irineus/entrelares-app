-- F-102 — a non-admin who meets a Premium gate may tell the admins, once a day.
--
-- The T-103 audit (04/10/2026): Dad is not admin, Mom (admin) will not pay; he
-- wants the agenda or the PDF for court, and every gate ended on "A assinatura
-- é feita por um administrador da família" — no name, no next step. Owner,
-- 07/10/2026: NAME the admin(s) in the sentence and add "Avisar o
-- administrador" — a push + in-app notification to the family's admins ("Bruno
-- quer o Premium para a agenda da criança"), at most ONE per requester per
-- day, judged HERE. Who may pay does NOT change; no billing rail is touched
-- (`billing-checkout` keeps refusing a non-admin).
--
--   · `premium_requests` is the ledger (requester × São Paulo day); no client
--     grant — the RPC is the only writer and nobody reads it.
--   · `request_premium_from_admin(p_gate)` writes ONE `notifications` row per
--     live admin with an account, type `premium_request`, params `kind=ask`,
--     `name` (the requester) and `gate` (the F-79 token: chat, chat-export,
--     agenda, expenses, pdf — anything else is the generic `premium`). The
--     PT-BR sentence is byte-identical to the catalog (U-13); the reader's
--     device rebuilds it in its own language from `params`.
--   · `dispatch_push_notification` with the new type (body copied VERBATIM from
--     20261008110000, F-101 PR B; the literal list is what the push mirror and
--     T-83's cross-check read).

CREATE TABLE IF NOT EXISTS public.premium_requests (
	id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	family_id            bigint NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
	requester_profile_id bigint NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
	gate                 text   NOT NULL,
	created_at           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS premium_requests_requester_idx
	ON public.premium_requests (requester_profile_id, created_at DESC);

COMMENT ON TABLE public.premium_requests IS
	'F-102: one row per "Avisar o administrador" — the per-requester daily guard of request_premium_from_admin. No client grant.';

ALTER TABLE public.premium_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.premium_requests FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.premium_requests TO service_role;


CREATE OR REPLACE FUNCTION public.request_premium_from_admin(p_gate text DEFAULT NULL)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me      public.profiles%ROWTYPE;
	today   date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	v_gate  text;
	v_label text;
	v_name  text;
	told    int;
BEGIN
	SELECT * INTO me
	  FROM public.profiles
	 WHERE user_id = auth.uid()
	   AND left_at IS NULL;
	IF me.id IS NULL THEN
		RAISE EXCEPTION 'Sua conta não pode pedir o Premium.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	IF me.is_admin THEN
		RAISE EXCEPTION 'Você é administrador da família: a assinatura é feita por você, na página do plano.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF public.is_premium(me.family_id) THEN
		RAISE EXCEPTION 'A família já tem o Premium.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- One per requester per São Paulo day.
	IF EXISTS (
		SELECT 1 FROM public.premium_requests r
		 WHERE r.requester_profile_id = me.id
		   AND (r.created_at AT TIME ZONE 'America/Sao_Paulo')::date = today
	) THEN
		RAISE EXCEPTION 'Você já pediu o Premium hoje. Dá para pedir de novo amanhã.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- The F-79 gate tokens; anything else is the generic ask.
	v_gate := CASE WHEN p_gate IN ('chat', 'chat-export', 'agenda', 'expenses', 'pdf')
	               THEN p_gate ELSE 'premium' END;
	-- PT-BR label of what the gate guards — byte-identical to the catalog's
	-- `notifRender.premiumGate.*`.
	v_label := CASE v_gate
		WHEN 'chat'        THEN 'escrever na Conversa'
		WHEN 'chat-export' THEN 'exportar a Conversa em PDF'
		WHEN 'agenda'      THEN 'a agenda da criança'
		WHEN 'expenses'    THEN 'as despesas'
		WHEN 'pdf'         THEN 'o relatório em PDF'
		ELSE                    'a família'
	END;
	v_name := coalesce(nullif(btrim(me.full_name), ''), 'Um membro da família');

	INSERT INTO public.premium_requests (family_id, requester_profile_id, gate)
	VALUES (me.family_id, me.id, v_gate);

	INSERT INTO public.notifications (recipient_profile_id, type, title, message, params)
	SELECT p.id, 'premium_request',
	       'Pedido de Premium',
	       v_name || ' quer o Premium para ' || v_label || '.',
	       jsonb_build_object('kind', 'ask', 'name', v_name, 'gate', v_gate)
	  FROM public.profiles p
	 WHERE p.family_id = me.family_id
	   AND p.is_admin
	   AND p.left_at IS NULL
	   AND p.user_id IS NOT NULL
	   AND p.id <> me.id;
	GET DIAGNOSTICS told = ROW_COUNT;

	RETURN told;
END;
$$;

ALTER FUNCTION public.request_premium_from_admin(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.request_premium_from_admin(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_premium_from_admin(text) TO authenticated, service_role;

COMMENT ON FUNCTION public.request_premium_from_admin(text) IS
	'F-102: a non-admin member tells the family''s admins they want Premium (push + in-app, type premium_request, params kind/name/gate). Refuses an admin, a Premium family and a second ask on the same São Paulo day. Who may pay does not change.';


-- ── Push: `premium_request` ──────────────────────────────────────────────────
-- Body copied VERBATIM from 20261008110000 (F-101 PR B) with the type added.

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
		'premium_request'
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
