// F-68 — Help & contact: a message from the app to the team's inbox.
//
// WHY. Family 19 (19/09/2026) tried to record a past-day fact through a channel
// that could not carry it, cancelled twice and gave up — with nobody to ask. The
// app had no help screen, no mailto, no form. This function is the door; the
// "Ajuda e contato" screen (`/help`, public AND signed in) is its only caller.
//
// WHAT IT DOES, in order:
//   1. validates the payload (category, message 10–2000, reply e-mail);
//   2. resolves WHO is asking: a valid user session → the account's own e-mail,
//      profile and family, read here (the client never chooses the reply address
//      of a signed-in person); no session → the e-mail the person typed;
//   3. records the request through `record_support_request`, which also applies
//      the limit in the same transaction (numbers below, owner 21/09/2026);
//   4. e-mails the team (`suporte@`, or `privacidade@` for the privacy category —
//      the LGPD channel the policy already names), Reply-To = the person;
//   5. e-mails the person a confirmation built from the shared layout (U-26).
//
// The team e-mail is the product: if it fails the row is marked `undelivered`
// (it stops counting against the limit) and the caller gets `send_failed`, so
// the screen offers the mailto instead of claiming success. The confirmation is
// best-effort: the request already reached the team.
//
// S-16: runs with verify_jwt = false. The signed-out caller has no session —
// only the publishable key, which authenticates nobody — so the gate never
// protected anything here. What protects the Resend allowance (L-20: 100/day per
// ACCOUNT, shared with production sign-ups and another product) is the limit.
// These e-mails do NOT consume a family's F-38 quota: support is not a family
// feature, and a family that ran out of e-mails must still be able to ask why.
//
// T-49: a reply address on `@resend.dev` is the test suite. Both sends are
// suppressed for it — the TEAM's inbox too, since the recipient there is real —
// and the IP is not recorded, so the shared CI runner IP never locks the gate out
// of its own runs. The e-mail limit still applies to it, which is what the gate
// asserts end to end.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { secretKey } from "../_shared/keys.ts";
import { isTestRecipient } from "../_shared/mail.ts";
import { emailDocument, heading, list, paragraph, small } from "../_shared/email_layout.ts";
import {
  common,
  type Lang,
  resolveLang,
  support,
  SUPPORT_CATEGORY_LABEL,
  type SupportCategory,
} from "../_shared/i18n.ts";

// ── The numbers. Since T-83 the limits and the message maximum are operator
// parameters (`support.*` in app_settings); these constants are their FALLBACKS
// and equal the migration seeds, and `SupportRules` (core) mirrors them —
// `support_constants_mirror_test` reads this file and the migration. The message
// minimum and the e-mail maximum stay constants.
const MESSAGE_MIN_CHARS = 10;
const MESSAGE_MAX_CHARS = 2000;
const EMAIL_MAX_CHARS = 254;
/** Signed out: per typed e-mail AND per caller IP. */
const ANON_HOURLY_LIMIT = 3;
const ANON_DAILY_LIMIT = 10;
/** Signed in: per profile. */
const MEMBER_HOURLY_LIMIT = 5;
const MEMBER_DAILY_LIMIT = 20;

const CATEGORIES: SupportCategory[] = ["question", "problem", "suggestion", "privacy", "other"];

/** The only diagnostics keys that survive; anything else the client sends is dropped. */
const DIAGNOSTIC_KEYS = ["appVersion", "channel", "platform", "language", "route"] as const;
const DIAGNOSTIC_MAX_CHARS = 120;

const RESEND_API_URL = "https://api.resend.com/emails";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

interface SupportPayload {
  category?: string;
  message?: string;
  replyEmail?: string;
  language?: string;
  diagnostics?: Record<string, unknown> | null;
}

/** Deliberately loose — the reply is a person's address, and GoTrue is not the judge here. */
function isPlausibleEmail(value: string): boolean {
  return value.length <= EMAIL_MAX_CHARS && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

/**
 * The allowed keys, as short strings. The route loses any query or fragment
 * again here: the client's analytics sanitizer already cut them, but an invite
 * token or a recovery hash is exactly what must never reach an inbox.
 */
function cleanDiagnostics(raw: unknown): Record<string, string> | null {
  if (!raw || typeof raw !== "object") return null;
  const out: Record<string, string> = {};
  for (const key of DIAGNOSTIC_KEYS) {
    const value = (raw as Record<string, unknown>)[key];
    if (typeof value !== "string") continue;
    let v = value.replace(/[\r\n\t]+/g, " ").trim();
    if (key === "route") v = v.split(/[?#]/)[0];
    if (v) out[key] = v.slice(0, DIAGNOSTIC_MAX_CHARS);
  }
  return Object.keys(out).length ? out : null;
}

/** HMAC-SHA256 of the caller's IP under the project's secret key — never the IP itself. */
async function ipHashOf(req: Request, key: string): Promise<string | null> {
  const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim();
  if (!ip) return null;
  const cryptoKey = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(`support-ip:${ip}`));
  return Array.from(new Uint8Array(mac)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
}

/** One line, no control characters — a subject is a header. */
function subjectSnippet(message: string): string {
  const flat = message.replace(/\s+/g, " ").trim();
  return flat.length > 60 ? `${flat.slice(0, 60)}…` : flat;
}

function teamHtml(opts: {
  id: number;
  category: SupportCategory;
  replyEmail: string;
  signedIn: boolean;
  profileId: number | null;
  familyId: number | null;
  message: string;
  diagnostics: Record<string, string> | null;
}): string {
  const who = [
    `Responder para: <strong>${escapeHtml(opts.replyEmail)}</strong>`,
    opts.signedIn
      ? `Conta: perfil ${opts.profileId ?? "—"} · família ${opts.familyId ?? "—"}`
      : "Enviado sem login",
  ];
  const diag = opts.diagnostics
    ? list(Object.entries(opts.diagnostics).map(([k, v]) => `${escapeHtml(k)}: ${escapeHtml(v)}`))
    : paragraph("Sem informações técnicas (a pessoa não permitiu).");
  return emailDocument({
    htmlLang: "pt-BR",
    title: `Pedido #${opts.id}`,
    body: `${heading(`${SUPPORT_CATEGORY_LABEL[opts.category]} · #${opts.id}`)}
      ${list(who)}
      ${paragraph(escapeHtml(opts.message).replace(/\n/g, "<br/>"))}
      ${small("Informações técnicas", true)}
      ${diag}`,
    footer: ["Responder a este e-mail responde à pessoa (Reply-To)."],
  });
}

function confirmationHtml(lang: Lang, category: SupportCategory, id: number): string {
  const t = support(lang);
  return emailDocument({
    htmlLang: common(lang).htmlLang,
    title: t.confirmationHeading,
    body: `${heading(t.confirmationHeading)}
      ${paragraph(t.confirmationIntro(t.categoryLabel[category], id))}
      ${paragraph(t.confirmationPromise)}
      ${paragraph(t.confirmationReply)}
      ${small(t.confirmationIgnore, true)}`,
    footer: [common(lang).signature],
  });
}

async function sendEmail(
  apiKey: string,
  from: string,
  msg: { to: string; subject: string; html: string; replyTo?: string },
): Promise<void> {
  const res = await fetch(RESEND_API_URL, {
    method: "POST",
    headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from,
      to: [msg.to],
      subject: msg.subject,
      html: msg.html,
      ...(msg.replyTo ? { reply_to: msg.replyTo } : {}),
    }),
  });
  if (!res.ok) throw new Error(`Resend error ${res.status}: ${await res.text()}`);
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = secretKey();
    const admin = createClient(supabaseUrl, serviceKey);

    let payload: SupportPayload;
    try {
      payload = await req.json();
    } catch {
      return jsonResponse({ error: "invalid_payload" }, 400);
    }

    const category = CATEGORIES.find((c) => c === payload.category);
    if (!category) return jsonResponse({ error: "invalid_category" }, 400);

    // T-83: the operator's numbers, each with its constant as the fallback.
    const setting = async (key: string, fallback: number): Promise<number> => {
      const { data } = await admin.rpc("setting_int", { p_key: key, p_default: fallback });
      return Number.isInteger(data) ? (data as number) : fallback;
    };
    const [messageMaxChars, anonHourly, anonDaily, memberHourly, memberDaily] = await Promise.all([
      setting("support.message_max_chars", MESSAGE_MAX_CHARS),
      setting("support.anon_hourly", ANON_HOURLY_LIMIT),
      setting("support.anon_daily", ANON_DAILY_LIMIT),
      setting("support.member_hourly", MEMBER_HOURLY_LIMIT),
      setting("support.member_daily", MEMBER_DAILY_LIMIT),
    ]);

    const message = (payload.message ?? "").trim();
    if (message.length < MESSAGE_MIN_CHARS || message.length > messageMaxChars) {
      return jsonResponse({ error: "invalid_message" }, 400);
    }

    // ── Who is asking. A bearer that is not a live user session (the anon key,
    // an expired token) is simply the signed-out path.
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
    let userEmail: string | null = null;
    let profile: { id: number; family_id: number | null; language: string | null } | null = null;
    if (jwt) {
      const { data } = await admin.auth.getUser(jwt);
      if (data?.user?.email) {
        userEmail = data.user.email;
        const { data: row } = await admin
          .from("profiles")
          .select("id, family_id, language")
          .eq("user_id", data.user.id)
          .maybeSingle();
        profile = row ?? null;
      }
    }
    const signedIn = userEmail !== null;

    const replyEmail = (signedIn ? userEmail! : (payload.replyEmail ?? "")).trim();
    if (!isPlausibleEmail(replyEmail)) return jsonResponse({ error: "invalid_email" }, 400);

    const lang = resolveLang(profile?.language ?? payload.language);
    const diagnostics = cleanDiagnostics(payload.diagnostics);
    const isTest = isTestRecipient(replyEmail);

    // A signed-in person with no profile yet (F-57 onboarding) is limited by
    // e-mail like a signed-out one — there is no profile to key on.
    const byProfile = profile !== null;
    const { data: recorded, error: recordError } = await admin.rpc("record_support_request", {
      p_profile_id: profile?.id ?? null,
      p_family_id: profile?.family_id ?? null,
      p_category: category,
      p_reply_email: replyEmail,
      p_message: message,
      p_diagnostics: diagnostics,
      p_language: lang,
      p_ip_hash: byProfile || isTest ? null : await ipHashOf(req, serviceKey),
      p_hour_limit: byProfile ? memberHourly : anonHourly,
      p_day_limit: byProfile ? memberDaily : anonDaily,
    });
    if (recordError) {
      console.error(`[send-support-request] record failed: ${recordError.message}`);
      return jsonResponse({ error: "failed" }, 500);
    }
    const row = (Array.isArray(recorded) ? recorded[0] : recorded) as
      { status: string; request_id: number | null } | null;
    if (row?.status === "rate_limited") return jsonResponse({ error: "rate_limited" }, 429);
    const id = row?.request_id;
    if (!id) return jsonResponse({ error: "failed" }, 500);

    if (isTest) {
      console.log(`[send-support-request] #${id} test recipient — Resend calls suppressed`);
      return jsonResponse({ ok: true, requestId: id });
    }

    const resendKey = Deno.env.get("RESEND_API_KEY");
    if (!resendKey) throw new Error("RESEND_API_KEY secret is not configured.");
    const fromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? "noreply@entrelares.app";
    const fromName = Deno.env.get("RESEND_FROM_NAME") ?? "Entrelares";
    const from = `${fromName} <${fromEmail}>`;
    const envName = Deno.env.get("APP_ENVIRONMENT") ?? "Production";
    const envPrefix = envName.toLowerCase() === "production" ? "" : "[Dev] ";
    const inbox = category === "privacy"
      ? (Deno.env.get("PRIVACY_INBOX") ?? "privacidade@entrelares.app")
      : (Deno.env.get("SUPPORT_INBOX") ?? "suporte@entrelares.app");

    // ── 4. The team. S-13: log the id and the category, never the address.
    try {
      await sendEmail(resendKey, from, {
        to: inbox,
        replyTo: replyEmail,
        subject: `${envPrefix}[Suporte][${SUPPORT_CATEGORY_LABEL[category]}] ${subjectSnippet(message)} · #${id}`,
        html: teamHtml({
          id,
          category,
          replyEmail,
          signedIn,
          profileId: profile?.id ?? null,
          familyId: profile?.family_id ?? null,
          message,
          diagnostics,
        }),
      });
    } catch (err) {
      console.error(`[send-support-request] #${id} team e-mail failed: ${err instanceof Error ? err.message : err}`);
      await admin.from("support_requests").update({ status: "undelivered" }).eq("id", id);
      return jsonResponse({ error: "send_failed" }, 502);
    }

    // ── 5. The person. Best-effort — the team already has it.
    try {
      await sendEmail(resendKey, from, {
        to: replyEmail,
        subject: `${envPrefix}${support(lang).subjConfirmation(id)}`,
        html: confirmationHtml(lang, category, id),
      });
    } catch (err) {
      console.error(`[send-support-request] #${id} confirmation failed: ${err instanceof Error ? err.message : err}`);
    }

    console.log(`[send-support-request] #${id} delivered (category=${category}, signedIn=${signedIn})`);
    return jsonResponse({ ok: true, requestId: id });
  } catch (err) {
    console.error(`[send-support-request] unexpected: ${err instanceof Error ? err.message : err}`);
    return jsonResponse({ error: "failed" }, 500);
  }
});
