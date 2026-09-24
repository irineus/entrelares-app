-- =============================================================================
-- T-83 (4/4) — the help-and-contact form's limits become operator parameters
--
-- F-68 kept its numbers in ONE home (send-support-request) mirrored in core. An
-- abuse wave is now answered from the console in a minute:
--   support.anon_hourly 3 / support.anon_daily 10      (per typed e-mail and IP)
--   support.member_hourly 5 / support.member_daily 20  (per profile)
--   support.message_max_chars 2000 (200–2000 — the column CHECK is 2000)
-- Ranges by the owner (24/09/2026): per hour 1–20, per day 1–100, and per hour
-- never above per day (added to app_settings_cross_check, recreated from its
-- latest definition, T-83 3/4). The e-mail maximum (254) and the message
-- minimum (10) stay constants. The function's constants become the fallbacks,
-- and support_constants_mirror_test pins them to these seeds.
-- =============================================================================

-- ── The rules between the keys ───────────────────────────────────────────────

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
END;
$$;

ALTER FUNCTION public.app_settings_cross_check() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.app_settings_cross_check() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.app_settings_cross_check() TO service_role;

-- ── The keys ─────────────────────────────────────────────────────────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, min_value, max_value, help)
VALUES
	('support.anon_hourly', '3', 'int', 'support',
	 'Mensagens por hora que o formulário de ajuda aceita de quem não entrou (por e-mail e por IP).',
	 false, 'count', 'sensitive', 1, 20,
	 jsonb_build_object(
		'controls', 'O limite por hora de record_support_request para quem escreve sem estar logado, contado por e-mail digitado E por IP.',
		'shown_at', jsonb_build_array('server_only'),
		'if_increased', 'Numa onda de problema real, mais gente consegue escrever; mais espaço para abuso a partir de um mesmo IP.',
		'if_decreased', 'Numa onda de abuso, a porta aperta em um minuto — quem passa do limite vê o e-mail de suporte como alternativa.',
		'takes_effect', 'No próximo envio pelo formulário de ajuda.',
		'caveats', 'Precisa ser no máximo support.anon_daily. Os e-mails de suporte saem da cota do Resend, que é da conta inteira.')),
	('support.anon_daily', '10', 'int', 'support',
	 'Mensagens por dia que o formulário de ajuda aceita de quem não entrou (por e-mail e por IP).',
	 false, 'count', 'sensitive', 1, 100,
	 jsonb_build_object(
		'controls', 'O limite por dia de record_support_request para quem escreve sem estar logado, contado por e-mail digitado E por IP.',
		'shown_at', jsonb_build_array('server_only'),
		'if_increased', 'Mais mensagens por dia de um mesmo endereço ou IP.',
		'if_decreased', 'Menos mensagens por dia; quem passa do limite vê o e-mail de suporte como alternativa.',
		'takes_effect', 'No próximo envio pelo formulário de ajuda.',
		'caveats', 'Precisa ser no mínimo support.anon_hourly.')),
	('support.member_hourly', '5', 'int', 'support',
	 'Mensagens por hora que o formulário de ajuda aceita de um membro logado.',
	 false, 'count', 'sensitive', 1, 20,
	 jsonb_build_object(
		'controls', 'O limite por hora de record_support_request por perfil logado.',
		'shown_at', jsonb_build_array('server_only'),
		'if_increased', 'Um membro com um problema que evolui consegue escrever de novo mais vezes.',
		'if_decreased', 'Menos mensagens por hora por perfil; o e-mail de suporte segue como alternativa.',
		'takes_effect', 'No próximo envio pelo formulário de ajuda.',
		'caveats', 'Precisa ser no máximo support.member_daily.')),
	('support.member_daily', '20', 'int', 'support',
	 'Mensagens por dia que o formulário de ajuda aceita de um membro logado.',
	 false, 'count', 'sensitive', 1, 100,
	 jsonb_build_object(
		'controls', 'O limite por dia de record_support_request por perfil logado.',
		'shown_at', jsonb_build_array('server_only'),
		'if_increased', 'Mais mensagens por dia por perfil.',
		'if_decreased', 'Menos mensagens por dia por perfil; o e-mail de suporte segue como alternativa.',
		'takes_effect', 'No próximo envio pelo formulário de ajuda.',
		'caveats', 'Precisa ser no mínimo support.member_hourly.')),
	('support.message_max_chars', '2000', 'int', 'support',
	 'Tamanho máximo, em caracteres, de uma mensagem enviada pelo formulário de ajuda.',
	 true, 'chars', 'sensitive', 200, 2000,
	 jsonb_build_object(
		'controls', 'O limite de caracteres que send-support-request aceita numa mensagem; o formulário conta até esse número quando a pessoa está logada.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Não passa de 2000: é o CHECK da coluna support_requests.message.',
		'if_decreased', 'Mensagens mais curtas; quem não entrou vê o contador do padrão (2000) e é recusado pelo servidor acima do novo limite.',
		'takes_effect', 'No próximo envio pelo formulário de ajuda.',
		'caveats', 'O mínimo de 10 caracteres e o máximo de 254 do e-mail ficam fixos.'))
ON CONFLICT (key) DO NOTHING;
