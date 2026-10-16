-- =============================================================================
-- F-94 — an unanswered swap request is told the evening BEFORE its day
--
-- Owner, 05/10/2026 (phase-3 chain): push + in-app at 19:00 São Paulo on the
-- EVE of the request's day, to whoever must answer it, ONCE per request, and
-- only while it is still pending. A request created after that 19:00 gets no
-- eve reminder. No push on the morning of the day. F-24/F-60's timings (the
-- reminder at expiry + 24 h, the approval at expiry + 48 h, anchored on the
-- DAY) are untouched — this ADDS a notice before the day; re-anchoring stays
-- an open decision (§2).
--
-- Why: Ana asks Bruno, four days ahead, to keep their daughter on a Thursday
-- with no handoff time. By F-24's arithmetic the reminder reaches Bruno on
-- Friday at 00:00 — after the day. Thursday arrived with nobody told.
--
-- No new push type: `auto_reminder` (already pushable, already routed to
-- "Para você" in both channels) with `params.kind = 'eve'` — the F-78 shape.
-- Pure SQL on pg_cron, the F-70/F-77/F-78 mould: a function + a ledger.
-- =============================================================================


-- ── 1. The ledger: one row per request already told on its eve ──────────────

CREATE TABLE IF NOT EXISTS public.swap_eve_reminders (
	swap_request_id bigint PRIMARY KEY REFERENCES public.swap_requests (id) ON DELETE CASCADE,
	sent_at         timestamp with time zone NOT NULL DEFAULT timezone('utc', now())
);

COMMENT ON TABLE public.swap_eve_reminders IS
	'F-94: one row per swap request whose target was reminded at 19:00 (Sao Paulo) on the eve of its day. Service role only.';

ALTER TABLE public.swap_eve_reminders ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.swap_eve_reminders FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.swap_eve_reminders TO service_role;


-- ── 2. The selection ─────────────────────────────────────────────────────────
-- `p_now` defaults to now() (what the cron sends); the DB gate passes the
-- instant it wants judged. The eve is the São Paulo date of `p_now`, the day
-- is the next one, and the cut-off is 19:00 of the eve: a request created
-- later than that is not reminded, even if the job runs a few minutes late.

CREATE OR REPLACE FUNCTION public.swap_eve_reminders_due(p_now timestamptz DEFAULT now())
RETURNS TABLE (swap_request_id bigint)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	tz      constant text := 'America/Sao_Paulo';
	eve     date := (p_now AT TIME ZONE tz)::date;
	cutoff  timestamptz := (eve + time '19:00') AT TIME ZONE tz;
	rec     record;
	who     text;
	d_iso   text;
	d_pt    text;
BEGIN
	FOR rec IN
		SELECT r.*
		  FROM public.swap_requests r
		 WHERE r.status IN ('pending', 'revert_pending')
		   AND r.schedule_date = eve + 1
		   AND r.created_at < cutoff
		   AND NOT EXISTS (SELECT 1 FROM public.swap_eve_reminders e
		                    WHERE e.swap_request_id = r.id)
		 ORDER BY r.id
	LOOP
		-- Whoever answers must be a live member with an account (never a
		-- viewer — a viewer is never a swap party, F-50).
		IF NOT EXISTS (
			SELECT 1 FROM public.profiles p
			 WHERE p.id = rec.target_profile_id
			   AND p.left_at IS NULL
			   AND p.user_id IS NOT NULL
			   AND p.membership_type <> 'viewer'
		) THEN
			CONTINUE;
		END IF;

		INSERT INTO public.swap_eve_reminders (swap_request_id) VALUES (rec.id);

		SELECT coalesce(nullif(btrim(full_name), ''), 'Outro responsável') INTO who
		  FROM public.profiles WHERE id = rec.requesting_profile_id;
		who   := coalesce(who, 'Outro responsável');
		d_iso := to_char(rec.schedule_date, 'YYYY-MM-DD');
		d_pt  := to_char(rec.schedule_date, 'DD/MM/YYYY');

		-- PT-BR byte-identical to the catalog (U-13); the reader's device
		-- rebuilds it from `params` in their own language.
		INSERT INTO public.notifications
			(recipient_profile_id, type, title, message, params, swap_request_id, is_read, created_at)
		VALUES (
			rec.target_profile_id,
			'auto_reminder',
			'Pedido para amanhã sem resposta',
			who || ' fez um pedido para amanhã, ' || d_pt || ', que ainda espera a sua resposta.',
			jsonb_build_object('kind', 'eve', 'date', d_iso, 'name', who),
			rec.id, false, now()
		);

		swap_request_id := rec.id;
		RETURN NEXT;
	END LOOP;
END;
$$;

ALTER FUNCTION public.swap_eve_reminders_due(timestamptz) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.swap_eve_reminders_due(timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.swap_eve_reminders_due(timestamptz) TO service_role;


-- ── 3. Schedule: daily at 19:00 in Brasília (22:00 UTC; no DST since 2019) ──

SELECT cron.schedule(
	'swap-eve-reminders-daily',
	'0 22 * * *',
	$cron$ SELECT public.swap_eve_reminders_due(); $cron$
);
