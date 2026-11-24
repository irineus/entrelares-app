/// T-109 — what a `push_subscriptions` row holds.
///
/// firebase_messaging 17 deprecated the FCM registration token
/// (`getToken`/`onTokenRefresh`) for the Firebase Installation ID that
/// `register()`/`onRegistered` hand out, and FCM HTTP v1 addresses the two
/// through different fields of a message (`token` / `fid`). The server reads
/// the row's `kind` to pick the field; the client says which kind it stored.
///
/// Three places carry these values, on purpose, because Deno cannot call Dart:
/// this file, the migration's CHECKs (`push_subscriptions_kind_check`,
/// `push_subscriptions_fid_shape`) and `supabase/functions/_shared/fcm.ts`
/// (`PushTargetKind`). `push_target_mirror_test` holds the three equal — a
/// drift would send an FID through the wrong field, FCM would refuse it, and
/// the server would retire a live device with every layer reporting success.
library;

/// The two kinds of push target, as stored in `push_subscriptions.kind`.
enum PushTargetKind {
  /// An FCM registration token — what every build before T-109 PR 2 stores,
  /// and the column's DEFAULT.
  token('token'),

  /// A Firebase Installation ID — what `register()`/`onRegistered` return.
  fid('fid');

  const PushTargetKind(this.wire);

  /// The value written to and read from `push_subscriptions.kind`.
  final String wire;
}

/// The pure rules about a push target.
abstract final class PushTargetRules {
  /// The shape of a Firebase Installation ID: 22 symbols of URL-safe base64
  /// whose first is `c`, `d`, `e` or `f` — the regex the Firebase JS SDK
  /// itself validates a generated FID against. A registration token is ~142
  /// characters with a `:` in it (every production row measured 24/11/2026),
  /// so the two never collide.
  static final RegExp fidShape = RegExp(r'^[cdef][A-Za-z0-9_-]{21}$');

  /// Whether [value] has the shape of an FID.
  static bool looksLikeFid(String value) => fidShape.hasMatch(value);
}
