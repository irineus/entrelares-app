-- =============================================================================
-- F-55 (PR 2) — the day agenda: events, the observation's replacement, and the
-- one-shot conversion
--
-- Owner decisions (24/09/2026, card F-55):
--   · The agenda REPLACES the "Observação do dia". Every non-empty
--     care_schedules.notes becomes a "Nota" event (child optional — a note
--     belongs to the DAY); the notes column turns read-only while the flag is
--     on; the F-47 revert stops moving text; the PDF shows the agenda.
--   · The conversion is an IDEMPOTENT function. It runs where the flag is on —
--     dev, in this migration — and in production only in S-22's migration,
--     which turns the flag on. Never before: a production family would lose
--     its observation with the agenda still dark.
--   · Closed kinds (key translated + optional free text): school, health,
--     medicine, activity, free, note, other.
--   · Free families: only "note", `agenda.free_notes_per_day` per day (1). The
--     rest is Premium (`agenda.premium_only`), gated HERE, on the server.
--     Downgrade keeps the data read-only: a non-note event of a family that is
--     no longer Premium can be read but not changed or removed.
--   · Any active member with an account writes, without approval; only from
--     TODAY on — the past is read-only, the admin mode included (the F-67
--     relato covers the past). Nothing here touches a day's protections,
--     actual_parent or the swap workflow.
--   · Creation and deletion are kept (who, when); an edit is not a record.
--
-- IMPLEMENTATION NOTE (divergence from the card's wording, recorded on the
-- card): the card says "activity_logs registra criar/apagar". activity_logs is
-- the care_schedules audit trail, and three readers take "the newest row for a
-- date" from it as a swap's pre-edit snapshot (`_latestLogIdForDate`,
-- answer_day_notice, stamp_swap_resolution_log) — an agenda row there would be
-- picked as the snapshot and break a revert. So the event row IS its own trail:
-- created_by/created_at, deleted_by/deleted_at (a delete is a soft delete no
-- client can undo), and the Histórico renders both, like F-67's relatos.
-- =============================================================================

-- ── 1. The keys (T-84 catalogue) ─────────────────────────────────────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, min_value, max_value, help)
VALUES
	('agenda.premium_only', 'true', 'bool', 'agenda',
	 'Só o Premium cria eventos estruturados na agenda (Escola, Saúde...). A Nota fica livre.',
	 true, 'flag', 'critical', NULL, NULL,
	 jsonb_build_object(
		'controls', 'Se add_child_event / update_child_event recusam, para família sem Premium, todo tipo que não seja Nota (Escola, Saúde, Remédio, Atividade, Livre, Outro). A Nota sempre é aceita, dentro de agenda.free_notes_per_day.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Ligado (padrão): a agenda completa é um benefício Premium; a família gratuita tem a Nota do dia.',
		'if_decreased', 'Desligado: toda família cria qualquer tipo de evento e as notas deixam de ter limite por dia (só agenda.max_events_per_day vale).',
		'takes_effect', 'Servidor no próximo evento gravado; app na próxima abertura do dia.',
		'caveats', 'Rebaixamento: os eventos estruturados de uma família que perdeu o Premium ficam em só leitura — não somem.')),
	('agenda.free_notes_per_day', '1', 'int', 'agenda',
	 'Notas por dia na agenda de uma família sem Premium.',
	 true, 'count', 'sensitive', 1, 3,
	 jsonb_build_object(
		'controls', 'Quantas Notas uma família gratuita tem em um mesmo dia da agenda (as apagadas não contam). Só vale com agenda.premium_only ligado.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'A família gratuita escreve mais notas por dia — a diferença para o Premium diminui.',
		'if_decreased', 'Com 1, a Nota equivale à antiga Observação do dia: uma por dia.',
		'takes_effect', 'Servidor na próxima Nota; app na próxima abertura do dia.',
		'caveats', 'Nunca acima de agenda.max_events_per_day (regra entre chaves).')),
	('agenda.max_events_per_day', '20', 'int', 'agenda',
	 'Eventos por dia na agenda de uma família (todos os tipos, todas as crianças).',
	 true, 'count', 'normal', 5, 50,
	 jsonb_build_object(
		'controls', 'O teto de eventos ativos num mesmo dia da agenda, para qualquer plano (as apagadas não contam).',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Dias mais cheios; a folha do dia e o PDF crescem.',
		'if_decreased', 'Um dia cheio passa a recusar eventos novos; os já gravados ficam.',
		'takes_effect', 'Servidor no próximo evento; app na próxima abertura do dia.',
		'caveats', 'Nunca abaixo de agenda.free_notes_per_day (regra entre chaves).')),
	('agenda.text_max_chars', '500', 'int', 'agenda',
	 'Tamanho máximo do texto de um evento da agenda.',
	 true, 'chars', 'normal', 100, 2000,
	 jsonb_build_object(
		'controls', 'Quantos caracteres o texto livre de um evento (e o de uma Nota) aceita.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Textos mais longos; o PDF cresce. Não passa de 2000: é o CHECK da coluna child_events.body.',
		'if_decreased', 'Eventos já gravados com texto maior ficam como estão; só a próxima gravação respeita o novo limite.',
		'takes_effect', 'Servidor na próxima gravação; app na próxima abertura do dia.'))
ON CONFLICT (key) DO NOTHING;


-- ── 2. The table ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.child_events (
	id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	family_id          bigint NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
	-- Required for every kind but "note" (a note belongs to the day). A child
	-- removed by the admin takes its agenda with it.
	child_id           bigint REFERENCES public.children(id) ON DELETE CASCADE,
	event_date         date   NOT NULL,
	start_time         time,
	end_time           time,
	kind               text   NOT NULL
	                   CHECK (kind IN ('school', 'health', 'medicine', 'activity', 'free', 'note', 'other')),
	-- Free text, trimmed; the operator limit is `agenda.text_max_chars` (the
	-- RPC), 2000 is the floor for every other writer.
	body               text   CHECK (body IS NULL
	                                 OR (body = btrim(body) AND char_length(body) BETWEEN 1 AND 2000)),
	-- The observation this note was converted from (idempotency key).
	source_schedule_id bigint,
	-- F-55 PR 3: the routine a generated event belongs to.
	batch_id           uuid,
	created_by         bigint REFERENCES public.profiles(id) ON DELETE SET NULL,
	created_at         timestamptz NOT NULL DEFAULT now(),
	updated_by         bigint REFERENCES public.profiles(id) ON DELETE SET NULL,
	updated_at         timestamptz,
	deleted_by         bigint REFERENCES public.profiles(id) ON DELETE SET NULL,
	deleted_at         timestamptz,
	CONSTRAINT child_events_note_has_text CHECK (kind <> 'note' OR body IS NOT NULL),
	CONSTRAINT child_events_structured_has_child CHECK (kind = 'note' OR child_id IS NOT NULL),
	CONSTRAINT child_events_end_after_start
		CHECK (end_time IS NULL OR (start_time IS NOT NULL AND end_time > start_time))
);

CREATE INDEX IF NOT EXISTS child_events_family_date_idx
	ON public.child_events (family_id, event_date);
CREATE UNIQUE INDEX IF NOT EXISTS child_events_source_schedule_key
	ON public.child_events (source_schedule_id) WHERE source_schedule_id IS NOT NULL;

ALTER TABLE public.child_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS child_events_family_read ON public.child_events;
CREATE POLICY child_events_family_read ON public.child_events
	FOR SELECT TO authenticated
	USING (family_id = public.get_my_family_id());

REVOKE ALL ON public.child_events FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.child_events TO authenticated;
GRANT ALL ON public.child_events TO service_role;

-- The day sheet refreshes when another member writes (the F-29 pattern).
DO $$
BEGIN
	ALTER PUBLICATION supabase_realtime ADD TABLE public.child_events;
EXCEPTION
	WHEN duplicate_object THEN NULL;
	WHEN undefined_object THEN NULL;
END $$;


-- ── 3. The writer guard and the rule ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.agenda_writer_guard()
RETURNS public.profiles
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me public.profiles%ROWTYPE;
BEGIN
	IF NOT public.setting_bool('feature.child_agenda', false) THEN
		RAISE EXCEPTION 'A agenda da criança ainda não está disponível.'
			USING ERRCODE = 'feature_not_supported';
	END IF;

	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();

	-- An active member with an account and a full seat. A departed member
	-- (S-11) writes nothing; a pending one (F-56) has no account to call with.
	IF me.id IS NULL OR me.left_at IS NOT NULL THEN
		RAISE EXCEPTION 'Sua conta não pode escrever na agenda.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	RETURN me;
END;
$$;

ALTER FUNCTION public.agenda_writer_guard() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.agenda_writer_guard() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.agenda_writer_guard() TO service_role;

-- Validates one event as it WILL be, for the caller's family. Returns the
-- normalised body. p_exclude_id is the event being edited (not counted twice).
CREATE OR REPLACE FUNCTION public.agenda_validate(
	p_family_id  bigint,
	p_date       date,
	p_kind       text,
	p_child_id   bigint,
	p_start      time,
	p_end        time,
	p_body       text,
	p_exclude_id bigint DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	today      date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	v_body     text := nullif(btrim(coalesce(p_body, '')), '');
	max_chars  int  := public.setting_int('agenda.text_max_chars', 500);
	max_day    int  := public.setting_int('agenda.max_events_per_day', 20);
	free_notes int  := public.setting_int('agenda.free_notes_per_day', 1);
	gated      boolean := public.setting_bool('agenda.premium_only', true)
	                      AND NOT public.is_premium(p_family_id);
	taken      int;
BEGIN
	IF p_date IS NULL OR p_date < today THEN
		RAISE EXCEPTION 'A agenda aceita eventos de hoje em diante. Um dia que já passou é só leitura.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF p_kind IS NULL OR p_kind NOT IN ('school', 'health', 'medicine', 'activity', 'free', 'note', 'other') THEN
		RAISE EXCEPTION 'Tipo de evento desconhecido.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF v_body IS NOT NULL AND char_length(v_body) > max_chars THEN
		RAISE EXCEPTION 'O texto do evento é limitado a % caracteres.', max_chars
			USING ERRCODE = 'check_violation';
	END IF;

	IF p_kind = 'note' AND v_body IS NULL THEN
		RAISE EXCEPTION 'Escreva o texto da nota.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF p_end IS NOT NULL AND (p_start IS NULL OR p_end <= p_start) THEN
		RAISE EXCEPTION 'O horário de fim precisa vir depois do início.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF p_child_id IS NOT NULL AND NOT EXISTS (
		SELECT 1 FROM public.children WHERE id = p_child_id AND family_id = p_family_id) THEN
		RAISE EXCEPTION 'Criança não encontrada na sua família.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF p_kind <> 'note' THEN
		IF p_child_id IS NULL THEN
			RAISE EXCEPTION 'Escolha a criança do evento. Se ainda não há criança cadastrada, o administrador cadastra em Família.'
				USING ERRCODE = 'check_violation';
		END IF;
		IF gated THEN
			RAISE EXCEPTION 'A agenda completa (escola, saúde, remédio, atividades) é um recurso Premium. No plano gratuito, a agenda tem a nota do dia.'
				USING ERRCODE = 'check_violation';
		END IF;
	END IF;

	SELECT count(*)::int INTO taken
	FROM public.child_events
	WHERE family_id = p_family_id AND event_date = p_date AND deleted_at IS NULL
	  AND (p_exclude_id IS NULL OR id <> p_exclude_id);
	IF taken >= max_day THEN
		RAISE EXCEPTION 'Este dia já tem % eventos na agenda, o máximo por dia.', max_day
			USING ERRCODE = 'check_violation';
	END IF;

	IF p_kind = 'note' AND gated THEN
		SELECT count(*)::int INTO taken
		FROM public.child_events
		WHERE family_id = p_family_id AND event_date = p_date AND deleted_at IS NULL
		  AND kind = 'note'
		  AND (p_exclude_id IS NULL OR id <> p_exclude_id);
		IF taken >= free_notes THEN
			RAISE EXCEPTION 'No plano gratuito, a agenda aceita % nota(s) por dia. Com o Premium, as notas não têm limite.', free_notes
				USING ERRCODE = 'check_violation';
		END IF;
	END IF;

	RETURN v_body;
END;
$$;

ALTER FUNCTION public.agenda_validate(bigint, date, text, bigint, time, time, text, bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.agenda_validate(bigint, date, text, bigint, time, time, text, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.agenda_validate(bigint, date, text, bigint, time, time, text, bigint) TO service_role;


-- ── 4. add / update / delete ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.add_child_event(
	p_date     date,
	p_kind     text,
	p_child_id bigint DEFAULT NULL,
	p_start    time   DEFAULT NULL,
	p_end      time   DEFAULT NULL,
	p_body     text   DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me     public.profiles%ROWTYPE := public.agenda_writer_guard();
	v_body text;
	new_id bigint;
BEGIN
	v_body := public.agenda_validate(me.family_id, p_date, p_kind, p_child_id, p_start, p_end, p_body);

	INSERT INTO public.child_events
		(family_id, child_id, event_date, start_time, end_time, kind, body, created_by)
	VALUES (me.family_id, p_child_id, p_date, p_start, p_end, p_kind, v_body, me.id)
	RETURNING id INTO new_id;

	RETURN new_id;
END;
$$;

ALTER FUNCTION public.add_child_event(date, text, bigint, time, time, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.add_child_event(date, text, bigint, time, time, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_child_event(date, text, bigint, time, time, text) TO authenticated, service_role;

-- The event as it IS must be writable (today on, not deleted, not a Premium
-- kind of a family that lapsed) and as it WILL be must pass the rule.
CREATE OR REPLACE FUNCTION public.agenda_editable_row(p_me public.profiles, p_event_id bigint)
RETURNS public.child_events
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	ev    public.child_events%ROWTYPE;
	today date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
	SELECT * INTO ev FROM public.child_events
	WHERE id = p_event_id AND family_id = p_me.family_id AND deleted_at IS NULL;
	IF ev.id IS NULL THEN
		RAISE EXCEPTION 'Evento não encontrado na agenda da sua família.'
			USING ERRCODE = 'no_data_found';
	END IF;
	IF ev.event_date < today THEN
		RAISE EXCEPTION 'A agenda aceita eventos de hoje em diante. Um dia que já passou é só leitura.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF ev.kind <> 'note'
	   AND public.setting_bool('agenda.premium_only', true)
	   AND NOT public.is_premium(p_me.family_id) THEN
		RAISE EXCEPTION 'Este evento é da agenda Premium e fica só para leitura no plano gratuito.'
			USING ERRCODE = 'check_violation';
	END IF;
	RETURN ev;
END;
$$;

ALTER FUNCTION public.agenda_editable_row(public.profiles, bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.agenda_editable_row(public.profiles, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.agenda_editable_row(public.profiles, bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.update_child_event(
	p_event_id bigint,
	p_date     date,
	p_kind     text,
	p_child_id bigint DEFAULT NULL,
	p_start    time   DEFAULT NULL,
	p_end      time   DEFAULT NULL,
	p_body     text   DEFAULT NULL)
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

	UPDATE public.child_events SET
		event_date = p_date,
		kind       = p_kind,
		child_id   = p_child_id,
		start_time = p_start,
		end_time   = p_end,
		body       = v_body,
		updated_by = me.id,
		updated_at = now()
	WHERE id = ev.id;
END;
$$;

ALTER FUNCTION public.update_child_event(bigint, date, text, bigint, time, time, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.update_child_event(bigint, date, text, bigint, time, time, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_child_event(bigint, date, text, bigint, time, time, text) TO authenticated, service_role;

-- A delete is a SOFT delete: the row stays, with who and when, so the
-- Histórico can say that it was removed. No client can bring it back.
CREATE OR REPLACE FUNCTION public.delete_child_event(p_event_id bigint)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me public.profiles%ROWTYPE := public.agenda_writer_guard();
	ev public.child_events%ROWTYPE;
BEGIN
	ev := public.agenda_editable_row(me, p_event_id);
	UPDATE public.child_events SET deleted_by = me.id, deleted_at = now()
	WHERE id = ev.id;
END;
$$;

ALTER FUNCTION public.delete_child_event(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.delete_child_event(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_child_event(bigint) TO authenticated, service_role;


-- ── 5. The observation becomes read-only while the agenda is on ─────────────
-- Every client UPDATE sends the whole row, notes included, so the guard refuses
-- only a CHANGED value. With the flag off nothing changes.

CREATE OR REPLACE FUNCTION public.freeze_day_observation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
	IF public.setting_bool('feature.child_agenda', false)
	   AND NEW.notes IS DISTINCT FROM (CASE WHEN TG_OP = 'UPDATE' THEN OLD.notes END) THEN
		RAISE EXCEPTION 'A observação do dia virou a agenda. Use a agenda do dia para escrever uma nota.'
			USING ERRCODE = 'check_violation';
	END IF;
	RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_freeze_day_observation ON public.care_schedules;
CREATE TRIGGER trigger_freeze_day_observation
	BEFORE INSERT OR UPDATE OF notes ON public.care_schedules
	FOR EACH ROW EXECUTE FUNCTION public.freeze_day_observation();


-- ── 6. The conversion — idempotent, run only where the flag is on ────────────

CREATE OR REPLACE FUNCTION public.convert_observations_to_agenda()
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	converted int;
BEGIN
	-- One "note" per non-empty observation, on its own day, with no child (a
	-- note belongs to the day) and no author: nobody wrote it through the
	-- agenda. Past days included — they are the record. Re-running is a no-op.
	INSERT INTO public.child_events
		(family_id, event_date, kind, body, source_schedule_id, created_at)
	SELECT cs.family_id, cs.schedule_date, 'note',
	       left(btrim(cs.notes), 2000), cs.id,
	       COALESCE(cs.updated_at, cs.created_at, now())
	FROM public.care_schedules cs
	WHERE nullif(btrim(cs.notes), '') IS NOT NULL
	ON CONFLICT (source_schedule_id) WHERE source_schedule_id IS NOT NULL DO NOTHING;

	GET DIAGNOSTICS converted = ROW_COUNT;
	RETURN converted;
END;
$$;

ALTER FUNCTION public.convert_observations_to_agenda() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.convert_observations_to_agenda() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.convert_observations_to_agenda() TO service_role;

DO $$
BEGIN
	IF public.setting_bool('feature.child_agenda', false) THEN
		PERFORM public.convert_observations_to_agenda();
	END IF;
END $$;


-- ── 7. The rule between the two agenda counts (T-80's DEFERRED check) ───────
-- Recreated from its LATEST definition (20260924090000_t83_support_limits.sql,
-- re-checked 24/09/2026); only the agenda rule is new.

CREATE OR REPLACE FUNCTION public.app_settings_cross_check()
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	months_free      int := public.setting_int('calendar_months_free', 6);
	months_premium   int := public.setting_int('calendar_months_premium', 24);
	free_seats       int := public.setting_int('free_caregivers', 2);
	max_seats        int := public.setting_int('max_caregivers', 4);
	grace            int := public.setting_int('billing.grace_days', 7);
	grace_warning    int := public.setting_int('billing.grace_warning_days', 2);
	cap_free         int := public.setting_int('email_cap_free', 100);
	cap_premium      int := public.setting_int('email_cap_premium', 10000);
	price_monthly    int := public.setting_int('billing.price_monthly_cents', 549);
	price_annual     int := public.setting_int('billing.price_annual_cents', 5490);
	override_free    int := public.setting_int('override_free_days', 7);
	override_premium int := public.setting_int('override_premium_months', 6);
	poll_degraded    int := public.setting_int('sync.poll_seconds_degraded', 25);
	poll_healthy     int := public.setting_int('sync.poll_seconds_healthy', 120);
	muted            jsonb;
	pushable         text;
	muted_type       text;
	anon_hourly      int := public.setting_int('support.anon_hourly', 3);
	anon_daily       int := public.setting_int('support.anon_daily', 10);
	member_hourly    int := public.setting_int('support.member_hourly', 5);
	member_daily     int := public.setting_int('support.member_daily', 20);
	agenda_notes     int := public.setting_int('agenda.free_notes_per_day', 1);
	agenda_max       int := public.setting_int('agenda.max_events_per_day', 20);
BEGIN
	IF months_free > months_premium THEN
		RAISE EXCEPTION 'calendar_months_free (%) precisa ser no máximo calendar_months_premium (%): o plano gratuito não planeja mais longe que o Premium.',
			months_free, months_premium
			USING ERRCODE = 'check_violation';
	END IF;

	IF free_seats > max_seats THEN
		RAISE EXCEPTION 'free_caregivers (%) precisa ser no máximo max_caregivers (%): o gratuito não inclui mais responsáveis que o teto.',
			free_seats, max_seats
			USING ERRCODE = 'check_violation';
	END IF;

	IF grace_warning >= grace THEN
		RAISE EXCEPTION 'billing.grace_warning_days (%) precisa ser menor que billing.grace_days (%): o aviso sai antes do rebaixamento, nunca no mesmo dia.',
			grace_warning, grace
			USING ERRCODE = 'check_violation';
	END IF;

	IF cap_free > cap_premium THEN
		RAISE EXCEPTION 'email_cap_free (%) precisa ser no máximo email_cap_premium (%).',
			cap_free, cap_premium
			USING ERRCODE = 'check_violation';
	END IF;

	IF price_annual > 12 * price_monthly THEN
		RAISE EXCEPTION 'billing.price_annual_cents (%) precisa ser no máximo 12 × billing.price_monthly_cents (%): o anual não pode custar mais que doze meses.',
			public.app_settings_format(price_annual, 'cents_brl'),
			public.app_settings_format(12 * price_monthly, 'cents_brl')
			USING ERRCODE = 'check_violation';
	END IF;

	IF override_free > override_premium * 28 THEN
		RAISE EXCEPTION 'override_free_days (%) precisa ser no máximo override_premium_months × 28 (% dias): o gratuito não corrige mais para trás que o Premium.',
			override_free, override_premium * 28
			USING ERRCODE = 'check_violation';
	END IF;
	-- T-83: with the socket up the poll is a safety net, so it is either off
	-- (0) or never MORE frequent than the poll that stands in for a dead socket.
	IF poll_healthy <> 0 AND poll_healthy < poll_degraded THEN
		RAISE EXCEPTION 'sync.poll_seconds_healthy (%) precisa ser 0 (desligado) ou pelo menos sync.poll_seconds_degraded (%): com o socket de pé o poll nunca fica mais frequente que sem ele.',
			poll_healthy, poll_degraded
			USING ERRCODE = 'check_violation';
	END IF;

	-- T-83: `push.disabled_types` may only name a type the dispatcher pushes.
	-- The list is read from the dispatcher's OWN filter, so the twelve types
	-- keep one home (the push mirror tests pin it against push.ts).
	muted := public.setting_text('push.disabled_types', '[]')::jsonb;
	IF jsonb_typeof(muted) <> 'array' THEN
		RAISE EXCEPTION 'push.disabled_types precisa ser uma lista JSON de tipos, como ["swap_requested"].'
			USING ERRCODE = 'check_violation';
	END IF;
	pushable := substring(pg_get_functiondef('public.dispatch_push_notification()'::regprocedure)
	                      from 'NEW\.type NOT IN \(([^)]*)\)');
	FOR muted_type IN SELECT jsonb_array_elements_text(muted) LOOP
		IF pushable IS NULL OR position(quote_literal(muted_type) in pushable) = 0 THEN
			RAISE EXCEPTION 'push.disabled_types: "%" não é um tipo que gera push. Os tipos são os do filtro de dispatch_push_notification.', muted_type
				USING ERRCODE = 'check_violation';
		END IF;
	END LOOP;

	-- T-83: a support limit per hour never exceeds the one per day it lives in.
	IF anon_hourly > anon_daily THEN
		RAISE EXCEPTION 'support.anon_hourly (%) precisa ser no máximo support.anon_daily (%).', anon_hourly, anon_daily
			USING ERRCODE = 'check_violation';
	END IF;
	IF member_hourly > member_daily THEN
		RAISE EXCEPTION 'support.member_hourly (%) precisa ser no máximo support.member_daily (%).', member_hourly, member_daily
			USING ERRCODE = 'check_violation';
	END IF;

	-- F-55 (T-84 rule 2): a free family's notes per day never exceed what any
	-- day may hold at all.
	IF agenda_notes > agenda_max THEN
		RAISE EXCEPTION 'agenda.free_notes_per_day (%) precisa ser no máximo agenda.max_events_per_day (%).', agenda_notes, agenda_max
			USING ERRCODE = 'check_violation';
	END IF;
END;
$$;

ALTER FUNCTION public.app_settings_cross_check() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.app_settings_cross_check() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.app_settings_cross_check() TO service_role;

-- ── 8. The F-47 revert moves no text while the agenda is on ─────────────────
-- Recreated from its LATEST definition (20260804220000_f47_revert_notes.sql,
-- re-checked 24/09/2026); only the notes line changes.

CREATE OR REPLACE FUNCTION public.restore_pre_edit_state(
    p_schedule_id     bigint,
    p_pre_edit_log_id bigint,
    p_restore_notes   boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    snap jsonb;
BEGIN
    IF p_schedule_id IS NULL THEN
        RETURN;
    END IF;

    -- No snapshot reference (swaps approved before F-26): clear the swap only.
    IF p_pre_edit_log_id IS NULL THEN
        UPDATE public.care_schedules
        SET actual_parent_id = NULL, updated_at = timezone('utc', now())
        WHERE id = p_schedule_id;
        RETURN;
    END IF;

    SELECT old_data INTO snap FROM public.activity_logs WHERE id = p_pre_edit_log_id;

    -- old_data NULL → the day was created by the edit; restoring "before"
    -- removes it. Nothing to decide about the observation: the day goes.
    IF snap IS NULL THEN
        DELETE FROM public.care_schedules WHERE id = p_schedule_id;
        RETURN;
    END IF;

    UPDATE public.care_schedules
    SET scheduled_parent_id = COALESCE((snap->>'scheduled_parent_id')::bigint, scheduled_parent_id),
        actual_parent_id    = (snap->>'actual_parent_id')::bigint,
        handoff_time        = (snap->>'handoff_time')::time,
        -- F-47: the observation moves only when the requester asked for it.
        -- NULL is treated as "no" — the safe answer is also the default one.
        -- F-55: with the agenda on, the observation is read-only and the
        -- revert moves no text at all (the notes live in the agenda now).
        notes               = CASE WHEN COALESCE(p_restore_notes, false)
                                    AND NOT public.setting_bool('feature.child_agenda', false)
                                   THEN snap->>'notes'
                                   ELSE notes
                              END,
        updated_at          = timezone('utc', now())
    WHERE id = p_schedule_id;
END;
$$;

ALTER FUNCTION public.restore_pre_edit_state(bigint, bigint, boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.restore_pre_edit_state(bigint, bigint, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.restore_pre_edit_state(bigint, bigint, boolean) TO service_role;

-- ── 9. The operator's usage report gains the agenda's COUNTS (F-69 rule) ────
-- Recreated from its LATEST definition (20260924050000_t82_server_parameters
-- .sql, re-checked 24/09/2026); the weekly `agenda_events` and the `agenda`
-- object are new. Converted notes are not "created" in a week: they count in
-- `converted` only.

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
