-- =============================================================================
-- F-80 (PR 3) — family referral: qualification, the reward, and its rail
--
-- PR 1 laid the referral down at sign-up (`family_referrals`, status
-- `attributed`). This PR walks the rest of the lifecycle, owner 02/10/2026:
--
--   attributed ──(first PAID payment of the referred family)──▶ paid
--        paid: first_paid_at = that payment's ledger instant,
--              qualifies_at  = first_paid_at + `referral.hold_days`
--   paid ──(refund / chargeback / Play revoke inside the window)──▶ cancelled
--   paid ──(qualifies_at passed, no reversal inside it)──▶ qualified
--   qualified ──▶ rewarded       the free month was delivered (notified)
--             ──▶ pending_rail   earned and counted, the rail still owes it
--             ──▶ capped         over `referral.yearly_cap` this year: terminal
--   pending_rail ──(the rail delivered)──▶ rewarded (notified then)
--   any open state ──(the referrer family no longer exists)──▶ cancelled
--
-- WHY `capped` IS A STATUS and not "qualified + a note": the cap is judged in
-- the calendar year the referral qualified. Left `qualified`, the next daily
-- run in January would find it under a fresh cap and pay it — a terminal
-- state is what keeps "over the cap, no reward" true forever. `pending_rail`
-- is a status for the opposite reason: it is a reward OWED (it counts toward
-- the cap and the operator must see it), not one decided against.
--
-- "Paid" is money that moved, so it is narrower than T-99's conversion: the
-- Asaas PAYMENT_CONFIRMED / PAYMENT_RECEIVED, a Play verification whose
-- `paymentState` is 1 (received — never 2, a Play free trial, never 0,
-- pending) and the Play renewals that charge (RTDN 1 RECOVERED, 2 RENEWED).
-- A reversal is any refund (`PAYMENT_REFUNDED`, `_PARTIALLY_REFUNDED`,
-- `_REFUND_IN_PROGRESS`), any Asaas chargeback event, or Play's RTDN 12
-- REVOKED — received at or after the first payment and BEFORE qualifies_at.
-- One after the window is accepted risk (owner): nothing is clawed back.
-- `qualifies_at` is recomputed from the CURRENT `referral.hold_days` while a
-- referral waits, as the key's own help promised in PR 1.
--
-- THE REWARD — one free month, delivered on the REFERRER's rail at reward time:
--
--   play         a Play subscription that still runs (or was canceled with
--                time left): Play owns the next charge, so only Play can
--                move it. `pending_rail` (`play_queued`); the Edge Function
--                `referral-rewards` defers the expiry by one month through the
--                Play Developer API and settles the row. Its own cron.
--   asaas        an Asaas subscription that will charge again (active,
--                overdue, scheduled): the next due date must move one month in
--                Asaas. The code base has no subscription-update call, and the
--                gate has no Asaas mock to prove one, so the owner's rule
--                applies — never improvise money movement: `pending_rail`
--                (`asaas_manual`). The operator moves the due date in Asaas and
--                records it with `referral_reward_delivered()`, which also moves
--                our `current_period_end` one month to match.
--   paid_period  a family whose paid time runs out with NO further charge
--                (an Asaas subscription canceled with time left, or an avulso
--                Pix — plan still premium): +30 days on `current_period_end`.
--                NOT the trial: the grace cron clears `trial_ends_at` when it
--                lapses the paid period, so a trial-shaped month would vanish
--                at exactly the moment it should start counting.
--   trial        everyone else — free, on the trial, a checkout started and
--                not paid: `trial_ends_at = greatest(trial_ends_at, now) + 30
--                days`. It is the Premium time `is_premium()` and the client's
--                EntitlementRules already read (and the one the operator
--                console moves); no new entitlement path. A comp or
--                grandfathered family gets it too, harmlessly.
--
-- The referred family gets nothing extra, and nothing is said to it.
--
-- THE NOTICE: one `referral_reward` row per active non-viewer member with an
-- account of the REFERRER family, written when the month is DELIVERED (a
-- pending reward promises nothing yet). Any caregiver may hold the code
-- (`my_referral_code`), so any caregiver may be the one who shared it — the
-- admin-only rule of F-77 is about who can subscribe, which this is not. Push
-- + in-app, no e-mail (F-59). `params` is `{"kind":"granted"}` and nothing
-- else: the referred family's id or name never reaches the referrer. A new
-- push type rather than a third kind of `premium_trial`: a paying family's
-- month is not a trial, and the T-83 mute switch must be able to silence one
-- without the other. The tap lands on the plan page, where the new end shows.
--
-- DARK: every function here does nothing (or refuses) while `feature.referral`
-- is off, and the Play Edge Function answers `skipped`.
-- =============================================================================

-- ── 1. The lifecycle columns ─────────────────────────────────────────────────

ALTER TABLE public.family_referrals
	DROP CONSTRAINT IF EXISTS family_referrals_status_check;

ALTER TABLE public.family_referrals
	ADD CONSTRAINT family_referrals_status_check CHECK (status IN (
		'attributed', 'paid', 'qualified', 'rewarded', 'pending_rail', 'capped', 'cancelled'));

ALTER TABLE public.family_referrals
	-- The referrer's rail, decided at reward time.
	ADD COLUMN reward_rail text
		CHECK (reward_rail IN ('trial', 'paid_period', 'asaas', 'play')),
	-- Why a `pending_rail` reward is not delivered yet (closed codes; the
	-- operator reads them). `play_in_flight` = a deferral was SENT and its
	-- outcome is unknown — the next run reconciles against Play, never resends
	-- blind.
	ADD COLUMN reward_pending_reason text
		CHECK (reward_pending_reason IN (
			'asaas_manual', 'play_queued', 'play_in_flight', 'play_not_configured',
			'play_permission_denied', 'play_no_subscription', 'play_not_found',
			'play_error')),
	-- Play's expiry before and after the deferral, in ms (strings, Google's
	-- shape). Nothing about either family.
	ADD COLUMN reward_detail jsonb,
	-- When the month actually reached the family. `rewarded_at` is when it was
	-- EARNED (and counted toward the cap), for `pending_rail` too.
	ADD COLUMN reward_delivered_at timestamp with time zone,
	ADD COLUMN cancel_reason text
		CHECK (cancel_reason IN ('refunded', 'chargeback', 'revoked', 'referrer_gone')),
	ADD CONSTRAINT family_referrals_reward_shape CHECK (
		(status <> 'rewarded'
		 OR (reward_rail IS NOT NULL AND rewarded_at IS NOT NULL AND reward_delivered_at IS NOT NULL))
		AND (status <> 'pending_rail'
		 OR (reward_rail IN ('asaas', 'play') AND rewarded_at IS NOT NULL
		     AND reward_pending_reason IS NOT NULL))
		AND (status <> 'cancelled' OR cancelled_at IS NOT NULL));

CREATE INDEX family_referrals_open_idx ON public.family_referrals (status)
	WHERE status IN ('attributed', 'paid', 'qualified', 'pending_rail');

COMMENT ON COLUMN public.family_referrals.rewarded_at IS
	'F-80 PR 3: when the reward was EARNED and counted toward referral.yearly_cap (rewarded or pending_rail). Delivery is reward_delivered_at.';


-- ── 2. The settings now have their reader ────────────────────────────────────
-- The cap is per CALENDAR year in São Paulo (owner, 02/10/2026), not the
-- rolling 12 months PR 1's text said.

UPDATE public.app_settings
   SET description = 'Máximo de meses grátis por indicação que uma família recebe por ano civil (F-80).',
       help = help || jsonb_build_object(
		'controls', 'Quantas recompensas (um mês grátis cada) uma mesma família que indica pode receber no mesmo ano civil (horário de São Paulo).',
		'takes_effect', 'Na próxima passada diária do job referral_rewards_due (12:00 UTC).',
		'caveats', 'Uma indicação qualificada além do teto fica "capped" para sempre: não ganha o mês nem no ano seguinte. Recompensas pendentes de trilho (Asaas/Play) contam no teto.')
 WHERE key = 'referral.yearly_cap';

UPDATE public.app_settings
   SET help = help || jsonb_build_object(
		'takes_effect', 'Na próxima passada diária do job referral_rewards_due (12:00 UTC), também para indicações que já esperam.',
		'caveats', 'Mudar com indicações em espera move a data delas também. Um estorno ou chargeback depois da janela não desfaz a recompensa (risco aceito).')
 WHERE key = 'referral.hold_days';


-- ── 3. The notice ────────────────────────────────────────────────────────────
-- PT-BR byte-identical to the catalog (U-13). "um mês" is the decided reward
-- unit, not an `app_settings` value, so it is written out (U-57's guard counts
-- typed digits and seeds of keys, neither of which this is).

CREATE OR REPLACE FUNCTION public.referral_reward_notify(p_referrer_family_id bigint)
RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
	INSERT INTO public.notifications (recipient_profile_id, type, title, message, params)
	SELECT p.id, 'referral_reward',
	       'Um mês de Premium pela indicação',
	       'Uma família que vocês indicaram assinou o Premium: a sua família ganhou um mês de Premium.',
	       jsonb_build_object('kind', 'granted')
	  FROM public.profiles p
	 WHERE p.family_id = p_referrer_family_id
	   AND p.left_at IS NULL
	   AND p.user_id IS NOT NULL
	   AND p.membership_type <> 'viewer';
END;
$$;

ALTER FUNCTION public.referral_reward_notify(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.referral_reward_notify(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.referral_reward_notify(bigint) TO service_role;


-- ── 4. The job ───────────────────────────────────────────────────────────────
-- `p_family_id` NULL (what the cron sends) walks every open referral. The DB
-- gate passes one of its throwaway families — a referral is in scope when that
-- family is its referrer OR its referred family — so a test never moves
-- another family's row. Returns counts only.

CREATE OR REPLACE FUNCTION public.referral_rewards_due(p_family_id bigint DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	now_utc   timestamp with time zone := now();
	this_year int := extract(year FROM timezone('America/Sao_Paulo', now()))::int;
	hold      int := public.setting_int('referral.hold_days', 30);
	cap       int := public.setting_int('referral.yearly_cap', 12);
	r         record;
	v_paid    timestamp with time zone;
	v_rev     text;
	v_q       timestamp with time zone;
	v_count   int;
	sub       public.subscriptions%ROWTYPE;
	fam       public.families%ROWTYPE;
	n_paid    int := 0;
	n_cancel  int := 0;
	n_qual    int := 0;
	n_reward  int := 0;
	n_pending int := 0;
	n_capped  int := 0;
BEGIN
	IF NOT public.setting_bool('feature.referral', false) THEN
		RETURN jsonb_build_object('skipped', 'dark');
	END IF;

	-- (a) The referrer is gone (ON DELETE SET NULL): nobody to reward.
	UPDATE public.family_referrals x
	   SET status = 'cancelled', cancelled_at = now_utc, cancel_reason = 'referrer_gone'
	 WHERE x.status IN ('attributed', 'paid', 'qualified')
	   AND x.referrer_family_id IS NULL
	   AND (p_family_id IS NULL OR x.referred_family_id = p_family_id);
	GET DIAGNOSTICS v_count = ROW_COUNT;
	n_cancel := n_cancel + v_count;

	-- (b) attributed → paid: the referred family's FIRST paid payment.
	FOR r IN
		SELECT * FROM public.family_referrals x
		 WHERE x.status = 'attributed'
		   AND (p_family_id IS NULL
		        OR x.referred_family_id = p_family_id OR x.referrer_family_id = p_family_id)
		 ORDER BY x.referred_family_id
		 FOR UPDATE
	LOOP
		SELECT min(e.received_at) INTO v_paid
		  FROM public.billing_events e
		 WHERE e.family_id = r.referred_family_id
		   AND (e.event_type IN ('PAYMENT_CONFIRMED', 'PAYMENT_RECEIVED', 'PLAY_RTDN_1', 'PLAY_RTDN_2')
		        OR (e.event_type = 'PLAY_PURCHASE_VERIFIED'
		            AND e.payload #>> '{purchase,paymentState}' = '1'));
		IF v_paid IS NOT NULL THEN
			UPDATE public.family_referrals
			   SET status = 'paid', first_paid_at = v_paid,
			       qualifies_at = v_paid + make_interval(days => hold)
			 WHERE referred_family_id = r.referred_family_id;
			n_paid := n_paid + 1;
		END IF;
	END LOOP;

	-- (c) paid: the window follows today's `referral.hold_days`; a reversal
	-- inside it cancels; a window that ran out clean qualifies.
	FOR r IN
		SELECT * FROM public.family_referrals x
		 WHERE x.status = 'paid'
		   AND (p_family_id IS NULL
		        OR x.referred_family_id = p_family_id OR x.referrer_family_id = p_family_id)
		 ORDER BY x.referred_family_id
		 FOR UPDATE
	LOOP
		v_q := r.first_paid_at + make_interval(days => hold);

		SELECT e.event_type INTO v_rev
		  FROM public.billing_events e
		 WHERE e.family_id = r.referred_family_id
		   AND e.received_at >= r.first_paid_at
		   AND e.received_at <  v_q
		   AND (e.event_type IN ('PAYMENT_REFUNDED', 'PAYMENT_PARTIALLY_REFUNDED',
		                         'PAYMENT_REFUND_IN_PROGRESS', 'PLAY_RTDN_12')
		        OR e.event_type LIKE '%CHARGEBACK%')
		 ORDER BY e.received_at, e.id
		 LIMIT 1;

		IF v_rev IS NOT NULL THEN
			UPDATE public.family_referrals
			   SET status = 'cancelled', cancelled_at = now_utc, qualifies_at = v_q,
			       cancel_reason = CASE WHEN v_rev LIKE '%CHARGEBACK%' THEN 'chargeback'
			                            WHEN v_rev = 'PLAY_RTDN_12' THEN 'revoked'
			                            ELSE 'refunded' END
			 WHERE referred_family_id = r.referred_family_id;
			n_cancel := n_cancel + 1;
		ELSIF v_q <= now_utc THEN
			UPDATE public.family_referrals
			   SET status = 'qualified', qualifies_at = v_q
			 WHERE referred_family_id = r.referred_family_id;
			n_qual := n_qual + 1;
		ELSE
			UPDATE public.family_referrals
			   SET qualifies_at = v_q
			 WHERE referred_family_id = r.referred_family_id
			   AND qualifies_at IS DISTINCT FROM v_q;
		END IF;
	END LOOP;

	-- (d) qualified → the reward, oldest first, one referrer's cap at a time.
	FOR r IN
		SELECT * FROM public.family_referrals x
		 WHERE x.status = 'qualified'
		   AND x.referrer_family_id IS NOT NULL
		   AND (p_family_id IS NULL
		        OR x.referred_family_id = p_family_id OR x.referrer_family_id = p_family_id)
		 ORDER BY x.qualifies_at, x.referred_family_id
		 FOR UPDATE
	LOOP
		-- Serialises two runs over the same referrer (the cap is a count).
		SELECT * INTO fam FROM public.families WHERE id = r.referrer_family_id FOR UPDATE;
		IF fam.id IS NULL THEN
			UPDATE public.family_referrals
			   SET status = 'cancelled', cancelled_at = now_utc, cancel_reason = 'referrer_gone'
			 WHERE referred_family_id = r.referred_family_id;
			n_cancel := n_cancel + 1;
			CONTINUE;
		END IF;

		SELECT count(*) INTO v_count
		  FROM public.family_referrals c
		 WHERE c.referrer_family_id = r.referrer_family_id
		   AND c.status IN ('rewarded', 'pending_rail')
		   AND extract(year FROM timezone('America/Sao_Paulo', c.rewarded_at))::int = this_year;
		IF v_count >= cap THEN
			UPDATE public.family_referrals SET status = 'capped'
			 WHERE referred_family_id = r.referred_family_id;
			n_capped := n_capped + 1;
			CONTINUE;
		END IF;

		-- No row leaves every field NULL (SELECT INTO without STRICT).
		SELECT * INTO sub FROM public.subscriptions s WHERE s.family_id = r.referrer_family_id;

		IF sub.id IS NOT NULL AND sub.gateway = 'play'
		   AND (sub.status IN ('active', 'overdue', 'scheduled')
		        OR (sub.status = 'canceled' AND sub.current_period_end > now_utc)) THEN
			UPDATE public.family_referrals
			   SET status = 'pending_rail', reward_rail = 'play', rewarded_at = now_utc,
			       reward_pending_reason = 'play_queued'
			 WHERE referred_family_id = r.referred_family_id;
			n_pending := n_pending + 1;

		ELSIF sub.id IS NOT NULL AND sub.gateway = 'asaas'
		      AND sub.status IN ('active', 'overdue', 'scheduled') THEN
			UPDATE public.family_referrals
			   SET status = 'pending_rail', reward_rail = 'asaas', rewarded_at = now_utc,
			       reward_pending_reason = 'asaas_manual'
			 WHERE referred_family_id = r.referred_family_id;
			n_pending := n_pending + 1;

		ELSIF sub.id IS NOT NULL AND sub.status = 'canceled'
		      AND sub.current_period_end > now_utc AND fam.plan = 'premium' THEN
			UPDATE public.subscriptions
			   SET current_period_end = current_period_end + interval '30 days',
			       updated_at = now_utc
			 WHERE id = sub.id;
			UPDATE public.family_referrals
			   SET status = 'rewarded', reward_rail = 'paid_period',
			       rewarded_at = now_utc, reward_delivered_at = now_utc
			 WHERE referred_family_id = r.referred_family_id;
			PERFORM public.referral_reward_notify(r.referrer_family_id);
			n_reward := n_reward + 1;

		ELSE
			UPDATE public.families
			   SET trial_ends_at = greatest(coalesce(trial_ends_at, now_utc), now_utc) + interval '30 days'
			 WHERE id = r.referrer_family_id;
			UPDATE public.family_referrals
			   SET status = 'rewarded', reward_rail = 'trial',
			       rewarded_at = now_utc, reward_delivered_at = now_utc
			 WHERE referred_family_id = r.referred_family_id;
			PERFORM public.referral_reward_notify(r.referrer_family_id);
			n_reward := n_reward + 1;
		END IF;
	END LOOP;

	RETURN jsonb_build_object(
		'paid', n_paid, 'cancelled', n_cancel, 'qualified', n_qual,
		'rewarded', n_reward, 'pending_rail', n_pending, 'capped', n_capped);
END;
$$;

COMMENT ON FUNCTION public.referral_rewards_due(bigint) IS
	'F-80 PR 3: the daily referral job — first payment → paid, reversal in the window → cancelled, window out → qualified → rewarded / pending_rail / capped. Counts only. No-op while feature.referral is off. Service role only.';

ALTER FUNCTION public.referral_rewards_due(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.referral_rewards_due(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.referral_rewards_due(bigint) TO service_role;


-- ── 5. A pending reward is delivered ─────────────────────────────────────────
-- The one way out of `pending_rail`. Two callers:
--   · `referral-rewards` (Play), AFTER Play accepted the deferral and the
--     function wrote Play's new expiry to `current_period_end`;
--   · the operator (Asaas), AFTER moving the subscription's next due date one
--     month in the Asaas dashboard — here the period moves one month too, so
--     the plan page and the webhook's additive arithmetic agree with Asaas.
-- Returns false (and changes nothing) for a row that is not pending.

CREATE OR REPLACE FUNCTION public.referral_reward_delivered(p_referred_family_id bigint)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	r public.family_referrals%ROWTYPE;
BEGIN
	IF NOT public.setting_bool('feature.referral', false) THEN
		RAISE EXCEPTION 'A indicação ainda não está disponível.'
			USING ERRCODE = 'feature_not_supported';
	END IF;

	SELECT * INTO r FROM public.family_referrals
	 WHERE referred_family_id = p_referred_family_id
	 FOR UPDATE;
	IF r.referred_family_id IS NULL OR r.status <> 'pending_rail'
	   OR r.referrer_family_id IS NULL THEN
		RETURN false;
	END IF;

	IF r.reward_rail = 'asaas' THEN
		UPDATE public.subscriptions
		   SET current_period_end = current_period_end + interval '1 month',
		       updated_at = now()
		 WHERE family_id = r.referrer_family_id
		   AND current_period_end IS NOT NULL;
	END IF;

	UPDATE public.family_referrals
	   SET status = 'rewarded', reward_delivered_at = now(), reward_pending_reason = NULL
	 WHERE referred_family_id = p_referred_family_id;

	PERFORM public.referral_reward_notify(r.referrer_family_id);
	RETURN true;
END;
$$;

COMMENT ON FUNCTION public.referral_reward_delivered(bigint) IS
	'F-80 PR 3: settles a pending_rail referral reward once its rail delivered it (Play: the referral-rewards function; Asaas: the operator, after moving the next due date one month — this also moves current_period_end one month). Notifies the referrer family. Service role only.';

ALTER FUNCTION public.referral_reward_delivered(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.referral_reward_delivered(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.referral_reward_delivered(bigint) TO service_role;


-- ── 6. Push: `referral_reward` ───────────────────────────────────────────────
-- Nobody in the referrer family did anything today: another family paid,
-- weeks ago. Body copied VERBATIM from 20261002170000 (F-77) with the type
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
		'premium_trial',
		'referral_reward'
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


-- ── 7. Schedules ─────────────────────────────────────────────────────────────
-- The state machine is pure SQL, daily at 12:00 UTC (09:00 BRT) beside F-70,
-- F-77 and F-78 — the notice it writes rings a phone. The Play rail needs HTTP,
-- so its Edge Function runs a quarter of an hour later, over whatever the SQL
-- job just queued; it reads the Vault like `weekly-bulletin`. An unarmed
-- project (no Vault secrets) only loses the Play half. cron.schedule upserts by
-- name, so a re-run is safe.

SELECT cron.schedule(
	'referral-rewards-daily',
	'0 12 * * *',
	$cron$ SELECT public.referral_rewards_due(); $cron$
);

SELECT cron.schedule(
	'referral-rewards-play-daily',
	'15 12 * * *',
	$cron$
	SELECT net.http_post(
		url     := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'functions_base_url')
		           || '/referral-rewards',
		headers := jsonb_build_object(
			'Content-Type', 'application/json',
			'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'secret_key')),
		body    := '{}'::jsonb,
		timeout_milliseconds := 30000);
	$cron$
);
