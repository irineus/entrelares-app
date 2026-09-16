/// U-13 — renders a notification in the READER's language. Ported from
/// `entrelares-app` `Entrelares/Localization/NotificationRenderer.cs`.
///
/// **Why this exists.** `notifications.title`/`.message` are rendered PT-BR
/// sentences, written at INSERT time by SQL triggers and by the swap service.
/// Each row is read by SOMEONE ELSE, whose language may differ from the
/// writer's — so there is no language the writer could pick that is right.
/// The fix is to store the DATA (`params`) and build the sentence here, on
/// the reader's device.
///
/// **Legacy rows are not a special case to fear.** Every row written before
/// the item has `params = NULL`, and this returns the stored text unchanged.
/// Nothing in history is rewritten, and no backfill fabricates a translation
/// that never existed.
///
/// **Unknown types and malformed params also fall back.** A trigger shipped
/// ahead of the client, or a payload missing a field, must never blank out a
/// notification — the stored sentence is always a truthful last resort. The
/// same applies to an unknown `kind`/`tier` discriminator: it is the shape a
/// FUTURE writer takes, and guessing one of the current wordings for it would
/// state something false.
///
/// **The PT-BR catalog entries are byte-identical to the stored sentences**
/// (owner decision, Aug 2026). A Portuguese reader's history must not appear
/// to change retroactively; `notification_renderer_test.dart` keeps them from
/// drifting apart.
library;

import 'dart:convert';

import 'date_formats.dart';
import 'k.dart';
import 'localization.dart';

abstract final class NotificationRenderer {
  /// The notification's body in the reader's language, or the stored sentence
  /// when it cannot be rebuilt.
  static String message(
    String type,
    String? paramsJson,
    String storedMessage,
    Localization l,
  ) {
    final p = _parse(paramsJson);
    if (p == null) return storedMessage;

    // Values used by many branches. `name` is USER DATA (a caregiver's own
    // name) and is substituted as plain text, never translated — same rule
    // as the F-41 custom roles. Each branch supplies its OWN fallback,
    // because the stored sentences say "Outro responsável", "O outro
    // responsável" and "o responsável planejado" in different positions.
    // U-24: `params.date` is ISO 8601 since that item, so the day is stated
    // in the READER's format; `formatIsoDate` returns anything that does not
    // parse as ISO unchanged — precisely a row written before U-24.
    final isoDate = p['date'];
    final date = isoDate != null ? l.formatIsoDate(isoDate) : null;
    final kind = p['kind'];
    final name = p['name'];

    // The free text (F-44 requester message / approval note / rejection
    // reason) is the LAST placeholder of every text that accepts one — see
    // the catalog comment. Absent or blank collapses to "", so no dangling
    // "Mensagem:" label can ever render.
    final msg = p['msg'];
    final suffix = (msg == null || msg.trim().isEmpty)
        ? ''
        : l.format(K.notifRenderMsgSuffix, [msg]);

    switch (type) {
      // ── Automatic resolution ──
      // F-60: the deadline is an INSTANT, not a window. `params.deadline` is
      // the `YYYY-MM-DDTHH:MM` wall clock of `America/Sao_Paulo` the RPC
      // already computes (`expiry + 48h`); the sentence places its own
      // preposition around the two halves, so no formatter has to know how a
      // language joins a day to an hour. A row written before this item has
      // no `deadline` and renders the window-free sentence — still in the
      // READER's language, which a fallback to the stored PT-BR would not be.
      case 'auto_reminder' when date != null:
        final deadline = _parseDeadline(p['deadline']);
        if (deadline == null) return l.format(K.notifRenderAutoReminder, [date]);
        return l.format(K.notifRenderAutoReminderDeadline,
            [date, l.formatDate(deadline), l.formatTime(deadline)]);

      case 'auto_approved' when date != null:
        return l.format(
            p['role'] == 'approver'
                ? K.notifRenderAutoApprovedApprover
                : K.notifRenderAutoApprovedRequester,
            [date]);

      // ── F-28 family fan-out: FOUR wordings under one type ──
      case 'swap_family_info' when date != null:
        return switch (kind) {
          'auto_swap' => l.format(K.notifRenderFamilyAutoSwap,
              [name ?? l[K.notifRenderFbOtherCap], date]),
          'auto_revert' => l.format(K.notifRenderFamilyAutoRevert,
              [name ?? l[K.notifRenderFbPlanned], date]),
          'revert' => l.format(K.notifRenderFamilyRevert,
              [name ?? l[K.notifRenderFbPlanned], date]),
          'swap' => l.format(K.notifRenderFamilySwap, [
              name ?? l[K.notifRenderFbOtherCap],
              date,
              p['requester'] ?? l[K.notifRenderFbSomeone],
              p['approver'] ?? l[K.calOtherCaregiver],
            ]),
          _ => storedMessage,
        };

      // ── Swap workflow ──
      case 'swap_sent' when date != null && name != null:
        return l.format(K.notifRenderSwapSent, [date, name]);

      // `proposed` is the scenario-A/B discriminator. Reading it wrong
      // inverts the request's meaning — hence its own branch, not a shared
      // default.
      case 'swap_requested' when date != null:
        return l.format(
            p['proposed'] == 'target'
                ? K.notifRenderSwapRequestedTarget
                : K.notifRenderSwapRequestedRequester,
            [name ?? l[K.notifRenderFbOtherThe], date, suffix]);

      case 'swap_approved' when date != null:
        return l.format(
            p['proposed'] == 'target'
                ? K.notifRenderSwapApprovedTarget
                : K.notifRenderSwapApprovedRequester,
            [name ?? l[K.notifRenderFbOtherThe], date, suffix]);

      case 'swap_approved_self' when date != null:
        return p['proposed'] == 'target'
            ? l.format(K.notifRenderSwapApprovedSelfTarget, [date])
            : l.format(K.notifRenderSwapApprovedSelfRequester,
                [name ?? l[K.notifRenderFbOtherLower], date]);

      case 'swap_rejected' when date != null:
        return l.format(K.notifRenderSwapRejected,
            [name ?? l[K.notifRenderFbOtherThe], date, suffix]);

      // Two writers, one type: the swap service cancels a request,
      // request_account_deletion cancels it BECAUSE someone left.
      case 'swap_cancelled' when date != null:
        return switch (kind) {
          'by_requester' =>
            l.format(K.notifRenderSwapCancelledByRequester, [date]),
          'member_left' => l.format(K.notifRenderSwapCancelledMemberLeft,
              [name ?? l[K.notifRenderFbOtherCap], date]),
          _ => storedMessage,
        };

      // ── Revert workflow ──
      case 'revert_sent' when date != null && name != null:
        return l.format(K.notifRenderRevertSent, [date, name]);

      case 'revert_requested' when date != null:
        return l.format(K.notifRenderRevertRequested,
            [name ?? l[K.notifRenderFbOtherThe], date, suffix]);

      case 'revert_approved' when date != null:
        return l.format(K.notifRenderRevertApproved,
            [name ?? l[K.notifRenderFbOtherThe], date, suffix]);

      case 'revert_approved_self' when date != null:
        return l.format(K.notifRenderRevertApprovedSelf, [date]);

      case 'revert_rejected' when date != null:
        return l.format(K.notifRenderRevertRejected,
            [name ?? l[K.notifRenderFbOtherThe], date, suffix]);

      case 'revert_cancelled' when date != null:
        return l.format(K.notifRenderRevertCancelled, [date]);

      // ── Membership ──
      case 'member_joined' when name != null:
        return l.format(K.notifRenderMemberJoined, [name]);

      case 'member_returned' when name != null:
        return l.format(K.notifRenderMemberReturned, [name]);

      // ── Individual departure (S-11) ──
      case 'account_deletion':
        return switch (kind) {
          'self' => l[K.notifRenderLeaveSelf],
          'self_last' => l[K.notifRenderLeaveSelfLast],
          'other_left' => l.format(K.notifRenderLeaveOther,
              [name ?? l[K.notifRenderFbOtherCap]]),
          _ => storedMessage,
        };

      // ── Family deletion (S-11): SEVEN wordings under one type ──
      case 'family_deletion':
        return switch (kind) {
          'requested_self' when date != null =>
            l.format(K.notifRenderFamDelRequestedSelf, [date]),
          'requested_other' when date != null =>
            l.format(K.notifRenderFamDelRequestedOther,
                [name ?? l[K.notifRenderFbOtherCap], date]),
          'agreed' => l.format(
              K.notifRenderFamDelAgreed, [name ?? l[K.notifRenderFbOtherCap]]),
          'agreement_undone' => l.format(K.notifRenderFamDelAgreementUndone,
              [name ?? l[K.notifRenderFbOtherCap]]),
          'refused' => l.format(
              K.notifRenderFamDelRefused, [name ?? l[K.notifRenderFbOtherCap]]),
          'withdrawn' => l.format(K.notifRenderFamDelWithdrawn,
              [name ?? l[K.notifRenderFbOtherCap]]),
          'reminder' when date != null =>
            l.format(K.notifRenderFamDelReminder, [date]),
          _ => storedMessage,
        };

      // ── E-mail quota (F-38) ──
      case 'email_cap_reached':
        return switch (p['tier']) {
          'premium' => l[K.notifRenderEmailCapPremium],
          'free' => l[K.notifRenderEmailCapFree],
          _ => storedMessage,
        };
      case 'email_cap_last':
        return l[K.notifRenderEmailCapLast];
      case 'email_cap_80':
        return l[K.notifRenderEmailCap80];

      // ── Billing grace period (S-15) ──
      case 'billing' when kind == 'grace_warning' && date != null:
        return l.format(K.notifRenderBillingGrace, [date]);

      default:
        return storedMessage;
    }
  }

  /// F-60: `params.deadline` as the instant it claims to be, or null.
  ///
  /// The shape is `YYYY-MM-DDTHH:MM` — the wall clock of
  /// `America/Sao_Paulo`, which is where the F-24 clock runs. Every component
  /// must ROUND-TRIP: `DateTime` rolls a bad one over (`T24:99` becomes 01:39
  /// of the next day), and a deadline the reader could act on is exactly the
  /// wrong place to silently invent an hour. Null falls the caller back to the
  /// sentence with no instant in it, which is always true.
  static DateTime? _parseDeadline(String? value) {
    if (value == null) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::\d{2})?$')
        .firstMatch(value);
    if (m == null) return null;
    final parts = [for (var i = 1; i <= 5; i++) int.parse(m.group(i)!)];
    final parsed = DateTime(parts[0], parts[1], parts[2], parts[3], parts[4]);
    if (parsed.year != parts[0] ||
        parsed.month != parts[1] ||
        parsed.day != parts[2] ||
        parsed.hour != parts[3] ||
        parsed.minute != parts[4]) {
      return null;
    }
    return parsed;
  }

  /// The notification's title in the reader's language, or the stored one.
  ///
  /// The environment prefix the writers add to the stored title (e.g.
  /// "[Dev] ") is deliberately NOT reproduced: it is a deploy-time marker,
  /// not something the reader's language changes. The URGENCY prefix is the
  /// opposite case — it is content, it rides in `params.tag`, and it is
  /// translated (owner decision, Aug 2026), because dropping it would leave
  /// the English reader with less information than the Portuguese one.
  static String title(
    String type,
    String? paramsJson,
    String storedTitle,
    Localization l,
  ) {
    final p = _parse(paramsJson);
    if (p == null) return storedTitle;

    final kind = p['kind'];

    final key = switch (type) {
      'auto_reminder' => K.notifRenderTitleAutoReminder,
      'auto_approved' => K.notifRenderTitleAutoApproved,
      'swap_family_info' => K.notifRenderTitleCalendarUpdated,
      'swap_sent' => K.notifRenderTitleSwapSent,
      'swap_requested' => K.notifRenderTitleSwapRequested,
      'swap_approved' => K.notifRenderTitleSwapApproved,
      'swap_approved_self' => K.notifRenderTitleSwapApprovedSelf,
      'swap_rejected' => K.notifRenderTitleSwapRejected,
      'revert_sent' => K.notifRenderTitleRevertSent,
      'revert_requested' => K.notifRenderTitleRevertRequested,
      'revert_approved' => K.notifRenderTitleRevertApproved,
      'revert_approved_self' => K.notifRenderTitleRevertApprovedSelf,
      'revert_rejected' => K.notifRenderTitleRevertRejected,
      'revert_cancelled' => K.notifRenderTitleRevertCancelled,
      'member_joined' => K.notifRenderTitleMemberJoined,
      'member_returned' => K.notifRenderTitleMemberReturned,
      'email_cap_last' => K.notifRenderTitleEmailCapLast,
      'email_cap_80' => K.notifRenderTitleEmailCap80,
      'email_cap_reached' => switch (p['tier']) {
          'premium' => K.notifRenderTitleEmailCapPremium,
          'free' => K.notifRenderTitleEmailCapFree,
          _ => null,
        },
      // Both known kinds share one title, but the switch still reads `kind`:
      // a title must never render from a branch whose MESSAGE fell back, or
      // the reader gets an English heading over a Portuguese body.
      'swap_cancelled' => (kind == 'by_requester' || kind == 'member_left')
          ? K.notifRenderTitleSwapCancelled
          : null,
      'account_deletion' => switch (kind) {
          'self' => K.notifRenderTitleLeaveRequested,
          'self_last' => K.notifRenderTitleFamilyDeletionRequested,
          'other_left' => K.notifRenderTitleMemberLeft,
          _ => null,
        },
      'family_deletion' => switch (kind) {
          'requested_self' ||
          'requested_other' =>
            K.notifRenderTitleFamilyDeletionRequested,
          'agreed' ||
          'agreement_undone' =>
            K.notifRenderTitleFamilyDeletionAnswer,
          'refused' => K.notifRenderTitleFamilyDeletionCancelled,
          'withdrawn' => K.notifRenderTitleFamilyDeletionWithdrawn,
          'reminder' => K.notifRenderTitleFamilyDeletionNear,
          _ => null,
        },
      'billing' =>
        kind == 'grace_warning' ? K.notifRenderTitleBillingGrace : null,
      _ => null,
    };

    if (key == null) return storedTitle;

    return switch (p['tag']) {
      'urgent' => l[K.notifRenderTagUrgent] + l[key],
      'overdue' => l[K.notifRenderTagOverdue] + l[key],
      _ => l[key],
    };
  }

  /// Flat string map from the JSONB payload. Returns null for absent, blank
  /// or malformed JSON — every caller treats that as "fall back to the stored
  /// sentence".
  static Map<String, String>? _parse(String? json) {
    if (json == null || json.trim().isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final map = <String, String>{};
    for (final entry in decoded.entries) {
      // A null JSON value (e.g. a name we could not resolve) is treated as
      // absent, so the caller's own default applies.
      final value = entry.value;
      if (value == null) continue;
      map[entry.key] = value is String ? value : value.toString();
    }
    return map;
  }
}
