import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { secretKey } from "../_shared/keys.ts";
import { hasValidUserSession, internalCallHeaders, isSecretKeyCaller } from "../_shared/auth.ts";

// Scheduled (cron) Edge Function — S-11.
// Hard-deletes accounts whose 30-day grace period has elapsed: calls
// purge_expired_accounts() (which scrubs the e-mail and returns the GoTrue
// user ids to remove — the profile row stays as a tombstone, keeping the name
// for calendar/audit history) and deletes those auth users via the Admin API.
// The profile's user_id is then nulled by the ON DELETE SET NULL constraint.
//
// PR2 adds the whole-family consent flow:
//   · family_deletion_reminders_due() — D-3 reminder (in-app rows written by
//     the RPC; the e-mail twin dispatched here via send-account-email).
//   · purge_expired_family_deletions() — requests past their 30-day window:
//     the RPC hands back each member's auth uid + REAL e-mail + family name
//     (collected BEFORE the teardown), here the GoTrue users are deleted and
//     the farewell e-mail goes out to the collected addresses.
//
// S-15 (PR3b) adds two retention/notice duties to the same daily pass:
//   · purge_stale_invitations()   — A-4: invitations never accepted, older than
//     30 days, which is what makes the invitation e-mail's purge promise true.
//   · billing_grace_warnings_due() — B-3: warns family admins by e-mail before
//     the Premium grace period expires, as the Terms now promise. The RPC writes
//     the in-app notice; the e-mail here is the best-effort twin.
//
// Not browser-invoked, so no CORS handling is needed. Trigger on a schedule
// (pg_cron -> net.http_post, or the Supabase cron scheduler), e.g. hourly.

interface GraceWarningRow {
  subscription_id: number;
  family_id: number;
  admin_profile_id: number;
  grace_ends_at: string;
}

interface FamilyPurgeRow {
  purged_family_id: number;
  auth_uid: string | null;
  member_email: string | null;
  family_name: string;
}

serve(async (req: Request) => {
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey  = secretKey();
    const supabase    = createClient(supabaseUrl, serviceKey);

    // S-16: verify_jwt is off (the cron authenticates with the SECRET key on
    // `apikey`, which the platform gate does not verify), so authorize here.
    // Two legitimate callers: the cron/internal one holding the secret key, and
    // the app itself, which invokes this right after a deletion request with the
    // user's session — exactly what the gate used to accept.
    if (!isSecretKeyCaller(req, serviceKey) && !(await hasValidUserSession(req, supabase))) {
      console.warn("[purge-deleted] refused — neither secret key nor a valid session");
      return json({ error: "Não autorizado." }, 401);
    }

    const envName   = Deno.env.get("APP_ENVIRONMENT") ?? "Production";
    const envPrefix = envName.toLowerCase() === "production" ? "" : "[Dev] ";

    const sendAccountEmail = async (body: Record<string, unknown>) => {
      const res = await fetch(`${supabaseUrl}/functions/v1/send-account-email`, {
        method: "POST",
        headers: internalCallHeaders(serviceKey),
        body: JSON.stringify({ ...body, environmentPrefix: envPrefix }),
      });
      if (!res.ok) throw new Error(`send-account-email ${res.status}: ${await res.text()}`);
    };

    // ── 1. Individual accounts past their grace ─────────────────────────────
    const { data, error } = await supabase.rpc("purge_expired_accounts");
    if (error) {
      console.error(`[purge-deleted] rpc failed — ${error.message}`);
      return json({ error: error.message }, 500);
    }

    const rows = (data ?? []) as { user_id: string }[];
    console.log(`[purge-deleted] ${rows.length} expired account(s) to remove from auth`);

    let failed = 0;
    for (const row of rows) {
      if (!row.user_id) continue;
      const { error: delError } = await supabase.auth.admin.deleteUser(row.user_id);
      if (delError) {
        failed++;
        // Left for the next run: the profile still has user_id set, so
        // purge_expired_accounts returns it again (convergent retry).
        console.error(`[purge-deleted] deleteUser ${row.user_id} failed — ${delError.message}`);
      }
    }

    // ── 1b. Retention (S-13): read notifications older than 6 months ────────
    let notificationsPurged = 0;
    const { data: retData, error: retError } = await supabase.rpc("purge_old_notifications");
    if (retError) {
      console.error(`[purge-deleted] retention rpc failed — ${retError.message}`);
    } else {
      notificationsPurged = (retData as number) ?? 0;
    }

    // ── 1c. Retention (S-15/A-4): invitations never accepted, older than 30d ─
    // What makes the invitation e-mail's purge promise true. Independent of the
    // blocks around it: a failure here must not stop the account purges.
    let invitationsPurged = 0;
    const { data: invData, error: invError } = await supabase.rpc("purge_stale_invitations");
    if (invError) {
      console.error(`[purge-deleted] invitation purge rpc failed — ${invError.message}`);
    } else {
      invitationsPurged = (invData as number) ?? 0;
    }

    // ── 1c'. Retention (F-68): support requests older than 12 months ────────
    // The period privacidade.html §3 promises. Independent, like the two above.
    let supportPurged = 0;
    const { data: supData, error: supError } = await supabase.rpc("purge_old_support_requests");
    if (supError) {
      console.error(`[purge-deleted] support retention rpc failed — ${supError.message}`);
    } else {
      supportPurged = (supData as number) ?? 0;
    }

    // ── 1d. Premium grace warnings (S-15/B-3, sent once) ────────────────────
    // The Terms promise an e-mail before the downgrade. The RPC already wrote the
    // in-app notice and stamped the marker inside its own transaction, so the
    // e-mail below is the best-effort twin — exactly like the D-3 reminder: if
    // Resend is down the user still sees the warning in the app, and the marker
    // is deliberately NOT rolled back (a second wave would be worse than a
    // missing e-mail whose message already reached the app).
    let graceWarnings = 0;
    const { data: warnData, error: warnError } = await supabase.rpc("billing_grace_warnings_due");
    if (warnError) {
      console.error(`[purge-deleted] grace warning rpc failed — ${warnError.message}`);
    } else {
      for (const w of (warnData ?? []) as GraceWarningRow[]) {
        try {
          await sendAccountEmail({
            emailType: "premium_grace_ending",
            profileId: w.admin_profile_id,
            graceEndsAt: w.grace_ends_at,
          });
          graceWarnings++;
        } catch (mailErr) {
          console.error(`[purge-deleted] grace warning e-mail failed — ${mailErr instanceof Error ? mailErr.message : mailErr}`);
        }
      }
    }

    // ── 2. Family-deletion reminders (D-3, sent once) ───────────────────────
    let reminders = 0;
    const { data: due, error: remError } = await supabase.rpc("family_deletion_reminders_due");
    if (remError) {
      console.error(`[purge-deleted] reminders rpc failed — ${remError.message}`);
    } else {
      for (const r of (due ?? []) as { request_id: number; requester_profile_id: number }[]) {
        try {
          await sendAccountEmail({
            emailType: "family_deletion_reminder",
            profileId: r.requester_profile_id,
          });
          reminders++;
        } catch (mailErr) {
          // In-app notices are already written (reliable channel); the e-mail
          // twin is best-effort and reminder_sent_at is not rolled back.
          console.error(`[purge-deleted] reminder e-mail failed — ${mailErr instanceof Error ? mailErr.message : mailErr}`);
        }
      }
    }

    // ── 3. Family deletions past their 30-day window ────────────────────────
    let familiesPurged = 0;
    const { data: famData, error: famError } = await supabase.rpc("purge_expired_family_deletions");
    if (famError) {
      console.error(`[purge-deleted] family purge rpc failed — ${famError.message}`);
    } else {
      const famRows = (famData ?? []) as FamilyPurgeRow[];
      const byFamily = new Map<number, FamilyPurgeRow[]>();
      for (const row of famRows) {
        const group = byFamily.get(row.purged_family_id) ?? [];
        group.push(row);
        byFamily.set(row.purged_family_id, group);
      }

      for (const [familyId, members] of byFamily) {
        familiesPurged++;
        for (const m of members) {
          if (!m.auth_uid) continue;
          const { error: delError } = await supabase.auth.admin.deleteUser(m.auth_uid);
          if (delError) {
            failed++;
            console.error(`[purge-deleted] deleteUser ${m.auth_uid} (family ${familyId}) failed — ${delError.message}`);
          }
        }
        const recipients = members.map((m) => m.member_email).filter((e): e is string => !!e);
        if (recipients.length > 0) {
          try {
            await sendAccountEmail({
              emailType: "family_deletion_completed",
              recipients,
              familyName: members[0].family_name,
            });
          } catch (mailErr) {
            console.error(`[purge-deleted] farewell e-mail (family ${familyId}) failed — ${mailErr instanceof Error ? mailErr.message : mailErr}`);
          }
        }
      }
    }

    console.log(`[purge-deleted] done — accounts=${rows.length} families=${familiesPurged} reminders=${reminders} oldNotifications=${notificationsPurged} staleInvitations=${invitationsPurged} oldSupportRequests=${supportPurged} graceWarnings=${graceWarnings} failed=${failed}`);
    return json({
      purged: rows.length - failed,
      families: familiesPurged,
      reminders,
      oldNotifications: notificationsPurged,
      staleInvitations: invitationsPurged,
      oldSupportRequests: supportPurged,
      graceWarnings,
      failed,
    });
  } catch (err) {
    console.error(`[purge-deleted] unexpected — ${err instanceof Error ? err.message : err}`);
    return json({ error: "unexpected" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
