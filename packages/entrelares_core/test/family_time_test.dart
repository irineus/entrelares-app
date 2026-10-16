// T-105 — the family's clock is America/Sao_Paulo (UTC−3), whatever the
// device's zone. The instants below are what a device in Manaus (UTC−4) reads
// as its local clock, given as the UTC instant they are.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

/// A wall-clock moment in Manaus (UTC−4), as the instant it is.
DateTime manaus(int y, int mo, int d, int h, [int mi = 0]) =>
    DateTime.utc(y, mo, d, h, mi).add(const Duration(hours: 4));

void main() {
  setUp(() => FamilyTime.debugOffset = null);
  tearDown(() => FamilyTime.debugOffset = null);

  group('a device in Manaus (UTC−4)', () {
    test('at 23:30 local the family is already on the next day', () {
      final instant = manaus(2026, 10, 8, 23, 30);
      expect(FamilyTime.now(instant), DateTime(2026, 10, 9, 0, 30));
      expect(FamilyTime.today(instant), DateTime(2026, 10, 9));
    });

    test('at 22:59 local both clocks are still on the same day', () {
      final instant = manaus(2026, 10, 8, 22, 59);
      expect(FamilyTime.today(instant), DateTime(2026, 10, 8));
    });

    test("an 18:00 handoff is judged at 18:00 in Brasília — 17:00 in Manaus",
        () {
      final expiry = swapExpiry(DateTime(2026, 10, 9), '18:00');
      expect(FamilyTime.now(manaus(2026, 10, 9, 16, 59)).isBefore(expiry),
          isTrue);
      expect(FamilyTime.now(manaus(2026, 10, 9, 17, 0)).isBefore(expiry),
          isFalse,
          reason: 'the server calls it late at 17:00 Manaus time');
    });

    test('the device reads another clock: deadlines say "(horário de Brasília)"',
        () {
      expect(FamilyTime.deviceDiffers(deviceOffset: const Duration(hours: -4)),
          isTrue);
      expect(FamilyTime.deviceDiffers(deviceOffset: const Duration(hours: -3)),
          isFalse);
      final l = Localization(AppLanguage.ptBr);
      final deadline = DateTime(2026, 10, 10);
      expect(l.formatFamilyDeadline(deadline, deviceDiffers: true),
          'sábado, 10/10, à 0h (horário de Brasília)');
      expect(l.formatFamilyDeadline(deadline, deviceDiffers: false),
          'sábado, 10/10, à 0h');
      expect(
          Localization(AppLanguage.en)
              .formatFamilyDeadline(deadline, deviceDiffers: true),
          'Saturday, 10 Oct, at 12 AM (Brasília time)');
    });
  });

  test('the offset is fixed: a summer and a winter instant agree', () {
    expect(FamilyTime.now(DateTime.utc(2027, 1, 15, 12)),
        DateTime(2027, 1, 15, 9));
    expect(FamilyTime.now(DateTime.utc(2027, 7, 15, 12)),
        DateTime(2027, 7, 15, 9));
  });

  test('debugOffset moves the family clock (tests only)', () {
    FamilyTime.debugOffset = Duration.zero;
    expect(FamilyTime.now(DateTime.utc(2026, 10, 9, 1)),
        DateTime(2026, 10, 9, 1));
    expect(FamilyTime.deviceDiffers(deviceOffset: Duration.zero), isFalse);
  });
}
