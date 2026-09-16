import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
import { secretKey } from "../_shared/keys.ts";
import { isTestRecipient } from "../_shared/mail.ts";
import { button, code as codeBlock, emailDocument, heading, paragraph } from "../_shared/email_layout.ts";
import { authMail, authMailKind, common, langFromRedirect, type Lang, resolveLang } from "../_shared/i18n.ts";

// U-13 (pre-production round) — the GoTrue auth e-mails, in the reader's language.
//
// THE PROBLEM THIS SOLVES. GoTrue owns three of the most important messages the
// product sends — confirm your sign-up, reset your password, confirm an e-mail
// change — and its templates are configured **one per project**. One body, one
// language, every reader. So an English tester who asked for a password reset
// received a Portuguese e-mail while every screen around them was in English.
// U-13 recorded that as out of scope precisely because there was no way to
// branch inside GoTrue.
//
// The way is Supabase's **Send Email Hook**: GoTrue stops sending and hands us
// the message instead — the user, the action type and the token — and we render
// and send it ourselves, through the same Resend account and the same visual
// shell as every other e-mail here.
//
// ── The thing to keep in mind when touching this file ────────────────────────
// Once the hook is enabled, GoTrue does NOT send these e-mails as a fallback.
// If this function fails, nobody can confirm a sign-up and nobody can recover a
// password. Three consequences, all deliberate:
//
//   1. An `email_action_type` we do not recognise is NOT an error — it renders
//      the generic `unknown` copy. A new GoTrue action type must never be the
//      reason someone cannot get into their account.
//   2. Every failure returns a non-2xx. Returning 200 on a failed send would be
//      worse than failing: the app would tell the person "check your e-mail"
//      for a message that is never coming, and they would wait instead of
//      retrying.
//   3. Secrets are read INSIDE the handler. Reading them at module load would
//      make a missing secret a boot crash, and CI redeploys every function on
//      every push — including onto a project where the hook secret does not
//      exist yet.
//
// ── Authorization (S-16) ─────────────────────────────────────────────────────
// `verify_jwt = false`, because GoTrue does not call us with a JWT: it signs
// the request with the Standard Webhooks scheme using the hook's own secret.
// That signature IS the authorization, and it is checked before anything else
// is read — same shape as `billing-webhook`'s token check.

const RESEND_API_URL = "https://api.resend.com/emails";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, webhook-id, webhook-timestamp, webhook-signature",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

/** The payload GoTrue posts. Only the fields we use are typed. */
interface HookPayload {
  user: {
    id: string;
    email: string;
    new_email?: string | null;
    // deno-lint-ignore no-explicit-any
    user_metadata?: Record<string, any> | null;
  };
  email_data: {
    token: string;
    token_hash: string;
    token_new?: string;
    token_hash_new?: string;
    redirect_to: string;
    email_action_type: string;
    site_url: string;
  };
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const hookSecret = Deno.env.get("SEND_EMAIL_HOOK_SECRET");
    if (!hookSecret) {
      // Fail CLOSED, and answer 401 rather than 500.
      //
      // The first cut returned 500 here, reasoning that a missing secret is our
      // misconfiguration and not the caller's fault. The `dev` gate rejected it,
      // correctly: `EdgeFunctionAuthTests` reads a 500 as "the function RAN and
      // failed later — i.e. the authorization check is missing", which is the
      // exact regression that class exists to catch, and a status that cannot
      // tell a refusal apart from a crash is worth nothing as a gate.
      //
      // 401 is also the honest answer on its own terms: the caller presented no
      // verifiable credential, which is true whether or not we hold the secret,
      // and it tells an anonymous prober nothing about our configuration. The
      // operator's signal is this log line — which is where runbook 5.7 sends
      // them — not the status code.
      //
      // This is the state the function sits in until the hook is enabled: live,
      // dormant, and refusing everyone.
      console.error(
        "[send-auth-email] SEND_EMAIL_HOOK_SECRET is not configured — refusing every call. " +
        "If the Send Email Hook is enabled, auth e-mails are NOT being delivered: see runbook 5.7 step 3.");
      return jsonResponse({ error: "Não autorizado." }, 401);
    }

    const raw = await req.text();

    let payload: HookPayload;
    try {
      // The secret arrives from the Dashboard as `v1,whsec_<base64>`; the
      // library wants the base64 alone.
      const webhook = new Webhook(hookSecret.replace("v1,whsec_", ""));
      payload = webhook.verify(raw, Object.fromEntries(req.headers)) as HookPayload;
    } catch (err) {
      console.warn(`[send-auth-email] refused — bad signature (${err instanceof Error ? err.message : err})`);
      return jsonResponse({ error: "Não autorizado." }, 401);
    }

    const resendKey = Deno.env.get("RESEND_API_KEY");
    if (!resendKey) throw new Error("RESEND_API_KEY secret is not configured.");
    const fromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? "noreply@entrelares.app";
    const fromName = Deno.env.get("RESEND_FROM_NAME") ?? "Entrelares";
    // Optional, per project: the subject tag that tells a QA e-mail apart from a
    // real one (the DEV templates carried "(DEV)"). Absent in production.
    const envPrefix = Deno.env.get("MAIL_ENV_PREFIX") ?? "";

    const { user, email_data } = payload;
    const kind = authMailKind(email_data.email_action_type);
    const lang = await recipientLanguage(user, email_data.redirect_to);
    const t = authMail(lang, kind);

    // `email_change_new` is the copy addressed to the NEW address, and GoTrue
    // hands it the second token pair. Getting this backwards sends a token the
    // recipient's address cannot redeem — a dead link, with no error anywhere.
    const isNewAddress = kind === "email_change_new";
    const to = isNewAddress ? (user.new_email || user.email) : user.email;
    const tokenHash = isNewAddress ? (email_data.token_hash_new || email_data.token_hash) : email_data.token_hash;
    const code = isNewAddress ? (email_data.token_new || email_data.token) : email_data.token;

    const html = kind === "reauthentication"
      ? codeHtml(lang, t.heading, t.intro, code, t.ignore)
      : linkHtml(lang, t.heading, t.intro, t.action, confirmationUrl(email_data, tokenHash), t.ignore);

    const sent = await sendEmail(resendKey, fromEmail, fromName, {
      to,
      subject: `${envPrefix}${t.subject}`,
      html,
    });

    // S-13: never log the address. The action type is enough to trace a report.
    console.log(`[send-auth-email] ${email_data.email_action_type} → ${lang}${sent ? "" : " (suppressed)"}`);
    return jsonResponse({ sent, suppressed: !sent });
  } catch (err) {
    console.error(`[send-auth-email] unexpected — ${err instanceof Error ? err.message : err}`);
    // Non-2xx on purpose: see note 2 at the top of this file.
    return jsonResponse({ error: "Falha ao enviar o e-mail." }, 500);
  }
});

/**
 * The language this person reads the app in, best signal first.
 *
 *   1. `profiles.language` — an explicit CHOICE. Someone who picked a language
 *      meant it, and nothing here may override that.
 *   2. the `lang` on `redirect_to` — the screen they were looking at when they
 *      asked. A DETECTION, but a fresh one.
 *   3. `profiles.language_detected` — the screen they were on LAST time. Also a
 *      detection, and a staler one.
 *   4. `user_metadata.language` — what the sign-up form was displayed in. The
 *      one case no column can cover: the profile row is created by
 *      `handle_new_user` from the very insert that triggers the confirmation
 *      e-mail, so it has no detected language yet.
 *   5. pt-BR.
 *
 * <b>Steps 2 and 3 were the wrong way round at first</b>, and QA found it: this
 * read the generated `language_effective`, which is `language ?? language_detected`,
 * and put the whole thing above the screen — on the reasoning that an explicit
 * choice outranks a passing screen. True for `language`; false for
 * `language_detected`, which is not a choice at all. A member who had signed in
 * once in English, signed out, switched the login screen to Portuguese and asked
 * for a reset kept receiving English, because a MONTHS-OLD detection was beating
 * the one they were looking at. Both are detections; the fresher one wins.
 *
 * `language_effective` stays right for `send-swap-email` / `send-account-email`:
 * those are triggered by someone ELSE, so there is no "screen the reader was on"
 * to consult and choice-then-detection is the whole story.
 *
 * Never throws: a lookup failure costs the reader's preferred language, and a
 * Portuguese e-mail is a far better outcome than no e-mail at all.
 */
async function recipientLanguage(
  user: HookPayload["user"],
  redirectTo: string | null | undefined,
): Promise<Lang> {
  const fromMetadata = typeof user.user_metadata?.language === "string"
    ? user.user_metadata.language as string
    : null;

  // The two columns are read SEPARATELY, not through the generated
  // `language_effective`: they rank on opposite sides of the screen signal.
  let chosen: string | null = null;
  let detected: string | null = null;
  try {
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, secretKey());
    const { data } = await supabase
      .from("profiles")
      .select("language, language_detected")
      .eq("user_id", user.id)
      .maybeSingle();

    chosen = data?.language ?? null;
    detected = data?.language_detected ?? null;
  } catch (err) {
    console.warn(`[send-auth-email] language lookup failed — ${err instanceof Error ? err.message : err}`);
  }

  if (chosen) return resolveLang(chosen);

  const fromScreen = langFromRedirect(redirectTo);
  if (fromScreen) return fromScreen;

  if (detected) return resolveLang(detected);

  return resolveLang(fromMetadata);
}

/**
 * The link GoTrue would have put in `{{ .ConfirmationURL }}`.
 *
 * It has to be assembled here because taking over the send means taking over
 * the template variable too. `redirect_to` is passed through untouched: it is
 * where the browser lands after the token is verified, GoTrue itself validates
 * it against the project's allow-list, and rewriting it here would reintroduce
 * exactly the bug the reset-redirect fix removed.
 */
function confirmationUrl(data: HookPayload["email_data"], tokenHash: string): string {
  const base = `${Deno.env.get("SUPABASE_URL")}/auth/v1/verify`;
  const params = new URLSearchParams({
    token: tokenHash,
    type: data.email_action_type,
    redirect_to: data.redirect_to,
  });
  return `${base}?${params.toString()}`;
}

// -- HTML bodies --------------------------------------------------------------
// Same shell as send-swap-email / send-account-email: an auth e-mail arriving in
// a different visual language from the rest is one more reason for a person who
// is already locked out to wonder whether it is a phishing attempt.
//
// U-26: that sentence was a promise, not a fact — this file wrote its own bare
// <div> and a #212529 button, the exact one that vanished in a dark client. The
// shell is now the shared layer's, literally the same one.

const shell = (lang: Lang, title: string, body: string) =>
  emailDocument({
    htmlLang: common(lang).htmlLang,
    title,
    body: `${heading(title)}${body}`,
    footer: [common(lang).automaticNote, common(lang).signature],
  });

function linkHtml(
  lang: Lang, title: string, intro: string, action: string, url: string, ignore: string,
): string {
  return shell(lang, title, `
      ${paragraph(intro, "last")}
      ${button(escapeHtml(url), action)}
      ${ignore ? paragraph(ignore, "after") : ""}`);
}

// Reauthentication is a CODE, not a link — the person is already on the screen
// that asks for it, so a button would send them somewhere they do not need to go.
function codeHtml(lang: Lang, title: string, intro: string, code: string, ignore: string): string {
  return shell(lang, title, `
      ${paragraph(intro)}
      ${codeBlock(escapeHtml(code))}
      ${ignore ? paragraph(ignore) : ""}`);
}

/** Returns true when the message was handed to Resend, false when suppressed (T-49). */
async function sendEmail(
  apiKey: string,
  fromEmail: string,
  fromName: string,
  msg: { to: string; subject: string; html: string },
): Promise<boolean> {
  // T-49: the suite signs real accounts up on every run, so without this the
  // auth e-mails would go straight back onto the Resend allowance the item was
  // written to protect — and this path is the one whose exhaustion locks a real
  // user out. See _shared/mail.ts.
  if (isTestRecipient(msg.to)) {
    console.log(`[send-auth-email] test recipient — Resend call suppressed (subject="${msg.subject}")`);
    return false;
  }

  const res = await fetch(RESEND_API_URL, {
    method: "POST",
    headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: `${fromName} <${fromEmail}>`,
      to: [msg.to],
      subject: msg.subject,
      html: msg.html,
    }),
  });

  if (!res.ok) {
    // Surfaced to the caller as a 500 — the person must be told to try again,
    // not told to check a mailbox nothing was sent to.
    throw new Error(`Resend rejected the message (${res.status}): ${await res.text()}`);
  }
  return true;
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
}
