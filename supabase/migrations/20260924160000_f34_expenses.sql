-- =============================================================================
-- F-34 (PR 1 of 2) — shared expenses: the Splitwise logic, with ONE difference
--
-- Decisions locked by the owner (24/09/2026, F-34 Notes). Source for the
-- Splitwise behaviour: its help center (kb.splitwise.com — ways to split,
-- "simplify debts", settle up, who can edit, restoring), recorded on the card.
--
--   * One expense group per child (`child_id`, F-55; NULL = the family's own
--     group while no child is registered). Any caregiver with a full seat adds,
--     edits and deletes — no approval (Splitwise: "no special permissions").
--   * Who paid (one payer) + the split among the chosen participants: equally,
--     exact amounts, percentages or shares. Splitwise gives a random person the
--     leftover cent; here the split is DETERMINISTIC — largest remainder, ties
--     to the lowest profile id — because this is a record, and the same inputs
--     must always give the same shares.
--   * The balance is SIMPLIFIED (net per person, then the fewest payments), as
--     the client computes from the rows (entrelares_core); the server stores
--     only facts: expenses, their shares, and settlements.
--   * THE ONE DIFFERENCE: "acertar contas" records a payment that the person
--     who RECEIVED must confirm before it touches the balance (Splitwise
--     dropped that step in 2013; a co-parenting record needs it).
--   * Every edit and delete goes to an append-only trail (`old_data`), shown on
--     the expense and in the PDF. Nothing moves money. No receipts (F-36 is out
--     of the chain). Closed categories; BRL only, in cents.
--   * A viewer (F-50) neither sees nor writes expenses. Premium, gated on the
--     server; downgrade = read-only. On leaving (S-11) the rows stay in the
--     tombstone's name; they go only with the family.
--   * Notifications: in-app + push to the participants, never e-mail — three
--     new push types (born ON in T-83's switch). F-69: counts only.
--   * Dark in production: `feature.expenses`.
-- =============================================================================


-- ── 1. The keys (T-84 catalogue) ─────────────────────────────────────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, min_value, max_value, help)
VALUES
	('feature.expenses', 'false', 'bool', 'features',
	 'Liga as despesas compartilhadas (F-34): aba Despesas, divisão e acertos. Desligado, o servidor recusa as escritas.',
	 true, 'flag', 'critical', NULL, NULL,
	 jsonb_build_object(
		'controls', 'Se add/update/delete_expense e os acertos aceitam chamadas, e se a aba Despesas aparece.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Ligado: a família registra despesas da criança, divide entre os responsáveis e acerta contas com confirmação.',
		'if_decreased', 'Desligado: a aba some e o servidor recusa escrever; as despesas já lançadas ficam guardadas.',
		'takes_effect', 'Servidor na próxima chamada; app na próxima abertura.',
		'caveats', 'Produção nasce desligada: o S-22 liga junto com a política.')),
	('expenses.premium_only', 'true', 'bool', 'expenses',
	 'Só o Premium lança despesas e acerta contas.',
	 true, 'flag', 'critical', NULL, NULL,
	 jsonb_build_object(
		'controls', 'Se as escritas de despesas e acertos recusam família sem Premium.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Ligado (padrão): despesas são benefício Premium; a família gratuita vê o convite para o plano.',
		'if_decreased', 'Desligado: toda família usa as despesas.',
		'takes_effect', 'Servidor na próxima escrita; app na próxima abertura.',
		'caveats', 'Rebaixamento: as despesas ficam em só leitura, nada é apagado.')),
	('expenses.description_max_chars', '200', 'int', 'expenses',
	 'Tamanho máximo da descrição de uma despesa.',
	 true, 'chars', 'normal', 50, 500,
	 jsonb_build_object(
		'controls', 'Quantos caracteres a descrição de uma despesa aceita.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Descrições mais longas; o extrato do PDF cresce. Não passa de 500: é o CHECK da coluna.',
		'if_decreased', 'Despesas já gravadas com texto maior ficam; só a próxima gravação respeita o novo limite.',
		'takes_effect', 'Servidor na próxima gravação; app na próxima abertura.')),
	('expenses.max_amount_cents', '10000000', 'int', 'expenses',
	 'Valor máximo de uma despesa ou de um acerto, em centavos.',
	 true, 'cents_brl', 'normal', 100000, 100000000,
	 jsonb_build_object(
		'controls', 'O teto de uma despesa ou de um acerto — um freio contra erro de digitação (um zero a mais).',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Aceita valores maiores numa despesa só.',
		'if_decreased', 'Despesas maiores já gravadas ficam; só lançamentos novos respeitam o teto.',
		'takes_effect', 'Servidor na próxima gravação; app na próxima abertura.'))
ON CONFLICT (key) DO NOTHING;


-- ── 2. The tables ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.expenses (
	id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	family_id      bigint NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
	child_id       bigint REFERENCES public.children(id) ON DELETE SET NULL,
	description    text NOT NULL CHECK (description = btrim(description) AND char_length(description) BETWEEN 1 AND 500),
	category       text NOT NULL
	               CHECK (category IN ('school', 'health', 'clothes', 'activities', 'food', 'transport', 'other')),
	amount_cents   bigint NOT NULL CHECK (amount_cents > 0),
	paid_by        bigint NOT NULL REFERENCES public.profiles(id),
	spent_on       date NOT NULL,
	split_method   text NOT NULL CHECK (split_method IN ('equal', 'exact', 'percent', 'shares')),
	created_by     bigint REFERENCES public.profiles(id),
	created_at     timestamptz NOT NULL DEFAULT now(),
	updated_by     bigint REFERENCES public.profiles(id),
	updated_at     timestamptz,
	deleted_by     bigint REFERENCES public.profiles(id),
	deleted_at     timestamptz
);

-- `weight`: what the payer typed — 1 (equal), cents (exact), basis points of a
-- percent (percent, 100% = 10000) or share units (shares). `share_cents`: what
-- the participant owes of the expense, summing EXACTLY to amount_cents.
CREATE TABLE IF NOT EXISTS public.expense_shares (
	expense_id   bigint NOT NULL REFERENCES public.expenses(id) ON DELETE CASCADE,
	profile_id   bigint NOT NULL REFERENCES public.profiles(id),
	weight       bigint NOT NULL CHECK (weight >= 0),
	share_cents  bigint NOT NULL CHECK (share_cents >= 0),
	PRIMARY KEY (expense_id, profile_id)
);

-- Append-only: created, updated (old_data = the expense and shares BEFORE),
-- deleted. No client grant; a trigger refuses UPDATE and DELETE for everyone.
CREATE TABLE IF NOT EXISTS public.expense_history (
	id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	expense_id  bigint NOT NULL REFERENCES public.expenses(id) ON DELETE CASCADE,
	family_id   bigint NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
	action      text NOT NULL CHECK (action IN ('created', 'updated', 'deleted')),
	actor_id    bigint REFERENCES public.profiles(id),
	at          timestamptz NOT NULL DEFAULT now(),
	old_data    jsonb,
	new_data    jsonb
);

CREATE TABLE IF NOT EXISTS public.expense_settlements (
	id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	family_id     bigint NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
	child_id      bigint REFERENCES public.children(id) ON DELETE SET NULL,
	from_profile  bigint NOT NULL REFERENCES public.profiles(id),
	to_profile    bigint NOT NULL REFERENCES public.profiles(id),
	amount_cents  bigint NOT NULL CHECK (amount_cents > 0),
	status        text NOT NULL DEFAULT 'pending'
	              CHECK (status IN ('pending', 'confirmed', 'rejected', 'cancelled')),
	created_by    bigint REFERENCES public.profiles(id),
	created_at    timestamptz NOT NULL DEFAULT now(),
	answered_at   timestamptz,
	CONSTRAINT expense_settlements_two_people CHECK (from_profile <> to_profile)
);

CREATE INDEX IF NOT EXISTS expenses_family_idx ON public.expenses (family_id, spent_on);
CREATE INDEX IF NOT EXISTS expense_history_expense_idx ON public.expense_history (expense_id, at);
CREATE INDEX IF NOT EXISTS expense_settlements_family_idx ON public.expense_settlements (family_id, created_at);

DO $$
DECLARE
	t text;
BEGIN
	FOREACH t IN ARRAY ARRAY['expenses', 'expense_shares', 'expense_history', 'expense_settlements'] LOOP
		EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
		EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, anon, authenticated', t);
		EXECUTE format('GRANT SELECT ON public.%I TO authenticated', t);
		EXECUTE format('GRANT ALL ON public.%I TO service_role', t);
		-- F-50: a viewer writes nothing.
		EXECUTE format('DROP TRIGGER IF EXISTS trigger_a_refuse_viewer_write ON public.%I', t);
		EXECUTE format(
			'CREATE TRIGGER trigger_a_refuse_viewer_write
			 BEFORE INSERT OR UPDATE OR DELETE ON public.%I
			 FOR EACH ROW EXECUTE FUNCTION public.refuse_viewer_write()', t);
	END LOOP;
END $$;

-- Read: the family's caregivers — never a viewer (F-50: "não vê Despesas").
DROP POLICY IF EXISTS expenses_family_read ON public.expenses;
CREATE POLICY expenses_family_read ON public.expenses FOR SELECT TO authenticated
	USING (family_id = public.get_my_family_id() AND NOT public.is_viewer_caller());
DROP POLICY IF EXISTS expense_shares_family_read ON public.expense_shares;
CREATE POLICY expense_shares_family_read ON public.expense_shares FOR SELECT TO authenticated
	USING (NOT public.is_viewer_caller() AND EXISTS (
		SELECT 1 FROM public.expenses e
		WHERE e.id = expense_id AND e.family_id = public.get_my_family_id()));
DROP POLICY IF EXISTS expense_history_family_read ON public.expense_history;
CREATE POLICY expense_history_family_read ON public.expense_history FOR SELECT TO authenticated
	USING (family_id = public.get_my_family_id() AND NOT public.is_viewer_caller());
DROP POLICY IF EXISTS expense_settlements_family_read ON public.expense_settlements;
CREATE POLICY expense_settlements_family_read ON public.expense_settlements FOR SELECT TO authenticated
	USING (family_id = public.get_my_family_id() AND NOT public.is_viewer_caller());

CREATE OR REPLACE FUNCTION public.expense_history_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
	-- The family's own deletion cascades through here; nothing else may.
	IF TG_OP = 'DELETE' AND current_setting('app.deletion_context', true) = 'on' THEN
		RETURN OLD;
	END IF;
	RAISE EXCEPTION 'A trilha das despesas não se altera nem se apaga.'
		USING ERRCODE = 'insufficient_privilege';
END;
$$;

REVOKE ALL ON FUNCTION public.expense_history_append_only() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_expense_history_append_only ON public.expense_history;
CREATE TRIGGER trigger_expense_history_append_only
	BEFORE UPDATE OR DELETE ON public.expense_history
	FOR EACH ROW EXECUTE FUNCTION public.expense_history_append_only();


-- ── 3. The writer guard and the split ────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.expense_writer_guard()
RETURNS public.profiles
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me public.profiles%ROWTYPE;
BEGIN
	IF NOT public.setting_bool('feature.expenses', false) THEN
		RAISE EXCEPTION 'As despesas ainda não estão disponíveis.'
			USING ERRCODE = 'feature_not_supported';
	END IF;
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();
	IF me.id IS NULL OR me.left_at IS NOT NULL OR me.membership_type <> 'full' THEN
		RAISE EXCEPTION 'Sua conta não pode lançar despesas.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;
	IF public.setting_bool('expenses.premium_only', true) AND NOT public.is_premium(me.family_id) THEN
		RAISE EXCEPTION 'As despesas compartilhadas são um recurso Premium. Sem o Premium, as despesas lançadas ficam só para leitura.'
			USING ERRCODE = 'check_violation';
	END IF;
	RETURN me;
END;
$$;

ALTER FUNCTION public.expense_writer_guard() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.expense_writer_guard() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expense_writer_guard() TO service_role;

-- A caregiver of the family with an account: full, not departed. A pending
-- placeholder (F-56) is left out on purpose — it cannot confirm a settlement,
-- and `remove_pending_member` deletes a placeholder it finds unreferenced by
-- its own fixed list, which does not (and should not have to) know expenses.
CREATE OR REPLACE FUNCTION public.expense_member_ok(p_family_id bigint, p_profile_id bigint)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
	SELECT EXISTS (SELECT 1 FROM public.profiles
	               WHERE id = p_profile_id AND family_id = p_family_id
	                 AND left_at IS NULL AND membership_type = 'full'
	                 AND user_id IS NOT NULL);
$$;

REVOKE ALL ON FUNCTION public.expense_member_ok(bigint, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expense_member_ok(bigint, bigint) TO service_role;

-- p_parts: [{"profile_id": 12, "value": 1}, …] — value per the method (see
-- expense_shares.weight). Returns the shares, summing exactly to p_amount;
-- the leftover cents go one each to the largest remainders, ties to the
-- lowest profile id (deterministic — a record must be reproducible).
CREATE OR REPLACE FUNCTION public.expense_split(p_amount bigint, p_method text, p_parts jsonb)
RETURNS TABLE (profile_id bigint, weight bigint, share_cents bigint)
LANGUAGE plpgsql IMMUTABLE
SET search_path TO 'public'
AS $$
DECLARE
	total_w bigint;
	n       int;
	n_dist  int;
	neg     boolean;
BEGIN
	IF p_parts IS NULL OR jsonb_typeof(p_parts) <> 'array' OR jsonb_array_length(p_parts) = 0 THEN
		RAISE EXCEPTION 'Escolha quem participa da despesa.'
			USING ERRCODE = 'check_violation';
	END IF;

	SELECT sum(w), count(*), count(DISTINCT pid), bool_or(w IS NULL OR w < 0)
	INTO total_w, n, n_dist, neg
	FROM (SELECT (e->>'profile_id')::bigint AS pid,
	             CASE WHEN p_method = 'equal' THEN 1 ELSE (e->>'value')::bigint END AS w
	      FROM jsonb_array_elements(p_parts) e) x;

	IF n_dist <> n THEN
		RAISE EXCEPTION 'Cada pessoa entra uma vez só na divisão.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF neg THEN
		RAISE EXCEPTION 'Os valores da divisão não podem ser negativos.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF p_method = 'exact' AND total_w <> p_amount THEN
		RAISE EXCEPTION 'Os valores da divisão somam % centavos, e a despesa é de % centavos.', total_w, p_amount
			USING ERRCODE = 'check_violation';
	END IF;
	IF p_method = 'percent' AND total_w <> 10000 THEN
		RAISE EXCEPTION 'Os percentuais da divisão precisam somar 100%%.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF total_w <= 0 THEN
		RAISE EXCEPTION 'A divisão precisa de pelo menos uma parte maior que zero.'
			USING ERRCODE = 'check_violation';
	END IF;

	RETURN QUERY
	WITH parts AS (
		SELECT (e->>'profile_id')::bigint AS pid,
		       CASE WHEN p_method = 'equal' THEN 1 ELSE (e->>'value')::bigint END AS w
		FROM jsonb_array_elements(p_parts) e),
	calc AS (
		SELECT pid, w,
		       CASE WHEN p_method = 'exact' THEN w ELSE (p_amount * w) / total_w END AS base,
		       CASE WHEN p_method = 'exact' THEN 0 ELSE (p_amount * w) % total_w END AS rem
		FROM parts),
	ranked AS (
		SELECT calc.*, row_number() OVER (ORDER BY rem DESC, pid ASC) AS rn FROM calc),
	leftover AS (
		SELECT p_amount - sum(base) AS l FROM calc)
	SELECT r.pid, r.w, r.base + CASE WHEN r.rn <= lo.l THEN 1 ELSE 0 END
	FROM ranked r CROSS JOIN leftover lo
	ORDER BY r.pid;
END;
$$;

REVOKE ALL ON FUNCTION public.expense_split(bigint, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.expense_split(bigint, text, jsonb) TO authenticated, service_role;

-- ── 4. Money in words, for the stored sentence (U-13: byte-identical to the
--      Dart catalog's PT-BR, which the reader's device rebuilds from params) ──

CREATE OR REPLACE FUNCTION public.brl_text(p_cents bigint)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $$
	SELECT 'R$ ' ||
	       regexp_replace((abs(p_cents) / 100)::text, '(\d)(?=(\d{3})+$)', '\1.', 'g') ||
	       ',' || lpad((abs(p_cents) % 100)::text, 2, '0');
$$;

REVOKE ALL ON FUNCTION public.brl_text(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.brl_text(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.expense_category_pt(p_category text)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $$
	SELECT CASE p_category
		WHEN 'school'     THEN 'Escola'
		WHEN 'health'     THEN 'Saúde'
		WHEN 'clothes'    THEN 'Roupas'
		WHEN 'activities' THEN 'Atividades'
		WHEN 'food'       THEN 'Alimentação'
		WHEN 'transport'  THEN 'Transporte'
		ELSE 'Outros' END;
$$;

REVOKE ALL ON FUNCTION public.expense_category_pt(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expense_category_pt(text) TO service_role;


-- ── 5. The one writer of the expense notifications ───────────────────────────
-- To the payer and the participants, never the actor, never a viewer (a viewer
-- is never either), never a placeholder without an account.

CREATE OR REPLACE FUNCTION public.expense_notify(p_expense_id bigint, p_kind text, p_actor bigint)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	e       public.expenses%ROWTYPE;
	v_actor text;
	v_title text;
	v_verb  text;
BEGIN
	SELECT * INTO e FROM public.expenses WHERE id = p_expense_id;
	SELECT coalesce(nullif(btrim(full_name), ''), 'Um membro da família') INTO v_actor
	FROM public.profiles WHERE id = p_actor;
	v_actor := coalesce(v_actor, 'Um membro da família');
	v_title := CASE p_kind WHEN 'added' THEN 'Despesa lançada'
	                       WHEN 'updated' THEN 'Despesa alterada'
	                       ELSE 'Despesa apagada' END;
	v_verb  := CASE p_kind WHEN 'added' THEN ' lançou uma despesa de '
	                       WHEN 'updated' THEN ' alterou uma despesa de '
	                       ELSE ' apagou uma despesa de ' END;

	INSERT INTO public.notifications (recipient_profile_id, type, title, message, params)
	SELECT p.id, 'expense_changed', v_title,
	       v_actor || v_verb || public.brl_text(e.amount_cents) || ' em ' ||
	       to_char(e.spent_on, 'DD/MM/YYYY') || ': ' || public.expense_category_pt(e.category) ||
	       '. ' || e.description,
	       jsonb_build_object(
	           'kind',     p_kind,
	           'date',     to_char(e.spent_on, 'YYYY-MM-DD'),
	           'amount',   e.amount_cents::text,
	           'category', e.category,
	           'name',     v_actor,
	           'msg',      e.description)
	FROM public.profiles p
	WHERE p.family_id = e.family_id
	  AND p.left_at IS NULL AND p.user_id IS NOT NULL AND p.membership_type = 'full'
	  AND p.id <> p_actor
	  AND (p.id = e.paid_by OR EXISTS (
	         SELECT 1 FROM public.expense_shares s
	         WHERE s.expense_id = e.id AND s.profile_id = p.id));
END;
$$;

ALTER FUNCTION public.expense_notify(bigint, text, bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.expense_notify(bigint, text, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expense_notify(bigint, text, bigint) TO service_role;


-- ── 6. Add, update, delete ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.expense_snapshot(p_expense_id bigint)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
	SELECT to_jsonb(e) - 'family_id' || jsonb_build_object('shares', (
		SELECT COALESCE(jsonb_agg(jsonb_build_object(
			'profile_id', s.profile_id, 'weight', s.weight, 'share_cents', s.share_cents)
			ORDER BY s.profile_id), '[]'::jsonb)
		FROM public.expense_shares s WHERE s.expense_id = e.id))
	FROM public.expenses e WHERE e.id = p_expense_id;
$$;

REVOKE ALL ON FUNCTION public.expense_snapshot(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expense_snapshot(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.expense_validate(
	p_family_id  bigint,
	p_child_id   bigint,
	p_desc       text,
	p_category   text,
	p_amount     bigint,
	p_paid_by    bigint,
	p_method     text,
	p_parts      jsonb)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	v_desc  text := nullif(btrim(coalesce(p_desc, '')), '');
	max_chr int  := public.setting_int('expenses.description_max_chars', 200);
	max_amt bigint := public.setting_int('expenses.max_amount_cents', 10000000);
	bad     bigint;
BEGIN
	IF v_desc IS NULL THEN
		RAISE EXCEPTION 'Descreva a despesa.' USING ERRCODE = 'check_violation';
	END IF;
	IF char_length(v_desc) > max_chr THEN
		RAISE EXCEPTION 'A descrição da despesa é limitada a % caracteres.', max_chr
			USING ERRCODE = 'check_violation';
	END IF;
	IF p_category IS NULL OR p_category NOT IN ('school', 'health', 'clothes', 'activities', 'food', 'transport', 'other') THEN
		RAISE EXCEPTION 'Categoria de despesa desconhecida.' USING ERRCODE = 'check_violation';
	END IF;
	IF p_amount IS NULL OR p_amount <= 0 THEN
		RAISE EXCEPTION 'Informe o valor da despesa.' USING ERRCODE = 'check_violation';
	END IF;
	IF p_amount > max_amt THEN
		RAISE EXCEPTION 'O valor passa do limite de % por despesa.', public.brl_text(max_amt)
			USING ERRCODE = 'check_violation';
	END IF;
	IF p_method IS NULL OR p_method NOT IN ('equal', 'exact', 'percent', 'shares') THEN
		RAISE EXCEPTION 'Forma de divisão desconhecida.' USING ERRCODE = 'check_violation';
	END IF;
	IF p_child_id IS NOT NULL AND NOT EXISTS (
		SELECT 1 FROM public.children WHERE id = p_child_id AND family_id = p_family_id) THEN
		RAISE EXCEPTION 'Criança não encontrada na sua família.' USING ERRCODE = 'check_violation';
	END IF;
	IF NOT public.expense_member_ok(p_family_id, p_paid_by) THEN
		RAISE EXCEPTION 'Quem pagou precisa ser um responsável da família.' USING ERRCODE = 'check_violation';
	END IF;
	SELECT s.profile_id INTO bad
	FROM public.expense_split(p_amount, p_method, p_parts) s
	WHERE NOT public.expense_member_ok(p_family_id, s.profile_id)
	LIMIT 1;
	IF bad IS NOT NULL THEN
		RAISE EXCEPTION 'Só responsáveis da família participam da divisão.' USING ERRCODE = 'check_violation';
	END IF;
	RETURN v_desc;
END;
$$;

REVOKE ALL ON FUNCTION public.expense_validate(bigint, bigint, text, text, bigint, bigint, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expense_validate(bigint, bigint, text, text, bigint, bigint, text, jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.add_expense(
	p_child_id  bigint,
	p_desc      text,
	p_category  text,
	p_amount    bigint,
	p_paid_by   bigint,
	p_spent_on  date,
	p_method    text,
	p_parts     jsonb)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me     public.profiles%ROWTYPE := public.expense_writer_guard();
	v_desc text;
	new_id bigint;
BEGIN
	v_desc := public.expense_validate(me.family_id, p_child_id, p_desc, p_category, p_amount, p_paid_by, p_method, p_parts);
	IF p_spent_on IS NULL THEN
		RAISE EXCEPTION 'Informe a data da despesa.' USING ERRCODE = 'check_violation';
	END IF;

	INSERT INTO public.expenses
		(family_id, child_id, description, category, amount_cents, paid_by, spent_on, split_method, created_by)
	VALUES (me.family_id, p_child_id, v_desc, p_category, p_amount, p_paid_by, p_spent_on, p_method, me.id)
	RETURNING id INTO new_id;

	INSERT INTO public.expense_shares (expense_id, profile_id, weight, share_cents)
	SELECT new_id, s.profile_id, s.weight, s.share_cents
	FROM public.expense_split(p_amount, p_method, p_parts) s;

	INSERT INTO public.expense_history (expense_id, family_id, action, actor_id, new_data)
	VALUES (new_id, me.family_id, 'created', me.id, public.expense_snapshot(new_id));

	PERFORM public.expense_notify(new_id, 'added', me.id);
	RETURN new_id;
END;
$$;

ALTER FUNCTION public.add_expense(bigint, text, text, bigint, bigint, date, text, jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.add_expense(bigint, text, text, bigint, bigint, date, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_expense(bigint, text, text, bigint, bigint, date, text, jsonb) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.update_expense(
	p_id        bigint,
	p_child_id  bigint,
	p_desc      text,
	p_category  text,
	p_amount    bigint,
	p_paid_by   bigint,
	p_spent_on  date,
	p_method    text,
	p_parts     jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me     public.profiles%ROWTYPE := public.expense_writer_guard();
	e      public.expenses%ROWTYPE;
	v_desc text;
	before jsonb;
BEGIN
	SELECT * INTO e FROM public.expenses
	WHERE id = p_id AND family_id = me.family_id AND deleted_at IS NULL
	FOR UPDATE;
	IF e.id IS NULL THEN
		RAISE EXCEPTION 'Despesa não encontrada.' USING ERRCODE = 'no_data_found';
	END IF;
	v_desc := public.expense_validate(me.family_id, p_child_id, p_desc, p_category, p_amount, p_paid_by, p_method, p_parts);
	IF p_spent_on IS NULL THEN
		RAISE EXCEPTION 'Informe a data da despesa.' USING ERRCODE = 'check_violation';
	END IF;

	before := public.expense_snapshot(e.id);

	UPDATE public.expenses SET
		child_id = p_child_id, description = v_desc, category = p_category,
		amount_cents = p_amount, paid_by = p_paid_by, spent_on = p_spent_on,
		split_method = p_method, updated_by = me.id, updated_at = now()
	WHERE id = e.id;

	DELETE FROM public.expense_shares WHERE expense_id = e.id;
	INSERT INTO public.expense_shares (expense_id, profile_id, weight, share_cents)
	SELECT e.id, s.profile_id, s.weight, s.share_cents
	FROM public.expense_split(p_amount, p_method, p_parts) s;

	INSERT INTO public.expense_history (expense_id, family_id, action, actor_id, old_data, new_data)
	VALUES (e.id, me.family_id, 'updated', me.id, before, public.expense_snapshot(e.id));

	PERFORM public.expense_notify(e.id, 'updated', me.id);
END;
$$;

ALTER FUNCTION public.update_expense(bigint, bigint, text, text, bigint, bigint, date, text, jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.update_expense(bigint, bigint, text, text, bigint, bigint, date, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_expense(bigint, bigint, text, text, bigint, bigint, date, text, jsonb) TO authenticated, service_role;

-- A delete is SOFT: the expense stays in the record (who, when, and the trail).
CREATE OR REPLACE FUNCTION public.delete_expense(p_id bigint)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me public.profiles%ROWTYPE := public.expense_writer_guard();
	e  public.expenses%ROWTYPE;
BEGIN
	SELECT * INTO e FROM public.expenses
	WHERE id = p_id AND family_id = me.family_id AND deleted_at IS NULL
	FOR UPDATE;
	IF e.id IS NULL THEN
		RAISE EXCEPTION 'Despesa não encontrada.' USING ERRCODE = 'no_data_found';
	END IF;
	INSERT INTO public.expense_history (expense_id, family_id, action, actor_id, old_data)
	VALUES (e.id, me.family_id, 'deleted', me.id, public.expense_snapshot(e.id));
	UPDATE public.expenses SET deleted_by = me.id, deleted_at = now() WHERE id = e.id;
	PERFORM public.expense_notify(e.id, 'deleted', me.id);
END;
$$;

ALTER FUNCTION public.delete_expense(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.delete_expense(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_expense(bigint) TO authenticated, service_role;


-- ── 7. Settling up — the one difference: the receiver confirms ───────────────

CREATE OR REPLACE FUNCTION public.settlement_notify(p_id bigint)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	st   public.expense_settlements%ROWTYPE;
	who  text;
	day_ text;
BEGIN
	SELECT * INTO st FROM public.expense_settlements WHERE id = p_id;
	day_ := to_char((now() AT TIME ZONE 'America/Sao_Paulo')::date, 'YYYY-MM-DD');
	IF st.status = 'pending' THEN
		SELECT coalesce(nullif(btrim(full_name), ''), 'Um membro da família') INTO who
		FROM public.profiles WHERE id = st.from_profile;
		INSERT INTO public.notifications (recipient_profile_id, type, title, message, params)
		SELECT p.id, 'settlement_requested', 'Confirme um acerto',
		       who || ' registrou em ' || to_char(day_::date, 'DD/MM/YYYY') || ' que pagou ' ||
		       public.brl_text(st.amount_cents) || ' a você. Confirme em Despesas se recebeu.',
		       jsonb_build_object('date', day_, 'amount', st.amount_cents::text, 'name', who)
		FROM public.profiles p
		WHERE p.id = st.to_profile AND p.user_id IS NOT NULL AND p.left_at IS NULL;
	ELSIF st.status IN ('confirmed', 'rejected') THEN
		SELECT coalesce(nullif(btrim(full_name), ''), 'Um membro da família') INTO who
		FROM public.profiles WHERE id = st.to_profile;
		INSERT INTO public.notifications (recipient_profile_id, type, title, message, params)
		SELECT p.id, 'settlement_answered',
		       CASE WHEN st.status = 'confirmed' THEN 'Acerto confirmado' ELSE 'Acerto não confirmado' END,
		       who || CASE WHEN st.status = 'confirmed' THEN ' confirmou que recebeu '
		                   ELSE ' não confirmou que recebeu ' END ||
		       public.brl_text(st.amount_cents) || ' (' || to_char(day_::date, 'DD/MM/YYYY') || ').',
		       jsonb_build_object('kind', st.status, 'date', day_,
		                          'amount', st.amount_cents::text, 'name', who)
		FROM public.profiles p
		WHERE p.id = st.from_profile AND p.user_id IS NOT NULL AND p.left_at IS NULL;
	END IF;
END;
$$;

ALTER FUNCTION public.settlement_notify(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.settlement_notify(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settlement_notify(bigint) TO service_role;

-- "I paid X to Y": recorded by the one who paid; nothing moves until Y says so.
CREATE OR REPLACE FUNCTION public.request_settlement(p_child_id bigint, p_to bigint, p_amount bigint)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me      public.profiles%ROWTYPE := public.expense_writer_guard();
	max_amt bigint := public.setting_int('expenses.max_amount_cents', 10000000);
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

-- Only the one who RECEIVED answers.
CREATE OR REPLACE FUNCTION public.answer_settlement(p_id bigint, p_received boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me public.profiles%ROWTYPE := public.expense_writer_guard();
	st public.expense_settlements%ROWTYPE;
BEGIN
	SELECT * INTO st FROM public.expense_settlements
	WHERE id = p_id AND family_id = me.family_id
	FOR UPDATE;
	IF st.id IS NULL OR st.to_profile <> me.id THEN
		RAISE EXCEPTION 'Só quem recebeu confirma o acerto.' USING ERRCODE = 'insufficient_privilege';
	END IF;
	IF st.status <> 'pending' THEN
		RAISE EXCEPTION 'Este acerto já foi respondido.' USING ERRCODE = 'check_violation';
	END IF;
	UPDATE public.expense_settlements
	SET status = CASE WHEN p_received THEN 'confirmed' ELSE 'rejected' END, answered_at = now()
	WHERE id = st.id;
	PERFORM public.settlement_notify(st.id);
END;
$$;

ALTER FUNCTION public.answer_settlement(bigint, boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.answer_settlement(bigint, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.answer_settlement(bigint, boolean) TO authenticated, service_role;

-- The one who recorded it takes it back while it waits.
CREATE OR REPLACE FUNCTION public.cancel_settlement(p_id bigint)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me public.profiles%ROWTYPE := public.expense_writer_guard();
	st public.expense_settlements%ROWTYPE;
BEGIN
	SELECT * INTO st FROM public.expense_settlements
	WHERE id = p_id AND family_id = me.family_id
	FOR UPDATE;
	IF st.id IS NULL OR st.from_profile <> me.id THEN
		RAISE EXCEPTION 'Só quem registrou o acerto pode cancelá-lo.' USING ERRCODE = 'insufficient_privilege';
	END IF;
	IF st.status <> 'pending' THEN
		RAISE EXCEPTION 'Este acerto já foi respondido.' USING ERRCODE = 'check_violation';
	END IF;
	UPDATE public.expense_settlements SET status = 'cancelled', answered_at = now() WHERE id = st.id;
END;
$$;

ALTER FUNCTION public.cancel_settlement(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.cancel_settlement(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_settlement(bigint) TO authenticated, service_role;


-- ── 8. The family's deletion takes the expenses with it ──────────────────────
-- Body from 20260719160000 plus the expense tables BEFORE the profiles they
-- reference (their FKs have no ON DELETE on purpose: a removed placeholder
-- that paid or owes becomes a tombstone, never a silent cascade).

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
	DELETE FROM public.expenses            WHERE family_id = p_family_id;
	DELETE FROM public.profiles           WHERE family_id = p_family_id;
	DELETE FROM public.families           WHERE id = p_family_id;
END;
$$;


-- ── 9. Push: the three expense types ─────────────────────────────────────────
-- Copied VERBATIM from 20260924130000 (F-55 PR 4) with 'expense_changed',
-- 'settlement_requested' and 'settlement_answered' in the filter — and so in
-- T-83's `push.disabled_types` vocabulary, born ON.

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
		'expense_changed', 'settlement_requested', 'settlement_answered'
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


-- ── 10. F-69: the expenses in the operator report — counts only ─────────────
-- Body from 20260924150000 (F-64) plus `expenses`.

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
