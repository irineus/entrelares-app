-- =============================================================================
-- F-35 (PR 1 of 3) — the family's Conversa, on the server
--
-- Decisions locked by the owner (24/09/2026, F-35 Notes):
--
--   * ONE conversation per family, like a group chat. Caregivers with a full
--     seat write; a viewer (F-50) READS and never writes. Premium, gated here
--     (`chat.premium_only`); a downgrade keeps everything readable and refuses
--     the next message.
--   * Text only, up to `chat.message_max_chars`, no attachment, and IMMUTABLE:
--     no edit, no delete — a trigger refuses both for everyone (the family's
--     own deletion cascades through the deletion context), and no client has
--     a grant to write the table at all.
--   * v1: reply quoting another message (the quote points at the id, and the
--     quoted text is the immutable original), "lida por" visible to everyone
--     (who and when), citing a calendar day (`quoted_day`), search (the client
--     filters what RLS already lets it read).
--   * Push + in-app to every reader but the author, a new push type
--     (`chat_message`, born ON in T-83's switch); each member may SILENCE the
--     chat's push for themselves (the in-app row stays). Never e-mail.
--   * No tone meter, no moderation, no reporting; a fixed notice on top of the
--     screen says messages are permanent. The operator never reads content
--     (F-69: counts only). On leaving (S-11) the messages stay in the
--     tombstone's name; they go only with the family.
--   * Dark in production: `feature.chat`. A flood brake per author:
--     `chat.messages_per_hour`.
--
-- Vocabulary: "Conversa" / "Chat". "Mensagem" stays the SWAP's message, so no
-- sentence here says it (vocabulary_test).
-- =============================================================================


-- ── 1. The keys (T-84 catalogue) ─────────────────────────────────────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, min_value, max_value, help)
VALUES
	('feature.chat', 'false', 'bool', 'features',
	 'Liga a Conversa da família (F-35). Desligado, a aba some e o servidor recusa escrever.',
	 true, 'flag', 'critical', NULL, NULL,
	 jsonb_build_object(
		'controls', 'Se send_chat_message e as marcas de leitura aceitam chamadas, e se a Conversa aparece em Comunicação.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Ligado: a família conversa num canal único, permanente, com leitura visível e push.',
		'if_decreased', 'Desligado: a Conversa some e o servidor recusa escrever; o que já foi dito fica guardado.',
		'takes_effect', 'Servidor na próxima chamada; app na próxima abertura.',
		'caveats', 'Produção nasce desligada: o S-22 liga junto com a política.')),
	('chat.premium_only', 'true', 'bool', 'chat',
	 'Só o Premium escreve na Conversa.',
	 true, 'flag', 'critical', NULL, NULL,
	 jsonb_build_object(
		'controls', 'Se o envio na Conversa recusa família sem Premium.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Ligado (padrão): a Conversa é benefício Premium; a família gratuita lê o que já existe e vê o convite para o plano.',
		'if_decreased', 'Desligado: toda família conversa.',
		'takes_effect', 'Servidor no próximo envio; app na próxima abertura.',
		'caveats', 'Rebaixamento: a conversa fica em só leitura, nada é apagado.')),
	('chat.message_max_chars', '2000', 'int', 'chat',
	 'Tamanho máximo de um texto na Conversa.',
	 true, 'chars', 'normal', 200, 4000,
	 jsonb_build_object(
		'controls', 'Quantos caracteres um envio na Conversa aceita.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Textos mais longos; o PDF cresce junto. Não passa de 4000: é o CHECK da coluna.',
		'if_decreased', 'O que já foi enviado fica; só o próximo envio respeita o novo limite.',
		'takes_effect', 'Servidor no próximo envio; app na próxima abertura.')),
	('chat.messages_per_hour', '60', 'int', 'chat',
	 'Quantos envios na Conversa uma pessoa pode fazer por hora.',
	 true, 'count', 'normal', 10, 300,
	 jsonb_build_object(
		'controls', 'O freio contra enxurrada: envios de um mesmo membro nos últimos 60 minutos.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Conversas rápidas não esbarram no limite; uma enxurrada chega mais longe (cada envio é um push).',
		'if_decreased', 'Quem passar do limite espera a hora virar para enviar de novo.',
		'takes_effect', 'Servidor no próximo envio.'))
ON CONFLICT (key) DO NOTHING;


-- ── 2. The tables ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.chat_messages (
	id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	family_id          bigint NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
	-- No ON DELETE, on purpose: an author who leaves becomes a tombstone
	-- (S-11); the rows go only with the family.
	author_profile_id  bigint NOT NULL REFERENCES public.profiles(id),
	body               text NOT NULL
	                   CHECK (body = btrim(body) AND char_length(body) BETWEEN 1 AND 4000),
	quote_id           bigint REFERENCES public.chat_messages(id),
	quoted_day         date,
	created_at         timestamptz NOT NULL DEFAULT now()
);

-- Who read what, and when — visible to the whole family ("lida por").
CREATE TABLE IF NOT EXISTS public.chat_reads (
	message_id  bigint NOT NULL REFERENCES public.chat_messages(id) ON DELETE CASCADE,
	profile_id  bigint NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
	read_at     timestamptz NOT NULL DEFAULT now(),
	PRIMARY KEY (message_id, profile_id)
);

-- Each member's own choice: silence the chat's PUSH (the in-app row stays).
CREATE TABLE IF NOT EXISTS public.chat_prefs (
	profile_id  bigint PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
	push_muted  boolean NOT NULL DEFAULT false,
	updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS chat_messages_family_idx ON public.chat_messages (family_id, id);
CREATE INDEX IF NOT EXISTS chat_messages_author_idx ON public.chat_messages (author_profile_id, created_at);
CREATE INDEX IF NOT EXISTS chat_reads_profile_idx ON public.chat_reads (profile_id);

DO $$
DECLARE
	t text;
BEGIN
	FOREACH t IN ARRAY ARRAY['chat_messages', 'chat_reads', 'chat_prefs'] LOOP
		EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
		EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, anon, authenticated', t);
		EXECUTE format('GRANT SELECT ON public.%I TO authenticated', t);
		EXECUTE format('GRANT ALL ON public.%I TO service_role', t);
	END LOOP;
END $$;

-- F-50: a viewer writes no message (its reads and its mute are its own rows,
-- written by RPCs that allow a viewer, so the guard sits on the messages only).
DROP TRIGGER IF EXISTS trigger_a_refuse_viewer_write ON public.chat_messages;
CREATE TRIGGER trigger_a_refuse_viewer_write
	BEFORE INSERT OR UPDATE OR DELETE ON public.chat_messages
	FOR EACH ROW EXECUTE FUNCTION public.refuse_viewer_write();

-- Read: the whole family, viewers included (a viewer reads the Conversa).
DROP POLICY IF EXISTS chat_messages_family_read ON public.chat_messages;
CREATE POLICY chat_messages_family_read ON public.chat_messages FOR SELECT TO authenticated
	USING (family_id = public.get_my_family_id());
DROP POLICY IF EXISTS chat_reads_family_read ON public.chat_reads;
CREATE POLICY chat_reads_family_read ON public.chat_reads FOR SELECT TO authenticated
	USING (EXISTS (SELECT 1 FROM public.chat_messages m
	               WHERE m.id = message_id AND m.family_id = public.get_my_family_id()));
DROP POLICY IF EXISTS chat_prefs_own_read ON public.chat_prefs;
CREATE POLICY chat_prefs_own_read ON public.chat_prefs FOR SELECT TO authenticated
	USING (profile_id IN (SELECT id FROM public.profiles WHERE user_id = auth.uid()));

-- Immutable: no edit, no delete — for anyone, service_role included. The
-- family's own deletion runs under the deletion context and cascades through.
CREATE OR REPLACE FUNCTION public.chat_messages_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
	IF TG_OP = 'DELETE' AND current_setting('app.deletion_context', true) = 'on' THEN
		RETURN OLD;
	END IF;
	RAISE EXCEPTION 'O que foi dito na Conversa não se altera nem se apaga.'
		USING ERRCODE = 'insufficient_privilege';
END;
$$;

REVOKE ALL ON FUNCTION public.chat_messages_immutable() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_chat_messages_immutable ON public.chat_messages;
CREATE TRIGGER trigger_chat_messages_immutable
	BEFORE UPDATE OR DELETE ON public.chat_messages
	FOR EACH ROW EXECUTE FUNCTION public.chat_messages_immutable();


-- ── 3. The guard ─────────────────────────────────────────────────────────────
-- p_write: sending (a full seat, Premium). Otherwise reading-side writes (the
-- read marks, the mute), which a viewer makes too.

CREATE OR REPLACE FUNCTION public.chat_guard(p_write boolean)
RETURNS public.profiles
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me public.profiles%ROWTYPE;
BEGIN
	IF NOT public.setting_bool('feature.chat', false) THEN
		RAISE EXCEPTION 'A Conversa ainda não está disponível.'
			USING ERRCODE = 'feature_not_supported';
	END IF;
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();
	IF me.id IS NULL OR me.left_at IS NOT NULL THEN
		RAISE EXCEPTION 'Sua conta não participa da Conversa desta família.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;
	IF p_write THEN
		IF me.membership_type <> 'full' THEN
			RAISE EXCEPTION 'Quem acompanha o plano lê a Conversa, mas não escreve nela.'
				USING ERRCODE = 'insufficient_privilege';
		END IF;
		IF public.setting_bool('chat.premium_only', true) AND NOT public.is_premium(me.family_id) THEN
			RAISE EXCEPTION 'A Conversa é um recurso Premium. Sem o Premium, o que já foi dito fica só para leitura.'
				USING ERRCODE = 'check_violation';
		END IF;
	END IF;
	RETURN me;
END;
$$;

ALTER FUNCTION public.chat_guard(boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.chat_guard(boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chat_guard(boolean) TO service_role;


-- ── 4. Sending ───────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.send_chat_message(p_body text, p_quote_id bigint, p_day date)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me       public.profiles%ROWTYPE := public.chat_guard(true);
	v_body   text := nullif(btrim(coalesce(p_body, '')), '');
	max_chr  int  := public.setting_int('chat.message_max_chars', 2000);
	per_hour int  := public.setting_int('chat.messages_per_hour', 60);
	v_name   text;
	v_short  text;
	new_id   bigint;
BEGIN
	IF v_body IS NULL THEN
		RAISE EXCEPTION 'Escreva algo antes de enviar.' USING ERRCODE = 'check_violation';
	END IF;
	IF char_length(v_body) > max_chr THEN
		RAISE EXCEPTION 'Um envio na Conversa é limitado a % caracteres.', max_chr
			USING ERRCODE = 'check_violation';
	END IF;
	IF p_quote_id IS NOT NULL AND NOT EXISTS (
		SELECT 1 FROM public.chat_messages WHERE id = p_quote_id AND family_id = me.family_id) THEN
		RAISE EXCEPTION 'O texto citado não está nesta Conversa.' USING ERRCODE = 'check_violation';
	END IF;
	IF (SELECT COUNT(*) FROM public.chat_messages
	    WHERE author_profile_id = me.id AND created_at > now() - interval '1 hour') >= per_hour THEN
		RAISE EXCEPTION 'Você chegou ao limite de % envios por hora na Conversa. Tente de novo mais tarde.', per_hour
			USING ERRCODE = 'check_violation';
	END IF;

	INSERT INTO public.chat_messages (family_id, author_profile_id, body, quote_id, quoted_day)
	VALUES (me.family_id, me.id, v_body, p_quote_id, p_day)
	RETURNING id INTO new_id;

	-- In-app to every reader but the author (viewers included — the viewer
	-- filter lets `chat_message` through); push unless the reader silenced it.
	v_name  := coalesce(nullif(btrim(me.full_name), ''), 'Um membro da família');
	v_short := CASE WHEN char_length(v_body) > 140
	                THEN left(v_body, 139) || '…' ELSE v_body END;
	INSERT INTO public.notifications (recipient_profile_id, type, title, message, params)
	SELECT p.id, 'chat_message', 'Conversa da família',
	       v_name || ': ' || v_short,
	       jsonb_build_object(
	           'date', to_char((now() AT TIME ZONE 'America/Sao_Paulo')::date, 'YYYY-MM-DD'),
	           'name', v_name,
	           'msg',  v_short,
	           'id',   new_id::text,
	           'push', CASE WHEN coalesce(cp.push_muted, false) THEN 'false' ELSE 'true' END)
	FROM public.profiles p
	LEFT JOIN public.chat_prefs cp ON cp.profile_id = p.id
	WHERE p.family_id = me.family_id
	  AND p.id <> me.id
	  AND p.user_id IS NOT NULL AND p.left_at IS NULL;

	RETURN new_id;
END;
$$;

ALTER FUNCTION public.send_chat_message(text, bigint, date) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.send_chat_message(text, bigint, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_chat_message(text, bigint, date) TO authenticated, service_role;


-- ── 5. Reading and silencing ─────────────────────────────────────────────────

-- Marks every message of the family up to p_up_to (not the reader's own) as
-- read now; returns how many were new. A viewer reads too.
CREATE OR REPLACE FUNCTION public.mark_chat_read(p_up_to bigint)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me public.profiles%ROWTYPE := public.chat_guard(false);
	n  integer;
BEGIN
	INSERT INTO public.chat_reads (message_id, profile_id)
	SELECT m.id, me.id FROM public.chat_messages m
	WHERE m.family_id = me.family_id AND m.id <= p_up_to AND m.author_profile_id <> me.id
	ON CONFLICT (message_id, profile_id) DO NOTHING;
	GET DIAGNOSTICS n = ROW_COUNT;
	RETURN n;
END;
$$;

ALTER FUNCTION public.mark_chat_read(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.mark_chat_read(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_chat_read(bigint) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.set_chat_push_muted(p_muted boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me public.profiles%ROWTYPE := public.chat_guard(false);
BEGIN
	INSERT INTO public.chat_prefs (profile_id, push_muted, updated_at)
	VALUES (me.id, coalesce(p_muted, false), now())
	ON CONFLICT (profile_id) DO UPDATE
	SET push_muted = EXCLUDED.push_muted, updated_at = now();
END;
$$;

ALTER FUNCTION public.set_chat_push_muted(boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.set_chat_push_muted(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_chat_push_muted(boolean) TO authenticated, service_role;


-- ── 6. Push: the chat type ───────────────────────────────────────────────────
-- Copied VERBATIM from 20260924160000_f34_expenses.sql with 'chat_message' in the filter — and so in
-- T-83's `push.disabled_types` vocabulary (read from this filter), born ON.
-- A reader who silenced the chat gets `params.push = 'false'`, which the
-- F-55 line already skips.

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
		'plan_ending',
		'agenda_notice', 'agenda_reminder',
		'expense_changed', 'settlement_requested', 'settlement_answered',
		'chat_message'
	) THEN
		RETURN NULL;
	END IF;

	-- A row written before U-13 (or by a writer that forgot `params`) carries no
	-- render data, and the function would only drop it. Save the round trip.
	IF NEW.params IS NULL THEN
		RETURN NULL;
	END IF;

	-- F-55: the agenda's creator chose "no push" for this item — the row is
	-- the in-app notice alone.
	IF NEW.params ->> 'push' = 'false' THEN
		RETURN NULL;
	END IF;

	-- T-83: the per-type kill switch. A muted type keeps its in-app row, its
	-- badge and its e-mail — only the phone stays quiet.
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
	-- row, the badge and the e-mail all stand; only the interruption is lost.
	RAISE WARNING 'dispatch_push_notification failed for notification %: %', NEW.id, SQLERRM;
	RETURN NULL;
END;
$$;

-- ── 7. A viewer reads the Conversa, so its notification reaches them ────────
-- Body from 20260924140000_f50_viewer.sql plus `chat_message`. (After the dispatcher on purpose: the
-- push mirror reads the FIRST `NEW.type NOT IN (` of the newest file.)

CREATE OR REPLACE FUNCTION public.filter_viewer_notifications()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
	IF EXISTS (SELECT 1 FROM public.profiles
	           WHERE id = NEW.recipient_profile_id AND membership_type = 'viewer')
	   AND NEW.type NOT IN ('swap_family_info', 'plan_ending', 'day_notice',
	                        'agenda_notice', 'agenda_reminder',
	                        'chat_message') THEN
		RETURN NULL;
	END IF;
	RETURN NEW;
END;
$$;

-- ── 8. The family's deletion takes the Conversa with it ──────────────────────
-- Body from 20260924160000_f34_expenses.sql; runs under the deletion context, which the immutability
-- trigger lets through.

CREATE OR REPLACE FUNCTION public.purge_family_data(p_family_id bigint)
RETURNS SETOF uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
	PERFORM set_config('app.deletion_context', 'on', true);

	IF NOT EXISTS (SELECT 1 FROM public.families WHERE id = p_family_id) THEN
		RETURN;   -- already purged
	END IF;

	-- Hand back the auth user ids BEFORE deleting the profiles.
	RETURN QUERY
	SELECT p.user_id::uuid FROM public.profiles p
	WHERE p.family_id = p_family_id AND p.user_id IS NOT NULL;

	-- Ordered teardown (children first; notifications have no family_id).
	DELETE FROM public.notifications
	WHERE recipient_profile_id IN (SELECT id FROM public.profiles WHERE family_id = p_family_id);
	DELETE FROM public.account_logs       WHERE family_id = p_family_id;
	DELETE FROM public.swap_requests      WHERE family_id = p_family_id;
	DELETE FROM public.care_schedules     WHERE family_id = p_family_id;
	DELETE FROM public.activity_logs      WHERE family_id = p_family_id;
	DELETE FROM public.family_invitations WHERE family_id = p_family_id;
	-- F-34: the expenses (shares and trail cascade) and the settlements.
	DELETE FROM public.expense_settlements WHERE family_id = p_family_id;
	-- F-35: the Conversa (reads cascade), before the profiles its authors are.
	DELETE FROM public.chat_messages       WHERE family_id = p_family_id;
	DELETE FROM public.expenses            WHERE family_id = p_family_id;
	DELETE FROM public.profiles           WHERE family_id = p_family_id;
	DELETE FROM public.families           WHERE id = p_family_id;
END;
$$;

-- Body from 20260924162000_f34_purge_e2e_deletion_context.sql — the gate's and the E2E lane's teardown.

CREATE OR REPLACE FUNCTION public.purge_e2e_family(p_family_id bigint)
RETURNS SETOF uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	fam_name text;
	non_e2e_members int;
BEGIN
	-- F-34: the same context `purge_family_data` sets — the append-only trail
	-- (`expense_history`) lets a cascade through only under it.
	PERFORM set_config('app.deletion_context', 'on', true);

	SELECT name INTO fam_name FROM public.families WHERE id = p_family_id;
	IF fam_name IS NULL THEN
		RETURN;   -- already gone: purge is idempotent
	END IF;

	-- E2E double signature — refuse anything that is not unmistakably test data.
	IF fam_name NOT LIKE 'E2E-%' THEN
		RAISE EXCEPTION 'purge_e2e_family: family % is not an E2E family (name).', p_family_id
			USING ERRCODE = 'check_violation';
	END IF;
	SELECT count(*) INTO non_e2e_members
	FROM public.profiles
	WHERE family_id = p_family_id
	  AND email NOT LIKE '%@resend.dev'
	  AND email NOT LIKE 'removido+%@guarda.invalido';
	IF non_e2e_members > 0 THEN
		RAISE EXCEPTION 'purge_e2e_family: family % has non-E2E members (email).', p_family_id
			USING ERRCODE = 'check_violation';
	END IF;

	-- Hand the auth user ids back BEFORE deleting the profiles.
	RETURN QUERY
	SELECT user_id::uuid FROM public.profiles
	WHERE family_id = p_family_id AND user_id IS NOT NULL;

	-- Ordered teardown (children first; profiles are referenced by all data).
	DELETE FROM public.notifications
	WHERE recipient_profile_id IN (SELECT id FROM public.profiles WHERE family_id = p_family_id);
	DELETE FROM public.swap_requests      WHERE family_id = p_family_id;
	DELETE FROM public.care_schedules     WHERE family_id = p_family_id;
	DELETE FROM public.activity_logs      WHERE family_id = p_family_id;
	DELETE FROM public.family_invitations WHERE family_id = p_family_id;
	-- T-39: the billing ledger is denormalized on purpose (audit survives the
	-- subscription); for E2E families it must go with them.
	DELETE FROM public.billing_events     WHERE family_id = p_family_id;
	-- F-34: the expenses (shares and trail cascade) and the settlements, BEFORE
	-- the profiles they reference (their FKs have no ON DELETE on purpose).
	DELETE FROM public.expense_settlements WHERE family_id = p_family_id;
	-- F-35: the Conversa (reads cascade), before the profiles.
	DELETE FROM public.chat_messages       WHERE family_id = p_family_id;
	DELETE FROM public.expenses            WHERE family_id = p_family_id;
	DELETE FROM public.profiles           WHERE family_id = p_family_id;
	DELETE FROM public.families           WHERE id = p_family_id;
END;
$$;

-- ── 9. F-69: the operator's report counts the Conversa — never its content ──
-- Body from 20260924160000_f34_expenses.sql plus the `chat` block.

CREATE OR REPLACE FUNCTION public.admin_family_usage_report(p_family_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	fam        public.families%ROWTYPE;
	today      date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	first_week date;
	weeks      int := public.setting_int('usage_report.weeks', 12);
	active_win int := public.setting_int('usage_report.active_days', 30);
	premium    boolean;
	result     jsonb;
BEGIN
	IF NOT public.is_platform_operator() THEN
		RAISE EXCEPTION 'Acesso restrito à operação da plataforma.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	SELECT * INTO fam FROM public.families WHERE id = p_family_id;

	INSERT INTO public.operator_audit_logs (operator_user_id, action, family_id, new_value)
	VALUES (auth.uid(), 'family_usage_report', fam.id, p_family_id::text);

	IF fam.id IS NULL THEN
		RETURN NULL;
	END IF;

	premium    := public.is_premium(fam.id);
	first_week := date_trunc('week', today)::date - 7 * (weeks - 1);

	WITH
	days AS (
		SELECT
			d.schedule_date                                       AS day,
			COALESCE(d.actual_parent_id, d.scheduled_parent_id)   AS carer,
			d.scheduled_parent_id                                 AS planned,
			d.actual_parent_id                                    AS actual,
			d.handoff_time,
			NULLIF(btrim(d.notes), '') IS NOT NULL                AS has_note,
			(p.id IS NULL
			 OR COALESCE(p.actual_parent_id, p.scheduled_parent_id)
			    IS DISTINCT FROM COALESCE(d.actual_parent_id, d.scheduled_parent_id))
			                                                      AS transition
		FROM public.care_schedules d
		LEFT JOIN public.care_schedules p
		       ON p.family_id = d.family_id AND p.schedule_date = d.schedule_date - 1
		WHERE d.family_id = fam.id
	),
	edits AS (
		SELECT
			(l.created_at AT TIME ZONE 'America/Sao_Paulo')::date AS day,
			l.performed_by_id,
			COALESCE(l.context ->> 'batch_id',
			         l.performed_by_id::text || '@' || l.created_at::text) AS unit,
			COALESCE((l.context ->> 'admin_override')::boolean, false) AS override
		FROM public.activity_logs l
		WHERE l.family_id = fam.id
		  AND l.created_at >= (first_week::timestamp AT TIME ZONE 'America/Sao_Paulo')
	),
	weeks AS (
		SELECT w::date AS week_start
		FROM generate_series(first_week, date_trunc('week', today)::date, interval '7 days') w
	)
	SELECT jsonb_build_object(
		'report_version', 1,
		'generated_at',   now(),
		'today',          today,
		'windows',        jsonb_build_object('weeks', weeks, 'active_days', active_win),

		'family', jsonb_build_object(
			'id',              fam.id,
			'created_at',      fam.created_at,
			'plan',            fam.plan,
			'is_premium',      premium,
			'trial_ends_at',   fam.trial_ends_at,
			'comp_premium_at', fam.comp_premium_at,
			'seats_used',      public.seat_count(fam.id),
			'seats_cap',       CASE WHEN premium
			                        THEN public.setting_int('max_caregivers', 4)
			                        ELSE public.setting_int('free_caregivers', 2) END,
			-- F-50: the viewers, outside the caregiver seats — counts only.
			'viewers_used',    (SELECT COUNT(*) FROM public.profiles v
			                    WHERE v.family_id = fam.id AND v.membership_type = 'viewer'
			                      AND v.left_at IS NULL),
			'viewers_cap',     CASE WHEN premium
			                        THEN public.setting_int('max_viewers', 4)
			                        ELSE public.setting_int('free_viewers', 1) END,
			-- F-34: the expenses — counts only, never an amount or a text.
			'expenses', jsonb_build_object(
				'active',   (SELECT COUNT(*) FROM public.expenses x
				             WHERE x.family_id = fam.id AND x.deleted_at IS NULL),
				'deleted',  (SELECT COUNT(*) FROM public.expenses x
				             WHERE x.family_id = fam.id AND x.deleted_at IS NOT NULL),
				'edits',    (SELECT COUNT(*) FROM public.expense_history h
				             WHERE h.family_id = fam.id AND h.action = 'updated'),
				'settlements_pending',   (SELECT COUNT(*) FROM public.expense_settlements st
				                          WHERE st.family_id = fam.id AND st.status = 'pending'),
				'settlements_confirmed', (SELECT COUNT(*) FROM public.expense_settlements st
				                          WHERE st.family_id = fam.id AND st.status = 'confirmed')),
			-- F-64: the verifiable reports — counts only, never the id.
			'attestations', (
				SELECT jsonb_build_object(
					'issued',  COUNT(*),
					'active',  COUNT(*) FILTER (WHERE ra.revoked_at IS NULL AND ra.expires_at > now()
					                              AND ra.sha256 IS NOT NULL),
					'revoked', COUNT(*) FILTER (WHERE ra.revoked_at IS NOT NULL),
					'pending', COUNT(*) FILTER (WHERE ra.sha256 IS NULL AND ra.revoked_at IS NULL
					                              AND ra.expires_at > now()))
				FROM public.report_attestations ra WHERE ra.family_id = fam.id),
			-- F-35: the Conversa — counts only, never a text.
			'chat', (
				SELECT jsonb_build_object(
					'messages',     COUNT(*),
					'messages_30d', COUNT(*) FILTER (WHERE cm.created_at > now() - interval '30 days'),
					'authors',      COUNT(DISTINCT cm.author_profile_id))
				FROM public.chat_messages cm WHERE cm.family_id = fam.id),
			'chat_push_muted', (SELECT COUNT(*) FROM public.chat_prefs cp
			                    JOIN public.profiles pp ON pp.id = cp.profile_id
			                    WHERE pp.family_id = fam.id AND cp.push_muted),
			'viewer_invitations_open', (SELECT COUNT(*) FROM public.family_invitations vi
			                    WHERE vi.family_id = fam.id AND vi.member_type = 'viewer'
			                      AND vi.accepted_at IS NULL AND vi.revoked_at IS NULL
			                      AND vi.expires_at > now()),
			'subscription', (
				SELECT jsonb_build_object(
					'gateway',            s.gateway,
					'status',             s.status,
					'cycle',              s.cycle,
					'current_period_end', s.current_period_end,
					'overdue_since',      s.overdue_since,
					'canceled_at',        s.canceled_at
				)
				FROM public.subscriptions s WHERE s.family_id = fam.id
			),
			'invitations', (
				SELECT jsonb_build_object(
					'open',     COUNT(*) FILTER (WHERE i.accepted_at IS NULL AND i.revoked_at IS NULL AND i.expires_at > now()),
					'accepted', COUNT(*) FILTER (WHERE i.accepted_at IS NOT NULL),
					'expired',  COUNT(*) FILTER (WHERE i.accepted_at IS NULL AND i.revoked_at IS NULL AND i.expires_at <= now()),
					'revoked',  COUNT(*) FILTER (WHERE i.accepted_at IS NULL AND i.revoked_at IS NOT NULL),
					'oldest_open_created_at',
					            MIN(i.created_at) FILTER (WHERE i.accepted_at IS NULL AND i.revoked_at IS NULL AND i.expires_at > now())
				)
				FROM public.family_invitations i WHERE i.family_id = fam.id
			)
		),

		'members', (
			SELECT COALESCE(jsonb_agg(jsonb_build_object(
				'profile_id',             p.id,
				'role',                   CASE WHEN r.family_id IS NULL THEN r.role ELSE 'custom' END,
				'is_admin',               p.is_admin,
				'membership',             p.membership_type,
				'state',                  CASE WHEN p.left_at IS NOT NULL THEN 'departed'
				                               WHEN p.user_id IS NULL     THEN 'pending'
				                               ELSE 'active' END,
				'created_at',             p.created_at,
				'joined_via_invite',      p.joined_via_invite,
				'left_at',                p.left_at,
				'has_password',           (SELECT COALESCE(u.encrypted_password, '') <> ''
				                           FROM auth.users u WHERE u.id = p.user_id),
				'has_google',             EXISTS (SELECT 1 FROM auth.identities i
				                                  WHERE i.user_id = p.user_id AND i.provider = 'google'),
				'language',               p.language_effective,
				'tour_seen_at',           p.onboarding_tour_seen_at,
				'consent_policy_version', p.consent_policy_version,
				'consent_accepted_at',    p.consent_accepted_at,
				'last_active_day',        la.last_day,
				'last_active_source',     la.last_source,
				'active_days_30', (
					SELECT COUNT(DISTINCT a.day) FROM public.member_activity_days a
					WHERE a.profile_id = p.id AND a.day > today - active_win
				),
				'channels_30', (
					SELECT COALESCE(jsonb_agg(DISTINCT a.channel), '[]'::jsonb)
					FROM public.member_activity_days a
					WHERE a.profile_id = p.id AND a.day > today - active_win
				),
				'devices', (
					SELECT COALESCE(jsonb_agg(jsonb_build_object(
						'platform',     ps.platform,
						'count',        ps.n,
						'last_seen_at', ps.last_seen
					) ORDER BY ps.platform), '[]'::jsonb)
					FROM (
						SELECT platform, COUNT(*) AS n, MAX(last_seen_at) AS last_seen
						FROM public.push_subscriptions
						WHERE profile_id = p.id
						GROUP BY platform
					) ps
				),
				'unread', (
					SELECT COALESCE(jsonb_agg(jsonb_build_object(
						'type',  un.type,
						'count', un.n
					) ORDER BY un.type), '[]'::jsonb)
					FROM (
						SELECT type, COUNT(*) AS n
						FROM public.notifications
						WHERE recipient_profile_id = p.id AND NOT COALESCE(is_read, false)
						GROUP BY type
					) un
				)
			) ORDER BY p.id), '[]'::jsonb)
			FROM public.profiles p
			LEFT JOIN public.roles r ON r.id = p.role_id
			LEFT JOIN LATERAL public.member_last_active(p.id) la ON true
			WHERE p.family_id = fam.id
		),

		'plan', (
			SELECT jsonb_build_object(
				'first_day',                   MIN(day),
				'last_day',                    MAX(day),
				'days_total',                  COUNT(*),
				'days_ahead',                  COUNT(*) FILTER (WHERE day >= today),
				'days_with_handoff_time',      COUNT(*) FILTER (WHERE handoff_time IS NOT NULL),
				'days_with_note',              COUNT(*) FILTER (WHERE has_note),
				'days_diverged',               COUNT(*) FILTER (WHERE actual IS NOT NULL AND actual IS DISTINCT FROM planned),
				'transitions_ahead',           COUNT(*) FILTER (WHERE day >= today AND transition),
				'transitions_ahead_with_time', COUNT(*) FILTER (WHERE day >= today AND transition AND handoff_time IS NOT NULL),
				'carers_ahead', (
					SELECT COALESCE(jsonb_agg(jsonb_build_object(
						'profile_id', c.carer,
						'days',       c.n
					) ORDER BY c.carer), '[]'::jsonb)
					FROM (
						SELECT carer, COUNT(*) AS n FROM days
						WHERE day >= today AND carer IS NOT NULL
						GROUP BY carer
					) c
				)
			)
			FROM days
		),

		'weeks', (
			SELECT COALESCE(jsonb_agg(jsonb_build_object(
				'week_start', wk.week_start,
				'edits', (
					SELECT COUNT(DISTINCT e.unit) FROM edits e
					WHERE e.day >= wk.week_start AND e.day < wk.week_start + 7
				),
				'edits_by_member', (
					SELECT COALESCE(jsonb_agg(jsonb_build_object(
						'profile_id', em.performed_by_id,
						'count',      em.n
					) ORDER BY em.performed_by_id), '[]'::jsonb)
					FROM (
						SELECT e.performed_by_id, COUNT(DISTINCT e.unit) AS n
						FROM edits e
						WHERE e.day >= wk.week_start AND e.day < wk.week_start + 7
						GROUP BY e.performed_by_id
					) em
				),
				'admin_overrides', (
					SELECT COUNT(DISTINCT e.unit) FROM edits e
					WHERE e.override AND e.day >= wk.week_start AND e.day < wk.week_start + 7
				),
				'swaps_opened', (
					SELECT COUNT(*) FROM public.swap_requests s
					WHERE s.family_id = fam.id
					  AND (s.created_at AT TIME ZONE 'America/Sao_Paulo')::date >= wk.week_start
					  AND (s.created_at AT TIME ZONE 'America/Sao_Paulo')::date <  wk.week_start + 7
				),
				'swaps_resolved', (
					SELECT COUNT(*) FROM public.swap_requests s
					WHERE s.family_id = fam.id
					  AND (s.resolved_at AT TIME ZONE 'America/Sao_Paulo')::date >= wk.week_start
					  AND (s.resolved_at AT TIME ZONE 'America/Sao_Paulo')::date <  wk.week_start + 7
				),
				'notices', (
					SELECT COUNT(*) FROM public.day_notices n
					WHERE n.family_id = fam.id
					  AND (n.created_at AT TIME ZONE 'America/Sao_Paulo')::date >= wk.week_start
					  AND (n.created_at AT TIME ZONE 'America/Sao_Paulo')::date <  wk.week_start + 7
				),
				'agenda_events', (
					SELECT COUNT(*) FROM public.child_events ce
					WHERE ce.family_id = fam.id AND ce.source_schedule_id IS NULL
					  AND ce.batch_id IS NULL
					  AND (ce.created_at AT TIME ZONE 'America/Sao_Paulo')::date >= wk.week_start
					  AND (ce.created_at AT TIME ZONE 'America/Sao_Paulo')::date <  wk.week_start + 7
				),
				'day_accounts', (
					SELECT COUNT(*) FROM public.day_accounts da
					WHERE da.family_id = fam.id
					  AND (da.created_at AT TIME ZONE 'America/Sao_Paulo')::date >= wk.week_start
					  AND (da.created_at AT TIME ZONE 'America/Sao_Paulo')::date <  wk.week_start + 7
				),
				'active_members', (
					SELECT COUNT(DISTINCT a.profile_id)
					FROM public.member_activity_days a
					JOIN public.profiles p ON p.id = a.profile_id
					WHERE p.family_id = fam.id
					  AND a.day >= wk.week_start AND a.day < wk.week_start + 7
				)
			) ORDER BY wk.week_start), '[]'::jsonb)
			FROM weeks wk
		),

		'swaps', jsonb_build_object(
			'by_status', (
				SELECT COALESCE(jsonb_agg(jsonb_build_object(
					'status',      bs.status,
					'resolved_by', bs.resolved_by,
					'count',       bs.n
				) ORDER BY bs.status, bs.resolved_by), '[]'::jsonb)
				FROM (
					SELECT status, resolved_by, COUNT(*) AS n
					FROM public.swap_requests
					WHERE family_id = fam.id
					GROUP BY status, resolved_by
				) bs
			),
			-- The COUNTERPART's answer: approved or rejected by a person. A
			-- cancellation is the requester's own act and an auto-approval
			-- (F-24, resolved_by 'system') is nobody's — both would skew it.
			'median_answer_hours', (
				SELECT round((percentile_cont(0.5) WITHIN GROUP (
					ORDER BY extract(epoch FROM s.resolved_at - s.created_at) / 3600.0))::numeric, 1)
				FROM public.swap_requests s
				WHERE s.family_id = fam.id
				  AND s.resolved_by = 'user'
				  AND s.status IN ('approved', 'rejected', 'revert_approved', 'revert_rejected')
				  AND s.resolved_at IS NOT NULL
			),
			'pending', (
				SELECT COUNT(*) FROM public.swap_requests s
				WHERE s.family_id = fam.id AND s.status IN ('pending', 'revert_pending')
			),
			'oldest_pending_created_at', (
				SELECT MIN(s.created_at) FROM public.swap_requests s
				WHERE s.family_id = fam.id AND s.status IN ('pending', 'revert_pending')
			)
		),

		'notices', jsonb_build_object(
			'total', (SELECT COUNT(*) FROM public.day_notices n WHERE n.family_id = fam.id),
			'by_outcome', (
				SELECT COALESCE(jsonb_agg(jsonb_build_object(
					'outcome', bo.outcome,
					'count',   bo.n
				) ORDER BY bo.outcome), '[]'::jsonb)
				FROM (
					SELECT COALESCE(o.outcome, 'none') AS outcome, COUNT(*) AS n
					FROM public.day_notices n
					LEFT JOIN public.day_notice_outcomes o ON o.notice_id = n.id
					WHERE n.family_id = fam.id
					GROUP BY COALESCE(o.outcome, 'none')
				) bo
			)
		),

		'day_accounts', jsonb_build_object(
			'total',       (SELECT COUNT(*) FROM public.day_accounts da WHERE da.family_id = fam.id),
			'corrections', (SELECT COUNT(*) FROM public.day_accounts da
			                WHERE da.family_id = fam.id AND da.corrects_id IS NOT NULL)
		),

		-- F-55: the child entity and the agenda — counts only, never a name
		-- or an event's text.
		'agenda', jsonb_build_object(
			'children',       (SELECT COUNT(*) FROM public.children c WHERE c.family_id = fam.id),
			'events_active',  (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.deleted_at IS NULL),
			'events_ahead',   (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.deleted_at IS NULL
			                     AND ce.event_date >= today),
			'events_deleted', (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.deleted_at IS NOT NULL),
			'notes_active',   (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.deleted_at IS NULL
			                     AND ce.kind = 'note'),
			'converted',      (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.source_schedule_id IS NOT NULL),
			'routines',       (SELECT COUNT(*) FROM public.child_routines cr
			                   WHERE cr.family_id = fam.id AND cr.stopped_at IS NULL),
			'events_from_routine', (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.deleted_at IS NULL
			                     AND ce.batch_id IS NOT NULL),
			'with_reminder',  (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.deleted_at IS NULL
			                     AND ce.remind_minutes IS NOT NULL),
			'reminders_sent', (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.reminded_at IS NOT NULL),
			'by_kind', (
				SELECT COALESCE(jsonb_agg(jsonb_build_object(
					'kind',  bk.kind,
					'count', bk.n
				) ORDER BY bk.kind), '[]'::jsonb)
				FROM (
					SELECT kind, COUNT(*) AS n FROM public.child_events
					WHERE family_id = fam.id AND deleted_at IS NULL
					GROUP BY kind
				) bk
			)
		)
	) INTO result;

	RETURN result;
END;
$$;
