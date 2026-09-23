/// T-78 — the server-side "is this member still using the app, and where?".
///
/// The app tells the database, once per day and per channel, that its signed-in
/// member used it (`touch_activity`). Nothing here reads it back: the table is
/// service-role only, because between co-parents "when did the other one last
/// open the app" is surveillance (§6 of the policy). These rules only decide
/// WHAT the app says and HOW OFTEN.
library;

/// Where the app is running, in the words the `member_activity_days.channel`
/// CHECK accepts. `activity_channel_mirror_test` reads that CHECK: the call is
/// fire-and-forget, so a value the server refused would vanish in silence.
///
/// Deliberately NOT the Umami `channel` (`web`/`store`, T-37): that one splits
/// the two BILLING rails and its series predate this item, so it stays; the
/// web's installed/tab split rides on Umami as a separate `display` prop.
enum ActivityChannel {
  android('android'),
  web('web'),
  webInstalled('web-installed');

  const ActivityChannel(this.wire);

  /// The exact string sent to `touch_activity(p_channel)`.
  final String wire;
}

abstract final class ActivityRules {
  /// How long a row lives, in days. The number is the database's
  /// (`purge_old_member_activity`) and the policy's (§11 of privacidade.html);
  /// kept here only so the mirror can hold the three together.
  static const retentionDays = 400;

  /// The channel this process reports. The Android build is the only native
  /// one (T-40's iOS waits for revenue); on the web, "installed" is the same
  /// fact the U-51 install hint reads (`InstallHintRules.isStandalone`).
  static ActivityChannel channel({required bool isWeb, required bool standalone}) {
    if (!isWeb) return ActivityChannel.android;
    return standalone ? ActivityChannel.webInstalled : ActivityChannel.web;
  }

  /// The throttle key: the device's LOCAL calendar day, `yyyy-MM-dd`.
  ///
  /// The server stamps the day in America/Sao_Paulo; the device may be
  /// elsewhere. The two only disagree around midnight, and the cost of that is
  /// one extra call the server answers with `ON CONFLICT DO NOTHING` — never a
  /// missing day, because a new local day always asks again.
  static String dayKey(DateTime local) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-${two(local.day)}';
  }

  /// Whether to call the server now. [lastTouchedDay] is the last day a call
  /// SUCCEEDED in this process — a failed call (no signal, T-18) leaves it
  /// untouched, so the next open or tap asks again; nothing is queued.
  static bool shouldTouch({required String? lastTouchedDay, required DateTime now}) =>
      lastTouchedDay != dayKey(now);
}
