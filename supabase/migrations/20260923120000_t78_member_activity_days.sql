-- =============================================================================
-- T-78 — Which members are alive, and on which channel: one row per member ×
-- day × channel, readable by nobody but the service role.
--
-- WHY. The family 19 analysis (21/09/2026) had to date each member's last use
-- from `auth.sessions` / `auth.refresh_tokens` — GoTrue internals that rotate,
-- expire and carry the full user agent. The product kept no "last used" of its
-- own, and Umami cannot answer per family by design (T-37: no identifier). The
-- operator report (F-69) and the definition of a family that stopped (F-70)
-- both need this fact, so it gets ONE small, honest home.
--
-- SHAPE. `(profile_id, day, channel)` and nothing else — the owner's
-- granularity (23/09/2026): the DAY in America/Sao_Paulo, never an hour; the
-- channel as a closed enum, never a user agent; no IP. A second open on the
-- same day writes nothing (`ON CONFLICT DO NOTHING`), so the table grows by at
-- most one row per member per channel per day.
--   · `android`       — the Play app;
--   · `web`           — web.entrelares.app in a browser tab;
--   · `web-installed` — the same web app launched from the Home Screen /
--                        installed (display-mode standalone), the iPhone door.
-- The client mirror is `ActivityRules` (core); `activity_channel_mirror_test`
-- reads THIS file's CHECK, because the client calls fire-and-forget and a value
-- the CHECK refused would vanish without a symptom.
--
-- ACCESS. Service role only — no policy, no grant to `anon`/`authenticated`,
-- the `support_requests` / `auth_elevation_codes` shape. Between co-parents,
-- "when did the other one last open the app" is surveillance, and §6 of the
-- policy promises the product is not a tool for it. The one writer is
-- `touch_activity`, for the CALLER's own profile only; the future reader is
-- F-69's operator RPC.
--
-- RETENTION. 400 days (owner, 23/09/2026 — a year-over-year read before an
-- annual renewal), stated in §11 of privacidade.html. The number lives in
-- `purge_old_member_activity()` and NOT in `app_settings` on purpose: it is a
-- promise printed in the policy, and a setting could move it without the text.
-- A member whose account is removed loses the rows at once (trigger below):
-- the profile itself survives as a tombstone for the history (S-11), so the
-- FK's cascade alone would keep the rows of someone who is gone.
-- =============================================================================

-- ── 1. member_activity_days ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.member_activity_days (
	profile_id  bigint NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
	day         date   NOT NULL,
	channel     text   NOT NULL
		CHECK (channel IN ('android', 'web', 'web-installed')),
	PRIMARY KEY (profile_id, day, channel)
);

COMMENT ON TABLE public.member_activity_days IS
	'T-78: one row per member × day (America/Sao_Paulo) × channel the app was used on. No hour, no IP, no user agent. Service role only — never readable by a family member. Written by touch_activity; purged after 400 days and when the account is removed.';

ALTER TABLE public.member_activity_days OWNER TO postgres;
ALTER TABLE public.member_activity_days ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.member_activity_days FROM PUBLIC;
REVOKE ALL ON TABLE public.member_activity_days FROM anon;
REVOKE ALL ON TABLE public.member_activity_days FROM authenticated;
GRANT ALL ON TABLE public.member_activity_days TO service_role;

-- The retention sweep and "last day per member" both read by day.
CREATE INDEX IF NOT EXISTS member_activity_days_day_idx
	ON public.member_activity_days (day);

-- ── 2. touch_activity ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.touch_activity(p_channel text)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me_id    bigint;
	today    date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	written  int;
BEGIN
	-- An unknown channel is a client bug, and it must be loud in the gate —
	-- the CHECK would refuse it anyway; this names why.
	IF p_channel IS NULL OR p_channel NOT IN ('android', 'web', 'web-installed') THEN
		RAISE EXCEPTION 'Canal de atividade desconhecido.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- The caller's OWN active profile, and no other: there is no parameter
	-- naming a profile. A session with no profile yet (the F-57 onboarding)
	-- and a departed member (S-11, frozen) record nothing — silently, because
	-- the caller fires and forgets.
	SELECT p.id INTO me_id
	FROM public.profiles p
	WHERE p.user_id = auth.uid() AND p.left_at IS NULL;

	IF me_id IS NULL THEN
		RETURN false;
	END IF;

	INSERT INTO public.member_activity_days (profile_id, day, channel)
	VALUES (me_id, today, p_channel)
	ON CONFLICT DO NOTHING;
	GET DIAGNOSTICS written = ROW_COUNT;

	RETURN written > 0;
END;
$$;

ALTER FUNCTION public.touch_activity(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.touch_activity(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.touch_activity(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.touch_activity(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.touch_activity(text) TO service_role;

-- ── 3. The account goes, the rows go ─────────────────────────────────────────
--
-- GoTrue's `deleteUser` (the purge-deleted pass, S-11) sets `profiles.user_id`
-- to NULL through `profiles_user_id_fkey ON DELETE SET NULL` — the moment an
-- account stops existing while its tombstone stays for the history. That is
-- the moment its activity must stop existing too. A whole-family purge deletes
-- the profiles, and the FK's CASCADE covers that path.

CREATE OR REPLACE FUNCTION public.forget_member_activity()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
	DELETE FROM public.member_activity_days WHERE profile_id = NEW.id;
	RETURN NULL;
END;
$$;

ALTER FUNCTION public.forget_member_activity() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.forget_member_activity() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.forget_member_activity() FROM anon;
REVOKE ALL ON FUNCTION public.forget_member_activity() FROM authenticated;

DROP TRIGGER IF EXISTS profiles_forget_activity ON public.profiles;
CREATE TRIGGER profiles_forget_activity
	AFTER UPDATE OF user_id ON public.profiles
	FOR EACH ROW
	WHEN (OLD.user_id IS NOT NULL AND NEW.user_id IS NULL)
	EXECUTE FUNCTION public.forget_member_activity();

-- ── 4. Retention — 400 days ──────────────────────────────────────────────────
--
-- Called by the daily `purge-deleted` pass. Also sweeps any tombstone's rows
-- (`left_at` set, account gone): convergent with the trigger, so a row that
-- predates it or slipped past it still goes.

CREATE OR REPLACE FUNCTION public.purge_old_member_activity()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	today    date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	removed  integer;
	gone     integer;
BEGIN
	DELETE FROM public.member_activity_days
	WHERE day < today - 400;
	GET DIAGNOSTICS removed = ROW_COUNT;

	DELETE FROM public.member_activity_days a
	USING public.profiles p
	WHERE a.profile_id = p.id
	  AND p.user_id IS NULL
	  AND p.left_at IS NOT NULL;
	GET DIAGNOSTICS gone = ROW_COUNT;

	RETURN removed + gone;
END;
$$;

ALTER FUNCTION public.purge_old_member_activity() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.purge_old_member_activity() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.purge_old_member_activity() FROM anon;
REVOKE ALL ON FUNCTION public.purge_old_member_activity() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.purge_old_member_activity() TO service_role;
