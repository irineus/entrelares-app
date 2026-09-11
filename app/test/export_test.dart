// F-17/S-13 — the LGPD export payload.
//
// Asserted as a SHAPE, not a snapshot: the keys are the contract (they stay
// English in every language, because the file is a schema and not prose), and
// every category the web publishes has to be present. An export silently
// missing a category would be a legal defect that no screen would ever show.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/app_notification.dart';
import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';
import 'package:entrelares_app/services/custody_data_source.dart';
import 'package:entrelares_app/services/export_service.dart';

const ana = Member(
    id: 1,
    fullName: 'Ana Souza',
    userId: 'u1',
    isAdmin: true,
    roleId: 1,
    email: 'ana@example.com');
const bruno = Member(
    id: 2, fullName: 'Bruno Lima', userId: 'u2', roleId: 2, email: 'bruno@x.com');

const roleMother = Role(id: 1, roleName: 'mother');
const roleFather = Role(id: 2, roleName: 'father');

final generatedAt = DateTime.utc(2026, 8, 19, 15, 30);

Map<String, dynamic> payload({
  Localization? l,
  ExportBundle bundle = const ExportBundle(),
}) =>
    ExportService.buildPayload(
      me: ana,
      family: const Family(id: 7, name: 'Souza', plan: 'free'),
      members: const [ana, bruno],
      roles: const [roleMother, roleFather],
      bundle: bundle,
      l: l ?? Localization(AppLanguage.ptBr),
      appVersion: '0.2.17+19',
      generatedAtUtc: generatedAt,
    );

void main() {
  group('shape', () {
    test('carries every category the web publishes', () {
      expect(
          payload().keys,
          containsAll([
            'exportInfo',
            'profile',
            'family',
            'schedules',
            'swapRequests',
            'notifications',
            'auditLog',
          ]));
    });

    test('exportInfo stamps the moment, the build and who asked', () {
      final info = payload()['exportInfo'] as Map<String, dynamic>;

      expect(info['generatedAtUtc'], generatedAt.toIso8601String());
      expect(info['appVersion'], '0.2.17+19');
      expect(info['requestedBy'], 'Ana Souza');
      expect(info['lgpdNote'], isNotEmpty);
    });

    test('the family block lists every member with their role', () {
      final family = payload()['family'] as Map<String, dynamic>;
      final members = family['members'] as List;

      expect(family['name'], 'Souza');
      expect(members, hasLength(2));
      expect((members.first as Map)['role'], 'Mãe');
      expect((members.last as Map)['role'], 'Pai');
    });
  });

  group('rows', () {
    test('a day resolves both parents by name and keeps the ISO date', () {
      final bundle = ExportBundle(schedules: [
        CareSchedule(
          id: 1,
          scheduleDate: DateTime(2026, 8, 19),
          scheduledParentId: 1,
          actualParentId: 2,
          handoffTime: '18:00:00',
          notes: 'levar mochila',
          revision: 1,
          revisionToken: 't',
        ),
      ]);

      final day = (payload(bundle: bundle)['schedules'] as List).single as Map;

      expect(day['date'], '2026-08-19');
      expect(day['plannedParent'], 'Ana Souza');
      expect(day['actualParent'], 'Bruno Lima');
      expect(day['handoffTime'], '18:00:00');
      expect(day['notes'], 'levar mochila');
    });

    test('an unassigned actual parent reads as empty, never as an id', () {
      final bundle = ExportBundle(schedules: [
        CareSchedule(
          id: 1,
          scheduleDate: DateTime(2026, 8, 19),
          scheduledParentId: 1,
          revision: 1,
          revisionToken: 't',
        ),
      ]);

      final day = (payload(bundle: bundle)['schedules'] as List).single as Map;

      expect(day['actualParent'], '');
    });

    test('a swap request names requester, approver and proposed parent', () {
      final bundle = ExportBundle(swapRequests: [
        SwapRequest(
          id: 5,
          scheduleDate: DateTime(2026, 8, 20),
          requestingProfileId: 2,
          targetProfileId: 1,
          proposedActualParentId: 2,
          status: 'approved',
          revertNotes: false,
          resolvedBy: 'user',
          createdAt: '2026-08-18T10:00:00Z',
          resolvedAt: '2026-08-18T11:00:00Z',
        ),
      ]);

      final swap =
          (payload(bundle: bundle)['swapRequests'] as List).single as Map;

      expect(swap['date'], '2026-08-20');
      expect(swap['requestedBy'], 'Bruno Lima');
      expect(swap['approver'], 'Ana Souza');
      expect(swap['proposedParent'], 'Bruno Lima');
      expect(swap['status'], 'approved');
      expect(swap['resolvedBy'], 'user');
    });

    test('the audit trail rides through untyped but complete', () {
      const bundle = ExportBundle(activityLog: [
        {
          'action': 'schedule_updated',
          'affected_date': '2026-08-19',
          'performed_by': 2,
          'created_at': '2026-08-18T10:00:00Z',
        },
      ]);

      final row = (payload(bundle: bundle)['auditLog'] as List).single as Map;

      expect(row['action'], 'schedule_updated');
      expect(row['affectedDate'], '2026-08-19');
      expect(row['performedBy'], 'Bruno Lima');
    });
  });

  group('U-13', () {
    const notified = ExportBundle(notifications: [
      AppNotification(
        id: 1,
        recipientProfileId: 1,
        type: 'swap_requested',
        title: 'título armazenado',
        message: 'mensagem armazenada',
        isRead: false,
        createdAt: '2026-08-18T10:00:00Z',
      ),
    ]);

    test('a notification without params falls back to the stored sentence', () {
      final row =
          (payload(bundle: notified)['notifications'] as List).single as Map;

      expect(row['title'], 'título armazenado');
      expect(row['message'], 'mensagem armazenada');
    });

    test('the KEYS stay English for an English reader — the file is a schema, '
        'not prose', () {
      final english = payload(l: Localization(AppLanguage.en));

      expect(english.keys, contains('swapRequests'));
      expect((english['profile'] as Map).keys, contains('fullName'));
    });

    test('but the LGPD note and the role labels follow the reader', () {
      final english = payload(l: Localization(AppLanguage.en));
      final ptBr = payload();

      expect((english['exportInfo'] as Map)['lgpdNote'],
          isNot((ptBr['exportInfo'] as Map)['lgpdNote']));
      expect((english['profile'] as Map)['role'], 'Mother');
    });
  });

  group('file', () {
    test('the name carries the local timestamp and the .json extension', () {
      final name = ExportService.fileName(
          Localization(AppLanguage.ptBr), DateTime(2026, 8, 19, 14, 30, 12));

      expect(name, 'guarda-compartilhada-dados-20260819-143012.json');
    });

    test('the English reader gets the English prefix', () {
      final name = ExportService.fileName(
          Localization(AppLanguage.en), DateTime(2026, 8, 19, 14, 30, 12));

      expect(name, startsWith('guarda-compartilhada-data-'));
    });

    test('the encoding is indented and leaves accents alone', () {
      final json = ExportService.encode(payload());

      expect(json, contains('\n  "exportInfo"'));
      expect(json, contains('Ana Souza'));
      expect(json, isNot(contains(r'\u00')));
    });
  });
}
