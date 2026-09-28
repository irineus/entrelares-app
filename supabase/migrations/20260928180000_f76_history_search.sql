-- =============================================================================
-- F-76 — search the Histórico by word
--
-- Decisions locked by the owner (28/09/2026, competitive chain):
--   * A SERVER RPC, SECURITY INVOKER: every source table's own RLS decides
--     what comes back — the family's rows only, and for a Visualizador no
--     swap negotiation (F-50's RESTRICTIVE policy on swap_requests).
--   * The cut is the trail the reader can already see (the Histórico has no
--     plan or window cut: free and Premium read the same trail). Sources, the
--     texts people WROTE: relatos (F-67) and their replies (F-75), the
--     requester's message and the approver's note of a RESOLVED swap (the
--     F-45 origin the Histórico prints under an entry), the day observation
--     where a log changed it, the agenda's text (F-55, only with the agenda
--     on, deleted items included, a converted note only once deleted), and
--     the avisos' notes (F-52 — named by the card; the reader already sees
--     them on the calendar).
--   * Matching = the Conversa's normalizer (`ChatRules.fold`, core): lower
--     case, the accents of Portuguese folded, every word of the query a
--     substring of the text, in any order. `history_fold` below is its SQL
--     mirror; `history_fold_mirror_test` (core) pins the translate() map to
--     `ChatRules.foldMap`, and the DB gate compares outputs byte for byte.
--   * Nothing new is stored. No module flag (read-only). The query never
--     reaches Umami — only a count does.
--   * `setting_bool` is not executable by `authenticated`, so the agenda
--     flag is read from `app_settings` directly (a public row, RLS allows).
-- =============================================================================

-- ── 1. The fold: ChatRules.fold, in SQL ─────────────────────────────────────
-- Upper case is in the map too: lower() depends on the database's ctype for
-- accented capitals, and the map must not.

CREATE OR REPLACE FUNCTION public.history_fold(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path TO 'public'
AS $$
	SELECT lower(translate(coalesce(p_text, ''),
		'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
		'aaaaaeeeeiiiiooooouuuucnaaaaaeeeeiiiiooooouuuucn'));
$$;

ALTER FUNCTION public.history_fold(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.history_fold(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.history_fold(text) TO authenticated, service_role;

-- ── 2. The search ───────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.search_history(p_query text)
RETURNS TABLE (
	kind              text,
	day               date,
	written_at        timestamp with time zone,
	author_profile_id bigint,
	body              text
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $$
DECLARE
	words     text[];
	agenda_on boolean;
BEGIN
	words := array_remove(
		regexp_split_to_array(public.history_fold(btrim(coalesce(p_query, ''))), '\s+'), '');
	IF coalesce(array_length(words, 1), 0) = 0 THEN
		RETURN;
	END IF;

	agenda_on := coalesce(
		(SELECT lower(s.value) = 'true' FROM public.app_settings s
		 WHERE s.key = 'feature.child_agenda'), false);

	RETURN QUERY
	WITH hits AS (
		-- F-67: the relatos.
		SELECT 'relato'::text AS kind, a.account_date AS day, a.created_at AS written_at,
		       a.author_profile_id AS author, a.body AS body, a.body AS haystack
		FROM public.day_accounts a
		UNION ALL
		-- F-75: the replies, on the day their relato is about.
		SELECT 'reply', a.account_date, r.created_at, r.author_profile_id, r.body, r.body
		FROM public.day_account_replies r
		JOIN public.day_accounts a ON a.id = r.account_id
		UNION ALL
		-- F-44/F-45: the requester's message of a RESOLVED swap — the origin
		-- the Histórico prints. A viewer's RLS returns no swap_requests row.
		SELECT 'swap_message', s.schedule_date, s.created_at, s.requesting_profile_id,
		       s.request_message, s.request_message
		FROM public.swap_requests s
		WHERE s.resolution_log_id IS NOT NULL
		  AND nullif(btrim(s.request_message), '') IS NOT NULL
		UNION ALL
		SELECT 'swap_note', s.schedule_date, coalesce(s.resolved_at, s.created_at),
		       s.target_profile_id, s.approval_note, s.approval_note
		FROM public.swap_requests s
		WHERE s.resolution_log_id IS NOT NULL
		  AND nullif(btrim(s.approval_note), '') IS NOT NULL
		UNION ALL
		-- The day observation, where a log CHANGED it (the diff shows it only
		-- then); both sides of the change are searched.
		SELECT 'day_note', l.affected_date, l.created_at, l.performed_by_id,
		       coalesce(l.new_data->>'notes', l.old_data->>'notes'),
		       coalesce(l.new_data->>'notes', '') || ' ' || coalesce(l.old_data->>'notes', '')
		FROM public.activity_logs l
		WHERE (l.old_data->>'notes') IS DISTINCT FROM (l.new_data->>'notes')
		UNION ALL
		-- F-55: the agenda's text, deleted items included, a converted day
		-- note only once deleted (AgendaRules.trail), with the agenda on.
		SELECT 'agenda', e.event_date, e.created_at, e.created_by, e.body, e.body
		FROM public.child_events e
		WHERE agenda_on
		  AND nullif(btrim(e.body), '') IS NOT NULL
		  AND (e.source_schedule_id IS NULL OR e.deleted_at IS NOT NULL)
		UNION ALL
		-- F-52: the aviso's note and the answer's note.
		SELECT 'notice', n.schedule_date, n.created_at, n.sender_profile_id, n.note, n.note
		FROM public.day_notices n
		WHERE nullif(btrim(n.note), '') IS NOT NULL
		UNION ALL
		SELECT 'notice', n.schedule_date, o.created_at, o.actor_profile_id, o.note, o.note
		FROM public.day_notice_outcomes o
		JOIN public.day_notices n ON n.id = o.notice_id
		WHERE nullif(btrim(o.note), '') IS NOT NULL
	)
	SELECT h.kind, h.day, h.written_at, h.author, h.body
	FROM hits h
	WHERE (SELECT bool_and(strpos(public.history_fold(h.haystack), w) > 0)
	       FROM unnest(words) AS w)
	ORDER BY h.day DESC, h.written_at DESC
	LIMIT 200;
END;
$$;

ALTER FUNCTION public.search_history(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.search_history(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_history(text) TO authenticated, service_role;
COMMENT ON FUNCTION public.search_history(text) IS
	'F-76: word search over the texts the Histórico shows, as the caller (SECURITY INVOKER — RLS decides). Nothing stored.';
