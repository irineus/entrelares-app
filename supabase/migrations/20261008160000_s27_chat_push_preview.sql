-- S-27 (T-103 audit, 04/10/2026; owner, 07/10/2026) — the Conversa's push
-- hides the text by default, for everyone.
--
-- A chat push put "Nome: <texto>" (140 chars) on the lock screen, where the
-- children or a new partner read a hostile message; the only control was
-- muting the push entirely. Now:
--   · `chat_prefs.push_preview` (default false) — beside `push_muted`, per
--     member, on the server, because the push text is built server-side in
--     `_shared/push.ts`.
--   · `set_chat_push_preview(p_on)` — the member's own switch.
--   · `send_chat_message` — copied VERBATIM from 20260924170000 (F-35, its
--     only definition), with `params.preview` ('1' | '0') per recipient. The
--     stored in-app row is unchanged: the reader is already in the app.

ALTER TABLE public.chat_prefs
	ADD COLUMN IF NOT EXISTS push_preview boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.chat_prefs.push_preview IS
	'S-27: show the text of a Conversa message in its push (default off: "Nova mensagem de <Nome> na Conversa").';

CREATE OR REPLACE FUNCTION public.set_chat_push_preview(p_on boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me public.profiles%ROWTYPE := public.chat_guard(false);
BEGIN
	INSERT INTO public.chat_prefs (profile_id, push_preview, updated_at)
	VALUES (me.id, coalesce(p_on, false), now())
	ON CONFLICT (profile_id) DO UPDATE
	SET push_preview = EXCLUDED.push_preview, updated_at = now();
END;
$$;

ALTER FUNCTION public.set_chat_push_preview(boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.set_chat_push_preview(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_chat_push_preview(boolean) TO authenticated, service_role;

COMMENT ON FUNCTION public.set_chat_push_preview(boolean) IS
	'S-27: the member turns the text preview of Conversa pushes on or off (chat_prefs.push_preview).';

CREATE OR REPLACE FUNCTION public.send_chat_message(p_body text, p_quote_id bigint, p_day date)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me       public.profiles%ROWTYPE := public.chat_guard(true);
	v_body   text := nullif(btrim(coalesce(p_body, '')), '');
	max_chr  int  := public.setting_int('chat.message_max_chars', 2000);
	per_hour int  := public.setting_int('chat.messages_per_hour', 60);
	v_name   text;
	v_short  text;
	new_id   bigint;
BEGIN
	IF v_body IS NULL THEN
		RAISE EXCEPTION 'Escreva algo antes de enviar.' USING ERRCODE = 'check_violation';
	END IF;
	IF char_length(v_body) > max_chr THEN
		RAISE EXCEPTION 'Um envio na Conversa é limitado a % caracteres.', max_chr
			USING ERRCODE = 'check_violation';
	END IF;
	IF p_quote_id IS NOT NULL AND NOT EXISTS (
		SELECT 1 FROM public.chat_messages WHERE id = p_quote_id AND family_id = me.family_id) THEN
		RAISE EXCEPTION 'O texto citado não está nesta Conversa.' USING ERRCODE = 'check_violation';
	END IF;
	IF (SELECT COUNT(*) FROM public.chat_messages
	    WHERE author_profile_id = me.id AND created_at > now() - interval '1 hour') >= per_hour THEN
		RAISE EXCEPTION 'Você chegou ao limite de % envios por hora na Conversa. Tente de novo mais tarde.', per_hour
			USING ERRCODE = 'check_violation';
	END IF;

	INSERT INTO public.chat_messages (family_id, author_profile_id, body, quote_id, quoted_day)
	VALUES (me.family_id, me.id, v_body, p_quote_id, p_day)
	RETURNING id INTO new_id;

	-- In-app to every reader but the author (viewers included — the viewer
	-- filter lets `chat_message` through); push unless the reader silenced it.
	v_name  := coalesce(nullif(btrim(me.full_name), ''), 'Um membro da família');
	v_short := CASE WHEN char_length(v_body) > 140
	                THEN left(v_body, 139) || '…' ELSE v_body END;
	INSERT INTO public.notifications (recipient_profile_id, type, title, message, params)
	SELECT p.id, 'chat_message', 'Conversa da família',
	       v_name || ': ' || v_short,
	       jsonb_build_object(
	           'date', to_char((now() AT TIME ZONE 'America/Sao_Paulo')::date, 'YYYY-MM-DD'),
	           'name', v_name,
	           'msg',  v_short,
	           'id',   new_id::text,
	           'push', CASE WHEN coalesce(cp.push_muted, false) THEN 'false' ELSE 'true' END,
	           -- S-27: the text reaches the lock screen only for a reader who
	           -- turned the preview on; everyone else reads "Nova mensagem de
	           -- <Nome> na Conversa".
	           'preview', CASE WHEN coalesce(cp.push_preview, false) THEN '1' ELSE '0' END)
	FROM public.profiles p
	LEFT JOIN public.chat_prefs cp ON cp.profile_id = p.id
	WHERE p.family_id = me.family_id
	  AND p.id <> me.id
	  AND p.user_id IS NOT NULL AND p.left_at IS NULL;

	RETURN new_id;
END;
$$;
