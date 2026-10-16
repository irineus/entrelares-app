-- =============================================================================
-- T-101 (04/10/2026) — every new family records where it came from, and the
-- weekly bulletin reads the REAL cohort apart from the testers
--
-- WHY. The owner disclosed (04/10/2026) that every family so far is an
-- internal tester, and the first real cohort is bought by L-31's campaign
-- (Google app + Search + Meta, R$ 600 / 4 weeks) WITHOUT a pixel. So the
-- source is recorded on our side, ONCE, at family creation, from what the
-- existing doors already carry:
--   · Android: the Play Install Referrer (F-80's platform channel) — Google
--     Ads auto-tagging (`gclid`/`gbraid`) or our `utm_source`;
--   · web: `/register?src=<source>&cmp=<campaign>`;
--   · a referral code (`ref`) on either door wins.
-- The client decides with ONE pure rule (`AcquisitionRules`, core, with a test
-- per branch) and hands over a word and an optional campaign token; this file
-- re-checks both and owns the defaults.
--
-- THE COLUMNS. `families.acquisition_source` — closed vocabulary (the CHECK
-- below, mirrored word for word by `acquisition_rules_test`):
--   google_app · google_search · meta · referral · organic · unknown
-- and `families.acquisition_campaign` — our own short token, or NULL. Rows
-- created before this migration stay NULL: "not recorded". WRITTEN ONCE: a
-- BEFORE INSERT trigger fills them, a BEFORE UPDATE trigger refuses every
-- change, for every writer. No client writes `families` anyway (RLS grants
-- only SELECT; the family's own members may read their row).
--
-- HOW THE WORD REACHES THE INSERT. Both founder paths create the family inside
-- a server transaction, so the word rides a transaction-local setting
-- (`entrelares.signup_acquisition`), the F-80 stash shape:
--   · e-mail sign-up: the metadata keys `acquisition_source` /
--     `acquisition_campaign`, stripped from the auth row ALWAYS by a BEFORE
--     INSERT OR UPDATE trigger on auth.users (GoTrue writes its in-memory
--     metadata back — F-80's lesson), stashed only on the INSERT and only for
--     a founder; `handle_new_user` then inserts the family in the same
--     transaction;
--   · Google sign-in: `complete_oauth_onboarding` gains two DEFAULTED
--     parameters (an older Android build keeps calling it with four) and
--     stashes them before its own INSERT.
-- Precedence on the server: F-80's referral stash (set only for a shaped code
-- with `feature.referral` on) → `referral`; else the stashed word, or
-- `unknown` if it is not one of ours; no stash at all → `organic`. A
-- privileged writer (service role, the gate's fixtures) may name the source
-- itself — the same normalization applies.
--
-- THE REAL COHORT. `acquisition.real_cohort_start` (date, T-80 metadata,
-- default 2026-10-05): a family created on or after that day (São Paulo) is
-- the real cohort; before it, the internal test cohort. L-31 moves it to the
-- launch day by migration.
--
-- THE BULLETIN (T-99). A `real_cohort` block: per source, cumulative since the
-- start as of the run — families, created in the asked week, planned within 7
-- days, invited, an invitee joined, paid (a first paying billing event), and
-- the families they referred — plus the test cohort's totals apart. Counts
-- only: the campaign token is NOT in the e-mail (a stranger can put anything
-- in a URL; F-69's rule keeps free text out of an inbox).
--
-- POLICY (S-15/S-18 method, decided by the session as DISCLOSURE): the same
-- category (how the service is used, like T-78's channel), the same purpose
-- and basis (§4 "melhorar o Serviço", legitimate interest), no new operator
-- (Google Play already delivers the referrer, §7). The landing's §3 is edited
-- in the same campaign (L-46 PR) — it said the rest of the Install Referrer
-- was discarded; no version bump.
-- =============================================================================

-- ── 1. The real-cohort date ──────────────────────────────────────────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, help)
VALUES
	('acquisition.real_cohort_start', '2026-10-05', 'string', 'operator',
	 'Dia em que começa a primeira turma real de famílias (T-101); antes dele, a turma de teste.',
	 false, 'date', 'sensitive',
	 jsonb_build_object(
		'controls', 'A data (AAAA-MM-DD, horário de Brasília) a partir da qual uma família criada conta como turma real no boletim semanal, separada por origem; as criadas antes são a turma de teste.',
		'shown_at', jsonb_build_array('email'),
		'if_increased', 'Uma data mais tarde move famílias da turma real para a de teste no próximo boletim.',
		'if_decreased', 'Uma data mais cedo traz famílias de teste para a turma real e mistura os números.',
		'takes_effect', 'No próximo boletim (a função lê a chave a cada execução).',
		'caveats', 'Formato AAAA-MM-DD; outro formato é recusado. O L-31 ajusta para o dia do lançamento por migração.'))
ON CONFLICT (key) DO NOTHING;

-- Only a date is a date: every writer, the console included.
CREATE OR REPLACE FUNCTION public.app_settings_validate_cohort_start()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
	IF NEW.key = 'acquisition.real_cohort_start' THEN
		IF NEW.value !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
			RAISE EXCEPTION 'Valor inválido para %: use AAAA-MM-DD.', NEW.key
				USING ERRCODE = 'check_violation';
		END IF;
		BEGIN
			PERFORM NEW.value::date;
		EXCEPTION WHEN OTHERS THEN
			RAISE EXCEPTION 'Valor inválido para %: % não é uma data.', NEW.key, NEW.value
				USING ERRCODE = 'check_violation';
		END;
	END IF;
	RETURN NEW;
END;
$$;

ALTER FUNCTION public.app_settings_validate_cohort_start() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.app_settings_validate_cohort_start() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS app_settings_validate_cohort_start ON public.app_settings;
CREATE TRIGGER app_settings_validate_cohort_start
	BEFORE INSERT OR UPDATE OF value ON public.app_settings
	FOR EACH ROW EXECUTE FUNCTION public.app_settings_validate_cohort_start();

-- The reader: the key as a date, never an error.
CREATE OR REPLACE FUNCTION public.acquisition_real_cohort_start()
RETURNS date
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
	RETURN public.setting_text('acquisition.real_cohort_start', '2026-10-05')::date;
EXCEPTION WHEN OTHERS THEN
	RETURN DATE '2026-10-05';
END;
$$;

ALTER FUNCTION public.acquisition_real_cohort_start() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.acquisition_real_cohort_start() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.acquisition_real_cohort_start() TO service_role;


-- ── 2. The columns ───────────────────────────────────────────────────────────

ALTER TABLE public.families
	ADD COLUMN IF NOT EXISTS acquisition_source text
		CONSTRAINT families_acquisition_source_check
		CHECK (acquisition_source IN ('google_app', 'google_search', 'meta', 'referral', 'organic', 'unknown')),
	ADD COLUMN IF NOT EXISTS acquisition_campaign text
		CONSTRAINT families_acquisition_campaign_check
		CHECK (acquisition_campaign ~ '^[a-z0-9][a-z0-9_-]{0,39}$');

COMMENT ON COLUMN public.families.acquisition_source IS
	'T-101: where the family came from, recorded ONCE at creation (google_app, google_search, meta, referral, organic, unknown). NULL = created before T-101.';
COMMENT ON COLUMN public.families.acquisition_campaign IS
	'T-101: the ad campaign token (our own naming, ^[a-z0-9][a-z0-9_-]{0,39}$) when the source carried one. Never in the bulletin.';


-- ── 3. The normalizers (the client's rule, re-checked) ──────────────────────

CREATE OR REPLACE FUNCTION public.acquisition_source_word(p_source text)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $$
	SELECT CASE
		WHEN p_source IS NULL OR btrim(p_source) = '' THEN 'organic'
		WHEN lower(btrim(p_source)) IN ('google_app', 'google_search', 'meta', 'referral', 'organic', 'unknown')
			THEN lower(btrim(p_source))
		ELSE 'unknown'
	END;
$$;

CREATE OR REPLACE FUNCTION public.acquisition_campaign_token(p_campaign text)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $$
	SELECT CASE
		WHEN lower(btrim(coalesce(p_campaign, ''))) ~ '^[a-z0-9][a-z0-9_-]{0,39}$'
			THEN lower(btrim(p_campaign))
	END;
$$;

ALTER FUNCTION public.acquisition_source_word(text) OWNER TO postgres;
ALTER FUNCTION public.acquisition_campaign_token(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.acquisition_source_word(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.acquisition_campaign_token(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.acquisition_source_word(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.acquisition_campaign_token(text) TO service_role;


-- ── 4. Write once: stamped on INSERT, frozen on UPDATE ──────────────────────

CREATE OR REPLACE FUNCTION public.families_stamp_acquisition()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	stash    text;
	referral text;
BEGIN
	BEGIN
		stash    := NULLIF(current_setting('entrelares.signup_acquisition', true), '');
		referral := NULLIF(current_setting('entrelares.signup_referral', true), '');
		-- Used once: a second family in the same transaction starts clean.
		PERFORM set_config('entrelares.signup_acquisition', '', true);

		IF NEW.acquisition_source IS NOT NULL THEN
			-- A privileged writer named it (service role, the gate's fixtures).
			NEW.acquisition_source   := public.acquisition_source_word(NEW.acquisition_source);
			NEW.acquisition_campaign := public.acquisition_campaign_token(NEW.acquisition_campaign);
		ELSIF referral IS NOT NULL THEN
			-- F-80's stash exists only for a shaped code with the module on.
			NEW.acquisition_source   := 'referral';
			NEW.acquisition_campaign := NULL;
		ELSIF stash IS NOT NULL THEN
			NEW.acquisition_source   := public.acquisition_source_word(split_part(stash, ':', 1));
			NEW.acquisition_campaign := public.acquisition_campaign_token(NULLIF(split_part(stash, ':', 2), ''));
		ELSE
			NEW.acquisition_source   := 'organic';
			NEW.acquisition_campaign := NULL;
		END IF;
	EXCEPTION WHEN OTHERS THEN
		-- A measurement never costs a sign-up.
		NEW.acquisition_source   := 'unknown';
		NEW.acquisition_campaign := NULL;
	END;
	RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.families_freeze_acquisition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
	IF NEW.acquisition_source IS DISTINCT FROM OLD.acquisition_source
	   OR NEW.acquisition_campaign IS DISTINCT FROM OLD.acquisition_campaign THEN
		RAISE EXCEPTION 'A origem da família é registrada uma vez, na criação, e não muda.'
			USING ERRCODE = 'check_violation';
	END IF;
	RETURN NEW;
END;
$$;

ALTER FUNCTION public.families_stamp_acquisition() OWNER TO postgres;
ALTER FUNCTION public.families_freeze_acquisition() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.families_stamp_acquisition() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.families_freeze_acquisition() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS families_stamp_acquisition ON public.families;
CREATE TRIGGER families_stamp_acquisition
	BEFORE INSERT ON public.families
	FOR EACH ROW EXECUTE FUNCTION public.families_stamp_acquisition();

DROP TRIGGER IF EXISTS families_freeze_acquisition ON public.families;
CREATE TRIGGER families_freeze_acquisition
	BEFORE UPDATE OF acquisition_source, acquisition_campaign ON public.families
	FOR EACH ROW EXECUTE FUNCTION public.families_freeze_acquisition();


-- ── 5. The e-mail sign-up: capture and strip ────────────────────────────────

CREATE OR REPLACE FUNCTION public.acquisition_capture_on_signup()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	v_source   text;
	v_campaign text;
BEGIN
	IF TG_OP = 'INSERT' THEN
		BEGIN
			PERFORM set_config('entrelares.signup_acquisition', '', true);
		EXCEPTION WHEN OTHERS THEN
			NULL;
		END;
	END IF;

	IF NEW.raw_user_meta_data IS NULL
	   OR NOT (NEW.raw_user_meta_data ? 'acquisition_source'
	           OR NEW.raw_user_meta_data ? 'acquisition_campaign') THEN
		RETURN NEW;
	END IF;

	v_source   := NEW.raw_user_meta_data ->> 'acquisition_source';
	v_campaign := NEW.raw_user_meta_data ->> 'acquisition_campaign';
	-- Never stored in the auth row.
	NEW.raw_user_meta_data := NEW.raw_user_meta_data - 'acquisition_source' - 'acquisition_campaign';

	IF TG_OP = 'UPDATE' THEN
		RETURN NEW;
	END IF;

	BEGIN
		-- A founder only (our form sends a role and no invite token): an
		-- invitee joins a family that already exists.
		IF NULLIF(btrim(coalesce(NEW.raw_user_meta_data ->> 'invite_token', '')), '') IS NULL
		   AND NULLIF(btrim(coalesce(NEW.raw_user_meta_data ->> 'role', '')), '') IS NOT NULL THEN
			PERFORM set_config('entrelares.signup_acquisition',
				public.acquisition_source_word(v_source) || ':'
				|| coalesce(public.acquisition_campaign_token(v_campaign), ''), true);
		END IF;
	EXCEPTION WHEN OTHERS THEN
		NULL;
	END;

	RETURN NEW;
END;
$$;

ALTER FUNCTION public.acquisition_capture_on_signup() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.acquisition_capture_on_signup() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_auth_user_acquisition_capture ON auth.users;
CREATE TRIGGER on_auth_user_acquisition_capture
	BEFORE INSERT OR UPDATE OF raw_user_meta_data ON auth.users
	FOR EACH ROW EXECUTE FUNCTION public.acquisition_capture_on_signup();


-- ── 6. The Google sign-in: complete_oauth_onboarding with two more words ────
-- Body from 20260827120000 (never redefined since); the two new parameters
-- are DEFAULTED, so an older build's four-argument call still resolves, and
-- the old signature is dropped so PostgREST never sees two candidates.

DROP FUNCTION IF EXISTS public.complete_oauth_onboarding(text, text, text, text);

CREATE OR REPLACE FUNCTION public.complete_oauth_onboarding(
	p_full_name            text,
	p_role                 text,
	p_family_name          text,
	p_policy_version       text,
	p_acquisition_source   text DEFAULT NULL,
	p_acquisition_campaign text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	uid         uuid := auth.uid();
	user_email  text;
	expected    text;
	the_name    text;
	new_role_id bigint;
	fam_id      bigint;
BEGIN
	IF uid IS NULL THEN
		RAISE EXCEPTION 'Sessão não autenticada.' USING ERRCODE = '42501';
	END IF;

	-- profiles has no UNIQUE on user_id (the trigger's EXISTS check covers the
	-- normal path), so serialize per user: a double-tap must not create two
	-- families.
	PERFORM pg_advisory_xact_lock(hashtext(uid::text));

	IF EXISTS (SELECT 1 FROM public.profiles WHERE user_id = uid) THEN
		RAISE EXCEPTION 'Esta conta já está vinculada a uma família.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- S-15 posture: never stamp a consent the client cannot prove it displayed.
	expected := public.setting_text('policy.current_version', NULL::text);
	IF expected IS NULL THEN
		RAISE EXCEPTION 'Configuração policy.current_version ausente — aceite não pode ser registrado.'
			USING ERRCODE = 'P0002';
	END IF;
	IF p_policy_version IS DISTINCT FROM expected THEN
		RAISE EXCEPTION 'Versão da política desatualizada (enviada: %, vigente: %). Atualize o aplicativo.',
			coalesce(p_policy_version, '(nula)'), expected USING ERRCODE = '22023';
	END IF;

	-- F-27/F-41: catalog lookup, built-ins only (a founder has no family).
	SELECT id INTO new_role_id
	FROM public.roles
	WHERE family_id IS NULL
	  AND (lower(trim(role)) = lower(p_role)
	    OR lower(trim(label_pt)) = lower(p_role))
	ORDER BY id
	LIMIT 1;
	IF new_role_id IS NULL THEN
		RAISE EXCEPTION 'Papel inválido: %.', coalesce(p_role, '(nulo)')
			USING ERRCODE = 'check_violation';
	END IF;

	SELECT email INTO user_email FROM auth.users WHERE id = uid;
	the_name := COALESCE(NULLIF(trim(p_full_name), ''), split_part(user_email, '@', 1));

	-- T-101: the family's source rides the stash into the INSERT below; no
	-- word from the client (an older build) is `organic`.
	PERFORM set_config('entrelares.signup_acquisition',
		CASE WHEN p_acquisition_source IS NULL THEN ''
		     ELSE public.acquisition_source_word(p_acquisition_source) || ':'
		          || coalesce(public.acquisition_campaign_token(p_acquisition_campaign), '')
		END, true);

	INSERT INTO public.families (name)
	VALUES (COALESCE(NULLIF(trim(p_family_name), ''), 'Família ' || the_name))
	RETURNING id INTO fam_id;

	-- Founder = admin, color slot 1, consent stamped at creation — the exact
	-- shape handle_new_user's founder branch produces.
	INSERT INTO public.profiles (user_id, full_name, role_id, email, family_id, is_admin, color_slot,
	                             consent_accepted_at, consent_policy_version)
	VALUES (uid, the_name, new_role_id, user_email, fam_id, true, 1,
	        timezone('utc', now()), expected);
END;
$$;

ALTER FUNCTION public.complete_oauth_onboarding(text, text, text, text, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.complete_oauth_onboarding(text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_oauth_onboarding(text, text, text, text, text, text) TO authenticated;

COMMENT ON FUNCTION public.complete_oauth_onboarding(text, text, text, text, text, text) IS
	'F-57: creates family + admin profile for an OAuth session whose profile was deferred by handle_new_user. Validates the policy version against policy.current_version (S-15) and refuses a caller who already has any profile row. T-101: records the family''s acquisition source (defaulted parameters; none = organic).';


-- ── 7. The bulletin's real-cohort block ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_weekly_sales_bulletin_cohort(p_week_start date)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	start  date := public.acquisition_real_cohort_start();
	cut    timestamp with time zone := (start::timestamp AT TIME ZONE 'America/Sao_Paulo');
	lo     timestamp with time zone := (p_week_start::timestamp AT TIME ZONE 'America/Sao_Paulo');
	hi     timestamp with time zone := ((p_week_start + 7)::timestamp AT TIME ZONE 'America/Sao_Paulo');
	result jsonb;
BEGIN
	WITH
	fam AS (
		SELECT f.id,
		       f.created_at >= cut AS is_real,
		       coalesce(f.acquisition_source, 'unknown') AS source,
		       (f.created_at >= lo AND f.created_at < hi) AS in_week,
		       EXISTS (SELECT 1 FROM public.care_schedules cs
		                WHERE cs.family_id = f.id
		                  AND cs.created_at < f.created_at + interval '7 days') AS planned,
		       EXISTS (SELECT 1 FROM public.family_invitations i
		                WHERE i.family_id = f.id) AS invited,
		       EXISTS (SELECT 1 FROM public.family_invitations i
		                WHERE i.family_id = f.id AND i.accepted_at IS NOT NULL) AS joined,
		       EXISTS (SELECT 1 FROM public.billing_events e
		                WHERE e.family_id = f.id
		                  AND e.event_type IN ('PAYMENT_CONFIRMED', 'PAYMENT_RECEIVED',
		                                       'PLAY_PURCHASE_VERIFIED',
		                                       'PLAY_RTDN_1', 'PLAY_RTDN_2', 'PLAY_RTDN_4', 'PLAY_RTDN_7')) AS paid,
		       (SELECT count(*) FROM public.family_referrals r
		         WHERE r.referrer_family_id = f.id) AS referred
		  FROM public.families f
	),
	src(source) AS (
		VALUES ('google_app'), ('google_search'), ('meta'), ('referral'), ('organic'), ('unknown')
	)
	SELECT jsonb_build_object(
		'start', start,
		'by_source', (
			SELECT jsonb_object_agg(t.source, t.stats)
			  FROM (
				SELECT s.source, jsonb_build_object(
					'families',        count(f.id),
					'created_week',    count(f.id) FILTER (WHERE f.in_week),
					'planned_7d',      count(f.id) FILTER (WHERE f.planned),
					'invited',         count(f.id) FILTER (WHERE f.invited),
					'invitee_joined',  count(f.id) FILTER (WHERE f.joined),
					'paid',            count(f.id) FILTER (WHERE f.paid),
					'referred_others', coalesce(sum(f.referred), 0)) AS stats
				  FROM src s
				  LEFT JOIN fam f ON f.source = s.source AND f.is_real
				 GROUP BY s.source) t),
		'test_cohort', (
			SELECT jsonb_build_object(
				'families',        count(*),
				'planned_7d',      count(*) FILTER (WHERE planned),
				'invited',         count(*) FILTER (WHERE invited),
				'invitee_joined',  count(*) FILTER (WHERE joined),
				'paid',            count(*) FILTER (WHERE paid),
				'referred_others', coalesce(sum(referred), 0))
			  FROM fam WHERE NOT is_real)
	) INTO result;

	RETURN result;
END;
$$;

COMMENT ON FUNCTION public.admin_weekly_sales_bulletin_cohort(date) IS
	'T-101: the bulletin''s real-cohort block — per acquisition source, cumulative since acquisition.real_cohort_start (São Paulo), plus the test cohort apart. Counts only, no campaign token. Service role only.';

ALTER FUNCTION public.admin_weekly_sales_bulletin_cohort(date) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_weekly_sales_bulletin_cohort(date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_weekly_sales_bulletin_cohort(date) TO service_role;

-- Body from 20261002200000 (F-80); only `real_cohort` is new.
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
		END,
		-- T-101: the real cohort per source, and the testers apart.
		'real_cohort', public.admin_weekly_sales_bulletin_cohort(w0)
	);
END;
$$;

COMMENT ON FUNCTION public.admin_weekly_sales_bulletin(date) IS
	'T-99: the operator''s weekly sales bulletin (default: the week that just ended, Monday..Sunday São Paulo) vs the week before, a 4-week trend and a snapshot — counts, dates and closed enums only, never a name, an e-mail or a family id. `referrals` (F-80) is NULL while feature.referral is off; `real_cohort` (T-101) splits the families by acquisition source since acquisition.real_cohort_start. Service role only; read by the weekly-bulletin Edge Function.';

ALTER FUNCTION public.admin_weekly_sales_bulletin(date) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_weekly_sales_bulletin(date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_weekly_sales_bulletin(date) TO service_role;
