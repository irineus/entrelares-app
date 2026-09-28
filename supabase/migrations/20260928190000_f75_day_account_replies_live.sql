-- =============================================================================
-- F-75 goes live: the reply to a relato do dia
--
-- F-75 shipped to main DARK (20260928170000_f75_day_account_replies.sql):
-- `feature.day_account_replies` seeded `false`, the server refusing every
-- reply while it is off. The owner's decision (28/09/2026, competitive
-- chain): no stop — the session checks the flow on the dev project (two
-- caregivers: reply, see it in the day, the Histórico and the PDF), then this
-- short migration turns it on in production. The flag stays afterwards as the
-- kill switch (T-84).
--
-- Nothing else moves: the landing's §10 (non-material, date only) was
-- promoted before this merge, and the Android build that renders the reply
-- is the one already on Internal. The app reads app_settings once per
-- opening, so an open app sees the reply on its next opening.
-- =============================================================================

UPDATE public.app_settings
   SET value      = 'true',
       updated_at = timezone('utc'::text, now())
 WHERE key = 'feature.day_account_replies';
