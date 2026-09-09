-- F-61 — authorship in the record (PR 2): the invitation log names the
-- placeholder it was issued for.
--
-- The "Responsáveis" section of the F-33 document prints each caregiver's
-- dated account timeline: added to the calendar by whom and when, invited
-- when, created the account when, left when. `account_logs` already carries
-- `pending_member_added` / `pending_member_claimed` / `pending_member_removed`
-- WITH a `target_profile_id` (F-56), but the three invitation rows written by
-- `audit_invitation_changes` carried only the e-mail — and a placeholder has
-- no e-mail, so nothing tied "Convite enviado" to the person it was for.
--
-- `family_invitations.profile_id` exists since F-56 (the placeholder behind
-- the invitation, NULL on a legacy one). This body is VERBATIM from
-- 20260718113000 (S-10) — the latest definition — plus `NEW.profile_id` as the
-- target on the three inserts. A legacy invitation keeps NULL, and the
-- renderer falls back to matching the stored e-mail against the member's.
--
-- Idempotent (`CREATE OR REPLACE`), so a pre-application through the MCP
-- leaves nothing for CI's `db push` to trip on.

CREATE OR REPLACE FUNCTION public.audit_invitation_changes()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	actor bigint;
BEGIN
	SELECT id INTO actor FROM public.profiles WHERE user_id = auth.uid();

	IF TG_OP = 'INSERT' THEN
		INSERT INTO public.account_logs (family_id, actor_profile_id, target_profile_id, action, new_value)
		VALUES (NEW.family_id, COALESCE(actor, NEW.invited_by), NEW.profile_id, 'invitation_created', NEW.email);
		RETURN NEW;
	END IF;

	IF NEW.revoked_at IS NOT NULL AND OLD.revoked_at IS NULL THEN
		INSERT INTO public.account_logs (family_id, actor_profile_id, target_profile_id, action, new_value)
		VALUES (NEW.family_id, actor, NEW.profile_id, 'invitation_revoked', NEW.email);
	END IF;

	IF NEW.accepted_at IS NOT NULL AND OLD.accepted_at IS NULL THEN
		INSERT INTO public.account_logs (family_id, actor_profile_id, target_profile_id, action, new_value)
		VALUES (NEW.family_id, actor, NEW.profile_id, 'invitation_accepted', NEW.email);
	END IF;

	RETURN NEW;
END;
$$;

ALTER FUNCTION public.audit_invitation_changes() OWNER TO postgres;
