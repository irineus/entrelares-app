-- =============================================================================
-- F-55 (PR 1) — the child entity, born multi-child
--
-- The product had no child at all: the only child datum was a free text field
-- typed into the PDF form (F-07's missing half). The agenda (F-55 PR 2) hangs
-- per-child events off a real row, so the row comes first, already shaped for
-- more than one child even though v1 renders one (owner, 24/09/2026 — building
-- the agenda on a hard-coded single child is the rework F-07 warns about).
--
-- Decisions locked with the owner (24/09/2026):
--   · ONLY the first name and an order. No surname, no birth date, no photo:
--     the minimum the agenda and the PDF need, and the minimum a policy has to
--     disclose (S-22 writes that sentence).
--   · ONLY an admin registers, renames or removes a child, and only through
--     these RPCs — the table has no client write grant at all.
--   · The whole phase-6 module ships DARK: `feature.child_agenda` is seeded
--     FALSE here, turned on in the dev project only, and S-22 flips it in
--     production. With the flag off the server refuses every write (the client
--     only hides); reads stay open, so a kill switch never loses data.
--   · Not Premium: the child is the anchor of the free "Nota" too (PR 2 gates
--     the structured events, not the entity).
--
-- Nothing here touches care_schedules, the day protections or activity_logs.
-- =============================================================================

-- ── 1. The feature flag (T-84 catalogue: `feature.child_agenda`) ────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, help)
VALUES
	('feature.child_agenda', 'false', 'bool', 'features',
	 'Liga a agenda da criança (F-55): o cadastro da criança e os eventos do dia. Desligado, o módulo some do app e o servidor recusa as escritas.',
	 true, 'flag', 'critical',
	 jsonb_build_object(
		'controls', 'Se o app mostra o cadastro da criança (Família → Criança) e a agenda do dia, e se add_child / rename_child / remove_child (e, a partir do PR 2, os eventos) aceitam escrever.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Ligado: o admin de toda família vê a linha Criança na Família e pode cadastrar a criança; o PDF passa a usar o nome cadastrado.',
		'if_decreased', 'Desligado (chave de emergência): o módulo some do app e toda escrita é recusada no servidor. Os dados já gravados FICAM e voltam a aparecer quando a chave for religada.',
		'takes_effect', 'Servidor na próxima escrita; app na próxima abertura da tela.',
		'caveats', 'Nasce DESLIGADO em produção (lançamento escuro da fase 6). Ligar em produção é o S-22, junto com a política nova e a conversão das observações — nunca antes, ou as famílias veem um módulo que a política ainda não descreve.',
		'requires', 'A política de privacidade da versão do S-22 publicada (o nome da criança é dado novo).'))
ON CONFLICT (key) DO NOTHING;


-- ── 2. The table ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.children (
	id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	family_id   bigint NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
	-- The first name only, trimmed, 1–40 characters (the RPCs normalise; the
	-- CHECK is the floor for any other writer, service role included).
	first_name  text   NOT NULL
	            CHECK (first_name = btrim(first_name)
	                   AND char_length(first_name) BETWEEN 1 AND 40),
	-- Display order; v1 shows one child, the order is what a selector will
	-- read once F-07 completes the multi-child UI.
	sort_order  int    NOT NULL DEFAULT 0,
	created_at  timestamptz NOT NULL DEFAULT now(),
	created_by  bigint REFERENCES public.profiles(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS children_family_idx ON public.children (family_id, sort_order);
-- Two children of one family never share a name — a picker could not tell
-- them apart, and the agenda would put an event under the wrong one.
CREATE UNIQUE INDEX IF NOT EXISTS children_family_name_key
	ON public.children (family_id, lower(first_name));

ALTER TABLE public.children ENABLE ROW LEVEL SECURITY;

-- Reads: my own family only. anon reads nothing (T-44: no table grant).
DROP POLICY IF EXISTS children_family_read ON public.children;
CREATE POLICY children_family_read ON public.children
	FOR SELECT TO authenticated
	USING (family_id = public.get_my_family_id());

-- Writes: none from any client. Only the SECURITY DEFINER RPCs below write.
REVOKE ALL ON public.children FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.children TO authenticated;
GRANT ALL ON public.children TO service_role;


-- ── 3. The shared guard ─────────────────────────────────────────────────────
-- Flag on, caller an active admin with an account. Returns the caller's row.

CREATE OR REPLACE FUNCTION public.child_admin_guard()
RETURNS public.profiles
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me public.profiles%ROWTYPE;
BEGIN
	IF NOT public.setting_bool('feature.child_agenda', false) THEN
		RAISE EXCEPTION 'A agenda da criança ainda não está disponível.'
			USING ERRCODE = 'feature_not_supported';
	END IF;

	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();

	-- A departed member (S-11) acts on nothing; a pending one (F-56) has no
	-- account to call with. Only an admin manages the family's children.
	IF me.id IS NULL OR me.left_at IS NOT NULL OR NOT me.is_admin THEN
		RAISE EXCEPTION 'Somente administradores da família podem cadastrar, renomear ou remover a criança.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	RETURN me;
END;
$$;

ALTER FUNCTION public.child_admin_guard() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.child_admin_guard() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.child_admin_guard() TO service_role;

-- The name rule, in one place (mirrored by `ChildRules.validateName`, core).
CREATE OR REPLACE FUNCTION public.child_normalize_name(p_first_name text)
RETURNS text
LANGUAGE plpgsql IMMUTABLE
SET search_path TO 'public'
AS $$
DECLARE
	v text := regexp_replace(btrim(coalesce(p_first_name, '')), '\s+', ' ', 'g');
BEGIN
	IF v = '' THEN
		RAISE EXCEPTION 'Informe o primeiro nome da criança.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF char_length(v) > 40 THEN
		RAISE EXCEPTION 'O nome da criança pode ter no máximo 40 caracteres.'
			USING ERRCODE = 'check_violation';
	END IF;
	RETURN v;
END;
$$;

ALTER FUNCTION public.child_normalize_name(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.child_normalize_name(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.child_normalize_name(text) TO service_role;


-- ── 4. add_child ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.add_child(p_first_name text)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me     public.profiles%ROWTYPE := public.child_admin_guard();
	v_name text := public.child_normalize_name(p_first_name);
	new_id bigint;
BEGIN
	IF EXISTS (SELECT 1 FROM public.children
	           WHERE family_id = me.family_id AND lower(first_name) = lower(v_name)) THEN
		RAISE EXCEPTION 'Já existe uma criança com esse nome na família.'
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


-- ── 5. rename_child ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.rename_child(p_child_id bigint, p_first_name text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me     public.profiles%ROWTYPE := public.child_admin_guard();
	v_name text := public.child_normalize_name(p_first_name);
BEGIN
	IF NOT EXISTS (SELECT 1 FROM public.children
	               WHERE id = p_child_id AND family_id = me.family_id) THEN
		RAISE EXCEPTION 'Criança não encontrada na sua família.'
			USING ERRCODE = 'no_data_found';
	END IF;

	IF EXISTS (SELECT 1 FROM public.children
	           WHERE family_id = me.family_id AND id <> p_child_id
	             AND lower(first_name) = lower(v_name)) THEN
		RAISE EXCEPTION 'Já existe uma criança com esse nome na família.'
			USING ERRCODE = 'check_violation';
	END IF;

	UPDATE public.children SET first_name = v_name
	WHERE id = p_child_id AND family_id = me.family_id;
END;
$$;

ALTER FUNCTION public.rename_child(bigint, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.rename_child(bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rename_child(bigint, text) TO authenticated, service_role;


-- ── 6. remove_child ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.remove_child(p_child_id bigint)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me public.profiles%ROWTYPE := public.child_admin_guard();
BEGIN
	DELETE FROM public.children
	WHERE id = p_child_id AND family_id = me.family_id;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'Criança não encontrada na sua família.'
			USING ERRCODE = 'no_data_found';
	END IF;
END;
$$;

ALTER FUNCTION public.remove_child(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.remove_child(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_child(bigint) TO authenticated, service_role;
