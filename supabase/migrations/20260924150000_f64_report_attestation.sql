-- =============================================================================
-- F-64 (PR 1 of 2) — the verifiable report: an attestation the server writes
--
-- Decisions locked by the owner (24/09/2026, F-64 Notes): the shape is an
-- ATTESTED SUMMARY + HASH. When the PDF is generated the app calls
-- `issue_report_attestation(period)`; the SERVER computes, from the database,
-- a summary WITHOUT names (days per caregiver by initials, swaps, relatos) and
-- the app then attaches the SHA-256 of the final PDF bytes. No document body is
-- ever stored. The PDF carries a QR to `web.entrelares.app/verificar/<id>` — a
-- public page (no login, noindex, the id kept out of Umami and Sentry: it is a
-- capability) that shows issue, period, summary and fingerprint and compares a
-- dropped PDF's hash LOCALLY. Valid 12 months, then purged by cron; an expired
-- or revoked id says so (never a 404); the family admin revokes. Premium, gated
-- on the server; after a downgrade an issued attestation stays verifiable
-- until it expires. Dark in production (`feature.report_attestation`).
--
--   * The id is a random uuid — the capability the QR carries. Nothing behind
--     it names anyone: the summary holds initials and counts.
--   * `verify_report_attestation` is callable by `anon` and answers a closed
--     state: valid | pending (issued, the PDF never finalised) | revoked |
--     expired | unknown.
--   * The purge keeps the id, the issue date and the expiry, and drops the
--     rest — so "vencido" is still the answer a year later, not "não existe".
--   * A viewer (F-50) issues nothing: the table carries the viewer guard.
--   * F-69: counts only.
-- =============================================================================


-- ── 1. The keys (T-84 catalogue) ─────────────────────────────────────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, min_value, max_value, help)
VALUES
	('feature.report_attestation', 'false', 'bool', 'features',
	 'Liga o relatório verificável (F-64): QR no PDF e página pública de conferência. Desligado, o servidor não emite atestado.',
	 true, 'flag', 'critical', NULL, NULL,
	 jsonb_build_object(
		'controls', 'Se issue_report_attestation aceita emitir. Atestados já emitidos continuam conferíveis na página /verificar até vencer.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Ligado: o PDF de uma família Premium sai com QR e impressão digital, conferíveis por quem o recebe.',
		'if_decreased', 'Desligado: o PDF volta a sair sem QR; os atestados já emitidos seguem valendo até vencer.',
		'takes_effect', 'Servidor na próxima emissão; app na próxima geração do PDF.',
		'caveats', 'Produção nasce desligada: o S-22 liga junto com a política e a frase de entrelares.app/relatorio.')),
	('report_attestation.premium_only', 'true', 'bool', 'reports',
	 'Só o Premium emite relatório verificável.',
	 true, 'flag', 'critical', NULL, NULL,
	 jsonb_build_object(
		'controls', 'Se issue_report_attestation recusa família sem Premium.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Ligado (padrão): o QR de conferência é benefício Premium; o PDF gratuito sai sem ele.',
		'if_decreased', 'Desligado: toda família emite PDF verificável.',
		'takes_effect', 'Servidor na próxima emissão; app na próxima geração do PDF.',
		'caveats', 'Rebaixamento não apaga nada: um atestado emitido segue conferível até vencer.')),
	('report_attestation.valid_months', '12', 'int', 'reports',
	 'Por quantos meses um relatório verificável pode ser conferido.',
	 true, 'months', 'sensitive', 1, 36,
	 jsonb_build_object(
		'controls', 'O prazo de um atestado novo: depois dele, a página /verificar diz que venceu e o resumo e a impressão digital são apagados pelo purge.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Atestados conferíveis por mais tempo; mais linhas guardadas.',
		'if_decreased', 'Só atestados NOVOS vencem antes; os emitidos guardam o prazo que tinham.',
		'takes_effect', 'Na próxima emissão.',
		'caveats', 'O prazo é gravado no atestado ao emitir: mudar a chave não mexe nos que já existem.'))
ON CONFLICT (key) DO NOTHING;


-- ── 2. The attestation ───────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.report_attestations (
	id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	-- Nullable: the purge drops it with the rest.
	family_id    bigint REFERENCES public.families(id) ON DELETE CASCADE,
	period_from  date,
	period_to    date,
	issued_at    timestamptz NOT NULL DEFAULT now(),
	issued_by    bigint REFERENCES public.profiles(id) ON DELETE SET NULL,
	-- Initials and counts — never a name, never a free text.
	summary      jsonb,
	sha256       text CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$'),
	expires_at   timestamptz NOT NULL,
	revoked_at   timestamptz,
	revoked_by   bigint REFERENCES public.profiles(id) ON DELETE SET NULL,
	purged_at    timestamptz,
	CONSTRAINT report_attestations_period CHECK (period_from IS NULL OR period_to >= period_from)
);

CREATE INDEX IF NOT EXISTS report_attestations_family_idx
	ON public.report_attestations (family_id, issued_at DESC);
CREATE INDEX IF NOT EXISTS report_attestations_purge_idx
	ON public.report_attestations (expires_at) WHERE purged_at IS NULL;

ALTER TABLE public.report_attestations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS report_attestations_family_read ON public.report_attestations;
CREATE POLICY report_attestations_family_read ON public.report_attestations
	FOR SELECT TO authenticated
	USING (family_id = public.get_my_family_id());

REVOKE ALL ON public.report_attestations FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.report_attestations TO authenticated;
GRANT ALL ON public.report_attestations TO service_role;

-- F-50: a viewer issues and revokes nothing.
DROP TRIGGER IF EXISTS trigger_a_refuse_viewer_write ON public.report_attestations;
CREATE TRIGGER trigger_a_refuse_viewer_write
	BEFORE INSERT OR UPDATE OR DELETE ON public.report_attestations
	FOR EACH ROW EXECUTE FUNCTION public.refuse_viewer_write();


-- ── 3. The summary the server attests ────────────────────────────────────────
-- Initials of a caregiver: the first letter of the first and of the last
-- word, upper case ("Ana Souza Lima" → "AL"). Two caregivers with the same
-- initials stay two rows: the row is per caregiver, the initials only label it.

CREATE OR REPLACE FUNCTION public.report_initials(p_name text)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $$
	SELECT upper(left(w[1], 1) ||
	             CASE WHEN array_length(w, 1) > 1 THEN left(w[array_length(w, 1)], 1) ELSE '' END)
	FROM (SELECT regexp_split_to_array(btrim(coalesce(p_name, '')), '\s+') AS w) t;
$$;

REVOKE ALL ON FUNCTION public.report_initials(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.report_initials(text) TO service_role;

CREATE OR REPLACE FUNCTION public.report_attestation_summary(p_family_id bigint, p_from date, p_to date)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
	SELECT jsonb_build_object(
		'days_planned', (
			SELECT count(*) FROM public.care_schedules cs
			WHERE cs.family_id = p_family_id AND cs.schedule_date BETWEEN p_from AND p_to),
		'days_by_caregiver', (
			SELECT COALESCE(jsonb_agg(jsonb_build_object(
				'initials', x.initials, 'days', x.days) ORDER BY x.days DESC, x.initials), '[]'::jsonb)
			FROM (
				SELECT public.report_initials(p.full_name) AS initials, count(*) AS days
				FROM public.care_schedules cs
				JOIN public.profiles p ON p.id = COALESCE(cs.actual_parent_id, cs.scheduled_parent_id)
				WHERE cs.family_id = p_family_id AND cs.schedule_date BETWEEN p_from AND p_to
				GROUP BY p.id, p.full_name
			) x),
		'days_changed_by_swap', (
			SELECT count(*) FROM public.care_schedules cs
			WHERE cs.family_id = p_family_id AND cs.schedule_date BETWEEN p_from AND p_to
			  AND cs.actual_parent_id IS NOT NULL
			  AND cs.actual_parent_id <> cs.scheduled_parent_id),
		'swaps', (
			SELECT COALESCE(jsonb_object_agg(s.status, s.n), '{}'::jsonb)
			FROM (
				SELECT sr.status, count(*) AS n FROM public.swap_requests sr
				WHERE sr.family_id = p_family_id AND sr.schedule_date BETWEEN p_from AND p_to
				GROUP BY sr.status
			) s),
		'day_accounts', (
			SELECT count(*) FROM public.day_accounts da
			WHERE da.family_id = p_family_id AND da.account_date BETWEEN p_from AND p_to));
$$;

ALTER FUNCTION public.report_attestation_summary(bigint, date, date) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.report_attestation_summary(bigint, date, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.report_attestation_summary(bigint, date, date) TO service_role;


-- ── 4. Issue, attach the hash, revoke ────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.issue_report_attestation(p_from date, p_to date)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me     public.profiles%ROWTYPE;
	months int := public.setting_int('report_attestation.valid_months', 12);
	row_   public.report_attestations%ROWTYPE;
BEGIN
	IF NOT public.setting_bool('feature.report_attestation', false) THEN
		RAISE EXCEPTION 'O relatório verificável ainda não está disponível.'
			USING ERRCODE = 'feature_not_supported';
	END IF;

	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();
	IF me.id IS NULL OR me.left_at IS NOT NULL THEN
		RAISE EXCEPTION 'Sua conta não pode emitir um relatório verificável.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	IF public.setting_bool('report_attestation.premium_only', true)
	   AND NOT public.is_premium(me.family_id) THEN
		RAISE EXCEPTION 'O relatório verificável é um recurso Premium. O PDF sai sem o código de conferência.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
		RAISE EXCEPTION 'Período do relatório inválido.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF p_to - p_from > 400 THEN
		RAISE EXCEPTION 'O relatório verificável cobre no máximo um ano por vez.'
			USING ERRCODE = 'check_violation';
	END IF;

	INSERT INTO public.report_attestations
		(family_id, period_from, period_to, issued_by, summary, expires_at)
	VALUES (me.family_id, p_from, p_to, me.id,
	        public.report_attestation_summary(me.family_id, p_from, p_to),
	        now() + make_interval(months => months))
	RETURNING * INTO row_;

	RETURN jsonb_build_object(
		'id',         row_.id,
		'summary',    row_.summary,
		'issued_at',  row_.issued_at,
		'expires_at', row_.expires_at);
END;
$$;

ALTER FUNCTION public.issue_report_attestation(date, date) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.issue_report_attestation(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.issue_report_attestation(date, date) TO authenticated, service_role;

-- The fingerprint of the FINAL bytes (the QR is inside them), once, by whoever
-- issued it, within the hour: a PDF that never came to exist stays "pending".
CREATE OR REPLACE FUNCTION public.attach_report_hash(p_id uuid, p_sha256 text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me public.profiles%ROWTYPE;
	r  public.report_attestations%ROWTYPE;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();
	SELECT * INTO r FROM public.report_attestations
	WHERE id = p_id AND family_id = me.family_id
	FOR UPDATE;
	IF r.id IS NULL OR r.issued_by IS DISTINCT FROM me.id THEN
		RAISE EXCEPTION 'Relatório verificável não encontrado.'
			USING ERRCODE = 'no_data_found';
	END IF;
	IF r.sha256 IS NOT NULL THEN
		RAISE EXCEPTION 'Este relatório já tem a impressão digital gravada.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF r.issued_at < now() - interval '1 hour' THEN
		RAISE EXCEPTION 'O prazo para concluir este relatório passou. Gere o PDF de novo.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF p_sha256 IS NULL OR lower(p_sha256) !~ '^[0-9a-f]{64}$' THEN
		RAISE EXCEPTION 'Impressão digital inválida.'
			USING ERRCODE = 'check_violation';
	END IF;

	UPDATE public.report_attestations SET sha256 = lower(p_sha256) WHERE id = r.id;
END;
$$;

ALTER FUNCTION public.attach_report_hash(uuid, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.attach_report_hash(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.attach_report_hash(uuid, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.revoke_report_attestation(p_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me public.profiles%ROWTYPE;
	r  public.report_attestations%ROWTYPE;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();
	IF me.id IS NULL OR NOT me.is_admin OR me.left_at IS NOT NULL THEN
		RAISE EXCEPTION 'Somente administradores da família podem revogar um relatório verificável.'
			USING ERRCODE = 'check_violation';
	END IF;
	SELECT * INTO r FROM public.report_attestations
	WHERE id = p_id AND family_id = me.family_id
	FOR UPDATE;
	IF r.id IS NULL THEN
		RAISE EXCEPTION 'Relatório verificável não encontrado.'
			USING ERRCODE = 'no_data_found';
	END IF;
	IF r.revoked_at IS NOT NULL THEN
		RETURN;
	END IF;
	UPDATE public.report_attestations
	SET revoked_at = now(), revoked_by = me.id
	WHERE id = r.id;
END;
$$;

ALTER FUNCTION public.revoke_report_attestation(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.revoke_report_attestation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_report_attestation(uuid) TO authenticated, service_role;


-- ── 5. The public answer ─────────────────────────────────────────────────────
-- Anyone holding the paper may ask. The state is closed; the summary and the
-- fingerprint are shown only while the attestation stands (valid) — a revoked
-- or expired one says so and when, and nothing more.

CREATE OR REPLACE FUNCTION public.verify_report_attestation(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	r public.report_attestations%ROWTYPE;
BEGIN
	SELECT * INTO r FROM public.report_attestations WHERE id = p_id;
	IF r.id IS NULL THEN
		RETURN jsonb_build_object('state', 'unknown');
	END IF;
	IF r.purged_at IS NOT NULL OR r.expires_at <= now() THEN
		RETURN jsonb_build_object(
			'state', 'expired', 'issued_at', r.issued_at, 'expires_at', r.expires_at);
	END IF;
	IF r.revoked_at IS NOT NULL THEN
		RETURN jsonb_build_object(
			'state', 'revoked', 'issued_at', r.issued_at, 'revoked_at', r.revoked_at,
			'period_from', r.period_from, 'period_to', r.period_to);
	END IF;
	RETURN jsonb_build_object(
		'state',       CASE WHEN r.sha256 IS NULL THEN 'pending' ELSE 'valid' END,
		'issued_at',   r.issued_at,
		'expires_at',  r.expires_at,
		'period_from', r.period_from,
		'period_to',   r.period_to,
		'summary',     r.summary,
		'sha256',      r.sha256);
END;
$$;

ALTER FUNCTION public.verify_report_attestation(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.verify_report_attestation(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_report_attestation(uuid) TO anon, authenticated, service_role;


-- ── 6. The purge: daily ──────────────────────────────────────────────────────
-- Keeps the id, the issue date and the expiry, so the page still answers
-- "vencido"; everything that described the family goes.

CREATE OR REPLACE FUNCTION public.purge_expired_report_attestations()
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	n int;
BEGIN
	UPDATE public.report_attestations
	SET family_id = NULL, period_from = NULL, period_to = NULL, issued_by = NULL,
	    summary = NULL, sha256 = NULL, revoked_by = NULL, purged_at = now()
	WHERE purged_at IS NULL AND expires_at <= now();
	GET DIAGNOSTICS n = ROW_COUNT;
	RETURN n;
END;
$$;

ALTER FUNCTION public.purge_expired_report_attestations() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.purge_expired_report_attestations() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_expired_report_attestations() TO service_role;

SELECT cron.schedule(
	'report-attestations-purge-daily',
	'30 4 * * *',
	$cron$ SELECT public.purge_expired_report_attestations(); $cron$
);


-- ── 7. F-69: the verifiable reports in the operator report — counts only ────
-- Body from 20260924140000 (F-50) plus `attestations`.

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
			-- F-50: the viewers, outside the caregiver seats — counts only.
			'viewers_used',    (SELECT COUNT(*) FROM public.profiles v
			                    WHERE v.family_id = fam.id AND v.membership_type = 'viewer'
			                      AND v.left_at IS NULL),
			'viewers_cap',     CASE WHEN premium
			                        THEN public.setting_int('max_viewers', 4)
			                        ELSE public.setting_int('free_viewers', 1) END,
			-- F-64: the verifiable reports — counts only, never the id.
			'attestations', (
				SELECT jsonb_build_object(
					'issued',  COUNT(*),
					'active',  COUNT(*) FILTER (WHERE ra.revoked_at IS NULL AND ra.expires_at > now()
					                              AND ra.sha256 IS NOT NULL),
					'revoked', COUNT(*) FILTER (WHERE ra.revoked_at IS NOT NULL),
					'pending', COUNT(*) FILTER (WHERE ra.sha256 IS NULL AND ra.revoked_at IS NULL
					                              AND ra.expires_at > now()))
				FROM public.report_attestations ra WHERE ra.family_id = fam.id),
			'viewer_invitations_open', (SELECT COUNT(*) FROM public.family_invitations vi
			                    WHERE vi.family_id = fam.id AND vi.member_type = 'viewer'
			                      AND vi.accepted_at IS NULL AND vi.revoked_at IS NULL
			                      AND vi.expires_at > now()),
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
				'membership',             p.membership_type,
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
				'agenda_events', (
					SELECT COUNT(*) FROM public.child_events ce
					WHERE ce.family_id = fam.id AND ce.source_schedule_id IS NULL
					  AND ce.batch_id IS NULL
					  AND (ce.created_at AT TIME ZONE 'America/Sao_Paulo')::date >= wk.week_start
					  AND (ce.created_at AT TIME ZONE 'America/Sao_Paulo')::date <  wk.week_start + 7
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
		),

		-- F-55: the child entity and the agenda — counts only, never a name
		-- or an event's text.
		'agenda', jsonb_build_object(
			'children',       (SELECT COUNT(*) FROM public.children c WHERE c.family_id = fam.id),
			'events_active',  (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.deleted_at IS NULL),
			'events_ahead',   (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.deleted_at IS NULL
			                     AND ce.event_date >= today),
			'events_deleted', (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.deleted_at IS NOT NULL),
			'notes_active',   (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.deleted_at IS NULL
			                     AND ce.kind = 'note'),
			'converted',      (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.source_schedule_id IS NOT NULL),
			'routines',       (SELECT COUNT(*) FROM public.child_routines cr
			                   WHERE cr.family_id = fam.id AND cr.stopped_at IS NULL),
			'events_from_routine', (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.deleted_at IS NULL
			                     AND ce.batch_id IS NOT NULL),
			'with_reminder',  (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.deleted_at IS NULL
			                     AND ce.remind_minutes IS NOT NULL),
			'reminders_sent', (SELECT COUNT(*) FROM public.child_events ce
			                   WHERE ce.family_id = fam.id AND ce.reminded_at IS NOT NULL),
			'by_kind', (
				SELECT COALESCE(jsonb_agg(jsonb_build_object(
					'kind',  bk.kind,
					'count', bk.n
				) ORDER BY bk.kind), '[]'::jsonb)
				FROM (
					SELECT kind, COUNT(*) AS n FROM public.child_events
					WHERE family_id = fam.id AND deleted_at IS NULL
					GROUP BY kind
				) bk
			)
		)
	) INTO result;

	RETURN result;
END;
$$;
