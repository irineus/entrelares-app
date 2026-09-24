-- =============================================================================
-- F-55 (PR 3 of 4) — the routine: a weekly model applied to the rest of the plan
--
-- Decisions locked by the owner (24/09/2026, F-55 Notes, item 6): lines per day
-- PLUS a routine model applied from a day on until the END OF THE PLAN
-- (max(schedule_date)), inside the tier horizon (F-39); re-applying replaces
-- only the future events the routine generated (batch_id), and the Histórico
-- folds the batch (the F-51 pattern). NOT RRULE: a routine is a generator, and
-- what it generates are ordinary `child_events` rows.
--
--   * `child_routines` — the model: kind, child, times, text, weekdays (ISO,
--     1 = Monday … 7 = Sunday), the first day and the last day it reached.
--     Its id is the `batch_id` of every event it generated.
--   * `save_child_routine` — creates, or re-applies an existing routine from a
--     day on: the routine's events from that day on are soft-deleted (they stay
--     in the record, with who and when) and the new ones inserted, all in one
--     transaction. Every generated day passes `agenda_validate` — the same rule
--     as a single event: Premium gate, the free note, the day's cap, the text.
--     One refused day refuses the whole routine, naming the day.
--   * `stop_child_routine` — removes the routine's events from a day on.
--   * An event of a routine edited on its own LEAVES the routine (trigger), so
--     a later re-apply does not overwrite a hand edit.
--   * F-69: `agenda.routines` (active) and `agenda.events_from_routine`.
--
-- Everything behind `feature.child_agenda` (the writer guard). No new key: the
-- catalogue (T-84) has none for the routine.
-- =============================================================================


-- ── 1. The routine ───────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.child_routines (
	id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	family_id   bigint NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
	child_id    bigint REFERENCES public.children(id) ON DELETE CASCADE,
	kind        text   NOT NULL
	            CHECK (kind IN ('school', 'health', 'medicine', 'activity', 'free', 'note', 'other')),
	start_time  time,
	end_time    time,
	body        text   CHECK (body IS NULL
	                          OR (body = btrim(body) AND char_length(body) BETWEEN 1 AND 2000)),
	weekdays    smallint[] NOT NULL
	            CHECK (cardinality(weekdays) BETWEEN 1 AND 7
	                   AND weekdays <@ ARRAY[1, 2, 3, 4, 5, 6, 7]::smallint[]),
	starts_on   date NOT NULL,
	ends_on     date NOT NULL,
	created_by  bigint REFERENCES public.profiles(id) ON DELETE SET NULL,
	created_at  timestamptz NOT NULL DEFAULT now(),
	updated_by  bigint REFERENCES public.profiles(id) ON DELETE SET NULL,
	updated_at  timestamptz,
	stopped_by  bigint REFERENCES public.profiles(id) ON DELETE SET NULL,
	stopped_at  timestamptz,
	CONSTRAINT child_routines_note_has_text CHECK (kind <> 'note' OR body IS NOT NULL),
	CONSTRAINT child_routines_structured_has_child CHECK (kind = 'note' OR child_id IS NOT NULL),
	CONSTRAINT child_routines_end_after_start
		CHECK (end_time IS NULL OR (start_time IS NOT NULL AND end_time > start_time))
);

CREATE INDEX IF NOT EXISTS child_routines_family_idx ON public.child_routines (family_id);
CREATE INDEX IF NOT EXISTS child_events_batch_idx
	ON public.child_events (batch_id) WHERE batch_id IS NOT NULL;

ALTER TABLE public.child_routines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS child_routines_family_read ON public.child_routines;
CREATE POLICY child_routines_family_read ON public.child_routines
	FOR SELECT TO authenticated
	USING (family_id = public.get_my_family_id());

REVOKE ALL ON public.child_routines FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.child_routines TO authenticated;
GRANT ALL ON public.child_routines TO service_role;


-- ── 2. A hand edit leaves the routine ────────────────────────────────────────
-- A re-apply replaces the routine's future events; an occurrence someone
-- changed on its own is theirs now, and must not be overwritten. A soft delete
-- (only deleted_*) keeps the batch, so the Histórico still folds it.

CREATE OR REPLACE FUNCTION public.child_event_leave_routine()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
	IF OLD.batch_id IS NOT NULL
	   AND NEW.batch_id IS NOT DISTINCT FROM OLD.batch_id
	   AND NEW.deleted_at IS NULL
	   AND (NEW.event_date, NEW.kind, NEW.child_id, NEW.start_time, NEW.end_time, NEW.body)
	       IS DISTINCT FROM
	       (OLD.event_date, OLD.kind, OLD.child_id, OLD.start_time, OLD.end_time, OLD.body) THEN
		NEW.batch_id := NULL;
	END IF;
	RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.child_event_leave_routine() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_child_event_leave_routine ON public.child_events;
CREATE TRIGGER trigger_child_event_leave_routine
	BEFORE UPDATE ON public.child_events
	FOR EACH ROW EXECUTE FUNCTION public.child_event_leave_routine();


-- ── 3. Where the plan ends ───────────────────────────────────────────────────
-- The last planned day of the family, inside the tier horizon (F-39: the same
-- keys `enforce_day_protection` reads). NULL = nothing planned from p_from on.

CREATE OR REPLACE FUNCTION public.agenda_plan_end(p_family_id bigint, p_from date)
RETURNS date
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	today   date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	months  int  := CASE WHEN public.is_premium(p_family_id)
	                     THEN public.setting_int('calendar_months_premium', 24)
	                     ELSE public.setting_int('calendar_months_free', 6) END;
	last_day date;
BEGIN
	SELECT max(schedule_date) INTO last_day
	FROM public.care_schedules
	WHERE family_id = p_family_id;

	last_day := LEAST(last_day, (today + make_interval(months => months))::date);
	IF last_day IS NULL OR last_day < p_from THEN
		RETURN NULL;
	END IF;
	RETURN last_day;
END;
$$;

ALTER FUNCTION public.agenda_plan_end(bigint, date) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.agenda_plan_end(bigint, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.agenda_plan_end(bigint, date) TO service_role;


-- ── 4. Save (create or re-apply) and stop ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.save_child_routine(
	p_routine_id uuid,
	p_from       date,
	p_kind       text,
	p_weekdays   smallint[],
	p_child_id   bigint DEFAULT NULL,
	p_start      time   DEFAULT NULL,
	p_end        time   DEFAULT NULL,
	p_body       text   DEFAULT NULL)
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
				 batch_id, created_by)
			VALUES (me.family_id, p_child_id, d, p_start, p_end, p_kind, v_body, r_id, me.id);
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
			 starts_on, ends_on, created_by)
		VALUES (r_id, me.family_id, p_child_id, p_kind, p_start, p_end, v_body, days,
		        p_from, until_d, me.id);
	ELSE
		UPDATE public.child_routines SET
			child_id   = p_child_id,
			kind       = p_kind,
			start_time = p_start,
			end_time   = p_end,
			body       = v_body,
			weekdays   = days,
			ends_on    = until_d,
			updated_by = me.id,
			updated_at = now()
		WHERE id = r.id;
	END IF;

	RETURN jsonb_build_object(
		'routine_id', r_id,
		'created',    made,
		'removed',    removed,
		'until',      until_d);
END;
$$;

ALTER FUNCTION public.save_child_routine(uuid, date, text, smallint[], bigint, time, time, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.save_child_routine(uuid, date, text, smallint[], bigint, time, time, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_child_routine(uuid, date, text, smallint[], bigint, time, time, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.stop_child_routine(p_routine_id uuid, p_from date)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me      public.profiles%ROWTYPE := public.agenda_writer_guard();
	today   date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	r       public.child_routines%ROWTYPE;
	removed int := 0;
BEGIN
	IF p_from IS NULL OR p_from < today THEN
		RAISE EXCEPTION 'A agenda aceita eventos de hoje em diante. Um dia que já passou é só leitura.'
			USING ERRCODE = 'check_violation';
	END IF;

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

	UPDATE public.child_events SET deleted_by = me.id, deleted_at = now()
	WHERE batch_id = r.id AND deleted_at IS NULL AND event_date >= p_from;
	GET DIAGNOSTICS removed = ROW_COUNT;

	UPDATE public.child_routines SET stopped_by = me.id, stopped_at = now()
	WHERE id = r.id;

	RETURN removed;
END;
$$;

ALTER FUNCTION public.stop_child_routine(uuid, date) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.stop_child_routine(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.stop_child_routine(uuid, date) TO authenticated, service_role;


-- ── 5. F-69: the routine in the operator report — counts only ────────────────
-- Recreated from 20260924110000 (F-55 PR 2) with two counts in `agenda`.
-- The weekly `agenda_events` now counts what a member wrote by hand: a
-- routine writes months of events in one call, and counts in `routines` /
-- `events_from_routine` instead.

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
