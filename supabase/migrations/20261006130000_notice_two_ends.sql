-- =============================================================================
-- Owner's QA of 3.1.10 (06/10/2026) — an aviso is the two ends' of TODAY
--
-- F-52 named three ends: today's carer, yesterday's (who hands over today) and
-- whoever receives the child at the NEXT handoff. On the owner's test family
-- the third one misfired: on a day wholly the father's (and the day before
-- his too), the mother — whose next day was two days away, after an approved
-- swap — could send "atraso, alguém pode buscar?", and the father answered.
-- The owner: "a função de aviso e o ícone são apenas do responsável do dia e
-- daquele que esteja entregando a criança."
--
-- Only the eligibility changes; the body is the live one from
-- 20260928230000_f07_lane_aware_server (lanes, the 'keep' rule, the daily cap,
-- the fan-out). `keep` is still only for whoever holds the day.
-- The client mirror is `noticeSenderIds` (core), which lost the same third end.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.send_day_notice(p_reason text, p_eta_minutes integer DEFAULT NULL::integer, p_request text DEFAULT 'info'::text, p_note text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
	me            public.profiles%ROWTYPE;
	today         date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	holds_today   boolean;
	eligible      boolean;
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

	-- The two ends of the day, mirrored from `noticeSenderIds` — per lane
	-- (F-07): today's carer and yesterday's (who hands the child over today).
	-- Owner, 06/10/2026: whoever receives at a LATER handoff is no longer an
	-- end — it let a parent whose next day was two days away send "atraso,
	-- alguém pode buscar?" about a day that was wholly the other parent's.
	SELECT EXISTS (
		SELECT 1 FROM public.care_schedules cs
		WHERE cs.family_id = me.family_id AND cs.schedule_date = today
		  AND COALESCE(cs.actual_parent_id, cs.scheduled_parent_id) = me.id)
	INTO holds_today;

	SELECT holds_today
	    OR EXISTS (
		SELECT 1 FROM public.care_schedules cs
		WHERE cs.family_id = me.family_id AND cs.schedule_date = today - 1
		  AND COALESCE(cs.actual_parent_id, cs.scheduled_parent_id) = me.id)
	INTO eligible;

	IF NOT eligible THEN
		RAISE EXCEPTION 'Um aviso é de quem está com a criança hoje ou de quem a entrega hoje.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	-- Only the carer whose day it is may put that day on offer. This is also
	-- what keeps PR 2's swap inside F-28: the answerer proposes THEMSELVES on
	-- the sender's own day (scenario A), never a third party on someone else's.
	IF p_request = 'keep' AND NOT holds_today THEN
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
$function$;
