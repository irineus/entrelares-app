import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { secretKey } from "../_shared/keys.ts";
import { hasValidUserSession, isSecretKeyCaller } from "../_shared/auth.ts";
import { isTestRecipient } from "../_shared/mail.ts";
import { button, emailDocument, heading, paragraph, rawUrl, small, smallLink } from "../_shared/email_layout.ts";
import { common, formatDateIn, type Lang, resolveLang, roleLabel, swap as swapText } from "../_shared/i18n.ts";

// F-15 — the invitation e-mail, the ONE message this function still sends.
//
// F-59 (owner, 02/10/2026): e-mail is kept only where nothing else can reach
// the reader. The person invited has no account and no app yet, so the
// invitation stays an e-mail. Every swap-workflow notice — request, answer,
// cancellation, revert, the F-24 reminder and auto-approval — is push + in-app
// only now: the `notifications` row is written by the app or the database, and
// the push follows from its trigger (F-09). The name stays for the invitation's
// sake and because Android builds already in Production call it by name.
//
// Those builds still dispatch the retired types from the client after every
// swap action. They are answered 200 with `skipped`, never 400: the app
// ignores the response by contract, and an error status would only fill the
// function's logs with noise for a call that did exactly what it should.
//
// The F-38 monthly quota went with them — it only ever counted these e-mails
// and the invitation, and a family is not rationed on invitations.

const RESEND_API_URL = "https://api.resend.com/emails";

// CORS headers required for every response from a browser-invoked Edge Function.
// The Supabase JS client always sends X-Client-Info; omitting it from the
// preflight Allow list causes the browser to block the actual POST.
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

/** F-59: the swap-workflow types this function used to mail. Push + in-app only now. */
const RETIRED_SWAP_EMAIL_TYPES: readonly string[] = [
  "swap_requested",
  "approved",
  "rejected",
  "cancelled",
  "reverted",
  "revert_requested",
  "revert_approved",
  "revert_rejected",
  "revert_cancelled",
  "reminder",
  "auto_approved",
];

interface EmailPayload {
  invitationId?: number;    // required for emailType "invitation" (F-15)
  emailType: string;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const resendKey = Deno.env.get("RESEND_API_KEY");
    if (!resendKey) throw new Error("RESEND_API_KEY secret is not configured.");

    const fromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? "noreply@entrelares.app";
    const fromName  = Deno.env.get("RESEND_FROM_NAME")  ?? "Entrelares";
    const appUrl    = (Deno.env.get("APP_URL") ?? "https://web.entrelares.app").replace(/\/$/, "");

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey  = secretKey();
    const supabase    = createClient(supabaseUrl, serviceKey);

    // S-16: with verify_jwt off (the new keys can't be verified by the gate),
    // this function authorizes its own callers — otherwise it would be an open
    // e-mail relay. The caller is the app, with the user's session.
    if (!isSecretKeyCaller(req, serviceKey) && !(await hasValidUserSession(req, supabase))) {
      console.warn("[send-swap-email] refused — neither secret key nor a valid session");
      return jsonResponse({ error: "Não autorizado." }, 401);
    }

    const { invitationId, emailType }: EmailPayload = await req.json();

    if (emailType === "invitation") {
      if (!invitationId) {
        return jsonResponse({ error: "invitationId is required for emailType invitation." }, 400);
      }
      return await handleInvitationEmail(supabase, invitationId, resendKey, fromEmail, fromName, appUrl);
    }

    if (RETIRED_SWAP_EMAIL_TYPES.includes(emailType)) {
      console.log(`[send-swap-email] ${emailType} — push and in-app only since F-59, nothing sent`);
      return jsonResponse({ sent: 0, suppressed: 0, failed: 0, skipped: "push_only" });
    }

    return jsonResponse({ error: "Payload inválido." }, 400);
  } catch (err) {
    console.error("[send-swap-email] unhandled error:", err);
    return jsonResponse({ error: String(err) }, 500);
  }
});

// ── F-15: invitation e-mail ───────────────────────────────────────────────────

// deno-lint-ignore no-explicit-any
async function handleInvitationEmail(
  supabase: any,
  invitationId: number,
  resendKey: string,
  fromEmail: string,
  fromName: string,
  appUrl: string
): Promise<Response> {
  const { data, error } = await supabase
    .from("family_invitations")
    .select("id, family_id, email, token, created_at, expires_at, accepted_at, revoked_at, profile_id, member_type, families(name), profiles!family_invitations_invited_by_fkey(full_name, language_effective), roles(role, label_pt)")
    .eq("id", invitationId)
    .single();

  if (error || !data) {
    console.error(`[send-swap-email] invitation not found — ${error?.message ?? "no data"}`);
    return jsonResponse({ error: "Invitation not found." }, 404);
  }

  // Only send for live invitations (a stale/revoked id must not leak a link).
  if (data.accepted_at || data.revoked_at || new Date(data.expires_at) <= new Date()) {
    console.error(`[send-swap-email] invitation ${invitationId} is not pending — refusing to send`);
    return jsonResponse({ error: "Invitation is not pending." }, 409);
  }

  // U-13: an invitee has NO profile yet, so there is no language of their own to
  // read. The INVITER's language is the best signal available — a family
  // operating the app in English is most likely inviting someone who reads it —
  // and it is at worst as wrong as the previous hardcoded Portuguese. Once they
  // sign up, everything else follows their own choice.
  const lang        = resolveLang(data.profiles?.language_effective);
  const t           = swapText(lang);
  const inviterName = data.profiles?.full_name ?? t.fallbackOtherCaregiver;
  const familyName  = data.families?.name ?? t.fallbackFamily;
  // F-27: the PT-BR label lives in the roles table (label_pt); U-13 adds the
  // English one from the RoleCatalog mirror in _shared/i18n.ts, keyed by the
  // canonical name. A CUSTOM role (F-41) is not in the mirror and passes through
  // exactly as the family typed it — user data is never translated.
  const roleName    = roleLabel(lang, data.roles?.role, data.roles?.label_pt)
    || (data.roles?.role ?? "");
  const inviteLink  = `${appUrl}/register?invite=${data.token}`;
  const expiresBr   = formatDateIn(lang, String(data.expires_at).slice(0, 10));
  // T-82: the days THIS invitation was issued for — `invitation.valid_days` at
  // creation, read back from the row so a later console edit never makes an old
  // invitation's e-mail promise a different window.
  const validDays   = Math.max(1, Math.round(
    (new Date(data.expires_at).getTime() - new Date(data.created_at).getTime()) / 86_400_000));

  // S-13: don't log the invitee's e-mail (PII) — the family is enough context.
  console.log(`[send-swap-email] invitation dispatch — family=${familyName}`);

  const delivered = await sendEmail(resendKey, fromEmail, fromName, {
    to: data.email,
    subject: t.subjInvitation(inviterName),
    // F-56: an invitation FOR a pending member states what stays (the admin's
    // name/role, as family data) and what is purged (the e-mail).
    // F-50: a viewer is told, before signing up, that it will only follow the plan.
    html: templateInvitation(lang, inviterName, familyName, roleName, inviteLink, expiresBr, validDays, data.profile_id != null, data.member_type === "viewer"),
  });

  // F-101: the row remembers that the message LEFT — the Família card reads
  // this column to say "E-mail não enviado" instead of "Convite enviado" after
  // a failed send (a Resend refusal throws in sendEmail and never reaches this
  // line). A suppressed test recipient counts as sent: nothing failed. Best-
  // effort: a stamp that fails is logged, never a failed send.
  const { error: stampError } = await supabase
    .from("family_invitations")
    .update({ email_sent_at: new Date().toISOString() })
    .eq("id", invitationId);
  if (stampError) {
    console.error(`[send-swap-email] email_sent_at not stamped — ${stampError.message}`);
  }

  console.log(`[send-swap-email] invitation ${delivered ? "sent" : "suppressed (test recipient)"}`);
  return jsonResponse({
    sent: delivered ? 1 : 0,
    suppressed: delivered ? 0 : 1,
    failed: 0,
  });
}

interface EmailMessage {
  to: string;
  subject: string;
  html: string;
}

/** Returns true when the message was handed to Resend, false when suppressed (T-49). */
async function sendEmail(
  apiKey: string,
  fromEmail: string,
  fromName: string,
  email: EmailMessage
): Promise<boolean> {
  // T-49: the test suite's recipients never reach Resend — see _shared/mail.ts.
  // S-13: log the subject, never the address.
  if (isTestRecipient(email.to)) {
    console.log(`[send-swap-email] test recipient — Resend call suppressed (subject="${email.subject}")`);
    return false;
  }

  const res = await fetch(RESEND_API_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from:    `${fromName} <${fromEmail}>`,
      to:      [email.to],
      subject: email.subject,
      html:    email.html,
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Resend error ${res.status}: ${body}`);
  }
  return true;
}

// -- HTML template -----------------------------------------------------------
// The markup is written ONCE and shared by both languages; only the text comes
// from _shared/i18n.ts, keyed by the RECIPIENT's language.
//
// U-26: and no style lives here at all. Every element comes from
// _shared/email_layout.ts, the one layer all the senders share, so a dark-mode
// fix cannot land in one sender and miss the others.

function baseTemplate(lang: Lang, title: string, body: string): string {
  const c = common(lang);
  return emailDocument({ htmlLang: c.htmlLang, title, body, footer: [c.automaticNote] });
}

function templateInvitation(lang: Lang, inviterName: string, familyName: string, roleName: string, inviteLink: string, expiresBr: string, validDays: number, forPlaceholder = false, asViewer = false): string {
  const t = swapText(lang);
  const roleLine = roleName ? paragraph(t.invitationRole(roleName)) : "";
  const privacy = forPlaceholder ? t.invitationPrivacyPlaceholder : t.invitationPrivacy;
  return baseTemplate(lang, t.invitationTitle,
    `${heading(t.invitationHeading)}
     ${paragraph((asViewer ? t.invitationBodyViewer : t.invitationBody)(inviterName, familyName))}
     ${roleLine}
     ${paragraph(t.invitationExpiry(validDays, expiresBr), "last")}
     ${button(inviteLink, t.invitationButton)}
     ${small(`${t.invitationLinkFallback}<br/>${rawUrl(inviteLink)}`)}
     ${small(t.invitationSafety(inviterName), true)}
     ${small(`${privacy} ${smallLink("https://entrelares.app/privacidade", t.invitationPrivacyLink)}.`, true)}`
  );
}
