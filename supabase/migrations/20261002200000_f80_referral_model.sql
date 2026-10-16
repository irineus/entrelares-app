-- =============================================================================
-- F-80 (PR 1) — family referral: the model, the opaque code, the attribution
--
-- A family that already uses the product invites ANOTHER family to found its
-- own (not to join — that is the invitation, F-14). The referrer gets a free
-- month once the referred family pays and stays paid (PR 3); the referred
-- family gets nothing beyond the normal trial. This PR lays the ground:
--
--   · `family_referral_codes` — one OPAQUE code per family, created lazily by
--     `my_referral_code()`. Ten characters drawn from an unambiguous 32-letter
--     alphabet with `gen_random_bytes` — never derived from an id or a name,
--     so a code tells nothing about whose it is.
--   · `family_referrals` — one row per REFERRED family (first touch wins),
--     carrying the lifecycle PR 3 walks: attributed → paid → qualified →
--     rewarded, or cancelled. Service role only; no client reads it.
--   · `attribute_referral(code, channel)` — the founder of a family created in
--     the last 24 h names the code that brought them. It answers a closed
--     enum (`attributed` / `ignored`) and never says anything about the
--     referrer: an unknown code is `ignored`, exactly like an already
--     attributed family, so the call cannot be used to probe codes.
--   · THE E-MAIL SIGN-UP, and why it does not call the RPC. The web founder
--     signs up with e-mail and password and has NO session until the
--     confirmation link is clicked (often in another tab, days later), so an
--     authenticated call "right after sign-up" does not exist on that path.
--     The code travels instead in the sign-up metadata (`referral_code`,
--     `referral_channel`), and two triggers on `auth.users` attribute it in
--     the SAME transaction that `handle_new_user` creates the family in:
--       BEFORE INSERT  strips both keys from raw_user_meta_data ALWAYS (the
--       OR UPDATE      code is never stored in the auth row), and only on the
--                      INSERT and only while the flag is on stashes it in a
--                      transaction-local setting. The UPDATE half exists
--                      because GoTrue writes its IN-MEMORY metadata back after
--                      the insert (confirming an address stamps
--                      `email_verified` into the same column) — the gate
--                      caught the key coming back that way;
--       AFTER INSERT   (named to fire after `on_auth_user_created`) reads the
--                      stash, finds the founder's new family and attributes.
--     Both swallow every error: a referral can never cost a sign-up. The
--     Google door has a session at once, so it calls the RPC after
--     `complete_oauth_onboarding` (and Android's Install Referrer, PR 2, will
--     do the same after the first sign-in).
--
-- DARK (T-84, owner 02/10/2026 — legal): `feature.referral` is seeded FALSE
-- and stays false in production until a material policy bump (2.1) ships with
-- the flip. While it is off NOTHING is collected: `my_referral_code` and
-- `attribute_referral` refuse, the sign-up triggers drop the code before any
-- row is written, and the client neither reads the URL code into a request
-- nor calls anything (it asks `referral_enabled()` first).
--
-- The reward rules live in PR 3 and are only carried by the shape here:
-- `referral.hold_days` (30 days without refund/chargeback after the FIRST paid
-- payment) and `referral.yearly_cap` (12 rewards per referrer family a year).
--
-- The T-99 bulletin's `referrals` placeholder becomes the count of families
-- attributed in the week — NULL while the module is dark, so the e-mail keeps
-- saying "not measured" instead of a zero that would read as a result.
-- =============================================================================

-- ── 1. The settings (T-80 metadata on every key) ────────────────────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, help)
VALUES
	('feature.referral', 'false', 'bool', 'features',
	 'Liga a indicação entre famílias (F-80): código da família e atribuição no cadastro. Desligado, nada é coletado.',
	 true, 'flag', 'critical',
	 jsonb_build_object(
		'controls', 'Se my_referral_code entrega o código de indicação da família, se attribute_referral e o cadastro por e-mail registram qual família indicou a nova, e se o app lê o código do link de cadastro.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Ligado: toda família pode obter o seu código, e uma família nova que se cadastra pelo link com ?ref= fica registrada como indicada por ela (só contagens chegam ao operador).',
		'if_decreased', 'Desligado (chave de emergência): o app para de ler o código do link, o servidor recusa as duas RPCs e descarta o código que vier no cadastro. O que já foi registrado FICA.',
		'takes_effect', 'Servidor na próxima chamada ou no próximo cadastro; app na próxima abertura da tela de cadastro.',
		'caveats', 'Nasce DESLIGADO em produção (lançamento escuro). Ligar exige a política de privacidade 2.1 publicada no mesmo dia: a indicação liga duas famílias e é dado novo.',
		'requires', 'Política de privacidade 2.1 (indicação) publicada; recompensa do PR 3 pronta antes de anunciar o programa.')),
	('referral.hold_days', '30', 'int', 'billing',
	 'Dias sem estorno nem chargeback após o 1º pagamento da família indicada antes de recompensar quem indicou (F-80).',
	 false, 'days', 'sensitive',
	 jsonb_build_object(
		'controls', 'Quantos dias depois do PRIMEIRO pagamento confirmado da família indicada a indicação vira "qualificada" e quem indicou ganha o mês grátis — um estorno dentro dessa janela cancela a indicação.',
		'shown_at', jsonb_build_array('server_only'),
		'if_increased', 'Mais espera antes do mês grátis: menos risco de premiar um pagamento que volta, recompensa mais tardia para quem indicou.',
		'if_decreased', 'Recompensa mais cedo, com mais risco de premiar um pagamento que vira estorno (chargeback depois da recompensa é risco aceito).',
		'takes_effect', 'Para indicações cujo primeiro pagamento ainda não completou a janela, na próxima passada do job de recompensa (PR 3).',
		'caveats', 'Nenhum leitor até o PR 3 (recompensa). Mudar com indicações em espera move a data delas também.')),
	('referral.yearly_cap', '12', 'int', 'billing',
	 'Máximo de meses grátis por indicação que uma família recebe em 12 meses (F-80).',
	 false, 'count', 'sensitive',
	 jsonb_build_object(
		'controls', 'Quantas recompensas (um mês grátis cada) uma mesma família que indica pode receber em qualquer janela de 12 meses.',
		'shown_at', jsonb_build_array('server_only'),
		'if_increased', 'Uma família que indica muito pode acumular mais meses grátis.',
		'if_decreased', 'Indicações além do teto continuam registradas, mas não geram mês grátis.',
		'takes_effect', 'Na próxima recompensa concedida pelo job do PR 3.',
		'caveats', 'Nenhum leitor até o PR 3 (recompensa).'))
ON CONFLICT (key) DO NOTHING;

UPDATE public.app_settings SET min_value = 7, max_value = 90 WHERE key = 'referral.hold_days';
UPDATE public.app_settings SET min_value = 1, max_value = 24 WHERE key = 'referral.yearly_cap';


-- ── 2. The code ──────────────────────────────────────────────────────────────
-- 32 symbols — no 0/O, no 1/I — so `get_byte & 31` draws each one with the
-- same probability; 10 of them are 50 random bits. Mirrored by
-- `ReferralRules` (core), whose test reads this file.

CREATE OR REPLACE FUNCTION public.referral_code_is_shaped(p_code text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $$
	SELECT coalesce(p_code ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{10}$', false);
$$;

CREATE OR REPLACE FUNCTION public.referral_new_code()
RETURNS text
LANGUAGE plpgsql VOLATILE
SET search_path TO 'public'
AS $$
DECLARE
	alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
	bytes    bytea := extensions.gen_random_bytes(10);
	result   text := '';
	i        int;
BEGIN
	FOR i IN 0..9 LOOP
		result := result || substr(alphabet, (get_byte(bytes, i) & 31) + 1, 1);
	END LOOP;
	RETURN result;
END;
$$;

ALTER FUNCTION public.referral_code_is_shaped(text) OWNER TO postgres;
ALTER FUNCTION public.referral_new_code() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.referral_code_is_shaped(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.referral_new_code() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.referral_code_is_shaped(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.referral_new_code() TO service_role;

CREATE TABLE public.family_referral_codes (
	family_id  bigint PRIMARY KEY REFERENCES public.families(id) ON DELETE CASCADE,
	code       text   NOT NULL UNIQUE CHECK (public.referral_code_is_shaped(code)),
	created_at timestamp with time zone NOT NULL DEFAULT timezone('utc', now())
);

COMMENT ON TABLE public.family_referral_codes IS
	'F-80: one opaque referral code per family (random, never derived from ids or names), created by my_referral_code(). No client grant.';

ALTER TABLE public.family_referral_codes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.family_referral_codes FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.family_referral_codes TO service_role;


-- ── 3. The referral ──────────────────────────────────────────────────────────
-- referrer_family_id is ON DELETE SET NULL, not CASCADE: the row belongs to
-- the REFERRED family. If the referrer deletes itself, the referred family
-- still "has been referred" (first touch stays won — it cannot be attributed
-- again to someone else), the bulletin's past weeks keep their counts, and
-- PR 3 finds no one to reward and cancels. What SET NULL erases is the link
-- to the deleted family, which is the part that is about it; the code text
-- left behind resolves to nothing once its family_referral_codes row is gone.

CREATE TABLE public.family_referrals (
	referred_family_id bigint PRIMARY KEY REFERENCES public.families(id) ON DELETE CASCADE,
	referrer_family_id bigint REFERENCES public.families(id) ON DELETE SET NULL,
	code               text NOT NULL,
	channel            text NOT NULL CHECK (channel IN ('web', 'android')),
	attributed_at      timestamp with time zone NOT NULL DEFAULT timezone('utc', now()),
	status             text NOT NULL DEFAULT 'attributed'
	                   CHECK (status IN ('attributed', 'paid', 'qualified', 'rewarded', 'cancelled')),
	first_paid_at      timestamp with time zone,
	qualifies_at       timestamp with time zone,
	rewarded_at        timestamp with time zone,
	cancelled_at       timestamp with time zone,
	CHECK (referrer_family_id IS DISTINCT FROM referred_family_id)
);

CREATE INDEX family_referrals_referrer_idx ON public.family_referrals (referrer_family_id);
CREATE INDEX family_referrals_attributed_idx ON public.family_referrals (attributed_at);

COMMENT ON TABLE public.family_referrals IS
	'F-80: one row per REFERRED family (first touch wins) and its reward lifecycle (PR 3). Service role only — no client reads it.';

ALTER TABLE public.family_referrals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.family_referrals FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.family_referrals TO service_role;


-- ── 4. The one writer of a referral ─────────────────────────────────────────
-- Shared by the RPC and the sign-up trigger. `self` is for the RPC to turn
-- into a refusal; nothing else leaves the server.

CREATE OR REPLACE FUNCTION public.referral_attribute_family(
	p_family_id bigint, p_code text, p_channel text)
RETURNS text
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	v_code     text := upper(btrim(coalesce(p_code, '')));
	v_referrer bigint;
BEGIN
	IF p_channel IS NULL OR p_channel NOT IN ('web', 'android') THEN
		RETURN 'ignored';
	END IF;
	-- First touch wins: a family already referred is a quiet no-op.
	IF EXISTS (SELECT 1 FROM public.family_referrals WHERE referred_family_id = p_family_id) THEN
		RETURN 'ignored';
	END IF;
	IF NOT public.referral_code_is_shaped(v_code) THEN
		RETURN 'ignored';
	END IF;

	SELECT family_id INTO v_referrer FROM public.family_referral_codes WHERE code = v_code;
	IF v_referrer IS NULL THEN
		RETURN 'ignored';
	END IF;
	IF v_referrer = p_family_id THEN
		RETURN 'self';
	END IF;

	INSERT INTO public.family_referrals (referred_family_id, referrer_family_id, code, channel)
	VALUES (p_family_id, v_referrer, v_code, p_channel)
	ON CONFLICT (referred_family_id) DO NOTHING;

	RETURN CASE WHEN FOUND THEN 'attributed' ELSE 'ignored' END;
END;
$$;

ALTER FUNCTION public.referral_attribute_family(bigint, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.referral_attribute_family(bigint, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.referral_attribute_family(bigint, text, text) TO service_role;


-- ── 5. my_referral_code() ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.my_referral_code()
RETURNS text
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me    public.profiles%ROWTYPE;
	v     text;
	tries int := 0;
BEGIN
	IF NOT public.setting_bool('feature.referral', false) THEN
		RAISE EXCEPTION 'A indicação ainda não está disponível.'
			USING ERRCODE = 'feature_not_supported';
	END IF;

	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();

	-- A departed member (S-11) speaks for no family; a viewer (F-50) reads,
	-- it does not represent the family to another one.
	IF me.id IS NULL OR me.left_at IS NOT NULL OR me.family_id IS NULL
	   OR me.membership_type = 'viewer' THEN
		RAISE EXCEPTION 'Somente responsáveis da família podem obter o código de indicação.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	SELECT code INTO v FROM public.family_referral_codes WHERE family_id = me.family_id;
	IF v IS NOT NULL THEN
		RETURN v;
	END IF;

	-- Two members asking at once: ON CONFLICT (family_id) keeps one code.
	-- A collision on the code itself (50 random bits) draws again.
	LOOP
		tries := tries + 1;
		BEGIN
			INSERT INTO public.family_referral_codes (family_id, code)
			VALUES (me.family_id, public.referral_new_code())
			ON CONFLICT (family_id) DO NOTHING;
			EXIT;
		EXCEPTION WHEN unique_violation THEN
			IF tries >= 5 THEN
				RAISE;
			END IF;
		END;
	END LOOP;

	SELECT code INTO v FROM public.family_referral_codes WHERE family_id = me.family_id;
	RETURN v;
END;
$$;

COMMENT ON FUNCTION public.my_referral_code() IS
	'F-80: the caller''s family referral code, created on first ask. Active full member with an account; refuses while feature.referral is off.';

ALTER FUNCTION public.my_referral_code() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.my_referral_code() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_referral_code() TO authenticated, service_role;


-- ── 6. attribute_referral(code, channel) ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.attribute_referral(p_code text, p_channel text)
RETURNS text
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me      public.profiles%ROWTYPE;
	born    timestamp with time zone;
	result  text;
BEGIN
	IF NOT public.setting_bool('feature.referral', false) THEN
		RAISE EXCEPTION 'A indicação ainda não está disponível.'
			USING ERRCODE = 'feature_not_supported';
	END IF;

	IF p_channel IS NULL OR p_channel NOT IN ('web', 'android') THEN
		RAISE EXCEPTION 'Canal de indicação inválido.'
			USING ERRCODE = 'invalid_parameter_value';
	END IF;

	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();

	-- Only the founder speaks for the new family: an admin (a viewer never
	-- is one — profiles_viewer_not_admin), present, with an account.
	IF me.id IS NULL OR me.left_at IS NOT NULL OR me.family_id IS NULL
	   OR NOT me.is_admin OR me.membership_type = 'viewer' THEN
		RAISE EXCEPTION 'Somente quem criou a família pode registrar a indicação.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	-- Idempotent: a second call is the same answer as a code nobody owns.
	IF EXISTS (SELECT 1 FROM public.family_referrals WHERE referred_family_id = me.family_id) THEN
		RETURN 'ignored';
	END IF;

	-- Attribution is a sign-up act, not something a family adds later.
	SELECT created_at INTO born FROM public.families WHERE id = me.family_id;
	IF born < timezone('utc', now()) - interval '24 hours' THEN
		RAISE EXCEPTION 'A indicação só pode ser registrada no cadastro da família.'
			USING ERRCODE = 'check_violation';
	END IF;

	result := public.referral_attribute_family(me.family_id, p_code, p_channel);
	IF result = 'self' THEN
		RAISE EXCEPTION 'Uma família não pode indicar a si mesma.'
			USING ERRCODE = 'check_violation';
	END IF;
	RETURN result;
END;
$$;

COMMENT ON FUNCTION public.attribute_referral(text, text) IS
	'F-80: the founder of a family created in the last 24 h names the referral code that brought it. Returns attributed | ignored and nothing about the referrer.';

ALTER FUNCTION public.attribute_referral(text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.attribute_referral(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.attribute_referral(text, text) TO authenticated, service_role;


-- ── 7. referral_enabled() — the one thing a signed-out visitor may ask ──────
-- The register screen runs before any session, and the anon key reads no
-- table (T-44). This answers the flag and nothing else, so the client can
-- decide NOT to send a code while the module is dark.

CREATE OR REPLACE FUNCTION public.referral_enabled()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
	SELECT public.setting_bool('feature.referral', false);
$$;

ALTER FUNCTION public.referral_enabled() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.referral_enabled() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.referral_enabled() TO anon, authenticated, service_role;


-- ── 8. The e-mail sign-up: capture, strip, attribute ─────────────────────────

CREATE OR REPLACE FUNCTION public.referral_capture_on_signup()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	v_code    text;
	v_channel text;
BEGIN
	IF NEW.raw_user_meta_data IS NULL
	   OR NOT (NEW.raw_user_meta_data ? 'referral_code'
	           OR NEW.raw_user_meta_data ? 'referral_channel') THEN
		RETURN NEW;
	END IF;

	-- GoTrue re-saving the metadata it holds in memory: strip, never capture
	-- (attribution is the INSERT's, inside the sign-up).
	IF TG_OP = 'UPDATE' THEN
		NEW.raw_user_meta_data := NEW.raw_user_meta_data - 'referral_code' - 'referral_channel';
		RETURN NEW;
	END IF;

	v_code    := upper(btrim(coalesce(NEW.raw_user_meta_data ->> 'referral_code', '')));
	v_channel := coalesce(NEW.raw_user_meta_data ->> 'referral_channel', 'web');
	-- Never stored in the auth row, flag on or off.
	NEW.raw_user_meta_data := NEW.raw_user_meta_data - 'referral_code' - 'referral_channel';

	BEGIN
		PERFORM set_config('entrelares.signup_referral', '', true);
		-- A founder only (our form sends a role and no invite token): an
		-- invitee joins a family that already exists.
		IF public.setting_bool('feature.referral', false)
		   AND public.referral_code_is_shaped(v_code)
		   AND v_channel IN ('web', 'android')
		   AND NULLIF(btrim(coalesce(NEW.raw_user_meta_data ->> 'invite_token', '')), '') IS NULL
		   AND NULLIF(btrim(coalesce(NEW.raw_user_meta_data ->> 'role', '')), '') IS NOT NULL THEN
			PERFORM set_config('entrelares.signup_referral', v_code || ':' || v_channel, true);
		END IF;
	EXCEPTION WHEN OTHERS THEN
		NULL;
	END;

	RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.referral_attribute_on_signup()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	stash text;
	fam   bigint;
BEGIN
	stash := NULLIF(current_setting('entrelares.signup_referral', true), '');
	IF stash IS NULL THEN
		RETURN NULL;
	END IF;

	BEGIN
		PERFORM set_config('entrelares.signup_referral', '', true);

		SELECT p.family_id INTO fam
		  FROM public.profiles p
		  JOIN public.families f ON f.id = p.family_id
		 WHERE p.user_id = NEW.id
		   AND p.is_admin
		   AND p.left_at IS NULL
		   AND f.created_at >= timezone('utc', now()) - interval '24 hours';

		IF fam IS NOT NULL AND public.setting_bool('feature.referral', false) THEN
			PERFORM public.referral_attribute_family(
				fam, split_part(stash, ':', 1), split_part(stash, ':', 2));
		END IF;
	EXCEPTION WHEN OTHERS THEN
		-- A referral never costs a sign-up.
		NULL;
	END;

	RETURN NULL;
END;
$$;

ALTER FUNCTION public.referral_capture_on_signup() OWNER TO postgres;
ALTER FUNCTION public.referral_attribute_on_signup() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.referral_capture_on_signup() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.referral_attribute_on_signup() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_auth_user_referral_capture ON auth.users;
CREATE TRIGGER on_auth_user_referral_capture
	BEFORE INSERT OR UPDATE OF raw_user_meta_data ON auth.users
	FOR EACH ROW EXECUTE FUNCTION public.referral_capture_on_signup();

-- Same-event triggers fire in NAME order: `on_auth_user_created` (which runs
-- handle_new_user and creates the family) sorts before this one.
DROP TRIGGER IF EXISTS on_auth_user_created_referral ON auth.users;
CREATE TRIGGER on_auth_user_created_referral
	AFTER INSERT ON auth.users
	FOR EACH ROW EXECUTE FUNCTION public.referral_attribute_on_signup();


-- ── 9. T-99: the bulletin's `referrals` ──────────────────────────────────────
-- Body from 20261002190000; only the last key changes. The number is the
-- families attributed in the asked week (Monday..Sunday, São Paulo) — NULL
-- while the module is dark, so the e-mail says "not measured" and not "0".

CREATE OR REPLACE FUNCTION public.admin_weekly_sales_bulletin(p_week_start date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	today  date := (timezone('America/Sao_Paulo', now()))::date;
	w0     date;
	weeks  jsonb[] := ARRAY[]::jsonb[];
	trend  jsonb := '[]'::jsonb;
	i      int;
	wk     jsonb;
BEGIN
	-- Monday of the asked week; by default the week that just ended.
	w0 := COALESCE(date_trunc('week', p_week_start::timestamp)::date,
	               date_trunc('week', today::timestamp)::date - 7);

	-- weeks[1] = this week, weeks[2] = the one before, … weeks[4].
	FOR i IN 0..3 LOOP
		weeks := array_append(weeks, public.admin_weekly_sales_bulletin_week(w0 - 7 * i));
	END LOOP;

	-- Oldest first, the four main lines only.
	FOR i IN REVERSE 4..1 LOOP
		wk := weeks[i];
		trend := trend || jsonb_build_array(jsonb_build_object(
			'week_start',        wk -> 'week_start',
			'families_created',  wk -> 'families_created',
			'active_families',   wk -> 'active_families',
			'invitations_sent',  wk -> 'invitations_sent',
			'conversions_total', wk -> 'conversions' -> 'total'));
	END LOOP;

	RETURN jsonb_build_object(
		'report_version', 1,
		'generated_at',   now(),
		'week_start',     w0,
		'week_end',       w0 + 6,
		'this_week',      weeks[1],
		'previous_week',  weeks[2],
		'trend',          trend,
		'snapshot', jsonb_build_object(
			'families_total',  (SELECT count(*) FROM public.families),
			'paying_families', (SELECT count(*) FROM public.families f WHERE f.plan = 'premium'),
			'trials_ending_7d', (
				SELECT count(*) FROM public.families f
				 WHERE f.trial_ends_at > now()
				   AND f.trial_ends_at <= now() + interval '7 days'
				   AND f.plan <> 'premium'
				   AND f.comp_premium_at IS NULL
				   AND NOT EXISTS (
				       SELECT 1 FROM public.subscriptions s
				        WHERE s.family_id = f.id
				          AND s.status IN ('active', 'scheduled', 'overdue'))),
			'dunning', (SELECT count(*) FROM public.subscriptions s WHERE s.status = 'overdue')),
		-- F-80: families attributed to a referral in the week. NULL while
		-- `feature.referral` is off — the e-mail then says it is not measured.
		'referrals', CASE WHEN public.setting_bool('feature.referral', false) THEN (
			SELECT count(*) FROM public.family_referrals r
			 WHERE r.attributed_at >= (w0::timestamp AT TIME ZONE 'America/Sao_Paulo')
			   AND r.attributed_at <  ((w0 + 7)::timestamp AT TIME ZONE 'America/Sao_Paulo'))
		END
	);
END;
$$;

COMMENT ON FUNCTION public.admin_weekly_sales_bulletin(date) IS
	'T-99: the operator''s weekly sales bulletin (default: the week that just ended, Monday..Sunday São Paulo) vs the week before, a 4-week trend and a snapshot — counts, dates and closed enums only, never a name, an e-mail or a family id. `referrals` (F-80) is NULL while feature.referral is off. Service role only; read by the weekly-bulletin Edge Function.';

ALTER FUNCTION public.admin_weekly_sales_bulletin(date) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_weekly_sales_bulletin(date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_weekly_sales_bulletin(date) TO service_role;
