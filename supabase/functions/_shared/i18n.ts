// U-13 — language for the SERVER-side senders.
//
// THE PROBLEM, same shape as the in-app notifications: an e-mail is triggered by
// one person and read by another. There is no language the sender could pick
// that is right for everyone, so each message is built in the RECIPIENT's
// language, read from `profiles.language`.
//
// WHY A COLUMN AND NOT THE BROWSER: these functions run on a cron or on someone
// else's request. There is no browser to ask. `profiles.language` exists exactly
// for this — it is the SERVER's copy of the choice the client made.
//
// NULL IS NOT "PORTUGUESE": it means the person never chose. Both facts resolve
// to PT-BR today (the current user base is Brazilian), but they stay distinct in
// the data, so a future default can change without rewriting anyone's stated
// preference.
//
// SHAPE: the HTML shell lives in each function and is written ONCE; only the
// TEXT varies by language. Entries carry their own inline <strong> for the same
// reason the app's billing copy does — emphasis is part of the sentence, and
// splitting a sentence to preserve it is how a translation ends up saying
// something the original did not.

export type Lang = "pt-BR" | "en";

/**
 * The recipient's language. Mirrors the client's LanguageResolver: anything
 * starting with `pt` is Portuguese, anything else is English, absent is PT-BR.
 * Kept deliberately lenient — a stored value we do not recognise must fall back,
 * never throw inside a mail dispatch.
 */
export function resolveLang(value: string | null | undefined): Lang {
  if (!value) return "pt-BR";
  return value.toLowerCase().startsWith("pt") ? "pt-BR" : "en";
}

/**
 * English labels for the BUILT-IN roles, keyed by canonical name — the same key
 * `RoleCatalog` uses on the client.
 *
 * This is a mirror, and the client's `Services/RoleCatalog.cs` is the source of
 * truth. `RoleCatalogParityTests` reads THIS FILE and fails when the two drift,
 * so the duplication cannot rot quietly. It exists because the `roles` table has
 * only `label_pt`, and the invitation e-mail is the one server-side surface that
 * prints a role name.
 *
 * A role missing here is a family's CUSTOM role (F-41) — user data, never
 * translated. The caller falls back to `label_pt`, which is what the family
 * typed.
 */
export const ROLE_LABEL_EN: Record<string, string> = {
  father: "Father",
  mother: "Mother",
  grandfather: "Grandfather",
  grandmother: "Grandmother",
  great_grandfather: "Great-grandfather",
  great_grandmother: "Great-grandmother",
  stepfather: "Stepfather",
  stepmother: "Stepmother",
  uncle: "Uncle",
  aunt: "Aunt",
  godfather: "Godfather",
  godmother: "Godmother",
  brother: "Brother",
  sister: "Sister",
  // The (m)/(f) suffixes are not decoration: Portuguese genders what English
  // collapses, and these are DISTINCT rows that profiles point at. Without the
  // suffix an English calendar legend would show two identical "Cousin" rows.
  cousin_m: "Cousin (m)",
  cousin_f: "Cousin (f)",
  friend_m: "Friend (m)",
  friend_f: "Friend (f)",
  guardian_m: "Guardian (m)",
  guardian_f: "Guardian (f)",
  nanny: "Nanny",
};

/** The role label in the reader's language; custom roles pass through. */
export function roleLabel(lang: Lang, canonical: string | null | undefined, labelPt: string | null | undefined): string {
  if (lang === "en" && canonical && ROLE_LABEL_EN[canonical]) return ROLE_LABEL_EN[canonical];
  return labelPt ?? canonical ?? "";
}

// ── Shared chrome ────────────────────────────────────────────────────────────

export interface CommonStrings {
  htmlLang: string;
  automaticNote: string;
  greeting: (name: string) => string;
  signature: string;
  openCalendar: string;
  messageLabel: string;
}

const COMMON: Record<Lang, CommonStrings> = {
  "pt-BR": {
    htmlLang: "pt-BR",
    automaticNote: "Esta é uma mensagem automática. Não responda a este e-mail.",
    greeting: (name) => `Olá, ${name}.`,
    signature: "Entrelares",
    openCalendar: "Abrir calendário →",
    messageLabel: "Mensagem",
  },
  en: {
    htmlLang: "en",
    automaticNote: "This is an automated message. Please do not reply to this e-mail.",
    greeting: (name) => `Hello, ${name}.`,
    signature: "Entrelares",
    openCalendar: "Open calendar →",
    messageLabel: "Message",
  },
};

export const common = (lang: Lang): CommonStrings => COMMON[lang];

// ── U-24: dates and times in the RECIPIENT's language ────────────────────────
//
// The server-side mirror of `Entrelares/Localization/DateFormats.cs`,
// and it must keep saying the same thing: the same day reaches one caregiver by
// e-mail and the other on screen, and the two surfaces disagreeing about how a
// date is written is how a family ends up arguing about which day was meant.
//
// English spells the month for the reason the client does: `05/08` is 5 August
// here and reads as May 8th to most of the anglophone world, and an e-mail —
// unlike a screen — cannot be re-read in context a second later. `MM/dd/yyyy`
// would only move the ambiguity from an American reader to a British one.
//
// There is no `Intl`/`toLocaleDateString` here on purpose: it would bind the
// output to whatever ICU data the Deno runtime ships, so a platform upgrade
// could silently restyle every e-mail we send.
const EN_MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                   "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** An ISO `yyyy-MM-dd` as the recipient reads it: `05/08/2026` · `05 Aug 2026`. */
export function formatDateIn(lang: Lang, isoDate: string): string {
  const [year, month, day] = isoDate.split("-");
  if (!year || !month || !day) return isoDate;   // never invent a date
  return lang === "en"
    ? `${day} ${EN_MONTHS[Number(month) - 1] ?? month} ${year}`
    : `${day}/${month}/${year}`;
}

/** A `HH:MM[:SS]` as the recipient reads it: `14:30` · `2:30 PM`. */
export function formatTimeIn(lang: Lang, timeStr: string | null): string | null {
  if (!timeStr) return null;
  const [hRaw, m] = timeStr.split(":");
  if (hRaw === undefined || m === undefined) return null;
  if (lang !== "en") return `${hRaw}:${m}`;

  const h = Number(hRaw);
  if (!Number.isFinite(h)) return null;
  const suffix = h < 12 ? "AM" : "PM";
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${m} ${suffix}`;
}

// ── send-swap-email ──────────────────────────────────────────────────────────

export interface SwapStrings {
  tagUrgent: string;
  tagOverdue: string;
  fallbackOtherCaregiver: string;
  fallbackRequester: string;
  fallbackFamily: string;

  bannerUrgent: string;
  bannerOverdue: string;
  handoffLine: (time: string) => string;

  subjRequested: (date: string) => string;
  subjApproved: (date: string) => string;
  subjRejected: (date: string) => string;
  subjCancelled: (date: string) => string;
  subjReverted: (date: string) => string;
  subjRevertRequested: (date: string) => string;
  subjRevertApproved: (date: string) => string;
  subjRevertRejected: (date: string) => string;
  subjRevertCancelled: (date: string) => string;
  subjReminder: (date: string, isRevert: boolean) => string;
  subjAutoApproved: (date: string, isRevert: boolean) => string;
  subjInvitation: (inviter: string) => string;
  subjCap80: string;
  subjCapLast: string;

  requestedTitle: string;
  requestedHeading: string;
  requestedTarget: (who: string, date: string) => string;
  requestedRequester: (who: string, date: string) => string;
  requestedCta: string;
  requestedButton: string;

  revertRequestedTitle: string;
  revertRequestedHeading: string;
  revertRequestedBody: (who: string, date: string) => string;
  revertRequestedCta: string;
  revertRequestedButton: string;

  revertApprovedTitle: string;
  revertApprovedHeading: string;
  revertApprovedBody: (who: string, date: string) => string;

  revertRejectedTitle: string;
  revertRejectedHeading: string;
  revertRejectedBody: (who: string, date: string) => string;
  seeHistory: string;

  revertCancelledTitle: string;
  revertCancelledHeading: string;
  revertCancelledBody: (who: string, date: string) => string;

  approvedTitle: string;
  approvedHeading: string;
  approvedTarget: (who: string, date: string) => string;
  approvedRequester: (who: string, date: string) => string;
  approvedCalendarNote: string;

  rejectedTitle: string;
  rejectedHeading: string;
  rejectedBody: (who: string, date: string) => string;
  seeRequestHistory: string;

  cancelledTitle: string;
  cancelledHeading: string;
  cancelledBody: (who: string, date: string) => string;

  revertedTitle: string;
  revertedHeading: string;
  revertedBody: (date: string) => string;

  reminderTitle: string;
  reminderBanner: string;
  reminderHeading: string;
  reminderBody: (date: string, isRevert: boolean) => string;
  reminderCta: string;
  reminderButton: string;

  autoApprovedTitle: string;
  autoApprovedHeading: string;
  autoApprovedApprover: (date: string, isRevert: boolean) => string;
  autoApprovedRequester: (date: string, isRevert: boolean) => string;
  autoApprovedCalendarNote: string;

  invitationTitle: string;
  invitationHeading: string;
  invitationBody: (inviter: string, family: string) => string;
  invitationRole: (role: string) => string;
  invitationExpiry: (date: string) => string;
  invitationButton: string;
  invitationLinkFallback: string;
  invitationPrivacy: string;
  // F-56: the invitation is for a PENDING member — the admin's name/role stay
  // as family planning data; only the e-mail is purged with the invitation.
  invitationPrivacyPlaceholder: string;
  invitationPrivacyLink: string;

  cap80Title: string;
  cap80Heading: string;
  cap80Body: string;
  cap80Note: string;
  cap80Upsell: string;
  capLastTitle: string;
  capLastHeading: string;
  capLastBody: string;
  capLastNote: string;
  capLastUpsell: string;
  capButton: string;
}

const SWAP: Record<Lang, SwapStrings> = {
  "pt-BR": {
    tagUrgent: "[URGENTE] ",
    tagOverdue: "[ATRASADO] ",
    fallbackOtherCaregiver: "O outro responsável",
    fallbackRequester: "O solicitante",
    fallbackFamily: "sua família",

    bannerUrgent: "⚠️ URGENTE — menos de 24h para o horário de entrega",
    bannerOverdue: "⏰ ATRASADO — o horário de entrega já passou",
    handoffLine: (time) => `Horário de entrega/retirada: <strong>${time}</strong>`,

    subjRequested: (d) => `Nova solicitação de troca para ${d}`,
    subjApproved: (d) => `Troca aprovada para ${d} ✅`,
    subjRejected: (d) => `Troca recusada para ${d}`,
    subjCancelled: (d) => `Solicitação de troca cancelada — ${d}`,
    subjReverted: (d) => `Troca desfeita — ${d}`,
    subjRevertRequested: (d) => `Pedido de reversão de troca — ${d}`,
    subjRevertApproved: (d) => `Reversão confirmada — ${d} ✅`,
    subjRevertRejected: (d) => `Reversão recusada — ${d}`,
    subjRevertCancelled: (d) => `Pedido de reversão cancelado — ${d}`,
    subjReminder: (d, r) => `[Auto-aprovação em 24h] ${r ? "Reversão" : "Troca"} do dia ${d}`,
    subjAutoApproved: (d, r) => `${r ? "Reversão" : "Troca"} do dia ${d} aprovada automaticamente ✅`,
    subjInvitation: (i) => `${i} convidou você para o Entrelares 👨‍👩‍👧`,
    subjCap80: "Vocês já usaram 80% dos e-mails do mês ✉️",
    subjCapLast: "Este é o último e-mail do mês (plano gratuito) ✉️",

    requestedTitle: "Nova solicitação de troca",
    requestedHeading: "Nova solicitação de troca 🔄",
    requestedTarget: (w, d) => `<strong>${w}</strong> solicitou que você fique responsável pela criança no dia <strong>${d}</strong>.`,
    requestedRequester: (w, d) => `<strong>${w}</strong> solicitou ficar responsável pela criança no dia <strong>${d}</strong> no seu lugar.`,
    requestedCta: "Abra o aplicativo para aprovar ou recusar a solicitação.",
    requestedButton: "Ver solicitação",

    revertRequestedTitle: "Pedido de reversão de troca",
    revertRequestedHeading: "Pedido de reversão de troca ↩️",
    revertRequestedBody: (w, d) => `<strong>${w}</strong> quer reverter a troca de guarda do dia <strong>${d}</strong> para o responsável original.`,
    revertRequestedCta: "Abra o aplicativo para confirmar ou recusar a reversão.",
    revertRequestedButton: "Ver pedido de reversão",

    revertApprovedTitle: "Reversão confirmada",
    revertApprovedHeading: "Reversão confirmada! ✅",
    revertApprovedBody: (w, d) => `<strong>${w}</strong> confirmou a reversão da troca do dia <strong>${d}</strong>. O calendário voltou ao estado original.`,

    revertRejectedTitle: "Reversão recusada",
    revertRejectedHeading: "Reversão recusada ❌",
    revertRejectedBody: (w, d) => `<strong>${w}</strong> recusou reverter a troca do dia <strong>${d}</strong>. A troca permanece ativa.`,
    seeHistory: "Ver histórico →",

    revertCancelledTitle: "Pedido de reversão cancelado",
    revertCancelledHeading: "Pedido de reversão cancelado",
    revertCancelledBody: (w, d) => `<strong>${w}</strong> cancelou o pedido de reversão da troca para o dia <strong>${d}</strong>. A troca original permanece ativa.`,

    approvedTitle: "Troca aprovada",
    approvedHeading: "Troca aprovada! ✅",
    approvedTarget: (w, d) => `<strong>${w}</strong> aceitou ficar com a criança no dia <strong>${d}</strong>.`,
    approvedRequester: (w, d) => `<strong>${w}</strong> aceitou que você fique com a criança no dia <strong>${d}</strong>.`,
    approvedCalendarNote: "O calendário foi atualizado automaticamente.",

    rejectedTitle: "Troca recusada",
    rejectedHeading: "Troca recusada ❌",
    rejectedBody: (w, d) => `<strong>${w}</strong> recusou a troca de guarda para o dia <strong>${d}</strong>. Nenhuma alteração foi feita no calendário.`,
    seeRequestHistory: "Ver histórico de solicitações →",

    cancelledTitle: "Solicitação cancelada",
    cancelledHeading: "Solicitação cancelada",
    cancelledBody: (w, d) => `<strong>${w}</strong> cancelou a solicitação de troca para o dia <strong>${d}</strong>.`,

    revertedTitle: "Troca desfeita",
    revertedHeading: "Troca desfeita",
    revertedBody: (d) => `A troca de guarda que você havia aceitado para o dia <strong>${d}</strong> foi desfeita pelo responsável planejado. O calendário voltou ao estado original.`,

    reminderTitle: "Solicitação pendente expira em 24h",
    reminderBanner: "⏰ Aprovação automática em 24h",
    reminderHeading: "Você tem 24h para responder",
    reminderBody: (d, r) => `A solicitação de ${r ? "reversão" : "troca"} do dia <strong>${d}</strong> será <strong>aprovada automaticamente em 24 horas</strong> se você não responder.`,
    reminderCta: "Abra o aplicativo para aprovar ou recusar agora.",
    reminderButton: "Responder solicitação",

    autoApprovedTitle: "Aprovada automaticamente",
    autoApprovedHeading: "Aprovada automaticamente ✅",
    autoApprovedApprover: (d, r) => `A solicitação de ${r ? "reversão" : "troca"} do dia <strong>${d}</strong> foi aprovada automaticamente. Você não respondeu dentro do prazo de 48 horas.`,
    autoApprovedRequester: (d, r) => `A solicitação de ${r ? "reversão" : "troca"} do dia <strong>${d}</strong> foi aprovada automaticamente após 48h sem resposta.`,
    autoApprovedCalendarNote: "O calendário foi atualizado.",

    invitationTitle: "Convite para o Entrelares",
    invitationHeading: "Você foi convidado(a)! 👨‍👩‍👧",
    invitationBody: (i, f) => `<strong>${i}</strong> convidou você para gerenciar juntos o calendário de guarda compartilhada da <strong>${f}</strong>.`,
    invitationRole: (r) => `Você entrará como <strong>${r}</strong>.`,
    invitationExpiry: (d) => `Toque no botão abaixo para criar a sua conta. Este convite é válido por <strong>7 dias</strong>, até <strong>${d}</strong>.`,
    invitationButton: "Criar minha conta",
    invitationLinkFallback: "Se o botão não funcionar, copie e cole este link no navegador:",
    invitationPrivacy: "Seu nome e e-mail foram inseridos sob o legítimo interesse de quem convidou você. Caso este convite não seja aceito, seu registro será permanentemente expurgado de nossos sistemas em até <strong>30 dias</strong>. Saiba mais na",
    invitationPrivacyPlaceholder: "Seu e-mail foi inserido sob o legítimo interesse de quem convidou você e, caso este convite não seja aceito, será permanentemente expurgado de nossos sistemas em até <strong>30 dias</strong>. O nome e o papel informados por quem convidou fazem parte do planejamento da família dessa pessoa, que pode editá-los ou removê-los a qualquer momento. Saiba mais na",
    invitationPrivacyLink: "Política de Privacidade",

    cap80Title: "Vocês estão chegando no limite de e-mails do mês",
    cap80Heading: "Chegando no limite de e-mails ✉️",
    cap80Body: "A sua família já usou <strong>80% dos e-mails deste mês</strong> no plano gratuito.",
    cap80Note: "Não se preocupe: as <strong>notificações dentro do app</strong> (pedidos e aprovações de troca) continuam <strong>sem limite</strong> — apenas a cópia por e-mail pode pausar ao fim do mês.",
    cap80Upsell: "Quer um limite bem maior de e-mails? Conheça o <strong>Premium</strong>.",
    capLastTitle: "Este é o último e-mail do mês",
    capLastHeading: "Último e-mail do mês ✉️",
    capLastBody: "A sua família atingiu o limite de e-mails deste mês no plano gratuito — <strong>este é o último e-mail que enviaremos até a virada do mês</strong>.",
    capLastNote: "As <strong>notificações dentro do app</strong> seguem <strong>normais e sem limite</strong>: vocês continuam vendo cada pedido e aprovação de troca em tempo real.",
    capLastUpsell: "Para voltar a receber e-mails imediatamente, ative o <strong>Premium</strong> (limite de e-mails bem maior).",
    capButton: "Ver o Premium",
  },
  en: {
    tagUrgent: "[URGENT] ",
    tagOverdue: "[OVERDUE] ",
    fallbackOtherCaregiver: "The other caregiver",
    fallbackRequester: "The requester",
    fallbackFamily: "your family",

    bannerUrgent: "⚠️ URGENT — less than 24h to the handover time",
    bannerOverdue: "⏰ OVERDUE — the handover time has passed",
    handoffLine: (time) => `Handover time: <strong>${time}</strong>`,

    subjRequested: (d) => `New swap request for ${d}`,
    subjApproved: (d) => `Swap approved for ${d} ✅`,
    subjRejected: (d) => `Swap declined for ${d}`,
    subjCancelled: (d) => `Swap request cancelled — ${d}`,
    subjReverted: (d) => `Swap undone — ${d}`,
    subjRevertRequested: (d) => `Swap revert request — ${d}`,
    subjRevertApproved: (d) => `Revert confirmed — ${d} ✅`,
    subjRevertRejected: (d) => `Revert declined — ${d}`,
    subjRevertCancelled: (d) => `Revert request cancelled — ${d}`,
    subjReminder: (d, r) => `[Auto-approval in 24h] ${r ? "Revert" : "Swap"} for ${d}`,
    subjAutoApproved: (d, r) => `${r ? "Revert" : "Swap"} for ${d} approved automatically ✅`,
    subjInvitation: (i) => `${i} invited you to Entrelares 👨‍👩‍👧`,
    subjCap80: "You have used 80% of this month's e-mails ✉️",
    subjCapLast: "This is the last e-mail of the month (free plan) ✉️",

    requestedTitle: "New swap request",
    requestedHeading: "New swap request 🔄",
    requestedTarget: (w, d) => `<strong>${w}</strong> asked you to be responsible for the child on <strong>${d}</strong>.`,
    requestedRequester: (w, d) => `<strong>${w}</strong> asked to be responsible for the child on <strong>${d}</strong> in your place.`,
    requestedCta: "Open the app to approve or decline the request.",
    requestedButton: "View request",

    revertRequestedTitle: "Swap revert request",
    revertRequestedHeading: "Swap revert request ↩️",
    revertRequestedBody: (w, d) => `<strong>${w}</strong> wants to revert the custody swap for <strong>${d}</strong> back to the original caregiver.`,
    revertRequestedCta: "Open the app to confirm or decline the revert.",
    revertRequestedButton: "View revert request",

    revertApprovedTitle: "Revert confirmed",
    revertApprovedHeading: "Revert confirmed! ✅",
    revertApprovedBody: (w, d) => `<strong>${w}</strong> confirmed the revert of the swap for <strong>${d}</strong>. The calendar is back to its original state.`,

    revertRejectedTitle: "Revert declined",
    revertRejectedHeading: "Revert declined ❌",
    revertRejectedBody: (w, d) => `<strong>${w}</strong> declined to revert the swap for <strong>${d}</strong>. The swap stays active.`,
    seeHistory: "View history →",

    revertCancelledTitle: "Revert request cancelled",
    revertCancelledHeading: "Revert request cancelled",
    revertCancelledBody: (w, d) => `<strong>${w}</strong> cancelled the revert request for the swap on <strong>${d}</strong>. The original swap stays active.`,

    approvedTitle: "Swap approved",
    approvedHeading: "Swap approved! ✅",
    approvedTarget: (w, d) => `<strong>${w}</strong> agreed to have the child on <strong>${d}</strong>.`,
    approvedRequester: (w, d) => `<strong>${w}</strong> agreed that you have the child on <strong>${d}</strong>.`,
    approvedCalendarNote: "The calendar was updated automatically.",

    rejectedTitle: "Swap declined",
    rejectedHeading: "Swap declined ❌",
    rejectedBody: (w, d) => `<strong>${w}</strong> declined the custody swap for <strong>${d}</strong>. No change was made to the calendar.`,
    seeRequestHistory: "View request history →",

    cancelledTitle: "Request cancelled",
    cancelledHeading: "Request cancelled",
    cancelledBody: (w, d) => `<strong>${w}</strong> cancelled the swap request for <strong>${d}</strong>.`,

    revertedTitle: "Swap undone",
    revertedHeading: "Swap undone",
    revertedBody: (d) => `The custody swap you had accepted for <strong>${d}</strong> was undone by the scheduled caregiver. The calendar is back to its original state.`,

    reminderTitle: "Pending request expires in 24h",
    reminderBanner: "⏰ Automatic approval in 24h",
    reminderHeading: "You have 24h to reply",
    reminderBody: (d, r) => `The ${r ? "revert" : "swap"} request for <strong>${d}</strong> will be <strong>approved automatically in 24 hours</strong> if you do not reply.`,
    reminderCta: "Open the app to approve or decline now.",
    reminderButton: "Reply to request",

    autoApprovedTitle: "Approved automatically",
    autoApprovedHeading: "Approved automatically ✅",
    autoApprovedApprover: (d, r) => `The ${r ? "revert" : "swap"} request for <strong>${d}</strong> was approved automatically. You did not reply within the 48-hour window.`,
    autoApprovedRequester: (d, r) => `The ${r ? "revert" : "swap"} request for <strong>${d}</strong> was approved automatically after 48h with no reply.`,
    autoApprovedCalendarNote: "The calendar was updated.",

    invitationTitle: "Invitation to Entrelares",
    invitationHeading: "You have been invited! 👨‍👩‍👧",
    invitationBody: (i, f) => `<strong>${i}</strong> invited you to manage the shared custody calendar of <strong>${f}</strong> together.`,
    invitationRole: (r) => `You will join as <strong>${r}</strong>.`,
    invitationExpiry: (d) => `Tap the button below to create your account. This invitation is valid for <strong>7 days</strong>, until <strong>${d}</strong>.`,
    invitationButton: "Create my account",
    invitationLinkFallback: "If the button does not work, copy and paste this link into your browser:",
    invitationPrivacy: "Your name and e-mail were entered under the legitimate interest of whoever invited you. If this invitation is not accepted, your record is permanently purged from our systems within <strong>30 days</strong>. Read more in the",
    invitationPrivacyPlaceholder: "Your e-mail was entered under the legitimate interest of whoever invited you and, if this invitation is not accepted, it is permanently purged from our systems within <strong>30 days</strong>. The name and role they entered are part of that person's own family planning, which they can edit or remove at any time. Read more in the",
    invitationPrivacyLink: "Privacy Policy",

    cap80Title: "You are approaching this month's e-mail limit",
    cap80Heading: "Approaching the e-mail limit ✉️",
    cap80Body: "Your family has already used <strong>80% of this month's e-mails</strong> on the free plan.",
    cap80Note: "Nothing to worry about: the <strong>notifications inside the app</strong> (swap requests and approvals) carry on <strong>with no limit</strong> — only the e-mail copy may pause at the end of the month.",
    cap80Upsell: "Want a much higher e-mail limit? Take a look at <strong>Premium</strong>.",
    capLastTitle: "This is the last e-mail of the month",
    capLastHeading: "Last e-mail of the month ✉️",
    capLastBody: "Your family reached this month's e-mail limit on the free plan — <strong>this is the last e-mail we will send until the month turns</strong>.",
    capLastNote: "The <strong>notifications inside the app</strong> carry on <strong>as normal and with no limit</strong>: you keep seeing every swap request and approval in real time.",
    capLastUpsell: "To start receiving e-mails again straight away, activate <strong>Premium</strong> (a much higher e-mail limit).",
    capButton: "See Premium",
  },
};

export const swap = (lang: Lang): SwapStrings => SWAP[lang];

// ── send-account-email ───────────────────────────────────────────────────────

export interface AccountStrings {
  // U-24: the deadline wording when the row carries no date. It used to be the
  // literal "30 dias" inside send-account-email, in every language.
  fallbackThirtyDays: string;
  subjLeftSelf: string;
  subjLeftOthers: (who: string) => string;
  subjJoined: (who: string) => string;
  subjReturned: (who: string) => string;
  subjGraceEnding: string;
  subjFdRequesterSelf: string;
  subjFdRequesterOthers: (deadline: string) => string;
  subjFdReminder: (deadline: string) => string;
  subjFdRefused: string;
  subjFdWithdrawn: string;
  subjFdCompleted: (family: string) => string;

  selfHeading: string;
  selfIntro: string;
  selfBullet1: (date: string) => string;
  selfBullet2: string;
  selfBullet3: string;
  selfBullet4: string;
  selfClosing: string;

  graceHeading: string;
  graceIntro: (date: string) => string;
  graceBody: string;
  graceHowTo: string;

  othersHeading: string;
  othersBody: (who: string) => string;
  othersHistory: string;

  joinedHeading: string;
  joinedBody: (who: string) => string;
  joinedClosing: string;

  returnedHeading: string;
  returnedBody: (who: string) => string;

  fdRequesterHeading: string;
  fdRequesterIntro: (deadline: string) => string;
  fdRequesterBullet1: string;
  fdRequesterBullet2: string;
  fdRequesterBullet3: string;
  fdRequesterBullet4: string;
  fdRequesterClosing: string;

  fdOthersHeading: string;
  fdOthersIntro: (who: string) => string;
  fdOthersBullet1: (deadline: string) => string;
  fdOthersBullet2: string;
  fdOthersBullet3: string;
  fdOthersBullet4: string;

  fdRefusedHeading: string;
  fdRefusedBody: (who: string) => string;

  fdWithdrawnHeading: string;
  fdWithdrawnBody: (who: string) => string;

  fdReminderHeading: string;
  fdReminderIntro: (deadline: string) => string;
  fdReminderBullet1: string;
  fdReminderBullet2: string;

  fdCompletedHeading: string;
  fdCompletedBody: (family: string) => string;
  fdCompletedClosing: string;
}

const ACCOUNT: Record<Lang, AccountStrings> = {
  "pt-BR": {
    fallbackThirtyDays: "30 dias",
    subjLeftSelf: "Sua saída da família foi solicitada",
    subjLeftOthers: (w) => `${w} saiu da família`,
    subjJoined: (w) => `${w} entrou na família`,
    subjReturned: (w) => `${w} voltou à família`,
    subjGraceEnding: "Seu Premium está prestes a ser interrompido",
    subjFdRequesterSelf: "Você solicitou a exclusão da família",
    subjFdRequesterOthers: (d) => `Exclusão da família solicitada — responda até ${d}`,
    subjFdReminder: (d) => `A família será excluída em ${d}`,
    subjFdRefused: "Exclusão da família cancelada",
    subjFdWithdrawn: "Exclusão da família retirada",
    subjFdCompleted: (f) => `A família "${f}" foi excluída`,

    selfHeading: "Saída da família solicitada",
    selfIntro: "Recebemos a sua solicitação para <strong>sair da família</strong>. Antes de concluir, é importante que você conheça todas as consequências:",
    selfBullet1: (d) => `Sua conta será <strong>apagada definitivamente em ${d}</strong> (30 dias). Até essa data você pode <strong>cancelar a saída</strong> abrindo o aplicativo — desde que ainda haja vaga na família.`,
    selfBullet2: "Seus <strong>dias futuros foram liberados de forma irreversível</strong>: se você voltar, eles <strong>não serão restaurados automaticamente</strong> e precisarão ser reagendados manualmente.",
    selfBullet3: "O <strong>histórico passado permanece</strong> com o seu nome, como registro de quem realizou cada ação no calendário.",
    selfBullet4: "Os <strong>demais responsáveis da família foram avisados</strong> da sua saída.",
    selfClosing: "Se você não reconhece esta solicitação, cancele-a o quanto antes pelo aplicativo.",

    graceHeading: "Seu Premium está prestes a ser interrompido",
    graceIntro: (d) => `Não conseguimos confirmar o pagamento da assinatura Premium da sua família. Estamos mantendo o acesso durante um <strong>período de carência</strong>, mas ele termina em <strong>${d}</strong>.`,
    graceBody: "Se a cobrança não for regularizada até lá, a família <strong>voltará ao Plano Gratuito</strong>. <strong>Nenhum dado é apagado</strong> — o calendário, as trocas e todo o histórico continuam intactos; apenas os recursos Premium ficam indisponíveis até uma nova contratação.",
    graceHowTo: "Para resolver, abra o aplicativo em <strong>Família &gt; Assinatura</strong>.",

    othersHeading: "Um responsável saiu da família",
    othersBody: (w) => `<strong>${w}</strong> solicitou a saída da família. Os <strong>dias futuros</strong> que estavam sob responsabilidade dessa pessoa foram <strong>liberados</strong> — abra o calendário para <strong>verificar e reatribuir</strong> o que for necessário.`,
    othersHistory: "O histórico passado permanece inalterado.",

    joinedHeading: "Novo responsável na família",
    joinedBody: (w) => `<strong>${w}</strong> <strong>juntou-se à família</strong>. A partir de agora essa pessoa também pode ser incluída no planejamento do calendário e nas trocas.`,
    joinedClosing: "Abra o aplicativo para conferir.",

    returnedHeading: "Um responsável voltou à família",
    returnedBody: (w) => `<strong>${w}</strong> <strong>cancelou a saída e voltou à família</strong>. Essa pessoa volta a participar normalmente do calendário e das trocas.`,

    fdRequesterHeading: "Exclusão da família solicitada",
    fdRequesterIntro: (d) => `Você solicitou a <strong>exclusão da família</strong>. Como os dados são compartilhados, todos os demais responsáveis foram avisados e têm até <strong>${d}</strong> para se manifestar:`,
    fdRequesterBullet1: "Se <strong>ninguém recusar</strong> até essa data, <strong>TODOS os dados</strong> (calendário, histórico, auditoria e as contas de todos os responsáveis) serão <strong>apagados definitivamente</strong>.",
    fdRequesterBullet2: "<strong>Qualquer recusa</strong> de outro responsável <strong>encerra a solicitação imediatamente</strong> e a família continua.",
    fdRequesterBullet3: "Você pode <strong>retirar a solicitação</strong> a qualquer momento pelo aplicativo.",
    fdRequesterBullet4: "Enquanto ela estiver pendente, <strong>convites e saídas individuais ficam bloqueados</strong>.",
    fdRequesterClosing: "Se desejar guardar uma cópia dos dados, use a exportação em Perfil antes do prazo.",

    fdOthersHeading: "Exclusão da família solicitada",
    fdOthersIntro: (w) => `<strong>${w}</strong> solicitou a <strong>exclusão da família</strong>. Isso apaga definitivamente <strong>TODOS os dados</strong> — calendário, histórico, auditoria e as contas de todos os responsáveis.`,
    fdOthersBullet1: (d) => `Você tem até <strong>${d}</strong> para responder no aplicativo (Perfil &gt; Exclusão da família).`,
    fdOthersBullet2: "<strong>Se você não responder, o silêncio vale como concordância.</strong>",
    fdOthersBullet3: "<strong>Uma única recusa cancela a exclusão</strong> — a família continua.",
    fdOthersBullet4: "Antes do prazo, você pode <strong>exportar seus dados</strong> em Perfil.",

    fdRefusedHeading: "Exclusão da família cancelada",
    fdRefusedBody: (w) => `<strong>${w}</strong> <strong>recusou</strong> a exclusão da família. A solicitação foi <strong>encerrada</strong> e a família continua normalmente — nada foi apagado.`,

    fdWithdrawnHeading: "Exclusão da família retirada",
    fdWithdrawnBody: (w) => `<strong>${w}</strong> <strong>retirou</strong> a solicitação de exclusão da família. A família continua normalmente — nada foi apagado.`,

    fdReminderHeading: "A exclusão da família se aproxima",
    fdReminderIntro: (d) => `A família será <strong>excluída definitivamente em ${d}</strong> — calendário, histórico, auditoria e as contas de todos os responsáveis.`,
    fdReminderBullet1: "Você ainda pode <strong>recusar</strong> no aplicativo (Perfil &gt; Exclusão da família) — uma única recusa cancela tudo.",
    fdReminderBullet2: "Se deseja guardar uma cópia, <strong>exporte seus dados</strong> em Perfil antes do prazo.",

    fdCompletedHeading: "Família excluída",
    fdCompletedBody: (f) => `A família <strong>${f}</strong> foi <strong>excluída definitivamente</strong>, conforme a solicitação aprovada por todos os responsáveis (nenhuma recusa dentro do prazo de 30 dias).`,
    fdCompletedClosing: "Todos os dados — calendário, histórico, auditoria e contas — foram apagados, e este e-mail não permite mais acesso ao aplicativo. Se isso for uma surpresa para você, responda a esta mensagem.",
  },
  en: {
    fallbackThirtyDays: "30 days",
    subjLeftSelf: "Your departure from the family was requested",
    subjLeftOthers: (w) => `${w} left the family`,
    subjJoined: (w) => `${w} joined the family`,
    subjReturned: (w) => `${w} is back in the family`,
    subjGraceEnding: "Your Premium is about to be interrupted",
    subjFdRequesterSelf: "You requested the deletion of the family",
    subjFdRequesterOthers: (d) => `Family deletion requested — reply by ${d}`,
    subjFdReminder: (d) => `The family will be deleted on ${d}`,
    subjFdRefused: "Family deletion cancelled",
    subjFdWithdrawn: "Family deletion withdrawn",
    subjFdCompleted: (f) => `The family "${f}" was deleted`,

    selfHeading: "Departure from the family requested",
    selfIntro: "We received your request to <strong>leave the family</strong>. Before it goes through, it is important that you know all the consequences:",
    selfBullet1: (d) => `Your account will be <strong>permanently deleted on ${d}</strong> (30 days). Until then you can <strong>cancel the departure</strong> by opening the app — as long as there is still a free seat in the family.`,
    selfBullet2: "Your <strong>future days were released irreversibly</strong>: if you come back, they <strong>will not be restored automatically</strong> and will have to be scheduled again by hand.",
    selfBullet3: "The <strong>past history stays</strong> under your name, as the record of who performed each action on the calendar.",
    selfBullet4: "The <strong>other caregivers in the family were notified</strong> of your departure.",
    selfClosing: "If you do not recognise this request, cancel it as soon as possible in the app.",

    graceHeading: "Your Premium is about to be interrupted",
    graceIntro: (d) => `We could not confirm the payment for your family's Premium subscription. We are keeping access during a <strong>grace period</strong>, but it ends on <strong>${d}</strong>.`,
    graceBody: "If the charge is not settled by then, the family <strong>goes back to the Free plan</strong>. <strong>No data is deleted</strong> — the calendar, the swaps and the whole history stay intact; only the Premium features become unavailable until a new subscription.",
    graceHowTo: "To sort it out, open the app under <strong>Family &gt; Subscription</strong>.",

    othersHeading: "A caregiver left the family",
    othersBody: (w) => `<strong>${w}</strong> requested to leave the family. The <strong>future days</strong> that were under that person's responsibility were <strong>released</strong> — open the calendar to <strong>check and reassign</strong> whatever is needed.`,
    othersHistory: "The past history stays unchanged.",

    joinedHeading: "New caregiver in the family",
    joinedBody: (w) => `<strong>${w}</strong> <strong>joined the family</strong>. From now on that person can also be included in the calendar planning and in swaps.`,
    joinedClosing: "Open the app to have a look.",

    returnedHeading: "A caregiver is back in the family",
    returnedBody: (w) => `<strong>${w}</strong> <strong>cancelled their departure and is back in the family</strong>. That person takes part in the calendar and in swaps as normal again.`,

    fdRequesterHeading: "Family deletion requested",
    fdRequesterIntro: (d) => `You requested the <strong>deletion of the family</strong>. Because the data is shared, all the other caregivers were notified and have until <strong>${d}</strong> to respond:`,
    fdRequesterBullet1: "If <strong>nobody refuses</strong> by that date, <strong>ALL the data</strong> (calendar, history, audit trail and every caregiver's account) will be <strong>permanently erased</strong>.",
    fdRequesterBullet2: "<strong>Any refusal</strong> from another caregiver <strong>ends the request immediately</strong> and the family continues.",
    fdRequesterBullet3: "You can <strong>withdraw the request</strong> at any time in the app.",
    fdRequesterBullet4: "While it is pending, <strong>invitations and individual departures are blocked</strong>.",
    fdRequesterClosing: "If you want to keep a copy of the data, use the export under Profile before the deadline.",

    fdOthersHeading: "Family deletion requested",
    fdOthersIntro: (w) => `<strong>${w}</strong> requested the <strong>deletion of the family</strong>. That permanently erases <strong>ALL the data</strong> — calendar, history, audit trail and every caregiver's account.`,
    fdOthersBullet1: (d) => `You have until <strong>${d}</strong> to reply in the app (Profile &gt; Family deletion).`,
    fdOthersBullet2: "<strong>If you do not reply, silence counts as agreement.</strong>",
    fdOthersBullet3: "<strong>A single refusal cancels the deletion</strong> — the family continues.",
    fdOthersBullet4: "Before the deadline, you can <strong>export your data</strong> under Profile.",

    fdRefusedHeading: "Family deletion cancelled",
    fdRefusedBody: (w) => `<strong>${w}</strong> <strong>refused</strong> the deletion of the family. The request was <strong>closed</strong> and the family continues as normal — nothing was deleted.`,

    fdWithdrawnHeading: "Family deletion withdrawn",
    fdWithdrawnBody: (w) => `<strong>${w}</strong> <strong>withdrew</strong> the family deletion request. The family continues as normal — nothing was deleted.`,

    fdReminderHeading: "The family deletion is near",
    fdReminderIntro: (d) => `The family will be <strong>permanently deleted on ${d}</strong> — calendar, history, audit trail and every caregiver's account.`,
    fdReminderBullet1: "You can still <strong>refuse</strong> in the app (Profile &gt; Family deletion) — a single refusal cancels everything.",
    fdReminderBullet2: "If you want to keep a copy, <strong>export your data</strong> under Profile before the deadline.",

    fdCompletedHeading: "Family deleted",
    fdCompletedBody: (f) => `The family <strong>${f}</strong> was <strong>permanently deleted</strong>, following the request approved by every caregiver (no refusal within the 30-day window).`,
    fdCompletedClosing: "All the data — calendar, history, audit trail and accounts — was erased, and this e-mail no longer grants access to the app. If this comes as a surprise to you, reply to this message.",
  },
};

export const account = (lang: Lang): AccountStrings => ACCOUNT[lang];

// ── Auth e-mails (the Send Email Hook) ───────────────────────────────────────
//
// WHY THESE LIVE HERE AT ALL. GoTrue's own templates are ONE per project — a
// single body for every reader — so an English tester who asked for a password
// reset got a Portuguese e-mail while the app around them was entirely in
// English. That was noted as out of scope when U-13 shipped, because there was
// no way to branch inside GoTrue; the way is the **Send Email Hook**, which
// hands the message to us before it is sent and lets `send-auth-email` render
// it in the recipient's language like every other e-mail this product sends.
//
// These are the highest-stakes e-mails we write: someone locked out of their
// account reads exactly one of them, usually in a hurry. So the copy says what
// happened, what to do, and what to do if it was not them — and never more.
export interface AuthMailStrings {
  /** Subject line, already language-appropriate. */
  subject: string;
  heading: string;
  /** The sentence before the button. */
  intro: string;
  /** The button's own label. */
  action: string;
  /** The reassurance for someone who did not ask for this. Empty when the mail
   *  cannot be triggered by anyone but the reader (a magic link they requested). */
  ignore: string;
}

/** Every `email_action_type` GoTrue can hand to the hook. `unknown` is the
 *  deliberate catch-all: a type we have never seen must still send a usable
 *  e-mail, because the alternative is a person who cannot get into their
 *  account. */
export type AuthMailKind =
  | "signup" | "recovery" | "invite" | "magiclink"
  | "email_change" | "email_change_new" | "reauthentication" | "unknown";

const AUTH_MAIL: Record<Lang, Record<AuthMailKind, AuthMailStrings>> = {
  "pt-BR": {
    signup: {
      subject: "Confirme seu e-mail",
      heading: "Confirme seu e-mail",
      intro: "Falta um passo para começar a usar o calendário: confirme que este endereço é seu.",
      action: "Confirmar e-mail",
      ignore: "Se não foi você que criou esta conta, pode ignorar esta mensagem.",
    },
    recovery: {
      subject: "Redefina sua senha",
      heading: "Redefina sua senha",
      intro: "Recebemos um pedido para redefinir a sua senha. Use o botão abaixo para escolher uma nova.",
      action: "Redefinir senha",
      ignore: "Se não foi você que pediu, pode ignorar esta mensagem — sua senha atual continua valendo.",
    },
    invite: {
      subject: "Você foi convidado",
      heading: "Você foi convidado",
      intro: "Você foi convidado para usar o Entrelares. Use o botão abaixo para criar sua conta.",
      action: "Aceitar convite",
      ignore: "Se você não esperava este convite, pode ignorar esta mensagem.",
    },
    magiclink: {
      subject: "Seu link de acesso",
      heading: "Seu link de acesso",
      intro: "Use o botão abaixo para entrar. O link vale por pouco tempo e só pode ser usado uma vez.",
      action: "Entrar",
      ignore: "",
    },
    email_change: {
      subject: "Confirme a troca do seu e-mail",
      heading: "Confirme a troca do seu e-mail",
      intro: "Recebemos um pedido para trocar o e-mail da sua conta. Confirme pelo botão abaixo.",
      action: "Confirmar troca",
      ignore: "Se não foi você que pediu, pode ignorar esta mensagem — nada muda.",
    },
    email_change_new: {
      subject: "Confirme seu novo e-mail",
      heading: "Confirme seu novo e-mail",
      intro: "Este endereço foi indicado como o novo e-mail da conta. Confirme pelo botão abaixo.",
      action: "Confirmar novo e-mail",
      ignore: "Se não foi você que pediu, pode ignorar esta mensagem — nada muda.",
    },
    reauthentication: {
      subject: "Seu código de verificação",
      heading: "Seu código de verificação",
      intro: "Use o código abaixo para confirmar que é você. Ele expira em poucos minutos.",
      action: "",
      ignore: "Se não foi você que pediu, pode ignorar esta mensagem.",
    },
    unknown: {
      subject: "Confirmação de segurança",
      heading: "Confirmação de segurança",
      intro: "Use o botão abaixo para concluir a ação solicitada na sua conta.",
      action: "Continuar",
      ignore: "Se não foi você que pediu, pode ignorar esta mensagem.",
    },
  },
  en: {
    signup: {
      subject: "Confirm your e-mail",
      heading: "Confirm your e-mail",
      intro: "One step left before you can start using the calendar: confirm this address is yours.",
      action: "Confirm e-mail",
      ignore: "If you did not create this account, you can ignore this message.",
    },
    recovery: {
      subject: "Reset your password",
      heading: "Reset your password",
      intro: "We received a request to reset your password. Use the button below to choose a new one.",
      action: "Reset password",
      ignore: "If this was not you, you can ignore this message — your current password still works.",
    },
    invite: {
      subject: "You have been invited",
      heading: "You have been invited",
      intro: "You have been invited to use Entrelares. Use the button below to create your account.",
      action: "Accept invitation",
      ignore: "If you were not expecting this invitation, you can ignore this message.",
    },
    magiclink: {
      subject: "Your sign-in link",
      heading: "Your sign-in link",
      intro: "Use the button below to sign in. The link expires shortly and can only be used once.",
      action: "Sign in",
      ignore: "",
    },
    email_change: {
      subject: "Confirm your e-mail change",
      heading: "Confirm your e-mail change",
      intro: "We received a request to change your account's e-mail address. Confirm with the button below.",
      action: "Confirm change",
      ignore: "If this was not you, you can ignore this message — nothing changes.",
    },
    email_change_new: {
      subject: "Confirm your new e-mail",
      heading: "Confirm your new e-mail",
      intro: "This address was given as the account's new e-mail. Confirm with the button below.",
      action: "Confirm new e-mail",
      ignore: "If this was not you, you can ignore this message — nothing changes.",
    },
    reauthentication: {
      subject: "Your verification code",
      heading: "Your verification code",
      intro: "Use the code below to confirm it is you. It expires in a few minutes.",
      action: "",
      ignore: "If this was not you, you can ignore this message.",
    },
    unknown: {
      subject: "Security confirmation",
      heading: "Security confirmation",
      intro: "Use the button below to complete the action requested on your account.",
      action: "Continue",
      ignore: "If this was not you, you can ignore this message.",
    },
  },
};

export const authMail = (lang: Lang, kind: AuthMailKind): AuthMailStrings =>
  AUTH_MAIL[lang][kind] ?? AUTH_MAIL[lang].unknown;

/** Maps GoTrue's `email_action_type` onto a kind we have copy for. Anything
 *  unrecognised becomes `unknown` rather than throwing — see AuthMailKind. */
export function authMailKind(actionType: string | null | undefined): AuthMailKind {
  const known: AuthMailKind[] = [
    "signup", "recovery", "invite", "magiclink",
    "email_change", "email_change_new", "reauthentication",
  ];
  const value = (actionType ?? "").trim();
  return known.includes(value as AuthMailKind) ? value as AuthMailKind : "unknown";
}

/**
 * U-13 — the language the sender's SCREEN was in, read out of `redirect_to`.
 *
 * The client appends it (`AuthService.LanguageQueryParam`) because a password
 * reset is asked for by someone who cannot sign in, and `profiles` only learns a
 * person's language when they DO sign in. For an account that has not been back
 * since the column shipped there is nothing else to go on, and the alternative is
 * telling an English reader in Portuguese that they can reset their password.
 *
 * Lenient by construction: a malformed URL, a missing key or a value we do not
 * recognise all yield `null`, and the caller falls through to its next source.
 * Nothing here may throw — it runs inside a mail dispatch that has no fallback.
 */
export const LANGUAGE_QUERY_PARAM = "lang";

export function langFromRedirect(redirectTo: string | null | undefined): Lang | null {
  if (!redirectTo) return null;
  try {
    const value = new URL(redirectTo).searchParams.get(LANGUAGE_QUERY_PARAM);
    return value ? resolveLang(value) : null;
  } catch {
    return null;
  }
}
