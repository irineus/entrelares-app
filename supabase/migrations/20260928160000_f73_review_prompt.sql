-- =============================================================================
-- F-73 — the Android app asks for a Play review at a good moment
--
-- Decisions locked by the owner (28/09/2026, competitive chain):
--   * The moment is the first time the swap's REQUESTER sees the other side's
--     approval (`swap_approved`) with the app open; never after a failure or
--     mid-task. Never a Visualizador, never offline, only on the PRODUCTION
--     store build (com.entrelares.app) — web, dev and iOS never call the API.
--   * The floors are keys, born with T-80's metadata. The rule is pure, in
--     core (`ReviewPromptRules`); the app reads the keys once per opening.
--   * Play decides whether a sheet appears and never says whether anyone
--     reviewed: the only reading is the Play Console's ratings over time.
-- =============================================================================

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, min_value, max_value, help)
VALUES
	('review_prompt.enabled', 'true', 'bool', 'review',
	 'Liga o pedido de avaliação da Play no app Android da loja (F-73).',
	 true, 'flag', 'normal', NULL, NULL,
	 jsonb_build_object(
		'controls', 'Se o app Android da loja pede à Play a folha de avaliação quando quem pediu uma troca vê a aprovação da outra parte.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Ligado: o app pede a folha no momento certo, respeitando os dias mínimos de conta e o intervalo entre pedidos.',
		'if_decreased', 'Desligado: o app nunca pede avaliação. É o botão de parar se algo der errado.',
		'takes_effect', 'Na próxima abertura do app (ele lê a chave ao entrar).',
		'caveats', 'A Play decide se a folha aparece (tem cota própria) e nunca informa se houve avaliação. Web, iPhone e builds de teste nunca pedem.')),
	('review_prompt.min_account_days', '14', 'int', 'review',
	 'Dias de conta antes do primeiro pedido de avaliação na Play (F-73).',
	 true, 'days', 'normal', 7, 90,
	 jsonb_build_object(
		'controls', 'Quantos dias a conta precisa ter, contados da criação do login, antes de o app pedir uma avaliação.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Só pede a quem já usa o app há mais tempo — menos pedidos, de gente com mais experiência.',
		'if_decreased', 'Pede mais cedo; o risco é pedir a quem ainda não conhece o app.',
		'takes_effect', 'Na próxima abertura do app.',
		'caveats', 'Conta a partir do login (não da linha da família): um convidado que resgatou um lugar reservado conta do dia em que criou a conta.')),
	('review_prompt.interval_days', '120', 'int', 'review',
	 'Dias mínimos entre dois pedidos de avaliação no mesmo aparelho (F-73).',
	 true, 'days', 'normal', 30, 365,
	 jsonb_build_object(
		'controls', 'Quanto tempo o app espera, no mesmo aparelho, antes de pedir uma avaliação de novo.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Pede menos vezes a quem já recebeu o pedido.',
		'if_decreased', 'Pede com mais frequência — a Play ainda aplica a própria cota por cima.',
		'takes_effect', 'Na próxima abertura do app.',
		'caveats', 'O último pedido fica guardado no aparelho: reinstalar ou trocar de celular recomeça a contagem.'))
ON CONFLICT (key) DO NOTHING;
