-- =============================================================================
-- F-34 — the settle-up after the owner's validation (25/09/2026)
--
-- What the owner saw on the phone: a R$ 1.000 payment recorded with no
-- expense at all (the "Registrar pagamento" door was always there and nothing
-- capped it), a balance told in sentences, and a second device that never
-- caught up. Decided with the owner the same day:
--
--   1. A payment is capped by what is owed. `request_settlement` refuses more
--      than the smaller of (what the payer owes in the group) and (what the
--      receiver is owed in the group) — counting the payments still waiting
--      for confirmation, so two taps cannot pay a debt twice. Partial payments
--      stay allowed. With two caregivers this is exactly the debt between
--      them; with more, it is any payment that lowers both balances.
--   2. "Lembrar": the one who is owed may remind the one who owes — an in-app
--      notice and a push (`settlement_reminder`, born ON in T-83's switch),
--      never e-mail, with no amount in the text. At most one per pair per
--      `expenses.reminder_cooldown_hours` (T-84: the number lives in a key).
--   3. Realtime: the four expense tables join the publication, so both
--      phones see an expense, a payment and its confirmation as they happen.
-- =============================================================================


-- ── 1. The key ───────────────────────────────────────────────────────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, min_value, max_value, help)
VALUES
	('expenses.reminder_cooldown_hours', '24', 'int', 'expenses',
	 'Intervalo mínimo entre dois lembretes de acerto da mesma pessoa para a mesma pessoa.',
	 false, 'hours', 'normal', 1, 168,
	 jsonb_build_object(
		'controls', 'De quanto em quanto tempo quem tem a receber pode lembrar quem deve (botão Lembrar em Despesas).',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Menos lembretes possíveis: menos pressão entre os responsáveis, cobrança mais lenta.',
		'if_decreased', 'Lembretes mais frequentes; abaixo de um dia pode virar cobrança insistente.',
		'takes_effect', 'Servidor no próximo lembrete.',
		'caveats', 'O lembrete não diz valor; o app mostra o saldo a quem abre Despesas.'))
ON CONFLICT (key) DO NOTHING;


-- ── 2. The balance, server-side ─────────────────────────────────────────────
-- The client's `ExpenseLedger.net` in SQL: the payer is credited the amount,
-- each participant debited their share, a CONFIRMED payment credits who paid
-- and debits who received. One group = one child (NULL = the family's own).

CREATE OR REPLACE FUNCTION public.expense_net(p_family_id bigint, p_child_id bigint, p_profile_id bigint)
RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
	SELECT
		coalesce((SELECT sum(e.amount_cents) FROM public.expenses e
		          WHERE e.family_id = p_family_id AND e.deleted_at IS NULL
		            AND e.child_id IS NOT DISTINCT FROM p_child_id
		            AND e.paid_by = p_profile_id), 0)
	  - coalesce((SELECT sum(s.share_cents) FROM public.expense_shares s
		          JOIN public.expenses e ON e.id = s.expense_id
		          WHERE e.family_id = p_family_id AND e.deleted_at IS NULL
		            AND e.child_id IS NOT DISTINCT FROM p_child_id
		            AND s.profile_id = p_profile_id), 0)
	  + coalesce((SELECT sum(st.amount_cents) FROM public.expense_settlements st
		          WHERE st.family_id = p_family_id AND st.status = 'confirmed'
		            AND st.child_id IS NOT DISTINCT FROM p_child_id
		            AND st.from_profile = p_profile_id), 0)
	  - coalesce((SELECT sum(st.amount_cents) FROM public.expense_settlements st
		          WHERE st.family_id = p_family_id AND st.status = 'confirmed'
		            AND st.child_id IS NOT DISTINCT FROM p_child_id
		            AND st.to_profile = p_profile_id), 0);
$$;

ALTER FUNCTION public.expense_net(bigint, bigint, bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.expense_net(bigint, bigint, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expense_net(bigint, bigint, bigint) TO service_role;

-- How much [p_from] may still pay [p_to] in the group: the smaller of the
-- payer's debt and the receiver's credit, each net of the payments already
-- waiting for an answer. Zero or less = nothing to pay.
CREATE OR REPLACE FUNCTION public.settlement_room(p_family_id bigint, p_child_id bigint,
                                                  p_from bigint, p_to bigint)
RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
	SELECT least(
		-public.expense_net(p_family_id, p_child_id, p_from)
		  - coalesce((SELECT sum(amount_cents) FROM public.expense_settlements
		              WHERE family_id = p_family_id AND status = 'pending'
		                AND child_id IS NOT DISTINCT FROM p_child_id
		                AND from_profile = p_from), 0),
		public.expense_net(p_family_id, p_child_id, p_to)
		  - coalesce((SELECT sum(amount_cents) FROM public.expense_settlements
		              WHERE family_id = p_family_id AND status = 'pending'
		                AND child_id IS NOT DISTINCT FROM p_child_id
		                AND to_profile = p_to), 0));
$$;

ALTER FUNCTION public.settlement_room(bigint, bigint, bigint, bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.settlement_room(bigint, bigint, bigint, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settlement_room(bigint, bigint, bigint, bigint) TO service_role;


-- ── 3. "I paid X to Y" — now capped by what is owed ─────────────────────────
-- Body from 20260924160000_f34_expenses.sql plus the room check.

CREATE OR REPLACE FUNCTION public.request_settlement(p_child_id bigint, p_to bigint, p_amount bigint)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me      public.profiles%ROWTYPE := public.expense_writer_guard();
	max_amt bigint := public.setting_int('expenses.max_amount_cents', 10000000);
	room    bigint;
	new_id  bigint;
BEGIN
	IF p_to IS NULL OR p_to = me.id OR NOT public.expense_member_ok(me.family_id, p_to) THEN
		RAISE EXCEPTION 'Escolha o responsável que recebeu o pagamento.' USING ERRCODE = 'check_violation';
	END IF;
	IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_to AND user_id IS NOT NULL) THEN
		RAISE EXCEPTION 'Quem recebeu ainda não tem conta para confirmar o acerto.' USING ERRCODE = 'check_violation';
	END IF;
	IF p_amount IS NULL OR p_amount <= 0 THEN
		RAISE EXCEPTION 'Informe o valor do acerto.' USING ERRCODE = 'check_violation';
	END IF;
	IF p_amount > max_amt THEN
		RAISE EXCEPTION 'O valor passa do limite de % por acerto.', public.brl_text(max_amt)
			USING ERRCODE = 'check_violation';
	END IF;
	IF p_child_id IS NOT NULL AND NOT EXISTS (
		SELECT 1 FROM public.children WHERE id = p_child_id AND family_id = me.family_id) THEN
		RAISE EXCEPTION 'Criança não encontrada na sua família.' USING ERRCODE = 'check_violation';
	END IF;

	-- The owner's validation: a payment settles a debt, it never creates one.
	-- Serialised per family, so two taps cannot both fit the same room.
	PERFORM pg_advisory_xact_lock(hashtext('settlement:' || me.family_id::text));
	room := public.settlement_room(me.family_id, p_child_id, me.id, p_to);
	IF room <= 0 THEN
		RAISE EXCEPTION 'Você não tem saldo a pagar a essa pessoa.' USING ERRCODE = 'check_violation';
	END IF;
	IF p_amount > room THEN
		RAISE EXCEPTION 'O valor passa do que você deve a essa pessoa (%).', public.brl_text(room)
			USING ERRCODE = 'check_violation';
	END IF;

	INSERT INTO public.expense_settlements (family_id, child_id, from_profile, to_profile, amount_cents, created_by)
	VALUES (me.family_id, p_child_id, me.id, p_to, p_amount, me.id)
	RETURNING id INTO new_id;
	PERFORM public.settlement_notify(new_id);
	RETURN new_id;
END;
$$;

ALTER FUNCTION public.request_settlement(bigint, bigint, bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.request_settlement(bigint, bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_settlement(bigint, bigint, bigint) TO authenticated, service_role;


-- ── 4. "Lembrar" ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.expense_reminders (
	id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	family_id     bigint NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
	child_id      bigint REFERENCES public.children(id) ON DELETE SET NULL,
	from_profile  bigint NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
	to_profile    bigint NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
	created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS expense_reminders_pair_idx
	ON public.expense_reminders (from_profile, to_profile, created_at);

-- Server-only: the RPC below reads and writes it; no client ever does.
ALTER TABLE public.expense_reminders ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.expense_reminders FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.expense_reminders TO service_role;

CREATE OR REPLACE FUNCTION public.remind_settlement(p_child_id bigint, p_to bigint)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me       public.profiles%ROWTYPE := public.expense_writer_guard();
	cooldown int := public.setting_int('expenses.reminder_cooldown_hours', 24);
	who      text;
	day_     text;
BEGIN
	IF p_to IS NULL OR p_to = me.id OR NOT public.expense_member_ok(me.family_id, p_to)
	   OR NOT EXISTS (SELECT 1 FROM public.profiles
	                  WHERE id = p_to AND user_id IS NOT NULL AND left_at IS NULL) THEN
		RAISE EXCEPTION 'Escolha o responsável que deve o acerto.' USING ERRCODE = 'check_violation';
	END IF;
	IF p_child_id IS NOT NULL AND NOT EXISTS (
		SELECT 1 FROM public.children WHERE id = p_child_id AND family_id = me.family_id) THEN
		RAISE EXCEPTION 'Criança não encontrada na sua família.' USING ERRCODE = 'check_violation';
	END IF;
	-- Only a debt that is still open, counting what they already sent.
	IF public.settlement_room(me.family_id, p_child_id, p_to, me.id) <= 0 THEN
		RAISE EXCEPTION 'Essa pessoa não tem acerto pendente com você.' USING ERRCODE = 'check_violation';
	END IF;
	IF EXISTS (SELECT 1 FROM public.expense_reminders
	           WHERE from_profile = me.id AND to_profile = p_to
	             AND child_id IS NOT DISTINCT FROM p_child_id
	             AND created_at > now() - make_interval(hours => cooldown)) THEN
		RAISE EXCEPTION 'Você já lembrou essa pessoa há pouco. Um novo lembrete fica disponível % h depois do anterior.', cooldown
			USING ERRCODE = 'check_violation';
	END IF;

	INSERT INTO public.expense_reminders (family_id, child_id, from_profile, to_profile)
	VALUES (me.family_id, p_child_id, me.id, p_to);

	who := coalesce(nullif(btrim(me.full_name), ''), 'Um membro da família');
	day_ := to_char((now() AT TIME ZONE 'America/Sao_Paulo')::date, 'YYYY-MM-DD');
	INSERT INTO public.notifications (recipient_profile_id, type, title, message, params)
	VALUES (p_to, 'settlement_reminder', 'Lembrete de acerto',
	        who || ' lembrou do acerto pendente entre vocês. Veja o saldo em Despesas.',
	        jsonb_build_object('date', day_, 'name', who));
END;
$$;

ALTER FUNCTION public.remind_settlement(bigint, bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.remind_settlement(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remind_settlement(bigint, bigint) TO authenticated, service_role;


-- ── 5. Realtime ──────────────────────────────────────────────────────────────
-- Realtime applies each table's SELECT policy to the subscriber: a viewer
-- (F-50) and another family receive nothing, as with the reads.

DO $$
DECLARE
	t text;
BEGIN
	FOREACH t IN ARRAY ARRAY['expenses', 'expense_shares', 'expense_settlements'] LOOP
		BEGIN
			EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
		EXCEPTION
			WHEN duplicate_object THEN NULL;
			WHEN undefined_object THEN NULL;
		END;
	END LOOP;
END $$;


-- ── 6. Push: the reminder ────────────────────────────────────────────────────
-- Copied VERBATIM from 20260924170000_f35_chat.sql with 'settlement_reminder'
-- in the filter — and so in T-83's `push.disabled_types` vocabulary (read
-- from this filter), born ON. The push mirror reads the first type filter of
-- the newest file that defines the dispatcher — this one, so nothing above
-- this function may spell that filter out, not even in a comment.

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
		'settlement_reminder',
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
