-- T-109 — push targets of two kinds, and a registry that forgets dead devices.
--
-- firebase_messaging 17 deprecated getToken/onTokenRefresh for
-- register()/onRegistered, which hand back a Firebase Installation ID (FID)
-- instead of an FCM registration token. FCM HTTP v1 addresses the two through
-- DIFFERENT fields of the message (`fid` / `token`; `token` is deprecated and
-- accepts an FID only "during the transition period", undated). So the server
-- must know which kind each row is BEFORE any client sends an FID — this
-- migration and `_shared/fcm.ts` ship first (T-109 PR 1); the clients move in
-- PR 2.
--
-- What this adds:
--   · `push_subscriptions.kind` — 'token' | 'fid', DEFAULT 'token', so every
--     Android build already in the stores keeps inserting exactly what it does
--     today and gets the right kind without knowing the column exists. The
--     column that holds the value stays named `token`: renaming it would break
--     those same builds' upsert.
--   · CHECK: a row that says 'fid' must LOOK like one — the 22-symbol shape
--     the Firebase JS SDK itself validates (`^[cdef][\w-]{21}$`). A client bug
--     that stored a registration token as 'fid' would otherwise be sent
--     through the wrong field and retired as dead, silently.
--   · `push.stale_after_days` (T-80 key, default 270, range 30–400) and
--     `prune_push_subscriptions()` — deletes rows not seen for that long, and
--     rows of members who left the family (S-11: never a recipient again).
--     270 is FCM's own expiry for an inactive Android registration. It is safe
--     with every build: `last_seen_at` is written only when a row is created
--     (PushService.start re-registers only when the row is missing), so a
--     pruned LIVE device re-registers itself on its next opening. PR 2 makes
--     the app touch `last_seen_at` on every start; only after that build is in
--     Production may the number come down (~60 would clear today's backlog:
--     190 rows of ONE profile, one per Play test-device install since 01/09).
--   · pg_cron `push-subscriptions-prune-daily`, 06:30 UTC (03:30 BRT), plain
--     SQL — no Edge Function in the loop.

-- ── 1. The kind of each target ──────────────────────────────────────────────

ALTER TABLE public.push_subscriptions
	ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'token';

ALTER TABLE public.push_subscriptions
	DROP CONSTRAINT IF EXISTS push_subscriptions_kind_check;
ALTER TABLE public.push_subscriptions
	ADD CONSTRAINT push_subscriptions_kind_check
		CHECK (kind IN ('token', 'fid'));

ALTER TABLE public.push_subscriptions
	DROP CONSTRAINT IF EXISTS push_subscriptions_fid_shape;
ALTER TABLE public.push_subscriptions
	ADD CONSTRAINT push_subscriptions_fid_shape
		CHECK (kind <> 'fid' OR token ~ '^[cdef][A-Za-z0-9_-]{21}$');

COMMENT ON COLUMN public.push_subscriptions.kind IS
	'T-109: what `token` holds — an FCM registration token (''token'', every build before T-109 PR 2) or a Firebase Installation ID (''fid''). send-push-notification addresses FCM v1 `message.token` or `message.fid` by this column.';

COMMENT ON TABLE public.push_subscriptions IS
	'F-09: push targets, one row per device — FCM registration tokens or, since T-109, Firebase Installation IDs (`kind`). Written by the app for its OWN profile; read by send-push-notification. Rows die by UNREGISTERED from FCM, with the profile, or by prune_push_subscriptions (stale or departed).';

-- ── 2. The parameter ────────────────────────────────────────────────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, min_value, max_value, help)
VALUES
	('push.stale_after_days', '270', 'int', 'push',
	 'T-109: dias sem contato até um aparelho sair da lista de push (poda diária).',
	 false, 'days', 'sensitive', 30, 400,
	 jsonb_build_object(
		'controls', 'Depois de quantos dias sem o aparelho dar sinal (last_seen_at) o registro de push dele é apagado pela poda diária. Membros que saíram da família perdem o registro na mesma rodada, sem esperar o prazo.',
		'shown_at', jsonb_build_array('push'),
		'if_increased', 'Aparelhos abandonados ficam mais tempo na lista: cada push tenta entregar a eles também e só a resposta do FCM os retira.',
		'if_decreased', 'A lista fica mais limpa, mas um aparelho vivo que ficou sem abrir o app por esse tempo perde o registro e só volta a receber push quando o app for aberto de novo.',
		'takes_effect', 'Servidor na próxima rodada diária (03:30 de Brasília).',
		'caveats', 'Até a versão do T-109 PR 2 estar na Production, o app só grava last_seen_at ao criar o registro — abaixo de 270 dias, aparelhos ativos de builds antigos perdem o push até a próxima abertura.',
		'requires', 'A versão do app que atualiza last_seen_at a cada abertura (T-109 PR 2) em Production antes de baixar de 270.'))
ON CONFLICT (key) DO NOTHING;

-- ── 3. The prune ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.prune_push_subscriptions()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	v_days  int := public.setting_int('push.stale_after_days', 270);
	v_count int;
BEGIN
	DELETE FROM public.push_subscriptions s
	 WHERE s.last_seen_at < now() - make_interval(days => v_days)
	    OR EXISTS (
	       SELECT 1 FROM public.profiles p
	        WHERE p.id = s.profile_id
	          AND p.left_at IS NOT NULL);

	GET DIAGNOSTICS v_count = ROW_COUNT;
	RETURN v_count;
END;
$$;

ALTER FUNCTION public.prune_push_subscriptions() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.prune_push_subscriptions() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prune_push_subscriptions() TO service_role;

COMMENT ON FUNCTION public.prune_push_subscriptions() IS
	'T-109: deletes push targets not seen for push.stale_after_days (default 270, FCM''s own Android expiry) and those of members who left the family (S-11). Returns the number deleted. Daily by pg_cron.';

-- ── 4. Daily, in plain SQL (the F-78 shape) ─────────────────────────────────

SELECT cron.schedule(
	'push-subscriptions-prune-daily',
	'30 6 * * *',
	$cron$ SELECT public.prune_push_subscriptions(); $cron$
);
