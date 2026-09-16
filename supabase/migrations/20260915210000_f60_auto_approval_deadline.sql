-- F-60 — the auto-approval deadline the notice promises must be the one the
-- request has.
--
-- F-24's clock is anchored on the DAY, and it is RIGHT: the deadline that
-- matters to a two-party workflow is the day being decided, not when someone
-- happened to ask. The SENTENCES were wrong — they described a window measured
-- from the request, and missed in both directions. Production request #32
-- (31/08/2026, no handoff, so expiry was 00:00 of that day) was created at
-- 16:20 BRT and got its "expires in 24h" nudge 7h48 later, with auto-approval
-- falling at 00:00 of 02/09: the target had ~31 h and was promised 48. A
-- request opened a week ahead gets the opposite lie.
--
-- So this revision keeps the rule untouched and changes what is SAID:
--   * the reminder carries `params.deadline` — the `YYYY-MM-DDTHH:MM` wall
--     clock of America/Sao_Paulo for `expiry + 48 h` — and its stored PT-BR
--     sentence names that instant. The client (U-13/U-24), the push
--     (`_shared/push.ts`) and the e-mail (`_shared/i18n.ts`) render the same
--     instant in the READER's language and format;
--   * every sentence written AFTER the fact drops the number instead of
--     quoting a window nobody had: "por falta de resposta".
--
-- Re-anchoring the clock on GREATEST(expiry, created_at) is option 2 of the
-- card and a SEPARATE decision — it does not ride along with a copy fix.
--
-- Written from the LATEST body of the function (20260909120000, F-56): a
-- CREATE OR REPLACE from a remembered version silently deletes later rules —
-- here, the F-56 fan-out filter that skips profiles with no account.

CREATE OR REPLACE FUNCTION public.auto_approve_expired(p_env_prefix text DEFAULT '')
RETURNS TABLE (swap_request_id bigint, email_type text)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    rec           record;
    tz            constant text := 'America/Sao_Paulo';
    expiry        timestamptz;
    d             text;
    d_iso         text;   -- U-24: ISO for params; `d` stays PT-BR in the stored sentence
    deadline      timestamptz;  -- F-60: expiry + 48 h, the instant the request stops waiting
    deadline_iso  text;   -- `YYYY-MM-DDTHH:MM` wall clock of America/Sao_Paulo, for params
    deadline_d    text;   -- PT-BR day for the STORED sentence
    deadline_t    text;   -- PT-BR hour for the STORED sentence
    proposed_name text;
    fanout_msg    text;
    fanout_kind   text;
BEGIN
    -- ── 24h reminders: expired between 24h and 48h ago, not yet reminded ──
    FOR rec IN
        SELECT * FROM public.swap_requests
        WHERE status IN ('pending', 'revert_pending') AND reminder_sent_at IS NULL
    LOOP
        expiry := (rec.schedule_date + COALESCE(rec.proposed_handoff_time, '00:00'::time)) AT TIME ZONE tz;
        IF now() >= expiry + interval '24 hours' AND now() < expiry + interval '48 hours' THEN
            d := to_char(rec.schedule_date, 'DD/MM');
            d_iso := to_char(rec.schedule_date, 'YYYY-MM-DD');
            -- F-60: the notice promises the deadline the request ACTUALLY has.
            -- The anchor is unchanged (the DAY, not the request); what changes
            -- is that the sentence states the instant instead of a window it
            -- never measured. `deadline_iso` is a wall clock, so the reader's
            -- device formats it without having to know our timezone.
            deadline := expiry + interval '48 hours';
            deadline_iso := to_char(deadline AT TIME ZONE tz, 'YYYY-MM-DD"T"HH24:MI');
            deadline_d := to_char(deadline AT TIME ZONE tz, 'DD/MM/YYYY');
            deadline_t := to_char(deadline AT TIME ZONE tz, 'HH24:MI');
            INSERT INTO public.notifications (recipient_profile_id, type, title, message, params, swap_request_id, is_read, created_at)
            VALUES (
                rec.target_profile_id,
                'auto_reminder',
                p_env_prefix || '⏰ Solicitação pendente aguardando resposta',
                'A solicitação do dia ' || d || ' será aprovada automaticamente em '
                    || deadline_d || ' às ' || deadline_t || ' se não houver resposta.',
                jsonb_build_object('date', d_iso, 'deadline', deadline_iso),
                rec.id, false, now()
            );
            UPDATE public.swap_requests SET reminder_sent_at = now() WHERE id = rec.id;

            swap_request_id := rec.id; email_type := 'reminder'; RETURN NEXT;
        END IF;
    END LOOP;

    -- ── Auto-approve: expired more than 48h ago ──────────────────────────
    FOR rec IN
        SELECT * FROM public.swap_requests
        WHERE status IN ('pending', 'revert_pending')
    LOOP
        expiry := (rec.schedule_date + COALESCE(rec.proposed_handoff_time, '00:00'::time)) AT TIME ZONE tz;
        IF now() >= expiry + interval '48 hours' THEN
            d := to_char(rec.schedule_date, 'DD/MM');
            d_iso := to_char(rec.schedule_date, 'YYYY-MM-DD');

            -- The person the day lands on: the proposed parent (for a revert
            -- request that is the restored planned responsible).
            SELECT full_name INTO proposed_name
            FROM public.profiles WHERE id = rec.proposed_actual_parent_id;

            IF rec.status = 'pending' THEN
                IF rec.schedule_id IS NOT NULL THEN
                    UPDATE public.care_schedules
                    SET actual_parent_id = rec.proposed_actual_parent_id,
                        handoff_time     = rec.proposed_handoff_time,
                        updated_at       = timezone('utc', now())
                    WHERE id = rec.schedule_id;
                END IF;
                UPDATE public.swap_requests SET status = 'approved', resolved_by = 'system' WHERE id = rec.id;

                fanout_msg := COALESCE(proposed_name, 'Outro responsável')
                    || ' ficará com a criança no dia ' || d
                    || ' (troca aprovada automaticamente por falta de resposta).';
                fanout_kind := 'auto_swap';
            ELSE
                -- F-47: the requester's decision about the day observation.
                PERFORM public.restore_pre_edit_state(rec.schedule_id, rec.pre_edit_log_id, rec.revert_notes);
                UPDATE public.swap_requests SET status = 'revert_approved', resolved_by = 'system' WHERE id = rec.id;

                fanout_msg := 'A troca do dia ' || d || ' foi revertida automaticamente — '
                    || COALESCE(proposed_name, 'o responsável planejado')
                    || ' volta a ficar com a criança.';
                fanout_kind := 'auto_revert';
            END IF;

            -- Notify the requester and the approver (distinct copy).
            -- U-13: same `type`, two different wordings — so `role` is the
            -- discriminator the renderer branches on. Without it the reader
            -- would get the other party's sentence.
            INSERT INTO public.notifications (recipient_profile_id, type, title, message, params, swap_request_id, is_read, created_at)
            VALUES (
                rec.requesting_profile_id, 'auto_approved',
                p_env_prefix || '✅ Solicitação aprovada automaticamente',
                'A solicitação do dia ' || d || ' foi aprovada automaticamente por falta de resposta.',
                jsonb_build_object('date', d_iso, 'role', 'requester'),
                rec.id, false, now()
            );
            INSERT INTO public.notifications (recipient_profile_id, type, title, message, params, swap_request_id, is_read, created_at)
            VALUES (
                rec.target_profile_id, 'auto_approved',
                p_env_prefix || '✅ Solicitação aprovada automaticamente',
                'A solicitação do dia ' || d || ' foi aprovada automaticamente. Você não respondeu dentro do prazo.',
                jsonb_build_object('date', d_iso, 'role', 'approver'),
                rec.id, false, now()
            );

            -- F-28: family-info fan-out to uninvolved caregivers.
            -- U-13: `name` is USER DATA (a caregiver's own name) and is passed
            -- through untranslated, exactly like the role catalogue's custom
            -- roles. `kind` tells the renderer swap from revert.
            -- F-56: only caregivers with an account — a pending member has no
            -- session to read it in, and a departed one is out.
            INSERT INTO public.notifications (recipient_profile_id, type, title, message, params, swap_request_id, is_read, created_at)
            SELECT p.id, 'swap_family_info',
                   p_env_prefix || '📅 Calendário atualizado',
                   fanout_msg,
                   jsonb_build_object('date', d_iso, 'kind', fanout_kind, 'name', proposed_name),
                   rec.id, false, now()
            FROM public.profiles p
            WHERE p.family_id = rec.family_id
              AND p.left_at IS NULL AND p.user_id IS NOT NULL
              AND p.id NOT IN (rec.requesting_profile_id, rec.target_profile_id);

            swap_request_id := rec.id; email_type := 'auto_approved'; RETURN NEXT;
        END IF;
    END LOOP;
END;
$$;
