-- S-27 (T-103 audit, 04/10/2026; owner, 07/10/2026) — a viewer no longer reads
-- the other members' e-mail.
--
-- `profiles_family_read` let every member of the family — viewers included —
-- SELECT every row of `profiles`, `email` included. In a high-conflict
-- separation the ex's new partner, invited as a viewer, got the other
-- parent's address. Column privileges are per ROLE, not per row, so the
-- column cannot be hidden from viewers alone; the rows can:
--
--   · `profiles_viewer_own_row` — a RESTRICTIVE select policy: a viewer reads
--     their OWN row of `profiles` directly and no other.
--   · `family_members()` — the family's rows as the app reads them
--     (`to_jsonb` of the row, the same shape as `select *`), SECURITY
--     DEFINER, with `email` NULL on every row but the caller's own when the
--     caller is a viewer. Full members read exactly what they read before.
--
-- The policy uses `is_viewer_caller()` (F-50, SECURITY DEFINER), which reads
-- `profiles` itself without recursing into this policy.

DROP POLICY IF EXISTS profiles_viewer_own_row ON public.profiles;
CREATE POLICY profiles_viewer_own_row ON public.profiles
	AS RESTRICTIVE FOR SELECT TO authenticated
	USING (NOT public.is_viewer_caller() OR user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.family_members()
RETURNS SETOF jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me     public.profiles%ROWTYPE;
	viewer boolean;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();
	IF me.id IS NULL THEN
		RETURN;
	END IF;
	viewer := me.membership_type = 'viewer' AND me.left_at IS NULL;

	RETURN QUERY
	SELECT CASE
	         WHEN viewer AND p.id <> me.id THEN to_jsonb(p) || jsonb_build_object('email', NULL)
	         ELSE to_jsonb(p)
	       END
	  FROM public.profiles p
	 WHERE p.family_id = me.family_id
	    OR p.id = me.id
	 ORDER BY p.id;
END;
$$;

ALTER FUNCTION public.family_members() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.family_members() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.family_members() TO authenticated, service_role;

COMMENT ON FUNCTION public.family_members() IS
	'S-27: the family''s profiles rows as the app reads them; a viewer gets email NULL on every row but their own (profiles_viewer_own_row keeps the direct read to their own row).';
