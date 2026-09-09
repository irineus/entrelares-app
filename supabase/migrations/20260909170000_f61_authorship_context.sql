-- F-61 — authorship in the record: who planned what, and whether the other
-- could see it (PR 1).
--
-- With a solo caregiver planning the other's days (F-56), the trail read the
-- same before and after the claim: the snapshot stores the assignee's profile
-- id, and the claim keeps the id. "Ana planned 12/09 for Bruno" said nothing
-- about whether Bruno could open the app that day, and the only way to know was
-- to cross-reference `account_logs` dates — which a judge-level reader must not
-- have to do.
--
-- The same silence covered the admin's direct writes (S-09 planned-parent
-- change, F-14 past-day correction, clearing an assigned day): the trail named
-- the actor and the reader inferred "unilateral" from the ABSENCE of a swap
-- origin block.
--
-- This migration stamps both facts AT WRITE TIME, trigger-side, in a new
-- `activity_logs.context` column:
--
--   scheduled_parent_has_account  the planned parent had an auth user at that
--                                 instant (`profiles.user_id IS NOT NULL`)
--   actual_parent_has_account     same for the real parent, when set
--   actor_is_admin                the writer was a family admin
--   admin_override                the write went through ONLY because the
--                                 writer is an admin: a DELETE, or an UPDATE of
--                                 the planned or the real parent, by an admin
--                                 who is not the target of a pending request on
--                                 that day (the SAME predicate
--                                 `enforce_day_protection` uses to let it pass)
--
-- Why a column and not keys inside `new_data`: the snapshot is `to_jsonb(NEW)`,
-- the row as it was, and `restore_pre_edit_state` (F-26/F-47) reads it back to
-- restore a day. Derived facts belong next to the snapshot, not inside it.
--
-- Rows older than this migration keep `context` NULL: the facts are unknown
-- for the past and the renderer says nothing rather than guessing (no
-- backfill, by decision on the card).
--
-- `audit_care_schedule_changes` was defined ONCE, in the baseline, and never
-- rewritten — this body starts from that one (the T-45 lesson: newest file
-- wins, and here the newest is the first).
--
-- Idempotent on purpose: `IF NOT EXISTS` + `CREATE OR REPLACE`, so a
-- pre-application through the MCP leaves nothing for CI's `db push` to trip on.

ALTER TABLE public.activity_logs ADD COLUMN IF NOT EXISTS context jsonb;

COMMENT ON COLUMN public.activity_logs.context IS
	'F-61: facts stamped by the audit trigger at write time — whether the assigned parents had an account, whether the actor was an admin, and whether the write was an admin override. NULL on rows written before F-61.';

CREATE OR REPLACE FUNCTION public.audit_care_schedule_changes()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	actor_id           bigint;
	actor_admin        boolean := false;
	is_target          boolean := false;
	fam                bigint;
	the_date           date;
	sched_parent       bigint;
	actual_parent      bigint;
	sched_has_account  boolean;
	actual_has_account boolean;
	admin_override     boolean := false;
	ctx                jsonb;
BEGIN
	SELECT id, is_admin INTO actor_id, actor_admin
	FROM public.profiles WHERE user_id = auth.uid();

	fam      := COALESCE(NEW.family_id, OLD.family_id);
	the_date := COALESCE(NEW.schedule_date, OLD.schedule_date);

	-- The assignees the row names after the write — or, for a DELETE, the ones
	-- it named when it went (the fact is about the day as recorded).
	sched_parent  := CASE WHEN TG_OP = 'DELETE' THEN OLD.scheduled_parent_id ELSE NEW.scheduled_parent_id END;
	actual_parent := CASE WHEN TG_OP = 'DELETE' THEN OLD.actual_parent_id    ELSE NEW.actual_parent_id    END;

	SELECT (user_id IS NOT NULL) INTO sched_has_account
	FROM public.profiles WHERE id = sched_parent;
	IF actual_parent IS NOT NULL THEN
		SELECT (user_id IS NOT NULL) INTO actual_has_account
		FROM public.profiles WHERE id = actual_parent;
	END IF;

	-- The admin override, with the predicate enforce_day_protection uses to
	-- let the write through: an admin who is NOT the target of a pending
	-- request on this day (a target applying an approval, or restoring the
	-- pre-edit snapshot on a revert, acts inside the two-party workflow).
	IF actor_id IS NOT NULL AND actor_admin THEN
		SELECT COALESCE(bool_or(target_profile_id = actor_id), false) INTO is_target
		FROM public.swap_requests
		WHERE family_id = fam AND schedule_date = the_date
		  AND status IN ('pending', 'revert_pending');

		admin_override := NOT is_target AND (
			TG_OP = 'DELETE'
			OR (TG_OP = 'UPDATE'
			    AND (NEW.scheduled_parent_id IS DISTINCT FROM OLD.scheduled_parent_id
			         OR NEW.actual_parent_id IS DISTINCT FROM OLD.actual_parent_id)));
	END IF;

	-- A system write (service_role: auto-approval, migrations) has no actor,
	-- and the two actor facts stay NULL rather than false — "unknown" and
	-- "no" are different answers on a record.
	ctx := jsonb_strip_nulls(jsonb_build_object(
		'scheduled_parent_has_account', sched_has_account,
		'actual_parent_has_account',    actual_has_account,
		'actor_is_admin',               CASE WHEN actor_id IS NULL THEN NULL ELSE actor_admin END,
		'admin_override',               CASE WHEN actor_id IS NULL THEN NULL ELSE admin_override END));

	INSERT INTO public.activity_logs (
		schedule_id,
		affected_date,
		action,
		old_data,
		new_data,
		performed_by_id,
		family_id,
		context
	) VALUES (
		CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE NEW.id END,
		the_date,
		TG_OP,
		CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE to_jsonb(OLD) END,
		CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE to_jsonb(NEW) END,
		actor_id,
		fam,
		ctx
	);

	IF TG_OP = 'DELETE' THEN
		RETURN OLD;
	END IF;
	RETURN NEW;
END;
$$;

ALTER FUNCTION public.audit_care_schedule_changes() OWNER TO postgres;
