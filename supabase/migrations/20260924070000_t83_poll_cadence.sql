-- =============================================================================
-- T-83 (2/4) — the safety-poll cadence becomes two operator parameters
--
-- F-23 kept a poll beside the native Realtime socket: 25 s while the socket is
-- down (the only fresh-data path), 120 s while it is up (a safety net). The code
-- called removing it "a future board decision"; it is now a console decision:
--   sync.poll_seconds_degraded  25   10–120 s
--   sync.poll_seconds_healthy  120   0–600 s, 0 = no poll while the socket is up
-- (owner, 23-24/09/2026), plus one rule between them, added to
-- `app_settings_cross_check` (recreated from its only definition, T-80): the
-- healthy poll is off or never more frequent than the degraded one.
-- Every open client polls at this cadence — the help says what that costs.
-- =============================================================================

-- ── The rule between the two keys ────────────────────────────────────────────

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
END;
$$;

ALTER FUNCTION public.app_settings_cross_check() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.app_settings_cross_check() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.app_settings_cross_check() TO service_role;

-- ── The keys ─────────────────────────────────────────────────────────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, min_value, max_value, help)
VALUES
	('sync.poll_seconds_degraded', '25', 'int', 'sync',
	 'Segundos entre as buscas do calendário quando a conexão em tempo real caiu.',
	 true, 'seconds', 'sensitive', 10, 120,
	 jsonb_build_object(
		'controls', 'O intervalo do poll de segurança (F-23) enquanto o socket do Realtime está fora — é o único caminho de dado novo para quem está com o calendário aberto.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Com o socket fora, uma troca aprovada demora mais para aparecer na tela do outro — menos consultas ao banco.',
		'if_decreased', 'Dado novo chega mais rápido sem socket, mas CADA aparelho com o calendário aberto consulta o banco com essa frequência.',
		'takes_effect', 'Na próxima abertura do calendário.',
		'caveats', 'Mínimo 10 s: abaixo disso o custo por aparelho aberto cresce sem ganho visível.')),
	('sync.poll_seconds_healthy', '120', 'int', 'sync',
	 'Segundos entre as buscas do calendário com a conexão em tempo real de pé (0 = desligado).',
	 true, 'seconds', 'sensitive', 0, 600,
	 jsonb_build_object(
		'controls', 'O poll de segurança (F-23) enquanto o socket do Realtime está de pé: uma rede de proteção para o caso de o socket perder um evento sem cair.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Menos consultas ao banco com o socket de pé; um evento perdido demora mais para ser recuperado.',
		'if_decreased', 'Um evento perdido aparece antes, ao custo de mais consultas de CADA aparelho aberto. 0 desliga o poll enquanto o socket está de pé (a remoção que o F-23 deixou para depois).',
		'takes_effect', 'Na próxima abertura do calendário.',
		'caveats', 'Precisa ser 0 ou pelo menos sync.poll_seconds_degraded. Com o socket caído, vale sempre o poll degradado.'))
ON CONFLICT (key) DO NOTHING;
