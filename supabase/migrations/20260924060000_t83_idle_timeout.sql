-- =============================================================================
-- T-83 (1/4) — the inactivity sign-out becomes an operator parameter
--
-- S-04 signed a session out after 30 minutes without interaction, a constant in
-- the client (`InactivityPolicy`). It is now `session.idle_timeout_minutes`,
-- default 30, range 5 to 240 minutes (owner, 23/09/2026), public — the app reads
-- it once per signed-in session and keeps the seed until (and unless) it
-- answers, so the sign-in never waits on it.
-- =============================================================================

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, min_value, max_value, help)
VALUES
	('session.idle_timeout_minutes', '30', 'int', 'security',
	 'Minutos sem interação até o app encerrar a sessão (S-04).',
	 true, 'minutes', 'sensitive', 5, 240,
	 jsonb_build_object(
		'controls', 'Quanto tempo o app espera sem nenhum toque, clique ou tecla antes de encerrar a sessão e voltar ao login, com o aviso "sessão encerrada por inatividade".',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Um aparelho esquecido aberto fica mais tempo com a sessão da família — mais conforto, menos proteção num celular compartilhado ou perdido.',
		'if_decreased', 'A sessão cai mais cedo; quem deixa o app aberto entre uma tarefa e outra entra de novo mais vezes.',
		'takes_effect', 'Na próxima sessão aberta (o app lê a chave ao entrar); uma sessão já aberta segue com o valor que leu.',
		'caveats', 'Tempo em segundo plano conta, como na web. Até a chave responder, vale o padrão de 30 minutos.'))
ON CONFLICT (key) DO NOTHING;
