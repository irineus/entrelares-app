import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { secretKey } from "../_shared/keys.ts";
import { hasValidUserSession, isSecretKeyCaller } from "../_shared/auth.ts";
import { isTestRecipient } from "../_shared/mail.ts";
import { banner, button, emailDocument, heading, link, linkRow, paragraph, rawUrl, small, smallLink } from "../_shared/email_layout.ts";
import { common, formatDateIn, formatTimeIn, type Lang, resolveLang, roleLabel, swap as swapText, type SwapStrings } from "../_shared/i18n.ts";

const RESEND_API_URL = "https://api.resend.com/emails";

// CORS headers required for every response from a browser-invoked Edge Function.
// The Supabase C# SDK (and the JS client) always send X-Client-Info; omitting it
// from the preflight Allow list causes the browser to block the actual POST.
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

interface EmailPayload {
  swapRequestId?: number;   // required for every swap-workflow type
  invitationId?: number;    // required for emailType "invitation" (F-15)
  emailType:
    | "swap_requested"
    | "approved"
    | "rejected"
    | "cancelled"
    | "reverted"
    | "revert_requested"
    | "revert_approved"
    | "revert_rejected"
    | "revert_cancelled"
    | "reminder"          // F-24: 24h-before-auto-approval nudge to the approver
    | "auto_approved"     // F-24: resolved automatically after 48h (to both parties)
    | "invitation";       // F-15: co-parent invite with the register link
}

// F-20: priority tag computed at SEND time — never stored, never sent by the
// client. Same formula as the app's SwapRequestService.ComputePriorityTag,
// evaluated in America/Sao_Paulo (this runtime is UTC).
type PriorityTag = "urgent" | "overdue" | null;

function computePriorityTag(scheduleDate: string, handoffTime: string | null): PriorityTag {
  const nowSp = new Date(new Date().toLocaleString("en-US", { timeZone: "America/Sao_Paulo" }));
  const [y, mo, d] = scheduleDate.split("-").map(Number);
  const [h = 0, mi = 0] = (handoffTime ?? "00:00").split(":").map(Number);
  const handoff = new Date(y, mo - 1, d, h, mi, 0);
  if (nowSp >= handoff) return "overdue";
  return handoff.getTime() - nowSp.getTime() < 24 * 3600 * 1000 ? "urgent" : null;
}

// F-60: the instant the request stops waiting, as `auto_approve_expired()`
// computes it — the DAY being decided (`schedule_date + handoff`, midnight when
// there is none) plus 48 h, in America/Sao_Paulo. The arithmetic runs in UTC on
// a WALL CLOCK so the runtime's own zone cannot shift it; Brazil has no DST to
// make the +48 h anything but 48 h. Never a window measured from the request:
// that is the sentence this item exists to delete.
function autoApprovalDeadline(
  scheduleDate: string,
  handoffTime: string | null,
): { date: string; time: string } {
  const [y, mo, d] = scheduleDate.split("-").map(Number);
  const [hRaw = 0, miRaw = 0] = (handoffTime ?? "00:00").split(":").map(Number);
  // An unparseable handoff is midnight — the same fallback the RPC's
  // COALESCE and the client's `parseTimeOfDay` make. Inventing an hour here
  // would put a wrong deadline in the subject line of the one e-mail whose
  // entire job is the deadline.
  const h = Number.isFinite(hRaw) ? hRaw : 0;
  const mi = Number.isFinite(miRaw) ? miRaw : 0;
  const at = new Date(Date.UTC(y!, mo! - 1, d!, h, mi));
  at.setUTCHours(at.getUTCHours() + 48);
  const iso = at.toISOString();
  return { date: iso.slice(0, 10), time: iso.slice(11, 16) };
}

interface SwapRequest {
  id: number;
  schedule_date: string;
  requesting_profile_id: number;
  target_profile_id: number;
  previous_actual_parent_id: number | null;
  proposed_actual_parent_id: number;
  proposed_handoff_time: string | null;
  rejection_reason: string | null;
  request_message: string | null;   // F-44: requester's message (creation)
  approval_note: string | null;     // F-44: approver's note (approval)
  status: string;
}

interface Profile {
  id: number;
  full_name: string;
  email: string;
  // U-13: the RECIPIENT's language. An e-mail is triggered by one person and
  // read by another, so the sender's language is never the right answer.
  //
  // `language_effective` and not `language`: the first is the member's explicit
  // CHOICE and is NULL for anyone who never used the picker — which, until the
  // pre-production round, was almost everyone, since a signed-in phone had no
  // picker to use. The generated column falls back to the language their session
  // actually renders in, so a reader is never told in Portuguese what their
  // screen has been saying in English. NULL still means "never seen since the
  // column shipped" and still resolves to PT-BR.
  language_effective?: string | null;
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
    // e-mail relay. Callers: `auto-approve-expired` (secret key on `apikey`) and
    // the app, which dispatches workflow e-mails with the user's session.
    if (!isSecretKeyCaller(req, serviceKey) && !(await hasValidUserSession(req, supabase))) {
      console.warn("[send-swap-email] refused — neither secret key nor a valid session");
      return jsonResponse({ error: "Não autorizado." }, 401);
    }

    const payload: EmailPayload = await req.json();
    const { swapRequestId, invitationId, emailType } = payload;

    console.log(`[send-swap-email] received emailType=${emailType} swapRequestId=${swapRequestId} invitationId=${invitationId}`);

    // F-15 — invitation e-mail: independent of the swap workflow, handled here.
    if (emailType === "invitation") {
      if (!invitationId) {
        return jsonResponse({ error: "invitationId is required for emailType invitation." }, 400);
      }
      return await handleInvitationEmail(supabase, invitationId, resendKey, fromEmail, fromName, appUrl);
    }

    if (!swapRequestId || !emailType) {
      return jsonResponse({ error: "swapRequestId and emailType are required." }, 400);
    }

    // Fetch swap request
    const { data: swapData, error: swapError } = await supabase
      .from("swap_requests")
      .select("*")
      .eq("id", swapRequestId)
      .single();

    if (swapError || !swapData) {
      console.error(`[send-swap-email] swap request not found — ${swapError?.message ?? "no data"}`);
      return jsonResponse({ error: "Swap request not found." }, 404);
    }

    const swap = swapData as SwapRequest;
    console.log(`[send-swap-email] swap found — date=${swap.schedule_date} status=${swap.status}`);

    // F-38: monthly e-mail cap (free tier). Capture the quota status: over the cap
    // we skip the real e-mail; on a warn_* status we still send it AND (after) an
    // admin heads-up. In-app is unaffected — it is created by the app / the DB.
    const swapFamilyId = (swapData as { family_id?: number }).family_id;
    const swapQuotaStatus = await emailQuotaStatus(supabase, swapFamilyId);
    if (swapQuotaStatus === "denied") {
      console.log(`[send-swap-email] monthly e-mail cap reached — skipping swap e-mail (in-app unaffected).`);
      return jsonResponse({ skipped: "email_cap" }, 200);
    }

    // Fetch both profiles
    const profileIds = [
      swap.requesting_profile_id,
      swap.target_profile_id,
    ].filter(Boolean);

    const { data: profilesData, error: profilesError } = await supabase
      .from("profiles")
      .select("id, full_name, email, language_effective")
      .in("id", profileIds);

    if (profilesError) {
      console.error(`[send-swap-email] profiles query failed — ${profilesError.message}`);
    }

    const profiles: Profile[] = profilesData ?? [];
    const requester = profiles.find((p) => p.id === swap.requesting_profile_id);
    const target    = profiles.find((p) => p.id === swap.target_profile_id);

    // S-13: never log PII (names/e-mails) to the function logs — log by id only.
    console.log(`[send-swap-email] requesterId=${requester?.id ?? "NOT FOUND"} targetId=${target?.id ?? "NOT FOUND"}`);

    // U-24: the date is NO LONGER formatted here. It used to be computed once,
    // at this line, and handed to every recipient — but `auto_approved` mails
    // both parties in one call and they may read in different languages, so one
    // of them received the other's format. `buildEmails` now formats it inside
    // each branch, where the recipient's language is already known.
    const priorityTag = computePriorityTag(swap.schedule_date, swap.proposed_handoff_time);
    console.log(`[send-swap-email] priorityTag=${priorityTag ?? "none"} (computed at send time)`);
    const emails = buildEmails(emailType, swap, requester, target, appUrl, priorityTag);

    console.log(`[send-swap-email] built ${emails.length} email(s) to send`);

    const results = await Promise.allSettled(
      emails.map((e) => sendEmail(resendKey, fromEmail, fromName, e))
    );

    const failures = results.filter((r) => r.status === "rejected");
    if (failures.length > 0) {
      console.error(`[send-swap-email] ${failures.length} email(s) failed:`, failures);
    }

    // T-49: suppressed test recipients are successes, not failures — counted
    // apart so the log tells "nothing was sent" from "sending was skipped".
    const suppressed = results.filter((r) => r.status === "fulfilled" && r.value === false).length;
    const sent = emails.length - failures.length - suppressed;

    console.log(`[send-swap-email] done — sent=${sent} suppressed=${suppressed} failed=${failures.length}`);

    // F-38: after the real e-mail, send the admin heads-up when this send crossed
    // the 80% / último milestone (the DB already posted the in-app notifications).
    if ((swapQuotaStatus === "warn_80" || swapQuotaStatus === "warn_last") && swapFamilyId) {
      await sendAdminQuotaWarning(supabase, swapFamilyId, swapQuotaStatus, resendKey, fromEmail, fromName, appUrl);
    }

    return jsonResponse({ sent, suppressed, failed: failures.length, quota: swapQuotaStatus });
  } catch (err) {
    console.error("[send-swap-email] unhandled error:", err);
    return jsonResponse({ error: String(err) }, 500);
  }
});

// ── F-38: monthly transactional-e-mail quota ──────────────────────────────────
// Consume one unit of the family's monthly quota and return the resulting status:
//   'allowed'   — under the cap; send the real e-mail, no warning.
//   'warn_80'   — send the real e-mail AND an 80% heads-up e-mail to the admins.
//   'warn_last' — send the real e-mail AND the "último e-mail" heads-up (this
//                 warning e-mail is the family's last of the month).
//   'denied'    — over the cap; skip the real e-mail (the in-app upsell was posted
//                 by the DB). Premium is always 'allowed' and never counted.
// The DB posts every in-app notification; only the admin WARNING e-mails go out
// here. Fail-open: any RPC error returns 'allowed' so a counter fault never blocks.
// deno-lint-ignore no-explicit-any
async function emailQuotaStatus(supabase: any, familyId: number | null | undefined): Promise<string> {
  if (!familyId) return "allowed";
  const { data, error } = await supabase.rpc("consume_email_quota", { p_family_id: familyId });
  if (error) {
    console.error(`[send-swap-email] consume_email_quota failed (fail-open) — ${error.message}`);
    return "allowed";
  }
  return (data as string) ?? "allowed";
}

// F-38: the 80%/último heads-up e-mail goes to the family ADMINS only (they own
// the upgrade). Best-effort — a warning that fails to send must never break the
// real transactional dispatch.
// deno-lint-ignore no-explicit-any
async function sendAdminQuotaWarning(
  supabase: any, familyId: number, stage: "warn_80" | "warn_last",
  resendKey: string, fromEmail: string, fromName: string, appUrl: string,
): Promise<void> {
  const { data: admins, error } = await supabase
    .from("profiles")
    .select("email, language_effective")
    .eq("family_id", familyId)
    .eq("is_admin", true)
    .is("left_at", null);
  if (error || !admins?.length) {
    if (error) console.error(`[send-swap-email] admin lookup for quota warning failed — ${error.message}`);
    return;
  }
  // T-82: the threshold the DB just crossed is `email_quota.warn_percent`; the
  // e-mail says the same number the in-app notification stored.
  const { data: pct } = await supabase.rpc("setting_int", {
    p_key: "email_quota.warn_percent", p_default: 80,
  });
  const percent = Number.isInteger(pct) ? (pct as number) : 80;
  // U-13: one admin may read in English and another in Portuguese, so the
  // subject and body are built PER ADMIN rather than once for the batch.
  // deno-lint-ignore no-explicit-any
  await Promise.allSettled(admins.map((a: any) => {
    if (!a.email) return Promise.resolve();
    const lang = resolveLang(a.language_effective);
    const t = swapText(lang);
    return sendEmail(resendKey, fromEmail, fromName, {
      to: a.email,
      subject: stage === "warn_last" ? t.subjCapLast : t.subjCap80(percent),
      html: stage === "warn_last" ? templateEmailCapLast(lang, appUrl) : templateEmailCap80(lang, appUrl, percent),
    });
  }));
  console.log(`[send-swap-email] quota warning (${stage}) e-mailed to ${admins.length} admin(s) of family=${familyId}`);
}

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

  // F-38: monthly e-mail cap (free tier) — invitations count too.
  const invQuotaStatus = await emailQuotaStatus(supabase, data.family_id);
  if (invQuotaStatus === "denied") {
    console.log(`[send-swap-email] monthly e-mail cap reached — skipping invitation e-mail.`);
    return jsonResponse({ skipped: "email_cap" }, 200);
  }

  const delivered = await sendEmail(resendKey, fromEmail, fromName, {
    to: data.email,
    subject: t.subjInvitation(inviterName),
    // F-56: an invitation FOR a pending member states what stays (the admin's
    // name/role, as family data) and what is purged (the e-mail).
    // F-50: a viewer is told, before signing up, that it will only follow the plan.
    html: templateInvitation(lang, inviterName, familyName, roleName, inviteLink, expiresBr, validDays, data.profile_id != null, data.member_type === "viewer"),
  });

  // F-38: admin heads-up when this invitation crossed the 80% / último milestone.
  if (invQuotaStatus === "warn_80" || invQuotaStatus === "warn_last") {
    await sendAdminQuotaWarning(supabase, data.family_id, invQuotaStatus, resendKey, fromEmail, fromName, appUrl);
  }

  console.log(`[send-swap-email] invitation ${delivered ? "sent" : "suppressed (test recipient)"}`);
  return jsonResponse({
    sent: delivered ? 1 : 0,
    suppressed: delivered ? 0 : 1,
    failed: 0,
    quota: invQuotaStatus,
  });
}

// ── Email builders ────────────────────────────────────────────────────────────

interface EmailMessage {
  to: string;
  subject: string;
  html: string;
}

function buildEmails(
  emailType: string,
  swap: SwapRequest,
  requester: Profile | undefined,
  target: Profile | undefined,
  appUrl: string,
  priorityTag: PriorityTag = null
): EmailMessage[] {
  const emails: EmailMessage[] = [];

  // U-24: the DATE is localized per recipient for the same reason the words are.
  // A wrong word reads as a missing translation; `05/08` read as May 8th is a
  // wrong DAY, and an e-mail cannot be re-read in context the way a screen can.
  const dateIn    = (lang: Lang) => formatDateIn(lang, swap.schedule_date);
  const handoffIn = (lang: Lang) => formatTimeIn(lang, swap.proposed_handoff_time);

  // U-13: the language is resolved PER RECIPIENT, not once for the message.
  // `auto_approved` sends to both parties in the same call, and they may read
  // in different languages — picking one language for the pair would hand at
  // least one of them a text they cannot read.
  const langOf = (p: Profile | undefined): Lang => resolveLang(p?.language_effective);
  const tagOf = (t: SwapStrings) =>
    priorityTag === "overdue" ? t.tagOverdue : priorityTag === "urgent" ? t.tagUrgent : "";

  // Scenario split (mirrors SwapRequestService): when the requester proposed
  // THEMSELVES on the target's day, "você fica responsável" would invert the
  // request's meaning — the texts must state who actually takes the day.
  const targetIsProposed = swap.proposed_actual_parent_id === swap.target_profile_id;

  switch (emailType) {
    case "swap_requested":
      if (target?.email) {
        const lang = langOf(target), t = swapText(lang);
        emails.push({
          to: target.email,
          subject: `${tagOf(t)}${t.subjRequested(dateIn(lang))}`,
          html: templateRequested(lang, requester?.full_name ?? t.fallbackOtherCaregiver, dateIn(lang), handoffIn(lang), appUrl, priorityTag, targetIsProposed, swap.request_message),
        });
      }
      break;

    case "approved":
      if (requester?.email) {
        const lang = langOf(requester), t = swapText(lang);
        emails.push({
          to: requester.email,
          subject: `${tagOf(t)}${t.subjApproved(dateIn(lang))}`,
          html: templateApprovedForRequester(lang, target?.full_name ?? t.fallbackOtherCaregiver, dateIn(lang), handoffIn(lang), appUrl, targetIsProposed, swap.approval_note),
        });
      }
      break;

    case "rejected":
      if (requester?.email) {
        const lang = langOf(requester), t = swapText(lang);
        emails.push({
          to: requester.email,
          subject: `${tagOf(t)}${t.subjRejected(dateIn(lang))}`,
          html: templateRejected(lang, target?.full_name ?? t.fallbackOtherCaregiver, dateIn(lang), swap.rejection_reason, appUrl),
        });
      }
      break;

    case "cancelled":
      if (target?.email) {
        const lang = langOf(target), t = swapText(lang);
        emails.push({
          to: target.email,
          subject: `${tagOf(t)}${t.subjCancelled(dateIn(lang))}`,
          html: templateCancelled(lang, requester?.full_name ?? t.fallbackRequester, dateIn(lang), appUrl),
        });
      }
      break;

    case "reverted":
      if (target?.email) {
        const lang = langOf(target), t = swapText(lang);
        emails.push({
          to: target.email,
          subject: `${tagOf(t)}${t.subjReverted(dateIn(lang))}`,
          html: templateReverted(lang, dateIn(lang), appUrl),
        });
      }
      break;

    case "revert_requested":
      if (target?.email) {
        const lang = langOf(target), t = swapText(lang);
        emails.push({
          to: target.email,
          subject: `${tagOf(t)}${t.subjRevertRequested(dateIn(lang))}`,
          html: templateRevertRequested(lang, requester?.full_name ?? t.fallbackOtherCaregiver, dateIn(lang), handoffIn(lang), appUrl, priorityTag, swap.request_message),
        });
      }
      break;

    case "revert_approved":
      if (requester?.email) {
        const lang = langOf(requester), t = swapText(lang);
        emails.push({
          to: requester.email,
          subject: `${tagOf(t)}${t.subjRevertApproved(dateIn(lang))}`,
          html: templateRevertApproved(lang, target?.full_name ?? t.fallbackOtherCaregiver, dateIn(lang), appUrl, swap.approval_note),
        });
      }
      break;

    case "revert_rejected":
      if (requester?.email) {
        const lang = langOf(requester), t = swapText(lang);
        emails.push({
          to: requester.email,
          subject: `${tagOf(t)}${t.subjRevertRejected(dateIn(lang))}`,
          html: templateRevertRejected(lang, target?.full_name ?? t.fallbackOtherCaregiver, dateIn(lang), swap.rejection_reason, appUrl),
        });
      }
      break;

    case "revert_cancelled":
      if (target?.email) {
        const lang = langOf(target), t = swapText(lang);
        emails.push({
          to: target.email,
          subject: `${tagOf(t)}${t.subjRevertCancelled(dateIn(lang))}`,
          html: templateRevertCancelled(lang, requester?.full_name ?? t.fallbackRequester, dateIn(lang), appUrl),
        });
      }
      break;

    // F-24 — nudge the approver 24 h after the day expired, 24 h before the
    // auto-approval. F-60: the copy states that instant instead of a window.
    case "reminder": {
      const isRevertReq = swap.status === "revert_pending";
      if (target?.email) {
        const lang = langOf(target), t = swapText(lang);
        // F-60: subject and body name the deadline, in the RECIPIENT's format.
        const deadline = autoApprovalDeadline(swap.schedule_date, swap.proposed_handoff_time);
        const deadlineDate = formatDateIn(lang, deadline.date);
        const deadlineTime = formatTimeIn(lang, deadline.time) ?? deadline.time;
        emails.push({
          to: target.email,
          subject: t.subjReminder(dateIn(lang), isRevertReq, deadlineDate, deadlineTime),
          html: templateReminder(lang, dateIn(lang), handoffIn(lang), isRevertReq, appUrl, swap.request_message, deadlineDate, deadlineTime),
        });
      }
      break;
    }

    // F-24 — request resolved automatically after 48h; notify both parties.
    case "auto_approved": {
      const isRevert = swap.status === "revert_approved";
      if (requester?.email) {
        const lang = langOf(requester), t = swapText(lang);
        emails.push({
          to: requester.email,
          subject: t.subjAutoApproved(dateIn(lang), isRevert),
          html: templateAutoApproved(lang, dateIn(lang), isRevert, false, appUrl),
        });
      }
      if (target?.email) {
        const lang = langOf(target), t = swapText(lang);
        emails.push({
          to: target.email,
          subject: t.subjAutoApproved(dateIn(lang), isRevert),
          html: templateAutoApproved(lang, dateIn(lang), isRevert, true, appUrl),
        });
      }
      break;
    }
  }

  return emails;
}

// ── F-38: quota heads-up templates (admins only) ──────────────────────────────

function templateEmailCap80(lang: Lang, appUrl: string, percent: number): string {
  const t = swapText(lang);
  return baseTemplate(lang, t.cap80Title,
    `${heading(t.cap80Heading)}
     ${paragraph(t.cap80Body(percent))}
     ${paragraph(t.cap80Note)}
     ${paragraph(t.cap80Upsell, "last")}
     ${button(`${appUrl}/family`, t.capButton)}`
  );
}

function templateEmailCapLast(lang: Lang, appUrl: string): string {
  const t = swapText(lang);
  return baseTemplate(lang, t.capLastTitle,
    `${heading(t.capLastHeading)}
     ${paragraph(t.capLastBody)}
     ${paragraph(t.capLastNote)}
     ${paragraph(t.capLastUpsell, "last")}
     ${button(`${appUrl}/family`, t.capButton)}`
  );
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

// U-24: the local `formatDate`/`formatTime` that used to live here moved to
// `_shared/i18n.ts` as `formatDateIn`/`formatTimeIn`, which take the recipient's
// language. They were hardcoded to `dd/MM/yyyy` and 24h — a Brazilian date
// inside an otherwise English e-mail.

// -- HTML templates ----------------------------------------------------------
// The markup is written ONCE and shared by both languages; only the text comes
// from _shared/i18n.ts, keyed by the RECIPIENT's language. Duplicating these
// shells per language would guarantee that a style fix lands in only one of them.
//
// U-26: and no style lives here at all. Every element comes from
// _shared/email_layout.ts, the one layer all three senders share, so a dark-mode
// fix cannot land in one sender and miss the other two.

function baseTemplate(lang: Lang, title: string, body: string): string {
  const c = common(lang);
  return emailDocument({ htmlLang: c.htmlLang, title, body, footer: [c.automaticNote] });
}

function priorityBanner(lang: Lang, tag: PriorityTag): string {
  const t = swapText(lang);
  if (tag === "overdue") return banner(t.bannerOverdue, "danger");
  if (tag === "urgent") return banner(t.bannerUrgent, "warning");
  return "";
}

// F-44: one paragraph for the requester message / approval note, same visual
// weight as the other detail lines. Empty text renders nothing. Since the F-44
// QA terminology round every workflow text carries the same "Message" label.
function detailLine(lang: Lang, text: string | null): string {
  return text
    ? paragraph(`<strong>${common(lang).messageLabel}:</strong> ${text}`)
    : "";
}

function handoffLine(lang: Lang, handoffTime: string | null): string {
  return handoffTime
    ? paragraph(swapText(lang).handoffLine(handoffTime))
    : "";
}

function reasonLine(lang: Lang, reason: string | null): string {
  return reason
    ? paragraph(`<strong>${common(lang).messageLabel}:</strong> ${reason}`, "after")
    : "";
}

function templateRequested(lang: Lang, requesterName: string, date: string, handoffTime: string | null, appUrl: string, priorityTag: PriorityTag = null, targetIsProposed = true, requestMessage: string | null = null): string {
  const t = swapText(lang);
  const requestLine = targetIsProposed ? t.requestedTarget(requesterName, date) : t.requestedRequester(requesterName, date);
  return baseTemplate(lang, t.requestedTitle,
    `${priorityBanner(lang, priorityTag)}${heading(t.requestedHeading)}
     ${paragraph(requestLine)}
     ${detailLine(lang, requestMessage)}${handoffLine(lang, handoffTime)}${paragraph(t.requestedCta, "last")}
     ${button(`${appUrl}/notifications`, t.requestedButton)}`
  );
}

function templateRevertRequested(lang: Lang, requesterName: string, date: string, handoffTime: string | null, appUrl: string, priorityTag: PriorityTag = null, requestMessage: string | null = null): string {
  const t = swapText(lang);
  return baseTemplate(lang, t.revertRequestedTitle,
    `${priorityBanner(lang, priorityTag)}${heading(t.revertRequestedHeading, "revert")}
     ${paragraph(t.revertRequestedBody(requesterName, date))}
     ${detailLine(lang, requestMessage)}${handoffLine(lang, handoffTime)}${paragraph(t.revertRequestedCta, "last")}
     ${button(`${appUrl}/notifications`, t.revertRequestedButton)}`
  );
}

function templateRevertApproved(lang: Lang, targetName: string, date: string, appUrl: string, approvalNote: string | null = null): string {
  const t = swapText(lang);
  return baseTemplate(lang, t.revertApprovedTitle,
    `${heading(t.revertApprovedHeading, "success")}
     ${paragraph(t.revertApprovedBody(targetName, date))}
     ${detailLine(lang, approvalNote)}${link(appUrl, common(lang).openCalendar)}`
  );
}

function templateRevertRejected(lang: Lang, targetName: string, date: string, reason: string | null, appUrl: string): string {
  const t = swapText(lang);
  return baseTemplate(lang, t.revertRejectedTitle,
    `${heading(t.revertRejectedHeading, "danger")}
     ${paragraph(t.revertRejectedBody(targetName, date))}
     ${reasonLine(lang, reason)}
     ${linkRow(`${appUrl}/notifications`, t.seeHistory)}`
  );
}

function templateRevertCancelled(lang: Lang, requesterName: string, date: string, appUrl: string): string {
  const t = swapText(lang);
  return baseTemplate(lang, t.revertCancelledTitle,
    `${heading(t.revertCancelledHeading, "warning")}
     ${paragraph(t.revertCancelledBody(requesterName, date), "last")}
     ${link(appUrl, common(lang).openCalendar)}`
  );
}

function templateApprovedForRequester(lang: Lang, targetName: string, date: string, handoffTime: string | null, appUrl: string, targetIsProposed = true, approvalNote: string | null = null): string {
  const t = swapText(lang);
  const approvalLine = targetIsProposed ? t.approvedTarget(targetName, date) : t.approvedRequester(targetName, date);
  return baseTemplate(lang, t.approvedTitle,
    `${heading(t.approvedHeading, "success")}
     ${paragraph(approvalLine)}
     ${detailLine(lang, approvalNote)}${handoffLine(lang, handoffTime)}${paragraph(t.approvedCalendarNote, "last")}
     ${link(appUrl, common(lang).openCalendar)}`
  );
}

function templateRejected(lang: Lang, targetName: string, date: string, reason: string | null, appUrl: string): string {
  const t = swapText(lang);
  return baseTemplate(lang, t.rejectedTitle,
    `${heading(t.rejectedHeading, "danger")}
     ${paragraph(t.rejectedBody(targetName, date))}
     ${reasonLine(lang, reason)}
     ${linkRow(`${appUrl}/notifications`, t.seeRequestHistory)}`
  );
}

function templateCancelled(lang: Lang, requesterName: string, date: string, appUrl: string): string {
  const t = swapText(lang);
  return baseTemplate(lang, t.cancelledTitle,
    `${heading(t.cancelledHeading, "warning")}
     ${paragraph(t.cancelledBody(requesterName, date), "last")}
     ${link(appUrl, common(lang).openCalendar)}`
  );
}

function templateReverted(lang: Lang, date: string, appUrl: string): string {
  const t = swapText(lang);
  return baseTemplate(lang, t.revertedTitle,
    `${heading(t.revertedHeading, "revert")}
     ${paragraph(t.revertedBody(date), "last")}
     ${link(appUrl, common(lang).openCalendar)}`
  );
}

function templateReminder(lang: Lang, date: string, handoffTime: string | null, isRevert: boolean, appUrl: string, requestMessage: string | null, deadlineDate: string, deadlineTime: string): string {
  const t = swapText(lang);
  return baseTemplate(lang, t.reminderTitle,
    `${banner(t.reminderBanner(deadlineDate, deadlineTime), "warning")}
     ${heading(t.reminderHeading(deadlineDate, deadlineTime))}
     ${paragraph(t.reminderBody(date, isRevert, deadlineDate, deadlineTime))}
     ${detailLine(lang, requestMessage)}${handoffLine(lang, handoffTime)}${paragraph(t.reminderCta, "last")}
     ${button(`${appUrl}/notifications`, t.reminderButton)}`
  );
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
     ${small(`${privacy} ${smallLink("https://entrelares.app/privacidade", t.invitationPrivacyLink)}.`, true)}`
  );
}

function templateAutoApproved(lang: Lang, date: string, isRevert: boolean, forApprover: boolean, appUrl: string): string {
  const t = swapText(lang);
  const reason = forApprover ? t.autoApprovedApprover(date, isRevert) : t.autoApprovedRequester(date, isRevert);
  return baseTemplate(lang, t.autoApprovedTitle,
    `${heading(t.autoApprovedHeading, "success")}
     ${paragraph(`${reason} ${t.autoApprovedCalendarNote}`, "last")}
     ${link(appUrl, common(lang).openCalendar)}`
  );
}
