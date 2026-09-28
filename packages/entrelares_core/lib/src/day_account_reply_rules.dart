/// F-75 — the reply to a relato do dia: the second voice, appended under the
/// relato, never an edit.
///
/// Client mirror of `add_day_account_reply` (migration `20260928170000_f75`).
/// The RPC is the enforcement — the flag, who, the window, the length, one
/// reply per member per relato and one correction of it; these exist so the
/// sheet offers *Responder* only where the server will accept it, and they
/// must keep saying what the RPC says.
///
/// Pure values only, like `day_account_rules.dart`: the rules read the few
/// fields they need as a record.
library;

import 'localization/date_formats.dart';
import 'localization/k_app.dart';
import 'localization/localization.dart';

/// The fields of a `day_account_replies` row the rules read.
typedef DayAccountReplyEntry = ({
  int id,
  int accountId,
  int authorId,
  int? correctsId,
  DateTime createdAt,
});

/// The window is counted from when the relato was WRITTEN (owner,
/// 28/09/2026), not from the day it is about: a relato about D-30 written
/// today still gets the whole window.
bool isInDayAccountReplyWindow({
  required DateTime accountCreatedAt,
  required DateTime now,
  required int windowDays,
}) =>
    !now.isAfter(accountCreatedAt.add(Duration(days: windowDays)));

/// The replies to one relato, in the order they were written.
List<DayAccountReplyEntry> repliesToDayAccount(
        int accountId, Iterable<DayAccountReplyEntry> replies) =>
    replies.where((r) => r.accountId == accountId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

/// Whether the reader may answer the relato [accountId] now: the module is
/// on, the reader is an active caregiver with an account (a Visualizador only
/// reads — F-50), is NOT the relato's author, the window is open and the
/// reader has not answered it yet (the second text is a correction, not a
/// second reply).
bool canReplyToDayAccount({
  required bool enabled,
  required bool isViewer,
  required bool hasAccount,
  required bool hasLeft,
  required int myProfileId,
  required int accountId,
  required int accountAuthorId,
  required DateTime accountCreatedAt,
  required DateTime now,
  required int windowDays,
  required Iterable<DayAccountReplyEntry> replies,
}) {
  if (!enabled || isViewer || !hasAccount || hasLeft) return false;
  if (accountAuthorId == myProfileId) return false;
  if (!isInDayAccountReplyWindow(
      accountCreatedAt: accountCreatedAt, now: now, windowDays: windowDays)) {
    return false;
  }
  return !replies.any((r) =>
      r.accountId == accountId &&
      r.authorId == myProfileId &&
      r.correctsId == null);
}

/// The correction a reply got, if any.
DayAccountReplyEntry? correctionOfReply(
    int replyId, Iterable<DayAccountReplyEntry> replies) {
  for (final r in replies) {
    if (r.correctsId == replyId) return r;
  }
  return null;
}

/// Whether the reader may correct [entry]: their own ORIGINAL reply (there is
/// no correction of a correction), not corrected yet, while the relato's
/// window is still open and the module is on.
bool canCorrectDayAccountReply({
  required DayAccountReplyEntry entry,
  required Iterable<DayAccountReplyEntry> replies,
  required int myProfileId,
  required bool canWrite,
}) =>
    canWrite &&
    entry.authorId == myProfileId &&
    entry.correctsId == null &&
    correctionOfReply(entry.id, replies) == null;

/// Null when [raw] is a body the RPC accepts, else the catalog key saying why
/// ([KApp.dayAccountReplyErrTooLong] takes [maxChars] as `{0}`).
String? dayAccountReplyBodyErrorKey(String raw, int maxChars) {
  final body = raw.trim();
  if (body.isEmpty) return KApp.dayAccountReplyErrEmpty;
  if (body.length > maxChars) return KApp.dayAccountReplyErrTooLong;
  return null;
}

/// "Resposta de Bruno em 21/09/2026 às 18:05" — the reply's own byline.
String dayAccountReplyByline(Localization l,
    {required String authorName, required DateTime writtenAt}) {
  final local = writtenAt.toLocal();
  return l.format(KApp.dayAccountReplyByline,
      [authorName, l.formatDate(local), l.formatTime(local)]);
}
