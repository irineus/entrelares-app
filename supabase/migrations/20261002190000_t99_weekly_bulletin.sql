-- =============================================================================
-- T-99 (02/10/2026) — the weekly sales bulletin, e-mailed to the OPERATOR
--
-- The acquisition chain of October (F-77 trial-end reminders, F-78 unplanned
-- nudge, F-80 referrals) needs a number to move, and every reading so far was
-- a session of hand-written SQL in production. Once a week, on Monday at 09:00
-- in Brasília, the `weekly-bulletin` Edge Function reads ONE aggregate and
-- e-mails it to `contato@entrelares.app` (routed to the owner). It is an
-- e-mail to the operator about the business, never to a user — outside F-59's
-- scope, and one send per week against the shared Resend allowance.
--
-- THE RULE THE PAYLOAD KEEPS (F-69's, owner 02/10/2026): counts, dates and
-- closed enums only. No family or member name, no e-mail, no custom role, no
-- note or message — and, unlike F-69's per-family report, NO family id either:
-- the bulletin is about the product, and an inbox is not an audited console.
-- The DB gate walks the JSON against a closed key list and seeds a free-text
-- marker into a throwaway family to prove none of it comes back.
--
-- WEEKS run Monday..Sunday in America/Sao_Paulo, like every clock of the
-- product. The default week is the one that JUST ENDED (the cron runs on the
-- Monday after it); `p_week_start` names another one (normalised to its
-- Monday) — the gate passes the current week so the rows it seeds are inside.
--
-- THE LINES, and the columns each one rests on:
--   · families created              families.created_at
--   · first channel of those        member_activity_days.channel (T-78) of the
--                                   family's EARLIEST active day; a tie on that
--                                   day reads android > web-installed > web;
--                                   no row at all is `none`
--   · planned within 7 days         care_schedules.created_at < families.created_at + 7 days
--                                   (any lane, F-07). For the newest cohort the
--                                   7 days may still be running: "so far".
--   · invitations sent / accepted   family_invitations.created_at / accepted_at
--   · active families               member_activity_days.day inside the week,
--                                   joined to profiles.family_id
--   · conversions (trial → paid)    a family's FIRST paying event in the
--                                   billing_events ledger falls in the week:
--                                   PAYMENT_CONFIRMED / PAYMENT_RECEIVED (Asaas)
--                                   or PLAY_PURCHASE_VERIFIED / PLAY_RTDN_{1,2,4,7}
--                                   (Play; the activating RTDN types). The rail
--                                   comes from the event, the cycle from the
--                                   family's subscriptions row (single_charge =
--                                   the F-48 Pix avulso). `during_trial` = paid
--                                   before families.trial_ends_at (F-46).
--                                   `subscriptions` has one row per family and
--                                   no "activated at", so the ledger is the only
--                                   honest clock for "became paid".
--   · cancellations                 subscriptions.canceled_at in the week,
--                                   avulso excluded (it rests at 'canceled' by
--                                   design)
--   · went overdue                  subscriptions.overdue_since in the week
--   · F-77 / F-78 sent              trial_end_reminders.sent_at by stage /
--                                   unplanned_family_nudges.sent_at
--   · snapshot (as of generated_at, whatever week was asked):
--       families_total, paying_families (families.plan = 'premium'),
--       trials_ending_7d (trial_ends_at within 7 days, F-77's exclusions plus
--       the comp), dunning (subscriptions.status = 'overdue')
--   · referrals                     NULL — the placeholder F-80 fills.
--
-- ACCESS. Service role only: the Edge Function is the one reader. No client,
-- an operator session included, may call it — the console has F-69 for that.
-- =============================================================================

-- ── 1. The kill switch ──────────────────────────────────────────────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, help)
VALUES
	('ops.weekly_bulletin.enabled', 'true', 'bool', 'operator',
	 'Liga o boletim semanal de vendas enviado ao operador toda segunda às 09:00 (T-99).',
	 false, 'flag', 'normal',
	 jsonb_build_object(
		'controls', 'Se a função weekly-bulletin envia toda segunda-feira, às 09:00 de Brasília, o boletim de vendas da semana anterior para contato@entrelares.app.',
		'shown_at', jsonb_build_array('email'),
		'if_increased', 'Ligado: um e-mail por semana ao operador, só com contagens (nenhum nome, e-mail ou id de família).',
		'if_decreased', 'Desligado: a função roda e sai sem enviar nada. Nenhuma família é afetada.',
		'takes_effect', 'Na próxima segunda-feira às 09:00 (a função lê a chave a cada execução).',
		'caveats', 'Gasta um envio por semana da cota do Resend, compartilhada com os e-mails de conta. No projeto de desenvolvimento os números incluem as famílias de teste.'))
ON CONFLICT (key) DO NOTHING;

-- ── 2. The ledger: one send per week ────────────────────────────────────────
-- The function claims the week here BEFORE it sends and releases the claim if
-- Resend refuses, so a second invocation of the same week (a manual re-run,
-- a retried cron) sends nothing. A dry run never touches it.

CREATE TABLE public.weekly_bulletin_sends (
	week_start date PRIMARY KEY,
	sent_at    timestamp with time zone NOT NULL DEFAULT timezone('utc', now())
);

COMMENT ON TABLE public.weekly_bulletin_sends IS
	'T-99: one row per week whose bulletin went to the operator (week_start = that Monday, São Paulo). Service role only.';

ALTER TABLE public.weekly_bulletin_sends ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.weekly_bulletin_sends FROM anon, authenticated;
GRANT ALL ON public.weekly_bulletin_sends TO service_role;

-- ── 3. One week's lines ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_weekly_sales_bulletin_week(p_week_start date)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	lo     timestamp with time zone := (p_week_start::timestamp AT TIME ZONE 'America/Sao_Paulo');
	hi     timestamp with time zone := ((p_week_start + 7)::timestamp AT TIME ZONE 'America/Sao_Paulo');
	result jsonb;
BEGIN
	WITH
	cohort AS (
		SELECT f.id, f.created_at
		  FROM public.families f
		 WHERE f.created_at >= lo AND f.created_at < hi
	),
	cohort_channel AS (
		SELECT c.id,
		       (SELECT a.channel
		          FROM public.member_activity_days a
		          JOIN public.profiles p ON p.id = a.profile_id
		         WHERE p.family_id = c.id
		         ORDER BY a.day,
		                  CASE a.channel WHEN 'android' THEN 1 WHEN 'web-installed' THEN 2 ELSE 3 END
		         LIMIT 1) AS channel,
		       EXISTS (SELECT 1 FROM public.care_schedules cs
		                WHERE cs.family_id = c.id
		                  AND cs.created_at < c.created_at + interval '7 days') AS planned
		  FROM cohort c
	),
	first_pay AS (
		SELECT DISTINCT ON (e.family_id) e.family_id, e.received_at, e.event_type
		  FROM public.billing_events e
		 WHERE e.family_id IS NOT NULL
		   AND e.event_type IN ('PAYMENT_CONFIRMED', 'PAYMENT_RECEIVED',
		                        'PLAY_PURCHASE_VERIFIED',
		                        'PLAY_RTDN_1', 'PLAY_RTDN_2', 'PLAY_RTDN_4', 'PLAY_RTDN_7')
		 ORDER BY e.family_id, e.received_at, e.id
	),
	converted AS (
		SELECT CASE WHEN fp.event_type LIKE 'PLAY%' THEN 'play' ELSE 'asaas' END AS rail,
		       CASE WHEN s.single_charge THEN 'single'
		            WHEN s.cycle IN ('monthly', 'annual') THEN s.cycle
		            ELSE 'unknown' END AS cycle,
		       (f.trial_ends_at IS NOT NULL AND fp.received_at < f.trial_ends_at) AS during_trial
		  FROM first_pay fp
		  JOIN public.families f ON f.id = fp.family_id
		  LEFT JOIN public.subscriptions s ON s.family_id = fp.family_id
		 WHERE fp.received_at >= lo AND fp.received_at < hi
	)
	SELECT jsonb_build_object(
		'week_start',       p_week_start,
		'families_created', (SELECT count(*) FROM cohort),
		'first_channel', (
			SELECT jsonb_build_object(
				'android',       count(*) FILTER (WHERE channel = 'android'),
				'web',           count(*) FILTER (WHERE channel = 'web'),
				'web_installed', count(*) FILTER (WHERE channel = 'web-installed'),
				'none',          count(*) FILTER (WHERE channel IS NULL))
			  FROM cohort_channel),
		'planned_within_7d', (SELECT count(*) FROM cohort_channel WHERE planned),
		'invitations_sent', (
			SELECT count(*) FROM public.family_invitations i
			 WHERE i.created_at >= lo AND i.created_at < hi),
		'invitations_accepted', (
			SELECT count(*) FROM public.family_invitations i
			 WHERE i.accepted_at >= lo AND i.accepted_at < hi),
		'active_families', (
			SELECT count(DISTINCT p.family_id)
			  FROM public.member_activity_days a
			  JOIN public.profiles p ON p.id = a.profile_id
			 WHERE a.day >= p_week_start AND a.day < p_week_start + 7
			   AND p.family_id IS NOT NULL),
		'conversions', (
			SELECT jsonb_build_object(
				'total',        count(*),
				'during_trial', count(*) FILTER (WHERE during_trial),
				'by_rail', jsonb_build_object(
					'asaas', count(*) FILTER (WHERE rail = 'asaas'),
					'play',  count(*) FILTER (WHERE rail = 'play')),
				'by_cycle', jsonb_build_object(
					'monthly', count(*) FILTER (WHERE cycle = 'monthly'),
					'annual',  count(*) FILTER (WHERE cycle = 'annual'),
					'single',  count(*) FILTER (WHERE cycle = 'single'),
					'unknown', count(*) FILTER (WHERE cycle = 'unknown')))
			  FROM converted),
		'cancellations', (
			SELECT count(*) FROM public.subscriptions s
			 WHERE s.canceled_at >= lo AND s.canceled_at < hi
			   AND NOT s.single_charge),
		'overdue_started', (
			SELECT count(*) FROM public.subscriptions s
			 WHERE s.overdue_since >= lo AND s.overdue_since < hi),
		'trial_reminders', (
			SELECT jsonb_build_object(
				'd7',    count(*) FILTER (WHERE t.stage = 'd7'),
				'd1',    count(*) FILTER (WHERE t.stage = 'd1'),
				'ended', count(*) FILTER (WHERE t.stage = 'ended'))
			  FROM public.trial_end_reminders t
			 WHERE t.sent_at >= lo AND t.sent_at < hi),
		'unplanned_nudges', (
			SELECT count(*) FROM public.unplanned_family_nudges n
			 WHERE n.sent_at >= lo AND n.sent_at < hi)
	) INTO result;

	RETURN result;
END;
$$;

COMMENT ON FUNCTION public.admin_weekly_sales_bulletin_week(date) IS
	'T-99: the lines of ONE week (Monday p_week_start, São Paulo) of the operator''s weekly bulletin — counts only. Service role only.';

ALTER FUNCTION public.admin_weekly_sales_bulletin_week(date) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_weekly_sales_bulletin_week(date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_weekly_sales_bulletin_week(date) TO service_role;

-- ── 4. The bulletin ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_weekly_sales_bulletin(p_week_start date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	today  date := (timezone('America/Sao_Paulo', now()))::date;
	w0     date;
	weeks  jsonb[] := ARRAY[]::jsonb[];
	trend  jsonb := '[]'::jsonb;
	i      int;
	wk     jsonb;
BEGIN
	-- Monday of the asked week; by default the week that just ended.
	w0 := COALESCE(date_trunc('week', p_week_start::timestamp)::date,
	               date_trunc('week', today::timestamp)::date - 7);

	-- weeks[1] = this week, weeks[2] = the one before, … weeks[4].
	FOR i IN 0..3 LOOP
		weeks := array_append(weeks, public.admin_weekly_sales_bulletin_week(w0 - 7 * i));
	END LOOP;

	-- Oldest first, the four main lines only.
	FOR i IN REVERSE 4..1 LOOP
		wk := weeks[i];
		trend := trend || jsonb_build_array(jsonb_build_object(
			'week_start',        wk -> 'week_start',
			'families_created',  wk -> 'families_created',
			'active_families',   wk -> 'active_families',
			'invitations_sent',  wk -> 'invitations_sent',
			'conversions_total', wk -> 'conversions' -> 'total'));
	END LOOP;

	RETURN jsonb_build_object(
		'report_version', 1,
		'generated_at',   now(),
		'week_start',     w0,
		'week_end',       w0 + 6,
		'this_week',      weeks[1],
		'previous_week',  weeks[2],
		'trend',          trend,
		'snapshot', jsonb_build_object(
			'families_total',  (SELECT count(*) FROM public.families),
			'paying_families', (SELECT count(*) FROM public.families f WHERE f.plan = 'premium'),
			'trials_ending_7d', (
				SELECT count(*) FROM public.families f
				 WHERE f.trial_ends_at > now()
				   AND f.trial_ends_at <= now() + interval '7 days'
				   AND f.plan <> 'premium'
				   AND f.comp_premium_at IS NULL
				   AND NOT EXISTS (
				       SELECT 1 FROM public.subscriptions s
				        WHERE s.family_id = f.id
				          AND s.status IN ('active', 'scheduled', 'overdue'))),
			'dunning', (SELECT count(*) FROM public.subscriptions s WHERE s.status = 'overdue')),
		-- F-80 (referrals) fills this; until then the e-mail says it is not
		-- measured yet. A key, not an absence, so the gate's closed list
		-- already names it and F-80 only changes its value.
		'referrals', NULL
	);
END;
$$;

COMMENT ON FUNCTION public.admin_weekly_sales_bulletin(date) IS
	'T-99: the operator''s weekly sales bulletin (default: the week that just ended, Monday..Sunday São Paulo) vs the week before, a 4-week trend and a snapshot — counts, dates and closed enums only, never a name, an e-mail or a family id. Service role only; read by the weekly-bulletin Edge Function.';

ALTER FUNCTION public.admin_weekly_sales_bulletin(date) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_weekly_sales_bulletin(date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_weekly_sales_bulletin(date) TO service_role;

-- ── 5. Schedule: Monday at 09:00 in Brasília ─────────────────────────────────
-- 12:00 UTC on Mondays. The job only calls the Edge Function (which reads the
-- aggregate, the switch and the ledger, and sends through Resend) with the
-- SAME Vault secrets the push trigger and F-70's job read, so a project armed
-- for push is armed for this. An unarmed project fails the call in cron's own
-- log and nothing else. cron.schedule upserts by name, so a re-run is safe.

SELECT cron.schedule(
	'weekly-bulletin',
	'0 12 * * 1',
	$cron$
	SELECT net.http_post(
		url     := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'functions_base_url')
		           || '/weekly-bulletin',
		headers := jsonb_build_object(
			'Content-Type', 'application/json',
			'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'secret_key')),
		body    := '{}'::jsonb,
		timeout_milliseconds := 30000);
	$cron$
);
