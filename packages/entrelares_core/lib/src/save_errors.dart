/// Client mirrors of the save/session error contracts — ported from
/// `entrelares-app` `CalendarHelpers.cs` (save-error translation, QA S-11 /
/// T-33 / T-35) plus the pilot's session-expiry mapping
/// (`entrelares-console` `lib/rules.dart`, F-58 QA lesson 1.2).
///
/// PostgREST wraps DB errors in a JSON body that used to be dumped raw at the
/// user. Known signatures get a meaningful PT-BR message; trigger-raised
/// messages (already PT-BR) pass through; anything else keeps the caller's
/// generic fallback. The substrings below are STABLE CONTRACTS with our own
/// triggers/constraints — change them only with the server.
library;

import 'dart:convert';

import 'localization/k_app.dart';
import 'localization/localization.dart';

/// True when the error is the UNIQUE(family, date) collision — another member
/// saved this day first (stale calendar race).
bool isUniqueDayConflict(String raw) =>
    raw.contains('23505') &&
    raw.contains('care_schedules_family_schedule_date_key');

/// T-33: true when the error is the optimistic-revision guard — a stale UPDATE
/// (the row changed since it was read). The message is our own trigger's, so
/// the substring is a stable contract.
bool isStaleDayConflict(String raw) => raw.contains('salvou este dia primeiro');

/// Any "someone got there first" day collision: the INSERT race (unique key)
/// or the UPDATE race (revision guard). Both recover the same way — reload,
/// rehydrate with the winner's version, explain.
bool isDayConflict(String raw) =>
    isUniqueDayConflict(raw) || isStaleDayConflict(raw);

/// T-35: true when the update was rejected for carrying NO concurrency echo —
/// the signature of a client build older than T-35. It must NOT be treated as
/// a day conflict: reloading the month cannot fix it, only reloading the APP
/// can, so the user gets that instruction instead of a retry loop.
bool isStaleClientBuild(String raw) => raw.contains('Recarregue o aplicativo');

/// F-58 QA lesson 1.2: without a valid session the client is `anon`, which in
/// this 100%-RLS product has no privilege at all (T-44) — `42501` reads like a
/// GRANT bug and is not. Map the signature to "sessão expirada" centrally.
bool isSessionExpired(String raw) =>
    raw.contains('42501') || raw.contains('permission denied');

/// U-13 port: the session-expired sentence now follows the reader's language.
String sessionExpiredMessage(Localization l) => l[KApp.sessionExpired];

const _accented = 'áâãàéêíóôõúçÁÂÃÉÊÍÓÔÕÚÇ';

/// `PostgrestException.toString()` — a FORMATTED DART STRING, not JSON.
///
/// The message is taken non-greedily up to the first `, code: `, which is the
/// delimiter the package itself writes; our own sentences never contain that
/// literal.
final _postgrestToString =
    RegExp(r'PostgrestException\(message: (.*?), code: (.*?), details: ',
        dotAll: true);

/// The `code`/`message` pair, from EITHER shape a save error reaches us in.
///
/// **Two shapes, and missing the second one is a bug this cost us.** The web
/// client received the raw PostgREST JSON body as the exception's text, so
/// hunting for `{` was enough there. This client receives
/// `PostgrestException.toString()`, which carries no JSON at all —
/// `PostgrestException(message: …, code: …, details: …, hint: …)`. Reading only
/// the JSON shape meant `indexOf('{')` returned -1 for every real refusal, the
/// whole branch was skipped, and every DB-raised rule — seat caps, admin-only,
/// day protection, "this e-mail already has an account" — surfaced as the
/// caller's generic "check your connection" fallback: the product blaming the
/// user's network for a rule the server had explained perfectly well.
///
/// Found 27/08/2026 sending an invitation on a real device, and invisible to
/// the suite because the tests fed hand-written JSON — the FROZEN WEB FORMAT.
/// A ported mirror keeps its logic but not necessarily its INPUT format, and a
/// test that encodes the old platform's format passes while production never
/// matches. Both shapes are covered by tests now; keep them that way.
({String? code, String? message}) _errorFields(String raw) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try {
      final doc = jsonDecode(raw.substring(start, end + 1));
      if (doc is Map<String, dynamic>) {
        return (
          code: doc['code']?.toString(),
          message: doc['message']?.toString(),
        );
      }
    } on FormatException {
      // Braces, but not JSON — fall through to the Dart shape below.
    }
  }
  final match = _postgrestToString.firstMatch(raw);
  if (match != null) {
    return (code: match.group(2), message: match.group(1));
  }
  return (code: null, message: null);
}

/// T-66 — what to do when this function could NOT explain an error.
///
/// **Only the fallback is worth reporting, and that is the whole design.** A
/// recognized refusal is the product working: a day conflict means somebody
/// saved first, a seat cap means the plan says no, `42501` means the session
/// died. Sending those to a crash sink would bury the signal under correct
/// behaviour. The fallback is the opposite — it means the SERVER said something
/// this client does not know, and the reader is being shown "check your
/// connection" for a reason that has nothing to do with their connection.
///
/// That is not a hypothetical: on 27/08/2026 every DB-raised rule — seat caps,
/// admin-only, day protection — reached this function in a shape it did not
/// parse and surfaced as that generic sentence, with the product blaming the
/// user's network for a rule the server had explained perfectly well. Nobody
/// found it for weeks, because an unexplained error looks exactly like a bad
/// connection from the outside.
///
/// Hung off the single choke point rather than wired at ~25 call sites, for the
/// reason F-09 hangs push off the single writer: a future call site gets it for
/// free, and one that forgets is not a possibility.
typedef SaveErrorObserver = void Function(String raw, String fallback);

/// Set once at boot by the app (never in core, which stays pure and has no
/// transport). Null in every test that does not opt in.
SaveErrorObserver? saveErrorObserver;

/// Mirror of CalendarHelpers.TranslateSaveError. The two known-signature
/// messages come from the catalog since the U-13 port (the web helper never
/// extracted its literals — a residue frozen with the Blazor app); the
/// trigger-raised pass-through stays PT-BR-only because the SERVER writes
/// those sentences in PT-BR regardless of the reader.
String translateSaveError(String raw, String fallback, Localization l) {
  final fields = _errorFields(raw);
  final message = fields.message;

  if (fields.code == '23505') {
    if (message != null &&
        message.contains('swap_requests_one_pending_per_date')) {
      return l[KApp.errSwapPendingExists];
    }
    return l[KApp.errConcurrentSaveRetry];
  }

  // Trigger-raised messages arrive in PT-BR (accented) — show them.
  if (message != null &&
      message.isNotEmpty &&
      message.split('').any(_accented.contains)) {
    return message;
  }
  // Unexplained: the caller's generic sentence is about to be shown for a
  // reason nobody understands. See [saveErrorObserver].
  try {
    saveErrorObserver?.call(raw, fallback);
  } catch (_) {
    // An observer may never cost the user their error message. This function
    // has one job and it is not reporting.
  }
  return fallback;
}
