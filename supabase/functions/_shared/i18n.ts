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
}

const COMMON: Record<Lang, CommonStrings> = {
  "pt-BR": {
    htmlLang: "pt-BR",
    automaticNote: "Esta é uma mensagem automática. Não responda a este e-mail.",
    greeting: (name) => `Olá, ${name}.`,
    signature: "Entrelares",
  },
  en: {
    htmlLang: "en",
    automaticNote: "This is an automated message. Please do not reply to this e-mail.",
    greeting: (name) => `Hello, ${name}.`,
    signature: "Entrelares",
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
  fallbackOtherCaregiver: string;
  fallbackFamily: string;

  subjInvitation: (inviter: string) => string;

  invitationTitle: string;
  invitationHeading: string;
  invitationBody: (inviter: string, family: string) => string;
  /** F-50: the same invitation, to someone invited as a VIEWER. */
  invitationBodyViewer: (inviter: string, family: string) => string;
  /** U-58: the reader who does not know the inviter is told what to do — nothing is created until they act. */
  invitationSafety: (inviter: string) => string;
  invitationRole: (role: string) => string;
  /** T-82: the days THIS invitation is valid for (`invitation.valid_days` when it was created). */
  invitationExpiry: (days: number, date: string) => string;
  invitationButton: string;
  invitationLinkFallback: string;
  invitationPrivacy: string;
  // F-56: the invitation is for a PENDING member — the admin's name/role stay
  // as family planning data; only the e-mail is purged with the invitation.
  invitationPrivacyPlaceholder: string;
  invitationPrivacyLink: string;
}

const SWAP: Record<Lang, SwapStrings> = {
  "pt-BR": {
    fallbackOtherCaregiver: "O outro responsável",
    fallbackFamily: "sua família",

    subjInvitation: (i) => `${i} convidou você para o Entrelares`,

    invitationTitle: "Convite para o Entrelares",
    invitationHeading: "Você foi convidado(a)!",
    invitationBody: (i, f) => `<strong>${i}</strong> convidou você para gerenciar juntos o calendário de guarda compartilhada da <strong>${f}</strong>.`,
    invitationBodyViewer: (i, f) => `<strong>${i}</strong> convidou você para acompanhar o calendário de guarda compartilhada da <strong>${f}</strong> como visualizador: você vê o plano, a agenda e as notificações informativas no aplicativo, sem alterar nada.`,
    invitationSafety: (i) => `Se você não reconhece <strong>${i}</strong>, ignore este e-mail — nenhuma conta é criada até você agir.`,
    invitationRole: (r) => `Você entrará como <strong>${r}</strong>.`,
    invitationExpiry: (n, d) => `Toque no botão abaixo para criar a sua conta. Este convite é válido por <strong>${n} ${n === 1 ? "dia" : "dias"}</strong>, até <strong>${d}</strong>.`,
    invitationButton: "Criar minha conta",
    invitationLinkFallback: "Se o botão não funcionar, copie e cole este link no navegador:",
    invitationPrivacy: "Seu nome e e-mail foram inseridos sob o legítimo interesse de quem convidou você. Caso este convite não seja aceito, seu registro será permanentemente expurgado de nossos sistemas em até <strong>30 dias</strong>. Saiba mais na",
    invitationPrivacyPlaceholder: "Seu e-mail foi inserido sob o legítimo interesse de quem convidou você e, caso este convite não seja aceito, será permanentemente expurgado de nossos sistemas em até <strong>30 dias</strong>. O nome e o papel informados por quem convidou fazem parte do planejamento da família dessa pessoa, que pode editá-los ou removê-los a qualquer momento. Saiba mais na",
    invitationPrivacyLink: "Política de Privacidade",
  },
  en: {
    fallbackOtherCaregiver: "The other caregiver",
    fallbackFamily: "your family",

    subjInvitation: (i) => `${i} invited you to Entrelares`,

    invitationTitle: "Invitation to Entrelares",
    invitationHeading: "You have been invited!",
    invitationBody: (i, f) => `<strong>${i}</strong> invited you to manage the shared custody calendar of <strong>${f}</strong> together.`,
    invitationBodyViewer: (i, f) => `<strong>${i}</strong> invited you to follow the shared custody calendar of <strong>${f}</strong> as a viewer: you see the plan, the agenda and the informative notifications in the app, without changing anything.`,
    invitationSafety: (i) => `If you do not recognise <strong>${i}</strong>, ignore this e-mail — no account is created until you act.`,
    invitationRole: (r) => `You will join as <strong>${r}</strong>.`,
    invitationExpiry: (n, d) => `Tap the button below to create your account. This invitation is valid for <strong>${n} ${n === 1 ? "day" : "days"}</strong>, until <strong>${d}</strong>.`,
    invitationButton: "Create my account",
    invitationLinkFallback: "If the button does not work, copy and paste this link into your browser:",
    invitationPrivacy: "Your name and e-mail were entered under the legitimate interest of whoever invited you. If this invitation is not accepted, your record is permanently purged from our systems within <strong>30 days</strong>. Read more in the",
    invitationPrivacyPlaceholder: "Your e-mail was entered under the legitimate interest of whoever invited you and, if this invitation is not accepted, it is permanently purged from our systems within <strong>30 days</strong>. The name and role they entered are part of that person's own family planning, which they can edit or remove at any time. Read more in the",
    invitationPrivacyLink: "Privacy Policy",
  },
};

export const swap = (lang: Lang): SwapStrings => SWAP[lang];

// ── send-account-email ───────────────────────────────────────────────────────

export interface AccountStrings {
  // U-24: the deadline wording when the row carries no date. It used to be the
  // literal "30 dias" inside send-account-email, in every language.
  fallbackThirtyDays: string;
  subjLeftSelf: string;
  subjGraceEnding: string;
  subjFdRequesterSelf: string;
  subjFdRequesterOthers: (deadline: string) => string;
  subjFdReminder: (deadline: string) => string;
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

  fdReminderHeading: string;
  fdReminderIntro: (deadline: string) => string;
  fdReminderBullet1: string;
  fdReminderBullet2: string;

  fdCompletedHeading: string;
  fdCompletedBody: (family: string) => string;
  fdCompletedClosing: string;

  // S-21 — the sudo gate's second proof, for a session that has no password to
  // confirm. The copy never names the action being confirmed: `elevate` is
  // called before the action runs and does not know which one it is, and
  // guessing in an e-mail about leaving or deleting would be worse than silence.
  subjElevationCode: string;
  elevationHeading: string;
  elevationIntro: string;
  elevationExpiry: (minutes: string) => string;
  elevationIgnore: string;
}

const ACCOUNT: Record<Lang, AccountStrings> = {
  "pt-BR": {
    fallbackThirtyDays: "30 dias",
    subjLeftSelf: "Sua saída da família foi solicitada",
    subjGraceEnding: "Seu Premium está prestes a ser interrompido",
    subjFdRequesterSelf: "Você solicitou a exclusão da família",
    subjFdRequesterOthers: (d) => `Exclusão da família solicitada — responda até ${d}`,
    subjFdReminder: (d) => `A família será excluída em ${d}`,
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

    fdReminderHeading: "A exclusão da família se aproxima",
    fdReminderIntro: (d) => `A família será <strong>excluída definitivamente em ${d}</strong> — calendário, histórico, auditoria e as contas de todos os responsáveis.`,
    fdReminderBullet1: "Você ainda pode <strong>recusar</strong> no aplicativo (Perfil &gt; Exclusão da família) — uma única recusa cancela tudo.",
    fdReminderBullet2: "Se deseja guardar uma cópia, <strong>exporte seus dados</strong> em Perfil antes do prazo.",

    fdCompletedHeading: "Família excluída",
    fdCompletedBody: (f) => `A família <strong>${f}</strong> foi <strong>excluída definitivamente</strong>, conforme a solicitação aprovada por todos os responsáveis (nenhuma recusa dentro do prazo de 30 dias).`,
    fdCompletedClosing: "Todos os dados — calendário, histórico, auditoria e contas — foram apagados, e este e-mail não permite mais acesso ao aplicativo. Se isso for uma surpresa para você, responda a esta mensagem.",

    subjElevationCode: "Seu código de confirmação",
    elevationHeading: "Seu código de confirmação",
    elevationIntro: "Você pediu para confirmar que é você antes de concluir uma ação sensível na sua conta. Use o código abaixo no aplicativo:",
    elevationExpiry: (m) => `O código vale por <strong>${m} minutos</strong> e só pode ser usado uma vez.`,
    elevationIgnore: "Se não foi você que pediu, ignore esta mensagem — nada foi alterado. Vale a pena conferir quem tem acesso à sua conta.",
  },
  en: {
    fallbackThirtyDays: "30 days",
    subjLeftSelf: "Your departure from the family was requested",
    subjGraceEnding: "Your Premium is about to be interrupted",
    subjFdRequesterSelf: "You requested the deletion of the family",
    subjFdRequesterOthers: (d) => `Family deletion requested — reply by ${d}`,
    subjFdReminder: (d) => `The family will be deleted on ${d}`,
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

    fdReminderHeading: "The family deletion is near",
    fdReminderIntro: (d) => `The family will be <strong>permanently deleted on ${d}</strong> — calendar, history, audit trail and every caregiver's account.`,
    fdReminderBullet1: "You can still <strong>refuse</strong> in the app (Profile &gt; Family deletion) — a single refusal cancels everything.",
    fdReminderBullet2: "If you want to keep a copy, <strong>export your data</strong> under Profile before the deadline.",

    fdCompletedHeading: "Family deleted",
    fdCompletedBody: (f) => `The family <strong>${f}</strong> was <strong>permanently deleted</strong>, following the request approved by every caregiver (no refusal within the 30-day window).`,
    fdCompletedClosing: "All the data — calendar, history, audit trail and accounts — was erased, and this e-mail no longer grants access to the app. If this comes as a surprise to you, reply to this message.",

    subjElevationCode: "Your confirmation code",
    elevationHeading: "Your confirmation code",
    elevationIntro: "You asked to confirm it is you before completing a sensitive action on your account. Use the code below in the app:",
    elevationExpiry: (m) => `The code is valid for <strong>${m} minutes</strong> and can only be used once.`,
    elevationIgnore: "If this was not you, ignore this message — nothing was changed. It is worth checking who has access to your account.",
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

// ── F-68: Help & contact ─────────────────────────────────────────────────────
//
// Two messages per request. The one to the TEAM is always PT-BR (the team reads
// Portuguese); only the category label and the field names live here, the rest
// is the person's own text. The CONFIRMATION goes to the person, in their
// language — and it never echoes the message back: on the signed-out path the
// reply address is whatever was typed, so an echo would turn the form into a
// relay that sends a stranger's text from our domain to anybody. The request
// number and the promise are all it carries.
//
// The promise ("até 2 dias úteis") is the owner's (21/09/2026). Changing it is a
// product decision, not a copy edit.

export type SupportCategory = "question" | "problem" | "suggestion" | "privacy" | "other";

/** The team's label for each category — PT-BR only, it goes to the inbox. */
export const SUPPORT_CATEGORY_LABEL: Record<SupportCategory, string> = {
  question: "Dúvida",
  problem: "Problema ou erro",
  suggestion: "Sugestão",
  privacy: "Privacidade e dados",
  other: "Outro",
};

export interface SupportStrings {
  categoryLabel: Record<SupportCategory, string>;
  subjConfirmation: (id: number) => string;
  confirmationHeading: string;
  confirmationIntro: (category: string, id: number) => string;
  confirmationPromise: string;
  confirmationReply: string;
  confirmationIgnore: string;
}

const SUPPORT: Record<Lang, SupportStrings> = {
  "pt-BR": {
    categoryLabel: SUPPORT_CATEGORY_LABEL,
    subjConfirmation: (id) => `Recebemos sua mensagem (#${id})`,
    confirmationHeading: "Recebemos sua mensagem",
    confirmationIntro: (category, id) =>
      `Sua mensagem ao Entrelares chegou, na categoria <strong>${category}</strong>. O número do pedido é <strong>#${id}</strong>.`,
    confirmationPromise: "Respondemos em até <strong>2 dias úteis</strong>, por este mesmo endereço de e-mail.",
    confirmationReply: "Se quiser acrescentar algo, responda a este e-mail citando o número do pedido.",
    confirmationIgnore: "Se não foi você quem escreveu, ignore esta mensagem — nada muda na sua conta.",
  },
  en: {
    categoryLabel: {
      question: "Question",
      problem: "Problem or error",
      suggestion: "Suggestion",
      privacy: "Privacy and data",
      other: "Other",
    },
    subjConfirmation: (id) => `We received your message (#${id})`,
    confirmationHeading: "We received your message",
    confirmationIntro: (category, id) =>
      `Your message to Entrelares arrived, under <strong>${category}</strong>. The request number is <strong>#${id}</strong>.`,
    confirmationPromise: "We reply within <strong>2 business days</strong>, to this same e-mail address.",
    confirmationReply: "If you want to add something, reply to this e-mail quoting the request number.",
    confirmationIgnore: "If you did not write to us, ignore this message — nothing changes on your account.",
  },
};

export const support = (lang: Lang): SupportStrings => SUPPORT[lang];
