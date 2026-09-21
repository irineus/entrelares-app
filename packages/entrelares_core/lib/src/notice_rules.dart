/// F-52 — the aviso de imprevisto: a one-tap notice about TODAY that does not
/// change who has the child.
///
/// **The third term, named on purpose.** The product already tells *Observação
/// do dia* (an operational note attached to a date) from *Mensagem* (the F-44
/// text two parties exchange while negotiating a swap). **Aviso** is the
/// third: one-way, about right now, tied to today, and — unlike a note — it
/// interrupts someone. `vocabulary_test` reserved the word for this item
/// before a single string was written, and now pins it to these keys alone.
///
/// **Why it is not messaging (the F-35 boundary).** F-35 is a free-form
/// append-only conversation: moderation expectations, LGPD data-subject weight
/// and a notification load of its own. This is its constrained subset — a
/// closed reason list, one optional short line, one day, a cap of
/// [noticeMaxPerSenderPerDay], and an answer that is a CHOICE from two, never
/// a sentence. If the reason list ever grows into a chat, the item has become
/// F-35 and must be re-decided as such.
///
/// **Why an aviso can hand the day over, when the card said it never could**
/// (owner, 18/09/2026). The card's invariant was *"an aviso never changes
/// `actual_parent`"*, and the honest path for a real change was the swap
/// request. That still holds for the aviso itself — what changed is that the
/// ANSWER to an aviso may open a swap that is already approved, because by
/// then both parties have consented in order and on the record: the sender
/// asked ([NoticeRequest.keep]) and the answerer accepted. `actual_parent`
/// therefore still moves only through the two-party workflow, with its
/// freezing, its audit stamps and its F-45 origin link — no second path, which
/// is what §2 of the standing decisions forbids.
///
/// **Why a stated delay closes that door** (owner, 18/09/2026). A bounded
/// delay does not justify giving the day away: if the sender says "30
/// minutes", the most anyone can offer is to hold the child until they
/// arrive. So [NoticeRequest.keep] exists only when [NoticeDraft.etaMinutes]
/// is null — the single rule the sheet states out loud, in both directions.
library;

import 'localization/k.dart';
import 'localization/localization.dart';
import 'swap_rules.dart' show normalizeFreeText;

/// What went wrong. A CLOSED list, because the choice travels as a key in
/// `params` and is rendered in the READER's language — never as a Portuguese
/// sentence stored for someone else to read.
enum NoticeReason {
  /// Running late, with or without a stated estimate.
  delay('atraso'),

  /// A medical appointment or emergency.
  medical('medico'),

  /// Traffic.
  traffic('transito'),

  /// Anything else — the optional note carries it.
  other('outro');

  const NoticeReason(this.wire);

  /// The value stored in `day_notices.reason`, and echoed in `params.reason`.
  final String wire;

  /// The reason for a stored value, or null — an unknown wire value is a
  /// FUTURE writer's, and guessing one of today's meanings for it would state
  /// something false (the NotificationRenderer rule, applied here).
  static NoticeReason? fromWire(String? wire) {
    for (final r in NoticeReason.values) {
      if (r.wire == wire) return r;
    }
    return null;
  }
}

/// What the sender needs from whoever reads it. The discriminator that decides
/// whether an answer is offered at all, and which answers.
enum NoticeRequest {
  /// "Só avisando" — information. No answer is offered.
  info('info'),

  /// "Alguém pode buscar?" — help now, the day unchanged.
  pickup('pickup'),

  /// "Alguém pode ficar com ela?" — the day itself is on offer. Available
  /// only to the carer whose day it is, and only with no stated estimate.
  keep('keep');

  const NoticeRequest(this.wire);

  final String wire;

  static NoticeRequest? fromWire(String? wire) {
    for (final r in NoticeRequest.values) {
      if (r.wire == wire) return r;
    }
    return null;
  }
}

/// The estimates a sender may state, in minutes. A fourth choice — "sem
/// previsão" — is the ABSENCE of one (null), not a value: it is what makes
/// [NoticeRequest.keep] reachable, so it cannot be a magic number that a
/// future edit could confuse with 90.
const List<int> noticeEtaOptions = [15, 30, 60];

/// Avisos one person may send about one day. Two, deliberately (owner,
/// 18/09/2026): one covers the event, the second covers it getting worse
/// ("atraso 30" → "sem previsão, alguém pode ficar?"). A third would be a
/// conversation, and the cap is the main thing holding this item away from
/// F-35. The number is stated in the UI BEFORE it blocks — a cap that only
/// announces itself by refusing reads as a bug.
const int noticeMaxPerSenderPerDay = 2;

/// The optional free line. Short on purpose: it explains the closed reason, it
/// does not replace it. Normalized through the same helper as every other free
/// text in the product (F-44), so trimming and emptiness cannot diverge.
const int noticeNoteMaxLength = 140;

/// The same ceiling for the answerer's line ("estou na padaria da esquina").
const int noticeAnswerNoteMaxLength = noticeNoteMaxLength;

/// Who may send an aviso about [dayParentId]'s day.
///
/// The product does NOT model "who is holding the child right now": a day has
/// ONE effective responsible (`actual ?? scheduled`) for its whole length, and
/// `handoff_time` is the hour the transition happens, not a second owner. So
/// "the person delivering" and "the person collecting" can only be named
/// through the days around this one:
///
/// * [dayParentId] — the carer whose day it is;
/// * [previousParentId] — yesterday's carer, who only ADDS a person when today
///   is a transition day (otherwise it is the same person). Theirs is the
///   handover that is happening;
/// * [nextHandoffParentId] — the carer of the next day with a different
///   responsible. Theirs is the collection that is coming.
///
/// Nulls are dropped: an unplanned day has no carer, and a family with no
/// future handoff inside the scan window has no third end. A frozen member
/// (S-11) and a pending one with no account (F-56) are filtered by the caller
/// — this function answers ROLE, not eligibility to act.
Set<int> noticeSenderIds({
  required int? dayParentId,
  required int? previousParentId,
  required int? nextHandoffParentId,
}) =>
    {
      ?dayParentId,
      ?previousParentId,
      ?nextHandoffParentId,
    };

/// The requests [senderId] may make about this day.
///
/// [NoticeRequest.info] and [NoticeRequest.pickup] are always available to an
/// eligible sender. [NoticeRequest.keep] needs BOTH:
///
/// * the sender to be the day's own carer — only the person whose day it is
///   may give the day away, which is also what keeps the swap the answer
///   creates inside F-28 (the answerer proposes THEMSELVES on the sender's
///   day, scenario A, approved by the answerer);
/// * no stated estimate — a delay with a deadline is not a reason to hand
///   over the day.
///
/// Returned in the order the sheet shows them.
List<NoticeRequest> noticeRequestsFor({
  required int senderId,
  required int? dayParentId,
  required int? etaMinutes,
}) =>
    [
      NoticeRequest.info,
      NoticeRequest.pickup,
      if (senderId == dayParentId && etaMinutes == null) NoticeRequest.keep,
    ];

/// Whether [request] may be CHOSEN on the sheet — which is a different
/// question from whether it may be SENT, and the difference is the point
/// (owner, 20/09/2026).
///
/// [noticeRequestAllowed] answers "is this payload legal", and the database
/// enforces exactly that. But two of its conditions are not the same kind of
/// thing:
///
/// * a stated estimate is something the sender can change **here and now** —
///   so the sheet does not refuse, it CLEARS the estimate and grants the
///   request. Blocking it made the reader hunt for a control above the one
///   they were looking at, and the owner read the explanation and still asked
///   why it was blocked;
/// * the day belonging to somebody else is **not fixable from this sheet** at
///   all. There the row stays disabled with its reason, because enabling it
///   would walk the person into a refusal the server has to make.
///
/// So: info and pickup always; keep only for the carer whose day it is.
bool noticeRequestSelectable({
  required NoticeRequest request,
  required int senderId,
  required int? dayParentId,
}) =>
    request != NoticeRequest.keep || senderId == dayParentId;

/// Whether [request] may be sent as described — the same predicate the
/// database enforces, mirrored here so the sheet can disable rather than let
/// the server refuse (the client MIRRORS, the database ENFORCES).
bool noticeRequestAllowed({
  required NoticeRequest request,
  required int senderId,
  required int? dayParentId,
  required int? etaMinutes,
}) =>
    noticeRequestsFor(
      senderId: senderId,
      dayParentId: dayParentId,
      etaMinutes: etaMinutes,
    ).contains(request);

// ── The sentence ─────────────────────────────────────────────────────────────
// ONE composition, read by two callers: the NotificationRenderer (the row in
// the list, and the push once F-52's third PR lands) and the banner on the
// Hoje card. Two copies of a sentence is how "the banner said 30 min and the
// notification said no estimate" happens, with both well-formed.

/// The reason as a verb clause, agreeing with "{sender} avisou que …".
String noticeReasonClause(Localization l, NoticeReason reason) =>
    l[switch (reason) {
      NoticeReason.delay => K.notifRenderDayNoticeReasonDelay,
      NoticeReason.medical => K.notifRenderDayNoticeReasonMedical,
      NoticeReason.traffic => K.notifRenderDayNoticeReasonTraffic,
      NoticeReason.other => K.notifRenderDayNoticeReasonOther,
    }];

/// The estimate as a parenthetical. **Absent is a value here, not a gap**: it
/// is what tells the reader nobody knows when this ends, and it is the exact
/// condition under which someone may offer to take the day.
String noticeEtaClause(Localization l, int? etaMinutes) => etaMinutes == null
    ? l[K.notifRenderDayNoticeEtaNone]
    : l.format(K.notifRenderDayNoticeEtaMinutes, ['$etaMinutes']);

/// The sender's own line, quoted, or "" — normalized through the F-44 helper
/// so a blank line can never render as empty quotation marks.
String noticeNoteSuffix(Localization l, String? note) {
  final normalized = normalizeFreeText(note);
  return normalized == null
      ? ''
      : l.format(K.notifRenderDayNoticeNoteSuffix, [normalized]);
}

/// The whole sentence, in the reader's language.
String noticeSentence({
  required Localization l,
  required String senderName,
  required NoticeReason reason,
  required int? etaMinutes,
  required NoticeRequest request,
  String? note,
}) =>
    l.format(
      switch (request) {
        NoticeRequest.info => K.notifRenderDayNoticeInfo,
        NoticeRequest.pickup => K.notifRenderDayNoticePickup,
        NoticeRequest.keep => K.notifRenderDayNoticeKeep,
      },
      [
        senderName,
        noticeReasonClause(l, reason),
        noticeEtaClause(l, etaMinutes),
        noticeNoteSuffix(l, note),
      ],
    );

/// The sentence the SENDER reads when somebody answers. One composition, two
/// readers again — the notification and, once PR 3 lands, the push.
String noticeAnswerSentence({
  required Localization l,
  required String answererName,
  required NoticeOutcome outcome,
  String? note,
}) =>
    l.format(
      outcome == NoticeOutcome.keeping
          ? K.notifRenderDayNoticeKeeping
          : K.notifRenderDayNoticeHelping,
      [answererName, noticeNoteSuffix(l, note)],
    );

/// How an answer resolves an aviso. Exactly one of these ever lands on a
/// notice — the row that carries it is append-only and unique per notice, so
/// the first answer wins and the second is refused by the database rather than
/// by a check the client could lose a race on.
enum NoticeOutcome {
  /// "Vou ajudar agora" — the answerer helps; the calendar does not move.
  helping('helping'),

  /// "Vou ficar com ela" — the answerer takes the day, through an approved
  /// swap. Reachable only from a [NoticeRequest.keep] aviso.
  keeping('keeping'),

  /// The sender withdrew it: they sorted it out, or it stopped being true.
  /// Authored by the sender alone, and it does NOT give a cap slot back —
  /// send-and-cancel would otherwise be an unbounded channel.
  cancelled('cancelled');

  const NoticeOutcome(this.wire);

  final String wire;

  static NoticeOutcome? fromWire(String? wire) {
    for (final o in NoticeOutcome.values) {
      if (o.wire == wire) return o;
    }
    return null;
  }
}

/// Whether [outcome] may be recorded on an aviso whose request was [request],
/// by [actorId], when the aviso was sent by [senderId].
///
/// Mirror of the database's own guard. Three rules, each with a reason the
/// reader can check: only the sender cancels (nobody else may silence someone
/// else's call for help); only somebody ELSE answers (an aviso is not a
/// conversation with oneself); and taking the day is reachable only from the
/// aviso that offered it.
bool noticeOutcomeAllowed({
  required NoticeOutcome outcome,
  required NoticeRequest request,
  required int actorId,
  required int senderId,
}) =>
    switch (outcome) {
      NoticeOutcome.cancelled => actorId == senderId,
      NoticeOutcome.helping =>
        actorId != senderId && request != NoticeRequest.info,
      NoticeOutcome.keeping =>
        actorId != senderId && request == NoticeRequest.keep,
    };
