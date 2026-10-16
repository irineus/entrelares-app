-- =============================================================================
-- F-82 — the family referral goes live: the material policy version 2.1, and
-- the flag
--
-- F-80 (PRs #339, #345, #346) shipped the referral DARK behind
-- `feature.referral` = false. Its own help said what turning it on requires:
-- the privacy policy 2.1 published the same day, because the referral links two
-- families and that is new data. This migration is the owner-approved switch
-- (03/10/2026), in S-22's order:
--
--   1. the S-15 pair — `policy.current_version` / `policy.enforce_from` — for
--      version 2.1 of entrelares.app/privacidade (and Terms 1.4, whose §10 now
--      carries the referral rules). The landing is promoted BEFORE this merge,
--      so the text is visible when the app asks for the accept. The client
--      constants are the other half (`PolicyVersions.current` / `.enforceFrom`);
--      the gate's reconsent suite fails the build if the two drift.
--      `enforce_from` = the production publication + 15 days (legal review B-4).
--      It moves 2.0's 10/10 to 18/10 for whoever has not accepted yet — a notice
--      period may grow, never shrink (policy_versions.dart);
--   2. `feature.referral` ON — it stays afterwards as the kill switch (T-84);
--   3. the help of the two referral numbers says that the Terms now state them
--      (30 days, 12 a year): a console edit alone would make the server and the
--      published rules disagree.
--
-- The dates below are the publication the owner approved; if the publish
-- slips, the client constants, these two rows and the pages' dates move
-- together, in the same delivery.
-- =============================================================================

UPDATE public.app_settings
   SET value      = '2026-10-03',
       updated_at = timezone('utc'::text, now())
 WHERE key = 'policy.current_version';

UPDATE public.app_settings
   SET value      = '2026-10-18',
       updated_at = timezone('utc'::text, now())
 WHERE key = 'policy.enforce_from';

UPDATE public.app_settings
   SET value      = 'true',
       updated_at = timezone('utc'::text, now()),
       help       = help || jsonb_build_object(
		'caveats', 'LIGADO em produção desde 03/10/2026 (F-82), com a política de privacidade 2.1 e os Termos 1.4 publicados. Desligar é a chave de emergência: o que já foi registrado fica, e as recompensas ainda não entregues param de andar enquanto estiver desligado.',
		'requires', 'Política de privacidade 2.1 e Termos 1.4 (regras da indicação) publicados — feito em 03/10/2026.')
 WHERE key = 'feature.referral';

UPDATE public.app_settings
   SET help = help || jsonb_build_object(
		'caveats', 'Mudar com indicações em espera move a data delas também. Um estorno ou chargeback depois da janela não desfaz a recompensa (risco aceito). Os Termos de Uso 1.4 (§10, Indicação de famílias) dizem 30 dias: mudar este número pede a atualização dos Termos na mesma entrega.')
 WHERE key = 'referral.hold_days';

UPDATE public.app_settings
   SET help = help || jsonb_build_object(
		'caveats', 'Uma indicação qualificada além do teto fica "capped" para sempre: não ganha o mês nem no ano seguinte. Recompensas pendentes de trilho (Asaas/Play) contam no teto. Os Termos de Uso 1.4 (§10, Indicação de famílias) dizem 12 por ano civil: mudar este número pede a atualização dos Termos na mesma entrega.')
 WHERE key = 'referral.yearly_cap';
