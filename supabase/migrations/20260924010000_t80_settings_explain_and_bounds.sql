-- =============================================================================
-- T-80 — Every operator parameter explains itself and refuses a value the
-- product cannot hold
--
-- The operator console (F-58, repo `entrelares-console`) edits `app_settings`
-- through `admin_update_setting`, which until now checked ONLY `value_type`.
-- Each of these was accepted, each with a real consequence (read from
-- production, 23/09/2026):
--   · billing.price_monthly_cents = 300 → every Pix/boleto checkout fails
--     (Asaas refuses charges under R$ 5,00 — the reason the promo is 549, F-48);
--   · max_caregivers = 5 → next_free_color_slot only knows slots 1..4, so the
--     5th member joins with no colour;
--   · calendar_months_free > calendar_months_premium → Free plans further out;
--   · billing.grace_warning_days >= billing.grace_days → the warning goes out
--     on day 0 or never (billing_grace_warnings_due);
--   · a negative int anywhere.
-- And the explanation did not explain: descriptions mixed EN/PT, two were stale
-- (a Blazor file path, a "PROVISÓRIA" note from a promotion that happened).
--
-- DECISIONS (owner, 23/09/2026):
--   · Each row carries its own bounds (`min_value`/`max_value`), `unit`, an
--     operator-facing `help` (PT-BR, fixed keys) and an `impact` level that
--     drives the console's confirmation. The completeness of that metadata is
--     pinned by the DB gate, so a new key (T-82, T-83) is born explained.
--   · Type and range are checked by a BEFORE trigger for EVERY writer —
--     migrations and the service role included: a seed out of range fails at
--     `db push`, not in production.
--   · The rules BETWEEN keys also hold for every writer, as a DEFERRED
--     constraint trigger checked at commit — so one migration may move two
--     keys together, and only the state it leaves behind is judged.
--     `admin_update_setting` runs it IMMEDIATE, so the console gets the
--     sentence in the same call.
--   · `help`, `impact` and `updated_by` are the operator's: an authenticated
--     client keeps SELECT only on the columns it can use (column-level grant).
--   · `free_caregivers` floor is 2: the Terms promise "dois responsáveis" in
--     the free plan, and going below that is an S-15 change, not a console edit.
--   · `cutover.web_date` is deleted: its only reader was the Blazor client,
--     archived on 25/08/2026.
-- =============================================================================

-- ── 1. The metadata columns ──────────────────────────────────────────────────

ALTER TABLE public.app_settings
	ADD COLUMN IF NOT EXISTS min_value numeric,
	ADD COLUMN IF NOT EXISTS max_value numeric,
	ADD COLUMN IF NOT EXISTS unit      text,
	ADD COLUMN IF NOT EXISTS help      jsonb NOT NULL DEFAULT '{}'::jsonb,
	ADD COLUMN IF NOT EXISTS impact    text  NOT NULL DEFAULT 'normal';

ALTER TABLE public.app_settings
	ADD CONSTRAINT app_settings_unit_check CHECK (unit IS NULL OR unit IN (
		'cents_brl', 'days', 'months', 'hours', 'minutes', 'seconds',
		'count', 'chars', 'percent', 'date', 'flag', 'list')),
	ADD CONSTRAINT app_settings_impact_check
		CHECK (impact IN ('normal', 'sensitive', 'critical')),
	ADD CONSTRAINT app_settings_help_is_object
		CHECK (jsonb_typeof(help) = 'object'),
	-- A range only means something on a number, and it must be a range.
	ADD CONSTRAINT app_settings_range_numeric_only
		CHECK ((min_value IS NULL AND max_value IS NULL) OR value_type IN ('int', 'decimal')),
	ADD CONSTRAINT app_settings_range_ordered
		CHECK (min_value IS NULL OR max_value IS NULL OR min_value <= max_value);

COMMENT ON COLUMN public.app_settings.min_value IS
	'T-80: lowest value the product can hold (int/decimal rows). Enforced for every writer by app_settings_validate_row.';
COMMENT ON COLUMN public.app_settings.max_value IS
	'T-80: highest value the product can hold (int/decimal rows). Enforced for every writer by app_settings_validate_row.';
COMMENT ON COLUMN public.app_settings.unit IS
	'T-80: how the console formats the value (cents_brl, days, months, count, chars, flag, date, …).';
COMMENT ON COLUMN public.app_settings.help IS
	'T-80: the operator''s explanation, PT-BR. Keys: controls, shown_at[], if_increased, if_decreased, takes_effect, caveats, requires. Completeness pinned by the DB gate.';
COMMENT ON COLUMN public.app_settings.impact IS
	'T-80: normal | sensitive | critical — drives the console''s confirmation before a write.';

-- ── 2. Unit-aware formatting for the refusal sentences ───────────────────────

CREATE OR REPLACE FUNCTION public.app_settings_format(p_value numeric, p_unit text)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $$
	SELECT CASE p_unit
		WHEN 'cents_brl' THEN 'R$ ' || replace(to_char(p_value / 100.0, 'FM999999990.00'), '.', ',')
		WHEN 'percent'   THEN p_value::text || '%'
		ELSE p_value::text
	END;
$$;

-- The unit word that closes a range ("de 1 a 30 dias"). Money and percent
-- carry their own mark inside each bound.
CREATE OR REPLACE FUNCTION public.app_settings_unit_word(p_unit text)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $$
	SELECT CASE p_unit
		WHEN 'days'    THEN ' dias'
		WHEN 'months'  THEN ' meses'
		WHEN 'hours'   THEN ' horas'
		WHEN 'minutes' THEN ' minutos'
		WHEN 'seconds' THEN ' segundos'
		WHEN 'chars'   THEN ' caracteres'
		ELSE ''
	END;
$$;

ALTER FUNCTION public.app_settings_format(numeric, text) OWNER TO postgres;
ALTER FUNCTION public.app_settings_unit_word(text)       OWNER TO postgres;

-- ── 3. Row validation — type and range, for EVERY writer ─────────────────────
-- Moved here from admin_update_setting (which now relies on it), so a migration
-- or a service-role write is judged exactly like a console edit.

CREATE OR REPLACE FUNCTION public.app_settings_validate_row()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
	n      numeric;
	dummy  jsonb;
	bounds text;
BEGIN
	IF NEW.value_type = 'int' THEN
		IF NEW.value !~ '^-?[0-9]+$' THEN
			RAISE EXCEPTION 'Valor inválido para o tipo int: %.', NEW.value
				USING ERRCODE = 'check_violation';
		END IF;
		n := NEW.value::numeric;
		-- setting_int() casts to int4: a longer number would break every reader.
		IF n NOT BETWEEN -2147483648 AND 2147483647 THEN
			RAISE EXCEPTION 'Valor inválido para o tipo int: % não cabe num inteiro.', NEW.value
				USING ERRCODE = 'check_violation';
		END IF;
	ELSIF NEW.value_type = 'decimal' THEN
		BEGIN
			n := NEW.value::numeric;
		EXCEPTION WHEN OTHERS THEN
			RAISE EXCEPTION 'Valor inválido para o tipo decimal: %.', NEW.value
				USING ERRCODE = 'check_violation';
		END;
	ELSIF NEW.value_type = 'bool' THEN
		IF lower(NEW.value) NOT IN ('true', 'false') THEN
			RAISE EXCEPTION 'Valor inválido para o tipo bool: %.', NEW.value
				USING ERRCODE = 'check_violation';
		END IF;
		-- Readers compare the string ('true'), so one spelling only.
		NEW.value := lower(NEW.value);
	ELSIF NEW.value_type = 'json' THEN
		BEGIN
			dummy := NEW.value::jsonb;
		EXCEPTION WHEN OTHERS THEN
			RAISE EXCEPTION 'Valor inválido para o tipo json: %.', NEW.value
				USING ERRCODE = 'check_violation';
		END;
	END IF;

	IF n IS NOT NULL
	   AND ((NEW.min_value IS NOT NULL AND n < NEW.min_value)
	        OR (NEW.max_value IS NOT NULL AND n > NEW.max_value)) THEN
		bounds := CASE
			WHEN NEW.min_value IS NOT NULL AND NEW.max_value IS NOT NULL THEN
				'de ' || public.app_settings_format(NEW.min_value, NEW.unit)
				|| ' a ' || public.app_settings_format(NEW.max_value, NEW.unit)
			WHEN NEW.min_value IS NOT NULL THEN
				'no mínimo ' || public.app_settings_format(NEW.min_value, NEW.unit)
			ELSE
				'no máximo ' || public.app_settings_format(NEW.max_value, NEW.unit)
		END || public.app_settings_unit_word(NEW.unit);
		RAISE EXCEPTION 'Valor fora da faixa para %: %.', NEW.key, bounds
			USING ERRCODE = 'check_violation';
	END IF;

	RETURN NEW;
END;
$$;

ALTER FUNCTION public.app_settings_validate_row() OWNER TO postgres;

DROP TRIGGER IF EXISTS app_settings_validate_row ON public.app_settings;
CREATE TRIGGER app_settings_validate_row
	BEFORE INSERT OR UPDATE ON public.app_settings
	FOR EACH ROW EXECUTE FUNCTION public.app_settings_validate_row();

-- ── 4. Rules BETWEEN keys — deferred, for EVERY writer ───────────────────────
-- Judged on the state a transaction LEAVES: a migration that raises the free
-- and the premium horizon together passes, whichever row it writes first. Each
-- refusal names both keys and both values, in the operator's language.

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
END;
$$;

ALTER FUNCTION public.app_settings_cross_check() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.app_settings_cross_check() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.app_settings_cross_check() TO service_role;

CREATE OR REPLACE FUNCTION public.app_settings_coherence()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
	PERFORM public.app_settings_cross_check();
	RETURN NULL;
END;
$$;

ALTER FUNCTION public.app_settings_coherence() OWNER TO postgres;

-- The constraint trigger itself is created at the END of this migration (§9):
-- an ALTER TABLE cannot run while deferred trigger events are pending, and §7
-- rewrites every row before §8 adds the last CHECK.

-- ── 5. What an authenticated client may read ─────────────────────────────────
-- RLS already filters the ROWS to is_public; this filters the COLUMNS. The app
-- reads `key, value`; the range and unit stay readable for a future UX mirror
-- (U-57). The operator's notes, the impact level and who wrote are not a
-- client's business.

REVOKE SELECT ON public.app_settings FROM authenticated;
GRANT SELECT (key, value, value_type, category, description, is_public,
              updated_at, min_value, max_value, unit)
	ON public.app_settings TO authenticated;

-- ── 6. admin_update_setting — the rules now live in the table ────────────────
-- Same gates as F-58 (operator, S-10 elevation, policy.* refused, edits only).
-- Type and range are the row trigger's; the rules between keys are forced
-- IMMEDIATE so the console reads the sentence from this call, not from a
-- failed commit.

CREATE OR REPLACE FUNCTION public.admin_update_setting(p_key text, p_value text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	cur      public.app_settings%ROWTYPE;
	me_id    bigint;
	stored   text;
BEGIN
	IF NOT public.is_platform_operator() THEN
		RAISE EXCEPTION 'Acesso restrito à operação da plataforma.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	IF NOT public.is_elevated() THEN
		RAISE EXCEPTION 'ELEVATION_REQUIRED: Confirme sua senha para alterar parâmetros da aplicação.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	-- S-15/B-4: the policy keys move ONLY by migration, in the four-piece
	-- delivery. A lone DB edit here could lock the whole user base out.
	IF p_key LIKE 'policy.%' THEN
		RAISE EXCEPTION 'As chaves policy.* só mudam por migração (fluxo S-15) — o console não as edita.'
			USING ERRCODE = 'check_violation';
	END IF;

	SELECT * INTO cur FROM public.app_settings WHERE key = p_key;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'Parâmetro inexistente: %.', p_key
			USING ERRCODE = 'check_violation';
	END IF;

	SELECT id INTO me_id FROM public.profiles WHERE user_id = auth.uid();

	UPDATE public.app_settings
	SET value      = p_value,
	    updated_at = timezone('utc', now()),
	    updated_by = me_id
	WHERE key = p_key
	RETURNING value INTO stored;

	SET CONSTRAINTS public.app_settings_coherence IMMEDIATE;

	INSERT INTO public.operator_audit_logs (operator_user_id, action, setting_key, old_value, new_value)
	VALUES (auth.uid(), 'setting_updated', p_key, cur.value, stored);
END;
$$;

ALTER FUNCTION public.admin_update_setting(text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_update_setting(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_update_setting(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_update_setting(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_setting(text, text) TO service_role;

-- ── 7. Every live key, explained and bounded ─────────────────────────────────
-- `takes_effect` shorthand the console shows as written: the SERVER reads a
-- key on the next operation; the APP reads the public keys each time the
-- calendar, family or plan screen opens (fetchPublicSettings has no cache);
-- the LANDING never reads them today (L-34).

-- billing ---------------------------------------------------------------------

UPDATE public.app_settings SET
	description = 'Liga a venda do Premium pela web (Asaas). Desligado, a Família mostra a lista de espera.',
	unit = 'flag', impact = 'critical', min_value = NULL, max_value = NULL,
	help = jsonb_build_object(
		'controls', 'Chave-mestra do trilho web/Asaas: se o app oferece a assinatura no navegador e se a função billing-checkout aceita criar uma nova.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Ligado: toda família do plano gratuito na web vê o funil de assinatura e pode pagar por Pix, boleto ou cartão.',
		'if_decreased', 'Desligado: a página do plano volta à lista de espera e billing-checkout recusa assinaturas novas. Assinaturas ativas, cobranças já emitidas e o trilho da Play NÃO mudam.',
		'takes_effect', 'Servidor na próxima tentativa de checkout; app na próxima abertura da página do plano.',
		'caveats', 'Independente de billing.store_enabled, que rege a Play.')
WHERE key = 'billing.enabled';

UPDATE public.app_settings SET
	description = 'Liga a venda do Premium pela Google Play. Desligado, o app Android mostra o aviso neutro (T-38).',
	unit = 'flag', impact = 'critical', min_value = NULL, max_value = NULL,
	help = jsonb_build_object(
		'controls', 'Chave-mestra do trilho da loja: se o app Android oferece a compra dentro do app e se billing-store-verify aceita um recibo.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Ligado: o app instalado pela Play mostra os preços da Play e vende o Premium por lá.',
		'if_decreased', 'Desligado: o app Android mostra o aviso neutro no lugar da compra e billing-store-verify recusa recibos novos. Assinaturas da Play já ativas seguem valendo.',
		'takes_effect', 'Servidor na próxima verificação de compra; app na próxima abertura da página do plano.',
		'caveats', 'O PREÇO da Play é definido na Play Console, não aqui. Independente de billing.enabled.')
WHERE key = 'billing.store_enabled';

UPDATE public.app_settings SET
	description = 'Preço mensal do Premium na web (Asaas), em centavos. Vale para assinaturas novas.',
	unit = 'cents_brl', impact = 'critical', min_value = 500, max_value = 99900,
	help = jsonb_build_object(
		'controls', 'O preço mensal que o app mostra na web e que billing-checkout cobra em cada assinatura NOVA e em cada reativação agendada.',
		'shown_at', jsonb_build_array('app', 'landing'),
		'if_increased', 'Assinaturas novas passam a custar mais. O selo "2 meses grátis" é recalculado a partir do anual e pode sumir.',
		'if_decreased', 'Assinaturas novas passam a custar menos. Abaixo de R$ 5,00 o Asaas recusa Pix e boleto — por isso o piso.',
		'takes_effect', 'Servidor no próximo checkout; app na próxima abertura da página do plano.',
		'caveats', 'NÃO muda: assinaturas Asaas ativas (os Termos garantem o preço contratado), o preço da Play (Play Console) e o texto da landing, que escreve o número à mão (L-34).',
		'requires', 'Conferir o texto de preço da landing e o anual (no máximo 12 × o mensal).')
WHERE key = 'billing.price_monthly_cents';

UPDATE public.app_settings SET
	description = 'Preço anual do Premium na web (Asaas), em centavos. Vale para assinaturas novas.',
	unit = 'cents_brl', impact = 'critical', min_value = 500, max_value = 999900,
	help = jsonb_build_object(
		'controls', 'O preço anual que o app mostra na web e que billing-checkout cobra em cada assinatura NOVA e em cada reativação agendada.',
		'shown_at', jsonb_build_array('app', 'landing'),
		'if_increased', 'Assinaturas anuais novas passam a custar mais; o selo "N meses grátis" diminui ou some (é calculado contra o mensal).',
		'if_decreased', 'Assinaturas anuais novas passam a custar menos; o selo pode passar a prometer mais meses grátis.',
		'takes_effect', 'Servidor no próximo checkout; app na próxima abertura da página do plano.',
		'caveats', 'NÃO muda: assinaturas Asaas ativas, o preço da Play e o texto da landing (L-34). Precisa ser no máximo 12 × o mensal.',
		'requires', 'Conferir o texto de preço da landing.')
WHERE key = 'billing.price_annual_cents';

UPDATE public.app_settings SET
	description = 'Dias entre a cobrança vencida e a volta ao plano gratuito.',
	unit = 'days', impact = 'sensitive', min_value = 1, max_value = 30,
	help = jsonb_build_object(
		'controls', 'Carência de uma renovação vencida: o cron billing-grace-downgrade (minuto 23 de toda hora) rebaixa a família quando overdue_since + N dias passou.',
		'shown_at', jsonb_build_array('app', 'email'),
		'if_increased', 'Famílias inadimplentes ficam mais tempo com o Premium; o painel de atraso e o e-mail de aviso passam a prometer a data nova.',
		'if_decreased', 'Famílias JÁ em atraso podem ser rebaixadas na próxima hora, se a data nova já passou para elas.',
		'takes_effect', 'Servidor na próxima rodada do cron (até 1 hora); app na próxima abertura da página do plano.',
		'caveats', 'Precisa ser maior que billing.grace_warning_days.')
WHERE key = 'billing.grace_days';

UPDATE public.app_settings SET
	description = 'Quantos dias antes do rebaixamento sai o aviso ao administrador da família.',
	unit = 'days', impact = 'normal', min_value = 1, max_value = 29,
	help = jsonb_build_object(
		'controls', 'Antecedência do aviso de fim da carência (notificação + e-mail ao administrador), enviado uma vez pela rotina diária purge-deleted.',
		'shown_at', jsonb_build_array('server_only'),
		'if_increased', 'O aviso sai mais cedo dentro da carência.',
		'if_decreased', 'O aviso sai mais perto do rebaixamento.',
		'takes_effect', 'Servidor na próxima rodada diária.',
		'caveats', 'Precisa ser menor que billing.grace_days; uma família que já recebeu o aviso não recebe outro.')
WHERE key = 'billing.grace_warning_days';

-- freemium --------------------------------------------------------------------

UPDATE public.app_settings SET
	description = 'Meses à frente que uma família do plano gratuito pode planejar.',
	unit = 'months', impact = 'sensitive', min_value = 1, max_value = 24,
	help = jsonb_build_object(
		'controls', 'Horizonte de planejamento do plano gratuito, conferido por enforce_day_protection a cada dia gravado.',
		'shown_at', jsonb_build_array('app', 'landing'),
		'if_increased', 'Famílias gratuitas planejam mais longe; o motivo para assinar o Premium diminui.',
		'if_decreased', 'Dias já planejados além do novo limite FICAM (nada é apagado); só gravações novas além dele são recusadas, com o convite ao Premium.',
		'takes_effect', 'Servidor na próxima gravação de dia; app na próxima abertura do calendário.',
		'caveats', 'O número também está escrito à mão em textos do app (U-57) e na landing (L-34). Precisa ser no máximo calendar_months_premium.')
WHERE key = 'calendar_months_free';

UPDATE public.app_settings SET
	description = 'Meses à frente do Premium — também o teto rígido de planejamento para todos.',
	unit = 'months', impact = 'sensitive', min_value = 6, max_value = 36,
	help = jsonb_build_object(
		'controls', 'Horizonte de planejamento do Premium e teto absoluto para qualquer família, conferido por enforce_day_protection.',
		'shown_at', jsonb_build_array('app', 'landing'),
		'if_increased', 'Famílias Premium planejam mais longe; mais linhas de calendário no banco.',
		'if_decreased', 'Dias já planejados além do novo limite FICAM; só gravações novas além dele são recusadas.',
		'takes_effect', 'Servidor na próxima gravação de dia; app na próxima abertura do calendário.',
		'caveats', 'O número também está escrito à mão em textos do app (U-57) e na landing (L-34). Precisa ser no mínimo calendar_months_free.')
WHERE key = 'calendar_months_premium';

UPDATE public.app_settings SET
	description = 'Responsáveis (membros + convites abertos) incluídos no plano gratuito.',
	unit = 'count', impact = 'critical', min_value = 2, max_value = 4,
	help = jsonb_build_object(
		'controls', 'Quantas cadeiras o gratuito inclui; além disso create_invitation e o cadastro pelo convite pedem o Premium.',
		'shown_at', jsonb_build_array('app', 'landing'),
		'if_increased', 'Famílias gratuitas convidam mais gente (avós, babá) sem assinar.',
		'if_decreased', 'Famílias que já passam do número NÃO perdem ninguém (vale só para convites novos). O piso é 2: os Termos prometem dois responsáveis no gratuito.',
		'takes_effect', 'Servidor no próximo convite ou cadastro; app na próxima abertura da Família.',
		'caveats', 'Os Termos dizem "dois responsáveis" (entrelares-site, termos.html). Precisa ser no máximo max_caregivers.',
		'requires', 'Revisar os Termos e a política (fluxo S-15) antes de mudar.')
WHERE key = 'free_caregivers';

UPDATE public.app_settings SET
	description = 'Teto absoluto de responsáveis por família, em qualquer plano.',
	unit = 'count', impact = 'critical', min_value = 2, max_value = 4,
	help = jsonb_build_object(
		'controls', 'O máximo de cadeiras (membros + convites abertos + membros pendentes) de uma família, Premium inclusive.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Não passa de 4: a paleta tem quatro cores (next_free_color_slot só conhece 1 a 4) e um 5º membro entraria sem cor.',
		'if_decreased', 'Famílias acima do número novo NÃO perdem ninguém; só convites novos são recusados.',
		'takes_effect', 'Servidor no próximo convite ou cadastro; app na próxima abertura da Família.',
		'caveats', 'Precisa ser no mínimo free_caregivers. Subir além de 4 pede código (paleta), não console.')
WHERE key = 'max_caregivers';

UPDATE public.app_settings SET
	description = 'Dias para trás que o administrador do plano gratuito pode corrigir no modo administrador.',
	unit = 'days', impact = 'normal', min_value = 0, max_value = 30,
	help = jsonb_build_object(
		'controls', 'Alcance retroativo da correção de dias passados por um administrador do gratuito (enforce_day_protection).',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Administradores do gratuito corrigem dias mais antigos; o registro marca cada correção como feita pelo administrador.',
		'if_decreased', 'Correções mais antigas passam a pedir o Premium. 0 = o gratuito não corrige dia passado nenhum.',
		'takes_effect', 'Servidor na próxima gravação; app na próxima abertura do calendário ou do modo administrador.',
		'caveats', 'Precisa ser no máximo override_premium_months × 28.')
WHERE key = 'override_free_days';

UPDATE public.app_settings SET
	description = 'Meses para trás que o administrador Premium pode corrigir — também o teto para todos.',
	unit = 'months', impact = 'normal', min_value = 1, max_value = 24,
	help = jsonb_build_object(
		'controls', 'Alcance retroativo da correção de dias passados no Premium, e teto rígido para qualquer família (enforce_day_protection).',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Correções de dias mais antigos passam a ser aceitas; o registro de cada uma segue marcado.',
		'if_decreased', 'Dias antes do novo limite ficam imutáveis para todos.',
		'takes_effect', 'Servidor na próxima gravação; app na próxima abertura do calendário ou do modo administrador.',
		'caveats', 'Precisa cobrir override_free_days (× 28 dias).')
WHERE key = 'override_premium_months';

UPDATE public.app_settings SET
	description = 'E-mails transacionais por família por mês no plano gratuito.',
	unit = 'count', impact = 'normal', min_value = 10, max_value = 1000,
	help = jsonb_build_object(
		'controls', 'Cota mensal (mês de São Paulo) de e-mails de uma família gratuita; consume_email_quota conta cada envio.',
		'shown_at', jsonb_build_array('app', 'email'),
		'if_increased', 'Famílias gratuitas recebem mais e-mails antes de parar; mais consumo da cota do Resend (compartilhada entre produtos).',
		'if_decreased', 'O aviso de 80% (notificação no app) e o último e-mail chegam antes; depois disso os e-mails param até o mês virar. As notificações no app seguem sem limite.',
		'takes_effect', 'Servidor no próximo e-mail.',
		'caveats', 'Precisa ser no máximo email_cap_premium.')
WHERE key = 'email_cap_free';

UPDATE public.app_settings SET
	description = 'E-mails transacionais por família por mês no Premium (teto contra abuso).',
	unit = 'count', impact = 'normal', min_value = 100, max_value = 100000,
	help = jsonb_build_object(
		'controls', 'Cota mensal (mês de São Paulo) de e-mails de uma família Premium; é um teto contra abuso, nada é ilimitado.',
		'shown_at', jsonb_build_array('server_only'),
		'if_increased', 'Uma família Premium pode disparar mais e-mails; a cota do Resend é da conta inteira.',
		'if_decreased', 'Famílias Premium muito ativas param de receber e-mail no mês — sem aviso prévio (os avisos são só do gratuito).',
		'takes_effect', 'Servidor no próximo e-mail.',
		'caveats', 'Precisa ser no mínimo email_cap_free.')
WHERE key = 'email_cap_premium';

-- product (F-67 relato do dia) -------------------------------------------------

UPDATE public.app_settings SET
	description = 'Quantos dias para trás um relato do dia pode ser registrado (D-1 a D-N; hoje nunca).',
	unit = 'days', impact = 'sensitive', min_value = 1, max_value = 90,
	help = jsonb_build_object(
		'controls', 'Alcance do relato do dia (add_day_account): até quantos dias passados um membro pode anexar o que aconteceu.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Relatos sobre dias mais antigos passam a entrar no registro, no Histórico e no PDF.',
		'if_decreased', 'Dias fora da nova janela deixam de aceitar relato; os relatos já gravados ficam.',
		'takes_effect', 'Servidor no próximo relato; app na próxima abertura do calendário.',
		'caveats', 'Muda o que o registro que a família leva a um advogado pode conter.')
WHERE key = 'day_account.max_days_back';

UPDATE public.app_settings SET
	description = 'Tamanho máximo do texto de um relato do dia, em caracteres.',
	unit = 'chars', impact = 'normal', min_value = 100, max_value = 4000,
	help = jsonb_build_object(
		'controls', 'Limite de caracteres de um relato do dia, conferido por add_day_account.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Relatos mais longos; o PDF cresce. Não passa de 4000: é o CHECK da coluna day_accounts.body.',
		'if_decreased', 'Textos acima do novo limite são recusados; os relatos já gravados ficam inteiros.',
		'takes_effect', 'Servidor no próximo relato; app na próxima abertura do calendário.')
WHERE key = 'day_account.max_chars';

UPDATE public.app_settings SET
	description = 'Relatos que um mesmo autor pode registrar por dia (teto contra abuso).',
	unit = 'count', impact = 'normal', min_value = 1, max_value = 50,
	help = jsonb_build_object(
		'controls', 'Quantos relatos do dia um mesmo membro grava num mesmo dia do calendário (add_day_account); o app avisa antes de bloquear.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Um membro pode anexar mais relatos sobre o mesmo dia.',
		'if_decreased', 'Quem já chegou ao número novo naquele dia é recusado no próximo relato.',
		'takes_effect', 'Servidor no próximo relato; app na próxima abertura do calendário.')
WHERE key = 'day_account.daily_cap';

-- legal (locked: migration only, S-15) ---------------------------------------

UPDATE public.app_settings SET
	description = 'Versão vigente da Política e dos Termos que o aceite referencia. Só muda por migração (S-15).',
	unit = 'date', impact = 'critical', min_value = NULL, max_value = NULL,
	help = jsonb_build_object(
		'controls', 'A versão que accept_policy exige; espelha PolicyVersions.current no app (packages/entrelares_core).',
		'shown_at', jsonb_build_array('app', 'landing'),
		'if_increased', 'Uma versão nova obriga todo membro a aceitar de novo a partir de policy.enforce_from.',
		'if_decreased', 'Não se volta versão: o app e o servidor deixariam de concordar e todo aceite seria recusado.',
		'takes_effect', 'Só por migração, na entrega de quatro peças do S-15 (código, app_settings, resumo de mudanças, janela de aviso).',
		'requires', 'Fluxo S-15 completo. O console nunca edita esta chave.')
WHERE key = 'policy.current_version';

UPDATE public.app_settings SET
	description = 'Data a partir da qual quem não aceitou a versão vigente fica bloqueado. Só muda por migração (S-15).',
	unit = 'date', impact = 'critical', min_value = NULL, max_value = NULL,
	help = jsonb_build_object(
		'controls', 'O fim da janela de aviso do reaceite; espelha PolicyVersions.enforceFrom no app.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'A janela de aviso fica mais longa; o bloqueio chega depois.',
		'if_decreased', 'O bloqueio chega antes — e precisa ser a data em que o texto ficou VISÍVEL + 15 dias.',
		'takes_effect', 'Só por migração, junto com policy.current_version (S-15).',
		'requires', 'Fluxo S-15 completo. O console nunca edita esta chave.')
WHERE key = 'policy.enforce_from';

-- dead ------------------------------------------------------------------------

-- Read ONLY by the Blazor client, archived on 25/08/2026 (T-53, T-56).
DELETE FROM public.app_settings WHERE key = 'cutover.web_date';

-- ── 8. One line per description ──────────────────────────────────────────────
-- Added AFTER the rewrite above: the old descriptions ran up to ~230 chars.

ALTER TABLE public.app_settings
	ADD CONSTRAINT app_settings_description_one_line
		CHECK (description IS NULL
		       OR (char_length(description) <= 120 AND description !~ '[\r\n]'));

-- ── 9. The rules between keys, from here on ──────────────────────────────────
-- Checked once now against the state this migration leaves, then for every
-- later writer at commit.

SELECT public.app_settings_cross_check();

DROP TRIGGER IF EXISTS app_settings_coherence ON public.app_settings;
CREATE CONSTRAINT TRIGGER app_settings_coherence
	AFTER INSERT OR UPDATE ON public.app_settings
	DEFERRABLE INITIALLY DEFERRED
	FOR EACH ROW EXECUTE FUNCTION public.app_settings_coherence();
