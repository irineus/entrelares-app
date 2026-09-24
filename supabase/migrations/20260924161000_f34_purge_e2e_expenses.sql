-- =============================================================================
-- F-34 (PR 1, fix) — the E2E purge learns the expense tables
--
-- `expenses.paid_by`, `expense_shares.profile_id` and the settlements'
-- profiles reference `profiles` with no ON DELETE, on purpose: a caregiver who
-- leaves becomes a tombstone (S-11), never a silent cascade. `purge_family_data`
-- learned the tables in 20260924160000; `purge_e2e_family` (the gate's and the
-- E2E lane's teardown, body from 20260728150000) did not, and the first gate
-- run failed on its tearDownAll with `expenses_paid_by_fkey`. A new file, not
-- an edit: the dev project had already recorded 20260924160000.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.purge_e2e_family(p_family_id bigint)
RETURNS SETOF uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	fam_name text;
	non_e2e_members int;
BEGIN
	SELECT name INTO fam_name FROM public.families WHERE id = p_family_id;
	IF fam_name IS NULL THEN
		RETURN;   -- already gone: purge is idempotent
	END IF;

	-- E2E double signature — refuse anything that is not unmistakably test data.
	IF fam_name NOT LIKE 'E2E-%' THEN
		RAISE EXCEPTION 'purge_e2e_family: family % is not an E2E family (name).', p_family_id
			USING ERRCODE = 'check_violation';
	END IF;
	SELECT count(*) INTO non_e2e_members
	FROM public.profiles
	WHERE family_id = p_family_id
	  AND email NOT LIKE '%@resend.dev'
	  AND email NOT LIKE 'removido+%@guarda.invalido';
	IF non_e2e_members > 0 THEN
		RAISE EXCEPTION 'purge_e2e_family: family % has non-E2E members (email).', p_family_id
			USING ERRCODE = 'check_violation';
	END IF;

	-- Hand the auth user ids back BEFORE deleting the profiles.
	RETURN QUERY
	SELECT user_id::uuid FROM public.profiles
	WHERE family_id = p_family_id AND user_id IS NOT NULL;

	-- Ordered teardown (children first; profiles are referenced by all data).
	DELETE FROM public.notifications
	WHERE recipient_profile_id IN (SELECT id FROM public.profiles WHERE family_id = p_family_id);
	DELETE FROM public.swap_requests      WHERE family_id = p_family_id;
	DELETE FROM public.care_schedules     WHERE family_id = p_family_id;
	DELETE FROM public.activity_logs      WHERE family_id = p_family_id;
	DELETE FROM public.family_invitations WHERE family_id = p_family_id;
	-- T-39: the billing ledger is denormalized on purpose (audit survives the
	-- subscription); for E2E families it must go with them.
	DELETE FROM public.billing_events     WHERE family_id = p_family_id;
	-- F-34: the expenses (shares and trail cascade) and the settlements, BEFORE
	-- the profiles they reference (their FKs have no ON DELETE on purpose).
	DELETE FROM public.expense_settlements WHERE family_id = p_family_id;
	DELETE FROM public.expenses            WHERE family_id = p_family_id;
	DELETE FROM public.profiles           WHERE family_id = p_family_id;
	DELETE FROM public.families           WHERE id = p_family_id;
END;
$$;
