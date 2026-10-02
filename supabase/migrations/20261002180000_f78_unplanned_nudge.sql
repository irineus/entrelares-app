-- =============================================================================
-- F-78 (02/10/2026) — a family that never planned hears "Falta planejar o
-- primeiro mês" (F-70's trigger B)
--
-- On 23/09/2026, 20 of 30 families had never planned a single day — all of
-- them with one member. A family that does not plan never invites the other
-- caregiver and never reaches the plan page. F-70 left this trigger open; the
-- owner approved it in the acquisition chain of October (02/10/2026):
--
--   · the gate is "no planned day in ANY lane" (F-07: a `care_schedules` row
--     of any child, or of the single-mode lane) N hours after the family was
--     created — N is `onboarding.unplanned_nudge_hours` (default 48, 24–168);
--   · ONE nudge per family, ever (ledger keyed on the family);
--   · push + in-app, no e-mail (F-59);
--   · the families already dormant at ship time are told too, ONCE — the
--     first run is the backfill, by construction (no upper bound on age);
--   · the tap opens the wizard on the first day (today).
--
-- No new push type: it is a third `kind` of F-70's `plan_ending` ("the plan
-- runs out" — here it never started), so the dispatcher already lets it
-- through, and the stated push-type list (§2) does not grow.
--
-- Recipients: every active member with an account who is not a viewer — any
-- caregiver may plan an empty day (F-70's rule); a Visualizador writes
-- nothing (F-50). A family with a pending deletion request hears nothing.
-- =============================================================================

-- ── 1. The parameter ─────────────────────────────────────────────────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, min_value, max_value, help)
VALUES
	('onboarding.unplanned_nudge_hours', '48', 'int', 'product',
	 'F-78: horas depois da criação da família até o aviso de que nenhum dia foi planejado.',
	 false, 'hours', 'normal', 24, 168,
	 jsonb_build_object(
		'controls', 'Quanto tempo uma família recém-criada e sem nenhum dia planejado espera até receber o aviso "Falta planejar o primeiro mês" (push e no app, uma vez só).',
		'shown_at', jsonb_build_array('push', 'app'),
		'if_increased', 'O aviso chega mais tarde: mais tempo para a família planejar sozinha, e mais famílias esfriam antes de ouvir algo.',
		'if_decreased', 'O aviso chega mais cedo; abaixo de um dia pode soar como cobrança logo depois do cadastro.',
		'takes_effect', 'Servidor na próxima rodada diária (09:00 de Brasília).',
		'caveats', 'Cada família recebe o aviso uma vez só; mudar o número não reenvia a quem já recebeu.'))
ON CONFLICT (key) DO NOTHING;

-- ── 2. The ledger ────────────────────────────────────────────────────────────

CREATE TABLE public.unplanned_family_nudges (
	family_id bigint PRIMARY KEY REFERENCES public.families (id) ON DELETE CASCADE,
	sent_at   timestamp with time zone NOT NULL DEFAULT timezone('utc', now())
);

COMMENT ON TABLE public.unplanned_family_nudges IS
	'F-78: one row per family already told it has no planned day. Service role only. '
	'Also the success measure: a nudged family with a care_schedules row created within 7 days of sent_at planned.';

ALTER TABLE public.unplanned_family_nudges ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.unplanned_family_nudges FROM anon, authenticated;

-- ── 3. The selection ─────────────────────────────────────────────────────────

-- `p_family_id` NULL (what the cron sends) scans every family; the DB gate
-- passes its throwaway family.
CREATE OR REPLACE FUNCTION public.unplanned_family_nudges_due(p_family_id bigint DEFAULT NULL)
RETURNS TABLE (profile_id bigint)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	today   date := (timezone('America/Sao_Paulo', now()))::date;
	v_hours int  := public.setting_int('onboarding.unplanned_nudge_hours', 48);
	r       record;
BEGIN
	FOR r IN
		SELECT f.id AS fam_id
		  FROM public.families f
		 WHERE f.created_at <= now() - make_interval(hours => v_hours)
		   AND (p_family_id IS NULL OR f.id = p_family_id)
		   -- Any lane (F-07): a day planned for any child, or for the family.
		   AND NOT EXISTS (SELECT 1 FROM public.care_schedules cs WHERE cs.family_id = f.id)
		   AND NOT EXISTS (SELECT 1 FROM public.unplanned_family_nudges n WHERE n.family_id = f.id)
		   AND NOT EXISTS (
		       SELECT 1 FROM public.family_deletion_requests d
		        WHERE d.family_id = f.id AND d.status = 'pending')
	LOOP
		-- No reader, no stamp: whoever joins later is still told.
		IF NOT EXISTS (
			SELECT 1 FROM public.profiles p
			 WHERE p.family_id = r.fam_id
			   AND p.left_at IS NULL
			   AND p.user_id IS NOT NULL
			   AND p.membership_type <> 'viewer'
		) THEN
			CONTINUE;
		END IF;

		INSERT INTO public.unplanned_family_nudges (family_id) VALUES (r.fam_id);

		-- PT-BR byte-identical to the catalog (U-13). `date` is the day the
		-- wizard opens on (today); the sentence itself states no number.
		INSERT INTO public.notifications (recipient_profile_id, type, title, message, params)
		SELECT p.id, 'plan_ending',
		       'Falta planejar o primeiro mês',
		       'O calendário da família ainda não tem nenhum dia planejado. Comece pelo primeiro mês.',
		       jsonb_build_object('kind', 'unplanned', 'date', to_char(today, 'YYYY-MM-DD'))
		  FROM public.profiles p
		 WHERE p.family_id = r.fam_id
		   AND p.left_at IS NULL
		   AND p.user_id IS NOT NULL
		   AND p.membership_type <> 'viewer';

		RETURN QUERY
		SELECT p.id
		  FROM public.profiles p
		 WHERE p.family_id = r.fam_id
		   AND p.left_at IS NULL
		   AND p.user_id IS NOT NULL
		   AND p.membership_type <> 'viewer';
	END LOOP;
END;
$$;

ALTER FUNCTION public.unplanned_family_nudges_due(bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.unplanned_family_nudges_due(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.unplanned_family_nudges_due(bigint) TO service_role;

-- ── 4. Schedule: daily at 09:00 in Brasília ──────────────────────────────────
-- Beside F-70's and F-77's jobs. Pure SQL, no Edge Function (no e-mail twin).

SELECT cron.schedule(
	'unplanned-family-nudges-daily',
	'0 12 * * *',
	$cron$ SELECT public.unplanned_family_nudges_due(); $cron$
);
