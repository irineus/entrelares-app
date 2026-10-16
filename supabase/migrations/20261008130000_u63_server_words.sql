-- U-63 — the words the SERVER says, in the app's vocabulary (owner, 07/10/2026).
--
--   · The auto-approval reminder's stored sentence says the deadline the way a
--     person says it — "até sábado, 10/10, à 0h" — instead of "em 10/10/2026
--     às 00:00", a timestamp whose midnight belongs to no day.
--     `pt_deadline_words` is the PT-BR twin of Dart's `formatDeadline` (core
--     `date_formats.dart`); `params.deadline` is unchanged, so every reader's
--     device rebuilds the sentence in its own language.
--   · "agendar" → "planejar" in the planning-horizon refusals
--     (`enforce_day_protection`; U-34 keeps "planejado", U-63 drops
--     "agendamento"/"agendar").
--   · "horário de troca" → "horário de entrega" in `set_handoff_time_range`'s
--     refusals: the handoff is an "entrega"; "troca" is a swap.
--
-- Each function body is copied VERBATIM from its live definition — 20260916150000_u31_notification_titles_no_emoji.sql,
-- 20261005090000_s25_swap_answer_rpcs.sql, 20260928210000_f07_schedule_lanes.sql — with only those literals changed; CREATE OR REPLACE
-- keeps owner and grants.

CREATE OR REPLACE FUNCTION public.pt_deadline_words(p_at timestamp)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $$
	SELECT (ARRAY['segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira',
	              'sexta-feira', 'sábado', 'domingo'])[extract(isodow FROM p_at)::int]
	    || ', ' || to_char(p_at, 'DD/MM') || ', '
	    || CASE WHEN extract(hour FROM p_at) <= 1 THEN 'à ' ELSE 'às ' END
	    || extract(hour FROM p_at)::int::text || 'h'
	    || CASE WHEN extract(minute FROM p_at) = 0 THEN '' ELSE to_char(p_at, 'MI') END
$$;

ALTER FUNCTION public.pt_deadline_words(timestamp) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.pt_deadline_words(timestamp) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.pt_deadline_words(timestamp) IS
	'U-63: a São Paulo wall-clock instant as a PT-BR deadline — "sábado, 10/10, à 0h", "domingo, 11/10, às 18h30". Twin of Dart formatDeadline.';


CREATE OR REPLACE FUNCTION public.auto_approve_expired(p_env_prefix text DEFAULT '')
RETURNS TABLE (swap_request_id bigint, email_type text)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    rec           record;
    tz            constant text := 'America/Sao_Paulo';
    expiry        timestamptz;
    d             text;
    d_iso         text;   -- U-24: ISO for params; `d` stays PT-BR in the stored sentence
    deadline      timestamptz;  -- F-60: expiry + 48 h, the instant the request stops waiting
    deadline_iso  text;   -- `YYYY-MM-DDTHH:MM` wall clock of America/Sao_Paulo, for params
    deadline_d    text;   -- PT-BR day for the STORED sentence
    deadline_t    text;   -- PT-BR hour for the STORED sentence
    proposed_name text;
    fanout_msg    text;
    fanout_kind   text;
BEGIN
    -- ── 24h reminders: expired between 24h and 48h ago, not yet reminded ──
    FOR rec IN
        SELECT * FROM public.swap_requests
        WHERE status IN ('pending', 'revert_pending') AND reminder_sent_at IS NULL
    LOOP
        expiry := (rec.schedule_date + COALESCE(rec.proposed_handoff_time, '00:00'::time)) AT TIME ZONE tz;
        IF now() >= expiry + interval '24 hours' AND now() < expiry + interval '48 hours' THEN
            d := to_char(rec.schedule_date, 'DD/MM');
            d_iso := to_char(rec.schedule_date, 'YYYY-MM-DD');
            -- F-60: the notice promises the deadline the request ACTUALLY has.
            -- The anchor is unchanged (the DAY, not the request); what changes
            -- is that the sentence states the instant instead of a window it
            -- never measured. `deadline_iso` is a wall clock, so the reader's
            -- device formats it without having to know our timezone.
            deadline := expiry + interval '48 hours';
            deadline_iso := to_char(deadline AT TIME ZONE tz, 'YYYY-MM-DD"T"HH24:MI');
            deadline_d := public.pt_deadline_words(deadline AT TIME ZONE tz);
            deadline_t := to_char(deadline AT TIME ZONE tz, 'HH24:MI');
            INSERT INTO public.notifications (recipient_profile_id, type, title, message, params, swap_request_id, is_read, created_at)
            VALUES (
                rec.target_profile_id,
                'auto_reminder',
                p_env_prefix || 'Solicitação pendente aguardando resposta',
                'A solicitação do dia ' || d || ' será aprovada automaticamente se não houver resposta até '
                    || deadline_d || '.',
                jsonb_build_object('date', d_iso, 'deadline', deadline_iso),
                rec.id, false, now()
            );
            UPDATE public.swap_requests SET reminder_sent_at = now() WHERE id = rec.id;

            swap_request_id := rec.id; email_type := 'reminder'; RETURN NEXT;
        END IF;
    END LOOP;

    -- ── Auto-approve: expired more than 48h ago ──────────────────────────
    FOR rec IN
        SELECT * FROM public.swap_requests
        WHERE status IN ('pending', 'revert_pending')
    LOOP
        expiry := (rec.schedule_date + COALESCE(rec.proposed_handoff_time, '00:00'::time)) AT TIME ZONE tz;
        IF now() >= expiry + interval '48 hours' THEN
            d := to_char(rec.schedule_date, 'DD/MM');
            d_iso := to_char(rec.schedule_date, 'YYYY-MM-DD');

            -- The person the day lands on: the proposed parent (for a revert
            -- request that is the restored planned responsible).
            SELECT full_name INTO proposed_name
            FROM public.profiles WHERE id = rec.proposed_actual_parent_id;

            IF rec.status = 'pending' THEN
                IF rec.schedule_id IS NOT NULL THEN
                    UPDATE public.care_schedules
                    SET actual_parent_id = rec.proposed_actual_parent_id,
                        handoff_time     = rec.proposed_handoff_time,
                        updated_at       = timezone('utc', now())
                    WHERE id = rec.schedule_id;
                END IF;
                UPDATE public.swap_requests SET status = 'approved', resolved_by = 'system' WHERE id = rec.id;

                fanout_msg := COALESCE(proposed_name, 'Outro responsável')
                    || ' ficará com a criança no dia ' || d
                    || ' (troca aprovada automaticamente por falta de resposta).';
                fanout_kind := 'auto_swap';
            ELSE
                -- F-47: the requester's decision about the day observation.
                PERFORM public.restore_pre_edit_state(rec.schedule_id, rec.pre_edit_log_id, rec.revert_notes);
                UPDATE public.swap_requests SET status = 'revert_approved', resolved_by = 'system' WHERE id = rec.id;

                fanout_msg := 'A troca do dia ' || d || ' foi revertida automaticamente — '
                    || COALESCE(proposed_name, 'o responsável planejado')
                    || ' volta a ficar com a criança.';
                fanout_kind := 'auto_revert';
            END IF;

            -- Notify the requester and the approver (distinct copy).
            -- U-13: same `type`, two different wordings — so `role` is the
            -- discriminator the renderer branches on. Without it the reader
            -- would get the other party's sentence.
            INSERT INTO public.notifications (recipient_profile_id, type, title, message, params, swap_request_id, is_read, created_at)
            VALUES (
                rec.requesting_profile_id, 'auto_approved',
                p_env_prefix || 'Solicitação aprovada automaticamente',
                'A solicitação do dia ' || d || ' foi aprovada automaticamente por falta de resposta.',
                jsonb_build_object('date', d_iso, 'role', 'requester'),
                rec.id, false, now()
            );
            INSERT INTO public.notifications (recipient_profile_id, type, title, message, params, swap_request_id, is_read, created_at)
            VALUES (
                rec.target_profile_id, 'auto_approved',
                p_env_prefix || 'Solicitação aprovada automaticamente',
                'A solicitação do dia ' || d || ' foi aprovada automaticamente. Você não respondeu dentro do prazo.',
                jsonb_build_object('date', d_iso, 'role', 'approver'),
                rec.id, false, now()
            );

            -- F-28: family-info fan-out to uninvolved caregivers.
            -- U-13: `name` is USER DATA (a caregiver's own name) and is passed
            -- through untranslated, exactly like the role catalogue's custom
            -- roles. `kind` tells the renderer swap from revert.
            -- F-56: only caregivers with an account — a pending member has no
            -- session to read it in, and a departed one is out.
            INSERT INTO public.notifications (recipient_profile_id, type, title, message, params, swap_request_id, is_read, created_at)
            SELECT p.id, 'swap_family_info',
                   p_env_prefix || 'Calendário atualizado',
                   fanout_msg,
                   jsonb_build_object('date', d_iso, 'kind', fanout_kind, 'name', proposed_name),
                   rec.id, false, now()
            FROM public.profiles p
            WHERE p.family_id = rec.family_id
              AND p.left_at IS NULL AND p.user_id IS NOT NULL
              AND p.id NOT IN (rec.requesting_profile_id, rec.target_profile_id);

            swap_request_id := rec.id; email_type := 'auto_approved'; RETURN NEXT;
        END IF;
    END LOOP;
END;
$$;


CREATE OR REPLACE FUNCTION public.enforce_day_protection()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
	cur_profile_id bigint;
	cur_is_admin   boolean := false;
	today          date;
	the_date       date;
	fam            bigint;
	lane           bigint;
	is_frozen      boolean := false;
	is_target      boolean := false;
	target_req     public.swap_requests%ROWTYPE;
	horizon_months int;
BEGIN
	-- T-45: internal cascade of the handoff transition rule (sync_next_day_handoff).
	IF current_setting('app.handoff_cascade', true) = 'on' THEN
		RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
	END IF;

	-- S-11: controlled erasure cleanup — see 20260719120000.
	IF current_setting('app.deletion_context', true) = 'on' THEN
		RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
	END IF;

	-- F-07: the plan-mode switch (`set_schedule_mode`, PR 3) moves the plan
	-- from today on between lanes as ONE admin act — an approved swap's day
	-- is copied with its real parent, which a direct write could never do.
	-- The RPC has already checked the flag, the admin, and that no request is
	-- pending from today on; a client cannot set a GUC through PostgREST.
	IF current_setting('app.schedule_mode_switch', true) = 'on' THEN
		RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
	END IF;

	-- System context (service_role: F-24 auto-approval, migrations): unrestricted.
	SELECT id, is_admin INTO cur_profile_id, cur_is_admin
	FROM public.profiles WHERE user_id = auth.uid();
	IF cur_profile_id IS NULL THEN
		RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
	END IF;

	-- S-11: a departed member (left_at set) cannot be NEWLY assigned to a day,
	-- as the planned or the real parent. Past history keeps their name — only a
	-- CHANGE that puts a departed member on a day is blocked.
	IF TG_OP IN ('INSERT', 'UPDATE') THEN
		IF (TG_OP = 'INSERT' OR NEW.scheduled_parent_id IS DISTINCT FROM OLD.scheduled_parent_id)
		   AND EXISTS (SELECT 1 FROM public.profiles
		               WHERE id = NEW.scheduled_parent_id AND left_at IS NOT NULL) THEN
			RAISE EXCEPTION 'Não é possível atribuir dias a um responsável que saiu da família.'
				USING ERRCODE = 'check_violation';
		END IF;
		IF NEW.actual_parent_id IS NOT NULL
		   AND (TG_OP = 'INSERT' OR NEW.actual_parent_id IS DISTINCT FROM OLD.actual_parent_id)
		   AND EXISTS (SELECT 1 FROM public.profiles
		               WHERE id = NEW.actual_parent_id AND left_at IS NOT NULL) THEN
			RAISE EXCEPTION 'Não é possível atribuir dias a um responsável que saiu da família.'
				USING ERRCODE = 'check_violation';
		END IF;
	END IF;

	today    := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	the_date := COALESCE(NEW.schedule_date, OLD.schedule_date);
	-- F-07: the lane is immutable (enforce_schedule_lane), so NEW and OLD agree.
	lane     := CASE WHEN TG_OP = 'DELETE' THEN OLD.child_id ELSE NEW.child_id END;
	fam      := COALESCE(NEW.family_id, OLD.family_id,
	                     (SELECT family_id FROM public.profiles WHERE id = NEW.scheduled_parent_id));

	-- F-39 (T-41: horizons from app_settings). Free plans up to N months ahead;
	-- premium up to M, the hard ceiling for all (not admin-bypassable). Grandfather:
	-- only NEW far-future writes are blocked.
	IF the_date > today
	   AND (TG_OP = 'INSERT'
	        OR (TG_OP = 'UPDATE' AND NEW.schedule_date IS DISTINCT FROM OLD.schedule_date)) THEN
		horizon_months := CASE WHEN public.is_premium(fam)
		                       THEN public.setting_int('calendar_months_premium', 24)
		                       ELSE public.setting_int('calendar_months_free', 6) END;
		IF the_date > (today + make_interval(months => horizon_months))::date THEN
			IF public.is_premium(fam) THEN
				RAISE EXCEPTION 'O calendário permite planejar no máximo % meses à frente.', horizon_months
					USING ERRCODE = 'check_violation';
			ELSE
				RAISE EXCEPTION 'O plano gratuito permite planejar até % meses à frente. Ative o Premium para planejar mais longe.', horizon_months
					USING ERRCODE = 'check_violation';
			END IF;
		END IF;
	END IF;

	SELECT bool_or(true), bool_or(target_profile_id = cur_profile_id)
	INTO is_frozen, is_target
	FROM public.swap_requests
	WHERE family_id = fam AND schedule_date = the_date
	  AND child_id IS NOT DISTINCT FROM lane
	  AND status IN ('pending', 'revert_pending');
	is_frozen := COALESCE(is_frozen, false);
	is_target := COALESCE(is_target, false);

	-- S-25: the target's exemption covers the ANSWER and nothing else. While a
	-- request is open, its target may write exactly what the request asks —
	-- the proposed real carer (and the proposed handoff, or the time already
	-- there) for a swap, the pre-edit snapshot for a revert — and no other
	-- field, and may not delete unless the revert restores "no day". Before
	-- this, being the target opened S-09, the past-day rule and the delete
	-- rules wholesale: through the API the approver could write ANY real
	-- carer, change the planned one or delete the day. The answer RPCs write
	-- exactly the allowed shape, and so does every Android build in the field
	-- (it applied `proposed_actual_parent_id` / `proposed_handoff_time` and
	-- nothing else), so neither stops working.
	IF is_target AND TG_OP IN ('UPDATE', 'DELETE') THEN
		SELECT * INTO target_req
		FROM public.swap_requests
		WHERE family_id = fam AND schedule_date = the_date
		  AND child_id IS NOT DISTINCT FROM lane
		  AND status IN ('pending', 'revert_pending')
		  AND target_profile_id = cur_profile_id
		ORDER BY id DESC
		LIMIT 1;
		IF NOT public.swap_target_write_ok(target_req, TG_OP, OLD,
		       CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE NEW END) THEN
			RAISE EXCEPTION 'Enquanto este dia tem uma solicitação pendente, quem a responde só pode aplicar o que foi pedido.'
				USING ERRCODE = 'check_violation';
		END IF;
	END IF;

	-- F-12: frozen days are untouchable, except by the pending request's target
	-- (who legitimately applies the calendar change while approving) or an admin.
	-- (F-40: frozen override stays a free Gestor power — not retroactive.)
	IF TG_OP IN ('UPDATE', 'DELETE') AND is_frozen AND NOT is_target AND NOT cur_is_admin THEN
		RAISE EXCEPTION 'Este dia tem uma solicitação pendente e não pode ser alterado.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- F-13 + F-40: past days are immutable, except the pending request's target
	-- (overdue workflow completion). Admin OVERRIDE of a past day is the
	-- Administrador (Premium) power: a free admin (Gestor) may fix only the last
	-- `override_free_days`; premium reaches back `override_premium_months`, which is
	-- the hard retroactive cap for everyone (beyond it, blocked even for premium).
	IF the_date < today AND NOT is_target THEN
		IF NOT cur_is_admin THEN
			RAISE EXCEPTION 'Dias passados não podem ser alterados.'
				USING ERRCODE = 'check_violation';
		ELSIF public.is_premium(fam) THEN
			IF the_date < (today - make_interval(months => public.setting_int('override_premium_months', 6)))::date THEN
				RAISE EXCEPTION 'Correções retroativas vão até % meses atrás.', public.setting_int('override_premium_months', 6)
					USING ERRCODE = 'check_violation';
			END IF;
		ELSE   -- free admin (Gestor): only the honest-fix window
			IF the_date < (today - make_interval(days => public.setting_int('override_free_days', 7)))::date THEN
				RAISE EXCEPTION 'O plano gratuito corrige apenas os últimos % dias. Ative o Premium para corrigir dias mais antigos (até % meses).',
					public.setting_int('override_free_days', 7), public.setting_int('override_premium_months', 6)
					USING ERRCODE = 'check_violation';
			END IF;
		END IF;
	END IF;

	-- S-09: the PLANNED schedule is immutable for regular users — changing the
	-- scheduled parent of an assigned day requires an admin (explicit, audited)
	-- or the pending revert's target restoring the pre-edit snapshot (F-26).
	-- (F-40: changing a FUTURE planned parent stays a free Gestor power; a PAST one
	-- is already gated by the tier-aware past-day check above.)
	IF TG_OP = 'UPDATE'
	   AND NEW.scheduled_parent_id IS DISTINCT FROM OLD.scheduled_parent_id
	   AND NOT cur_is_admin AND NOT is_target THEN
		RAISE EXCEPTION 'O responsável planejado só pode ser alterado por administradores; para mudar quem fica com a criança, use o fluxo de troca.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF TG_OP = 'DELETE' THEN
		-- F-12: a day with an approved swap cannot be deleted (admin may — F-14).
		IF OLD.actual_parent_id IS NOT NULL AND OLD.actual_parent_id <> OLD.scheduled_parent_id
		   AND NOT cur_is_admin AND NOT is_target THEN
			RAISE EXCEPTION 'Dias com troca aprovada não podem ser apagados.'
				USING ERRCODE = 'check_violation';
		END IF;
		-- QA (July 2026): clearing an assigned day is admin-only — otherwise a
		-- regular member deletes + recreates the day with anyone, bypassing the
		-- S-09 planned-parent rule. The workflow target keeps its exemption.
		IF NOT cur_is_admin AND NOT is_target THEN
			RAISE EXCEPTION 'Um dia já planejado só pode ser limpo por um administrador.'
				USING ERRCODE = 'check_violation';
		END IF;
		RETURN OLD;
	END IF;

	-- Swap-workflow enforcement (applies to admins too — F-14 decision):
	-- creating or undoing a swap directly is forbidden; only the pending
	-- request's target (applying an approval) may write such a change.
	-- Exception: admins may correct the actual parent of PAST days (historical
	-- fixes — the workflow cannot exist for past dates), never future ones. The
	-- retroactive reach was already tier-gated by the past-day check above.
	IF cur_is_admin AND the_date < today THEN
		RETURN NEW;
	END IF;

	IF TG_OP = 'INSERT' THEN
		IF NEW.actual_parent_id IS NOT NULL AND NEW.actual_parent_id <> NEW.scheduled_parent_id THEN
			RAISE EXCEPTION 'Alterações do responsável real devem passar pelo fluxo de aprovação.'
				USING ERRCODE = 'check_violation';
		END IF;
	ELSIF NEW.actual_parent_id IS DISTINCT FROM OLD.actual_parent_id AND NOT is_target THEN
		IF (OLD.actual_parent_id IS NOT NULL AND OLD.actual_parent_id <> OLD.scheduled_parent_id)  -- undo/alter an approved swap
		   OR (NEW.actual_parent_id IS NOT NULL AND NEW.actual_parent_id <> NEW.scheduled_parent_id) -- create a swap directly
		THEN
			RAISE EXCEPTION 'Alterações do responsável real devem passar pelo fluxo de aprovação.'
				USING ERRCODE = 'check_violation';
		END IF;
	END IF;

	RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.set_handoff_time_range(p_from date, p_to date, p_time time without time zone, p_child_id bigint DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
	me             public.profiles%ROWTYPE;
	today          date;
	v_from         date;
	batch          uuid;
	updated        integer := 0;
	kept_frozen    integer := 0;
	kept_existing  integer := 0;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();
	IF me.id IS NULL THEN
		RAISE EXCEPTION 'Perfil não encontrado.' USING ERRCODE = 'check_violation';
	END IF;
	-- Refused before any row is read, even over an empty range: a silent
	-- "0 updated" would read as permission.
	IF NOT me.is_admin THEN
		RAISE EXCEPTION 'Só um administrador define o horário de entrega de vários dias de uma vez.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF p_time IS NULL THEN
		RAISE EXCEPTION 'Informe o horário de entrega.' USING ERRCODE = 'check_violation';
	END IF;
	IF p_from IS NULL OR (p_to IS NOT NULL AND p_to < p_from) THEN
		RAISE EXCEPTION 'Intervalo de datas inválido.' USING ERRCODE = 'check_violation';
	END IF;

	today  := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	v_from := GREATEST(p_from, today);
	IF p_to IS NOT NULL AND v_from > p_to THEN
		RETURN jsonb_build_object('updated', 0, 'kept_frozen', 0, 'kept_existing', 0);
	END IF;

	-- What the UPDATE below will leave alone, counted over the same rows it
	-- sees. A transition day that already has a time counts as existing even
	-- when it is also frozen — it would not be written either way.
	SELECT
		COUNT(*) FILTER (WHERE handoff_time IS NOT NULL),
		COUNT(*) FILTER (WHERE handoff_time IS NULL AND frozen)
	INTO kept_existing, kept_frozen
	FROM (
		SELECT
			d.handoff_time,
			EXISTS (SELECT 1 FROM public.swap_requests s
			        WHERE s.family_id = d.family_id AND s.schedule_date = d.schedule_date
			          AND s.child_id IS NOT DISTINCT FROM d.child_id
			          AND s.status IN ('pending', 'revert_pending')) AS frozen
		FROM public.care_schedules d
		LEFT JOIN public.care_schedules p
		       ON p.family_id = d.family_id AND p.schedule_date = d.schedule_date - 1
		      AND p.child_id IS NOT DISTINCT FROM d.child_id
		WHERE d.family_id = me.family_id
		  AND (p_child_id IS NULL OR d.child_id = p_child_id)
		  AND d.schedule_date >= v_from
		  AND (p_to IS NULL OR d.schedule_date <= p_to)
		  -- T-27, the trigger's own test: no D-1 row, or a different effective.
		  AND (p.id IS NULL
		       OR COALESCE(p.actual_parent_id, p.scheduled_parent_id)
		          IS DISTINCT FROM COALESCE(d.actual_parent_id, d.scheduled_parent_id))
	) k;

	batch := gen_random_uuid();
	PERFORM set_config('app.schedule_batch', batch::text, true);
	PERFORM set_config('app.schedule_batch_kind', 'handoff_range', true);

	UPDATE public.care_schedules d
	SET handoff_time    = p_time,
	    submitted_token = d.revision_token
	WHERE d.family_id = me.family_id
	  AND (p_child_id IS NULL OR d.child_id = p_child_id)
	  AND d.schedule_date >= v_from
	  AND (p_to IS NULL OR d.schedule_date <= p_to)
	  AND d.handoff_time IS NULL
	  AND NOT EXISTS (SELECT 1 FROM public.swap_requests s
	                  WHERE s.family_id = d.family_id AND s.schedule_date = d.schedule_date
	                    AND s.child_id IS NOT DISTINCT FROM d.child_id
	                    AND s.status IN ('pending', 'revert_pending'))
	  AND NOT EXISTS (SELECT 1 FROM public.care_schedules p
	                  WHERE p.family_id = d.family_id
	                    AND p.child_id IS NOT DISTINCT FROM d.child_id
	                    AND p.schedule_date = d.schedule_date - 1
	                    AND COALESCE(p.actual_parent_id, p.scheduled_parent_id)
	                        IS NOT DISTINCT FROM COALESCE(d.actual_parent_id, d.scheduled_parent_id));
	GET DIAGNOSTICS updated = ROW_COUNT;

	PERFORM set_config('app.schedule_batch', '', true);
	PERFORM set_config('app.schedule_batch_kind', '', true);

	RETURN jsonb_build_object(
		'updated',       updated,
		'kept_frozen',   kept_frozen,
		'kept_existing', kept_existing,
		'batch_id',      batch);
END;
$function$;
