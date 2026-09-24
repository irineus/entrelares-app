// F-09 — the push copy, rendered SERVER-SIDE in the recipient's language.
//
// **Why this file duplicates Dart.** In-app, a notification is rendered on the
// reader's device by `NotificationRenderer` (U-13/U-24): the row stores DATA
// (`params`) and the sentence is built from `type` + `params` in whatever
// language that reader uses. A push has no device to render on — the OS shows
// the payload as it arrives, and on iOS a data-only message is throttled and
// not guaranteed to be delivered at all. So the text must be assembled here,
// per recipient, exactly as `send-swap-email` already assembles an e-mail.
// Deno cannot call Dart, so this is a deliberate duplication, and
// `push_notification_mirror_test.dart` is the gate that keeps it honest: it
// reads THIS file and compares every string against the Dart catalog.
//
// **Why only ten types.** The `notifications` table carries ~25 types, and
// pushing all of them would mean mirroring the whole catalog for events nobody
// needs woken for. The line drawn here is: **push only what the recipient did
// not just do.** A receipt for your own action (`swap_sent`, `revert_sent`,
// `swap_approved_self`, `revert_approved_self`) reaches a person who is holding
// the phone that produced it. The F-28 family fan-out (`swap_family_info`) is
// information, not a call to action. Membership, account/family deletion,
// e-mail quota and billing all already have an e-mail and a screen, and none of
// them is time-critical the way a day starting tomorrow is.
//
// Anything outside PUSH_TYPES simply never reaches this module — the database
// trigger filters first, and `renderPush` refuses a second time, because a
// trigger shipped ahead of a function is exactly how a silent gap opens.

import { formatDateIn, formatTimeIn, type Lang } from "./i18n.ts";

/// The notification types that earn a push. Kept in sync with the database
/// trigger's own list by `push_notification_mirror_test.dart` — the trigger is
/// the cheap filter, this is the authority.
export const PUSH_TYPES: readonly string[] = [
	"auto_reminder",
	"auto_approved",
	"swap_requested",
	"swap_approved",
	"swap_rejected",
	"swap_cancelled",
	"revert_requested",
	"revert_approved",
	"revert_rejected",
	"revert_cancelled",
	// F-52. All four wordings of an aviso reach a phone. The FIRST version cut
	// three of them, because routing was by TYPE alone and a courtesy note would
	// have landed on "Para você" without being listed there. The owner sent two
	// courtesy avisos on the first real round and nothing rang: "vou atrasar 15
	// minutes" is the most common one there is. So the payload carries `kind` now
	// and both channels route on it — asking goes to "Para você", telling goes to
	// "Todas", where the row always is.
	"day_notice",
	// F-70. The family's own plan runs out (D-30, D-7) or ran out. Nobody did
	// anything, so the rule above holds: the calendar is emptying under them,
	// and the member who stopped opening the app is exactly the one a row in
	// the list never reaches. Lands on "Todas", where the row always is.
	"plan_ending",
	// F-55. The agenda's notice (to whom the creator chose — never the creator)
	// and its reminder (0/15/30/60 minutes before the start). Nobody on the
	// receiving end did anything; the reminder is the product's strongest push
	// case after the handoff ("remédio às 14h"). The creator may have said "no
	// push" for the item: the dispatcher skips that row before pg_net. Both
	// land on "Todas".
	"agenda_notice",
	"agenda_reminder",
];

/// Catalog keys, spelled exactly as `K` spells them on the Dart side. The
/// mirror test matches on these strings, so a rename that is not made in both
/// places fails the core lane rather than shipping an untranslated push.
const K = {
	titleAutoReminder: "notifRender.title.autoReminder",
	titleAutoApproved: "notifRender.title.autoApproved",
	titleSwapRequested: "notifRender.title.swapRequested",
	titleSwapApproved: "notifRender.title.swapApproved",
	titleSwapRejected: "notifRender.title.swapRejected",
	titleSwapCancelled: "notifRender.title.swapCancelled",
	titleRevertRequested: "notifRender.title.revertRequested",
	titleRevertApproved: "notifRender.title.revertApproved",
	titleRevertRejected: "notifRender.title.revertRejected",
	titleRevertCancelled: "notifRender.title.revertCancelled",

	autoReminder: "notifRender.autoReminder",
	autoReminderDeadline: "notifRender.autoReminder.deadline",
	autoApprovedRequester: "notifRender.autoApproved.requester",
	autoApprovedApprover: "notifRender.autoApproved.approver",
	swapRequestedTarget: "notifRender.swapRequested.target",
	swapRequestedRequester: "notifRender.swapRequested.requester",
	swapApprovedTarget: "notifRender.swapApproved.target",
	swapApprovedRequester: "notifRender.swapApproved.requester",
	swapRejected: "notifRender.swapRejected",
	swapCancelledByRequester: "notifRender.swapCancelled.byRequester",
	swapCancelledMemberLeft: "notifRender.swapCancelled.memberLeft",
	revertRequested: "notifRender.revertRequested",
	revertApproved: "notifRender.revertApproved",
	revertRejected: "notifRender.revertRejected",
	revertCancelled: "notifRender.revertCancelled",

	titleDayNotice: "notifRender.title.dayNotice",
	dayNoticeInfo: "notifRender.dayNotice.info",
	dayNoticePickup: "notifRender.dayNotice.pickup",
	dayNoticeKeep: "notifRender.dayNotice.keep",
	dayNoticeReasonDelay: "notifRender.dayNotice.reason.delay",
	dayNoticeReasonMedical: "notifRender.dayNotice.reason.medical",
	dayNoticeReasonTraffic: "notifRender.dayNotice.reason.traffic",
	dayNoticeReasonOther: "notifRender.dayNotice.reason.other",
	dayNoticeEtaMinutes: "notifRender.dayNotice.eta.minutes",
	dayNoticeEtaNone: "notifRender.dayNotice.eta.none",
	dayNoticeNoteSuffix: "notifRender.dayNotice.noteSuffix",
	// The two answers and the withdrawal. They were the three wordings the old
	// trigger filter hid: it never let them reach this module, so nobody noticed
	// there was no copy for them here. Dropping the filter without writing these
	// turned a silent NON-push into a silent UNRENDERABLE one.
	titleDayNoticeHelping: "notifRender.title.dayNoticeHelping",
	titleDayNoticeKeeping: "notifRender.title.dayNoticeKeeping",
	titleDayNoticeCancelled: "notifRender.title.dayNoticeCancelled",
	dayNoticeHelping: "notifRender.dayNotice.helping",
	dayNoticeKeeping: "notifRender.dayNotice.keeping",
	dayNoticeCancelled: "notifRender.dayNotice.cancelled",

	msgSuffix: "notifRender.msgSuffix",
	tagUrgent: "notifRender.tag.urgent",
	tagOverdue: "notifRender.tag.overdue",
	fbOtherCap: "notifRender.fb.otherCap",
	fbOtherThe: "notifRender.fb.otherThe",

	titlePlanEnding: "notifRender.title.planEnding",
	titlePlanEnded: "notifRender.title.planEnded",
	titleAgendaNotice: "notifRender.title.agendaNotice",
	titleAgendaReminder: "notifRender.title.agendaReminder",
	agendaNotice: "notifRender.agendaNotice",
	agendaRoutineNotice: "notifRender.agendaRoutineNotice",
	agendaReminder: "notifRender.agendaReminder",
	agendaTextSuffix: "notifRender.agendaTextSuffix",
	agendaKindSchool: "notifRender.agendaKind.school",
	agendaKindHealth: "notifRender.agendaKind.health",
	agendaKindMedicine: "notifRender.agendaKind.medicine",
	agendaKindActivity: "notifRender.agendaKind.activity",
	agendaKindFree: "notifRender.agendaKind.free",
	agendaKindNote: "notifRender.agendaKind.note",
	agendaKindOther: "notifRender.agendaKind.other",
	planEnding: "notifRender.planEnding",
	planEnded: "notifRender.planEnded",
} as const;

/// The strings themselves — byte-identical to `StringsPtBr`/`StringsEn` for
/// the same keys. The PT-BR side is also byte-identical to the sentence the
/// writer stored, which is the U-13 rule the Dart catalog already carries: a
/// Portuguese reader's history must never appear to change retroactively.
const STRINGS: Record<Lang, Record<string, string>> = {
	"pt-BR": {
		"notifRender.title.autoReminder": "Solicitação pendente aguardando resposta",
		"notifRender.title.autoApproved": "Solicitação aprovada automaticamente",
		"notifRender.title.swapRequested": "Nova solicitação de troca",
		"notifRender.title.swapApproved": "Troca aprovada!",
		"notifRender.title.swapRejected": "Troca recusada",
		"notifRender.title.swapCancelled": "Solicitação cancelada",
		"notifRender.title.revertRequested": "Pedido de reversão de troca",
		"notifRender.title.revertApproved": "Reversão confirmada",
		"notifRender.title.revertRejected": "Reversão recusada",
		"notifRender.title.revertCancelled": "Pedido de reversão cancelado",
		"notifRender.autoReminder": "A solicitação do dia {0} será aprovada automaticamente se não houver resposta.",
		"notifRender.autoReminder.deadline": "A solicitação do dia {0} será aprovada automaticamente em {1} às {2} se não houver resposta.",
		"notifRender.autoApproved.requester": "A solicitação do dia {0} foi aprovada automaticamente por falta de resposta.",
		"notifRender.autoApproved.approver": "A solicitação do dia {0} foi aprovada automaticamente. Você não respondeu dentro do prazo.",
		"notifRender.swapRequested.target": "{0} solicitou que você fique responsável pela criança no dia {1}.{2}",
		"notifRender.swapRequested.requester": "{0} solicitou ficar responsável pela criança no dia {1} no seu lugar.{2}",
		"notifRender.swapApproved.target": "{0} aceitou ficar com a criança no dia {1}.{2}",
		"notifRender.swapApproved.requester": "{0} aceitou que você fique com a criança no dia {1}.{2}",
		"notifRender.swapRejected": "{0} recusou a troca de guarda para o dia {1}.{2}",
		"notifRender.swapCancelled.byRequester": "A solicitação de troca para o dia {0} foi cancelada pelo solicitante.",
		"notifRender.swapCancelled.memberLeft": "{0} saiu da família e a solicitação de troca de {1} foi cancelada.",
		"notifRender.revertRequested": "{0} quer reverter a troca de guarda do dia {1}. Você precisa confirmar.{2}",
		"notifRender.revertApproved": "{0} confirmou a reversão da troca do dia {1}. O calendário voltou ao normal.{2}",
		"notifRender.revertRejected": "{0} recusou reverter a troca do dia {1}.{2} A troca permanece ativa.",
		"notifRender.revertCancelled": "O pedido de reversão da troca do dia {0} foi cancelado.",
		"notifRender.title.dayNotice": "Aviso de imprevisto",
		"notifRender.dayNotice.info": "{0} avisou que {1}{2}.{3}",
		"notifRender.dayNotice.pickup": "{0} avisou que {1}{2} e precisa que alguém busque a criança.{3}",
		"notifRender.dayNotice.keep": "{0} avisou que {1}{2} e precisa que alguém fique com a criança hoje.{3}",
		"notifRender.dayNotice.reason.delay": "vai atrasar",
		"notifRender.dayNotice.reason.medical": "teve um imprevisto médico",
		"notifRender.dayNotice.reason.traffic": "está preso no trânsito",
		"notifRender.dayNotice.reason.other": "teve um imprevisto",
		"notifRender.dayNotice.eta.minutes": " (cerca de {0} min)",
		"notifRender.dayNotice.eta.none": " (sem previsão)",
		"notifRender.dayNotice.noteSuffix": " \"{0}\"",
		"notifRender.title.dayNoticeHelping": "Alguém vai ajudar",
		"notifRender.title.dayNoticeKeeping": "O dia de hoje mudou de responsável",
		"notifRender.title.dayNoticeCancelled": "Aviso cancelado",
		"notifRender.dayNotice.helping": "{0} vai ajudar agora.{1}",
		"notifRender.dayNotice.keeping": "{0} vai ficar com a criança hoje. O dia de hoje passou para {0}.{1}",
		"notifRender.dayNotice.cancelled": "{0} cancelou o aviso de hoje.",
		"notifRender.msgSuffix": " Mensagem: {0}",
		"notifRender.tag.urgent": "URGENTE: ",
		"notifRender.tag.overdue": "ATRASADO: ",
		"notifRender.fb.otherCap": "Outro responsável",
		"notifRender.fb.otherThe": "O outro responsável",
		"notifRender.title.planEnding": "O planejamento termina em breve",
		"notifRender.title.planEnded": "O planejamento terminou",
		"notifRender.planEnding": "O planejamento da família vai até {0}. Planeje os próximos meses.",
		"notifRender.planEnded": "O último dia planejado foi {0}. Planeje os próximos meses no calendário.",
		"notifRender.title.agendaNotice": "Novo na agenda",
		"notifRender.title.agendaReminder": "Lembrete da agenda",
		"notifRender.agendaNotice": "{0} adicionou à agenda de {1}: {2}.{3}",
		"notifRender.agendaRoutineNotice": "{0} criou uma rotina na agenda a partir de {1}: {2}.{3}",
		"notifRender.agendaReminder": "{0} ({1}).{2}",
		"notifRender.agendaTextSuffix": " {0}",
		"notifRender.agendaKind.school": "Escola",
		"notifRender.agendaKind.health": "Saúde",
		"notifRender.agendaKind.medicine": "Remédio",
		"notifRender.agendaKind.activity": "Atividade",
		"notifRender.agendaKind.free": "Livre",
		"notifRender.agendaKind.note": "Nota",
		"notifRender.agendaKind.other": "Outro",
	},
	"en": {
		"notifRender.title.autoReminder": "Pending request awaiting your reply",
		"notifRender.title.autoApproved": "Request approved automatically",
		"notifRender.title.swapRequested": "New swap request",
		"notifRender.title.swapApproved": "Swap approved!",
		"notifRender.title.swapRejected": "Swap declined",
		"notifRender.title.swapCancelled": "Request cancelled",
		"notifRender.title.revertRequested": "Swap revert request",
		"notifRender.title.revertApproved": "Revert confirmed",
		"notifRender.title.revertRejected": "Revert declined",
		"notifRender.title.revertCancelled": "Revert request cancelled",
		"notifRender.autoReminder": "The request for {0} will be approved automatically if nobody replies.",
		"notifRender.autoReminder.deadline": "The request for {0} will be approved automatically on {1} at {2} if nobody replies.",
		"notifRender.autoApproved.requester": "The request for {0} was approved automatically for lack of a reply.",
		"notifRender.autoApproved.approver": "The request for {0} was approved automatically. You did not reply before the deadline.",
		"notifRender.swapRequested.target": "{0} asked you to be responsible for the child on {1}.{2}",
		"notifRender.swapRequested.requester": "{0} asked to be responsible for the child on {1} in your place.{2}",
		"notifRender.swapApproved.target": "{0} agreed to have the child on {1}.{2}",
		"notifRender.swapApproved.requester": "{0} agreed that you have the child on {1}.{2}",
		"notifRender.swapRejected": "{0} declined the custody swap for {1}.{2}",
		"notifRender.swapCancelled.byRequester": "The swap request for {0} was cancelled by whoever opened it.",
		"notifRender.swapCancelled.memberLeft": "{0} left the family, so the swap request for {1} was cancelled.",
		"notifRender.revertRequested": "{0} wants to revert the custody swap for {1}. You need to confirm.{2}",
		"notifRender.revertApproved": "{0} confirmed the revert of the swap for {1}. The calendar is back to normal.{2}",
		"notifRender.revertRejected": "{0} declined to revert the swap for {1}.{2} The swap stays active.",
		"notifRender.revertCancelled": "The revert request for the swap on {0} was cancelled.",
		"notifRender.title.dayNotice": "Notice about today",
		"notifRender.dayNotice.info": "{0} let you know they {1}{2}.{3}",
		"notifRender.dayNotice.pickup": "{0} let you know they {1}{2} and need someone to collect the child.{3}",
		"notifRender.dayNotice.keep": "{0} let you know they {1}{2} and need someone to keep the child today.{3}",
		"notifRender.dayNotice.reason.delay": "are running late",
		"notifRender.dayNotice.reason.medical": "have a medical emergency",
		"notifRender.dayNotice.reason.traffic": "are stuck in traffic",
		"notifRender.dayNotice.reason.other": "ran into a problem",
		"notifRender.dayNotice.eta.minutes": " (about {0} min)",
		"notifRender.dayNotice.eta.none": " (no estimate)",
		"notifRender.dayNotice.noteSuffix": " \"{0}\"",
		"notifRender.title.dayNoticeHelping": "Someone is helping",
		"notifRender.title.dayNoticeKeeping": "Today changed carer",
		"notifRender.title.dayNoticeCancelled": "Notice cancelled",
		"notifRender.dayNotice.helping": "{0} is coming to help now.{1}",
		"notifRender.dayNotice.keeping": "{0} will keep the child today. Today has moved to {0}.{1}",
		"notifRender.dayNotice.cancelled": "{0} cancelled today's notice.",
		"notifRender.msgSuffix": " Message: {0}",
		"notifRender.tag.urgent": "URGENT: ",
		"notifRender.tag.overdue": "OVERDUE: ",
		"notifRender.fb.otherCap": "Another caregiver",
		"notifRender.fb.otherThe": "The other caregiver",
		"notifRender.title.planEnding": "Your plan ends soon",
		"notifRender.title.planEnded": "Your plan has ended",
		"notifRender.planEnding": "Your family's plan runs until {0}. Plan the next months.",
		"notifRender.planEnded": "The last planned day was {0}. Plan the next months in the calendar.",
		"notifRender.title.agendaNotice": "New on the agenda",
		"notifRender.title.agendaReminder": "Agenda reminder",
		"notifRender.agendaNotice": "{0} added to the agenda for {1}: {2}.{3}",
		"notifRender.agendaRoutineNotice": "{0} created an agenda routine starting {1}: {2}.{3}",
		"notifRender.agendaReminder": "{0} ({1}).{2}",
		"notifRender.agendaTextSuffix": " {0}",
		"notifRender.agendaKind.school": "School",
		"notifRender.agendaKind.health": "Health",
		"notifRender.agendaKind.medicine": "Medicine",
		"notifRender.agendaKind.activity": "Activity",
		"notifRender.agendaKind.free": "Free time",
		"notifRender.agendaKind.note": "Note",
		"notifRender.agendaKind.other": "Other",
	},
};

/// `{0}`-style substitution — the same placeholder shape the Dart catalog uses,
/// so a string can be copied between the two without editing.
/// F-60: `params.deadline` is the `YYYY-MM-DDTHH:MM` wall clock of
/// `America/Sao_Paulo` that `auto_approve_expired()` computes. Split here so
/// each language positions its own preposition around the two halves.
///
/// Every component is RANGE-CHECKED, because neither `formatDateIn` nor
/// `formatTimeIn` validates: they would happily print `40/13/2026` or turn
/// `24:99` into `12:99 PM`. A deadline the reader plans around is the wrong
/// place to print whatever arrived, so anything off-shape returns null and the
/// caller sends the sentence with no instant in it.
function splitDeadline(value: string | undefined): { date: string; time: string } | null {
	if (!value) return null;
	const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::\d{2})?$/.exec(value);
	if (match === null) return null;
	const [y, mo, d, h, mi] = match.slice(1, 6).map(Number) as [number, number, number, number, number];
	const at = new Date(Date.UTC(y, mo - 1, d, h, mi));
	if (
		at.getUTCFullYear() !== y || at.getUTCMonth() !== mo - 1 || at.getUTCDate() !== d ||
		at.getUTCHours() !== h || at.getUTCMinutes() !== mi
	) return null;
	return { date: `${match[1]}-${match[2]}-${match[3]}`, time: `${match[4]}:${match[5]}` };
}

function fmt(lang: Lang, key: string, args: string[] = []): string {
	const template = STRINGS[lang][key] ?? STRINGS["pt-BR"][key] ?? "";
	return template.replace(/\{(\d+)\}/g, (whole, index) => args[Number(index)] ?? whole);
}

export interface PushCopy {
	title: string;
	body: string;
}

/// The `params` payload as it reaches us: values only, never sentences.
export type PushParams = Record<string, string | undefined>;

/// Builds the notification's push copy, or `null` when it cannot be built.
///
/// **`null` means "do not push", never "push the stored sentence".** In-app,
/// an unknown type or a malformed payload falls back to the stored PT-BR text,
/// because the reader is already looking at a screen and a truthful sentence in
/// the wrong language beats a blank row. A push is the opposite situation: it
/// interrupts someone, it cannot be corrected once shown, and the same event is
/// always reachable in-app anyway. So a payload we cannot render is dropped and
/// logged — the person still gets the notification and the e-mail.
export function renderPush(
	lang: Lang,
	type: string,
	params: PushParams | null,
): PushCopy | null {
	if (!PUSH_TYPES.includes(type)) return null;
	if (params === null) return null;

	const isoDate = params["date"];
	const date = isoDate ? formatDateIn(lang, isoDate) : null;
	if (date === null) return null;   // every pushable type states a day

	const kind = params["kind"];
	const name = params["name"];

	// F-44 free text is the LAST placeholder of every body that accepts one.
	// Blank collapses to "", so no dangling "Mensagem:" label can render.
	const msg = params["msg"];
	const suffix = !msg || msg.trim() === "" ? "" : fmt(lang, K.msgSuffix, [msg]);

	const otherCap = () => fmt(lang, K.fbOtherCap);
	const otherThe = () => fmt(lang, K.fbOtherThe);

	let titleKey: string;
	let body: string;

	switch (type) {
		case "auto_reminder": {
			titleKey = K.titleAutoReminder;
			// F-60: the push says the INSTANT the request stops waiting, the
			// same one the in-app sentence and the e-mail say. A row written
			// before the item carries no `deadline` and falls back to the
			// window-free sentence — never to a number that was wrong in both
			// directions.
			const deadline = splitDeadline(params["deadline"]);
			body = deadline === null
				? fmt(lang, K.autoReminder, [date])
				: fmt(lang, K.autoReminderDeadline, [
					date,
					formatDateIn(lang, deadline.date),
					formatTimeIn(lang, deadline.time) ?? deadline.time,
				]);
			break;
		}

		case "auto_approved":
			titleKey = K.titleAutoApproved;
			body = fmt(
				lang,
				params["role"] === "approver" ? K.autoApprovedApprover : K.autoApprovedRequester,
				[date],
			);
			break;

		// `proposed` is the scenario-A/B discriminator. Reading it wrong inverts
		// the request's meaning, so it gets a branch and never a default.
		case "swap_requested":
			titleKey = K.titleSwapRequested;
			body = fmt(
				lang,
				params["proposed"] === "target" ? K.swapRequestedTarget : K.swapRequestedRequester,
				[name ?? otherThe(), date, suffix],
			);
			break;

		case "swap_approved":
			titleKey = K.titleSwapApproved;
			body = fmt(
				lang,
				params["proposed"] === "target" ? K.swapApprovedTarget : K.swapApprovedRequester,
				[name ?? otherThe(), date, suffix],
			);
			break;

		case "swap_rejected":
			titleKey = K.titleSwapRejected;
			body = fmt(lang, K.swapRejected, [name ?? otherThe(), date, suffix]);
			break;

		// Two writers, one type: the swap service cancels a request, and
		// request_account_deletion cancels it BECAUSE someone left.
		case "swap_cancelled":
			titleKey = K.titleSwapCancelled;
			if (kind === "by_requester") {
				body = fmt(lang, K.swapCancelledByRequester, [date]);
			} else if (kind === "member_left") {
				body = fmt(lang, K.swapCancelledMemberLeft, [name ?? otherCap(), date]);
			} else {
				return null;   // a future `kind` — guessing one of these would state something false
			}
			break;

		case "revert_requested":
			titleKey = K.titleRevertRequested;
			body = fmt(lang, K.revertRequested, [name ?? otherThe(), date, suffix]);
			break;

		case "revert_approved":
			titleKey = K.titleRevertApproved;
			body = fmt(lang, K.revertApproved, [name ?? otherThe(), date, suffix]);
			break;

		case "revert_rejected":
			titleKey = K.titleRevertRejected;
			body = fmt(lang, K.revertRejected, [name ?? otherThe(), date, suffix]);
			break;

		case "revert_cancelled":
			titleKey = K.titleRevertCancelled;
			body = fmt(lang, K.revertCancelled, [date]);
			break;

		// F-52. The reason and the estimate are VALUES, woven into the request's
		// own template — the same composition `noticeSentence` does in Dart, which
		// is why the push and the row the reader then opens say the same thing.
		// An unknown `reason` or `request` is a FUTURE writer's, and a push that
		// cannot be built is DROPPED rather than guessed: the person still gets
		// the notification in the app.
		case "day_notice": {
			// The three wordings that are NEWS rather than a request: they carry no
			// reason and no estimate, only who acted. They are handled first, and
			// they earn a push for the same reason the aviso does — somebody is
			// waiting on an answer, and "o dia de hoje mudou de responsável" is the
			// one fact the sender must not learn late.
			const answerKey = ({
				helping: K.dayNoticeHelping,
				keeping: K.dayNoticeKeeping,
				cancelled: K.dayNoticeCancelled,
			} as Record<string, string>)[kind ?? ""];
			if (answerKey !== undefined) {
				const answerNote = params["note"];
				// `cancelled` takes no note, and its template has no {1}; passing one
				// extra argument to `fmt` is inert, so the three share one call.
				const answerSuffix = !answerNote || answerNote.trim() === ""
					? ""
					: fmt(lang, K.dayNoticeNoteSuffix, [answerNote]);
				titleKey = kind === "helping"
					? K.titleDayNoticeHelping
					: kind === "keeping"
					? K.titleDayNoticeKeeping
					: K.titleDayNoticeCancelled;
				body = fmt(lang, answerKey, [name ?? otherCap(), answerSuffix]);
				break;
			}

			const reasonKey = ({
				atraso: K.dayNoticeReasonDelay,
				medico: K.dayNoticeReasonMedical,
				transito: K.dayNoticeReasonTraffic,
				outro: K.dayNoticeReasonOther,
			} as Record<string, string>)[params["reason"] ?? ""];
			const templateKey = ({
				info: K.dayNoticeInfo,
				pickup: K.dayNoticePickup,
				keep: K.dayNoticeKeep,
			} as Record<string, string>)[kind ?? ""];
			if (reasonKey === undefined || templateKey === undefined) return null;

			const eta = params["eta"];
			// Absent is a VALUE here, not a gap: it is what tells the reader
			// nobody knows when this ends, and it is the state in which somebody
			// may offer to take the day.
			const etaClause = eta === undefined || eta === ""
				? fmt(lang, K.dayNoticeEtaNone)
				: fmt(lang, K.dayNoticeEtaMinutes, [eta]);

			// The sender's own line is QUOTED, never labelled: "Mensagem" belongs
			// to F-44 and "Observação" to the day note, and an aviso borrowing
			// either word is the blurring U-34 exists to stop.
			const noteText = params["note"];
			const noteSuffix = !noteText || noteText.trim() === ""
				? ""
				: fmt(lang, K.dayNoticeNoteSuffix, [noteText]);

			titleKey = K.titleDayNotice;
			body = fmt(lang, templateKey, [
				name ?? otherCap(),
				fmt(lang, reasonKey),
				etaClause,
				noteSuffix,
			]);
			break;
		}

		// F-70: `kind` says whether the last planned day is still ahead or past.
		// An unknown one is a future writer's shape — no push, never a guess.
		case "plan_ending":
			if (kind === "ending") {
				titleKey = K.titlePlanEnding;
				body = fmt(lang, K.planEnding, [date]);
			} else if (kind === "ended") {
				titleKey = K.titlePlanEnded;
				body = fmt(lang, K.planEnded, [date]);
			} else {
				return null;
			}
			break;

		// F-55. "What" is the item as the day sheet heads it (time, kind,
		// child); its own text follows as written. An unknown kind is a
		// future writer's — dropped, never guessed.
		case "agenda_notice":
		case "agenda_reminder": {
			const kindKey = ({
				school: K.agendaKindSchool,
				health: K.agendaKindHealth,
				medicine: K.agendaKindMedicine,
				activity: K.agendaKindActivity,
				free: K.agendaKindFree,
				note: K.agendaKindNote,
				other: K.agendaKindOther,
			} as Record<string, string>)[kind ?? ""];
			if (kindKey === undefined) return null;
			const time = params["time"];
			const what = [
				time ? (formatTimeIn(lang, time) ?? time) : null,
				fmt(lang, kindKey),
				params["child"] ?? null,
			].filter((x) => x !== null && x !== "").join(" · ");
			const text = !msg || msg.trim() === "" ? "" : fmt(lang, K.agendaTextSuffix, [msg]);
			if (type === "agenda_notice") {
				titleKey = K.titleAgendaNotice;
				body = fmt(
					lang,
					params["routine"] === "1" ? K.agendaRoutineNotice : K.agendaNotice,
					[name ?? otherCap(), date, what, text],
				);
			} else {
				titleKey = K.titleAgendaReminder;
				body = fmt(lang, K.agendaReminder, [what, date, text]);
			}
			break;
		}

		default:
			return null;
	}

	// The urgency prefix is CONTENT (it rides in `params.tag`) and is
	// translated; the writers' environment prefix ("[Dev] ") is a deploy-time
	// marker and is deliberately not reproduced — same rule as the in-app
	// renderer's title.
	const tag = params["tag"];
	const prefix = tag === "urgent"
		? fmt(lang, K.tagUrgent)
		: tag === "overdue"
		? fmt(lang, K.tagOverdue)
		: "";

	return { title: prefix + fmt(lang, titleKey), body };
}
