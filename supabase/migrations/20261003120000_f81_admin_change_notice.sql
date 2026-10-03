-- =============================================================================
-- F-81 — an admin's DIRECT change of a day tells the caregivers it affects
--
-- The swap workflow notifies both parties at every step; a write made on an
-- admin's own authority (the F-14 admin mode: reassigning a planned day,
-- correcting the real carer of a past one, clearing a month, re-running the
-- wizard, a handoff time for a range, the plan-mode switch) notified nobody.
-- The other carer found out by opening the calendar. Now each such ACTION
-- writes ONE notification per affected caregiver — push + in-app, no e-mail
-- (F-59: e-mail only where nothing else reaches the reader).
--
-- WHICH writes (owner, 03/10/2026, and the one engineering reading of it):
--   · the actor is a family admin, signed in (`auth.uid()`); a system write
--     (service_role: auto-approval, migrations, crons) has no actor and stays
--     silent;
--   · the actor is NOT the target of a pending request on that day — the
--     predicate `enforce_day_protection` and F-61's audit use: a target
--     applying an approval (or restoring a revert) acts inside the two-party
--     workflow, which notifies on its own;
--   · something of SUBSTANCE changed (planned carer, real carer, handoff time,
--     the day note, the date) — a revision-token touch is not a change;
--   · not the T-45 cascade (`app.handoff_cascade`: a mechanical consequence of
--     the day the admin did change) and not a controlled cleanup
--     (`app.deletion_context`: a member leaving, a pending member removed, a
--     family purge — each has its own notice).
--   F-61's `admin_override` stamp is NARROWER on purpose: it records the
--   admin-only POWERS (a parent changed, a day cleared), so a handoff time or
--   a planned new day carries `admin_override = false`. The owner's list
--   names those too (a handoff-only change still affects the day's carers; a
--   wizard replace and a handoff range notify), so the trigger reads the
--   actor's authority, not the stamp.
--
-- WHO: the day's planned and real carer BEFORE and AFTER the write (both
-- columns, old and new row) — with an account (`user_id`), active
-- (`left_at IS NULL`: a pending member has no account, a departed one has
-- left), not a viewer, and not the actor.
--
-- ONE PER ACTION: a row trigger STAGES (family, actor, recipient, date, lane)
-- in `admin_change_notice_queue`, keyed by the transaction id; a DEFERRED
-- constraint trigger on that table runs at COMMIT, aggregates everything the
-- transaction staged per recipient and writes one notification each:
--   · one distinct day for that recipient → kind `single`, the day;
--   · more than one → kind `batch`, the first and last day and the count.
-- Every F-51/U-55/F-07 range RPC (clear month, wizard replace, handoff range,
-- mode switch) is ONE transaction, and so is one PostgREST request (the bulk
-- sheet's multi-row insert, a day edit), so "one action" is "one
-- transaction" without reading `app.schedule_batch` at all. Separate requests
-- are separate notices, which is what they are to the person who made them.
-- The first deferred firing flushes and empties the queue for the
-- transaction; every later firing finds nothing and returns. A failure in
-- the flush is a WARNING, never a failed write — a notice is not worth the
-- calendar change that earned it (the dispatcher's own rule).
--
-- PT-BR stored sentences are byte-identical to the Dart catalog (U-13);
-- `params` carries values only: `kind`, `date` (ISO, the day or the first
-- day), `to` + `count` for a batch, `name` (the actor's own name, the rule
-- every swap notice follows), and `child` when every staged row is ONE
-- child's lane (F-07). Nothing about any other family.
-- =============================================================================


-- ── 1. The staging table ─────────────────────────────────────────────────────
-- Rows live only inside the transaction that staged them: the flush deletes
-- them before COMMIT returns. No FK on purpose — nothing here outlives the
-- write it describes, and a purge must never trip over it.

CREATE TABLE IF NOT EXISTS public.admin_change_notice_queue (
	id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	txid                 bigint NOT NULL DEFAULT txid_current(),
	family_id            bigint NOT NULL,
	actor_profile_id     bigint NOT NULL,
	recipient_profile_id bigint NOT NULL,
	affected_date        date   NOT NULL,
	child_id             bigint
);

CREATE INDEX IF NOT EXISTS admin_change_notice_queue_txid_idx
	ON public.admin_change_notice_queue (txid);

ALTER TABLE public.admin_change_notice_queue ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.admin_change_notice_queue FROM PUBLIC;
REVOKE ALL ON TABLE public.admin_change_notice_queue FROM anon;
REVOKE ALL ON TABLE public.admin_change_notice_queue FROM authenticated;
GRANT ALL ON TABLE public.admin_change_notice_queue TO service_role;

COMMENT ON TABLE public.admin_change_notice_queue IS
	'F-81: per-transaction staging of an admin''s direct day changes; flushed into ONE notification per affected caregiver at COMMIT and emptied. Readable by no client.';


-- ── 2. Stage: one row per (affected caregiver, day) of an admin's write ─────

CREATE OR REPLACE FUNCTION public.stage_admin_change_notice()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	actor_id    bigint;
	actor_admin boolean := false;
	fam         bigint;
	the_date    date;
	lane        bigint;
	is_target   boolean := false;
BEGIN
	-- A controlled cleanup and the T-45 cascade are not an admin's act.
	IF current_setting('app.deletion_context', true) = 'on'
	   OR current_setting('app.handoff_cascade', true) = 'on' THEN
		RETURN NULL;
	END IF;

	-- No actor (service_role) or not an admin: the existing notices cover it.
	SELECT id, is_admin INTO actor_id, actor_admin
	FROM public.profiles WHERE user_id = auth.uid();
	IF actor_id IS NULL OR NOT COALESCE(actor_admin, false) THEN
		RETURN NULL;
	END IF;

	-- A touch with nothing of substance (a revision token, `updated_at`).
	IF TG_OP = 'UPDATE'
	   AND NEW.schedule_date       IS NOT DISTINCT FROM OLD.schedule_date
	   AND NEW.scheduled_parent_id IS NOT DISTINCT FROM OLD.scheduled_parent_id
	   AND NEW.actual_parent_id    IS NOT DISTINCT FROM OLD.actual_parent_id
	   AND NEW.handoff_time        IS NOT DISTINCT FROM OLD.handoff_time
	   AND NEW.notes               IS NOT DISTINCT FROM OLD.notes THEN
		RETURN NULL;
	END IF;

	fam      := COALESCE(NEW.family_id, OLD.family_id);
	the_date := COALESCE(NEW.schedule_date, OLD.schedule_date);
	lane     := CASE WHEN TG_OP = 'DELETE' THEN OLD.child_id ELSE NEW.child_id END;

	-- The two-party workflow: the target applying an approval (or restoring
	-- the pre-edit snapshot of a revert) — the predicate F-61 stamps with.
	SELECT COALESCE(bool_or(target_profile_id = actor_id), false) INTO is_target
	FROM public.swap_requests
	WHERE family_id = fam AND schedule_date = the_date
	  AND child_id IS NOT DISTINCT FROM lane
	  AND status IN ('pending', 'revert_pending');
	IF is_target THEN
		RETURN NULL;
	END IF;

	-- The day's carers before and after, each on the date it was theirs.
	INSERT INTO public.admin_change_notice_queue
		(family_id, actor_profile_id, recipient_profile_id, affected_date, child_id)
	SELECT DISTINCT fam, actor_id, p.id, c.day, lane
	FROM (VALUES
		(OLD.scheduled_parent_id, OLD.schedule_date),
		(OLD.actual_parent_id,    OLD.schedule_date),
		(NEW.scheduled_parent_id, NEW.schedule_date),
		(NEW.actual_parent_id,    NEW.schedule_date)
	) AS c(profile_id, day)
	JOIN public.profiles p ON p.id = c.profile_id
	WHERE c.day IS NOT NULL
	  AND p.id <> actor_id
	  AND p.family_id = fam
	  AND p.user_id IS NOT NULL
	  AND p.left_at IS NULL
	  AND p.membership_type <> 'viewer';

	RETURN NULL;
END;
$$;

ALTER FUNCTION public.stage_admin_change_notice() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.stage_admin_change_notice() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_stage_admin_change_notice ON public.care_schedules;
CREATE TRIGGER trigger_stage_admin_change_notice
	AFTER INSERT OR UPDATE OR DELETE ON public.care_schedules
	FOR EACH ROW EXECUTE FUNCTION public.stage_admin_change_notice();


-- ── 3. Flush at COMMIT: one notification per recipient per transaction ──────
-- PT-BR byte-identical to the catalog (U-13): `notifRender.title.dayAdminChange.*`
-- and `notifRender.dayAdminChange.*`. The count is a value, never a setting.

CREATE OR REPLACE FUNCTION public.flush_admin_change_notices()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	tx bigint := txid_current();
BEGIN
	-- Every firing after the first finds the queue already emptied.
	IF NOT EXISTS (SELECT 1 FROM public.admin_change_notice_queue WHERE txid = tx) THEN
		RETURN NULL;
	END IF;

	BEGIN
		WITH staged AS (
			DELETE FROM public.admin_change_notice_queue
			WHERE txid = tx
			RETURNING family_id, actor_profile_id, recipient_profile_id, affected_date, child_id
		), per_recipient AS (
			SELECT s.family_id, s.actor_profile_id, s.recipient_profile_id,
			       min(s.affected_date)            AS first_day,
			       max(s.affected_date)            AS last_day,
			       count(DISTINCT s.affected_date) AS days,
			       -- F-07: the child is named only when every row is ONE lane.
			       CASE WHEN bool_and(s.child_id IS NOT NULL)
			                 AND count(DISTINCT s.child_id) = 1
			            THEN min(s.child_id) END    AS lane
			FROM staged s
			GROUP BY s.family_id, s.actor_profile_id, s.recipient_profile_id
		), shaped AS (
			SELECT r.recipient_profile_id, r.days, r.first_day, r.last_day,
			       a.full_name  AS actor_name,
			       c.first_name AS child_name
			FROM per_recipient r
			LEFT JOIN public.profiles a ON a.id = r.actor_profile_id
			LEFT JOIN public.children c ON c.id = r.lane AND c.family_id = r.family_id
		)
		INSERT INTO public.notifications (recipient_profile_id, type, title, message, params)
		SELECT
			s.recipient_profile_id,
			'day_admin_change',
			CASE WHEN s.days = 1 THEN 'Dia alterado no calendário'
			     ELSE 'Dias alterados no calendário' END
				|| COALESCE(' · ' || s.child_name, ''),
			CASE WHEN s.days = 1
			     THEN COALESCE(s.actor_name, 'Outro responsável') || ' alterou o dia '
			          || to_char(s.first_day, 'DD/MM/YYYY') || ' no calendário.'
			     ELSE COALESCE(s.actor_name, 'Outro responsável') || ' alterou ' || s.days
			          || ' dias entre ' || to_char(s.first_day, 'DD/MM/YYYY')
			          || ' e ' || to_char(s.last_day, 'DD/MM/YYYY') || ' no calendário.' END,
			jsonb_strip_nulls(CASE WHEN s.days = 1
				THEN jsonb_build_object(
					'kind',  'single',
					'date',  to_char(s.first_day, 'YYYY-MM-DD'),
					'name',  s.actor_name,
					'child', s.child_name)
				ELSE jsonb_build_object(
					'kind',  'batch',
					'date',  to_char(s.first_day, 'YYYY-MM-DD'),
					'to',    to_char(s.last_day, 'YYYY-MM-DD'),
					'count', s.days::text,
					'name',  s.actor_name,
					'child', s.child_name) END)
		FROM shaped s;
	EXCEPTION WHEN OTHERS THEN
		-- The write stands; only the notice is lost. The staged rows go too,
		-- so the next firing does not try again.
		RAISE WARNING 'flush_admin_change_notices failed for transaction %: %', tx, SQLERRM;
		DELETE FROM public.admin_change_notice_queue WHERE txid = tx;
	END;

	RETURN NULL;
END;
$$;

ALTER FUNCTION public.flush_admin_change_notices() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.flush_admin_change_notices() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_flush_admin_change_notices ON public.admin_change_notice_queue;
CREATE CONSTRAINT TRIGGER trigger_flush_admin_change_notices
	AFTER INSERT ON public.admin_change_notice_queue
	DEFERRABLE INITIALLY DEFERRED
	FOR EACH ROW EXECUTE FUNCTION public.flush_admin_change_notices();


-- ── 4. Push: `day_admin_change` ──────────────────────────────────────────────
-- The reader did not make this change: an admin did, on a day that is (or
-- was) the reader's. Body copied VERBATIM from 20261002210000 (F-80 PR 3)
-- with the type added; the filter keeps its literal list shape, which T-83's
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
		'referral_reward',
		'day_admin_change'
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
