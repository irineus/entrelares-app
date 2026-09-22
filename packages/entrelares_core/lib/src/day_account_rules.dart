/// F-67 — the relato do dia: a dated account of what happened on a day that
/// has PASSED, appended to the record and never edited.
///
/// Client mirror of `add_day_account` (migration `20260921220000_f67`). The
/// RPC is the enforcement — author, window, length, correction target and the
/// daily cap; these exist so the sheet can refuse upfront and say why, and
/// they must keep saying what the RPC says.
///
/// Pure values only: `entrelares_db_contracts` depends on this package, never
/// the other way, so the rules read the few fields they need as a record.
library;

import 'date_math.dart';
import 'localization/date_formats.dart';
import 'localization/k_app.dart';
import 'localization/localization.dart';

/// The fields of a `day_accounts` row the rules read.
typedef DayAccountEntry = ({
  int id,
  int authorId,
  int? correctsId,
  DateTime createdAt,
});

/// The oldest day a relato may still be about: `today − maxDaysBack`.
DateTime dayAccountOldestDate(DateTime today, int maxDaysBack) =>
    DateTime(today.year, today.month, today.day - maxDaysBack);

/// D-1 … D-[maxDaysBack]: a day that has passed, inside the window. TODAY is
/// refused on purpose (owner, 21/09/2026) — today has the Observação and the
/// aviso; the relato is for what already happened.
bool isDayAccountDate(DateTime date, DateTime today, int maxDaysBack) {
  final d = dateOnly(date);
  return d.isBefore(dateOnly(today)) &&
      !d.isBefore(dayAccountOldestDate(today, maxDaysBack));
}

/// Who may write: an ACTIVE member with an account (a pending member has none
/// — F-56; a departed one is frozen — S-11), about a day inside the window.
bool canWriteDayAccount({
  required bool hasAccount,
  required bool hasLeft,
  required DateTime date,
  required DateTime today,
  required int maxDaysBack,
}) =>
    hasAccount && !hasLeft && isDayAccountDate(date, today, maxDaysBack);

/// The RPC trims before it counts — two trims that disagree is how one text
/// renders differently on two screens.
String normalizeDayAccountBody(String raw) => raw.trim();

/// Null when [raw] is a body the RPC accepts, else the catalog key saying why
/// ([KApp.dayAccountErrTooLong] takes [maxChars] as `{0}`).
String? dayAccountBodyErrorKey(String raw, int maxChars) {
  final body = normalizeDayAccountBody(raw);
  if (body.isEmpty) return KApp.dayAccountErrEmpty;
  if (body.length > maxChars) return KApp.dayAccountErrTooLong;
  return null;
}

/// The relatos some OTHER relato corrects — rendered in the undone style, with
/// "corrigido em …", and never offered for another correction (the database
/// keeps one correction per relato; a chain is corrected at its newest link).
Set<int> supersededDayAccountIds(Iterable<DayAccountEntry> entries) => {
      for (final e in entries)
        if (e.correctsId != null) e.correctsId!,
    };

/// The relato that corrects [id], if any — its `createdAt` is the instant the
/// superseded one prints as "corrigido em".
DayAccountEntry? correctionOf(int id, Iterable<DayAccountEntry> entries) {
  for (final e in entries) {
    if (e.correctsId == id) return e;
  }
  return null;
}

/// Only the AUTHOR corrects, only the newest link of a chain, and only while
/// the day is still inside the window — the RPC's own three conditions.
bool canCorrectDayAccount({
  required DayAccountEntry entry,
  required Iterable<DayAccountEntry> sameDay,
  required int? myProfileId,
  required bool canWrite,
}) =>
    canWrite &&
    entry.authorId == myProfileId &&
    !supersededDayAccountIds(sameDay).contains(entry.id);

/// The same day's relatos in the order they were written — the record reads
/// top to bottom as the story was told.
List<T> dayAccountsInOrder<T>(
        Iterable<T> entries, DateTime Function(T) createdAt) =>
    entries.toList()..sort((a, b) => createdAt(a).compareTo(createdAt(b)));

/// "Registrado por Ana em 19/09 às 10:32" — a dated fact, the F-61 discipline
/// (no judgement word). [writtenAt] is shown in the READER's local time.
String dayAccountByline(Localization l,
        {required String authorName, required DateTime writtenAt}) {
  final local = writtenAt.toLocal();
  return l.format(KApp.dayAccountByline,
      [authorName, l.formatDate(local), l.formatTime(local)]);
}

/// "Corrigido em 20/09 às 08:10" — printed on the superseded relato.
String dayAccountCorrectedLine(Localization l, {required DateTime correctedAt}) {
  final local = correctedAt.toLocal();
  return l.format(
      KApp.dayAccountCorrected, [l.formatDate(local), l.formatTime(local)]);
}
