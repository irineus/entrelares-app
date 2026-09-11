import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { secretKey } from "../_shared/keys.ts";
import { hasValidUserSession, isSecretKeyCaller } from "../_shared/auth.ts";
import { isTestRecipient } from "../_shared/mail.ts";
import { account, common, formatDateIn, type Lang, resolveLang } from "../_shared/i18n.ts";

// S-11 — account-lifecycle e-mails (Resend). Separate from send-swap-email
// (which is swap-centric) so account/family-deletion notices have a clean home;
// PR2 adds family-deletion e-mail types here.
//
// Types (all identify the subject by profileId, except family_deletion_completed):
//   · member_left     — a member requested to leave: confirmation (with grace/
//     cancel/irreversibility) to the LEAVER + heads-up to every other active
//     member. Guarded: only fires when the profile is really leaving.
//   · member_joined   — a new member joined: heads-up to every OTHER active
//     member (the subject just signed up, so not e-mailed).
//   · member_returned — a member cancelled their exit: heads-up to every OTHER
//     active member.
//   · family_deletion_requested — subject = the requesting admin: confirmation
//     to them + consent notice (deadline, right to refuse) to every other
//     active member. Deadline read from the family's pending request.
//   · family_deletion_refused   — subject = the refuser: everyone (subject
//     included) learns the request ended and the family continues.
//   · family_deletion_withdrawn — subject = the requester: everyone learns the
//     request was withdrawn.
//   · family_deletion_reminder  — subject = the requester (cron, D-3): everyone
//     gets the final heads-up with the purge date.
//   · family_deletion_completed — cron only, AFTER the purge: the profiles are
//     gone, so the payload carries explicit `recipients` + `familyName`.
//   · elevation_code — S-21, `elevate` only: the one-time code that lets a
//     session with no password pass the S-10 sudo gate. The odd one out in
//     every way, and each difference is deliberate: it is keyed by `userId`
//     (the subject may have no profile yet — a deferred OAuth sign-up), it
//     e-mails ONLY the subject, it refuses a user-session caller, and it reads
//     the destination address from `auth.users` instead of trusting the
//     payload. A caller that could name both the recipient and the code would
//     be a way to mail a valid elevation code to an address of its choosing.
//   · premium_grace_ending — S-15/B-3, cron: subject = a family ADMIN, warned
//     that the Premium grace period is about to expire. Unlike every type above
//     it e-mails ONLY the subject, never the other members: the checkout and the
//     subscription panel are admin-only, so an alarm to someone who cannot act on
//     it is noise. The deadline arrives in the payload (`graceEndsAt`) because
//     the caller already computed it from billing.grace_days.

const RESEND_API_URL = "https://api.resend.com/emails";

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

type EmailType =
  | "member_left" | "member_joined" | "member_returned"
  | "family_deletion_requested" | "family_deletion_refused"
  | "family_deletion_withdrawn" | "family_deletion_reminder"
  | "family_deletion_completed"
  | "premium_grace_ending"
  | "elevation_code";

interface Payload {
  emailType: EmailType;
  profileId?: number;
  environmentPrefix?: string;
  // family_deletion_completed only — the family is already purged.
  recipients?: string[];
  familyName?: string;
  // premium_grace_ending only — ISO date the grace period runs out.
  graceEndsAt?: string;
  // elevation_code only — the subject and the code itself. `elevate` mints the
  // code, stores only its digest, and hands the plaintext here; this is the one
  // place it exists outside that function's memory.
  userId?: string;
  code?: string;
  expiresInMinutes?: number;
}

interface Profile {
  id: number;
  full_name: string;
  email: string;
  // U-13: the RECIPIENT's language. These messages are triggered by one person
  // and read by another, so the sender's language is never the right answer.
  // `language_effective` and not `language`: the first is the member's explicit
  // CHOICE and is NULL for anyone who never used the picker — which, until the
  // pre-production round, was almost everyone, since a signed-in phone had no
  // picker to use. The generated column falls back to the language their session
  // actually renders in, so a reader is never told in Portuguese what their
  // screen has been saying in English.
  language_effective?: string | null;
  family_id: number;
  left_at: string | null;
  deletion_scheduled_for: string | null;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const resendKey = Deno.env.get("RESEND_API_KEY");
    if (!resendKey) throw new Error("RESEND_API_KEY secret is not configured.");
    const fromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? "noreply@entrelares.app";
    const fromName  = Deno.env.get("RESEND_FROM_NAME")  ?? "Entrelares";

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey  = secretKey();
    const supabase    = createClient(supabaseUrl, serviceKey);

    // S-16: verify_jwt is off (see _shared/auth.ts), so the relay authorizes
    // itself. Callers: `purge-deleted` and `register-invitee` (secret key on
    // `apikey`) and the app's own deletion/lifecycle flows (user session).
    if (!isSecretKeyCaller(req, serviceKey) && !(await hasValidUserSession(req, supabase))) {
      console.warn("[send-account-email] refused — neither secret key nor a valid session");
      return jsonResponse({ error: "Não autorizado." }, 401);
    }

    const { emailType, profileId, environmentPrefix = "", recipients, familyName, graceEndsAt,
            userId, code, expiresInMinutes }: Payload = await req.json();

    const validTypes: EmailType[] = [
      "member_left", "member_joined", "member_returned",
      "family_deletion_requested", "family_deletion_refused",
      "family_deletion_withdrawn", "family_deletion_reminder",
      "family_deletion_completed", "premium_grace_ending", "elevation_code",
    ];
    if (!validTypes.includes(emailType)) {
      return jsonResponse({ error: "Payload inválido." }, 400);
    }

    // S-21 — the sudo gate's e-mail code. `elevate` is the only legitimate
    // caller, and it holds the secret key; a user session reaching here would
    // mean someone found a way to ask us to mail a code they also chose.
    if (emailType === "elevation_code") {
      if (!isSecretKeyCaller(req, serviceKey)) {
        console.warn("[send-account-email] elevation_code refused — not a secret-key caller");
        return jsonResponse({ error: "Não autorizado." }, 401);
      }
      if (!userId || !code || !expiresInMinutes) {
        return jsonResponse({ error: "Payload inválido." }, 400);
      }

      // The address is READ, never accepted: see the note at the top of this file.
      const { data: authUser, error: authError } = await supabase.auth.admin.getUserById(userId);
      const to = authUser?.user?.email;
      if (authError || !to) {
        console.error("[send-account-email] elevation_code — no address for that user");
        return jsonResponse({ error: "Usuário não encontrado." }, 404);
      }

      // U-13: the subject may legitimately have NO profile — a deferred OAuth
      // sign-up (F-57) that has not onboarded yet still owns an account it is
      // entitled to delete. `maybeSingle` and the PT-BR fallback are the honest
      // answer there, not an error.
      const { data: langRow } = await supabase
        .from("profiles")
        .select("language_effective")
        .eq("user_id", userId)
        .maybeSingle();
      const lang = resolveLang((langRow?.language_effective as string | null) ?? null);

      const sent = await sendEmail(resendKey, fromEmail, fromName, {
        to,
        subject: `${environmentPrefix}${account(lang).subjElevationCode}`,
        html: elevationCodeHtml(lang, code, String(expiresInMinutes)),
      });
      // S-13: never log the address, and never the code.
      console.log(`[send-account-email] elevation_code → ${lang}${sent ? "" : " (suppressed)"}`);
      return jsonResponse({ sent: sent ? 1 : 0, suppressed: sent ? 0 : 1, failed: 0 });
    }

    // The purge already removed the profiles — recipients come in the payload.
    if (emailType === "family_deletion_completed") {
      if (!recipients?.length || !familyName) {
        return jsonResponse({ error: "Payload inválido." }, 400);
      }
      // U-13: the profiles are already gone (the purge ran before this call), so
      // there is no language to look up — the payload carries e-mail addresses
      // and nothing else. PT-BR is the documented fallback, exactly as for a
      // profile that never chose. Sending SOMETHING true beats sending nothing.
      const farewellLang = resolveLang(null);
      const farewell = recipients.map((to) => ({
        to,
        subject: `${environmentPrefix}${account(farewellLang).subjFdCompleted(familyName)}`,
        html: fdCompletedHtml(farewellLang, familyName),
      }));
      const farewellResults = await Promise.allSettled(
        farewell.map((m) => sendEmail(resendKey, fromEmail, fromName, m)),
      );
      const farewellFailed = farewellResults.filter((r) => r.status === "rejected").length;
      if (farewellFailed > 0) {
        console.error(`[send-account-email] ${farewellFailed}/${farewell.length} farewell e-mail(s) failed`);
      }
      // T-49: suppressed test recipients are successes, not failures.
      const farewellSuppressed = farewellResults.filter(
        (r) => r.status === "fulfilled" && r.value === false).length;
      return jsonResponse({
        sent: farewell.length - farewellFailed - farewellSuppressed,
        suppressed: farewellSuppressed,
        failed: farewellFailed,
      });
    }

    if (!profileId) {
      return jsonResponse({ error: "Payload inválido." }, 400);
    }

    const { data: subjectRow } = await supabase
      .from("profiles")
      .select("id, full_name, email, family_id, left_at, deletion_scheduled_for, language_effective")
      .eq("id", profileId)
      .maybeSingle();

    if (!subjectRow) {
      return jsonResponse({ error: "Perfil não encontrado." }, 404);
    }
    const s = subjectRow as Profile;

    // member_left only fires for a profile that is genuinely leaving.
    if (emailType === "member_left" && !s.left_at) {
      return jsonResponse({ error: "Perfil não está em processo de saída." }, 409);
    }

    const { data: others } = await supabase
      .from("profiles")
      .select("id, full_name, email, family_id, left_at, deletion_scheduled_for, language_effective")
      .eq("family_id", s.family_id)
      .is("left_at", null)
      .not("user_id", "is", null)
      .neq("id", s.id);

    const messages: { to: string; subject: string; html: string }[] = [];

    // U-13: language per RECIPIENT. Several of these types fan out to the whole
    // family in one call, and two members may read in different languages —
    // choosing one for the batch would hand at least one of them a text they
    // cannot read.
    const langOf = (p: Profile): Lang => resolveLang(p.language_effective);

    if (emailType === "premium_grace_ending") {
      // The deadline is the whole point of this e-mail, and the "in 30 days"
      // fallback belongs to the account-deletion grace — printing it here would
      // state a period that is not this one. Refuse instead of misinform.
      if (!graceEndsAt) {
        return jsonResponse({ error: "Payload inválido: graceEndsAt ausente." }, 400);
      }
      // S-15/B-3: only the admin who can actually resolve the payment.
      const lang = langOf(s);
      messages.push({
        to: s.email,
        subject: `${environmentPrefix}${account(lang).subjGraceEnding}`,
        html: graceEndingHtml(lang, s.full_name, deadlineFor(lang, graceEndsAt)),
      });
    } else if (emailType === "member_left") {
      // The leaver gets the full-consequence confirmation...
      const selfLang = langOf(s);
      messages.push({
        to: s.email,
        subject: `${environmentPrefix}${account(selfLang).subjLeftSelf}`,
        html: selfHtml(selfLang, s.full_name, deadlineFor(selfLang, s.deletion_scheduled_for)),
      });
      // ...and every other active member a heads-up to check the calendar.
      for (const o of (others ?? []) as Profile[]) {
        const lang = langOf(o);
        messages.push({
          to: o.email,
          subject: `${environmentPrefix}${account(lang).subjLeftOthers(s.full_name)}`,
          html: othersHtml(lang, o.full_name, s.full_name),
        });
      }
    } else if (emailType === "member_joined" || emailType === "member_returned") {
      // Notify the OTHER active members only.
      const joined = emailType === "member_joined";
      for (const o of (others ?? []) as Profile[]) {
        const lang = langOf(o);
        const t = account(lang);
        messages.push({
          to: o.email,
          subject: `${environmentPrefix}${joined ? t.subjJoined(s.full_name) : t.subjReturned(s.full_name)}`,
          html: joined ? joinedHtml(lang, o.full_name, s.full_name) : returnedHtml(lang, o.full_name, s.full_name),
        });
      }
    } else if (emailType === "family_deletion_requested" || emailType === "family_deletion_reminder") {
      // Both carry the purge deadline, read from the family's pending request.
      const { data: request } = await supabase
        .from("family_deletion_requests")
        .select("scheduled_for")
        .eq("family_id", s.family_id)
        .eq("status", "pending")
        .maybeSingle();
      if (!request) {
        // Resolved between the trigger and this dispatch — nothing to send.
        return jsonResponse({ sent: 0, failed: 0 });
      }
      // U-24: per RECIPIENT — this fan-out mails the requester AND every other
      // member, and they may read in different languages.
      const deadlineIn = (lang: Lang) => deadlineFor(lang, request.scheduled_for as string);

      if (emailType === "family_deletion_requested") {
        const requesterLang = langOf(s);
        messages.push({
          to: s.email,
          subject: `${environmentPrefix}${account(requesterLang).subjFdRequesterSelf}`,
          html: fdRequesterHtml(requesterLang, s.full_name, deadlineIn(requesterLang)),
        });
        for (const o of (others ?? []) as Profile[]) {
          const lang = langOf(o);
          messages.push({
            to: o.email,
            subject: `${environmentPrefix}${account(lang).subjFdRequesterOthers(deadlineIn(lang))}`,
            html: fdOthersHtml(lang, o.full_name, s.full_name, deadlineIn(lang)),
          });
        }
      } else {
        for (const m of [s, ...((others ?? []) as Profile[])]) {
          const lang = langOf(m);
          messages.push({
            to: m.email,
            subject: `${environmentPrefix}${account(lang).subjFdReminder(deadlineIn(lang))}`,
            html: fdReminderHtml(lang, m.full_name, deadlineIn(lang)),
          });
        }
      }
    } else {
      // family_deletion_refused / family_deletion_withdrawn: everyone
      // (subject included) learns the request ended and the family continues.
      const refused = emailType === "family_deletion_refused";
      for (const m of [s, ...((others ?? []) as Profile[])]) {
        const lang = langOf(m);
        const t = account(lang);
        messages.push({
          to: m.email,
          subject: `${environmentPrefix}${refused ? t.subjFdRefused : t.subjFdWithdrawn}`,
          html: refused
            ? fdRefusedHtml(lang, m.full_name, s.full_name)
            : fdWithdrawnHtml(lang, m.full_name, s.full_name),
        });
      }
    }

    const results = await Promise.allSettled(
      messages.map((m) => sendEmail(resendKey, fromEmail, fromName, m)),
    );
    const failed = results.filter((r) => r.status === "rejected").length;
    if (failed > 0) console.error(`[send-account-email] ${failed}/${messages.length} e-mail(s) failed`);

    // T-49: suppressed test recipients are successes, not failures.
    const suppressed = results.filter((r) => r.status === "fulfilled" && r.value === false).length;

    return jsonResponse({ sent: messages.length - failed - suppressed, suppressed, failed });
  } catch (err) {
    console.error(`[send-account-email] unexpected — ${err instanceof Error ? err.message : err}`);
    return jsonResponse({ error: "Falha ao enviar e-mails." }, 500);
  }
});

// -- HTML bodies --------------------------------------------------------------
// The markup is written ONCE and shared by both languages; only the text comes
// from _shared/i18n.ts, keyed by the RECIPIENT's language (U-13).
//
// NOTE ON escapeHtml: names are USER DATA and stay escaped. The catalogue text
// is ours, reviewed in a PR, and carries its own <strong> — the same split the
// app's LocalizationService.Rich makes, for the same reason.

const shell = (body: string, lang: Lang) => `
    <div style="font-family: system-ui, sans-serif; color: #212529; max-width: 480px;">
      ${body}
      <p style="color: #868e96; font-size: 13px;">${common(lang).signature}</p>
    </div>`;

const list = (...items: string[]) =>
  `<ul style="line-height: 1.6;">${items.map((i) => `<li>${i}</li>`).join("")}</ul>`;

// S-21. No greeting by name: the code mail is keyed by user, and the subject
// may have no profile to take a name from. No button either — a confirmation
// code must be TYPED into the app the reader already has open, and a link here
// would be one more thing a phishing copy could imitate.
function elevationCodeHtml(lang: Lang, code: string, minutes: string): string {
  const t = account(lang);
  return shell(`
      <h2>${t.elevationHeading}</h2>
      <p>${t.elevationIntro}</p>
      <p style="font-size: 28px; font-weight: 700; letter-spacing: 4px;">${escapeHtml(code)}</p>
      <p>${t.elevationExpiry(escapeHtml(minutes))}</p>
      <p>${t.elevationIgnore}</p>`, lang);
}

function selfHtml(lang: Lang, name: string, graceDate: string): string {
  const t = account(lang);
  return shell(`
      <h2>${t.selfHeading}</h2>
      <p>${common(lang).greeting(escapeHtml(name))}</p>
      <p>${t.selfIntro}</p>
      ${list(t.selfBullet1(graceDate), t.selfBullet2, t.selfBullet3, t.selfBullet4)}
      <p>${t.selfClosing}</p>`, lang);
}

// S-15/B-3 -- the warning the Terms promise before the downgrade ("Avisaremos por
// e-mail antes da indisponibilidade"). Deliberately non-alarmist: nothing is lost
// and nothing is deleted, which is the single most reassuring fact for a parent
// whose custody calendar lives here. Says what happens, by when, and how to fix.
function graceEndingHtml(lang: Lang, name: string, graceDate: string): string {
  const t = account(lang);
  return shell(`
      <h2>${t.graceHeading}</h2>
      <p>${common(lang).greeting(escapeHtml(name))}</p>
      <p>${t.graceIntro(graceDate)}</p>
      <p>${t.graceBody}</p>
      <p>${t.graceHowTo}</p>`, lang);
}

function othersHtml(lang: Lang, recipientName: string, leaverName: string): string {
  const t = account(lang);
  return shell(`
      <h2>${t.othersHeading}</h2>
      <p>${common(lang).greeting(escapeHtml(recipientName))}</p>
      <p>${t.othersBody(escapeHtml(leaverName))}</p>
      <p>${t.othersHistory}</p>`, lang);
}

function joinedHtml(lang: Lang, recipientName: string, joinerName: string): string {
  const t = account(lang);
  return shell(`
      <h2>${t.joinedHeading}</h2>
      <p>${common(lang).greeting(escapeHtml(recipientName))}</p>
      <p>${t.joinedBody(escapeHtml(joinerName))}</p>
      <p>${t.joinedClosing}</p>`, lang);
}

function returnedHtml(lang: Lang, recipientName: string, returnerName: string): string {
  const t = account(lang);
  return shell(`
      <h2>${t.returnedHeading}</h2>
      <p>${common(lang).greeting(escapeHtml(recipientName))}</p>
      <p>${t.returnedBody(escapeHtml(returnerName))}</p>`, lang);
}

function fdRequesterHtml(lang: Lang, name: string, deadline: string): string {
  const t = account(lang);
  return shell(`
      <h2>${t.fdRequesterHeading}</h2>
      <p>${common(lang).greeting(escapeHtml(name))}</p>
      <p>${t.fdRequesterIntro(deadline)}</p>
      ${list(t.fdRequesterBullet1, t.fdRequesterBullet2, t.fdRequesterBullet3, t.fdRequesterBullet4)}
      <p>${t.fdRequesterClosing}</p>`, lang);
}

function fdOthersHtml(lang: Lang, recipientName: string, requesterName: string, deadline: string): string {
  const t = account(lang);
  return shell(`
      <h2>${t.fdOthersHeading}</h2>
      <p>${common(lang).greeting(escapeHtml(recipientName))}</p>
      <p>${t.fdOthersIntro(escapeHtml(requesterName))}</p>
      ${list(t.fdOthersBullet1(deadline), t.fdOthersBullet2, t.fdOthersBullet3, t.fdOthersBullet4)}`, lang);
}

function fdRefusedHtml(lang: Lang, recipientName: string, refuserName: string): string {
  const t = account(lang);
  return shell(`
      <h2>${t.fdRefusedHeading}</h2>
      <p>${common(lang).greeting(escapeHtml(recipientName))}</p>
      <p>${t.fdRefusedBody(escapeHtml(refuserName))}</p>`, lang);
}

function fdWithdrawnHtml(lang: Lang, recipientName: string, requesterName: string): string {
  const t = account(lang);
  return shell(`
      <h2>${t.fdWithdrawnHeading}</h2>
      <p>${common(lang).greeting(escapeHtml(recipientName))}</p>
      <p>${t.fdWithdrawnBody(escapeHtml(requesterName))}</p>`, lang);
}

function fdReminderHtml(lang: Lang, recipientName: string, deadline: string): string {
  const t = account(lang);
  return shell(`
      <h2>${t.fdReminderHeading}</h2>
      <p>${common(lang).greeting(escapeHtml(recipientName))}</p>
      <p>${t.fdReminderIntro(deadline)}</p>
      ${list(t.fdReminderBullet1, t.fdReminderBullet2)}`, lang);
}

// The farewell goes to people whose profile NO LONGER EXISTS (the purge already
// ran), so there is no language to look up. The payload carries the recipients
// and nothing else -- PT-BR is the documented fallback, same as a NULL column.
function fdCompletedHtml(lang: Lang, familyName: string): string {
  const t = account(lang);
  return shell(`
      <h2>${t.fdCompletedHeading}</h2>
      <p>${t.fdCompletedBody(escapeHtml(familyName))}</p>
      <p>${t.fdCompletedClosing}</p>`, lang);
}

/** Returns true when the message was handed to Resend, false when suppressed (T-49). */
async function sendEmail(
  apiKey: string,
  fromEmail: string,
  fromName: string,
  msg: { to: string; subject: string; html: string },
): Promise<boolean> {
  // T-49: the test suite's recipients never reach Resend — see _shared/mail.ts.
  // S-13: log the subject, never the address.
  if (isTestRecipient(msg.to)) {
    console.log(`[send-account-email] test recipient — Resend call suppressed (subject="${msg.subject}")`);
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
  if (!res.ok) throw new Error(`Resend error ${res.status}: ${await res.text()}`);
  return true;
}

// U-24 — the two halves this used to do in one step, now separated because they
// answer different questions: the timezone shift decides WHICH day it is, and
// the format decides how that day is WRITTEN. Only the second one depends on
// who is reading, so only the second one can be resolved per recipient.
//
// The fallback moved to the catalogue for the same reason: it read "30 dias" in
// every language, so an English recipient was told the deadline in Portuguese.

/** The date part of a timestamptz, in America/Sao_Paulo, as ISO `yyyy-MM-dd`. */
function isoDayInSaoPaulo(iso: string): string {
  const d = new Date(iso);
  const sp = new Date(d.toLocaleString("en-US", { timeZone: "America/Sao_Paulo" }));
  const dd = String(sp.getDate()).padStart(2, "0");
  const mm = String(sp.getMonth() + 1).padStart(2, "0");
  return `${sp.getFullYear()}-${mm}-${dd}`;
}

/** A deadline as the RECIPIENT reads it, or the catalogue's "in 30 days" when
 *  the row carries no date. */
function deadlineFor(lang: Lang, iso: string | null): string {
  return iso ? formatDateIn(lang, isoDayInSaoPaulo(iso)) : account(lang).fallbackThirtyDays;
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
}
