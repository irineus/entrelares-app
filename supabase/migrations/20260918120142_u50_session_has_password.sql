-- =============================================================================
-- U-50 — whether the CALLER's account has a password, answered by the only
-- party that can know.
--
-- WHY. The profile screen decided which sign-in doors to list, and whether the
-- "Senha" card exists at all, from `app_metadata.providers`: no `email` among
-- them was read as "this account has no password". Measured in production on
-- 10/09/2026 (S-21): an account whose providers are `["google"]` alone, whose
-- only row in `auth.identities` is `google`, and which nonetheless carries a
-- non-empty `encrypted_password`. The reverse can be built too (an invited
-- user signed in by magic link: the `email` provider, an empty column). So
-- "has a password" and "which providers" are INDEPENDENT facts, and the client
-- holds only the second. S-21 took the guess out of the sudo gate; this takes
-- it out of the screen.
--
-- WHAT `true` MEANS — AND DOES NOT. "A credential is stored", never "the
-- person knows one": GoTrue writes a RANDOM password when the Admin API
-- creates a user without one and when an invite link is redeemed (measured on
-- dev, 18/09/2026). For the screen that is the right side to err on — the
-- password sheet carries the reset-by-e-mail door, which turns an unknown
-- credential into a known one; "there is no password here" would hide it.
--
-- WHAT IT ANSWERS. One boolean, about `auth.uid()` and nobody else — the
-- function takes no argument on purpose, so there is no way to ask it about
-- another account. It leaks nothing: the caller already learns the same fact
-- by typing a password into the login form. The digest itself never leaves.
--
-- NOT A SECURITY INPUT. Nothing may branch a security decision on this answer:
-- the sudo sheet keeps offering both proofs to every session and `elevate`
-- keeps deciding (S-21). This exists so a screen can say something true.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.session_has_password()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO ''
AS $$
	SELECT COALESCE(
		(SELECT COALESCE(u.encrypted_password, '') <> ''
		 FROM auth.users u
		 WHERE u.id = auth.uid()),
		false
	);
$$;

ALTER FUNCTION public.session_has_password() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.session_has_password() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.session_has_password() FROM anon;
GRANT EXECUTE ON FUNCTION public.session_has_password() TO authenticated;
GRANT EXECUTE ON FUNCTION public.session_has_password() TO service_role;
