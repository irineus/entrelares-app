/// The PostgREST row contracts of Entrelares — one class per table (plus the
/// two RPC payloads that are not tables), in pure Dart.
///
/// **Why they live outside the app.** They were written for the Flutter client
/// and stayed under `app/lib/models/` while it was their only
/// reader. T-56's port of the database gate to Dart gave them a SECOND reader
/// that must not depend on Flutter, and the shape of the answer was already on
/// record: in C# the same suite was unblocked by lifting `Entrelares.Models`
/// out of the Blazor project into `Entrelares.DbContracts` — 1.010 lines moved,
/// 221 tests carried across without a line of test rewritten. This package is
/// that move, in Dart.
///
/// **What it buys the gate.** The gate asserts against the SAME contract the
/// app reads, so a column rename cannot be green on one side and red on the
/// other — the mirror-test philosophy this product applies to catalogs, role
/// labels and e-mail date formats, applied to the wire shape itself.
///
/// The models carry no rules of their own: anything computed lives in
/// `entrelares_core`, which they compose. And nothing here writes — the
/// database ENFORCES, the client MIRRORS.
library;

export 'models/account_log.dart';
export 'models/activity_log.dart';
export 'models/app_notification.dart';
export 'models/care_schedule.dart';
export 'models/family.dart';
export 'models/family_deletion.dart';
export 'models/family_invitation.dart';
export 'models/invite_info.dart';
export 'models/member.dart';
export 'models/role.dart';
export 'models/subscription.dart';
export 'models/swap_request.dart';
