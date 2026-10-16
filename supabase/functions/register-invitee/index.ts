// U-17 — invitee sign-up with auto-confirmed e-mail.
//
// An invitee registers through /register?invite=<token>, where the e-mail is
// LOCKED to the invitation's address. Requiring a confirmation e-mail on top
// of that is redundant for the mailbox-link path and only marginally useful
// for the copied-link (WhatsApp) path, so the product decision (July 2026)
// is to auto-confirm invited users: this function validates the token and
// creates the user PRE-CONFIRMED via the GoTrue Admin API. The existing
// handle_new_user trigger then does what it always did — re-validate the
// invitation, create the profile, join the family and mark the invite
// accepted. Founders keep the normal confirmation flow (their e-mail is
// free-typed, so confirmation is the only ownership check there).
//
// Security: the invite token is the capability — without a valid, pending,
// unexpired token nothing is created, and the account e-mail is always the
// invitation's address (never caller-chosen). The secret key never leaves the
// server.
//
// S-16: this one runs with verify_jwt = false and gains NO in-code key check,
// unlike the other gate-less functions. Its caller is a person who has not
// signed up yet and therefore holds no session — only the publishable key,
// which is public by definition, so the gate never authenticated anybody here.
// The invitation token above is, and always was, the real authorization.

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

interface RegisterPayload {
  token?: string;
  fullName?: string;
  password?: string;
  // S-11 cross-family migration: set true after the caregiver acknowledged that
  // joining this family permanently erases their previous-family registration.
  confirmMigration?: boolean;
  // S-13: privacy-policy version the consent checkbox referred to — stamped on
  // the profile by handle_new_user (demonstrable consent, LGPD art. 8 §1).
  policyVersion?: string;
}

// GoTrue's "account already exists" message across API versions.
function isAlreadyRegistered(msg: string): boolean {
  return /already[\s_]*(been\s*)?registered|already exists/i.test(msg);
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey  = secretKey();
    const supabase    = createClient(supabaseUrl, serviceKey);

    const { token, fullName, password, confirmMigration, policyVersion }: RegisterPayload =
      await req.json();

    if (!token || !fullName?.trim() || !password) {
      return jsonResponse({ error: "Dados de cadastro incompletos." }, 400);
    }
    // Mirror the register form's client-side rule — the Admin API does not
    // apply the project's sign-up password policy.
    if (password.length < 8) {
      return jsonResponse({ error: "A senha deve ter pelo menos 8 caracteres." }, 400);
    }

    // The token is the capability: it must reference a pending, unexpired
    // invitation, and the account is created for THAT e-mail only.
    const { data: invitation } = await supabase
      .from("family_invitations")
      .select("email")
      .eq("token", token)
      .is("accepted_at", null)
      .is("revoked_at", null)
      .gt("expires_at", new Date().toISOString())
      .maybeSingle();

    if (!invitation) {
      return jsonResponse(
        { error: "Convite inválido, expirado ou emitido para outro e-mail." }, 400);
    }

    // Pre-confirmed creation; handle_new_user re-validates the token, creates
    // the profile and marks the invitation accepted (same trigger as always).
    const createUser = () => supabase.auth.admin.createUser({
      email: invitation.email,
      password,
      email_confirm: true,
      user_metadata: {
        full_name: fullName.trim(),
        invite_token: token,
        policy_version: policyVersion ?? "",
      },
    });

    let { error: createError } = await createUser();

    // S-11: "1 e-mail = 1 family" — the account may already exist because this
    // caregiver LEFT another family and is within the 30-day grace (GoTrue user
    // still alive). create_invitation forbids inviting ACTIVE members, so an
    // "already registered" here means either a departed member (migratable) or
    // a fully active account elsewhere (never — but treated as non-migratable).
    if (createError && isAlreadyRegistered(createError.message ?? "")) {
      const { data: previousFamily } = await supabase
        .rpc("departed_member_family", { p_email: invitation.email });

      if (!previousFamily) {
        // Not a departed member → cannot migrate; keep the plain rejection.
        return jsonResponse(
          { error: "Este e-mail já possui cadastro. Faça login ou recupere a senha." }, 409);
      }

      if (!confirmMigration) {
        // Ask the client to warn the caregiver before the destructive step.
        return jsonResponse({
          needsMigration: true,
          previousFamilyName: previousFamily,
          error: `Este e-mail já pertence à família "${previousFamily}". ` +
                 "Entrar nesta nova família apagará definitivamente aquele cadastro.",
        }, 409);
      }

      // Consent given: run the definitive erasure of the previous-family
      // registration NOW (same teardown the grace-expiry cron would do), delete
      // the freed GoTrue user(s), then retry the account creation for this family.
      const { data: purged, error: purgeError } = await supabase
        .rpc("purge_departed_member_by_email", { p_email: invitation.email });
      if (purgeError) {
        console.error(`[register-invitee] purge failed: ${purgeError.message}`);
        return jsonResponse(
          { error: "Não foi possível concluir a migração. Tente novamente." }, 500);
      }
      for (const row of (purged ?? []) as { auth_uid: string }[]) {
        if (!row.auth_uid) continue;
        const { error: delError } = await supabase.auth.admin.deleteUser(row.auth_uid);
        if (delError) {
          console.error(`[register-invitee] deleteUser(${row.auth_uid}) failed: ${delError.message}`);
          return jsonResponse(
            { error: "Não foi possível concluir a migração. Tente novamente." }, 500);
        }
      }

      ({ error: createError } = await createUser());
    }

    if (createError) {
      console.error(`[register-invitee] createUser failed: ${createError.message}`);
      const msg = createError.message ?? "";
      if (isAlreadyRegistered(msg)) {
        return jsonResponse(
          { error: "Este e-mail já possui cadastro. Faça login ou recupere a senha." }, 409);
      }
      // Trigger-raised messages (seat cap, invalid invite) are already PT-BR.
      const dbMessage = /[a-zçãéíõê]/i.test(msg) && /família|convite|respons/i.test(msg)
        ? msg.replace(/^.*?:\s*/, "")
        : "Não foi possível criar a conta. Tente novamente.";
      return jsonResponse({ error: dbMessage }, 400);
    }

    // S-11 + F-59: the existing members learn that someone joined from the
    // `member_joined` row the notify_member_joined trigger writes, and from its
    // push. There is no e-mail any more — it was the third copy of one fact.

    return jsonResponse({ ok: true });
  } catch (err) {
    console.error(`[register-invitee] unexpected: ${err instanceof Error ? err.message : err}`);
    return jsonResponse({ error: "Não foi possível criar a conta. Tente novamente." }, 500);
  }
});
