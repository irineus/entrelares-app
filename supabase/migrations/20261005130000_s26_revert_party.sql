-- S-26 (T-103 audit, 04/10/2026) — a revert is opened only by a PARTY to the
-- day: its planned carer or its actual one.
--
-- F-28 forbids scenario C on swaps: a third caregiver may not hand somebody
-- else's day to another person. Reverts had no such rule. Saturday planned for
-- Mom, swapped (approved) to Dad: the grandmother picked "Sem troca" and the
-- client sent a revert whose approver was "the one who is not me" = Mom — who
-- approved, and Dad lost the day without being asked.
--
-- Owner decision (04/10/2026, phase-2 chain): only the day's planned or actual
-- carer may request the revert, enforced HERE; the client mirrors it in
-- `isRevertCandidate` / `mayRequestRevert` and hides "Sem troca" from others.
--
-- The check reads the DAY (care_schedules), never the request's own
-- `proposed_actual_parent_id` / `previous_actual_parent_id`, which the client
-- writes. With `schedule_id` set it is that row; without it (an old client),
-- any lane of the family on that date where the requester is a party.

CREATE OR REPLACE FUNCTION public.enforce_revert_party()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
	IF NEW.status IS DISTINCT FROM 'revert_pending' THEN
		RETURN NEW;
	END IF;

	IF NOT EXISTS (
		SELECT 1
		FROM public.care_schedules cs
		WHERE cs.family_id = NEW.family_id
		  AND cs.schedule_date = NEW.schedule_date
		  AND (NEW.schedule_id IS NULL OR cs.id = NEW.schedule_id)
		  AND NEW.requesting_profile_id IN (cs.scheduled_parent_id, cs.actual_parent_id)
	) THEN
		RAISE EXCEPTION 'Só quem estava planejado para o dia ou está com ele pode pedir para desfazer a troca.'
			USING ERRCODE = 'check_violation';
	END IF;

	RETURN NEW;
END;
$$;

ALTER FUNCTION public.enforce_revert_party() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.enforce_revert_party() FROM PUBLIC, anon, authenticated;

-- `trigger_c_…`: after `trigger_a_set_swap_request_family` (fills family_id)
-- and the lane stamp, which run first in name order.
DROP TRIGGER IF EXISTS trigger_c_enforce_revert_party ON public.swap_requests;
CREATE TRIGGER trigger_c_enforce_revert_party
	BEFORE INSERT ON public.swap_requests
	FOR EACH ROW
	EXECUTE FUNCTION public.enforce_revert_party();

COMMENT ON FUNCTION public.enforce_revert_party() IS
	'S-26: a revert_pending request may only be opened by the day''s planned or actual carer (F-28 scenario C, on reverts).';
