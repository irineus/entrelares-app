-- =============================================================================
-- F-52 (correção, 18/09/2026) — um aviso de cortesia também acorda o telefone
--
-- A migração anterior (20260918214500) filtrava o push de `day_notice` para
-- `pickup` e `keep`. O raciocínio era real: o roteamento do tap acontecia por
-- TIPO apenas, nos dois canais, então todo `day_notice` que virasse push cairia
-- em "Para você" — e um "só avisando" ali abriria uma aba onde ele não está
-- listado, que é o defeito que o PushRouting existe para impedir.
--
-- **O primeiro uso real derrubou a decisão.** O owner mandou dois avisos e
-- nenhum telefone tocou: os dois eram `info`, que é o PADRÃO da folha e o caso
-- mais comum do produto. "Vou atrasar 15 minutos" é exatamente a frase cujo
-- valor inteiro é chegar antes de a outra pessoa sair de casa — e era o único
-- que estava cortado.
--
-- A causa nunca foi o `kind`; era o roteamento não saber lê-lo. Então o payload
-- do FCM passa a carregar `kind` (um campo, num mapa de strings que já existia)
-- e os dois canais roteiam por tipo E kind: `pickup`/`keep` vão para
-- "Para você", o resto vai para "Todas", onde a linha sempre está. Sem aba
-- vazia e sem corte — e o filtro abaixo deixa de existir.
--
-- Quem recebe não muda e nunca mudou: `send_day_notice` escreve uma notificação
-- para TODO membro ativo com conta menos quem enviou, e o trigger dispara por
-- linha. O push sempre foi para a família inteira; o que faltava era ele sair.
--
-- Copiado VERBATIM de 20260918214500 com o bloco do `kind` removido.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.dispatch_push_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'vault'
AS $$
DECLARE
	base_url text;
	api_key  text;
BEGIN
	-- The cheap filter. Most inserts (receipts, family fan-out, membership,
	-- quota, billing) stop on this line and never touch pg_net.
	IF NEW.type NOT IN (
		'auto_reminder', 'auto_approved',
		'swap_requested', 'swap_approved', 'swap_rejected', 'swap_cancelled',
		'revert_requested', 'revert_approved', 'revert_rejected', 'revert_cancelled',
		'day_notice'
	) THEN
		RETURN NULL;
	END IF;

	-- A row written before U-13 (or by a writer that forgot `params`) carries no
	-- render data, and the function would only drop it. Save the round trip.
	IF NEW.params IS NULL THEN
		RETURN NULL;
	END IF;

	SELECT decrypted_secret INTO base_url
	FROM vault.decrypted_secrets WHERE name = 'functions_base_url';

	SELECT decrypted_secret INTO api_key
	FROM vault.decrypted_secrets WHERE name = 'secret_key';

	-- Unarmed project: no Vault secrets, no push, no noise. This is the state of
	-- every environment until the runbook's § 11 is done.
	IF base_url IS NULL OR api_key IS NULL THEN
		RETURN NULL;
	END IF;

	-- S-16: the key goes on `apikey`, NEVER on Authorization — the new-model
	-- secret keys are not JWTs and the platform rejects them there.
	PERFORM net.http_post(
		url     := base_url || '/send-push-notification',
		headers := jsonb_build_object(
			'Content-Type', 'application/json',
			'apikey', api_key),
		body    := jsonb_build_object('notification_id', NEW.id),
		-- 30s, per the runbook's own cron rule: a cold isolate has taken over
		-- five seconds to boot (the send-auth-email incident), and a timeout
		-- here ABORTS the request — it would drop the push and log a failure
		-- for a function that was about to work. Nothing waits on this call.
		timeout_milliseconds := 30000
	);

	RETURN NULL;
EXCEPTION WHEN OTHERS THEN
	-- A push is never worth failing the write that earned it. The notification
	-- row, the badge and the e-mail all stand; only the interruption is lost.
	RAISE WARNING 'dispatch_push_notification failed for notification %: %', NEW.id, SQLERRM;
	RETURN NULL;
END;
$$;
