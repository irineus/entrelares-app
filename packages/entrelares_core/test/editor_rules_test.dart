/// The day editor's pure decision rules — inline in `Home.razor` on the web,
/// with no C# unit suite. These pin the port to the web's documented
/// behaviour (F-28 scenario gate, the S-09 admin confirmation).
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  group('canOfferAsActual (F-28 scenario gate)', () {
    // Family: user 1, planned parent of the day 2, current actual 3.
    bool offer(int candidate,
            {int? user = 1, int scheduled = 2, int? actual}) =>
        canOfferAsActual(
          candidateId: candidate,
          userProfileId: user,
          editingScheduledParentId: scheduled,
          existingActualParentId: actual,
        );

    test('scenario A: the day\'s planned parent may offer anyone', () {
      expect(offer(3, user: 2, scheduled: 2), isTrue);
      expect(offer(4, user: 2, scheduled: 2), isTrue);
    });

    test('scenario B: otherwise only themselves', () {
      expect(offer(1), isTrue);
      expect(offer(4), isFalse); // scenario C: a third member — forbidden
    });

    test('the planned parent stays listed (no-swap saves keep working)', () {
      expect(offer(2), isTrue);
    });

    test('the current actual stays listed (revert saves keep working)', () {
      expect(offer(3, actual: 3), isTrue);
    });

    test('no user profile loaded: only planned/current-actual candidates', () {
      expect(offer(2, user: null), isTrue);
      expect(offer(4, user: null), isFalse);
    });
  });

  group('needsAdminScheduleChangeConfirm (S-09)', () {
    test('changing the planned parent of an assigned day asks first', () {
      expect(
          needsAdminScheduleChangeConfirm(
            existingScheduledParentId: 1,
            editingScheduledParentId: 2,
            alreadyConfirmed: false,
          ),
          isTrue);
    });
    test('an unassigned day never asks', () {
      expect(
          needsAdminScheduleChangeConfirm(
            existingScheduledParentId: null,
            editingScheduledParentId: 2,
            alreadyConfirmed: false,
          ),
          isFalse);
      expect(
          needsAdminScheduleChangeConfirm(
            existingScheduledParentId: 0,
            editingScheduledParentId: 2,
            alreadyConfirmed: false,
          ),
          isFalse);
    });
    test('keeping the same parent never asks', () {
      expect(
          needsAdminScheduleChangeConfirm(
            existingScheduledParentId: 1,
            editingScheduledParentId: 1,
            alreadyConfirmed: false,
          ),
          isFalse);
    });
    test('a given confirmation is consumed by the save, not asked again', () {
      expect(
          needsAdminScheduleChangeConfirm(
            existingScheduledParentId: 1,
            editingScheduledParentId: 2,
            alreadyConfirmed: true,
          ),
          isFalse);
    });
  });

  group('swapAvailableForScheduled (F-56)', () {
    const active = MemberView(id: 1, fullName: 'Ana');
    const pending = MemberView(
        id: 2, fullName: 'Bia', isActiveMember: false, isPendingMember: true);
    const gone = MemberView(id: 3, fullName: 'Caio', isActiveMember: false);
    const members = [active, pending, gone];

    test('a pending planned parent has nobody to approve — no workflow', () {
      expect(swapAvailableForScheduled(2, members), isFalse);
    });
    test('an active planned parent keeps the workflow', () {
      expect(swapAvailableForScheduled(1, members), isTrue);
    });
    test('a departed planned parent is the S-11 ghost, not this rule', () {
      expect(swapAvailableForScheduled(3, members), isTrue);
    });
    test('no planned parent, or an unknown one, never blocks', () {
      expect(swapAvailableForScheduled(null, members), isTrue);
      expect(swapAvailableForScheduled(0, members), isTrue);
      expect(swapAvailableForScheduled(99, members), isTrue);
    });
  });

  group('daySheetOpening (U-56)', () {
    test('a day the reader can change, today or ahead, opens the editor', () {
      final o = daySheetOpening(canSave: true, isEmptyDay: false, isPast: false);
      expect(o, DaySheetOpening.edit);
      expect(o.opensEditor, isTrue);
    });
    test('an empty day the reader can plan opens the editor — past included '
        '(the admin mode is on, and there is nothing to summarize)', () {
      expect(daySheetOpening(canSave: true, isEmptyDay: true, isPast: false),
          DaySheetOpening.plan);
      expect(daySheetOpening(canSave: true, isEmptyDay: true, isPast: true),
          DaySheetOpening.plan);
    });
    test('a past assigned day stays a summary even under the admin mode — '
        'the relato is its primary (F-67)', () {
      final o = daySheetOpening(canSave: true, isEmptyDay: false, isPast: true);
      expect(o, DaySheetOpening.view);
      expect(o.opensEditor, isFalse);
    });
    test('a day nothing can be saved on is always the summary', () {
      for (final empty in [true, false]) {
        for (final past in [true, false]) {
          expect(
              daySheetOpening(canSave: false, isEmptyDay: empty, isPast: past),
              DaySheetOpening.view);
        }
      }
    });
    test('the wire values are the analytics tokens, and they are pinned', () {
      expect([for (final o in DaySheetOpening.values) o.wire],
          ['plan', 'edit', 'view']);
      expect([for (final r in DaySheetResult.values) r.wire],
          ['saved', 'cleared', 'swap', 'revert', 'report', 'none']);
    });
  });

  group('dayDraftChanged (U-56)', () {
    bool changed({
      int? storedScheduled = 1,
      int? storedActual,
      String? storedNotes = 'Casaco',
      String? storedHandoff = '18:00:00',
      int? scheduled = 1,
      int? actual,
      String notes = 'Casaco',
      ({int hour, int minute})? handoff = (hour: 18, minute: 0),
    }) =>
        dayDraftChanged(
          storedScheduledParentId: storedScheduled,
          storedActualParentId: storedActual,
          storedNotes: storedNotes,
          storedHandoffTime: storedHandoff,
          draftScheduledParentId: scheduled,
          draftActualParentId: actual,
          draftNotes: notes,
          draftHandoff: handoff,
        );

    test('an untouched draft is not a change', () {
      expect(changed(), isFalse);
    });
    test('each field on its own is a change', () {
      expect(changed(scheduled: 2), isTrue);
      expect(changed(actual: 2), isTrue);
      expect(changed(notes: 'Casaco azul'), isTrue);
      expect(changed(handoff: (hour: 18, minute: 30)), isTrue);
      expect(changed(handoff: null), isTrue);
      expect(changed(storedHandoff: null), isTrue);
    });
    test('normalized like the save writes it: 0 is none, the note is '
        'trimmed, the wire seconds are ignored', () {
      expect(changed(storedActual: 0, actual: null), isFalse);
      expect(changed(storedActual: null, actual: 0), isFalse);
      expect(changed(notes: '  Casaco  '), isFalse);
      expect(changed(storedNotes: null, notes: ''), isFalse);
      expect(changed(storedHandoff: '18:00'), isFalse);
      expect(changed(storedHandoff: null, handoff: null), isFalse);
    });
    test('an empty day has nothing stored: choosing a carer is the change', () {
      expect(
          changed(
              storedScheduled: 0,
              storedNotes: null,
              storedHandoff: null,
              scheduled: null,
              notes: '',
              handoff: null),
          isFalse);
      expect(
          changed(
              storedScheduled: 0,
              storedNotes: null,
              storedHandoff: null,
              scheduled: 2,
              notes: '',
              handoff: null),
          isTrue);
    });
  });
}
