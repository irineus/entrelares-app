/// The audit-trail mirror — `AuditService.ComputeDiff`,
/// `ResolutionOriginText` (F-45) and `AccountActionLabel` (S-10), plus the
/// badge vocabulary the two timelines share. The C# has no unit suite for
/// these (they live inline in the service and in `ReportsAudit.razor`); the
/// expectations below were transcribed on 19/08/2026 and are the contract.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

const _members = [
  MemberView(id: 1, fullName: 'Ana Prado'),
  MemberView(id: 2, fullName: 'Bruno Prado'),
];

final _pt = Localization(AppLanguage.ptBr);
final _en = Localization(AppLanguage.en);

AuditLogView _log({
  Map<String, dynamic>? oldData,
  Map<String, dynamic>? newData,
  String action = 'UPDATE',
}) =>
    AuditLogView(
      id: 1,
      affectedDate: DateTime(2026, 8, 20),
      createdAtLocal: DateTime(2026, 8, 19, 10, 0),
      action: action,
      oldData: oldData,
      newData: newData,
      performedById: 1,
    );

void main() {
  group('computeAuditDiff', () {
    test('the four fields come out in the web order', () {
      final changes = computeAuditDiff(
        log: _log(
          oldData: const {
            'scheduled_parent_id': 1,
            'actual_parent_id': null,
            'handoff_time': '08:00:00',
            'notes': 'levar mochila',
          },
          newData: const {
            'scheduled_parent_id': 2,
            'actual_parent_id': 1,
            'handoff_time': '19:30:00',
            'notes': '',
          },
        ),
        profiles: _members,
        l: _pt,
      );

      expect(changes.map((c) => c.label), [
        _pt[K.auditFieldScheduledParent],
        _pt[K.auditFieldActualParent],
        _pt[K.auditFieldHandoffTime],
        _pt[K.auditFieldDayNote],
      ]);
    });

    test('parent ids resolve to names; an unknown id shows its raw value', () {
      final changes = computeAuditDiff(
        log: _log(
          oldData: const {'scheduled_parent_id': 1},
          newData: const {'scheduled_parent_id': 77},
        ),
        profiles: _members,
        l: _pt,
      );

      expect(changes.single.from, 'Ana Prado');
      expect(changes.single.to, '77');
    });

    test('an unchanged field produces no row', () {
      final changes = computeAuditDiff(
        log: _log(
          oldData: const {'scheduled_parent_id': 1, 'notes': 'igual'},
          newData: const {'scheduled_parent_id': 1, 'notes': 'igual'},
        ),
        profiles: _members,
        l: _pt,
      );
      expect(changes, isEmpty);
    });

    test('a missing key and an explicit null are the same absence', () {
      final changes = computeAuditDiff(
        log: _log(
          oldData: const {'actual_parent_id': null},
          newData: const {},
        ),
        profiles: _members,
        l: _pt,
      );
      expect(changes, isEmpty);
    });

    test('an INSERT with no old snapshot reads as a set value', () {
      final changes = computeAuditDiff(
        log: _log(
          action: 'INSERT',
          newData: const {'scheduled_parent_id': 2},
        ),
        profiles: _members,
        l: _pt,
      );
      expect(changes.single.from, isNull);
      expect(changes.single.to, 'Bruno Prado');
    });

    test('the handoff time loses its seconds; a cleared note reads "—"', () {
      final changes = computeAuditDiff(
        log: _log(
          oldData: const {'handoff_time': '08:00:00', 'notes': 'algo'},
          newData: const {'handoff_time': '9:5:00', 'notes': ''},
        ),
        profiles: _members,
        l: _pt,
      );
      expect(changes.first.from, '08:00');
      expect(changes.first.to, '09:05');
      expect(changes.last.to, '—');
    });

    test('an unparseable time passes through untouched', () {
      expect(formatAuditTime('meia-noite'), 'meia-noite');
      expect(formatAuditTime('08:00'), '08:00');
    });

    test('the labels follow the reader (U-13)', () {
      final log = _log(
        oldData: const {'notes': 'a'},
        newData: const {'notes': 'b'},
      );
      final pt = computeAuditDiff(log: log, profiles: _members, l: _pt);
      final en = computeAuditDiff(log: log, profiles: _members, l: _en);
      expect(pt.single.label, isNot(en.single.label));
    });
  });

  group('action vocabulary', () {
    test('the timeline and the document phrase the same action differently',
        () {
      expect(scheduleActionLabel('INSERT', _pt), _pt[K.auditCreatedSchedule]);
      expect(reportActionLabel('INSERT', _pt), _pt[K.pdfDocActionInsert]);
      expect(scheduleActionLabel('INSERT', _pt),
          isNot(reportActionLabel('INSERT', _pt)));
    });

    test('anything that is not INSERT/DELETE reads as an update', () {
      expect(scheduleActionLabel('UPDATE', _pt), _pt[K.auditUpdatedSchedule]);
      expect(scheduleActionLabel('TRUNCATE', _pt), _pt[K.auditUpdatedSchedule]);
      expect(scheduleActionBadge('DELETE'), AuditBadge.deleted);
      expect(scheduleActionBadge('WHATEVER'), AuditBadge.updated);
    });
  });

  group('resolutionOriginText — F-45', () {
    SwapOrigin origin(String status, String? resolvedBy) => SwapOrigin(
          requestingProfileId: 1,
          targetProfileId: 2,
          status: status,
          resolvedBy: resolvedBy,
        );

    test('the four combinations are four distinct sentences', () {
      final sentences = {
        resolutionOriginText(origin('approved', 'user'), _members, _pt),
        resolutionOriginText(origin('approved', 'system'), _members, _pt),
        resolutionOriginText(origin('revert_approved', 'user'), _members, _pt),
        resolutionOriginText(
            origin('revert_approved', 'system'), _members, _pt),
      };
      expect(sentences.length, 4);
    });

    test('a manual swap names requester and approver', () {
      final text =
          resolutionOriginText(origin('approved', 'user'), _members, _pt);
      expect(text, contains('Ana Prado'));
      expect(text, contains('Bruno Prado'));
    });

    test('F-24 auto-approval names only the requester', () {
      final text =
          resolutionOriginText(origin('approved', 'system'), _members, _pt);
      expect(text, contains('Ana Prado'));
      expect(text, isNot(contains('Bruno Prado')));
    });

    test('an unknown profile falls back to the generic caregiver wording', () {
      final text = resolutionOriginText(
        const SwapOrigin(
            requestingProfileId: 8,
            targetProfileId: 9,
            status: 'approved',
            resolvedBy: 'user'),
        _members,
        _pt,
      );
      expect(text, contains(_pt[K.auditOriginSomeCaregiver]));
      expect(text, contains(_pt[K.auditOriginOtherCaregiver]));
    });
  });

  group('accountActionLabel — S-10', () {
    test('a known action is translated', () {
      expect(accountActionLabel('admin_granted', _pt),
          _pt[K.auditActionAdminGranted]);
      expect(accountActionLabel('admin_granted', _en),
          _en[K.auditActionAdminGranted]);
    });

    test('an UNKNOWN action shows its raw key — the record, not an invention',
        () {
      expect(accountActionLabel('something_new', _pt), 'something_new');
    });

    test('the badge vocabulary maps the money and the shield rows', () {
      expect(accountActionBadge('invitation_created').$1, AuditBadge.created);
      expect(accountActionBadge('invitation_revoked').$1, AuditBadge.deleted);
      expect(accountActionBadge('admin_revoked').$2, '🛡️');
      expect(accountActionBadge('plan_free_overdue').$1, AuditBadge.deleted);
      expect(accountActionBadge('plan_premium_avulso').$2, '💳');
      expect(accountActionBadge('mystery').$2, '✏️');
    });

    test('only role_changed translates its stored value', () {
      String translate(String role) => 'ROLE:$role';
      expect(accountLogValueDisplay('role_changed', 'Mother', translate),
          'ROLE:Mother');
      expect(accountLogValueDisplay('name_changed', 'Ana', translate), 'Ana');
      expect(accountLogValueDisplay('role_changed', null, translate), isNull);
    });
  });

  group('trialEndedEntry — F-58 QA 2', () {
    final now = DateTime.utc(2026, 8, 19, 12);

    test('a trial that ran out becomes an entry at the moment it ended', () {
      final ended = DateTime.utc(2026, 8, 1);
      expect(
        trialEndedEntry(
            plan: 'free',
            trialEndsAtUtc: ended,
            compPremiumAtUtc: null,
            nowUtc: now),
        ended,
      );
    });

    test('a running trial has not ended', () {
      expect(
        trialEndedEntry(
            plan: 'free',
            trialEndsAtUtc: DateTime.utc(2026, 9, 1),
            compPremiumAtUtc: null,
            nowUtc: now),
        isNull,
      );
    });

    test('premium or comped families never see the loss narrated', () {
      final ended = DateTime.utc(2026, 8, 1);
      expect(
        trialEndedEntry(
            plan: 'premium',
            trialEndsAtUtc: ended,
            compPremiumAtUtc: null,
            nowUtc: now),
        isNull,
      );
      expect(
        trialEndedEntry(
            plan: 'free',
            trialEndsAtUtc: ended,
            compPremiumAtUtc: DateTime.utc(2026, 7, 1),
            nowUtc: now),
        isNull,
      );
    });

    test('a family that never had a trial has no entry', () {
      expect(
        trialEndedEntry(
            plan: 'free',
            trialEndsAtUtc: null,
            compPremiumAtUtc: null,
            nowUtc: now),
        isNull,
      );
    });
  });

  // F-61 — the dated facts beyond the diff. The trigger stamps them; this is
  // the ONLY place that turns them into sentences, for the timeline and the
  // PDF alike.
  group('F-61 authorship', () {
    AuditLogView stamped({
      AuditContext? context,
      Map<String, dynamic>? newData,
      Map<String, dynamic>? oldData,
      String action = 'INSERT',
      int? performedById = 1,
    }) =>
        AuditLogView(
          id: 7,
          affectedDate: DateTime(2026, 9, 12),
          createdAtLocal: DateTime(2026, 9, 9, 10, 0),
          action: action,
          oldData: oldData,
          newData: newData,
          performedById: performedById,
          context: context,
        );

    test('AuditContext.parse reads booleans and treats the rest as unknown',
        () {
      final ctx = AuditContext.parse({
        'scheduled_parent_has_account': false,
        'actual_parent_has_account': 'yes', // not a boolean → unknown
        'admin_override': true,
      })!;
      expect(ctx.scheduledParentHasAccount, isFalse);
      expect(ctx.actualParentHasAccount, isNull);
      expect(ctx.actorIsAdmin, isNull, reason: 'a stripped key is unknown');
      expect(ctx.adminOverride, isTrue);

      expect(AuditContext.parse(null), isNull);
      expect(AuditContext.parse('junk'), isNull);
      expect(AuditContext.parse(const []), isNull);
    });

    test('a row older than F-61 says nothing — no context, no guessing', () {
      expect(
        authorshipLines(
          log: stamped(newData: const {'scheduled_parent_id': 2}),
          profiles: _members,
          l: _pt,
        ),
        isEmpty,
      );
    });

    test('an assignee without an account is named, in the reader language',
        () {
      final log = stamped(
        context: const AuditContext(
            scheduledParentHasAccount: false, actorIsAdmin: true,
            adminOverride: false),
        newData: const {'scheduled_parent_id': 2},
      );

      expect(authorshipLines(log: log, profiles: _members, l: _pt),
          ['Bruno Prado ainda não tinha conta no aplicativo neste momento.']);
      expect(authorshipLines(log: log, profiles: _members, l: _en),
          ['Bruno Prado did not yet have an account in the app at this moment.']);
    });

    test('the same person planned AND real is named once; two people, twice',
        () {
      const ctx = AuditContext(
          scheduledParentHasAccount: false, actualParentHasAccount: false);

      expect(
        authorshipLines(
          log: stamped(
              context: ctx,
              newData: const {'scheduled_parent_id': 2, 'actual_parent_id': 2}),
          profiles: _members,
          l: _pt,
        ),
        hasLength(1),
      );
      expect(
        authorshipLines(
          log: stamped(
              context: ctx,
              newData: const {'scheduled_parent_id': 2, 'actual_parent_id': 1}),
          profiles: _members,
          l: _pt,
        ),
        [
          'Bruno Prado ainda não tinha conta no aplicativo neste momento.',
          'Ana Prado ainda não tinha conta no aplicativo neste momento.',
        ],
      );
    });

    test('an assignee WITH an account (or unknown) yields no sentence', () {
      for (final has in [true, null]) {
        expect(
          authorshipLines(
            log: stamped(
                context: AuditContext(scheduledParentHasAccount: has),
                newData: const {'scheduled_parent_id': 2}),
            profiles: _members,
            l: _pt,
          ),
          isEmpty,
        );
      }
    });

    test('a DELETE reads the assignee from the row that went', () {
      expect(
        authorshipLines(
          log: stamped(
              action: 'DELETE',
              context: const AuditContext(
                  scheduledParentHasAccount: false, adminOverride: true),
              oldData: const {'scheduled_parent_id': 2}),
          profiles: _members,
          l: _pt,
        ),
        [
          'Bruno Prado ainda não tinha conta no aplicativo neste momento.',
          'Alteração direta pela pessoa administradora (Ana Prado).',
        ],
      );
    });

    test('the admin override names the actor; false and unknown are silent',
        () {
      expect(
        authorshipLines(
          log: stamped(
              context: const AuditContext(adminOverride: true),
              newData: const {'scheduled_parent_id': 1}),
          profiles: _members,
          l: _en,
        ),
        ['Direct change by the family administrator (Ana Prado).'],
      );
      for (final override in [false, null]) {
        expect(
          authorshipLines(
            log: stamped(
                context: AuditContext(adminOverride: override),
                newData: const {'scheduled_parent_id': 1}),
            profiles: _members,
            l: _pt,
          ),
          isEmpty,
        );
      }
    });

    test('an unknown actor id falls back to the generic caregiver', () {
      expect(
        authorshipLines(
          log: stamped(
              performedById: 99,
              context: const AuditContext(adminOverride: true),
              newData: const {'scheduled_parent_id': 1}),
          profiles: _members,
          l: _pt,
        ),
        ['Alteração direta pela pessoa administradora (um responsável).'],
      );
    });

    test('no sentence qualifies conduct — both catalogs, pinned', () {
      // The owner's rule: a dated fact, never a judgement. The words below
      // are the ones a qualifier would use; none may enter these entries.
      const banned = ['sozinh', 'sem consultar', 'alone', 'without consult',
        'unilateral', 'decidiu', 'decided'];
      for (final l in [_pt, _en]) {
        for (final key in [
          K.auditAuthorshipNoAccount,
          K.auditAuthorshipAdminOverride,
        ]) {
          final text = l[key].toLowerCase();
          for (final word in banned) {
            expect(text, isNot(contains(word)), reason: '$key / $word');
          }
        }
      }
    });
  });
}
