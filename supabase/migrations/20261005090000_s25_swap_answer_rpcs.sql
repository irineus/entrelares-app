-- =============================================================================
-- S-25 — answering a swap is ONE server transaction, and the target's
-- exemption is narrowed to the answer (fase 2 da auditoria T-103, 05/10/2026)
--
-- Until now the approver's PHONE ran the approval as four separate writes:
-- the day, the request's status, the notifications, the e-mail. Two people
-- answering at once (Mom approves, Dad cancels) could leave the day showing
-- the swap under a request that reads "cancelada"; a dropped connection
-- between the writes left a swapped day still frozen, or an approval nobody
-- was told about; and a batch ("Aprovar os N pedidos") could not be re-run
-- after a failure, because the items already done now failed.
--
--   * approve_swap_request / reject_swap_request / cancel_swap_request —
--     SECURITY DEFINER, the request locked FOR UPDATE, only an OPEN request
--     moves; a swap applies exactly the proposal, a revert restores the
--     pre-edit snapshot through the existing restore_pre_edit_state; the
--     notifications the client composed (core keeps the texts and their
--     mirrors) are inserted in the SAME transaction, filtered to the
--     request's family, to live members with an account and to the types of
--     that answer. Answering what is already in the asked state is a no-op
--     that says so (`changed: false`) — a retried batch completes; anything
--     else already resolved raises "já foi respondida".
--   * enforce_day_protection — recreated from its LATEST body
--     (20260928210000_f07_schedule_lanes.sql) with one block: while a request
--     is open, its target may write only the answer (swap_target_write_ok).
--     Android builds in Production keep working: they write exactly that.
--
-- enforce_swap_status_transition still decides WHO may move a request; the
-- RPCs run as definer, but that trigger and enforce_day_protection read
-- auth.uid(), which is still the caller.
-- =============================================================================

-- ── 1. What the target of an open request may write ─────────────────────────

CREATE OR REPLACE FUNCTION public.swap_target_write_ok(
	p_req public.swap_requests,
	p_op  text,
	p_old public.care_schedules,
	p_new public.care_schedules)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	snap jsonb;
BEGIN
	IF p_req.id IS NULL THEN
		RETURN false;
	END IF;

	IF p_req.status = 'pending' THEN
		-- The proposal: the real carer, and the proposed handoff — or the time
		-- already on the day (F-52's answer leaves it alone). Nothing else.
		RETURN p_op = 'UPDATE'
		   AND p_new.actual_parent_id IS NOT DISTINCT FROM p_req.proposed_actual_parent_id
		   AND (p_new.handoff_time IS NOT DISTINCT FROM p_req.proposed_handoff_time
		        OR p_new.handoff_time IS NOT DISTINCT FROM p_old.handoff_time)
		   AND p_new.scheduled_parent_id = p_old.scheduled_parent_id
		   AND p_new.schedule_date = p_old.schedule_date
		   AND p_new.notes IS NOT DISTINCT FROM p_old.notes;
	END IF;

	-- revert_pending: the restore restore_pre_edit_state (and every client's
	-- revertRestorePlan) performs — and only it.
	IF p_req.pre_edit_log_id IS NULL THEN
		RETURN p_op = 'UPDATE'
		   AND p_new.actual_parent_id IS NULL
		   AND p_new.scheduled_parent_id = p_old.scheduled_parent_id
		   AND p_new.handoff_time IS NOT DISTINCT FROM p_old.handoff_time
		   AND p_new.schedule_date = p_old.schedule_date
		   AND p_new.notes IS NOT DISTINCT FROM p_old.notes;
	END IF;

	SELECT old_data INTO snap FROM public.activity_logs WHERE id = p_req.pre_edit_log_id;
	IF snap IS NULL THEN
		-- The day was created by the swapped edit: restoring removes it.
		RETURN p_op = 'DELETE';
	END IF;

	RETURN p_op = 'UPDATE'
	   AND p_new.scheduled_parent_id
	       = COALESCE((snap->>'scheduled_parent_id')::bigint, p_old.scheduled_parent_id)
	   AND p_new.actual_parent_id IS NOT DISTINCT FROM (snap->>'actual_parent_id')::bigint
	   AND p_new.handoff_time IS NOT DISTINCT FROM (snap->>'handoff_time')::time
	   AND p_new.schedule_date = p_old.schedule_date
	   -- F-47: the observation comes back only when the requester asked.
	   AND (p_new.notes IS NOT DISTINCT FROM p_old.notes
	        OR p_new.notes IS NOT DISTINCT FROM snap->>'notes');
END;
$$;

ALTER FUNCTION public.swap_target_write_ok(public.swap_requests, text, public.care_schedules, public.care_schedules) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.swap_target_write_ok(public.swap_requests, text, public.care_schedules, public.care_schedules) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.swap_target_write_ok(public.swap_requests, text, public.care_schedules, public.care_schedules) TO service_role;

-- ── 2. enforce_day_protection — latest body + the narrowing ─────────────────

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
				RAISE EXCEPTION 'O calendário permite agendar no máximo % meses à frente.', horizon_months
					USING ERRCODE = 'check_violation';
			ELSE
				RAISE EXCEPTION 'O plano gratuito permite agendar até % meses à frente. Ative o Premium para planejar mais longe.', horizon_months
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


-- ── 3. The answers ──────────────────────────────────────────────────────────

-- Inserts the notifications the client composed for THIS answer. Only rows
-- addressed to a live member of the request's family with an account, and
-- only the types this answer writes, are kept — anything else is dropped
-- silently, never an error that would roll the answer back.
CREATE OR REPLACE FUNCTION public.insert_swap_answer_notifications(
	p_request_id    bigint,
	p_family_id     bigint,
	p_types         text[],
	p_notifications jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
	IF p_notifications IS NULL OR jsonb_typeof(p_notifications) <> 'array' THEN
		RETURN;
	END IF;

	INSERT INTO public.notifications (
		recipient_profile_id, type, title, message, params, swap_request_id, is_read, created_at)
	SELECT p.id, n->>'type', n->>'title', n->>'message',
	       CASE WHEN jsonb_typeof(n->'params') = 'object' THEN n->'params' ELSE NULL END,
	       p_request_id, false, timezone('utc', now())
	FROM jsonb_array_elements(p_notifications) AS n
	JOIN public.profiles p
	  ON p.id = CASE WHEN (n->>'recipient_profile_id') ~ '^[0-9]+$'
	                 THEN (n->>'recipient_profile_id')::bigint END
	WHERE p.family_id = p_family_id
	  AND p.left_at IS NULL
	  AND p.user_id IS NOT NULL
	  AND (n->>'type') = ANY (p_types)
	  AND COALESCE(btrim(n->>'title'), '') <> ''
	  AND COALESCE(btrim(n->>'message'), '') <> '';
END;
$$;

ALTER FUNCTION public.insert_swap_answer_notifications(bigint, bigint, text[], jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.insert_swap_answer_notifications(bigint, bigint, text[], jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.insert_swap_answer_notifications(bigint, bigint, text[], jsonb) TO service_role;

-- The caller and the locked request, with the refusals every answer shares.
CREATE OR REPLACE FUNCTION public.lock_swap_request_for_answer(p_id bigint)
RETURNS public.swap_requests
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me  public.profiles%ROWTYPE;
	req public.swap_requests%ROWTYPE;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid() AND left_at IS NULL;
	IF me.id IS NULL THEN
		RAISE EXCEPTION 'Sessão inválida. Entre novamente.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	SELECT * INTO req FROM public.swap_requests WHERE id = p_id FOR UPDATE;
	IF req.id IS NULL OR req.family_id IS DISTINCT FROM me.family_id THEN
		RAISE EXCEPTION 'Solicitação não encontrada.'
			USING ERRCODE = 'no_data_found';
	END IF;
	RETURN req;
END;
$$;

ALTER FUNCTION public.lock_swap_request_for_answer(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.lock_swap_request_for_answer(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lock_swap_request_for_answer(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.approve_swap_request(
	p_id            bigint,
	p_note          text  DEFAULT NULL,
	p_notifications jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	req  public.swap_requests%ROWTYPE := public.lock_swap_request_for_answer(p_id);
	me   bigint := (SELECT id FROM public.profiles WHERE user_id = auth.uid());
	note text   := NULLIF(btrim(p_note), '');
	done text;
BEGIN
	IF req.target_profile_id IS DISTINCT FROM me THEN
		RAISE EXCEPTION 'Só quem recebeu a solicitação pode respondê-la.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	-- A retry of an answer that already landed: nothing to do, nothing sent.
	IF req.status IN ('approved', 'revert_approved') THEN
		RETURN jsonb_build_object('status', req.status, 'changed', false);
	END IF;
	IF req.status NOT IN ('pending', 'revert_pending') THEN
		RAISE EXCEPTION 'Esta solicitação já foi respondida e não está mais pendente.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF req.status = 'pending' THEN
		-- Exactly the proposal, as the target — enforce_day_protection judges
		-- this write like any other (and lets exactly this one through).
		IF req.schedule_id IS NOT NULL THEN
			UPDATE public.care_schedules
			SET actual_parent_id = req.proposed_actual_parent_id,
			    handoff_time     = req.proposed_handoff_time
			WHERE id = req.schedule_id;
		END IF;
		done := 'approved';
	ELSE
		PERFORM public.restore_pre_edit_state(req.schedule_id, req.pre_edit_log_id, req.revert_notes);
		done := 'revert_approved';
	END IF;

	UPDATE public.swap_requests
	SET status = done, approval_note = note, resolved_by = 'user'
	WHERE id = req.id;

	PERFORM public.insert_swap_answer_notifications(req.id, req.family_id,
		CASE WHEN done = 'approved'
		     THEN ARRAY['swap_approved', 'swap_approved_self', 'swap_family_info']
		     ELSE ARRAY['revert_approved', 'revert_approved_self', 'swap_family_info'] END,
		p_notifications);

	RETURN jsonb_build_object('status', done, 'changed', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_swap_request(
	p_id            bigint,
	p_reason        text  DEFAULT NULL,
	p_notifications jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	req    public.swap_requests%ROWTYPE := public.lock_swap_request_for_answer(p_id);
	me     bigint := (SELECT id FROM public.profiles WHERE user_id = auth.uid());
	reason text   := NULLIF(btrim(p_reason), '');
	done   text;
BEGIN
	IF req.target_profile_id IS DISTINCT FROM me THEN
		RAISE EXCEPTION 'Só quem recebeu a solicitação pode respondê-la.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;
	IF req.status IN ('rejected', 'revert_rejected') THEN
		RETURN jsonb_build_object('status', req.status, 'changed', false);
	END IF;
	IF req.status NOT IN ('pending', 'revert_pending') THEN
		RAISE EXCEPTION 'Esta solicitação já foi respondida e não está mais pendente.'
			USING ERRCODE = 'check_violation';
	END IF;

	done := CASE WHEN req.status = 'pending' THEN 'rejected' ELSE 'revert_rejected' END;
	UPDATE public.swap_requests
	SET status = done, rejection_reason = reason, resolved_by = 'user'
	WHERE id = req.id;

	PERFORM public.insert_swap_answer_notifications(req.id, req.family_id,
		CASE WHEN done = 'rejected' THEN ARRAY['swap_rejected'] ELSE ARRAY['revert_rejected'] END,
		p_notifications);

	RETURN jsonb_build_object('status', done, 'changed', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_swap_request(
	p_id            bigint,
	p_notifications jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	req  public.swap_requests%ROWTYPE := public.lock_swap_request_for_answer(p_id);
	me   bigint := (SELECT id FROM public.profiles WHERE user_id = auth.uid());
	done text;
BEGIN
	IF req.requesting_profile_id IS DISTINCT FROM me THEN
		RAISE EXCEPTION 'Só quem fez a solicitação pode cancelá-la.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;
	IF req.status IN ('cancelled', 'revert_cancelled') THEN
		RETURN jsonb_build_object('status', req.status, 'changed', false);
	END IF;
	IF req.status NOT IN ('pending', 'revert_pending') THEN
		RAISE EXCEPTION 'Esta solicitação já foi respondida e não está mais pendente.'
			USING ERRCODE = 'check_violation';
	END IF;

	done := CASE WHEN req.status = 'pending' THEN 'cancelled' ELSE 'revert_cancelled' END;
	UPDATE public.swap_requests
	SET status = done, resolved_by = 'user'
	WHERE id = req.id;

	PERFORM public.insert_swap_answer_notifications(req.id, req.family_id,
		CASE WHEN done = 'cancelled' THEN ARRAY['swap_cancelled'] ELSE ARRAY['revert_cancelled'] END,
		p_notifications);

	RETURN jsonb_build_object('status', done, 'changed', true);
END;
$$;

ALTER FUNCTION public.approve_swap_request(bigint, text, jsonb) OWNER TO postgres;
ALTER FUNCTION public.reject_swap_request(bigint, text, jsonb) OWNER TO postgres;
ALTER FUNCTION public.cancel_swap_request(bigint, jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.approve_swap_request(bigint, text, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reject_swap_request(bigint, text, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_swap_request(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_swap_request(bigint, text, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reject_swap_request(bigint, text, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cancel_swap_request(bigint, jsonb) TO authenticated, service_role;
