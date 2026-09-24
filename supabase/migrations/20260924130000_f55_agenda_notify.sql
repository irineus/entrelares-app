-- =============================================================================
-- F-55 (PR 4 of 4) — the agenda speaks: a notice on creation, a reminder before
--
-- Decisions locked by the owner (24/09/2026, F-55 Notes, item 8): the CREATOR
-- chooses who is told (only me / the day's carer / the whole family, a viewer
-- included) and the channel (push and/or in-app, NEVER e-mail); a notice when
-- the item is created and, when it has a start time, a reminder 0/15/30/60
-- minutes before (FIXED offsets — T-84: not a key). New push types are born in
-- T-83's per-type switch, ON. Downgrade: the reminders of Premium items stop.
--
--   * `child_events` / `child_routines` gain the choice: `notify_to`
--     (none/self/responsible/family), `notify_push`, `notify_in_app`,
--     `remind_minutes`; the event gains `reminded_at` (sent once).
--   * `agenda_notify` is the ONE writer of the two types. Recipients are
--     resolved when it runs: `self` = who created the item, `responsible` =
--     the day's effective carer (actual, else planned — the F-52 rule), `family`
--     = every active member with an account. A NOTICE never goes to the person
--     who just created the item (the "push only what you did not just do"
--     rule); a REMINDER goes to everyone chosen, the creator included.
--   * Channel: in-app off = the row is born READ and carries `in_app: false`
--     (the app hides it; the push still needs the row to render from); push
--     off = `push: false`, and the dispatcher skips it. E-mail: never.
--   * `agenda_reminders_due` runs every minute (pg_cron), SQL only — nothing
--     here sends e-mail, so no Edge Function. Flag off = nothing; a Premium
--     item of a family that lost Premium = no reminder (the note keeps its).
--   * Two push types, `agenda_notice` and `agenda_reminder`, in the dispatcher
--     filter (and so in `push.disabled_types`' vocabulary, T-83).
--   * F-69: `agenda.with_reminder` and `agenda.reminders_sent` — counts only.
--
-- The RPCs of PR 2/3 gain four DEFAULTed parameters. They are DROPPED and
-- recreated rather than overloaded: two overloads with defaults make PostgREST
-- refuse the call as ambiguous.
-- =============================================================================


-- ── 1. The choice, on the item and on the routine ───────────────────────────

ALTER TABLE public.child_events
	ADD COLUMN IF NOT EXISTS notify_to      text NOT NULL DEFAULT 'none'
		CHECK (notify_to IN ('none', 'self', 'responsible', 'family')),
	ADD COLUMN IF NOT EXISTS notify_push    boolean NOT NULL DEFAULT true,
	ADD COLUMN IF NOT EXISTS notify_in_app  boolean NOT NULL DEFAULT true,
	ADD COLUMN IF NOT EXISTS remind_minutes smallint
		CHECK (remind_minutes IN (0, 15, 30, 60)),
	ADD COLUMN IF NOT EXISTS reminded_at    timestamptz;

ALTER TABLE public.child_events
	ADD CONSTRAINT child_events_remind_needs_time
		CHECK (remind_minutes IS NULL OR (start_time IS NOT NULL AND notify_to <> 'none')),
	ADD CONSTRAINT child_events_notify_has_channel
		CHECK (notify_to = 'none' OR notify_push OR notify_in_app);

ALTER TABLE public.child_routines
	ADD COLUMN IF NOT EXISTS notify_to      text NOT NULL DEFAULT 'none'
		CHECK (notify_to IN ('none', 'self', 'responsible', 'family')),
	ADD COLUMN IF NOT EXISTS notify_push    boolean NOT NULL DEFAULT true,
	ADD COLUMN IF NOT EXISTS notify_in_app  boolean NOT NULL DEFAULT true,
	ADD COLUMN IF NOT EXISTS remind_minutes smallint
		CHECK (remind_minutes IN (0, 15, 30, 60));

-- What the minute job scans: pending reminders only.
CREATE INDEX IF NOT EXISTS child_events_reminder_due_idx
	ON public.child_events (event_date)
	WHERE remind_minutes IS NOT NULL AND reminded_at IS NULL AND deleted_at IS NULL;


-- ── 2. The rule of the choice ────────────────────────────────────────────────

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
		IF p_remind NOT IN (0, 15, 30, 60) THEN
			RAISE EXCEPTION 'O lembrete é na hora ou 15, 30 ou 60 minutos antes.'
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

REVOKE ALL ON FUNCTION public.agenda_notify_validate(text, boolean, boolean, smallint, time) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.agenda_notify_validate(text, boolean, boolean, smallint, time) TO service_role;


-- ── 3. The one writer of agenda_notice / agenda_reminder ─────────────────────
-- PT-BR sentences byte-identical to the Dart catalog (U-13): the reader's
-- device rebuilds them from `params` in its own language, and `_shared/push.ts`
-- does the same for the push.

CREATE OR REPLACE FUNCTION public.agenda_kind_label_pt(p_kind text)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $$
	SELECT CASE p_kind
		WHEN 'school'   THEN 'Escola'
		WHEN 'health'   THEN 'Saúde'
		WHEN 'medicine' THEN 'Remédio'
		WHEN 'activity' THEN 'Atividade'
		WHEN 'free'     THEN 'Livre'
		WHEN 'note'     THEN 'Nota'
		ELSE 'Outro' END;
$$;

REVOKE ALL ON FUNCTION public.agenda_kind_label_pt(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.agenda_kind_label_pt(text) TO service_role;

CREATE OR REPLACE FUNCTION public.agenda_notify(
	p_ev      public.child_events,
	p_type    text,
	p_actor   bigint,
	p_routine boolean DEFAULT false)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	v_date   text := to_char(p_ev.event_date, 'DD/MM/YYYY');
	v_time   text := to_char(p_ev.start_time, 'HH24:MI');
	v_child  text;
	v_actor  text;
	v_what   text;
	v_suffix text := coalesce(' ' || p_ev.body, '');
	v_title  text;
	v_msg    text;
	v_params jsonb;
	day_parent bigint;
	made     int := 0;
BEGIN
	IF p_ev.notify_to = 'none' OR p_type NOT IN ('agenda_notice', 'agenda_reminder') THEN
		RETURN 0;
	END IF;

	SELECT first_name INTO v_child FROM public.children WHERE id = p_ev.child_id;
	SELECT full_name INTO v_actor FROM public.profiles WHERE id = p_actor;
	-- The catalog's own fallback (U-13), so a nameless author never NULLs the row.
	v_actor := coalesce(nullif(btrim(v_actor), ''), 'Um membro da família');
	v_what := concat_ws(' · ', v_time, public.agenda_kind_label_pt(p_ev.kind), v_child);

	IF p_type = 'agenda_notice' THEN
		v_title := 'Novo na agenda';
		v_msg := CASE WHEN p_routine
		              THEN v_actor || ' criou uma rotina na agenda a partir de ' || v_date || ': ' || v_what || '.' || v_suffix
		              ELSE v_actor || ' adicionou à agenda de ' || v_date || ': ' || v_what || '.' || v_suffix END;
	ELSE
		v_title := 'Lembrete da agenda';
		v_msg := v_what || ' (' || v_date || ').' || v_suffix;
	END IF;

	v_params := jsonb_strip_nulls(jsonb_build_object(
		'date',    to_char(p_ev.event_date, 'YYYY-MM-DD'),
		'kind',    p_ev.kind,
		'time',    v_time,
		'child',   v_child,
		'name',    CASE WHEN p_type = 'agenda_notice' THEN v_actor END,
		'msg',     p_ev.body,
		'routine', CASE WHEN p_routine THEN '1' END,
		'push',    CASE WHEN NOT p_ev.notify_push THEN 'false' END,
		'in_app',  CASE WHEN NOT p_ev.notify_in_app THEN 'false' END));

	IF p_ev.notify_to = 'responsible' THEN
		SELECT COALESCE(cs.actual_parent_id, cs.scheduled_parent_id) INTO day_parent
		FROM public.care_schedules cs
		WHERE cs.family_id = p_ev.family_id AND cs.schedule_date = p_ev.event_date;
	END IF;

	INSERT INTO public.notifications (recipient_profile_id, type, title, message, params, is_read)
	SELECT p.id, p_type, v_title, v_msg, v_params, NOT p_ev.notify_in_app
	FROM public.profiles p
	WHERE p.family_id = p_ev.family_id
	  AND p.left_at IS NULL
	  AND p.user_id IS NOT NULL
	  AND CASE p_ev.notify_to
	          WHEN 'self'        THEN p.id = p_ev.created_by
	          WHEN 'responsible' THEN p.id = day_parent
	          ELSE true END
	  -- A notice never tells its author what they just did.
	  AND (p_type <> 'agenda_notice' OR p.id IS DISTINCT FROM p_actor);
	GET DIAGNOSTICS made = ROW_COUNT;
	RETURN made;
END;
$$;

ALTER FUNCTION public.agenda_notify(public.child_events, text, bigint, boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.agenda_notify(public.child_events, text, bigint, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.agenda_notify(public.child_events, text, bigint, boolean) TO service_role;


-- ── 4. add / update, with the choice ─────────────────────────────────────────

DROP FUNCTION IF EXISTS public.add_child_event(date, text, bigint, time, time, text);

CREATE OR REPLACE FUNCTION public.add_child_event(
	p_date          date,
	p_kind          text,
	p_child_id      bigint   DEFAULT NULL,
	p_start         time     DEFAULT NULL,
	p_end           time     DEFAULT NULL,
	p_body          text     DEFAULT NULL,
	p_notify_to     text     DEFAULT 'none',
	p_notify_push   boolean  DEFAULT true,
	p_notify_in_app boolean  DEFAULT true,
	p_remind        smallint DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me     public.profiles%ROWTYPE := public.agenda_writer_guard();
	v_body text;
	ev     public.child_events%ROWTYPE;
BEGIN
	v_body := public.agenda_validate(me.family_id, p_date, p_kind, p_child_id, p_start, p_end, p_body);
	PERFORM public.agenda_notify_validate(p_notify_to, p_notify_push, p_notify_in_app, p_remind, p_start);

	INSERT INTO public.child_events
		(family_id, child_id, event_date, start_time, end_time, kind, body, created_by,
		 notify_to, notify_push, notify_in_app, remind_minutes)
	VALUES (me.family_id, p_child_id, p_date, p_start, p_end, p_kind, v_body, me.id,
	        p_notify_to, p_notify_push, p_notify_in_app, p_remind)
	RETURNING * INTO ev;

	PERFORM public.agenda_notify(ev, 'agenda_notice', me.id);
	RETURN ev.id;
END;
$$;

ALTER FUNCTION public.add_child_event(date, text, bigint, time, time, text, text, boolean, boolean, smallint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.add_child_event(date, text, bigint, time, time, text, text, boolean, boolean, smallint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_child_event(date, text, bigint, time, time, text, text, boolean, boolean, smallint) TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.update_child_event(bigint, date, text, bigint, time, time, text);

-- An edit is not news: no notice. A reminder whose moment moved is armed again.
CREATE OR REPLACE FUNCTION public.update_child_event(
	p_event_id      bigint,
	p_date          date,
	p_kind          text,
	p_child_id      bigint   DEFAULT NULL,
	p_start         time     DEFAULT NULL,
	p_end           time     DEFAULT NULL,
	p_body          text     DEFAULT NULL,
	p_notify_to     text     DEFAULT 'none',
	p_notify_push   boolean  DEFAULT true,
	p_notify_in_app boolean  DEFAULT true,
	p_remind        smallint DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me     public.profiles%ROWTYPE := public.agenda_writer_guard();
	ev     public.child_events%ROWTYPE;
	v_body text;
BEGIN
	ev := public.agenda_editable_row(me, p_event_id);
	v_body := public.agenda_validate(me.family_id, p_date, p_kind, p_child_id, p_start, p_end, p_body, ev.id);
	PERFORM public.agenda_notify_validate(p_notify_to, p_notify_push, p_notify_in_app, p_remind, p_start);

	UPDATE public.child_events SET
		event_date     = p_date,
		kind           = p_kind,
		child_id       = p_child_id,
		start_time     = p_start,
		end_time       = p_end,
		body           = v_body,
		notify_to      = p_notify_to,
		notify_push    = p_notify_push,
		notify_in_app  = p_notify_in_app,
		remind_minutes = p_remind,
		reminded_at    = CASE
		                   WHEN (p_date, p_start, p_remind)
		                        IS DISTINCT FROM (ev.event_date, ev.start_time, ev.remind_minutes)
		                   THEN NULL
		                   ELSE ev.reminded_at END,
		updated_by     = me.id,
		updated_at     = now()
	WHERE id = ev.id;
END;
$$;

ALTER FUNCTION public.update_child_event(bigint, date, text, bigint, time, time, text, text, boolean, boolean, smallint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.update_child_event(bigint, date, text, bigint, time, time, text, text, boolean, boolean, smallint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_child_event(bigint, date, text, bigint, time, time, text, text, boolean, boolean, smallint) TO authenticated, service_role;

-- ── 5. The routine carries the choice to every event it writes ───────────────
-- ONE notice for the routine (not one per generated day), and only when it is
-- created; each generated event keeps the reminder.

DROP FUNCTION IF EXISTS public.save_child_routine(uuid, date, text, smallint[], bigint, time, time, text);

CREATE OR REPLACE FUNCTION public.save_child_routine(
	p_routine_id    uuid,
	p_from          date,
	p_kind          text,
	p_weekdays      smallint[],
	p_child_id      bigint   DEFAULT NULL,
	p_start         time     DEFAULT NULL,
	p_end           time     DEFAULT NULL,
	p_body          text     DEFAULT NULL,
	p_notify_to     text     DEFAULT 'none',
	p_notify_push   boolean  DEFAULT true,
	p_notify_in_app boolean  DEFAULT true,
	p_remind        smallint DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me       public.profiles%ROWTYPE := public.agenda_writer_guard();
	today    date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	r        public.child_routines%ROWTYPE;
	r_id     uuid := COALESCE(p_routine_id, gen_random_uuid());
	days     smallint[];
	until_d  date;
	d        date;
	v_body   text := nullif(btrim(coalesce(p_body, '')), '');
	made     int := 0;
	removed  int := 0;
	first_ev public.child_events%ROWTYPE;
BEGIN
	IF p_from IS NULL OR p_from < today THEN
		RAISE EXCEPTION 'A agenda aceita eventos de hoje em diante. Um dia que já passou é só leitura.'
			USING ERRCODE = 'check_violation';
	END IF;

	SELECT array_agg(DISTINCT w ORDER BY w) INTO days FROM unnest(p_weekdays) w;
	IF days IS NULL OR NOT days <@ ARRAY[1, 2, 3, 4, 5, 6, 7]::smallint[] THEN
		RAISE EXCEPTION 'Escolha pelo menos um dia da semana para a rotina.'
			USING ERRCODE = 'check_violation';
	END IF;

	PERFORM public.agenda_notify_validate(p_notify_to, p_notify_push, p_notify_in_app, p_remind, p_start);

	IF p_routine_id IS NOT NULL THEN
		SELECT * INTO r FROM public.child_routines
		WHERE id = p_routine_id AND family_id = me.family_id AND stopped_at IS NULL
		FOR UPDATE;
		IF r.id IS NULL THEN
			RAISE EXCEPTION 'Rotina não encontrada na agenda da sua família.'
				USING ERRCODE = 'no_data_found';
		END IF;
		IF r.kind <> 'note'
		   AND public.setting_bool('agenda.premium_only', true)
		   AND NOT public.is_premium(me.family_id) THEN
			RAISE EXCEPTION 'Esta rotina é da agenda Premium e fica só para leitura no plano gratuito.'
				USING ERRCODE = 'check_violation';
		END IF;

		-- Re-apply: the routine's events from p_from on give way to the new
		-- ones (soft delete — they stay in the record). They go FIRST, so the
		-- day caps below do not count the events being replaced.
		UPDATE public.child_events SET deleted_by = me.id, deleted_at = now()
		WHERE batch_id = r.id AND deleted_at IS NULL AND event_date >= p_from;
		GET DIAGNOSTICS removed = ROW_COUNT;
	END IF;

	until_d := public.agenda_plan_end(me.family_id, p_from);
	IF until_d IS NULL THEN
		RAISE EXCEPTION 'O calendário ainda não tem dias planejados a partir desse dia. Preencha o calendário antes de aplicar a rotina.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- Every generated day passes the rule of a single event. A refusal that
	-- belongs to ONE day (its cap, its free note) names the day; any other
	-- (kind, text, times, child, Premium) is the routine's, and reads as is.
	d := p_from;
	WHILE d <= until_d LOOP
		IF extract(isodow FROM d)::smallint = ANY (days) THEN
			BEGIN
				v_body := public.agenda_validate(me.family_id, d, p_kind, p_child_id, p_start, p_end, v_body);
			EXCEPTION WHEN check_violation THEN
				IF SQLERRM LIKE 'Este dia já tem%' OR SQLERRM LIKE 'No plano gratuito, a agenda aceita%' THEN
					RAISE EXCEPTION 'Em %: %', to_char(d, 'DD/MM/YYYY'), SQLERRM
						USING ERRCODE = 'check_violation';
				END IF;
				RAISE;
			END;
			INSERT INTO public.child_events
				(family_id, child_id, event_date, start_time, end_time, kind, body,
				 batch_id, created_by, notify_to, notify_push, notify_in_app, remind_minutes)
			VALUES (me.family_id, p_child_id, d, p_start, p_end, p_kind, v_body, r_id, me.id,
			        p_notify_to, p_notify_push, p_notify_in_app, p_remind)
			RETURNING * INTO first_ev;
			made := made + 1;
		END IF;
		d := d + 1;
	END LOOP;

	IF made = 0 THEN
		RAISE EXCEPTION 'Nenhum dia planejado cai nesses dias da semana. Escolha outros dias ou preencha o calendário antes.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF r.id IS NULL THEN
		INSERT INTO public.child_routines
			(id, family_id, child_id, kind, start_time, end_time, body, weekdays,
			 starts_on, ends_on, created_by, notify_to, notify_push, notify_in_app, remind_minutes)
		VALUES (r_id, me.family_id, p_child_id, p_kind, p_start, p_end, v_body, days,
		        p_from, until_d, me.id, p_notify_to, p_notify_push, p_notify_in_app, p_remind);

		-- The notice speaks of the routine from its first day.
		SELECT * INTO first_ev FROM public.child_events
		WHERE batch_id = r_id AND deleted_at IS NULL
		ORDER BY event_date LIMIT 1;
		PERFORM public.agenda_notify(first_ev, 'agenda_notice', me.id, true);
	ELSE
		UPDATE public.child_routines SET
			child_id       = p_child_id,
			kind           = p_kind,
			start_time     = p_start,
			end_time       = p_end,
			body           = v_body,
			weekdays       = days,
			ends_on        = until_d,
			notify_to      = p_notify_to,
			notify_push    = p_notify_push,
			notify_in_app  = p_notify_in_app,
			remind_minutes = p_remind,
			updated_by     = me.id,
			updated_at     = now()
		WHERE id = r.id;
	END IF;

	RETURN jsonb_build_object(
		'routine_id', r_id,
		'created',    made,
		'removed',    removed,
		'until',      until_d);
END;
$$;

ALTER FUNCTION public.save_child_routine(uuid, date, text, smallint[], bigint, time, time, text, text, boolean, boolean, smallint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.save_child_routine(uuid, date, text, smallint[], bigint, time, time, text, text, boolean, boolean, smallint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_child_routine(uuid, date, text, smallint[], bigint, time, time, text, text, boolean, boolean, smallint) TO authenticated, service_role;


-- ── 6. The reminder: every minute ────────────────────────────────────────────
-- Due when the moment (the day's São Paulo clock at the start time, minus the
-- offset) has come, and not after the event itself is ten minutes old — a
-- reminder for what already happened is noise. Stamped in the same statement
-- that selects it (SKIP LOCKED), so two runs never send the same reminder
-- twice. `p_family_id` scopes a gate run to its own throwaway family.

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
			  AND ((x.event_date + x.start_time) AT TIME ZONE 'America/Sao_Paulo')
			        - make_interval(mins => x.remind_minutes) <= now()
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

ALTER FUNCTION public.agenda_reminders_due(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.agenda_reminders_due(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.agenda_reminders_due(bigint) TO service_role;

SELECT cron.schedule(
	'agenda-reminders-minutely',
	'* * * * *',
	$cron$ SELECT public.agenda_reminders_due(); $cron$
);

-- ── 7. Push: the two agenda types ────────────────────────────────────────────
-- Copied VERBATIM from 20260924080000 (T-83) with 'agenda_notice' and
-- 'agenda_reminder' in the filter — and so in the vocabulary T-83's
-- `push.disabled_types` validation reads back from it, born ON (nobody lists
-- them) — and the creator's "no push" honoured before pg_net.

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
		'agenda_notice', 'agenda_reminder'
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


-- ── 8. F-69: the agenda's reminders in the operator report — counts only ────
-- Recreated from 20260924120000 (F-55 PR 3) with two counts in `agenda`.

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

COMMENT ON FUNCTION public.admin_family_usage_report(bigint) IS
	'F-69: one family''s usage report for the operator console — counts, dates, ids and closed enums only, never free text. Operator-gated; every call (an unknown family included) is written to operator_audit_logs. Read-only, no sudo.';

ALTER FUNCTION public.admin_family_usage_report(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_family_usage_report(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_family_usage_report(bigint) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_family_usage_report(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_family_usage_report(bigint) TO service_role;
