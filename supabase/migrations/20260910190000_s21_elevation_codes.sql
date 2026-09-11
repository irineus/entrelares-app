-- =============================================================================
-- S-21 — a second way to prove freshness for the S-10 sudo gate: a one-time
-- code sent to the account's e-mail.
--
-- WHY. `elevate` proves identity by verifying the CURRENT PASSWORD through
-- GoTrue's password grant. A session that signed in with Google has no password
-- to verify, so every sudo-gated operation — leaving the family, cancelling
-- one's own departure, requesting / withdrawing / executing a family deletion,
-- changing admin permissions, the F-58 operator console and
-- admin-update-member-email — was unreachable for it. Measured in production on
-- 10/09/2026: four accounts with no password at all, three of them the SOLE
-- ADMIN of a one-seat family, i.e. people who could not delete their own
-- account by any in-app path. That is the Play deletion-policy requirement of
-- T-59, not an inconvenience.
--
-- WHAT THIS IS NOT. The S-10 rule is untouched: a sensitive action still needs
-- a fresh proof of identity, and `is_elevated()` is still the only thing the
-- gated RPCs consult. This changes what counts as proof, never whether one is
-- required. The code is not a weaker door than the ones already standing: the
-- address it goes to is the same one `resetPasswordForEmail` already mails a
-- full account takeover to, and for a Google session it is the address that
-- owns the Google account itself.
--
-- SHAPE. One row per user (PK), so asking for a new code REPLACES the previous
-- one — an old code in an old e-mail stops working the moment a new one is
-- asked for. The table never sees the code itself: `elevate` hashes it with the
-- user id as salt and stores only the digest, so a leaked backup or log line
-- carries nothing redeemable.
--
-- The two RPCs exist instead of plain PostgREST writes because both operations
-- are compare-and-set: counting a failed attempt and consuming a good code have
-- to happen in ONE statement, or two parallel guesses each see `attempts = 0`.
-- They are service_role only — `elevate` is the sole caller, and it is the only
-- thing that knows the plaintext.
--
-- The TTL, the attempt ceiling and the resend interval are NOT here on purpose:
-- they live as named constants in `supabase/functions/elevate/index.ts`, which
-- passes them in. One place for the numbers, and it is the place the client's
-- mirror test reads.
--
-- purge_e2e_family needs NO change: auth_elevation_codes.user_id cascades when
-- the Admin API deletes auth.users, exactly as auth_elevations does.
-- =============================================================================

-- ── 1. auth_elevation_codes ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.auth_elevation_codes (
	user_id     uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
	code_hash   text NOT NULL,
	expires_at  timestamp with time zone NOT NULL,
	attempts    smallint NOT NULL DEFAULT 0,
	created_at  timestamp with time zone DEFAULT timezone('utc', now()) NOT NULL
);

ALTER TABLE public.auth_elevation_codes OWNER TO postgres;
ALTER TABLE public.auth_elevation_codes ENABLE ROW LEVEL SECURITY;

-- No policies at all, deliberately: service_role bypasses RLS and is the only
-- caller. An end user must never read the digest of their own pending code —
-- the code is something they RECEIVE, not something they look up.
REVOKE ALL ON TABLE public.auth_elevation_codes FROM PUBLIC;
REVOKE ALL ON TABLE public.auth_elevation_codes FROM anon;
REVOKE ALL ON TABLE public.auth_elevation_codes FROM authenticated;
GRANT ALL ON TABLE public.auth_elevation_codes TO service_role;

-- ── 2. request_elevation_code ────────────────────────────────────────────────
-- Stores a freshly minted digest, unless the previous one is still young — that
-- throttle is what stops a loop from spending the Resend allowance (and filling
-- somebody's inbox) one request at a time.
--
-- Returns the expiry so the caller can tell the user how long the code lasts,
-- and 'throttled' with the EXISTING expiry when it refused: the old code is
-- still valid, so the honest answer is "you already have one, it runs out at".

CREATE OR REPLACE FUNCTION public.request_elevation_code(
	p_user_id               uuid,
	p_code_hash             text,
	p_ttl_seconds           integer,
	p_min_interval_seconds  integer
)
RETURNS TABLE (status text, expires_at timestamp with time zone)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	existing public.auth_elevation_codes%ROWTYPE;
	v_expires timestamp with time zone;
BEGIN
	SELECT * INTO existing
	FROM public.auth_elevation_codes
	WHERE user_id = p_user_id
	FOR UPDATE;

	IF existing.user_id IS NOT NULL
	   AND existing.expires_at > timezone('utc', now())
	   AND existing.created_at > timezone('utc', now()) - make_interval(secs => p_min_interval_seconds)
	THEN
		RETURN QUERY SELECT 'throttled'::text, existing.expires_at;
		RETURN;
	END IF;

	v_expires := timezone('utc', now()) + make_interval(secs => p_ttl_seconds);

	INSERT INTO public.auth_elevation_codes AS c (user_id, code_hash, expires_at, attempts, created_at)
	VALUES (p_user_id, p_code_hash, v_expires, 0, timezone('utc', now()))
	ON CONFLICT (user_id) DO UPDATE
		SET code_hash  = EXCLUDED.code_hash,
		    expires_at = EXCLUDED.expires_at,
		    attempts   = 0,
		    created_at = EXCLUDED.created_at;

	RETURN QUERY SELECT 'ok'::text, v_expires;
END;
$$;

ALTER FUNCTION public.request_elevation_code(uuid, text, integer, integer) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.request_elevation_code(uuid, text, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.request_elevation_code(uuid, text, integer, integer) FROM anon;
REVOKE ALL ON FUNCTION public.request_elevation_code(uuid, text, integer, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.request_elevation_code(uuid, text, integer, integer) TO service_role;

-- ── 3. consume_elevation_code ────────────────────────────────────────────────
-- The whole verdict in one statement. Status vocabulary, and why each is its
-- own answer rather than a shared "invalid":
--
--   'none'    — nothing was ever asked for. The caller says "ask for a code",
--               not "wrong code", or the user retypes forever.
--   'expired' — there WAS one and it ran out; same sentence as 'none' to the
--               user, different line in the logs.
--   'locked'  — the attempt ceiling was reached. The row is destroyed with the
--               verdict, so the next step is necessarily a new code.
--   'invalid' — a real wrong guess. This is the only one that spends an attempt.
--   'ok'      — consumed. The row is deleted here, so a code is single-use even
--               if the caller is interrupted before it writes the elevation.

CREATE OR REPLACE FUNCTION public.consume_elevation_code(
	p_user_id   uuid,
	p_code_hash text
)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	existing public.auth_elevation_codes%ROWTYPE;
	v_max_attempts CONSTANT smallint := 3;
BEGIN
	SELECT * INTO existing
	FROM public.auth_elevation_codes
	WHERE user_id = p_user_id
	FOR UPDATE;

	IF existing.user_id IS NULL THEN
		RETURN 'none';
	END IF;

	IF existing.expires_at <= timezone('utc', now()) THEN
		DELETE FROM public.auth_elevation_codes WHERE user_id = p_user_id;
		RETURN 'expired';
	END IF;

	IF existing.code_hash = p_code_hash THEN
		DELETE FROM public.auth_elevation_codes WHERE user_id = p_user_id;
		RETURN 'ok';
	END IF;

	-- A wrong guess. Count it, and destroy the code once the ceiling is hit —
	-- leaving a locked row behind would only make the next verdict ambiguous.
	IF existing.attempts + 1 >= v_max_attempts THEN
		DELETE FROM public.auth_elevation_codes WHERE user_id = p_user_id;
		RETURN 'locked';
	END IF;

	UPDATE public.auth_elevation_codes
	SET attempts = attempts + 1
	WHERE user_id = p_user_id;

	RETURN 'invalid';
END;
$$;

ALTER FUNCTION public.consume_elevation_code(uuid, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.consume_elevation_code(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.consume_elevation_code(uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.consume_elevation_code(uuid, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.consume_elevation_code(uuid, text) TO service_role;
