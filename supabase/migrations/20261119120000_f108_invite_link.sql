-- =============================================================================
-- F-108 (PR 1) — invite the other caregiver by LINK, without their e-mail
--
-- Activation reading of the real cohort (19/11/2026): 8 of 16 families tried to
-- add the other caregiver and 6 stopped at a pending member with no e-mail —
-- `create_invitation` refused a NULL address, so there was no link to share.
-- And when an e-mail WAS typed, it locked the claim: `handle_new_user` and
-- `claim_invitation_for_user` matched the account's address against it, so a
-- co-parent signing in with another Google address was refused.
--
-- Decisions locked with the owner (19/11/2026):
--   (1) a caregiver invitation attached to a PLACEHOLDER (F-56) may be claimed
--       by whoever holds its link — single use (`accepted_at`), valid
--       `invitation.valid_days`; the admin hears it (`member_joined`, F-56) and
--       can remove + revoke on the roster;
--   (2) the e-mail the admin typed is DELIVERY only, never a lock;
--   (3) an address the invitation was not mailed to proves itself: e-mail +
--       password goes through GoTrue's normal confirmation, Google is verified
--       by the provider; the invitation's own address keeps U-17's
--       pre-confirmed path (`register-invitee`);
--   (5) that unconfirmed account takes the seat at CONFIRMATION, never at the
--       sign-up INSERT — a typo address never confirms, so it never squats the
--       placeholder, and the link stays usable meanwhile;
--   (6) someone already signed in, alone in an EMPTY family, who opens the link
--       is offered to join — F-88's rules, keyed on the token instead of the
--       e-mail (`invitation_offer_for_token`).
--
-- Rollout (owner, 19/11/2026): `feature.invite_link` is born FALSE (T-84). The
-- Android build in Production locks the sign-up e-mail to the invitation's, so
-- an invitation WITHOUT one would strand whoever installed from Play. While
-- the flag is off, `create_invitation` keeps refusing a NULL address; a
-- migration turns it on after a build carrying F-108's PR 2 is in Production
-- (the F-07 `per_child_schedule` path).
--
-- Not changed: viewer invitations (F-50) and legacy invitations with no
-- placeholder stay e-mail-bound; the refusal of an address that already has an
-- account stays (F-30 deferred); seats do not move (a link always belongs to a
-- placeholder, which already holds its seat).
--
-- No policy change: a link invitation stores LESS than an e-mail one, and the
-- 30-day purge of never-accepted rows (S-15/A-4) is untouched — not material,
-- no `PolicyVersions` bump (§3, S-15).
-- =============================================================================


-- ── 1. The flag (T-84 catalogue) ─────────────────────────────────────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, help)
VALUES
	('feature.invite_link', 'false', 'bool', 'features',
	 'Liga o convite por link (F-108): o admin compartilha o convite do responsável pendente sem informar e-mail.',
	 true, 'flag', 'critical',
	 jsonb_build_object(
		'controls', 'Se um convite de responsável pode nascer SEM e-mail (só o link), e se o app abre o compartilhamento logo depois de adicionar o responsável.',
		'shown_at', jsonb_build_array('app'),
		'if_increased', 'Ligado: o admin compartilha o link do convite por WhatsApp ou onde quiser; quem abrir o link entra no lugar do responsável pendente, com qualquer e-mail.',
		'if_decreased', 'Desligado (chave de emergência): o servidor volta a exigir o e-mail para criar convite. Links já compartilhados CONTINUAM valendo até expirar ou ser revogados.',
		'takes_effect', 'Servidor no próximo convite; app na próxima abertura.',
		'caveats', 'Nasce DESLIGADO em produção. Ligar só depois que um build com o F-108 (PR 2) estiver na Production da Play — o Android anterior trava o e-mail do cadastro no do convite.'))
ON CONFLICT (key) DO NOTHING;


-- ── 2. The row: an invitation may carry no address ───────────────────────────
-- A link always belongs to a caregiver placeholder, so the seat arithmetic
-- (seat_count + open invitations WITHOUT a placeholder) never sees one.

ALTER TABLE public.family_invitations
	ALTER COLUMN email DROP NOT NULL;

ALTER TABLE public.family_invitations
	DROP CONSTRAINT IF EXISTS family_invitations_link_needs_placeholder;
ALTER TABLE public.family_invitations
	ADD CONSTRAINT family_invitations_link_needs_placeholder
	CHECK (email IS NOT NULL OR (profile_id IS NOT NULL AND member_type = 'full'));

COMMENT ON COLUMN public.family_invitations.email IS
	'Where the invitation message is DELIVERED (F-15). NULL = a link invitation (F-108), only for a caregiver placeholder. Locks the claim only for a viewer invitation (F-50) or a legacy one with no placeholder — otherwise whoever holds the token may claim (F-108).';


-- ── 3. Who may claim — ONE predicate, three readers ─────────────────────────

CREATE OR REPLACE FUNCTION public.invitation_claimable_by(
	p_member_type text,
	p_profile_id  bigint,
	p_inv_email   text,
	p_email       text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $$
	SELECT (p_member_type = 'full' AND p_profile_id IS NOT NULL)
	    OR (p_inv_email IS NOT NULL AND lower(p_inv_email) = lower(p_email));
$$;

ALTER FUNCTION public.invitation_claimable_by(text, bigint, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.invitation_claimable_by(text, bigint, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.invitation_claimable_by(text, bigint, text, text) TO service_role;

COMMENT ON FUNCTION public.invitation_claimable_by(text, bigint, text, text) IS
	'F-108: a caregiver invitation for a placeholder is claimable by any address (the link is the capability; the e-mail is delivery only); a viewer or legacy invitation only by its own address. Read by handle_new_user, claim_invitation_for_user, join_invitation_from_empty_family and invitation_offer_for_token.';


-- ── 4. create_invitation — the address may be absent for a placeholder ──────
-- Body from 20260924140000 (F-50). Changes:
--   * a NULL address is accepted for a placeholder while `feature.invite_link`
--     is on, and is IDEMPOTENT: an open invitation of that placeholder is
--     returned as it is (sharing again never kills a link already sent);
--   * an address for a placeholder whose open invitation is a LINK attaches to
--     that same row (same token, same expiry) instead of revoking it — the
--     e-mail is delivery, and the link already in a WhatsApp chat stays alive.
--     `email_sent_at` is cleared so F-101 reads the new message's fate.
-- Every other path is verbatim.

CREATE OR REPLACE FUNCTION public.create_invitation(
	p_email      text,
	p_role_id    bigint,
	p_profile_id bigint DEFAULT NULL
)
RETURNS TABLE (invitation_id bigint, token uuid, expires_at timestamp with time zone)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
	me          public.profiles%ROWTYPE;
	target      public.profiles%ROWTYPE;
	inv         public.family_invitations%ROWTYPE;
	open_inv    public.family_invitations%ROWTYPE;
	clean_email text := NULLIF(lower(trim(p_email)), '');
	role_to_use bigint;
	max_seats   int := public.setting_int('max_caregivers', 4);
	free_seats  int := public.setting_int('free_caregivers', 2);
	taken       int;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();

	IF me.id IS NULL OR NOT me.is_admin THEN
		RAISE EXCEPTION 'Somente administradores da família podem enviar convites.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF EXISTS (SELECT 1 FROM public.family_deletion_requests
	           WHERE family_id = me.family_id AND status = 'pending') THEN
		RAISE EXCEPTION 'Há uma solicitação de exclusão da família em andamento — convites ficam bloqueados até ela ser resolvida.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- F-108: no address is a LINK — only for a placeholder, only with the flag.
	IF clean_email IS NULL
	   AND (p_profile_id IS NULL OR NOT public.setting_bool('feature.invite_link', false)) THEN
		RAISE EXCEPTION 'Informe o e-mail de quem você quer convidar.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF clean_email IS NOT NULL AND EXISTS (
		SELECT 1 FROM public.profiles
		WHERE lower(email) = clean_email
		  AND user_id IS NOT NULL AND left_at IS NULL) THEN
		RAISE EXCEPTION 'Este e-mail já possui cadastro no aplicativo.'
			USING ERRCODE = 'check_violation';
	END IF;

	IF p_profile_id IS NOT NULL THEN
		-- F-56: the invitation is for a placeholder of MY family that nobody
		-- has claimed yet. Its role is the invitation's role.
		SELECT * INTO target FROM public.profiles
		WHERE id = p_profile_id AND family_id = me.family_id;
		IF target.id IS NULL THEN
			RAISE EXCEPTION 'Perfil não encontrado na sua família.'
				USING ERRCODE = 'check_violation';
		END IF;
		IF target.user_id IS NOT NULL OR target.left_at IS NOT NULL THEN
			RAISE EXCEPTION 'Só é possível convidar um responsável que ainda não entrou no aplicativo.'
				USING ERRCODE = 'check_violation';
		END IF;
		role_to_use := target.role_id;

		-- F-108: the placeholder's live invitation, if any (one at most — the
		-- resend below keeps it that way).
		SELECT * INTO open_inv FROM public.family_invitations fi
		WHERE fi.profile_id = target.id
		  AND fi.accepted_at IS NULL AND fi.revoked_at IS NULL
		  AND fi.expires_at > timezone('utc', now())
		ORDER BY fi.created_at DESC
		LIMIT 1;

		IF open_inv.id IS NOT NULL AND clean_email IS NULL THEN
			-- Share again: the link that is already out there.
			RETURN QUERY SELECT open_inv.id, open_inv.token, open_inv.expires_at;
			RETURN;
		END IF;

		IF open_inv.id IS NOT NULL AND open_inv.email IS NULL THEN
			-- A LINK gains an address to be mailed to: same row, same token.
			UPDATE public.family_invitations fi
			SET email = clean_email, email_sent_at = NULL
			WHERE fi.id = open_inv.id;
			RETURN QUERY SELECT open_inv.id, open_inv.token, open_inv.expires_at;
			RETURN;
		END IF;

		-- Resend keeps the identity: the placeholder's previous open invitation
		-- dies, the row and its days stay.
		UPDATE public.family_invitations fi
		SET revoked_at = timezone('utc', now())
		WHERE fi.profile_id = target.id
		  AND fi.accepted_at IS NULL AND fi.revoked_at IS NULL;
	ELSE
		-- F-41: a role is assignable when built-in OR a custom role of MY family —
		-- another family's custom role id must not resolve.
		IF NOT EXISTS (SELECT 1 FROM public.roles
		               WHERE id = p_role_id
		                 AND (family_id IS NULL OR family_id = me.family_id)) THEN
			RAISE EXCEPTION 'Papel inválido.'
				USING ERRCODE = 'check_violation';
		END IF;
		role_to_use := p_role_id;
	END IF;

	-- Resend semantics: revoke this e-mail's previous open invitation BEFORE
	-- counting seats, so a resend never trips the cap it already occupies.
	IF clean_email IS NOT NULL THEN
		UPDATE public.family_invitations fi
		SET revoked_at = timezone('utc', now())
		WHERE fi.family_id = me.family_id
		  AND lower(fi.email) = clean_email
		  AND fi.accepted_at IS NULL AND fi.revoked_at IS NULL;
	END IF;

	IF p_profile_id IS NULL THEN
		-- Seats taken = ACTIVE + PENDING members + open invitations that carry
		-- no placeholder (a placeholder's invitation is the placeholder's seat).
		SELECT public.seat_count(me.family_id)
		     + (SELECT count(*) FROM public.family_invitations fi
		        WHERE fi.family_id = me.family_id
		          AND fi.profile_id IS NULL
		          AND fi.member_type = 'full'
		          AND fi.accepted_at IS NULL AND fi.revoked_at IS NULL
		          AND fi.expires_at > timezone('utc', now()))
		INTO taken;

		-- F-37 (T-41: free_caregivers from settings) — the free tier includes N
		-- caregivers; adding beyond that is Premium. Add-only + grandfather (F-32).
		IF taken >= free_seats AND NOT public.is_premium(me.family_id) THEN
			RAISE EXCEPTION 'Famílias no plano gratuito incluem % responsáveis. Para adicionar mais (avós, babá, etc.), ative o Premium.', free_seats
				USING ERRCODE = 'check_violation';
		END IF;

		IF taken >= max_seats THEN
			RAISE EXCEPTION 'Esta família já atingiu o limite de % responsáveis (contando convites pendentes).', max_seats
				USING ERRCODE = 'check_violation';
		END IF;
	END IF;

	INSERT INTO public.family_invitations (family_id, email, role_id, invited_by, profile_id)
	VALUES (me.family_id, clean_email, role_to_use, me.id, p_profile_id)
	RETURNING * INTO inv;

	RETURN QUERY SELECT inv.id, inv.token, inv.expires_at;
END;
$$;

ALTER FUNCTION public.create_invitation(text, bigint, bigint) OWNER TO postgres;

COMMENT ON FUNCTION public.create_invitation(text, bigint, bigint) IS
	'Admin-only invitation. F-56: optionally for a placeholder (its role, its seat; resend revokes its previous open invitation). F-108: for a placeholder the address may be NULL (a link, feature.invite_link) — idempotent, returning the open invitation; an address given to an open LINK attaches to that same row and token.';


-- ── 5. handle_new_user — the link claims; another address waits to confirm ──
-- Body from 20260924140000 (F-50). Changes, invitee branch only:
--   * the token is looked up without the address; `invitation_claimable_by`
--     decides (a viewer or legacy invitation keeps its address lock);
--   * an UNCONFIRMED address other than the invitation's gets the account and
--     nothing else — the claim runs at confirmation (§6). A typo never
--     confirms, so it never holds the placeholder.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	meta_name    text;
	meta_role    text;
	meta_token   text;
	meta_family  text;
	meta_policy  text;
	inv          public.family_invitations%ROWTYPE;
	fam_id       bigint;
	new_role_id  bigint;
	admin_flag   boolean;
	max_seats    int := public.setting_int('max_caregivers', 4);
	free_seats   int := public.setting_int('free_caregivers', 2);
BEGIN
	-- Idempotency: never duplicate a profile (e.g. trigger re-run).
	IF EXISTS (SELECT 1 FROM public.profiles WHERE user_id = NEW.id) THEN
		RETURN NEW;
	END IF;

	meta_name   := NULLIF(trim(NEW.raw_user_meta_data ->> 'full_name'), '');
	meta_role   := NULLIF(trim(NEW.raw_user_meta_data ->> 'role'), '');
	meta_token  := NULLIF(trim(NEW.raw_user_meta_data ->> 'invite_token'), '');
	meta_family := NULLIF(trim(NEW.raw_user_meta_data ->> 'family_name'), '');
	meta_policy := NULLIF(trim(NEW.raw_user_meta_data ->> 'policy_version'), '');

	-- F-57: a sign-up that carries neither an invite token nor a role did not
	-- come through our forms (they always send the metadata) — it is an OAuth
	-- sign-up, whose raw_user_meta_data is the PROVIDER's. Raising here would
	-- abort the auth.users INSERT and the account would never exist, so the
	-- profile is DEFERRED: the client routes the profile-less session to
	-- onboarding, and the profile is created by complete_oauth_onboarding
	-- (founder) or claim-invitation (invitee). Deliberately NOT keyed on
	-- raw_app_meta_data->>'provider': the Admin API cannot forge it, so a
	-- provider-based rule is one the db gate can never exercise.
	IF meta_token IS NULL AND meta_role IS NULL THEN
		RETURN NEW;
	END IF;

	IF meta_token IS NOT NULL THEN
		-- INVITEE: token must be valid and pending; F-108 — who may claim it is
		-- `invitation_claimable_by` (a malformed token must fail with the
		-- friendly message, not a cast error).
		BEGIN
			SELECT * INTO inv
			FROM public.family_invitations
			WHERE token = meta_token::uuid
			  AND accepted_at IS NULL
			  AND revoked_at  IS NULL
			  AND expires_at  > timezone('utc', now());
		EXCEPTION WHEN invalid_text_representation THEN
			inv := NULL;
		END;

		IF inv.id IS NULL
		   OR NOT public.invitation_claimable_by(inv.member_type, inv.profile_id, inv.email, NEW.email) THEN
			RAISE EXCEPTION 'Convite inválido, expirado ou emitido para outro e-mail.'
				USING ERRCODE = 'check_violation';
		END IF;

		-- F-108: an address the invitation was NOT mailed to proves itself
		-- first. The account exists, profile-less; claim_invitation_on_confirm
		-- takes the seat when GoTrue stamps email_confirmed_at.
		IF NEW.email_confirmed_at IS NULL
		   AND (inv.email IS NULL OR lower(inv.email) <> lower(NEW.email)) THEN
			RETURN NEW;
		END IF;

		-- F-56: the invitation names a PLACEHOLDER — attach this auth user to
		-- that row instead of creating one. The name the person typed wins over
		-- the admin's description; role and colour stay (they are the seat).
		-- No seat gate: the placeholder already holds it (add-only + grandfather).
		IF inv.profile_id IS NOT NULL THEN
			UPDATE public.profiles p
			SET user_id                = NEW.id,
			    email                  = NEW.email,
			    full_name              = COALESCE(meta_name, p.full_name),
			    consent_accepted_at    = CASE WHEN meta_policy IS NOT NULL THEN timezone('utc', now()) END,
			    consent_policy_version = meta_policy
			WHERE p.id = inv.profile_id
			  AND p.family_id = inv.family_id
			  AND p.user_id IS NULL
			  AND p.left_at IS NULL;

			IF NOT FOUND THEN
				RAISE EXCEPTION 'Convite inválido, expirado ou emitido para outro e-mail.'
					USING ERRCODE = 'check_violation';
			END IF;

			UPDATE public.family_invitations
			SET accepted_at = timezone('utc', now())
			WHERE id = inv.id;

			INSERT INTO public.account_logs (family_id, actor_profile_id, target_profile_id, action, new_value)
			VALUES (inv.family_id, inv.profile_id, inv.profile_id, 'pending_member_claimed',
			        COALESCE(meta_name, split_part(NEW.email, '@', 1)));

			RETURN NEW;
		END IF;
	END IF;

	-- Fallback: e-mail local part (metadata should always carry the name).
	IF meta_name IS NULL THEN
		meta_name := split_part(NEW.email, '@', 1);
	END IF;

	IF meta_token IS NOT NULL THEN
		IF inv.member_type = 'viewer' THEN
			-- F-50: a viewer joins against the VIEWER caps, never a caregiver
			-- seat (the primary guard is create_viewer_invitation; this is the
			-- parallel-invite / lapsed-trial backstop).
			IF (SELECT count(*) FROM public.profiles
			    WHERE family_id = inv.family_id AND membership_type = 'viewer'
			      AND left_at IS NULL) >= public.setting_int('max_viewers', 4) THEN
				RAISE EXCEPTION 'Esta família já atingiu o limite de % visualizadores.', public.setting_int('max_viewers', 4)
					USING ERRCODE = 'check_violation';
			END IF;
			IF (SELECT count(*) FROM public.profiles
			    WHERE family_id = inv.family_id AND membership_type = 'viewer'
			      AND left_at IS NULL) >= public.setting_int('free_viewers', 1)
			   AND NOT public.is_premium(inv.family_id) THEN
				RAISE EXCEPTION 'Esta família já atingiu o limite de % visualizador(es) do plano gratuito. Peça ao administrador para ativar o Premium.', public.setting_int('free_viewers', 1)
					USING ERRCODE = 'check_violation';
			END IF;
		ELSE
			-- The family may have completed meanwhile (parallel invites racing).
			-- F-56: seat_count — a pending member holds a seat.
			IF public.seat_count(inv.family_id) >= max_seats THEN
				RAISE EXCEPTION 'Esta família já atingiu o limite de % responsáveis.', max_seats
					USING ERRCODE = 'check_violation';
			END IF;

			-- F-37 (T-41: free_caregivers from settings) backstop — a caregiver beyond
			-- the free tier joining a free family needs Premium. Primary guard is
			-- create_invitation; this covers the trial-expired / parallel-invite race.
			IF public.seat_count(inv.family_id) >= free_seats
			   AND NOT public.is_premium(inv.family_id) THEN
				RAISE EXCEPTION 'Esta família já atingiu o limite de % responsáveis do plano gratuito. Peça ao administrador para ativar o Premium e liberar novos cuidadores.', free_seats
					USING ERRCODE = 'check_violation';
			END IF;
		END IF;

		fam_id      := inv.family_id;
		new_role_id := inv.role_id;
		admin_flag  := false;

		UPDATE public.family_invitations
		SET accepted_at = timezone('utc', now())
		WHERE id = inv.id;
	ELSE
		-- FOUNDER: creates the family and becomes its admin (F-14 decision).
		IF meta_role IS NULL THEN
			RAISE EXCEPTION 'Selecione o seu papel para criar a conta.'
				USING ERRCODE = 'check_violation';
		END IF;

		-- F-27: catalog-driven lookup — the client sends the canonical slug;
		-- the PT-BR label is accepted as a fallback vocabulary.
		-- F-41: built-ins only — a founder has no family, so no custom row
		-- (from ANY family) may resolve here.
		SELECT id INTO new_role_id
		FROM public.roles
		WHERE family_id IS NULL
		  AND (lower(trim(role)) = lower(meta_role)
		    OR lower(trim(label_pt)) = lower(meta_role))
		ORDER BY id
		LIMIT 1;
		IF new_role_id IS NULL THEN
			RAISE EXCEPTION 'Papel inválido: %.', meta_role
				USING ERRCODE = 'check_violation';
		END IF;

		-- Family name chosen by the founder; neutral fallback for safety
		-- (the register form makes the field required).
		INSERT INTO public.families (name)
		VALUES (COALESCE(meta_family, 'Família ' || meta_name))
		RETURNING id INTO fam_id;

		admin_flag := true;
	END IF;

	-- S-11 QA: the color slot is assigned at join and belongs to the person —
	-- founder = 1; invitee = lowest slot free among the ACTIVE members (which
	-- naturally reuses a departed member's freed color).
	-- S-13: the LGPD consent (checkbox gated sign-up) is recorded with the
	-- policy version accepted, so it is demonstrable later (art. 8 §1).
	-- F-50: a viewer invitation makes a viewer — no colour (the palette is for
	-- the people who appear on a day).
	INSERT INTO public.profiles (user_id, full_name, role_id, email, family_id, is_admin, color_slot,
	                             consent_accepted_at, consent_policy_version, membership_type)
	VALUES (NEW.id, meta_name, new_role_id, NEW.email, fam_id, admin_flag,
	        CASE WHEN admin_flag THEN 1
	             WHEN inv.member_type = 'viewer' THEN NULL
	             ELSE public.next_free_color_slot(fam_id) END,
	        CASE WHEN meta_policy IS NOT NULL THEN timezone('utc', now()) END,
	        meta_policy,
	        COALESCE(inv.member_type, 'full'));

	RETURN NEW;
END;
$$;


-- ── 6. claim_invitation_for_user — the same predicate, a confirmed address ──
-- Body from 20260924140000 (F-50). Changes: the token is looked up without the
-- address and `invitation_claimable_by` decides; an UNCONFIRMED account may
-- claim only with the invitation's own address (defence in depth — the OAuth
-- path is always confirmed, and claim_invitation_on_confirm runs after the
-- stamp).

CREATE OR REPLACE FUNCTION public.claim_invitation_for_user(
	p_user_id           uuid,
	p_full_name         text,
	p_token             text,
	p_policy_version    text,
	p_confirm_migration boolean DEFAULT false
)
RETURNS TABLE (auth_uid uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	user_email  text;
	confirmed   timestamptz;
	expected    text;
	the_name    text;
	inv         public.family_invitations%ROWTYPE;
	prev_family text;
	max_seats   int := public.setting_int('max_caregivers', 4);
	free_seats  int := public.setting_int('free_caregivers', 2);
BEGIN
	PERFORM pg_advisory_xact_lock(hashtext(p_user_id::text));

	SELECT u.email, u.email_confirmed_at INTO user_email, confirmed
	FROM auth.users u WHERE u.id = p_user_id;
	IF user_email IS NULL THEN
		RAISE EXCEPTION 'Sessão não autenticada.' USING ERRCODE = '42501';
	END IF;

	IF EXISTS (SELECT 1 FROM public.profiles p
	           WHERE p.user_id = p_user_id AND p.left_at IS NULL) THEN
		RAISE EXCEPTION 'Esta conta já está vinculada a uma família.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- S-15 posture — same validation as complete_oauth_onboarding.
	expected := public.setting_text('policy.current_version', NULL::text);
	IF expected IS NULL THEN
		RAISE EXCEPTION 'Configuração policy.current_version ausente — aceite não pode ser registrado.'
			USING ERRCODE = 'P0002';
	END IF;
	IF p_policy_version IS DISTINCT FROM expected THEN
		RAISE EXCEPTION 'Versão da política desatualizada (enviada: %, vigente: %). Atualize o aplicativo.',
			coalesce(p_policy_version, '(nula)'), expected USING ERRCODE = '22023';
	END IF;

	-- Token validation — the trigger's invitee branch, F-108's predicate.
	BEGIN
		SELECT * INTO inv
		FROM public.family_invitations i
		WHERE i.token = p_token::uuid
		  AND i.accepted_at IS NULL
		  AND i.revoked_at  IS NULL
		  AND i.expires_at  > timezone('utc', now());
	EXCEPTION WHEN invalid_text_representation THEN
		inv := NULL;
	END;

	IF inv.id IS NULL
	   OR NOT public.invitation_claimable_by(inv.member_type, inv.profile_id, inv.email, user_email)
	   OR (confirmed IS NULL
	       AND (inv.email IS NULL OR lower(inv.email) <> lower(user_email))) THEN
		RAISE EXCEPTION 'Convite inválido, expirado ou emitido para outro e-mail.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- S-11: a departed previous-family registration must be consciously erased
	-- before joining the new family (1 e-mail = 1 family until F-30).
	prev_family := public.departed_member_family(user_email);
	IF prev_family IS NOT NULL THEN
		IF NOT p_confirm_migration THEN
			RAISE EXCEPTION 'MIGRATION_REQUIRED:%', prev_family
				USING ERRCODE = 'check_violation';
		END IF;

		-- Same teardown register-invitee runs, but the caller's own auth user
		-- SURVIVES (it is the session making this claim): their tombstoned
		-- profile is detached instead, and only other freed users are handed
		-- back for GoTrue deletion (whole-family purge can free several).
		RETURN QUERY
			SELECT purged.auth_uid
			FROM public.purge_departed_member_by_email(user_email) AS purged
			WHERE purged.auth_uid IS DISTINCT FROM p_user_id;

		UPDATE public.profiles p
		SET user_id = NULL
		WHERE p.user_id = p_user_id AND p.left_at IS NOT NULL;
	END IF;

	the_name := NULLIF(trim(p_full_name), '');

	-- F-56: the invitation names a PLACEHOLDER — attach this auth user to it.
	-- Same rules as the trigger: typed name wins, role and colour stay, no
	-- seat gate (the placeholder holds the seat).
	IF inv.profile_id IS NOT NULL THEN
		UPDATE public.profiles p
		SET user_id                = p_user_id,
		    email                  = user_email,
		    full_name              = COALESCE(the_name, p.full_name),
		    consent_accepted_at    = timezone('utc', now()),
		    consent_policy_version = expected
		WHERE p.id = inv.profile_id
		  AND p.family_id = inv.family_id
		  AND p.user_id IS NULL
		  AND p.left_at IS NULL;

		IF NOT FOUND THEN
			RAISE EXCEPTION 'Convite inválido, expirado ou emitido para outro e-mail.'
				USING ERRCODE = 'check_violation';
		END IF;

		UPDATE public.family_invitations i
		SET accepted_at = timezone('utc', now())
		WHERE i.id = inv.id;

		INSERT INTO public.account_logs (family_id, actor_profile_id, target_profile_id, action, new_value)
		VALUES (inv.family_id, inv.profile_id, inv.profile_id, 'pending_member_claimed',
		        COALESCE(the_name, split_part(user_email, '@', 1)));

		RETURN;
	END IF;

	-- Seat caps — verbatim mirror of the trigger's invitee branch.
	IF inv.member_type = 'viewer' THEN
		-- F-50: a viewer joins against the VIEWER caps, never a caregiver
		-- seat (the primary guard is create_viewer_invitation; this is the
		-- parallel-invite / lapsed-trial backstop).
		IF (SELECT count(*) FROM public.profiles
		    WHERE family_id = inv.family_id AND membership_type = 'viewer'
		      AND left_at IS NULL) >= public.setting_int('max_viewers', 4) THEN
			RAISE EXCEPTION 'Esta família já atingiu o limite de % visualizadores.', public.setting_int('max_viewers', 4)
				USING ERRCODE = 'check_violation';
		END IF;
		IF (SELECT count(*) FROM public.profiles
		    WHERE family_id = inv.family_id AND membership_type = 'viewer'
		      AND left_at IS NULL) >= public.setting_int('free_viewers', 1)
		   AND NOT public.is_premium(inv.family_id) THEN
			RAISE EXCEPTION 'Esta família já atingiu o limite de % visualizador(es) do plano gratuito. Peça ao administrador para ativar o Premium.', public.setting_int('free_viewers', 1)
				USING ERRCODE = 'check_violation';
		END IF;
	ELSE
		-- F-56: seat_count — a pending member holds a seat.
		IF public.seat_count(inv.family_id) >= max_seats THEN
			RAISE EXCEPTION 'Esta família já atingiu o limite de % responsáveis.', max_seats
				USING ERRCODE = 'check_violation';
		END IF;

		IF public.seat_count(inv.family_id) >= free_seats
		   AND NOT public.is_premium(inv.family_id) THEN
			RAISE EXCEPTION 'Esta família já atingiu o limite de % responsáveis do plano gratuito. Peça ao administrador para ativar o Premium e liberar novos cuidadores.', free_seats
				USING ERRCODE = 'check_violation';
		END IF;
	END IF;

	UPDATE public.family_invitations i
	SET accepted_at = timezone('utc', now())
	WHERE i.id = inv.id;

	the_name := COALESCE(the_name, split_part(user_email, '@', 1));

	INSERT INTO public.profiles (user_id, full_name, role_id, email, family_id, is_admin, color_slot,
	                             consent_accepted_at, consent_policy_version, membership_type)
	VALUES (p_user_id, the_name, inv.role_id, user_email, inv.family_id, false,
	        CASE WHEN inv.member_type = 'viewer' THEN NULL
	             ELSE public.next_free_color_slot(inv.family_id) END,
	        timezone('utc', now()), expected, inv.member_type);

	RETURN;
END;
$$;

ALTER FUNCTION public.claim_invitation_for_user(uuid, text, text, text, boolean) OWNER TO postgres;


-- ── 7. The claim at confirmation ─────────────────────────────────────────────
-- An e-mail + password sign-up with an address other than the invitation's
-- left a profile-less account (§5). When GoTrue stamps email_confirmed_at, the
-- token in the sign-up metadata is claimed through the same function the OAuth
-- path uses. It NEVER raises: a refusal here would roll back the confirmation
-- itself. A claim that cannot happen (the link was taken meanwhile, expired,
-- a departed registration needs consent — S-11) leaves the account confirmed
-- and profile-less, which the client routes to onboarding (F-57), exactly as
-- a Google sign-in that has not claimed yet.

CREATE OR REPLACE FUNCTION public.claim_invitation_on_confirm()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	meta_token text := NULLIF(trim(NEW.raw_user_meta_data ->> 'invite_token'), '');
BEGIN
	IF meta_token IS NULL THEN
		RETURN NEW;
	END IF;
	IF EXISTS (SELECT 1 FROM public.profiles WHERE user_id = NEW.id) THEN
		RETURN NEW;
	END IF;

	BEGIN
		PERFORM 1 FROM public.claim_invitation_for_user(
			NEW.id,
			NEW.raw_user_meta_data ->> 'full_name',
			meta_token,
			NULLIF(trim(NEW.raw_user_meta_data ->> 'policy_version'), ''),
			false);
	EXCEPTION WHEN OTHERS THEN
		RAISE WARNING '[claim_invitation_on_confirm] claim not made: %', SQLERRM;
	END;

	RETURN NEW;
END;
$$;

ALTER FUNCTION public.claim_invitation_on_confirm() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.claim_invitation_on_confirm() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.claim_invitation_on_confirm() IS
	'F-108: when an invitee''s address is confirmed, claims the invite_token of the sign-up metadata (claim_invitation_for_user). Never raises — a failed claim leaves the confirmed account profile-less, routed to onboarding.';

DROP TRIGGER IF EXISTS on_auth_user_confirmed_claim_invitation ON auth.users;
CREATE TRIGGER on_auth_user_confirmed_claim_invitation
	AFTER UPDATE ON auth.users
	FOR EACH ROW
	WHEN (OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL)
	EXECUTE FUNCTION public.claim_invitation_on_confirm();


-- ── 8. F-88 by the token — a solo founder opens a link ───────────────────────
-- join_invitation_from_empty_family: body from 20261005110000 (F-88), with the
-- address match replaced by `invitation_claimable_by`. The offer that leads to
-- it for a link is `invitation_offer_for_token` — my_pending_invitation's
-- rules, keyed on the token the person opened instead of their address.

CREATE OR REPLACE FUNCTION public.join_invitation_from_empty_family(
	p_token          uuid,
	p_policy_version text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me        public.profiles%ROWTYPE;
	the_email text;
	confirmed timestamptz;
	old_family bigint;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid() AND left_at IS NULL;
	IF me.id IS NULL THEN
		RAISE EXCEPTION 'Sessão inválida. Entre novamente.'
			USING ERRCODE = 'insufficient_privilege';
	END IF;
	SELECT u.email, u.email_confirmed_at INTO the_email, confirmed
	FROM auth.users u WHERE u.id = auth.uid();
	IF confirmed IS NULL THEN
		RAISE EXCEPTION 'Confirme seu e-mail antes de entrar em outra família.'
			USING ERRCODE = 'check_violation';
	END IF;

	-- The same family the offer judged — and judged again, under the lock the
	-- claim takes, so nothing planned since the dialog opened is discarded.
	PERFORM pg_advisory_xact_lock(hashtext(auth.uid()::text));
	IF NOT public.family_is_empty_for_join(me.family_id, me.id) THEN
		RAISE EXCEPTION 'Sua família atual já tem outros membros ou dias planejados — ela não pode ser descartada.'
			USING ERRCODE = 'check_violation';
	END IF;
	IF NOT EXISTS (SELECT 1 FROM public.family_invitations i
	               WHERE i.token = p_token
	                 AND public.invitation_claimable_by(i.member_type, i.profile_id, i.email, the_email)
	                 AND i.family_id <> me.family_id
	                 AND i.accepted_at IS NULL
	                 AND i.revoked_at  IS NULL
	                 AND i.expires_at  > timezone('utc', now())) THEN
		RAISE EXCEPTION 'Convite inválido, expirado ou emitido para outro e-mail.'
			USING ERRCODE = 'check_violation';
	END IF;

	old_family := me.family_id;

	-- The family-deletion teardown, under its own deletion context. It hands
	-- back the auth ids of the family's profiles for a caller to delete; this
	-- caller deletes none — the only one is this session's, which survives.
	PERFORM 1 FROM public.purge_family_data(old_family);
	PERFORM set_config('app.deletion_context', 'off', true);

	PERFORM 1 FROM public.claim_invitation_for_user(
		auth.uid(), me.full_name, p_token::text, p_policy_version, false);
END;
$$;

ALTER FUNCTION public.join_invitation_from_empty_family(uuid, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.join_invitation_from_empty_family(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.join_invitation_from_empty_family(uuid, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.invitation_offer_for_token(p_token uuid)
RETURNS TABLE (token uuid, family_name text, inviter_name text, member_type text)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me        public.profiles%ROWTYPE;
	the_email text;
	confirmed timestamptz;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid() AND left_at IS NULL;
	IF me.id IS NULL THEN
		RETURN;
	END IF;
	SELECT u.email, u.email_confirmed_at INTO the_email, confirmed
	FROM auth.users u WHERE u.id = auth.uid();
	IF the_email IS NULL OR confirmed IS NULL THEN
		RETURN;
	END IF;
	IF NOT public.family_is_empty_for_join(me.family_id, me.id) THEN
		RETURN;
	END IF;

	RETURN QUERY
	SELECT i.token, f.name, p.full_name, i.member_type
	FROM public.family_invitations i
	JOIN public.families f ON f.id = i.family_id
	JOIN public.profiles p ON p.id = i.invited_by
	WHERE i.token = p_token
	  AND public.invitation_claimable_by(i.member_type, i.profile_id, i.email, the_email)
	  AND i.family_id <> me.family_id
	  AND i.accepted_at IS NULL
	  AND i.revoked_at  IS NULL
	  AND i.expires_at  > timezone('utc', now());
END;
$$;

ALTER FUNCTION public.invitation_offer_for_token(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.invitation_offer_for_token(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.invitation_offer_for_token(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.invitation_offer_for_token(uuid) IS
	'F-108: F-88''s offer keyed on the token a signed-in person opened — returns the invitation when the caller (verified e-mail) is alone in an empty family and may claim it (invitation_claimable_by); nothing otherwise. join_invitation_from_empty_family does the move.';


-- ── 9. The bulletin counts the step F-108 is about ──────────────────────────
-- Body from 20261004120000 (T-101), plus three counts per cohort, read in the
-- family's FIRST 7 DAYS from account_logs and the accepted invitations —
-- neither is touched by the 30-day purge of never-accepted invitation rows
-- (S-15/A-4), which would otherwise make an old family read "never invited":
--   pending_no_invite_7d — added a pending member and created no invitation;
--   invited_7d           — created an invitation (e-mail or link);
--   invitee_joined_7d    — an invitation was accepted.

CREATE OR REPLACE FUNCTION public.admin_weekly_sales_bulletin_cohort(p_week_start date)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	start  date := public.acquisition_real_cohort_start();
	cut    timestamp with time zone := (start::timestamp AT TIME ZONE 'America/Sao_Paulo');
	lo     timestamp with time zone := (p_week_start::timestamp AT TIME ZONE 'America/Sao_Paulo');
	hi     timestamp with time zone := ((p_week_start + 7)::timestamp AT TIME ZONE 'America/Sao_Paulo');
	result jsonb;
BEGIN
	WITH
	fam AS (
		SELECT f.id,
		       f.created_at >= cut AS is_real,
		       coalesce(f.acquisition_source, 'unknown') AS source,
		       (f.created_at >= lo AND f.created_at < hi) AS in_week,
		       EXISTS (SELECT 1 FROM public.care_schedules cs
		                WHERE cs.family_id = f.id
		                  AND cs.created_at < f.created_at + interval '7 days') AS planned,
		       EXISTS (SELECT 1 FROM public.family_invitations i
		                WHERE i.family_id = f.id) AS invited,
		       EXISTS (SELECT 1 FROM public.family_invitations i
		                WHERE i.family_id = f.id AND i.accepted_at IS NOT NULL) AS joined,
		       EXISTS (SELECT 1 FROM public.account_logs l
		                WHERE l.family_id = f.id AND l.action = 'pending_member_added'
		                  AND l.created_at < f.created_at + interval '7 days') AS pending_7d,
		       EXISTS (SELECT 1 FROM public.account_logs l
		                WHERE l.family_id = f.id AND l.action = 'invitation_created'
		                  AND l.created_at < f.created_at + interval '7 days') AS invited_7d,
		       EXISTS (SELECT 1 FROM public.family_invitations i
		                WHERE i.family_id = f.id AND i.member_type = 'full'
		                  AND i.accepted_at < f.created_at + interval '7 days') AS joined_7d,
		       EXISTS (SELECT 1 FROM public.billing_events e
		                WHERE e.family_id = f.id
		                  AND e.event_type IN ('PAYMENT_CONFIRMED', 'PAYMENT_RECEIVED',
		                                       'PLAY_PURCHASE_VERIFIED',
		                                       'PLAY_RTDN_1', 'PLAY_RTDN_2', 'PLAY_RTDN_4', 'PLAY_RTDN_7')) AS paid,
		       (SELECT count(*) FROM public.family_referrals r
		         WHERE r.referrer_family_id = f.id) AS referred
		  FROM public.families f
	),
	src(source) AS (
		VALUES ('google_app'), ('google_search'), ('meta'), ('referral'), ('organic'), ('unknown')
	)
	SELECT jsonb_build_object(
		'start', start,
		'by_source', (
			SELECT jsonb_object_agg(t.source, t.stats)
			  FROM (
				SELECT s.source, jsonb_build_object(
					'families',             count(f.id),
					'created_week',         count(f.id) FILTER (WHERE f.in_week),
					'planned_7d',           count(f.id) FILTER (WHERE f.planned),
					'invited',              count(f.id) FILTER (WHERE f.invited),
					'invitee_joined',       count(f.id) FILTER (WHERE f.joined),
					'pending_no_invite_7d', count(f.id) FILTER (WHERE f.pending_7d AND NOT f.invited_7d),
					'invited_7d',           count(f.id) FILTER (WHERE f.invited_7d),
					'invitee_joined_7d',    count(f.id) FILTER (WHERE f.joined_7d),
					'paid',                 count(f.id) FILTER (WHERE f.paid),
					'referred_others',      coalesce(sum(f.referred), 0)) AS stats
				  FROM src s
				  LEFT JOIN fam f ON f.source = s.source AND f.is_real
				 GROUP BY s.source) t),
		'test_cohort', (
			SELECT jsonb_build_object(
				'families',             count(*),
				'planned_7d',           count(*) FILTER (WHERE planned),
				'invited',              count(*) FILTER (WHERE invited),
				'invitee_joined',       count(*) FILTER (WHERE joined),
				'pending_no_invite_7d', count(*) FILTER (WHERE pending_7d AND NOT invited_7d),
				'invited_7d',           count(*) FILTER (WHERE invited_7d),
				'invitee_joined_7d',    count(*) FILTER (WHERE joined_7d),
				'paid',                 count(*) FILTER (WHERE paid),
				'referred_others',      coalesce(sum(referred), 0))
			  FROM fam WHERE NOT is_real)
	) INTO result;

	RETURN result;
END;
$$;

COMMENT ON FUNCTION public.admin_weekly_sales_bulletin_cohort(date) IS
	'T-101: the bulletin''s real-cohort block — per acquisition source, cumulative since acquisition.real_cohort_start (São Paulo), plus the test cohort apart. F-108: pending_no_invite_7d / invited_7d / invitee_joined_7d read the family''s first 7 days. Counts only, no campaign token. Service role only.';

ALTER FUNCTION public.admin_weekly_sales_bulletin_cohort(date) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_weekly_sales_bulletin_cohort(date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_weekly_sales_bulletin_cohort(date) TO service_role;
