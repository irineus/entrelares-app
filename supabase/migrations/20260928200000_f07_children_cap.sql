-- =============================================================================
-- F-07 (PR 1) — more than one child per family; the second one is Premium
--
-- F-55 built `children` multi-child from day one, but v1 rendered one child and
-- `add_child` had no cap at all (the client hid the door after the first). This
-- migration is the server half of opening that door.
--
-- Decisions locked with the owner (28/09/2026):
--   · A free family keeps ONE child; the second one onwards needs Premium. The
--     numbers are keys born with T-80's metadata (T-84): `children.free_max`
--     (seed 1) and `children.max_per_family` (seed 6), `free ≤ max` judged by
--     the deferred cross-check.
--   · A downgrade takes nothing away: the children already registered, and
--     everything hanging off them, keep working. Only a NEW child is refused —
--     the same shape as the viewer caps (F-50).
--   · The custody plan stays ONE plan for the whole family here. The per-child
--     plan is F-07 PR 2 onwards, dark behind its own flag.
--
-- Nothing here touches care_schedules, the day protections or activity_logs.
-- =============================================================================

-- ── 1. The keys (T-84 catalogue) ─────────────────────────────────────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, min_value, max_value, help)
VALUES
	('children.free_max', '1', 'int', 'freemium',
	 'Crianças cadastradas numa família sem Premium (F-07).',
	 true, 'count', 'sensitive', 1, 10,
	 jsonb_build_object(
		'controls', 'Quantas crianças uma família gratuita pode cadastrar em Família → Crianças. A partir da seguinte, add_child pede Premium.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Mais crianças no gratuito; menos motivo para o Premium.',
		'if_decreased', 'Famílias acima do número novo NÃO perdem nenhuma criança; só um cadastro novo é recusado.',
		'takes_effect', 'Servidor no próximo cadastro; app na próxima abertura de Crianças.',
		'caveats', 'Precisa ser no máximo children.max_per_family (regra entre chaves).')),
	('children.max_per_family', '6', 'int', 'freemium',
	 'Teto de crianças por família, em qualquer plano (F-07).',
	 true, 'count', 'sensitive', 1, 10,
	 jsonb_build_object(
		'controls', 'O máximo de crianças que uma família cadastra, Premium inclusive.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Famílias maiores cabem; cada criança a mais é uma linha a mais na agenda, nas despesas e no seletor.',
		'if_decreased', 'Famílias acima do número novo NÃO perdem nenhuma criança; só um cadastro novo é recusado.',
		'takes_effect', 'Servidor no próximo cadastro; app na próxima abertura de Crianças.',
		'caveats', 'Precisa ser no mínimo children.free_max (regra entre chaves).'))
ON CONFLICT (key) DO NOTHING;


-- ── 2. add_child counts before it inserts ────────────────────────────────────
-- Body from 20260924100000 (F-55 PR 1) plus the two caps. The cap is checked
-- AFTER the duplicate-name check, so a typo'd repeat still reads as a repeat.

CREATE OR REPLACE FUNCTION public.add_child(p_first_name text)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me       public.profiles%ROWTYPE := public.child_admin_guard();
	v_name   text := public.child_normalize_name(p_first_name);
	free_max int  := public.setting_int('children.free_max', 1);
	cap      int  := public.setting_int('children.max_per_family', 6);
	taken    int;
	new_id   bigint;
BEGIN
	IF EXISTS (SELECT 1 FROM public.children
	           WHERE family_id = me.family_id AND lower(first_name) = lower(v_name)) THEN
		RAISE EXCEPTION 'Já existe uma criança com esse nome na família.'
			USING ERRCODE = 'check_violation';
	END IF;

	SELECT count(*)::int INTO taken FROM public.children WHERE family_id = me.family_id;

	IF taken >= cap THEN
		RAISE EXCEPTION 'Esta família já atingiu o limite de % crianças.', cap
			USING ERRCODE = 'check_violation';
	END IF;

	IF taken >= free_max AND NOT public.is_premium(me.family_id) THEN
		RAISE EXCEPTION 'O plano gratuito inclui % criança(s). Ative o Premium para cadastrar mais.', free_max
			USING ERRCODE = 'check_violation';
	END IF;

	INSERT INTO public.children (family_id, first_name, sort_order, created_by)
	VALUES (me.family_id, v_name,
	        COALESCE((SELECT max(sort_order) + 1 FROM public.children
	                  WHERE family_id = me.family_id), 0),
	        me.id)
	RETURNING id INTO new_id;

	RETURN new_id;
END;
$$;

ALTER FUNCTION public.add_child(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.add_child(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_child(text) TO authenticated, service_role;


-- ── 3. children.free_max ≤ children.max_per_family (T-80's DEFERRED check) ──
-- Body from 20260924140000 (F-50) plus the children rule.

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
	viewers_free     int := public.setting_int('free_viewers', 1);
	viewers_max      int := public.setting_int('max_viewers', 4);
	children_free    int := public.setting_int('children.free_max', 1);
	children_max     int := public.setting_int('children.max_per_family', 6);
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

	IF viewers_free > viewers_max THEN
		RAISE EXCEPTION 'free_viewers (%) precisa ser no máximo max_viewers (%): o gratuito não inclui mais visualizadores que o teto.', viewers_free, viewers_max
			USING ERRCODE = 'check_violation';
	END IF;

	-- F-07: the free plan never registers more children than any family may.
	IF children_free > children_max THEN
		RAISE EXCEPTION 'children.free_max (%) precisa ser no máximo children.max_per_family (%): o gratuito não inclui mais crianças que o teto.', children_free, children_max
			USING ERRCODE = 'check_violation';
	END IF;
END;
$$;
