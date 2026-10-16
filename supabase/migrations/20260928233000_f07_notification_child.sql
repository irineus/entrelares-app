-- =============================================================================
-- F-07 (PR 5b) — a swap's notification names its child
--
-- In a per-child plan a swap request is ONE child's day, and "Nova solicitação
-- de troca — 12/10" no longer says which child. Every writer of a swap
-- notification (the app's composers, `auto_approve_expired`, the F-24
-- reminder) links the row to its request through `swap_request_id`, and the
-- request carries its lane since PR 2 — so ONE trigger stamps the child for
-- all of them, and a writer added later gets it for free (F-09's "hang it off
-- the single writer").
--
--   · `params.child` = the child's first name (family data, never translated);
--     the in-app renderer (`NotificationRenderer.withChild`) and the push
--     (`_shared/push.ts`) append " · <name>" to the heading in the reader's
--     language; the e-mail subject does the same from the request itself.
--   · The stored PT-BR title (the fallback) gets the same suffix.
--   · A single-plan family's requests have no lane, so nothing changes.
--   · An aviso's notifications are left alone: "fica com o dia" may move
--     several lanes at once (PR 5a), and naming one child would be wrong.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.stamp_notification_child()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	v_child text;
BEGIN
	IF NEW.swap_request_id IS NULL OR (NEW.params ? 'child') THEN
		RETURN NEW;
	END IF;

	-- An aviso's answer is about today as a whole (PR 5a).
	IF EXISTS (SELECT 1 FROM public.day_notice_outcomes o
	           WHERE o.swap_request_id = NEW.swap_request_id) THEN
		RETURN NEW;
	END IF;

	SELECT c.first_name INTO v_child
	FROM public.swap_requests s
	JOIN public.children c ON c.id = s.child_id
	WHERE s.id = NEW.swap_request_id;

	IF v_child IS NOT NULL THEN
		NEW.params := COALESCE(NEW.params, '{}'::jsonb) || jsonb_build_object('child', v_child);
		NEW.title  := NEW.title || ' · ' || v_child;
	END IF;

	RETURN NEW;
END;
$$;

ALTER FUNCTION public.stamp_notification_child() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.stamp_notification_child() FROM PUBLIC, anon, authenticated;

-- After trigger_a_filter_viewer_notifications (alphabetical), which may drop
-- the row for a viewer before anything is stamped.
DROP TRIGGER IF EXISTS trigger_b_stamp_notification_child ON public.notifications;
CREATE TRIGGER trigger_b_stamp_notification_child
	BEFORE INSERT ON public.notifications
	FOR EACH ROW EXECUTE FUNCTION public.stamp_notification_child();
