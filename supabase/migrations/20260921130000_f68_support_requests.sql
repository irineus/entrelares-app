-- =============================================================================
-- F-68 — Help & contact: the record behind every message sent from the app.
--
-- WHY. Family 19 (19/09/2026) tried to record a past-day fact through a channel
-- that could not carry it, gave up twice and had nobody to ask: the app had no
-- help screen, no mailto, no form. The product learned about it only because
-- the owner happened to read the database. `send-support-request` is the door;
-- this table is what it writes before it e-mails the team.
--
-- WHAT THE ROW IS FOR. The team READS requests in the inbox (owner, 21/09/2026 —
-- a console tab is F-69's). The row exists for two things only:
--   · the RATE LIMIT, counted here rather than in a second store, so the count
--     and the insert are one transaction (`record_support_request`);
--   · the request NUMBER printed in both e-mails, so a reply can name it.
--
-- SHAPE. `reply_email` is always the address the answer goes to: typed by the
-- person when signed out, the account's own when signed in (the function reads
-- it server-side; the client never chooses it). `ip_hash` is an HMAC of the
-- caller's IP under the project's secret key — never the IP itself — and only
-- for the signed-out path, which is the only one limited by it.
-- `diagnostics` holds what the person ALLOWED on the form (version, channel,
-- OS/browser family, language, route) and nothing else: the function keeps a
-- fixed list of keys and drops the rest.
--
-- `status`: `open` on arrival; `undelivered` when the e-mail to the team failed
-- (the person is told to use the mailto instead, and the row stops counting
-- against their limit so a retry is possible); `closed` is for F-69's console.
--
-- ACCESS. Service role only — no policy, no grant to `anon`/`authenticated`,
-- the `auth_elevation_codes` shape. A message to support can carry things a
-- person would not say to the other caregivers of their own family, so not even
-- the family reads it.
--
-- RETENTION. 12 months, by `purge_old_support_requests()` in the daily
-- `purge-deleted` pass. `profile_id`/`family_id` are SET NULL when the account
-- or family goes: the request outlives its author only for that window, and
-- the policy (§3 of privacidade.html) says so.
-- =============================================================================

-- ── 1. support_requests ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.support_requests (
	id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	created_at   timestamp with time zone DEFAULT timezone('utc', now()) NOT NULL,
	profile_id   bigint REFERENCES public.profiles (id) ON DELETE SET NULL,
	family_id    bigint REFERENCES public.families (id) ON DELETE SET NULL,
	category     text NOT NULL
		CHECK (category IN ('question', 'problem', 'suggestion', 'privacy', 'other')),
	reply_email  text NOT NULL CHECK (char_length(reply_email) BETWEEN 3 AND 254),
	message      text NOT NULL CHECK (char_length(message) BETWEEN 10 AND 2000),
	diagnostics  jsonb,
	language     text,
	ip_hash      text,
	status       text NOT NULL DEFAULT 'open'
		CHECK (status IN ('open', 'undelivered', 'closed'))
);

ALTER TABLE public.support_requests OWNER TO postgres;
ALTER TABLE public.support_requests ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.support_requests FROM PUBLIC;
REVOKE ALL ON TABLE public.support_requests FROM anon;
REVOKE ALL ON TABLE public.support_requests FROM authenticated;
GRANT ALL ON TABLE public.support_requests TO service_role;

-- The three windows the limit reads. Partial on the rows that count.
CREATE INDEX IF NOT EXISTS support_requests_profile_recent
	ON public.support_requests (profile_id, created_at) WHERE status <> 'undelivered';
CREATE INDEX IF NOT EXISTS support_requests_email_recent
	ON public.support_requests (lower(reply_email), created_at) WHERE status <> 'undelivered';
CREATE INDEX IF NOT EXISTS support_requests_ip_recent
	ON public.support_requests (ip_hash, created_at) WHERE status <> 'undelivered';

-- ── 2. record_support_request ────────────────────────────────────────────────
-- Counts and inserts in ONE transaction, serialized per key by an advisory lock
-- — two parallel posts would otherwise each count N-1 and both get in.
--
-- The limits are NOT here: they are named constants in
-- `supabase/functions/send-support-request/index.ts`, passed in, and the core
-- mirror (`support_constants_mirror_test`) reads that file. One home for the
-- numbers, the S-21 shape.
--
-- Signed in (`p_profile_id` not null): limited by profile.
-- Signed out: limited by e-mail AND, when the function has one, by IP hash.
-- Returns ('ok', id) or ('rate_limited', NULL).

CREATE OR REPLACE FUNCTION public.record_support_request(
	p_profile_id   bigint,
	p_family_id    bigint,
	p_category     text,
	p_reply_email  text,
	p_message      text,
	p_diagnostics  jsonb,
	p_language     text,
	p_ip_hash      text,
	p_hour_limit   integer,
	p_day_limit    integer
)
RETURNS TABLE (status text, request_id bigint)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	v_now   timestamp with time zone := timezone('utc', now());
	v_email text := lower(trim(p_reply_email));
	v_id    bigint;
BEGIN
	IF p_profile_id IS NOT NULL THEN
		PERFORM pg_advisory_xact_lock(hashtext('support:profile:' || p_profile_id));
		IF (SELECT count(*) FROM public.support_requests r
		    WHERE r.profile_id = p_profile_id AND r.status <> 'undelivered'
		      AND r.created_at > v_now - interval '1 hour') >= p_hour_limit
		OR (SELECT count(*) FROM public.support_requests r
		    WHERE r.profile_id = p_profile_id AND r.status <> 'undelivered'
		      AND r.created_at > v_now - interval '1 day') >= p_day_limit
		THEN
			RETURN QUERY SELECT 'rate_limited'::text, NULL::bigint;
			RETURN;
		END IF;
	ELSE
		PERFORM pg_advisory_xact_lock(hashtext('support:email:' || v_email));
		IF p_ip_hash IS NOT NULL THEN
			PERFORM pg_advisory_xact_lock(hashtext('support:ip:' || p_ip_hash));
		END IF;
		IF (SELECT count(*) FROM public.support_requests r
		    WHERE lower(r.reply_email) = v_email AND r.profile_id IS NULL
		      AND r.status <> 'undelivered'
		      AND r.created_at > v_now - interval '1 hour') >= p_hour_limit
		OR (SELECT count(*) FROM public.support_requests r
		    WHERE lower(r.reply_email) = v_email AND r.profile_id IS NULL
		      AND r.status <> 'undelivered'
		      AND r.created_at > v_now - interval '1 day') >= p_day_limit
		OR (p_ip_hash IS NOT NULL AND (SELECT count(*) FROM public.support_requests r
		    WHERE r.ip_hash = p_ip_hash AND r.status <> 'undelivered'
		      AND r.created_at > v_now - interval '1 hour') >= p_hour_limit)
		OR (p_ip_hash IS NOT NULL AND (SELECT count(*) FROM public.support_requests r
		    WHERE r.ip_hash = p_ip_hash AND r.status <> 'undelivered'
		      AND r.created_at > v_now - interval '1 day') >= p_day_limit)
		THEN
			RETURN QUERY SELECT 'rate_limited'::text, NULL::bigint;
			RETURN;
		END IF;
	END IF;

	INSERT INTO public.support_requests
		(profile_id, family_id, category, reply_email, message, diagnostics, language, ip_hash)
	VALUES
		(p_profile_id, p_family_id, p_category, trim(p_reply_email), p_message,
		 p_diagnostics, p_language, CASE WHEN p_profile_id IS NULL THEN p_ip_hash END)
	RETURNING id INTO v_id;

	RETURN QUERY SELECT 'ok'::text, v_id;
END;
$$;

ALTER FUNCTION public.record_support_request(bigint, bigint, text, text, text, jsonb, text, text, integer, integer) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.record_support_request(bigint, bigint, text, text, text, jsonb, text, text, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_support_request(bigint, bigint, text, text, text, jsonb, text, text, integer, integer) FROM anon;
REVOKE ALL ON FUNCTION public.record_support_request(bigint, bigint, text, text, text, jsonb, text, text, integer, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.record_support_request(bigint, bigint, text, text, text, jsonb, text, text, integer, integer) TO service_role;

-- ── 3. Retention — 12 months ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.purge_old_support_requests()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	removed integer;
BEGIN
	DELETE FROM public.support_requests
	WHERE created_at < timezone('utc', now()) - interval '12 months';
	GET DIAGNOSTICS removed = ROW_COUNT;
	RETURN removed;
END;
$$;

ALTER FUNCTION public.purge_old_support_requests() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.purge_old_support_requests() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.purge_old_support_requests() FROM anon;
REVOKE ALL ON FUNCTION public.purge_old_support_requests() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.purge_old_support_requests() TO service_role;
