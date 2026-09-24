-- =============================================================================
-- T-82 (PR 1) — the aviso cap becomes an operator parameter
--
-- F-52 capped avisos at TWO per sender per day, as a literal in
-- `send_day_notice`: one covers the event, the second covers it getting worse;
-- a third is a conversation, and the cap is what keeps avisos from becoming
-- F-35 (messaging). The owner took this one number — and only this one — from
-- the "keep fixed" list (23/09/2026): it is now `day_notice.daily_cap`, default
-- 2, range 1 to 3 (NOT 1–5 as the card first proposed), born with the T-80
-- metadata. The app reads it too (is_public), so the sheet states the number
-- the server enforces.
--
-- `send_day_notice` is recreated from its ONLY definition
-- (20260918190000_f52_day_notices.sql, re-checked 24/09/2026); only the cap
-- line and its sentence change.
-- =============================================================================

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, min_value, max_value, help)
VALUES
	('day_notice.daily_cap', '2', 'int', 'product',
	 'Avisos de imprevisto que uma pessoa pode enviar por dia (F-52).',
	 true, 'count', 'sensitive', 1, 3,
	 jsonb_build_object(
		'controls', 'Quantos avisos de imprevisto um mesmo membro envia num mesmo dia (send_day_notice); o app diz o número antes de bloquear. Cancelar um aviso não devolve a vaga.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Mais avisos por dia — e o aviso se aproxima de uma conversa. Um aviso cobre o imprevisto, o segundo cobre o imprevisto que piorou; o terceiro já é troca de mensagens, que é o F-35 e não o aviso.',
		'if_decreased', 'Com 1, quem avisou "vou atrasar" não consegue avisar de novo que piorou ("sem previsão, alguém pode ficar?") — o motivo de o padrão ser 2.',
		'takes_effect', 'Servidor no próximo aviso; app na próxima abertura do calendário.',
		'caveats', 'Faixa 1 a 3 por decisão do owner (23/09/2026): o limite é o que separa o aviso do F-35 (mensagens).'))
ON CONFLICT (key) DO NOTHING;


-- ── 4. send_day_notice ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.send_day_notice(
	p_reason      text,
	p_eta_minutes int  DEFAULT NULL,
	p_request     text DEFAULT 'info',
	p_note        text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me            public.profiles%ROWTYPE;
	today         date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	day_parent    bigint;
	prev_parent   bigint;
	next_parent   bigint;
	note          text := nullif(btrim(p_note), '');
	sent_today    int;
	daily_cap     int := public.setting_int('day_notice.daily_cap', 2);
	new_id        bigint;
	sentence      text;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();

	-- A frozen member (S-11) holds no seat and acts on nothing; a pending one
	-- (F-56) has no account to act with, so it can never reach this anyway.
	IF me.id IS NULL OR me.left_at IS NOT NULL THEN
		RAISE EXCEPTION 'Sua conta não pode enviar avisos.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	IF note IS NOT NULL AND char_length(note) > 140 THEN
		RAISE EXCEPTION 'O detalhe do aviso é limitado a 140 caracteres.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- The three ends of the day, mirrored from `noticeSenderIds`.
	SELECT COALESCE(cs.actual_parent_id, cs.scheduled_parent_id) INTO day_parent
	FROM public.care_schedules cs
	WHERE cs.family_id = me.family_id AND cs.schedule_date = today;

	SELECT COALESCE(cs.actual_parent_id, cs.scheduled_parent_id) INTO prev_parent
	FROM public.care_schedules cs
	WHERE cs.family_id = me.family_id AND cs.schedule_date = today - 1;

	-- The next day whose effective carer DIFFERS — the same forward scan the
	-- Hoje card's next-handoff line does, inside the same 90-day window
	-- (`nextHandoffWindowDays`). Unplanned days are simply not rows, so a gap
	-- is skipped rather than read as a change of carer.
	SELECT COALESCE(cs.actual_parent_id, cs.scheduled_parent_id) INTO next_parent
	FROM public.care_schedules cs
	WHERE cs.family_id = me.family_id
	  AND cs.schedule_date > today
	  AND cs.schedule_date <= today + 90
	  AND COALESCE(cs.actual_parent_id, cs.scheduled_parent_id) IS DISTINCT FROM day_parent
	ORDER BY cs.schedule_date
	LIMIT 1;

	IF me.id IS DISTINCT FROM day_parent
	   AND me.id IS DISTINCT FROM prev_parent
	   AND me.id IS DISTINCT FROM next_parent THEN
		RAISE EXCEPTION 'Um aviso é de quem está no meio da troca do dia: quem está com a criança hoje, quem entregou hoje, ou quem recebe na próxima troca.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	-- Only the carer whose day it is may put that day on offer. This is also
	-- what keeps PR 2's swap inside F-28: the answerer proposes THEMSELVES on
	-- the sender's own day (scenario A), never a third party on someone else's.
	IF p_request = 'keep' AND me.id IS DISTINCT FROM day_parent THEN
		RAISE EXCEPTION 'Só quem está com o dia de hoje pode oferecê-lo.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	-- The daily cap (F-52; T-82: `day_notice.daily_cap`, default 2): one covers
	-- the event, the second covers it getting worse. A third is a conversation,
	-- and that is F-35. A cancelled notice still counts — send-and-cancel would
	-- otherwise be an unbounded channel.
	SELECT count(*)::int INTO sent_today
	FROM public.day_notices
	WHERE sender_profile_id = me.id AND schedule_date = today;

	IF sent_today >= daily_cap THEN
		RAISE EXCEPTION 'Você já enviou % avisos hoje. O limite volta amanhã.', daily_cap
			USING ERRCODE = 'check_violation';
	END IF;

	INSERT INTO public.day_notices
		(family_id, schedule_date, sender_profile_id, reason, eta_minutes, request, note)
	VALUES (me.family_id, today, me.id, p_reason, p_eta_minutes, p_request, note)
	RETURNING id INTO new_id;

	sentence := public.day_notice_sentence(
		me.full_name, p_reason, p_eta_minutes, p_request, note);

	-- Everyone with an account except the sender. F-09's rule holds: push only
	-- what the recipient did NOT just do, so the sender never gets a receipt.
	INSERT INTO public.notifications (recipient_profile_id, type, title, message, params)
	SELECT p.id, 'day_notice', 'Aviso de imprevisto', sentence,
	       jsonb_strip_nulls(jsonb_build_object(
	           'kind',   p_request,
	           'reason', p_reason,
	           'eta',    p_eta_minutes::text,
	           'note',   note,
	           'name',   me.full_name,
	           'date',   to_char(today, 'YYYY-MM-DD')))
	FROM public.profiles p
	WHERE p.family_id = me.family_id
	  AND p.id <> me.id
	  AND p.left_at IS NULL
	  AND p.user_id IS NOT NULL;

	RETURN new_id;
END;
$$;

ALTER FUNCTION public.send_day_notice(text, int, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.send_day_notice(text, int, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_day_notice(text, int, text, text) TO authenticated;
GRANT ALL    ON FUNCTION public.send_day_notice(text, int, text, text) TO service_role;

