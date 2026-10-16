-- =============================================================================
-- F-07 (PR 5a) — the rest of the server reads the lanes
--
-- PR 2 made the day's own rules lane-aware. These are the functions that
-- still read "the day" by (family, date) and pick ONE row with SELECT INTO —
-- right for a single-plan family (one row per date, unchanged below), an
-- arbitrary lane for a per-child one:
--
--   · the aviso (F-52): who may send one is decided in ANY lane (the carer of
--     one child is "in the middle of the day" too), and taking the day
--     ("fica com o dia") moves EVERY lane of today that is the sender's —
--     each through its own request, applied as the target and approved, the
--     path PR 2 already locks per lane;
--   · the agenda's "responsible" (F-55): the carer of the event's CHILD in a
--     per-child plan (a note, which names no child, reads the first lane);
--   · the plan's end (F-70) and the routine's reach (F-55): only the lanes of
--     the family's CURRENT mode count — a family that switched keeps old
--     lanes in the past, and a past lane is not "the plan ending". In a
--     per-child plan the end is the FIRST child's plan to run out, so no lane
--     runs out unannounced;
--   · the operator's usage report (F-69): the transition's D-1 is in the same
--     lane.
--
-- Deliberately unchanged: `report_attestation_summary` (F-64) counts rows —
-- in a per-child plan that is child-days, and the PDF's per-child sections
-- (PR 5b) add up to it.
-- =============================================================================

-- ── 1. The aviso: eligible in any lane ───────────────────────────────────────
-- Body from production (t82_aviso_daily_cap), the three SELECT INTO replaced
-- by lane-aware EXISTS. A single-plan family has one lane, so the answers are
-- the same as before.

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

	-- The three ends of the day, mirrored from `noticeSenderIds` — per lane
	-- (F-07): today's carer, yesterday's, and the next DIFFERENT carer of the
	-- same lane inside the 90-day window. Unplanned days are not rows, so a
	-- gap is skipped rather than read as a change of carer.
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
	    OR EXISTS (
		SELECT 1
		FROM (SELECT DISTINCT cs.child_id FROM public.care_schedules cs
		      WHERE cs.family_id = me.family_id
		        AND cs.schedule_date BETWEEN today AND today + 90) lanes
		CROSS JOIN LATERAL (
			SELECT COALESCE(n.actual_parent_id, n.scheduled_parent_id) AS carer
			FROM public.care_schedules n
			WHERE n.family_id = me.family_id
			  AND n.child_id IS NOT DISTINCT FROM lanes.child_id
			  AND n.schedule_date > today
			  AND n.schedule_date <= today + 90
			  AND COALESCE(n.actual_parent_id, n.scheduled_parent_id) IS DISTINCT FROM (
				SELECT COALESCE(t.actual_parent_id, t.scheduled_parent_id)
				FROM public.care_schedules t
				WHERE t.family_id = me.family_id
				  AND t.child_id IS NOT DISTINCT FROM lanes.child_id
				  AND t.schedule_date = today)
			ORDER BY n.schedule_date
			LIMIT 1) nx
		WHERE nx.carer = me.id)
	INTO eligible;

	IF NOT eligible THEN
		RAISE EXCEPTION 'Um aviso é de quem está no meio da troca do dia: quem está com a criança hoje, quem entregou hoje, ou quem recebe na próxima troca.'
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


-- ── 2. Taking the day moves every lane of today that is the sender's ────────
-- Body from production (f52_answer_day_notice); the "keeping" branch loops
-- over the sender's lanes. The notice keeps ONE `swap_request_id` (the first
-- lane's) — the outcome table's shape — and every lane's request stays in
-- `swap_requests`, stamped with its lane.

CREATE OR REPLACE FUNCTION public.answer_day_notice(p_notice_id bigint, p_outcome text, p_note text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
	me          public.profiles%ROWTYPE;
	notice      public.day_notices%ROWTYPE;
	day_row     public.care_schedules%ROWTYPE;
	sender_name text;
	today       date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	note        text := nullif(btrim(p_note), '');
	swap_id     bigint;
	lane_swap   bigint;
	pre_edit    bigint;
	moved       int := 0;
	d           text;
	d_iso       text;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();
	IF me.id IS NULL OR me.left_at IS NOT NULL THEN
		RAISE EXCEPTION 'Sua conta não pode responder avisos.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	IF p_outcome NOT IN ('helping', 'keeping') THEN
		RAISE EXCEPTION 'Resposta desconhecida.' USING ERRCODE = 'check_violation';
	END IF;

	IF note IS NOT NULL AND char_length(note) > 140 THEN
		RAISE EXCEPTION 'O detalhe da resposta é limitado a 140 caracteres.'
			USING ERRCODE = 'check_violation';
	END IF;

	SELECT * INTO notice FROM public.day_notices WHERE id = p_notice_id;

	-- One message for "not yours to answer" and "does not exist": a caller
	-- learning which of the two it was learns about another family's rows.
	IF notice.id IS NULL OR notice.family_id IS DISTINCT FROM me.family_id THEN
		RAISE EXCEPTION 'Aviso não encontrado.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	-- An aviso is not a conversation with oneself.
	IF notice.sender_profile_id = me.id THEN
		RAISE EXCEPTION 'Você não pode responder ao próprio aviso.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF notice.schedule_date <> today THEN
		RAISE EXCEPTION 'Só o aviso de hoje pode ser respondido.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- "Só avisando" asks for nothing, so there is nothing to accept; and the
	-- day can only be taken when the aviso OFFERED it.
	IF notice.request = 'info' THEN
		RAISE EXCEPTION 'Este aviso não pede nada.' USING ERRCODE = 'check_violation';
	END IF;
	IF p_outcome = 'keeping' AND notice.request <> 'keep' THEN
		RAISE EXCEPTION 'Este aviso pediu ajuda, não que alguém ficasse com a criança.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- The UNIQUE below decides the real race; this says WHY in a sentence.
	IF EXISTS (SELECT 1 FROM public.day_notice_outcomes o WHERE o.notice_id = notice.id) THEN
		RAISE EXCEPTION 'Este aviso já foi resolvido.' USING ERRCODE = 'check_violation';
	END IF;

	SELECT full_name INTO sender_name
	FROM public.profiles WHERE id = notice.sender_profile_id;

	d     := to_char(notice.schedule_date, 'DD/MM/YYYY');
	d_iso := to_char(notice.schedule_date, 'YYYY-MM-DD');

	IF p_outcome = 'keeping' THEN
		IF NOT EXISTS (SELECT 1 FROM public.care_schedules
		               WHERE family_id = me.family_id AND schedule_date = notice.schedule_date) THEN
			RAISE EXCEPTION 'O dia de hoje não está planejado.'
				USING ERRCODE = 'check_violation';
		END IF;

		-- F-07: every lane of today that is still the sender's. The offer is
		-- only good while the day is still theirs — a lane that moved since (an
		-- admin correction, another workflow) is not taken, and when NO lane is
		-- left the aviso is stale.
		FOR day_row IN
			SELECT * FROM public.care_schedules
			WHERE family_id = me.family_id AND schedule_date = notice.schedule_date
			  AND COALESCE(actual_parent_id, scheduled_parent_id) = notice.sender_profile_id
			ORDER BY child_id NULLS FIRST
		LOOP
			-- F-26: the snapshot a later revert restores from — the newest audit
			-- row for this date IN THIS LANE, exactly as the client picks it.
			SELECT id INTO pre_edit FROM public.activity_logs
			WHERE affected_date = notice.schedule_date AND family_id = me.family_id
			  AND child_id IS NOT DISTINCT FROM day_row.child_id
			ORDER BY id DESC LIMIT 1;

			-- Step 1 — the request. Scenario A: the sender (whose day it is)
			-- asks, and the person proposed as the real carer is the answerer.
			-- `swap_requests_one_pending_per_date` (per lane since PR 2) refuses
			-- a lane that already has an open request — frozen is frozen.
			INSERT INTO public.swap_requests (
				schedule_date, schedule_id, requesting_profile_id, target_profile_id,
				previous_actual_parent_id, proposed_actual_parent_id,
				proposed_handoff_time, status, pre_edit_log_id, created_at, updated_at)
			VALUES (
				notice.schedule_date, day_row.id, notice.sender_profile_id, me.id,
				day_row.actual_parent_id, me.id,
				NULL, 'pending', pre_edit, now(), now())
			RETURNING id INTO lane_swap;

			-- Step 2 — apply it AS THE TARGET (`enforce_day_protection`'s
			-- is_target branch, per lane).
			UPDATE public.care_schedules
			SET actual_parent_id = me.id,
			    updated_at       = timezone('utc', now())
			WHERE id = day_row.id;

			-- Step 3 — close it. `resolved_by = 'user'`: a person decided this.
			UPDATE public.swap_requests
			SET status = 'approved', resolved_at = now(), updated_at = now(),
			    resolved_by = 'user'
			WHERE id = lane_swap;

			swap_id := COALESCE(swap_id, lane_swap);
			moved := moved + 1;
		END LOOP;

		IF moved = 0 THEN
			RAISE EXCEPTION 'O dia de hoje já mudou de responsável; o aviso não vale mais.'
				USING ERRCODE = 'check_violation';
		END IF;
	END IF;

	-- The outcome is written LAST, so the UNIQUE on notice_id is what decides a
	-- race — and the loser's swaps and day updates roll back with it, because
	-- a plpgsql function is one transaction.
	INSERT INTO public.day_notice_outcomes
		(notice_id, outcome, actor_profile_id, note, swap_request_id)
	VALUES (notice.id, p_outcome, me.id, note, swap_id);

	-- ── Whoever asked, told ──
	INSERT INTO public.notifications (recipient_profile_id, type, title, message, params, swap_request_id)
	VALUES (
		notice.sender_profile_id,
		'day_notice',
		CASE p_outcome
			WHEN 'keeping' THEN 'O dia de hoje mudou de responsável'
			ELSE 'Alguém vai ajudar'
		END,
		CASE p_outcome
			WHEN 'keeping' THEN me.full_name || ' vai ficar com a criança hoje. O dia de hoje passou para '
				|| me.full_name || '.'
			ELSE me.full_name || ' vai ajudar agora.'
		END || CASE WHEN note IS NULL THEN '' ELSE ' "' || note || '"' END,
		jsonb_strip_nulls(jsonb_build_object(
			'kind', p_outcome,
			'name', me.full_name,
			'note', note,
			'date', d_iso)),
		swap_id);

	-- ── F-28 fan-out: the calendar moved, so the uninvolved are told ──
	-- Same type, same `kind` and the same four values the approve path writes,
	-- so the renderer needs no branch of its own. F-56: only caregivers with an
	-- account — a pending member has no session to read it in.
	IF p_outcome = 'keeping' THEN
		INSERT INTO public.notifications (recipient_profile_id, type, title, message, params, swap_request_id)
		SELECT p.id, 'swap_family_info', 'Calendário atualizado',
		       me.full_name || ' ficará com a criança no dia ' || d
		           || ' (troca solicitada por ' || COALESCE(sender_name, 'alguém')
		           || ' e aprovada por ' || me.full_name || ').',
		       jsonb_build_object(
		           'kind', 'swap',
		           'name', me.full_name,
		           'date', d_iso,
		           'requester', sender_name,
		           'approver', me.full_name),
		       swap_id
		FROM public.profiles p
		WHERE p.family_id = me.family_id
		  AND p.id <> me.id
		  AND p.id <> notice.sender_profile_id
		  AND p.left_at IS NULL
		  AND p.user_id IS NOT NULL;
	END IF;

	RETURN swap_id;
END;
$function$;


-- ── 3. The agenda's "responsible" is the carer of the event's child ─────────
-- Body from production (f55_agenda_notify); only the day_parent lookup moves.

CREATE OR REPLACE FUNCTION public.agenda_notify(p_ev child_events, p_type text, p_actor bigint, p_routine boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
		-- F-07: the family lane where there is one; in a per-child plan the
		-- event's child's lane, and for a note (no child) the first child's.
		SELECT COALESCE(cs.actual_parent_id, cs.scheduled_parent_id) INTO day_parent
		FROM public.care_schedules cs
		LEFT JOIN public.children ch ON ch.id = cs.child_id
		WHERE cs.family_id = p_ev.family_id AND cs.schedule_date = p_ev.event_date
		  AND (cs.child_id IS NULL OR p_ev.child_id IS NULL OR cs.child_id = p_ev.child_id)
		ORDER BY cs.child_id IS NOT NULL, ch.sort_order, cs.child_id
		LIMIT 1;
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
$function$;


-- ── 4. The plan's end counts the lanes of the current mode ──────────────────

-- The last planned day of a family, as its CURRENT mode reads it: the family
-- lane in a single plan; in a per-child plan the earliest end among the
-- children's lanes (the first child whose plan runs out). Nothing planned →
-- NULL. Past lanes of the other mode never count.
CREATE OR REPLACE FUNCTION public.family_plan_last_day(p_family_id bigint)
RETURNS date
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
	SELECT CASE WHEN f.schedule_mode = 'per_child'
	            THEN (SELECT min(lane_last) FROM (
	                      SELECT max(cs.schedule_date) AS lane_last
	                      FROM public.care_schedules cs
	                      WHERE cs.family_id = f.id AND cs.child_id IS NOT NULL
	                      GROUP BY cs.child_id) l)
	            ELSE (SELECT max(cs.schedule_date) FROM public.care_schedules cs
	                  WHERE cs.family_id = f.id AND cs.child_id IS NULL)
	       END
	FROM public.families f WHERE f.id = p_family_id;
$$;

ALTER FUNCTION public.family_plan_last_day(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.family_plan_last_day(bigint) FROM PUBLIC, anon;
-- The app's F-70 strip reads the same answer (`fetchLastPlannedDay`); the
-- function reads only the caller's own family through the argument, so it is
-- guarded to it.
GRANT EXECUTE ON FUNCTION public.family_plan_last_day(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.my_plan_last_day()
RETURNS date
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
	SELECT public.family_plan_last_day(public.get_my_family_id());
$$;

ALTER FUNCTION public.my_plan_last_day() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.my_plan_last_day() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_plan_last_day() TO authenticated, service_role;

-- Body from production (f70_plan_end_reminders); the per-family last day is
-- `family_plan_last_day` instead of max() over every row.
CREATE OR REPLACE FUNCTION public.plan_end_reminders_due(p_family_id bigint DEFAULT NULL::bigint)
 RETURNS TABLE(profile_id bigint, stage text, plan_end date, send_email boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
	today   date := (timezone('America/Sao_Paulo', now()))::date;
	r       record;
	v_stage text;
BEGIN
	FOR r IN
		SELECT fams.fam_id, public.family_plan_last_day(fams.fam_id) AS last_day
		  FROM (SELECT DISTINCT cs.family_id AS fam_id
		          FROM public.care_schedules cs
		         WHERE p_family_id IS NULL OR cs.family_id = p_family_id) fams
	LOOP
		-- F-07: a family whose current mode has no row yet (a switch with
		-- nothing from today on) has no plan to end.
		IF r.last_day IS NULL THEN
			CONTINUE;
		END IF;

		IF r.last_day < today THEN
			v_stage := 'ended';
		ELSIF r.last_day - today <= 7 THEN
			v_stage := 'd7';
		ELSIF r.last_day - today <= 30 THEN
			v_stage := 'd30';
		ELSE
			CONTINUE;
		END IF;

		-- Once per plan end and stage. A D-30 is also moot once the D-7 of the
		-- same end went out (a family first seen inside the last week gets the
		-- D-7 only, and must not get a late D-30 on top of it).
		IF EXISTS (
			SELECT 1 FROM public.plan_end_reminders x
			 WHERE x.family_id = r.fam_id
			   AND x.plan_end  = r.last_day
			   AND (x.stage = v_stage OR (v_stage = 'd30' AND x.stage = 'd7'))
		) THEN
			CONTINUE;
		END IF;

		IF EXISTS (
			SELECT 1 FROM public.family_deletion_requests d
			 WHERE d.family_id = r.fam_id AND d.status = 'pending'
		) THEN
			CONTINUE;
		END IF;

		-- No reader, no stamp: a family whose only members are placeholders or
		-- departed is left unmarked, so a member who joins later is still told.
		IF NOT EXISTS (
			SELECT 1 FROM public.profiles p
			 WHERE p.family_id = r.fam_id
			   AND p.left_at IS NULL
			   AND p.user_id IS NOT NULL
		) THEN
			CONTINUE;
		END IF;

		INSERT INTO public.plan_end_reminders (family_id, plan_end, stage)
		VALUES (r.fam_id, r.last_day, v_stage);

		-- The reliable channel, in the same transaction as the stamp. PT-BR
		-- sentences byte-identical to the catalog (U-13); the reader's device
		-- rebuilds them from `params` in its own language.
		INSERT INTO public.notifications (recipient_profile_id, type, title, message, params)
		SELECT p.id, 'plan_ending',
		       CASE WHEN v_stage = 'ended'
		            THEN 'O planejamento terminou'
		            ELSE 'O planejamento termina em breve' END,
		       CASE WHEN v_stage = 'ended'
		            THEN 'O último dia planejado foi ' || to_char(r.last_day, 'DD/MM/YYYY') ||
		                 '. Planeje os próximos meses no calendário.'
		            ELSE 'O planejamento da família vai até ' || to_char(r.last_day, 'DD/MM/YYYY') ||
		                 '. Planeje os próximos meses.' END,
		       jsonb_build_object(
		           'kind', CASE WHEN v_stage = 'ended' THEN 'ended' ELSE 'ending' END,
		           'date', to_char(r.last_day, 'YYYY-MM-DD'))
		  FROM public.profiles p
		 WHERE p.family_id = r.fam_id
		   AND p.left_at IS NULL
		   AND p.user_id IS NOT NULL;

		-- One row per recipient for the e-mail twin (D-7 and ended only).
		RETURN QUERY
		SELECT p.id, v_stage, r.last_day, v_stage <> 'd30'
		  FROM public.profiles p
		 WHERE p.family_id = r.fam_id
		   AND p.left_at IS NULL
		   AND p.user_id IS NOT NULL;
	END LOOP;
END;
$function$;

-- The routine's reach (F-55): the same last day, clamped to the horizon.
-- Body from production (f55_routine_plan_end_null).
CREATE OR REPLACE FUNCTION public.agenda_plan_end(p_family_id bigint, p_from date)
 RETURNS date
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
	today   date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	months  int  := CASE WHEN public.is_premium(p_family_id)
	                     THEN public.setting_int('calendar_months_premium', 24)
	                     ELSE public.setting_int('calendar_months_free', 6) END;
	last_day date := public.family_plan_last_day(p_family_id);
BEGIN
	-- Nothing planned: nothing to reach. Checked BEFORE the clamp, because
	-- LEAST(NULL, x) is x.
	IF last_day IS NULL THEN
		RETURN NULL;
	END IF;

	last_day := LEAST(last_day, (today + make_interval(months => months))::date);
	IF last_day < p_from THEN
		RETURN NULL;
	END IF;
	RETURN last_day;
END;
$function$;


-- ── 5. The operator's usage report: D-1 in the same lane ────────────────────
-- A 17k-character body whose ONLY change is one join predicate, so the
-- production text is edited in place — and the migration fails loudly if the
-- exact clause is not there (a later rewrite of the report must carry the
-- lane predicate itself).
DO $$
DECLARE
	def  text := pg_get_functiondef('public.admin_family_usage_report(bigint)'::regprocedure);
	old  text := 'ON p.family_id = d.family_id AND p.schedule_date = d.schedule_date - 1';
	new  text := 'ON p.family_id = d.family_id AND p.schedule_date = d.schedule_date - 1'
	             || ' AND p.child_id IS NOT DISTINCT FROM d.child_id';
BEGIN
	IF position(old IN def) = 0 THEN
		RAISE EXCEPTION 'F-07: admin_family_usage_report no longer has the D-1 join this migration rewrites';
	END IF;
	IF position('p.child_id IS NOT DISTINCT FROM d.child_id' IN def) = 0 THEN
		EXECUTE replace(def, old, new);
	END IF;
END;
$$;
