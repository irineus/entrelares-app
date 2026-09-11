import 'dart:convert';

import 'package:entrelares_core/entrelares_core.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'custody_data_source.dart';

/// F-17/S-13 — the LGPD data export. Port of `Entrelares/Services/ExportService.cs`.
///
/// Two properties make this file worth reading twice:
///
/// * **The JSON KEYS stay English.** The payload is a schema, not prose — a
///   file whose field names changed with the reader's language would be
///   useless to whoever receives it. Only `lgpdNote` follows the language.
/// * **Notification text is rendered through the same [NotificationRenderer]
///   the Histórico tab uses**, so the export and the app can never disagree
///   about what an event said.
///
/// Assembly is pure on purpose: the payload can be asserted without a backend,
/// which is the only practical way to keep an LGPD record honest over time.
abstract final class ExportService {
  /// `guarda-compartilhada-dados-20260819-143012.json`. The timestamp is
  /// LOCAL, as in the web — it names the moment the person pressed the button.
  static String fileName(Localization l, DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return '${l[K.exportFileNamePrefix]}-$stamp.json';
  }

  /// The published shape. [generatedAtUtc] is stamped by the caller so the
  /// payload is deterministic under test.
  static Map<String, dynamic> buildPayload({
    required Member me,
    required Family? family,
    required List<Member> members,
    required List<Role> roles,
    required ExportBundle bundle,
    required Localization l,
    required String appVersion,
    required DateTime generatedAtUtc,
  }) {
    String memberName(int? profileId) {
      if (profileId == null) return '';
      for (final member in members) {
        if (member.id == profileId) return member.fullName;
      }
      return '';
    }

    String roleLabel(int? roleId) {
      if (roleId == null) return '';
      for (final role in roles) {
        if (role.id == roleId) {
          return RoleCatalog.translate(role.roleName, l.current);
        }
      }
      return '';
    }

    return {
      'exportInfo': {
        'generatedAtUtc': generatedAtUtc.toIso8601String(),
        'appVersion': appVersion,
        'requestedBy': me.fullName,
        'lgpdNote': l[K.exportLgpdNote],
      },
      'profile': {
        'fullName': me.fullName,
        'email': me.email ?? '',
        'role': roleLabel(me.roleId),
        'isAdmin': me.isAdmin,
      },
      'family': {
        'name': family?.name ?? '',
        'members': [
          for (final member in members)
            {
              'fullName': member.fullName,
              'email': member.email ?? '',
              'role': roleLabel(member.roleId),
              'isAdmin': member.isAdmin,
            },
        ],
      },
      'schedules': [
        for (final day in bundle.schedules)
          {
            // U-24: the wire format is the export format — ISO, always.
            'date': CareSchedule.isoDate(day.scheduleDate),
            'plannedParent': memberName(day.scheduledParentId),
            'actualParent': memberName(day.actualParentId),
            'handoffTime': day.handoffTime ?? '',
            'notes': day.notes ?? '',
          },
      ],
      'swapRequests': [
        for (final swap in bundle.swapRequests)
          {
            'date': CareSchedule.isoDate(swap.scheduleDate),
            'requestedBy': memberName(swap.requestingProfileId),
            'approver': memberName(swap.targetProfileId),
            'proposedParent': memberName(swap.proposedActualParentId),
            'status': swap.status,
            'rejectionReason': swap.rejectionReason ?? '',
            'resolvedBy': swap.resolvedBy ?? '',
            'createdAt': swap.createdAt ?? '',
            'resolvedAt': swap.resolvedAt ?? '',
          },
      ],
      'notifications': [
        for (final notification in bundle.notifications)
          {
            // The SAME renderer the Histórico tab uses — stored title/message
            // are the fallback for rows written before the params existed.
            'title': NotificationRenderer.title(notification.type,
                notification.paramsJson, notification.title, l),
            'message': NotificationRenderer.message(notification.type,
                notification.paramsJson, notification.message, l),
            'isRead': notification.isRead,
            'createdAt': notification.createdAt ?? '',
          },
      ],
      'auditLog': [
        for (final row in bundle.activityLog)
          {
            'action': row['action'] ?? '',
            'affectedDate': row['affected_date'] ?? '',
            'performedBy': memberName(row['performed_by'] as int?),
            'createdAt': row['created_at'] ?? '',
          },
      ],
    };
  }

  /// The file's bytes. Indented because a person may well open it in a text
  /// editor, and unescaped because the default JSON encoder would turn every
  /// accented name into `ã`.
  static String encode(Map<String, dynamic> payload) =>
      const JsonEncoder.withIndent('  ').convert(payload);
}
