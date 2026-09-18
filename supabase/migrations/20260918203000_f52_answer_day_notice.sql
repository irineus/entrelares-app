-- =============================================================================
-- F-52 (PR 2) — answering an aviso, and the only way the answer moves the day
--
-- Two answers, and the difference between them is the whole item:
--
--   * `helping`  — "vou ajudar agora". The calendar does not move. Whoever
--                  sent the aviso is told, with an optional line saying where
--                  the helper will be.
--   * `keeping`  — "vou ficar com a criança hoje". TODAY changes carer.
--
-- **`keeping` does not touch `actual_parent_id` on its own authority.** §2 of
-- the standing decisions forbids a second path around the swap workflow, and
-- the card's own invariant said an aviso never moves the calendar. What the
-- owner asked for (18/09/2026) is reachable without breaking either, because
-- `enforce_day_protection` already names the one actor who may apply a change
-- to a day: **the target of a pending request**. So this function walks the
-- ordinary workflow, in one transaction:
--
--   1. open a swap request — requester = the aviso's SENDER (whose day it is),
--      target = the answerer, proposed actual parent = the answerer. That is
--      scenario A, and it is inside F-28 by construction: the answerer is
--      proposing THEMSELVES on the sender's own day, never a third party on
--      somebody else's;
--   2. apply the day AS THAT TARGET — the trigger's `is_target` branch, the
--      same one the client's approve button goes through;
--   3. approve it.
--
-- Everything downstream therefore happens for free and unchanged: the day is
-- frozen while the request is open, `audit_care_schedule_changes` writes the
-- record with its F-61 authorship stamp, F-45 can trace the change back to the
-- request, T-27 re-evaluates tomorrow's handoff, and F-26 can revert it later.
-- No new way for a day to change hands exists after this migration.
--
-- **Consent is two-sided and DATED.** The sender asked, in writing, by sending
-- an aviso whose `request` is `keep` — which only the day's own carer can do,
-- and only with no stated estimate (PR 1). The answerer accepted. Both facts
-- are rows, in order, in append-only tables. That is what makes an
-- already-approved swap honest here and nowhere else.
--
-- **The race is decided by the database.** Two carers tapping "eu fico" in the
-- same second is the case, not the corner case. `day_notice_outcomes` has a
-- UNIQUE on `notice_id`, this whole function is ONE transaction, and the
-- outcome INSERT is the last thing it does — so the loser's swap, day update
-- and notifications all roll back with it. No compensating logic, because
-- there is nothing to compensate.
-- =============================================================================

-- ── 1. The outcomes a notice can now reach ───────────────────────────────────
-- PR 1 shipped the table accepting `cancelled` alone, on purpose: a value the
-- schema takes and no function can produce is a promise the product does not
-- keep, and a merge to `main` reaches real users.

ALTER TABLE public.day_notice_outcomes
	DROP CONSTRAINT IF EXISTS day_notice_outcomes_outcome_check;

ALTER TABLE public.day_notice_outcomes
	ADD CONSTRAINT day_notice_outcomes_outcome_check
	CHECK (outcome IN ('cancelled', 'helping', 'keeping'));

COMMENT ON COLUMN public.day_notice_outcomes.outcome IS
	'F-52: cancelled (the sender withdrew it) · helping (somebody helps, the calendar does not move) · keeping (somebody takes today, through the approved swap in swap_request_id).';

-- ── 2. answer_day_notice ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.answer_day_notice(
	p_notice_id bigint,
	p_outcome   text,
	p_note      text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me          public.profiles%ROWTYPE;
	notice      public.day_notices%ROWTYPE;
	day_row     public.care_schedules%ROWTYPE;
	sender_name text;
	today       date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	note        text := nullif(btrim(p_note), '');
	swap_id     bigint;
	pre_edit    bigint;
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
		SELECT * INTO day_row FROM public.care_schedules
		WHERE family_id = me.family_id AND schedule_date = notice.schedule_date;

		IF day_row.id IS NULL THEN
			RAISE EXCEPTION 'O dia de hoje não está planejado.'
				USING ERRCODE = 'check_violation';
		END IF;

		-- The offer is only good while the day is still the sender's. It may
		-- have moved since — an admin correction, another workflow — and taking
		-- it anyway would apply a consent nobody gave for THIS state.
		IF COALESCE(day_row.actual_parent_id, day_row.scheduled_parent_id)
		   IS DISTINCT FROM notice.sender_profile_id THEN
			RAISE EXCEPTION 'O dia de hoje já mudou de responsável; o aviso não vale mais.'
				USING ERRCODE = 'check_violation';
		END IF;

		-- F-26: the snapshot a later revert restores from — the newest audit row
		-- for this date, exactly as the client's own path picks it.
		SELECT id INTO pre_edit FROM public.activity_logs
		WHERE affected_date = notice.schedule_date AND family_id = me.family_id
		ORDER BY id DESC LIMIT 1;

		-- Step 1 — the request. Scenario A: the sender (whose day it is) asks,
		-- and the person proposed as the real carer is the answerer.
		-- `swap_requests_one_pending_per_date` is what refuses this when the day
		-- already has an open request, and that refusal is correct: a frozen day
		-- is frozen for this too.
		INSERT INTO public.swap_requests (
			schedule_date, schedule_id, requesting_profile_id, target_profile_id,
			previous_actual_parent_id, proposed_actual_parent_id,
			proposed_handoff_time, status, pre_edit_log_id, created_at, updated_at)
		VALUES (
			notice.schedule_date, day_row.id, notice.sender_profile_id, me.id,
			day_row.actual_parent_id, me.id,
			-- No handoff is proposed: the T-27 triggers re-evaluate the
			-- transitions of this day and D+1 once the change lands.
			NULL, 'pending', pre_edit, now(), now())
		RETURNING id INTO swap_id;

		-- Step 2 — apply it AS THE TARGET. `enforce_day_protection` lets this
		-- through on the `is_target` branch and on no other: the same door the
		-- approve button uses, and the reason no second path exists.
		UPDATE public.care_schedules
		SET actual_parent_id = me.id,
		    updated_at       = timezone('utc', now())
		WHERE id = day_row.id;

		-- Step 3 — close it. `resolved_by = 'user'`: a person decided this, not
		-- the F-24 clock.
		UPDATE public.swap_requests
		SET status = 'approved', resolved_at = now(), updated_at = now(),
		    resolved_by = 'user'
		WHERE id = swap_id;
	END IF;

	-- The outcome is written LAST, so the UNIQUE on notice_id is what decides a
	-- race — and the loser's swap and day update roll back with it, because a
	-- plpgsql function is one transaction.
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
$$;

ALTER FUNCTION public.answer_day_notice(bigint, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.answer_day_notice(bigint, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.answer_day_notice(bigint, text, text) TO authenticated;
GRANT ALL    ON FUNCTION public.answer_day_notice(bigint, text, text) TO service_role;
