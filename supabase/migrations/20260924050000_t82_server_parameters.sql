-- =============================================================================
-- T-82 (PR 2) — server-first operator parameters
--
-- Values that were hardcoded but are operating knobs become `app_settings`
-- keys, each born with the T-80 metadata (the completeness gate refuses one
-- without it). Ranges decided by the owner (23/09/2026); the Asaas one on
-- 24/09/2026, because the Asaas docs set no limit (see the key's help).
--
--   trial.days               30   0–90 days   — new-family trial (column default)
--   invitation.valid_days     7   1–30 days   — new invitations (column default);
--                                               the 30-day stale purge stays FIXED
--                                               (privacy §, counted from creation)
--   email_quota.warn_percent 80   50–95 %     — the free tier's heads-up threshold
--   billing.asaas_due_days    5   1–30 business days — payment-link boletos
--   usage_report.weeks       12   4–52 weeks  — F-69 report, operator only
--   usage_report.active_days 30   7–90 days   — F-69 report, operator only
--
-- Both column defaults read the key, so the default stays the single writer:
-- existing trials and invitations never move. `consume_email_quota` and
-- `admin_family_usage_report` are recreated from their LATEST definitions
-- (20260806180000 and 20260923200000, re-checked 24/09/2026); the report now
-- also says which windows it used (`windows`), so the console can print them.
-- =============================================================================

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, min_value, max_value, help)
VALUES
	('trial.days', '30', 'int', 'billing',
	 'Dias de Premium de teste que toda família nova ganha ao ser criada.',
	 false, 'days', 'sensitive', 0, 90,
	 jsonb_build_object(
		'controls', 'O prazo do teste gratuito do Premium: o valor padrão de families.trial_ends_at, gravado quando a família é criada.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Famílias NOVAS testam o Premium por mais tempo; as que já existem mantêm o prazo que ganharam.',
		'if_decreased', 'Famílias NOVAS testam por menos tempo. 0 = nenhuma família nova ganha teste.',
		'takes_effect', 'Na próxima família criada.',
		'caveats', 'Nunca move um teste já em andamento. A tela do plano mostra a data de fim, calculada por família.')),
	('invitation.valid_days', '7', 'int', 'freemium',
	 'Dias que um convite novo fica válido antes de expirar.',
	 false, 'days', 'normal', 1, 30,
	 jsonb_build_object(
		'controls', 'A validade de um convite: o valor padrão de family_invitations.expires_at, gravado quando o convite é criado ou reenviado.',
		'shown_at', jsonb_build_array('app', 'email'),
		'if_increased', 'Convites NOVOS valem por mais dias; o e-mail do convite diz o prazo daquele convite.',
		'if_decreased', 'Convites NOVOS expiram antes; os já enviados mantêm a data que tinham.',
		'takes_effect', 'No próximo convite criado ou reenviado.',
		'caveats', 'Teto 30: a purga de convites não aceitos apaga o registro 30 dias após o envio (política de privacidade) e nunca pode alcançar um convite ainda válido.')),
	('email_quota.warn_percent', '80', 'int', 'freemium',
	 'Percentual da cota de e-mails do gratuito em que a família recebe o aviso.',
	 false, 'percent', 'normal', 50, 95,
	 jsonb_build_object(
		'controls', 'Quando consume_email_quota avisa uma família gratuita de que a cota do mês está acabando (notificação no app + e-mail aos administradores).',
		'shown_at', jsonb_build_array('app', 'email'),
		'if_increased', 'O aviso chega mais tarde, mais perto do fim da cota.',
		'if_decreased', 'O aviso chega mais cedo; a família tem mais tempo para reagir.',
		'takes_effect', 'No próximo e-mail enviado; cada família é avisada uma vez por mês.',
		'caveats', 'Só o plano gratuito recebe o aviso; o Premium roda contra o teto anti-abuso sem aviso.')),
	('billing.asaas_due_days', '5', 'int', 'billing',
	 'Dias úteis que um boleto gerado pelo link de pagamento do Asaas pode ser pago.',
	 false, 'days', 'sensitive', 1, 30,
	 jsonb_build_object(
		'controls', 'O dueDateLimitDays dos links de pagamento que billing-checkout cria no Asaas: quantos dias ÚTEIS o boleto gerado pode ser pago. Pix e cartão liquidam na hora.',
		'shown_at', jsonb_build_array('server_only'),
		'if_increased', 'Um boleto aberto fica pagável por mais tempo — o Premium da família espera o pagamento.',
		'if_decreased', 'Boletos vencem antes; quem demora para pagar precisa gerar outro.',
		'takes_effect', 'No próximo link de pagamento criado.',
		'caveats', 'O Asaas não documenta mínimo nem máximo (docs.asaas.com/reference/criar-um-link-de-pagamentos e /docs/criando-um-link-de-pagamentos, lidos em 24/09/2026 — o exemplo é 10). A faixa 1–30 é decisão do owner (24/09/2026). São dias úteis, não corridos.')),
	('usage_report.weeks', '12', 'int', 'operator',
	 'Semanas que o relatório de uso da família mostra no console.',
	 false, 'count', 'normal', 4, 52,
	 jsonb_build_object(
		'controls', 'Quantas semanas admin_family_usage_report devolve na série semanal (edições, trocas, membros ativos).',
		'shown_at', jsonb_build_array('server_only'),
		'if_increased', 'O relatório olha mais para trás; a consulta fica mais pesada.',
		'if_decreased', 'O relatório fica mais curto e mais focado no presente.',
		'takes_effect', 'No próximo relatório aberto no console.',
		'caveats', 'Só o operador lê. O relatório devolve a janela usada (windows.weeks) para o console escrever o número certo.')),
	('usage_report.active_days', '30', 'int', 'operator',
	 'Janela, em dias, dos "dias de uso" e canais por membro no relatório de uso.',
	 false, 'days', 'normal', 7, 90,
	 jsonb_build_object(
		'controls', 'A janela de active_days_30 e channels_30 em admin_family_usage_report (os nomes das chaves ficaram por compatibilidade; o número é este).',
		'shown_at', jsonb_build_array('server_only'),
		'if_increased', 'Mais dias contados; um membro que parou há pouco ainda aparece ativo.',
		'if_decreased', 'Menos dias; a parada de um membro aparece mais cedo.',
		'takes_effect', 'No próximo relatório aberto no console.',
		'caveats', 'Não pode passar da retenção de member_activity_days (400 dias). O relatório devolve a janela usada (windows.active_days).'))
ON CONFLICT (key) DO NOTHING;

-- ── The two column defaults: the single writer stays the default ────────────

ALTER TABLE public.families
	ALTER COLUMN trial_ends_at
	SET DEFAULT timezone('utc', now()) + make_interval(days => public.setting_int('trial.days', 30));

ALTER TABLE public.family_invitations
	ALTER COLUMN expires_at
	SET DEFAULT timezone('utc', now()) + make_interval(days => public.setting_int('invitation.valid_days', 7));

-- ── consume_email_quota — the heads-up threshold from the key ───────────────
-- Body from 20260806180000_u13_notification_params_rest.sql; the stored title and
-- sentence carry the configured number, and `params.percent` lets the app render
-- it (a row written before this migration has none and renders 80, which is what
-- it was written at).

CREATE OR REPLACE FUNCTION public.consume_email_quota(p_family_id bigint)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	is_prem boolean;
	cap     int;
	warn_at int;
	warn_pct int := public.setting_int('email_quota.warn_percent', 80);
	last_at int;
	ym      text := to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM');
	cur     int;
BEGIN
	is_prem := public.is_premium(p_family_id);
	-- Per-tier cap — nothing is truly unlimited: premium runs against a HIGH
	-- anti-abuse cap. Both tiers are counted and enforced (T-41 config).
	cap     := CASE WHEN is_prem THEN public.setting_int('email_cap_premium', 10000)
	                             ELSE public.setting_int('email_cap_free', 100) END;
	warn_at := cap * warn_pct / 100;   -- T-82: the heads-up threshold
	last_at := cap - 1;       -- one slot left; the free warning takes it

	-- Atomically consume one unit while under the cap. A NULL return means the
	-- row was already at the cap (the counter never climbs past it).
	INSERT INTO public.email_usage (family_id, year_month, sent_count)
	VALUES (p_family_id, ym, 1)
	ON CONFLICT (family_id, year_month) DO UPDATE
		SET sent_count = email_usage.sent_count + 1
		WHERE email_usage.sent_count < cap
	RETURNING sent_count INTO cur;

	IF cur IS NULL THEN
		-- Over the cap (either tier): skip the real e-mail. First denial → one
		-- in-app notification (tier-aware — no "upgrade" nudge for premium).
		UPDATE public.email_usage SET upsell_notified = true
		WHERE family_id = p_family_id AND year_month = ym AND upsell_notified = false;
		IF FOUND THEN
			IF is_prem THEN
				-- U-13: one type, two wordings — `tier` is the discriminator.
				PERFORM public.notify_family_email_cap(p_family_id, 'email_cap_reached',
					'Limite de e-mails do mês atingido',
					'Sua família atingiu o limite de e-mails deste mês. As notificações aqui no app seguem normais.',
					jsonb_build_object('tier', 'premium'));
			ELSE
				PERFORM public.notify_family_email_cap(p_family_id, 'email_cap_reached',
					'Limite de e-mails do plano gratuito',
					'Sua família atingiu o limite de e-mails deste mês no plano gratuito. As notificações aqui no app seguem normais — ative o Premium para um limite bem maior.',
					jsonb_build_object('tier', 'free'));
			END IF;
		END IF;
		RETURN 'denied';
	END IF;

	-- Proactive heads-ups are FREE-tier conversion nudges only — premium just runs
	-- against its high anti-abuse cap, with no upsell.
	IF NOT is_prem THEN
		-- Last-e-mail heads-up: the warning e-mail itself takes the final slot, so
		-- it is literally the last e-mail of the month.
		IF cur >= last_at THEN
			UPDATE public.email_usage SET warned_last = true, sent_count = cap
			WHERE family_id = p_family_id AND year_month = ym AND warned_last = false;
			IF FOUND THEN
				PERFORM public.notify_family_email_cap(p_family_id, 'email_cap_last',
					'Último e-mail do mês',
					'Este é o último e-mail do mês no plano gratuito. As notificações aqui no app seguem normais — ative o Premium para um limite bem maior.',
					jsonb_build_object('tier', 'free'));
				RETURN 'warn_last';
			END IF;
			RETURN 'allowed';   -- already warned this month
		END IF;

		-- The heads-up (T-82: `email_quota.warn_percent`, default 80) does NOT
		-- consume a slot.
		IF cur >= warn_at THEN
			UPDATE public.email_usage SET warned_80 = true
			WHERE family_id = p_family_id AND year_month = ym AND warned_80 = false;
			IF FOUND THEN
				PERFORM public.notify_family_email_cap(p_family_id, 'email_cap_80',
					'E-mails do mês em ' || warn_pct || '%',
					'Sua família já usou ' || warn_pct || '% dos e-mails deste mês (plano gratuito). As notificações aqui no app seguem sem limite — ative o Premium para um limite bem maior.',
					jsonb_build_object('tier', 'free', 'percent', warn_pct::text));
				RETURN 'warn_80';
			END IF;
			RETURN 'allowed';
		END IF;
	END IF;

	RETURN 'allowed';
END;
$$;

ALTER FUNCTION public.consume_email_quota(bigint) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.notify_family_email_cap(bigint, text, text, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notify_family_email_cap(bigint, text, text, text, jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.consume_email_quota(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_email_quota(bigint) TO service_role;

-- ── admin_family_usage_report — the windows from the keys ───────────────────
-- Body from 20260923200000_f69_member_dates_for_sorting.sql. The key names
-- `active_days_30` / `channels_30` stay (the console reads them); the number is
-- `usage_report.active_days`, and `windows` says which ones were used.

CREATE OR REPLACE FUNCTION public.admin_family_usage_report(p_family_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	fam        public.families%ROWTYPE;
	today      date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	first_week date;
	weeks      int := public.setting_int('usage_report.weeks', 12);
	active_win int := public.setting_int('usage_report.active_days', 30);
	premium    boolean;
	result     jsonb;
BEGIN
	IF NOT public.is_platform_operator() THEN
		RAISE EXCEPTION 'Acesso restrito à operação da plataforma.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	SELECT * INTO fam FROM public.families WHERE id = p_family_id;

	INSERT INTO public.operator_audit_logs (operator_user_id, action, family_id, new_value)
	VALUES (auth.uid(), 'family_usage_report', fam.id, p_family_id::text);

	IF fam.id IS NULL THEN
		RETURN NULL;
	END IF;

	premium    := public.is_premium(fam.id);
	first_week := date_trunc('week', today)::date - 7 * (weeks - 1);

	WITH
	days AS (
		SELECT
			d.schedule_date                                       AS day,
			COALESCE(d.actual_parent_id, d.scheduled_parent_id)   AS carer,
			d.scheduled_parent_id                                 AS planned,
			d.actual_parent_id                                    AS actual,
			d.handoff_time,
			NULLIF(btrim(d.notes), '') IS NOT NULL                AS has_note,
			(p.id IS NULL
			 OR COALESCE(p.actual_parent_id, p.scheduled_parent_id)
			    IS DISTINCT FROM COALESCE(d.actual_parent_id, d.scheduled_parent_id))
			                                                      AS transition
		FROM public.care_schedules d
		LEFT JOIN public.care_schedules p
		       ON p.family_id = d.family_id AND p.schedule_date = d.schedule_date - 1
		WHERE d.family_id = fam.id
	),
	edits AS (
		SELECT
			(l.created_at AT TIME ZONE 'America/Sao_Paulo')::date AS day,
			l.performed_by_id,
			COALESCE(l.context ->> 'batch_id',
			         l.performed_by_id::text || '@' || l.created_at::text) AS unit,
			COALESCE((l.context ->> 'admin_override')::boolean, false) AS override
		FROM public.activity_logs l
		WHERE l.family_id = fam.id
		  AND l.created_at >= (first_week::timestamp AT TIME ZONE 'America/Sao_Paulo')
	),
	weeks AS (
		SELECT w::date AS week_start
		FROM generate_series(first_week, date_trunc('week', today)::date, interval '7 days') w
	)
	SELECT jsonb_build_object(
		'report_version', 1,
		'generated_at',   now(),
		'today',          today,
		'windows',        jsonb_build_object('weeks', weeks, 'active_days', active_win),

		'family', jsonb_build_object(
			'id',              fam.id,
			'created_at',      fam.created_at,
			'plan',            fam.plan,
			'is_premium',      premium,
			'trial_ends_at',   fam.trial_ends_at,
			'comp_premium_at', fam.comp_premium_at,
			'seats_used',      public.seat_count(fam.id),
			'seats_cap',       CASE WHEN premium
			                        THEN public.setting_int('max_caregivers', 4)
			                        ELSE public.setting_int('free_caregivers', 2) END,
			'subscription', (
				SELECT jsonb_build_object(
					'gateway',            s.gateway,
					'status',             s.status,
					'cycle',              s.cycle,
					'current_period_end', s.current_period_end,
					'overdue_since',      s.overdue_since,
					'canceled_at',        s.canceled_at
				)
				FROM public.subscriptions s WHERE s.family_id = fam.id
			),
			'invitations', (
				SELECT jsonb_build_object(
					'open',     COUNT(*) FILTER (WHERE i.accepted_at IS NULL AND i.revoked_at IS NULL AND i.expires_at > now()),
					'accepted', COUNT(*) FILTER (WHERE i.accepted_at IS NOT NULL),
					'expired',  COUNT(*) FILTER (WHERE i.accepted_at IS NULL AND i.revoked_at IS NULL AND i.expires_at <= now()),
					'revoked',  COUNT(*) FILTER (WHERE i.accepted_at IS NULL AND i.revoked_at IS NOT NULL),
					'oldest_open_created_at',
					            MIN(i.created_at) FILTER (WHERE i.accepted_at IS NULL AND i.revoked_at IS NULL AND i.expires_at > now())
				)
				FROM public.family_invitations i WHERE i.family_id = fam.id
			)
		),

		'members', (
			SELECT COALESCE(jsonb_agg(jsonb_build_object(
				'profile_id',             p.id,
				'role',                   CASE WHEN r.family_id IS NULL THEN r.role ELSE 'custom' END,
				'is_admin',               p.is_admin,
				'state',                  CASE WHEN p.left_at IS NOT NULL THEN 'departed'
				                               WHEN p.user_id IS NULL     THEN 'pending'
				                               ELSE 'active' END,
				'created_at',             p.created_at,
				'joined_via_invite',      p.joined_via_invite,
				'left_at',                p.left_at,
				'has_password',           (SELECT COALESCE(u.encrypted_password, '') <> ''
				                           FROM auth.users u WHERE u.id = p.user_id),
				'has_google',             EXISTS (SELECT 1 FROM auth.identities i
				                                  WHERE i.user_id = p.user_id AND i.provider = 'google'),
				'language',               p.language_effective,
				'tour_seen_at',           p.onboarding_tour_seen_at,
				'consent_policy_version', p.consent_policy_version,
				'consent_accepted_at',    p.consent_accepted_at,
				'last_active_day',        la.last_day,
				'last_active_source',     la.last_source,
				'active_days_30', (
					SELECT COUNT(DISTINCT a.day) FROM public.member_activity_days a
					WHERE a.profile_id = p.id AND a.day > today - active_win
				),
				'channels_30', (
					SELECT COALESCE(jsonb_agg(DISTINCT a.channel), '[]'::jsonb)
					FROM public.member_activity_days a
					WHERE a.profile_id = p.id AND a.day > today - active_win
				),
				'devices', (
					SELECT COALESCE(jsonb_agg(jsonb_build_object(
						'platform',     ps.platform,
						'count',        ps.n,
						'last_seen_at', ps.last_seen
					) ORDER BY ps.platform), '[]'::jsonb)
					FROM (
						SELECT platform, COUNT(*) AS n, MAX(last_seen_at) AS last_seen
						FROM public.push_subscriptions
						WHERE profile_id = p.id
						GROUP BY platform
					) ps
				),
				'unread', (
					SELECT COALESCE(jsonb_agg(jsonb_build_object(
						'type',  un.type,
						'count', un.n
					) ORDER BY un.type), '[]'::jsonb)
					FROM (
						SELECT type, COUNT(*) AS n
						FROM public.notifications
						WHERE recipient_profile_id = p.id AND NOT COALESCE(is_read, false)
						GROUP BY type
					) un
				)
			) ORDER BY p.id), '[]'::jsonb)
			FROM public.profiles p
			LEFT JOIN public.roles r ON r.id = p.role_id
			LEFT JOIN LATERAL public.member_last_active(p.id) la ON true
			WHERE p.family_id = fam.id
		),

		'plan', (
			SELECT jsonb_build_object(
				'first_day',                   MIN(day),
				'last_day',                    MAX(day),
				'days_total',                  COUNT(*),
				'days_ahead',                  COUNT(*) FILTER (WHERE day >= today),
				'days_with_handoff_time',      COUNT(*) FILTER (WHERE handoff_time IS NOT NULL),
				'days_with_note',              COUNT(*) FILTER (WHERE has_note),
				'days_diverged',               COUNT(*) FILTER (WHERE actual IS NOT NULL AND actual IS DISTINCT FROM planned),
				'transitions_ahead',           COUNT(*) FILTER (WHERE day >= today AND transition),
				'transitions_ahead_with_time', COUNT(*) FILTER (WHERE day >= today AND transition AND handoff_time IS NOT NULL),
				'carers_ahead', (
					SELECT COALESCE(jsonb_agg(jsonb_build_object(
						'profile_id', c.carer,
						'days',       c.n
					) ORDER BY c.carer), '[]'::jsonb)
					FROM (
						SELECT carer, COUNT(*) AS n FROM days
						WHERE day >= today AND carer IS NOT NULL
						GROUP BY carer
					) c
				)
			)
			FROM days
		),

		'weeks', (
			SELECT COALESCE(jsonb_agg(jsonb_build_object(
				'week_start', wk.week_start,
				'edits', (
					SELECT COUNT(DISTINCT e.unit) FROM edits e
					WHERE e.day >= wk.week_start AND e.day < wk.week_start + 7
				),
				'edits_by_member', (
					SELECT COALESCE(jsonb_agg(jsonb_build_object(
						'profile_id', em.performed_by_id,
						'count',      em.n
					) ORDER BY em.performed_by_id), '[]'::jsonb)
					FROM (
						SELECT e.performed_by_id, COUNT(DISTINCT e.unit) AS n
						FROM edits e
						WHERE e.day >= wk.week_start AND e.day < wk.week_start + 7
						GROUP BY e.performed_by_id
					) em
				),
				'admin_overrides', (
					SELECT COUNT(DISTINCT e.unit) FROM edits e
					WHERE e.override AND e.day >= wk.week_start AND e.day < wk.week_start + 7
				),
				'swaps_opened', (
					SELECT COUNT(*) FROM public.swap_requests s
					WHERE s.family_id = fam.id
					  AND (s.created_at AT TIME ZONE 'America/Sao_Paulo')::date >= wk.week_start
					  AND (s.created_at AT TIME ZONE 'America/Sao_Paulo')::date <  wk.week_start + 7
				),
				'swaps_resolved', (
					SELECT COUNT(*) FROM public.swap_requests s
					WHERE s.family_id = fam.id
					  AND (s.resolved_at AT TIME ZONE 'America/Sao_Paulo')::date >= wk.week_start
					  AND (s.resolved_at AT TIME ZONE 'America/Sao_Paulo')::date <  wk.week_start + 7
				),
				'notices', (
					SELECT COUNT(*) FROM public.day_notices n
					WHERE n.family_id = fam.id
					  AND (n.created_at AT TIME ZONE 'America/Sao_Paulo')::date >= wk.week_start
					  AND (n.created_at AT TIME ZONE 'America/Sao_Paulo')::date <  wk.week_start + 7
				),
				'day_accounts', (
					SELECT COUNT(*) FROM public.day_accounts da
					WHERE da.family_id = fam.id
					  AND (da.created_at AT TIME ZONE 'America/Sao_Paulo')::date >= wk.week_start
					  AND (da.created_at AT TIME ZONE 'America/Sao_Paulo')::date <  wk.week_start + 7
				),
				'active_members', (
					SELECT COUNT(DISTINCT a.profile_id)
					FROM public.member_activity_days a
					JOIN public.profiles p ON p.id = a.profile_id
					WHERE p.family_id = fam.id
					  AND a.day >= wk.week_start AND a.day < wk.week_start + 7
				)
			) ORDER BY wk.week_start), '[]'::jsonb)
			FROM weeks wk
		),

		'swaps', jsonb_build_object(
			'by_status', (
				SELECT COALESCE(jsonb_agg(jsonb_build_object(
					'status',      bs.status,
					'resolved_by', bs.resolved_by,
					'count',       bs.n
				) ORDER BY bs.status, bs.resolved_by), '[]'::jsonb)
				FROM (
					SELECT status, resolved_by, COUNT(*) AS n
					FROM public.swap_requests
					WHERE family_id = fam.id
					GROUP BY status, resolved_by
				) bs
			),
			-- The COUNTERPART's answer: approved or rejected by a person. A
			-- cancellation is the requester's own act and an auto-approval
			-- (F-24, resolved_by 'system') is nobody's — both would skew it.
			'median_answer_hours', (
				SELECT round((percentile_cont(0.5) WITHIN GROUP (
					ORDER BY extract(epoch FROM s.resolved_at - s.created_at) / 3600.0))::numeric, 1)
				FROM public.swap_requests s
				WHERE s.family_id = fam.id
				  AND s.resolved_by = 'user'
				  AND s.status IN ('approved', 'rejected', 'revert_approved', 'revert_rejected')
				  AND s.resolved_at IS NOT NULL
			),
			'pending', (
				SELECT COUNT(*) FROM public.swap_requests s
				WHERE s.family_id = fam.id AND s.status IN ('pending', 'revert_pending')
			),
			'oldest_pending_created_at', (
				SELECT MIN(s.created_at) FROM public.swap_requests s
				WHERE s.family_id = fam.id AND s.status IN ('pending', 'revert_pending')
			)
		),

		'notices', jsonb_build_object(
			'total', (SELECT COUNT(*) FROM public.day_notices n WHERE n.family_id = fam.id),
			'by_outcome', (
				SELECT COALESCE(jsonb_agg(jsonb_build_object(
					'outcome', bo.outcome,
					'count',   bo.n
				) ORDER BY bo.outcome), '[]'::jsonb)
				FROM (
					SELECT COALESCE(o.outcome, 'none') AS outcome, COUNT(*) AS n
					FROM public.day_notices n
					LEFT JOIN public.day_notice_outcomes o ON o.notice_id = n.id
					WHERE n.family_id = fam.id
					GROUP BY COALESCE(o.outcome, 'none')
				) bo
			)
		),

		'day_accounts', jsonb_build_object(
			'total',       (SELECT COUNT(*) FROM public.day_accounts da WHERE da.family_id = fam.id),
			'corrections', (SELECT COUNT(*) FROM public.day_accounts da
			                WHERE da.family_id = fam.id AND da.corrects_id IS NOT NULL)
		)
	) INTO result;

	RETURN result;
END;
$$;

COMMENT ON FUNCTION public.admin_family_usage_report(bigint) IS
	'F-69: one family''s usage report for the operator console — counts, dates, ids and closed enums only, never free text. Operator-gated; every call (an unknown family included) is written to operator_audit_logs. Read-only, no sudo.';

ALTER FUNCTION public.admin_family_usage_report(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_family_usage_report(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_family_usage_report(bigint) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_family_usage_report(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_family_usage_report(bigint) TO service_role;
