-- =============================================================================
-- F-69 (owner QA of the console, 23/09/2026) — one rule for "last active", and
-- the dates the console sorts by.
--
-- WHY. The owner asked the console to SORT families and participants by name,
-- by creation date and, for participants, by last login. `admin_list_families`
-- carried no date per member at all, so the sort needs three facts per member:
--   · `created_at`        — when the profile was created;
--   · `last_sign_in_at`   — GoTrue's last SIGN-IN (a login, not a refresh: a
--                           member who stays signed in for months keeps an old
--                           value here, which is exactly what "last login" says);
--   · `last_active_day` + `last_active_source` — the usage report's "last
--                           active", so the list and the report never disagree.
-- Only dates: §10 of the policy (F-69) already discloses that the operator sees
-- when each carer last used the app. No user agent, no IP.
--
-- ONE RULE. "Last active" moves out of the report into
-- `member_last_active(profile_id)`: T-78's `member_activity_days` first, GoTrue's
-- latest session touch as the approximate fallback (DATE only). It is
-- SECURITY DEFINER with NO grant to any client role — only the operator RPCs
-- (which run as the owner) call it, so it opens nothing on its own. The report
-- is redefined here unchanged except for reading this function.
-- =============================================================================

-- ── 1. member_last_active ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.member_last_active(p_profile_id bigint)
RETURNS TABLE (last_day date, last_source text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
	SELECT x.d, x.src
	FROM (
		SELECT MAX(a.day) AS d, 'activity'::text AS src, 1 AS pri
		FROM public.member_activity_days a
		WHERE a.profile_id = p_profile_id
		UNION ALL
		SELECT (MAX(GREATEST(s.refreshed_at AT TIME ZONE 'UTC', s.updated_at))
		        AT TIME ZONE 'America/Sao_Paulo')::date,
		       'auth_sessions', 2
		FROM auth.sessions s
		JOIN public.profiles p ON p.user_id = s.user_id
		WHERE p.id = p_profile_id
	) x
	WHERE x.d IS NOT NULL
	ORDER BY x.pri
	LIMIT 1;
$$;

COMMENT ON FUNCTION public.member_last_active(bigint) IS
	'F-69: a member''s last active DAY (America/Sao_Paulo) — member_activity_days (T-78) first, else the latest GoTrue session touch, source ''auth_sessions'' (approximate). No client grant: only the operator RPCs call it.';

ALTER FUNCTION public.member_last_active(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.member_last_active(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.member_last_active(bigint) FROM anon;
REVOKE ALL ON FUNCTION public.member_last_active(bigint) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.member_last_active(bigint) TO service_role;

-- ── 2. admin_family_usage_report, reading the one rule ──────────────────────

CREATE OR REPLACE FUNCTION public.admin_family_usage_report(p_family_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	fam        public.families%ROWTYPE;
	today      date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
	first_week date;
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
	first_week := date_trunc('week', today)::date - 7 * 11;

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
					WHERE a.profile_id = p.id AND a.day > today - 30
				),
				'channels_30', (
					SELECT COALESCE(jsonb_agg(DISTINCT a.channel), '[]'::jsonb)
					FROM public.member_activity_days a
					WHERE a.profile_id = p.id AND a.day > today - 30
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

-- ── 3. admin_list_families, with the dates the console sorts by ─────────────
-- Same body as 20260818210000 plus three facts per member (see the header).

CREATE OR REPLACE FUNCTION public.admin_list_families()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	result jsonb;
BEGIN
	IF NOT public.is_platform_operator() THEN
		RAISE EXCEPTION 'Acesso restrito à operação da plataforma.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;

	INSERT INTO public.operator_audit_logs (operator_user_id, action)
	VALUES (auth.uid(), 'families_listed');

	SELECT COALESCE(jsonb_agg(jsonb_build_object(
		'id',                f.id,
		'name',              f.name,
		'plan',              f.plan,
		'trial_ends_at',     f.trial_ends_at,
		'comp_premium_at',   f.comp_premium_at,
		'comp_premium_note', f.comp_premium_note,
		'is_premium',        public.is_premium(f.id),
		'created_at',        f.created_at,
		'subscription', (
			SELECT jsonb_build_object(
				'status',             s.status,
				'cycle',              s.cycle,
				'price_cents',        s.price_cents,
				'current_period_end', s.current_period_end,
				'overdue_since',      s.overdue_since,
				'canceled_at',        s.canceled_at
			)
			FROM public.subscriptions s WHERE s.family_id = f.id
		),
		'members', (
			SELECT COALESCE(jsonb_agg(jsonb_build_object(
				'id',                 p.id,
				'full_name',          p.full_name,
				'email',              p.email,
				'role',               (SELECT r.role FROM public.roles r WHERE r.id = p.role_id),
				'is_admin',           p.is_admin,
				'left_at',            p.left_at,
				'created_at',         p.created_at,
				'last_sign_in_at',    (SELECT u.last_sign_in_at FROM auth.users u WHERE u.id = p.user_id),
				'last_active_day',    la.last_day,
				'last_active_source', la.last_source
			) ORDER BY p.id), '[]'::jsonb)
			FROM public.profiles p
			LEFT JOIN LATERAL public.member_last_active(p.id) la ON true
			WHERE p.family_id = f.id
		)
	) ORDER BY f.name, f.id), '[]'::jsonb)
	INTO result
	FROM public.families f;

	RETURN result;
END;
$$;

ALTER FUNCTION public.admin_list_families() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_list_families() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_families() FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_list_families() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_families() TO service_role;
