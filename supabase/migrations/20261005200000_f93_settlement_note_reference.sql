-- =============================================================================
-- F-93 — a payment between caregivers holds up as evidence
--
-- Decided by the owner (05/10/2026, phase-3 chain), on top of F-34:
--
--   * the receiver's answer stays FINAL (F-34's rule) — the app now asks
--     first, naming amount and person; the server is unchanged there;
--   * an optional NOTE ("comentário" on screen — "nota" is the F-55 agenda's word) on both answers ("chegou só uma parte") and an optional
--     REFERENCE when the payment is recorded (e.g. the Pix transaction id);
--   * a refused or taken-back payment stays in the record — it already did on
--     the server; the app and the PDF now show it, out of the balance.
--
-- Both texts are capped by `expenses.description_max_chars` (the same kind of
-- free text as the expense's description) and by a 500-char CHECK, the
-- column ceiling the key's own range already names.
--
-- Old Android builds call the RPCs WITHOUT the new parameters. The new ones
-- are DEFAULT NULL, and the old signatures are DROPPED first: two overloads
-- that both accept the old named call would make PostgREST refuse it as
-- ambiguous ("Could not choose the best candidate function").
-- =============================================================================


-- ── 1. The columns ───────────────────────────────────────────────────────────

ALTER TABLE public.expense_settlements
	ADD COLUMN IF NOT EXISTS reference   text,
	ADD COLUMN IF NOT EXISTS answer_note text;

ALTER TABLE public.expense_settlements
	DROP CONSTRAINT IF EXISTS expense_settlements_reference_text,
	DROP CONSTRAINT IF EXISTS expense_settlements_answer_note_text;
ALTER TABLE public.expense_settlements
	ADD CONSTRAINT expense_settlements_reference_text CHECK (
		reference IS NULL
		OR (reference = btrim(reference) AND char_length(reference) BETWEEN 1 AND 500)),
	ADD CONSTRAINT expense_settlements_answer_note_text CHECK (
		answer_note IS NULL
		OR (answer_note = btrim(answer_note) AND char_length(answer_note) BETWEEN 1 AND 500));


-- ── 2. A free text the payment carries: trimmed, empty is NULL, capped ──────

CREATE OR REPLACE FUNCTION public.settlement_text(p_text text, p_what text)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	v       text := nullif(btrim(coalesce(p_text, '')), '');
	max_chr int  := public.setting_int('expenses.description_max_chars', 200);
BEGIN
	IF v IS NOT NULL AND char_length(v) > max_chr THEN
		RAISE EXCEPTION '% do pagamento tem no máximo % caracteres.', p_what, max_chr
			USING ERRCODE = 'check_violation';
	END IF;
	RETURN v;
END;
$$;

ALTER FUNCTION public.settlement_text(text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.settlement_text(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settlement_text(text, text) TO service_role;


-- ── 3. "I paid X to Y" — plus the optional reference ────────────────────────
-- Body from 20260925130000_f34_settle_up_validation.sql plus `p_reference`.

DROP FUNCTION IF EXISTS public.request_settlement(bigint, bigint, bigint);

CREATE OR REPLACE FUNCTION public.request_settlement(
	p_child_id  bigint,
	p_to        bigint,
	p_amount    bigint,
	p_reference text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me      public.profiles%ROWTYPE := public.expense_writer_guard();
	max_amt bigint := public.setting_int('expenses.max_amount_cents', 10000000);
	v_ref   text;
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
	v_ref := public.settlement_text(p_reference, 'A referência');

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

	INSERT INTO public.expense_settlements
		(family_id, child_id, from_profile, to_profile, amount_cents, created_by, reference)
	VALUES (me.family_id, p_child_id, me.id, p_to, p_amount, me.id, v_ref)
	RETURNING id INTO new_id;
	PERFORM public.settlement_notify(new_id);
	RETURN new_id;
END;
$$;

ALTER FUNCTION public.request_settlement(bigint, bigint, bigint, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.request_settlement(bigint, bigint, bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_settlement(bigint, bigint, bigint, text) TO authenticated, service_role;


-- ── 4. Only the one who RECEIVED answers — plus the optional note ───────────
-- Body from 20260924160000_f34_expenses.sql plus `p_note`. Still final.

DROP FUNCTION IF EXISTS public.answer_settlement(bigint, boolean);

CREATE OR REPLACE FUNCTION public.answer_settlement(
	p_id       bigint,
	p_received boolean,
	p_note     text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me     public.profiles%ROWTYPE := public.expense_writer_guard();
	st     public.expense_settlements%ROWTYPE;
	v_note text;
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
	IF p_received IS NULL THEN
		RAISE EXCEPTION 'Diga se recebeu ou não o pagamento.' USING ERRCODE = 'check_violation';
	END IF;
	v_note := public.settlement_text(p_note, 'O comentário');
	UPDATE public.expense_settlements
	SET status      = CASE WHEN p_received THEN 'confirmed' ELSE 'rejected' END,
	    answered_at = now(),
	    answer_note = v_note
	WHERE id = st.id;
	PERFORM public.settlement_notify(st.id);
END;
$$;

ALTER FUNCTION public.answer_settlement(bigint, boolean, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.answer_settlement(bigint, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.answer_settlement(bigint, boolean, text) TO authenticated, service_role;
