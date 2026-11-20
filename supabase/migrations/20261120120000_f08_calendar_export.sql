-- F-08 — export to another calendar (.ics): the server half.
--
-- The export itself is CLIENT-only (the app assembles a file from rows the
-- family already reads, like the F-33 PDF), so the server carries just two
-- things:
--
--   1. `calendar_export.premium_only` (T-84/T-80 shape, default true): the
--      app offers the export to a Premium family only while it is on, and the
--      console can open it to everyone without a release. Client-side gate on
--      purpose — the same posture as the PDF: the data is already readable, so
--      a server refusal would guard nothing. A server-enforced gate comes with
--      F-109's subscription feed.
--   2. A new F-79/F-102 gate token, `calendar-export`, so a non-admin who
--      meets the gate can ask the admins and the notification says what was
--      wanted. `request_premium_from_admin` below is the F-102 body copied
--      VERBATIM with the token and its PT-BR label added — byte-identical to
--      the catalog's `notifRender.premiumGate.calendarExport` and to push.ts.
-- =============================================================================


-- ── 1. The key ───────────────────────────────────────────────────────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, min_value, max_value, help)
VALUES
	('calendar_export.premium_only', 'true', 'bool', 'reports',
	 'Só o Premium exporta o calendário para outro app de calendário (.ics).',
	 true, 'flag', 'sensitive', NULL, NULL,
	 jsonb_build_object(
		'controls', 'Se a folha "Exportar para outro calendário" gera o arquivo só para família Premium.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Ligado (padrão): a exportação é benefício Premium; a família gratuita vê a folha com o convite para o plano.',
		'if_decreased', 'Desligado: toda família exporta.',
		'takes_effect', 'App na próxima abertura.',
		'caveats', 'Trava só no app, como o PDF: os dados exportados a família já lê. Não há escrita no servidor para recusar.'))
ON CONFLICT (key) DO NOTHING;


-- ── 2. The gate token ────────────────────────────────────────────────────────

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
	v_gate := CASE WHEN p_gate IN ('chat', 'chat-export', 'agenda', 'expenses', 'pdf', 'calendar-export')
	               THEN p_gate ELSE 'premium' END;
	-- PT-BR label of what the gate guards — byte-identical to the catalog's
	-- `notifRender.premiumGate.*`.
	v_label := CASE v_gate
		WHEN 'chat'        THEN 'escrever na Conversa'
		WHEN 'chat-export' THEN 'exportar a Conversa em PDF'
		WHEN 'agenda'      THEN 'a agenda da criança'
		WHEN 'expenses'    THEN 'as despesas'
		WHEN 'pdf'         THEN 'o relatório em PDF'
		WHEN 'calendar-export' THEN 'exportar para outro calendário'
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
	'F-102 (+ F-08 calendar-export token): a non-admin member tells the family''s admins they want Premium (push + in-app, type premium_request, params kind/name/gate). Refuses an admin, a Premium family and a second ask on the same São Paulo day. Who may pay does not change.';
