-- F-105 (T-103 audit, 04/10/2026) — agenda reminders reach the evening before.
--
-- A pediatrician at 08:00 on a day the other parent has the child needs a
-- reminder the night before (fasting, the vaccination card, leaving work
-- early); the catalogue stopped at 60 minutes. It is a CLOSED catalogue
-- (T-84): the CHECK, the server's validation, the minute job and the client
-- (`AgendaNotify.remindOffsets`, core) change together.
--
--   · 120, 180 — two and three hours before the start;
--   · 1440     — one day before the start, at the same time;
--   · -1       — "na véspera às 19h": 19:00 in Brasília on the day before,
--                whatever the start (a sentinel, since it is not an offset).
-- A reminder still needs a start time and an audience (unchanged).
--
-- `agenda_notify_validate` and `agenda_reminders_due` are copied VERBATIM from
-- 20260924130000 (F-55, their only definition) with the catalogue and the due
-- moment changed. The 1-day window the job scans (`today - 1 .. today + 1`)
-- already covers a reminder due the day before.

DO $$
DECLARE
	r record;
BEGIN
	FOR r IN
		SELECT c.conrelid::regclass AS tbl, c.conname
		  FROM pg_constraint c
		 WHERE c.conrelid IN ('public.child_events'::regclass, 'public.child_routines'::regclass)
		   AND c.contype = 'c'
		   AND pg_get_constraintdef(c.oid) LIKE '%remind_minutes%'
		   AND pg_get_constraintdef(c.oid) LIKE '%60%'
	LOOP
		EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', r.tbl, r.conname);
	END LOOP;
END;
$$;

ALTER TABLE public.child_events
	ADD CONSTRAINT child_events_remind_minutes_check
		CHECK (remind_minutes IN (0, 15, 30, 60, 120, 180, 1440, -1));

ALTER TABLE public.child_routines
	ADD CONSTRAINT child_routines_remind_minutes_check
		CHECK (remind_minutes IN (0, 15, 30, 60, 120, 180, 1440, -1));

CREATE OR REPLACE FUNCTION public.agenda_notify_validate(
	p_to     text,
	p_push   boolean,
	p_in_app boolean,
	p_remind smallint,
	p_start  time)
RETURNS void
LANGUAGE plpgsql IMMUTABLE
SET search_path TO 'public'
AS $$
BEGIN
	IF p_to IS NULL OR p_to NOT IN ('none', 'self', 'responsible', 'family') THEN
		RAISE EXCEPTION 'Destinatário da notificação desconhecido.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF p_to <> 'none' AND NOT (coalesce(p_push, false) OR coalesce(p_in_app, false)) THEN
		RAISE EXCEPTION 'Escolha pelo menos um canal da notificação: no celular ou no app.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF p_remind IS NOT NULL THEN
		IF p_remind NOT IN (0, 15, 30, 60, 120, 180, 1440, -1) THEN
			RAISE EXCEPTION 'Escolha um lembrete da lista: na hora, 15, 30 ou 60 minutos, 2 ou 3 horas, 1 dia antes ou na véspera às 19h.'
				USING ERRCODE = 'check_violation';
		END IF;
		IF p_start IS NULL THEN
			RAISE EXCEPTION 'O lembrete precisa do horário de início.'
				USING ERRCODE = 'check_violation';
		END IF;
		IF p_to = 'none' THEN
			RAISE EXCEPTION 'Escolha quem recebe o lembrete.'
				USING ERRCODE = 'check_violation';
		END IF;
	END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.agenda_reminders_due(p_family_id bigint DEFAULT NULL)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	today date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	ev    public.child_events%ROWTYPE;
	sent  int := 0;
BEGIN
	IF NOT public.setting_bool('feature.child_agenda', false) THEN
		RETURN 0;
	END IF;

	FOR ev IN
		UPDATE public.child_events ce SET reminded_at = now()
		WHERE ce.id IN (
			SELECT x.id FROM public.child_events x
			WHERE x.remind_minutes IS NOT NULL
			  AND x.reminded_at IS NULL
			  AND x.deleted_at IS NULL
			  AND x.start_time IS NOT NULL
			  AND x.notify_to <> 'none'
			  AND x.event_date BETWEEN today - 1 AND today + 1
			  AND (p_family_id IS NULL OR x.family_id = p_family_id)
			  -- F-105: -1 is "na véspera às 19h", a fixed hour of the day before;
			  -- every other value is minutes before the start.
			  AND (CASE WHEN x.remind_minutes = -1
			            THEN ((x.event_date - 1) + time '19:00') AT TIME ZONE 'America/Sao_Paulo'
			            ELSE ((x.event_date + x.start_time) AT TIME ZONE 'America/Sao_Paulo')
			                 - make_interval(mins => x.remind_minutes)
			       END) <= now()
			  AND ((x.event_date + x.start_time) AT TIME ZONE 'America/Sao_Paulo')
			        + interval '10 minutes' > now()
			  -- Downgrade: the reminders of Premium items stop; the note keeps its.
			  AND (x.kind = 'note'
			       OR NOT public.setting_bool('agenda.premium_only', true)
			       OR public.is_premium(x.family_id))
			FOR UPDATE SKIP LOCKED)
		RETURNING ce.*
	LOOP
		sent := sent + public.agenda_notify(ev, 'agenda_reminder', ev.created_by);
	END LOOP;
	RETURN sent;
END;
$$;
