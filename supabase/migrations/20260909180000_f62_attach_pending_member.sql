-- =============================================================================
-- F-62 — A legacy open invitation gets its placeholder
--
-- F-56 made the invitation form name the person first, so every invitation it
-- issues is born WITH a pending member (`family_invitations.profile_id`). An
-- invitation issued before F-56 — or by an Android build not yet promoted on
-- the Play Console, which still calls `create_invitation` with two arguments —
-- carries only an e-mail and a role: nobody to plan days for.
--
-- `attach_pending_member` closes that gap without touching the link the
-- person already has. `create_invitation(email, role, profile_id)` would
-- REVOKE the open invitation and issue a new token — the mail already in the
-- invitee's inbox would die, possibly halfway through the sign-up. Attaching
-- to the existing row keeps the token; from then on the row is an F-56
-- invitation in every respect: `get_invite_info` shows the name, a resend
-- carries the placeholder, and both claim paths (`handle_new_user`,
-- `claim_invitation_for_user`) branch on `profile_id` and UPDATE the same row.
-- None of those bodies changes here.
--
-- Seats (owner, 09/09/2026 — "aritmética honesta"): a VALID legacy invitation
-- already holds a seat in the F-37 arithmetic (`seat_count()` + open
-- placeholder-less invitations that have not expired), so attaching only
-- moves that seat from the invitation to the placeholder — the total is the
-- same before and after, and no gate runs. An EXPIRED invitation holds NO
-- seat (the `expires_at > now()` predicate dropped it), so its placeholder
-- would be a NEW seat: that case goes through the ordinary F-37 gate, with
-- the same sentences `add_pending_member` uses. A placeholder never creates a
-- seat the family did not have room for.
--
-- Idempotent on purpose: the dev project may receive it through the MCP
-- before CI applies the file.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.attach_pending_member(
	p_invitation_id bigint,
	p_full_name     text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
	me         public.profiles%ROWTYPE;
	inv        public.family_invitations%ROWTYPE;
	clean_name text := trim(p_full_name);
	max_seats  int := public.setting_int('max_caregivers', 4);
	free_seats int := public.setting_int('free_caregivers', 2);
	taken      int;
	new_id     bigint;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();

	IF me.id IS NULL OR NOT me.is_admin THEN
		RAISE EXCEPTION 'Somente administradores da família podem adicionar responsáveis.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF EXISTS (SELECT 1 FROM public.family_deletion_requests
	           WHERE family_id = me.family_id AND status = 'pending') THEN
		RAISE EXCEPTION 'Há uma solicitação de exclusão da família em andamento — convites ficam bloqueados até ela ser resolvida.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF clean_name IS NULL OR length(clean_name) < 2 OR length(clean_name) > 80 THEN
		RAISE EXCEPTION 'Informe um nome entre 2 e 80 caracteres.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- MY family's invitation, still open, not yet somebody's.
	SELECT * INTO inv FROM public.family_invitations
	WHERE id = p_invitation_id AND family_id = me.family_id;
	IF inv.id IS NULL THEN
		RAISE EXCEPTION 'Convite não encontrado na sua família.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF inv.accepted_at IS NOT NULL THEN
		RAISE EXCEPTION 'Este convite já foi aceito — a pessoa já está na família.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF inv.revoked_at IS NOT NULL THEN
		RAISE EXCEPTION 'Este convite foi revogado. Adicione a pessoa pelo formulário e envie um convite novo.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF inv.profile_id IS NOT NULL THEN
		RAISE EXCEPTION 'Este convite já está ligado a um responsável no calendário.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- A valid invitation already holds the seat the placeholder will take:
	-- nothing to gate. An expired one holds none, so this is a NEW seat and the
	-- F-37 arithmetic applies (this invitation is outside it by construction).
	IF inv.expires_at <= timezone('utc', now()) THEN
		SELECT public.seat_count(me.family_id)
		     + (SELECT count(*) FROM public.family_invitations fi
		        WHERE fi.family_id = me.family_id
		          AND fi.profile_id IS NULL
		          AND fi.accepted_at IS NULL AND fi.revoked_at IS NULL
		          AND fi.expires_at > timezone('utc', now()))
		INTO taken;

		IF taken >= free_seats AND NOT public.is_premium(me.family_id) THEN
			RAISE EXCEPTION 'Famílias no plano gratuito incluem % responsáveis. Para adicionar mais (avós, babá, etc.), ative o Premium.', free_seats
				USING ERRCODE = 'check_violation';
		END IF;

		IF taken >= max_seats THEN
			RAISE EXCEPTION 'Esta família já atingiu o limite de % responsáveis (contando convites pendentes).', max_seats
				USING ERRCODE = 'check_violation';
		END IF;
	END IF;

	-- The placeholder, exactly as add_pending_member builds one: the
	-- invitation's role, the system's colour, no e-mail (that stays on the
	-- invitation row and its 30-day purge — LGPD, F-56).
	INSERT INTO public.profiles (user_id, full_name, role_id, email, family_id, is_admin, color_slot)
	VALUES (NULL, clean_name, inv.role_id, NULL, me.family_id, false,
	        public.next_free_color_slot(me.family_id))
	RETURNING id INTO new_id;

	INSERT INTO public.account_logs (family_id, actor_profile_id, target_profile_id, action, new_value)
	VALUES (me.family_id, me.id, new_id, 'pending_member_added', clean_name);

	-- Same row, same token: the link already sent now lands on this profile.
	UPDATE public.family_invitations
	SET profile_id = new_id
	WHERE id = inv.id;

	RETURN new_id;
END;
$$;
ALTER FUNCTION public.attach_pending_member(bigint, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.attach_pending_member(bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.attach_pending_member(bigint, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.attach_pending_member(bigint, text) IS
	'F-62: gives a LEGACY open invitation (no profile_id) its pending member — same row, same token, the link already sent keeps working. Admin only. Seat gate only when the invitation is expired (a valid one already holds the seat).';
