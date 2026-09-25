-- =============================================================================
-- F-35 fix — the Conversa updates live
--
-- The owner's validation (25/09/2026): a text sent from the web did not reach
-- the sender's own "lida por" until a manual refresh, on either device. The
-- client now listens to both tables; they join the Realtime publication the
-- way F-29 and F-55 did theirs. Realtime applies each table's SELECT policy
-- to the subscriber, so a family sees only its own rows — the same read the
-- Conversa already makes.
-- =============================================================================

DO $$
BEGIN
	ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
EXCEPTION
	WHEN duplicate_object THEN NULL;
	WHEN undefined_object THEN NULL;
END $$;

DO $$
BEGIN
	ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_reads;
EXCEPTION
	WHEN duplicate_object THEN NULL;
	WHEN undefined_object THEN NULL;
END $$;
