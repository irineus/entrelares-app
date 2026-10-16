/// U-60 — a swap request said in plain words, to the person who must answer.
///
/// The T-103 audit (04/10/2026) watched the invitee receive *"Solicitante:
/// Ana Souza · Proposto: Bruno Lima"* — no weekday, no verb, nothing that said
/// what answering would do. These sentences are what the row, the Hoje card
/// and any later surface say instead, from the same three facts the request
/// already carries.
library;

import 'calendar_rules.dart';
import 'localization/date_formats.dart';
import 'localization/k_app.dart';
import 'localization/localization.dart';

/// "na qui, 08/10" / "no sáb, 10/10" (PT-BR genders the weekday: sábado and
/// domingo are masculine) · "on Thu, 08 Oct".
String swapOnDay(DateTime date, Localization l) => l.format(
    date.weekday >= DateTime.saturday ? KApp.swapOnDayMasc : KApp.swapOnDayFem,
    [formatHandoffDate(date, l)]);

/// "da qui, 08/10" / "do sáb, 10/10" · "of Thu, 08 Oct".
String swapOfDay(DateTime date, Localization l) => l.format(
    date.weekday >= DateTime.saturday ? KApp.swapOfDayMasc : KApp.swapOfDayFem,
    [formatHandoffDate(date, l)]);

/// The sentence for the TARGET of an open request — the reader who answers.
///
/// * a revert: "Ana pede para desfazer a troca da qui, 08/10.";
/// * scenario A (the reader is asked to take the day): "Ana pede que você
///   fique com a criança na qui, 08/10.";
/// * scenario B (the requester proposes themselves on the reader's day):
///   "Ana pede para ficar com a criança na qui, 08/10, que é seu dia."
///
/// [childName] (U-61): with exactly one child in the family the sentence says
/// the name — "Ana pede que você fique com a Sofia…" — `ChildRules.singleName`
/// decides; null keeps "a criança".
String swapRequestSentence({
  required Localization l,
  required String requesterName,
  required DateTime date,
  required bool isRevert,
  required bool requesterIsProposed,
  String? childName,
}) {
  if (isRevert) {
    return l.format(KApp.swapAskRevert, [requesterName, swapOfDay(date, l)]);
  }
  if (childName != null) {
    return l.format(
        requesterIsProposed ? KApp.swapAskTakeNamed : KApp.swapAskKeepNamed,
        [requesterName, swapOnDay(date, l), childName]);
  }
  return l.format(requesterIsProposed ? KApp.swapAskTake : KApp.swapAskKeep,
      [requesterName, swapOnDay(date, l)]);
}

/// F-94 — the Hoje card's line on a day whose request still waits, for the
/// two parties: whoever has the day keeps it until the answer. [me] is the
/// reader, [carerId] the day's current carer (the request froze the day),
/// [targetId] who must answer; [firstName] names a profile.
String pendingTodaySentence({
  required Localization l,
  required int me,
  required int carerId,
  required int targetId,
  required String Function(int profileId) firstName,
}) {
  if (carerId == me && targetId == me) {
    return l[KApp.cardPendingTodayYouUntilYou];
  }
  if (carerId == me) {
    return l.format(KApp.cardPendingTodayYouStay, [firstName(targetId)]);
  }
  if (targetId == me) {
    return l.format(KApp.cardPendingTodayUntilYou, [firstName(carerId)]);
  }
  return l.format(
      KApp.cardPendingTodayBody, [firstName(carerId), firstName(targetId)]);
}

/// F-95 — the story of a swapped day, one line under the pills: who asked
/// and when, who approved and when (or that it was approved automatically),
/// and the approver's note. "Pedida por Ana em 03/10 09:12, aprovada por
/// Bruno em 04/10 18:12 · "combinado"".
String swapStorySentence({
  required Localization l,
  required String requesterName,
  required DateTime? askedAtLocal,
  required String approverName,
  required DateTime? approvedAtLocal,
  required bool automatic,
  String? note,
}) {
  String when(DateTime? t) => t == null ? '—' : l.formatDateTimeShort(t);
  final asked = l.format(KApp.swapStoryAsked, [requesterName, when(askedAtLocal)]);
  final approved = automatic
      ? l.format(KApp.swapStoryAuto, [when(approvedAtLocal)])
      : l.format(KApp.swapStoryApproved, [approverName, when(approvedAtLocal)]);
  final trimmed = note?.trim() ?? '';
  return trimmed.isEmpty ? '$asked, $approved' : '$asked, $approved · "$trimmed"';
}
