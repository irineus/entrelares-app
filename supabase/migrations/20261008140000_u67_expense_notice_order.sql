-- U-67 (T-103 audit, 04/10/2026): the expense notice read "…em 04/10/2026:
-- Outros. Mensalidade escolar" — the category before what the expense IS.
-- The description comes first now, the category after it in parentheses:
-- "…em 04/10/2026: Mensalidade escolar (Outros)." The same order in the Dart
-- catalog (K.notifRender.expense*) and in _shared/push.ts. expense_notify is
-- copied verbatim from 20260924160000_f34_expenses.sql (its only definition),
-- with the stored sentence changed and nothing else. params are unchanged.

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
	       to_char(e.spent_on, 'DD/MM/YYYY') || ': ' || e.description ||
	       ' (' || public.expense_category_pt(e.category) || ').',
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
