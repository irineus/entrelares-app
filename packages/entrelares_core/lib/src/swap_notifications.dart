/// Composition of the workflow's in-app notifications — ported from the
/// notification blocks inside `SwapRequestService.cs` mutations. The stored
/// `title`/`message` are the PT-BR FALLBACK sentences (U-13) and must stay
/// byte-identical to what the web client writes; `params` carries VALUES only
/// — never a sentence — plus a discriminator wherever one `type` has more
/// than one wording, so the NotificationRenderer can rebuild the copy in the
/// READER's language. A null param value is dropped rather than written as
/// JSON null, so the renderer's own fallback applies.
library;

import 'calendar_rules.dart';
import 'swap_rules.dart';

/// One notification to insert. [bestEffort] marks the F-28 family-info
/// fan-out: a failed insert for one member must not fail the approval itself
/// (the two involved parties' notifications DO propagate failures, as on the
/// web).
class NotificationDraft {
  final int recipientProfileId;
  final String type;
  final String title;
  final String message;

  /// Render payload for the NotificationRenderer — nulls already dropped.
  final Map<String, String> params;
  final bool bestEffort;

  const NotificationDraft({
    required this.recipientProfileId,
    required this.type,
    required this.title,
    required this.message,
    required this.params,
    this.bestEffort = false,
  });
}

/// The stored PT-BR sentences render the date as the web does (`dd/MM/yyyy`);
/// `params.date` carries ISO so the reader's device reformats it (U-24).
String _ddMMyyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year.toString().padLeft(4, '0')}';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Map<String, String> _params(List<(String, String?)> entries) => {
      for (final (key, value) in entries) key: ?value,
    };

String? _nameOf(List<MemberView> profiles, int? id) {
  if (id == null) return null;
  for (final p in profiles) {
    if (p.id == id) return p.fullName;
  }
  return null;
}

// ── CreateSwapRequestAsync ───────────────────────────────────────────────────

/// The requester's receipt + the approver's call to action. The wording
/// depends on WHO was proposed as the actual parent — `targetIsProposed`
/// (scenario A: "que você fique responsável") vs the requester proposing
/// THEMSELVES (scenario B); inverting it inverts the request's meaning (bug
/// found in production). `params.proposed` is that same discriminator.
List<NotificationDraft> composeSwapCreated({
  required DateTime scheduleDate,
  required int requesterId,
  required String requesterName,
  required int targetId,
  required String targetName,
  required bool targetIsProposed,
  required SwapPriorityTag creationTag,
  String? requestMessage,
  required String environmentPrefix,
}) {
  final message = normalizeFreeText(requestMessage);
  final date = _ddMMyyyy(scheduleDate);
  final dateIso = _iso(scheduleDate);
  final urgentPrefix = priorityTagPrefix(creationTag);
  final tagParam = priorityTagParam(creationTag);

  final targetMessage = (targetIsProposed
          ? '$requesterName solicitou que você fique responsável pela criança no dia $date.'
          : '$requesterName solicitou ficar responsável pela criança no dia $date no seu lugar.') +
      messageSuffix(message);

  return [
    NotificationDraft(
      recipientProfileId: requesterId,
      type: 'swap_sent',
      title: '$environmentPrefix${urgentPrefix}Solicitação de troca enviada',
      message:
          'Você solicitou uma troca de guarda para o dia $date. Aguardando resposta de $targetName.',
      params: _params([
        ('date', dateIso),
        ('name', targetName),
        ('tag', tagParam),
      ]),
    ),
    NotificationDraft(
      recipientProfileId: targetId,
      type: 'swap_requested',
      title: '$environmentPrefix${urgentPrefix}Nova solicitação de troca',
      message: targetMessage,
      params: _params([
        ('date', dateIso),
        ('name', requesterName),
        ('tag', tagParam),
        ('proposed', targetIsProposed ? 'target' : 'requester'),
        ('msg', message),
      ]),
    ),
  ];
}

// ── ApproveAsync ─────────────────────────────────────────────────────────────

/// Requester (when their profile still exists), the approver's own receipt,
/// and the F-28 informational fan-out to every caregiver not involved —
/// explicit names, no "you/other" pronouns, in-app only.
List<NotificationDraft> composeSwapApproved({
  required DateTime scheduleDate,
  required int requestingProfileId,
  required int targetProfileId,
  required int proposedActualParentId,
  String? approvalNote,
  required List<MemberView> allProfiles,
  required String environmentPrefix,
}) {
  final note = normalizeFreeText(approvalNote);
  final date = _ddMMyyyy(scheduleDate);
  final dateIso = _iso(scheduleDate);
  final targetIsProposed = targetProfileId == proposedActualParentId;

  final requesterName = _nameOf(allProfiles, requestingProfileId);
  final targetName = _nameOf(allProfiles, targetProfileId);
  final proposedName = _nameOf(allProfiles, proposedActualParentId);
  final proposedParam = targetIsProposed ? 'target' : 'requester';

  return [
    if (requesterName != null)
      NotificationDraft(
        recipientProfileId: requestingProfileId,
        type: 'swap_approved',
        title: '${environmentPrefix}Troca aprovada! ✅',
        message: (targetIsProposed
                ? '${targetName ?? 'O outro responsável'} aceitou ficar com a criança no dia $date.'
                : '${targetName ?? 'O outro responsável'} aceitou que você fique com a criança no dia $date.') +
            messageSuffix(note),
        params: _params([
          ('date', dateIso),
          ('name', targetName),
          ('proposed', proposedParam),
          ('msg', note),
        ]),
      ),
    NotificationDraft(
      recipientProfileId: targetProfileId,
      type: 'swap_approved_self',
      title: '${environmentPrefix}Troca confirmada',
      message: targetIsProposed
          ? 'Você confirmou que ficará com a criança no dia $date.'
          : 'Você confirmou que ${proposedName ?? 'o outro responsável'} ficará com a criança no dia $date.',
      params: _params([
        ('date', dateIso),
        ('name', proposedName),
        ('proposed', proposedParam),
      ]),
    ),
    ..._familyInfo(
      allProfiles: allProfiles,
      requestingProfileId: requestingProfileId,
      targetProfileId: targetProfileId,
      title: '${environmentPrefix}Calendário atualizado',
      message:
          '${proposedName ?? 'Outro responsável'} ficará com a criança no dia $date '
          '(troca solicitada por ${requesterName ?? 'um responsável'} e aprovada por ${targetName ?? 'outro responsável'}).',
      params: _params([
        ('kind', 'swap'),
        ('date', dateIso),
        ('name', proposedName),
        ('requester', requesterName),
        ('approver', targetName),
      ]),
    ),
  ];
}

// ── RejectAsync ──────────────────────────────────────────────────────────────

List<NotificationDraft> composeSwapRejected({
  required DateTime scheduleDate,
  required int requestingProfileId,
  required int targetProfileId,
  String? reason,
  required List<MemberView> allProfiles,
  required String environmentPrefix,
}) {
  final date = _ddMMyyyy(scheduleDate);
  final dateIso = _iso(scheduleDate);
  final requesterName = _nameOf(allProfiles, requestingProfileId);
  final targetName = _nameOf(allProfiles, targetProfileId);

  return [
    if (requesterName != null)
      NotificationDraft(
        recipientProfileId: requestingProfileId,
        type: 'swap_rejected',
        title: '${environmentPrefix}Troca recusada ❌',
        message:
            '${targetName ?? 'O outro responsável'} recusou a troca de guarda para o dia $date.${messageSuffix(reason)}',
        params: _params([
          ('date', dateIso),
          ('name', targetName),
          // normalizeFreeText, not the raw reason: messageSuffix trims and
          // drops whitespace-only, so the payload must do the same or a blank
          // reason would render a dangling "Mensagem:" label.
          ('msg', normalizeFreeText(reason)),
        ]),
      ),
  ];
}

// ── CancelAsync ──────────────────────────────────────────────────────────────

List<NotificationDraft> composeSwapCancelled({
  required DateTime scheduleDate,
  required int targetProfileId,
  required List<MemberView> allProfiles,
  required String environmentPrefix,
}) {
  final date = _ddMMyyyy(scheduleDate);
  final dateIso = _iso(scheduleDate);
  final targetName = _nameOf(allProfiles, targetProfileId);

  return [
    if (targetName != null)
      NotificationDraft(
        recipientProfileId: targetProfileId,
        type: 'swap_cancelled',
        title: '${environmentPrefix}Solicitação cancelada',
        message:
            'A solicitação de troca para o dia $date foi cancelada pelo solicitante.',
        // `kind` because request_account_deletion writes this SAME type with
        // completely different copy ("X saiu da família e …").
        params: _params([
          ('kind', 'by_requester'),
          ('date', dateIso),
        ]),
      ),
  ];
}

// ── RequestRevertAsync ───────────────────────────────────────────────────────

List<NotificationDraft> composeRevertRequested({
  required DateTime scheduleDate,
  required int requesterId,
  required String requesterName,
  required int approverId,
  required String approverName,
  required SwapPriorityTag creationTag,
  String? requestMessage,
  required String environmentPrefix,
}) {
  final message = normalizeFreeText(requestMessage);
  final date = _ddMMyyyy(scheduleDate);
  final dateIso = _iso(scheduleDate);
  final urgentPrefix = priorityTagPrefix(creationTag);
  final tagParam = priorityTagParam(creationTag);

  return [
    NotificationDraft(
      recipientProfileId: requesterId,
      type: 'revert_sent',
      title: '$environmentPrefix${urgentPrefix}Reversão de troca solicitada',
      message:
          'Você solicitou reverter a troca de guarda do dia $date. Aguardando confirmação de $approverName.',
      params: _params([
        ('date', dateIso),
        ('name', approverName),
        ('tag', tagParam),
      ]),
    ),
    NotificationDraft(
      recipientProfileId: approverId,
      type: 'revert_requested',
      title: '$environmentPrefix${urgentPrefix}Pedido de reversão de troca',
      message:
          '$requesterName quer reverter a troca de guarda do dia $date. Você precisa confirmar.${messageSuffix(message)}',
      params: _params([
        ('date', dateIso),
        ('name', requesterName),
        ('tag', tagParam),
        ('msg', message),
      ]),
    ),
  ];
}

// ── ApproveRevertAsync ───────────────────────────────────────────────────────

List<NotificationDraft> composeRevertApproved({
  required DateTime scheduleDate,
  required int requestingProfileId,
  required int targetProfileId,
  required int proposedActualParentId,
  String? approvalNote,
  required List<MemberView> allProfiles,
  required String environmentPrefix,
}) {
  final note = normalizeFreeText(approvalNote);
  final date = _ddMMyyyy(scheduleDate);
  final dateIso = _iso(scheduleDate);

  final requesterName = _nameOf(allProfiles, requestingProfileId);
  final targetName = _nameOf(allProfiles, targetProfileId);
  // In a revert the proposed parent is the day's planned responsible being
  // restored — named in the family-info fan-out below.
  final restoredName = _nameOf(allProfiles, proposedActualParentId);

  return [
    if (requesterName != null)
      NotificationDraft(
        recipientProfileId: requestingProfileId,
        type: 'revert_approved',
        title: '${environmentPrefix}Reversão confirmada ✅',
        message:
            '${targetName ?? 'O outro responsável'} confirmou a reversão da troca do dia $date. O calendário voltou ao normal.${messageSuffix(note)}',
        params: _params([
          ('date', dateIso),
          ('name', targetName),
          ('msg', note),
        ]),
      ),
    NotificationDraft(
      recipientProfileId: targetProfileId,
      type: 'revert_approved_self',
      title: '${environmentPrefix}Reversão confirmada',
      message: 'Você confirmou a reversão da troca do dia $date.',
      params: _params([('date', dateIso)]),
    ),
    ..._familyInfo(
      allProfiles: allProfiles,
      requestingProfileId: requestingProfileId,
      targetProfileId: targetProfileId,
      title: '${environmentPrefix}Calendário atualizado',
      message:
          'A troca do dia $date foi revertida — ${restoredName ?? 'o responsável planejado'} volta a ficar com a criança.',
      params: _params([
        ('kind', 'revert'),
        ('date', dateIso),
        ('name', restoredName),
      ]),
    ),
  ];
}

// ── RejectRevertAsync ────────────────────────────────────────────────────────

List<NotificationDraft> composeRevertRejected({
  required DateTime scheduleDate,
  required int requestingProfileId,
  required int targetProfileId,
  String? reason,
  required List<MemberView> allProfiles,
  required String environmentPrefix,
}) {
  final date = _ddMMyyyy(scheduleDate);
  final dateIso = _iso(scheduleDate);
  final requesterName = _nameOf(allProfiles, requestingProfileId);
  final targetName = _nameOf(allProfiles, targetProfileId);

  return [
    if (requesterName != null)
      NotificationDraft(
        recipientProfileId: requestingProfileId,
        type: 'revert_rejected',
        title: '${environmentPrefix}Reversão recusada ❌',
        message:
            '${targetName ?? 'O outro responsável'} recusou reverter a troca do dia $date.${messageSuffix(reason)} A troca permanece ativa.',
        params: _params([
          ('date', dateIso),
          ('name', targetName),
          ('msg', normalizeFreeText(reason)),
        ]),
      ),
  ];
}

// ── CancelRevertAsync ────────────────────────────────────────────────────────

List<NotificationDraft> composeRevertCancelled({
  required DateTime scheduleDate,
  required int targetProfileId,
  required List<MemberView> allProfiles,
  required String environmentPrefix,
}) {
  final date = _ddMMyyyy(scheduleDate);
  final dateIso = _iso(scheduleDate);
  final targetName = _nameOf(allProfiles, targetProfileId);

  return [
    if (targetName != null)
      NotificationDraft(
        recipientProfileId: targetProfileId,
        type: 'revert_cancelled',
        title: '${environmentPrefix}Pedido de reversão cancelado',
        message: 'O pedido de reversão da troca do dia $date foi cancelado.',
        params: _params([('date', dateIso)]),
      ),
  ];
}

// ── F-28: informational fan-out to uninvolved caregivers ────────────────────

/// Fired only on CALENDAR-CHANGING events (approval, revert approval) —
/// requests/rejections/cancellations stay between the two involved parties.
/// No e-mail: it is awareness, not a call to action.
List<NotificationDraft> _familyInfo({
  required List<MemberView> allProfiles,
  required int requestingProfileId,
  required int targetProfileId,
  required String title,
  required String message,
  required Map<String, String> params,
}) =>
    [
      // F-56: only caregivers with an account — a pending member has no
      // session to read it in, and a departed one is out. Same predicate the
      // database's own fan-out (auto_approve_expired) applies.
      for (final member in allProfiles)
        if (member.isActiveMember &&
            member.id != requestingProfileId &&
            member.id != targetProfileId)
          NotificationDraft(
            recipientProfileId: member.id,
            type: 'swap_family_info',
            title: title,
            message: message,
            params: params,
            bestEffort: true,
          ),
    ];
