// F-57 — invite claim for an EXISTING (social-login) session.
//
// register-invitee creates a password account for someone who does not exist
// yet. A Google invitee is the mirror image: the account already exists (the
// OAuth redirect created it — or automatic linking landed them on their old
// one), but it has no profile, because handle_new_user DEFERS the profile when
// a sign-up arrives with provider ≠ 'email' and no invite metadata. This
// function attaches that session to the invitation's family.
//
// Identity comes from the session token, never from the request body (the
// elevate pattern): the platform's JWT verification gates the call, and the
// user id + e-mail are resolved server-side. The invitation token remains the
// capability that selects WHICH family — and the SQL half refuses a token
// issued for another e-mail, so a stolen token alone attaches nobody.
//
// The heavy lifting is claim_invitation_for_user (service_role-only SQL twin
// of handle_new_user's invitee branch). It handles the S-11 cross-family
// migration atomically and hands back the auth uids freed by the purge —
// NEVER the caller's own (their session must survive the claim) — for this
// function to delete via the Admin API, exactly like register-invitee does.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { secretKey } from "../_shared/keys.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

interface ClaimPayload {
  token?: string;
  fullName?: string;
  // S-13: privacy-policy version the consent checkbox referred to — validated
  // against policy.current_version and stamped on the profile (LGPD art. 8 §1).
  policyVersion?: string;
  // S-11 cross-family migration: set true after the caregiver acknowledged that
  // joining this family permanently erases their previous-family registration.
  confirmMigration?: boolean;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey  = secretKey();
    const admin       = createClient(supabaseUrl, serviceKey);

    // Identity comes from the session token, never from the request body.
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) {
      return jsonResponse({ error: "Sessão inválida. Entre novamente." }, 401);
    }
    const { data: userData, error: userError } = await admin.auth.getUser(jwt);
    if (userError || !userData?.user?.id) {
      return jsonResponse({ error: "Sessão inválida. Entre novamente." }, 401);
    }

    const { token, fullName, policyVersion, confirmMigration }: ClaimPayload =
      await req.json().catch(() => ({} as ClaimPayload));

    if (!token) {
      return jsonResponse({ error: "Convite inválido, expirado ou emitido para outro e-mail." }, 400);
    }

    const { data: freed, error: claimError } = await admin
      .rpc("claim_invitation_for_user", {
        p_user_id: userData.user.id,
        p_full_name: fullName?.trim() ?? "",
        p_token: token,
        p_policy_version: policyVersion ?? "",
        p_confirm_migration: confirmMigration === true,
      });

    if (claimError) {
      const msg = claimError.message ?? "";

      // S-11: warn before the destructive step — same response shape as
      // register-invitee, so the client reuses its migration dialog.
      const migration = msg.match(/MIGRATION_REQUIRED:(.*)$/);
      if (migration) {
        const previousFamily = migration[1].trim();
        return jsonResponse({
          needsMigration: true,
          previousFamilyName: previousFamily,
          error: `Este e-mail já pertence à família "${previousFamily}". ` +
                 "Entrar nesta nova família apagará definitivamente aquele cadastro.",
        }, 409);
      }

      console.error(`[claim-invitation] rpc failed: ${msg}`);
      // RPC-raised messages (seat cap, invalid invite, stale policy) are
      // already PT-BR user text, and PostgREST hands the RAISE message over
      // BARE — no prefix to strip. (register-invitee's prefix-strip is for
      // GoTrue Admin API errors, and here it would eat everything up to the
      // first colon INSIDE the message, e.g. "…(enviada: ".)
      const dbMessage = /[a-zçãéíõê]/i.test(msg) && /família|convite|respons|política|conta|sessão/i.test(msg)
        ? msg
        : "Não foi possível entrar na família. Tente novamente.";
      return jsonResponse({ error: dbMessage }, 400);
    }

    // S-11 migration aftermath: the purge freed OTHER auth users (the caller's
    // own was detached, never returned) — delete them so their e-mails free up,
    // exactly like register-invitee.
    for (const row of (freed ?? []) as { auth_uid: string }[]) {
      if (!row.auth_uid) continue;
      const { error: delError } = await admin.auth.admin.deleteUser(row.auth_uid);
      if (delError) {
        // The claim itself already committed — log loudly, never fail the join.
        console.error(`[claim-invitation] deleteUser(${row.auth_uid}) failed: ${delError.message}`);
      }
    }

    // S-11 + F-59: the existing members learn that someone joined from the
    // `member_joined` row the notify_member_joined trigger writes, and from its
    // push. There is no e-mail any more — it was the third copy of one fact.

    return jsonResponse({ ok: true });
  } catch (err) {
    console.error(`[claim-invitation] unexpected: ${err instanceof Error ? err.message : err}`);
    return jsonResponse({ error: "Não foi possível entrar na família. Tente novamente." }, 500);
  }
});
