-- =============================================================================
-- F-07 (PR 3) — switching the plan between "one for the family" and "one per
-- child"
--
-- `set_schedule_mode(p_mode, p_base_child_id)` is the ONLY writer of
-- `families.schedule_mode`. It moves the plan FROM TODAY ON as one admin act;
-- the past is immutable and keeps the lane it was written in.
--
--   · single → per_child: every day from today on is copied into each child's
--     lane (same planned carer, same real carer, same handoff time), and the
--     family row of that day goes. At least two children are needed.
--   · per_child → single: the admin names the child whose plan becomes the
--     family's (`p_base_child_id`); that lane is copied into the family lane
--     and every child lane from today on goes.
--
-- Decisions (engineering, recorded on the card, 28/09/2026):
--   · A pending request from today on REFUSES the switch: it freezes one day
--     of one lane, and moving that day would strand the request.
--   · An APPROVED swap from today on is a fact, so its real carer is copied
--     into every lane. The request becomes history (its `schedule_id` goes NULL
--     with the row, as on any cleared day); undoing it is now per child.
--   · The day note travels only while `feature.child_agenda` is off — with the
--     agenda on, the observation is frozen and lives in the agenda (F-55).
--   · The writes carry `app.schedule_mode_switch` (the day protections step
--     aside, as for T-45's cascade) and ONE batch id, kind `mode_switch`, so
--     the Histórico folds the switch into one entry (F-51's shape).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_schedule_mode(p_mode text, p_base_child_id bigint DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me       public.profiles%ROWTYPE;
	cur_mode text;
	today    date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	kids     int;
	src      public.care_schedules[];
	keep_notes boolean := NOT public.setting_bool('feature.child_agenda', false);
	batch    uuid := gen_random_uuid();
	written  int := 0;
BEGIN
	IF NOT public.setting_bool('feature.per_child_schedule', false) THEN
		RAISE EXCEPTION 'O plano por criança ainda não está disponível.'
			USING ERRCODE = 'feature_not_supported';
	END IF;

	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();
	IF me.id IS NULL OR me.left_at IS NOT NULL OR NOT me.is_admin THEN
		RAISE EXCEPTION 'Somente administradores da família podem mudar o modo do plano.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	IF p_mode IS NULL OR p_mode NOT IN ('single', 'per_child') THEN
		RAISE EXCEPTION 'Modo de plano inválido.' USING ERRCODE = 'check_violation';
	END IF;

	-- The family row is the lock: two admins switching at once serialize here.
	SELECT schedule_mode INTO cur_mode FROM public.families
	WHERE id = me.family_id FOR UPDATE;

	IF cur_mode = p_mode THEN
		RETURN jsonb_build_object('changed', false, 'mode', cur_mode, 'days', 0);
	END IF;

	IF EXISTS (SELECT 1 FROM public.swap_requests
	           WHERE family_id = me.family_id AND schedule_date >= today
	             AND status IN ('pending', 'revert_pending')) THEN
		RAISE EXCEPTION 'Há pedidos de troca pendentes a partir de hoje. Resolva-os antes de mudar o modo do plano.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF p_mode = 'per_child' THEN
		SELECT count(*)::int INTO kids FROM public.children WHERE family_id = me.family_id;
		IF kids < 2 THEN
			RAISE EXCEPTION 'Cadastre pelo menos duas crianças para ter um plano por criança.'
				USING ERRCODE = 'check_violation';
		END IF;
		src := ARRAY(SELECT c FROM public.care_schedules c
		             WHERE c.family_id = me.family_id AND c.child_id IS NULL
		               AND c.schedule_date >= today
		             ORDER BY c.schedule_date);
	ELSE
		IF p_base_child_id IS NULL OR NOT EXISTS (
			SELECT 1 FROM public.children WHERE id = p_base_child_id AND family_id = me.family_id) THEN
			RAISE EXCEPTION 'Escolha de qual criança vem o plano da família.'
				USING ERRCODE = 'check_violation';
		END IF;
		src := ARRAY(SELECT c FROM public.care_schedules c
		             WHERE c.family_id = me.family_id AND c.child_id = p_base_child_id
		               AND c.schedule_date >= today
		             ORDER BY c.schedule_date);
	END IF;

	PERFORM set_config('app.schedule_mode_switch', 'on', true);
	PERFORM set_config('app.schedule_batch', batch::text, true);
	PERFORM set_config('app.schedule_batch_kind', 'mode_switch', true);

	-- The mode first: the lane guard judges every insert below against it.
	UPDATE public.families SET schedule_mode = p_mode WHERE id = me.family_id;

	-- The old lanes go before the new ones arrive: one date, one mode.
	DELETE FROM public.care_schedules
	WHERE family_id = me.family_id AND schedule_date >= today
	  AND (CASE WHEN p_mode = 'per_child' THEN child_id IS NULL ELSE child_id IS NOT NULL END);

	IF p_mode = 'per_child' THEN
		INSERT INTO public.care_schedules
			(schedule_date, scheduled_parent_id, actual_parent_id, handoff_time, notes, child_id)
		SELECT s.schedule_date, s.scheduled_parent_id, s.actual_parent_id, s.handoff_time,
		       CASE WHEN keep_notes THEN s.notes END, ch.id
		FROM unnest(src) AS s
		CROSS JOIN public.children ch
		WHERE ch.family_id = me.family_id
		ORDER BY ch.sort_order, ch.id, s.schedule_date;
	ELSE
		INSERT INTO public.care_schedules
			(schedule_date, scheduled_parent_id, actual_parent_id, handoff_time, notes)
		SELECT s.schedule_date, s.scheduled_parent_id, s.actual_parent_id, s.handoff_time,
		       CASE WHEN keep_notes THEN s.notes END
		FROM unnest(src) AS s
		ORDER BY s.schedule_date;
	END IF;
	GET DIAGNOSTICS written = ROW_COUNT;

	PERFORM set_config('app.schedule_mode_switch', '', true);
	PERFORM set_config('app.schedule_batch', '', true);
	PERFORM set_config('app.schedule_batch_kind', '', true);

	RETURN jsonb_build_object(
		'changed',  true,
		'mode',     p_mode,
		'days',     coalesce(array_length(src, 1), 0),
		'written',  written,
		'batch_id', batch);
END;
$$;

ALTER FUNCTION public.set_schedule_mode(text, bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.set_schedule_mode(text, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_schedule_mode(text, bigint) TO authenticated, service_role;
