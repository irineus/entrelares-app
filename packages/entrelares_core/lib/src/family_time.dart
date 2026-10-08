/// T-105 — the family's clock.
///
/// Every day rule on the server reads `(now() AT TIME ZONE 'America/Sao_Paulo')`:
/// which day is "today" (past days are immutable), when a handoff is urgent or
/// late, when a pending request is approved by itself. The app read the
/// DEVICE's clock for the same questions, so for a family in Manaus (UTC−4)
/// or a parent travelling, between 00:00 in Brasília and local midnight the
/// app offered yesterday as editable and the save failed with "Dias passados
/// não podem ser alterados", and URGENTE/ATRASADO and the 48 h deadline fired
/// an hour off from what the screen said (T-103 audit, 04/10/2026).
///
/// São Paulo is UTC−3 with no daylight saving since 2019 (Decree 9.772), so
/// the zone is a fixed offset and needs no tz database. The values returned
/// are NAIVE wall-clock DateTimes — their fields are São Paulo's — which is
/// the shape every rule here already compares (`swapExpiry`, the priority
/// tag, `scheduleDate`).
library;

abstract final class FamilyTime {
  /// America/Sao_Paulo since 2019.
  static const Duration offset = Duration(hours: -3);

  /// Tests only: the offset the family clock uses instead of [offset]. The
  /// app's widget tests set it to the HOST's offset, so fixtures that build
  /// "today" from `DateTime.now()` keep meaning the app's today on a UTC CI
  /// runner. Null in the app.
  static Duration? debugOffset;

  static Duration get _offset => debugOffset ?? offset;

  /// The family's wall clock at [instant] (default: now).
  static DateTime now([DateTime? instant]) {
    final u = (instant ?? DateTime.now()).toUtc().add(_offset);
    return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second,
        u.millisecond);
  }

  /// The family's calendar day at [instant], at midnight.
  static DateTime today([DateTime? instant]) {
    final n = now(instant);
    return DateTime(n.year, n.month, n.day);
  }

  /// Whether a device whose zone sits at [deviceOffset] (default: this
  /// device's, at [instant]) reads a different clock from the family's — the
  /// condition for saying "(horário de Brasília)" beside a deadline.
  static bool deviceDiffers({Duration? deviceOffset, DateTime? instant}) =>
      (deviceOffset ?? (instant ?? DateTime.now()).toLocal().timeZoneOffset) !=
      _offset;
}
