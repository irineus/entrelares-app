-- U-61 — the founder may name the child at sign-up (owner, 07/10/2026).
--
-- Step 2 of the founder's sign-up (and the Google onboarding) gains an
-- OPTIONAL "Primeiro nome da criança". It becomes the family's first
-- `children` row — F-55's entity, the one child datum the policy allows
-- (S-15: "o único campo próprio para dados da criança é o seu primeiro nome")
-- — and the app then says the name where it said "a criança".
--
-- Two doors, one writer:
--   · the e-mail sign-up has NO session until the address is confirmed, so the
--     name rides the signUp metadata like F-80's referral and T-101's source:
--     a BEFORE trigger on auth.users stashes it in a transaction-local GUC and
--     STRIPS the key — a child's name is never stored on the auth row;
--   · `complete_oauth_onboarding` (the Google door) takes it as a defaulted
--     parameter and stashes the same GUC before it inserts the family;
--   · an AFTER INSERT trigger on `families` reads the stash and writes the
--     child, so both doors share one rule: `feature.child_agenda` on (T-84 —
--     a dark module writes nothing), the name normalised by F-55's own
--     `child_normalize_name`, and an invalid name DROPPED with a warning, never
--     a refused account — the field is optional and the client validates it.
--
-- `created_by` is NULL on purpose: the founder's profile row is inserted after
-- the family's, and the column allows it (ON DELETE SET NULL).

-- ── 1. The e-mail sign-up: capture and strip ────────────────────────────────

CREATE OR REPLACE FUNCTION public.child_name_capture_on_signup()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	v_name text;
BEGIN
	IF TG_OP = 'INSERT' THEN
		BEGIN
			PERFORM set_config('entrelares.signup_child_first_name', '', true);
		EXCEPTION WHEN OTHERS THEN
			NULL;
		END;
	END IF;

	IF NEW.raw_user_meta_data IS NULL
	   OR NOT (NEW.raw_user_meta_data ? 'child_first_name') THEN
		RETURN NEW;
	END IF;

	v_name := NEW.raw_user_meta_data ->> 'child_first_name';
	-- Never stored in the auth row.
	NEW.raw_user_meta_data := NEW.raw_user_meta_data - 'child_first_name';

	IF TG_OP = 'UPDATE' THEN
		RETURN NEW;
	END IF;

	BEGIN
		-- A founder only (our form sends a role and no invite token): an
		-- invitee joins a family that already exists.
		IF NULLIF(btrim(coalesce(NEW.raw_user_meta_data ->> 'invite_token', '')), '') IS NULL
		   AND NULLIF(btrim(coalesce(NEW.raw_user_meta_data ->> 'role', '')), '') IS NOT NULL THEN
			PERFORM set_config('entrelares.signup_child_first_name', coalesce(v_name, ''), true);
		END IF;
	EXCEPTION WHEN OTHERS THEN
		NULL;
	END;

	RETURN NEW;
END;
$$;

ALTER FUNCTION public.child_name_capture_on_signup() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.child_name_capture_on_signup() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_auth_user_child_name_capture ON auth.users;
CREATE TRIGGER on_auth_user_child_name_capture
	BEFORE INSERT OR UPDATE OF raw_user_meta_data ON auth.users
	FOR EACH ROW EXECUTE FUNCTION public.child_name_capture_on_signup();


-- ── 2. The family is born: the stash becomes the first child ────────────────

CREATE OR REPLACE FUNCTION public.families_add_signup_child()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	stash  text;
	v_name text;
BEGIN
	BEGIN
		stash := NULLIF(current_setting('entrelares.signup_child_first_name', true), '');
		-- Consumed: a second family in the same transaction (none today) must
		-- not inherit it.
		PERFORM set_config('entrelares.signup_child_first_name', '', true);
	EXCEPTION WHEN OTHERS THEN
		stash := NULL;
	END;
	IF stash IS NULL THEN
		RETURN NEW;
	END IF;

	-- T-84: a dark module writes nothing, whatever the client sent.
	IF NOT public.setting_bool('feature.child_agenda', false) THEN
		RETURN NEW;
	END IF;

	-- F-55's own rule for the name (trimmed, collapsed, 1–40). An invalid
	-- name is an optional field gone wrong, never a refused account.
	BEGIN
		v_name := public.child_normalize_name(stash);
	EXCEPTION WHEN OTHERS THEN
		RAISE WARNING 'U-61: child first name at sign-up dropped for family %: %', NEW.id, SQLERRM;
		RETURN NEW;
	END;

	INSERT INTO public.children (family_id, first_name, sort_order, created_by)
	VALUES (NEW.id, v_name, 0, NULL)
	ON CONFLICT DO NOTHING;

	RETURN NEW;
END;
$$;

ALTER FUNCTION public.families_add_signup_child() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.families_add_signup_child() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS families_add_signup_child ON public.families;
CREATE TRIGGER families_add_signup_child
	AFTER INSERT ON public.families
	FOR EACH ROW EXECUTE FUNCTION public.families_add_signup_child();

COMMENT ON FUNCTION public.families_add_signup_child() IS
	'U-61: writes the first child a founder named at sign-up (stash entrelares.signup_child_first_name, set by child_name_capture_on_signup or complete_oauth_onboarding). Flag feature.child_agenda must be on; an invalid name is dropped with a WARNING, never refused.';


-- ── 3. The Google sign-in: complete_oauth_onboarding with one more word ─────
-- Body from 20261004120000 (T-101); the new parameter is DEFAULTED, so an
-- older build's four- or six-argument call still resolves, and the previous
-- signature is dropped so PostgREST never sees two candidates.

DROP FUNCTION IF EXISTS public.complete_oauth_onboarding(text, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.complete_oauth_onboarding(
	p_full_name            text,
	p_role                 text,
	p_family_name          text,
	p_policy_version       text,
	p_acquisition_source   text DEFAULT NULL,
	p_acquisition_campaign text DEFAULT NULL,
	p_child_first_name     text DEFAULT NULL
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

	-- U-61: the child's first name rides the same way; the families trigger
	-- (`families_add_signup_child`) writes it under F-55's rules.
	PERFORM set_config('entrelares.signup_child_first_name',
		coalesce(p_child_first_name, ''), true);

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

ALTER FUNCTION public.complete_oauth_onboarding(text, text, text, text, text, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.complete_oauth_onboarding(text, text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_oauth_onboarding(text, text, text, text, text, text, text) TO authenticated;

COMMENT ON FUNCTION public.complete_oauth_onboarding(text, text, text, text, text, text, text) IS
	'F-57: creates family + admin profile for an OAuth session whose profile was deferred by handle_new_user. Validates the policy version against policy.current_version (S-15) and refuses a caller who already has any profile row. T-101: records the family''s acquisition source (defaulted parameters; none = organic). U-61: an optional child first name becomes the family''s first child (families_add_signup_child).';
