import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import 'package:entrelares_db_contracts/models/day_notice.dart';
import '../services/custody_data_source.dart';
import '../theme/tokens.dart';
import '../widgets/app_l10n.dart';
import '../widgets/ui/ui.dart';

/// F-52 — sending an aviso de imprevisto about today.
///
/// **Every choice states its consequence** (owner, 18/09/2026). The three
/// requests do visibly different things, and one of them can hand TODAY to
/// whoever answers, with no second confirmation from the sender. Nobody can
/// consent to that by reading a four-word label, so each option carries the
/// sentence that says what will happen, under the option itself — not in a
/// tooltip, not on a help page, and not after the tap.
///
/// **An unavailable option is shown, disabled, WITH ITS REASON.** Hiding
/// "alguém pode ficar com a criança" when an estimate is set would leave the
/// sender looking for a feature they were told exists; the disabled row says
/// *why* and what to change ("escolha Sem previsão"). The two reasons are
/// different facts — a stated estimate, or the day not being yours — and they
/// read as different sentences.
///
/// Every rule here is a MIRROR: `send_day_notice` refuses the same things, and
/// this only exists so the sheet can disable rather than let the server say no.
/// Pops with the new notice's id.
Future<int?> showNoticeSheet({
  required BuildContext context,
  required CustodyDataSource dataSource,
  required int myProfileId,
  required int? dayParentId,
  required int sentToday,
}) {
  return showAppSheet<int>(
    context: context,
    builder: (context) => _NoticeSheet(
      dataSource: dataSource,
      myProfileId: myProfileId,
      dayParentId: dayParentId,
      sentToday: sentToday,
    ),
  );
}

class _NoticeSheet extends StatefulWidget {
  final CustodyDataSource dataSource;
  final int myProfileId;

  /// The effective carer of TODAY, or null on an unplanned day. Only this
  /// person may put the day on offer.
  final int? dayParentId;

  /// How many avisos this person already sent today — the cap is stated
  /// before it blocks.
  final int sentToday;

  const _NoticeSheet({
    required this.dataSource,
    required this.myProfileId,
    required this.dayParentId,
    required this.sentToday,
  });

  @override
  State<_NoticeSheet> createState() => _NoticeSheetState();
}

class _NoticeSheetState extends State<_NoticeSheet> {
  /// Keys a flow test reaches the choices by, so no finder depends on a
  /// localized label.
  static const reasonKey = Key('notice-reason');
  static const etaKey = Key('notice-eta');
  static const requestKey = Key('notice-request');

  NoticeReason _reason = NoticeReason.delay;

  /// Starts at the shortest estimate rather than at "sem previsão": the common
  /// aviso is a bounded delay, and the state that unlocks handing the day over
  /// should be chosen on purpose, never arrived at by default.
  int? _eta = noticeEtaOptions.first;

  NoticeRequest _request = NoticeRequest.info;

  final TextEditingController _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _mineToday => widget.myProfileId == widget.dayParentId;

  bool _allowed(NoticeRequest request) => noticeRequestAllowed(
        request: request,
        senderId: widget.myProfileId,
        dayParentId: widget.dayParentId,
        etaMinutes: _eta,
      );

  /// Why [NoticeRequest.keep] is not on offer, or null when it is. The two
  /// reasons are different facts and must not collapse into one sentence: an
  /// estimate is something the sender can change here and now; somebody else's
  /// day is not.
  String? _keepBlockedReason(Localization l) {
    if (_allowed(NoticeRequest.keep)) return null;
    return _mineToday
        ? l[KApp.noticeConsequenceKeepBlocked]
        : l[KApp.noticeConsequenceKeepNotMyDay];
  }

  void _setEta(int? eta) {
    setState(() {
      _eta = eta;
      // Stating an estimate takes the day off the table. Falling back to
      // `pickup` rather than to `info` keeps what the sender actually wanted —
      // help — and the disabled row says why the stronger ask went away.
      if (_request == NoticeRequest.keep && !_allowed(NoticeRequest.keep)) {
        _request = NoticeRequest.pickup;
      }
    });
  }

  Future<void> _send() async {
    if (_saving) return;
    final l = AppL10n.of(context).l;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await widget.dataSource.sendDayNotice(
        reason: _reason.wire,
        etaMinutes: _eta,
        request: _request.wire,
        note: _note.text,
      );
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      setState(() {
        _saving = false;
        _error = isSessionExpired(raw)
            ? sessionExpiredMessage(l)
            : translateSaveError(raw, l[KApp.noticeErrSend], l);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final textTheme = Theme.of(context).textTheme;
    final capReached = widget.sentToday >= noticeMaxPerSenderPerDay;

    return AppSheetFrame(
      title: l[KApp.noticeTitle],
      subtitle: l[KApp.noticeSubtitle],
      primaryLabel: l[KApp.noticeSend],
      onPrimary: capReached ? null : _send,
      secondaryLabel: l[K.commonCancel],
      onSecondary: () => Navigator.of(context).pop(),
      busy: _saving,
      error: _error,
      // The cap is said BEFORE it blocks: a limit that only announces itself
      // by refusing reads as a bug, not as a rule.
      pinnedNotice: capReached
          ? AppBanner(
              tone: context.tokens.warning,
              icon: Icons.info_outline,
              message: l.format(
                  KApp.noticeCapReached, [noticeMaxPerSenderPerDay]),
            )
          : null,
      children: [
        AppFieldLabel(l[KApp.noticeReasonLabel]),
        Wrap(
          key: reasonKey,
          spacing: Spacing.sm,
          runSpacing: Spacing.xs,
          children: [
            for (final reason in NoticeReason.values)
              ChoiceChip(
                label: Text(_reasonLabel(l, reason)),
                selected: _reason == reason,
                onSelected: _saving
                    ? null
                    : (_) => setState(() => _reason = reason),
              ),
          ],
        ),
        const SizedBox(height: Spacing.md),

        AppFieldLabel(l[KApp.noticeEtaLabel]),
        Wrap(
          key: etaKey,
          spacing: Spacing.sm,
          runSpacing: Spacing.xs,
          children: [
            for (final eta in noticeEtaOptions)
              ChoiceChip(
                label: Text(l.format(KApp.noticeEtaMinutes, [eta])),
                selected: _eta == eta,
                onSelected: _saving ? null : (_) => _setEta(eta),
              ),
            ChoiceChip(
              label: Text(l[KApp.noticeEtaNone]),
              selected: _eta == null,
              onSelected: _saving ? null : (_) => _setEta(null),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),

        AppFieldLabel(l[KApp.noticeRequestLabel]),
        Column(
          key: requestKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final request in NoticeRequest.values)
              _RequestOption(
                label: _requestLabel(l, request),
                consequence: _consequence(l, request),
                selected: _request == request,
                enabled: !_saving && _allowed(request),
                onSelected: () => setState(() => _request = request),
              ),
          ],
        ),
        const SizedBox(height: Spacing.md),

        AppTextField(
          label: l[KApp.noticeNoteLabel],
          hint: l[KApp.noticeNoteHint],
          controller: _note,
          maxLength: noticeNoteMaxLength,
          maxLines: 2,
          enabled: !_saving && !capReached,
        ),
        const SizedBox(height: Spacing.sm),

        if (!capReached)
          Text(
            l.format(KApp.noticeCapHint, [noticeMaxPerSenderPerDay]),
            style: textTheme.bodySmall?.copyWith(color: context.tokens.textMuted),
          ),
      ],
    );
  }

  /// The disabled row's sentence is the REASON it is disabled; an available
  /// one's is what will happen if it is chosen.
  String _consequence(Localization l, NoticeRequest request) =>
      switch (request) {
        NoticeRequest.info => l[KApp.noticeConsequenceInfo],
        NoticeRequest.pickup => l[KApp.noticeConsequencePickup],
        NoticeRequest.keep =>
          _keepBlockedReason(l) ?? l[KApp.noticeConsequenceKeep],
      };

  String _reasonLabel(Localization l, NoticeReason reason) => l[switch (reason) {
        NoticeReason.delay => KApp.noticeReasonDelay,
        NoticeReason.medical => KApp.noticeReasonMedical,
        NoticeReason.traffic => KApp.noticeReasonTraffic,
        NoticeReason.other => KApp.noticeReasonOther,
      }];

  String _requestLabel(Localization l, NoticeRequest request) =>
      l[switch (request) {
        NoticeRequest.info => KApp.noticeRequestInfo,
        NoticeRequest.pickup => KApp.noticeRequestPickup,
        NoticeRequest.keep => KApp.noticeRequestKeep,
      }];
}

/// Withdrawing my own open aviso.
///
/// A sheet rather than a dialog, and the question is its `confirmation:` (U-38)
/// — the finger is on the banner's action, and that is where the answer
/// belongs. It is worth asking at all because a cancellation is not free:
/// somebody may already be walking to a school, so whoever received the aviso
/// is told, and the row still counts towards the daily cap. The sheet says
/// both, because a person who learns that afterwards learns it as a surprise.
class CancelNoticeSheet extends StatefulWidget {
  final CustodyDataSource dataSource;
  final DayNotice notice;

  /// What the aviso said, so the sender confirms against the notice itself
  /// rather than against their memory of which one it was.
  final String sentence;

  const CancelNoticeSheet({
    super.key,
    required this.dataSource,
    required this.notice,
    required this.sentence,
  });

  @override
  State<CancelNoticeSheet> createState() => _CancelNoticeSheetState();
}

class _CancelNoticeSheetState extends State<CancelNoticeSheet> {
  bool _saving = false;
  String? _error;

  Future<void> _cancel() async {
    if (_saving) return;
    final l = AppL10n.of(context).l;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.dataSource.cancelDayNotice(widget.notice.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      setState(() {
        _saving = false;
        _error = isSessionExpired(raw)
            ? sessionExpiredMessage(l)
            : translateSaveError(raw, l[KApp.noticeErrCancel], l);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return AppSheetFrame(
      title: l[KApp.noticeCancel],
      busy: _saving,
      error: _error,
      confirmation: AppSheetConfirmation(
        message: l[KApp.noticeCancelConfirm],
        actions: AppActionPair(
          primaryLabel: l[KApp.noticeCancel],
          onPrimary: _cancel,
          secondaryLabel: l[KApp.noticeCancelKeep],
          onSecondary: () => Navigator.of(context).pop(false),
          busy: _saving,
        ),
      ),
      children: [
        Text(widget.sentence, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

/// One request, its consequence under it, as a single tap target.
///
/// U-32: the row is ONE semantics node — the mark, the label and the sentence
/// are one thing the eye reads, and three nodes would make a screen reader
/// announce a control with no idea what it does. The consequence is part of
/// that node, not decoration, because it is the part that carries the risk:
/// "Alguém pode ficar com a criança hoje?" announced alone tells a blind
/// reader nothing about the swap it can produce.
///
/// The mark is an `Icon`, not a `Radio`: `Radio.groupValue`/`onChanged` are
/// deprecated in favour of a `RadioGroup` ancestor, and the app lane fails on
/// an info. `inMutuallyExclusiveGroup` + `selected` is what carries the radio
/// MEANING anyway — the widget only ever drew the dot.
class _RequestOption extends StatelessWidget {
  final String label;
  final String consequence;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  const _RequestOption({
    required this.label,
    required this.consequence,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final ink = enabled ? null : tokens.textMuted;
    return MergeSemantics(
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        selected: selected,
        enabled: enabled,
        child: InkWell(
          onTap: enabled ? onSelected : null,
          borderRadius: BorderRadius.circular(Radii.md),
          child: ConstrainedBox(
            // U-32: a tap target is 48 dp even when its text is short.
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: enabled
                        ? (selected
                            ? theme.colorScheme.primary
                            : tokens.textMuted)
                        : tokens.textMuted,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style:
                                theme.textTheme.bodyMedium?.copyWith(color: ink)),
                        const SizedBox(height: Spacing.xs / 2),
                        Text(consequence,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: ink ?? tokens.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// F-52 (PR 2) — answering somebody else's open aviso.
///
/// Two answers, and they are not the same kind of act. "Vou ajudar agora"
/// tells the sender something; **"Vou ficar com a criança hoje" moves the
/// day**, through an already-approved swap, with no further confirmation from
/// anyone. That is the only tap in this product that does so, and it is only
/// reachable because the sender asked for it in writing first
/// ([NoticeRequest.keep]) — so the sentence under it names the swap, says it
/// is already approved, and says it stays in the history and can be reverted.
///
/// Pops with the outcome that was sent, so the caller toasts the right one: a
/// person who just took the day must be told that, not "resposta enviada".
Future<NoticeOutcome?> showAnswerNoticeSheet({
  required BuildContext context,
  required CustodyDataSource dataSource,
  required DayNotice notice,
  required String sentence,
}) {
  return showAppSheet<NoticeOutcome>(
    context: context,
    builder: (context) => _AnswerNoticeSheet(
      dataSource: dataSource,
      notice: notice,
      sentence: sentence,
    ),
  );
}

class _AnswerNoticeSheet extends StatefulWidget {
  final CustodyDataSource dataSource;
  final DayNotice notice;
  final String sentence;

  const _AnswerNoticeSheet({
    required this.dataSource,
    required this.notice,
    required this.sentence,
  });

  @override
  State<_AnswerNoticeSheet> createState() => _AnswerNoticeSheetState();
}

class _AnswerNoticeSheetState extends State<_AnswerNoticeSheet> {
  static const outcomeKey = Key('notice-answer-outcome');

  /// Starts on the answer that changes nothing. The one that moves a day is
  /// never the default — it is chosen, like every other irreversible thing in
  /// this product.
  NoticeOutcome _outcome = NoticeOutcome.helping;

  final TextEditingController _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// `keeping` exists only on an aviso that OFFERED the day. A pickup request
  /// asked for help now, and answering it with "fico com ela" would take
  /// something nobody put on the table.
  bool get _canKeep =>
      NoticeRequest.fromWire(widget.notice.request) == NoticeRequest.keep;

  Future<void> _send() async {
    if (_saving) return;
    final l = AppL10n.of(context).l;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.dataSource.answerDayNotice(
        noticeId: widget.notice.id,
        outcome: _outcome.wire,
        note: _note.text,
      );
      if (mounted) Navigator.of(context).pop(_outcome);
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      setState(() {
        _saving = false;
        _error = isSessionExpired(raw)
            ? sessionExpiredMessage(l)
            : translateSaveError(raw, l[KApp.noticeErrAnswer], l);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return AppSheetFrame(
      title: l[KApp.noticeAnswerTitle],
      subtitle: widget.sentence,
      primaryLabel: l[KApp.noticeAnswerSend],
      onPrimary: _send,
      secondaryLabel: l[K.commonCancel],
      onSecondary: () => Navigator.of(context).pop(),
      busy: _saving,
      error: _error,
      children: [
        Column(
          key: outcomeKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RequestOption(
              label: l[KApp.noticeAnswerHelping],
              consequence: l[KApp.noticeAnswerHelpingWhat],
              selected: _outcome == NoticeOutcome.helping,
              enabled: !_saving,
              onSelected: () =>
                  setState(() => _outcome = NoticeOutcome.helping),
            ),
            // Shown even when it is not on offer, disabled: hiding it would
            // leave the reader looking for an answer they were told exists.
            if (_canKeep)
              _RequestOption(
                label: l[KApp.noticeAnswerKeeping],
                consequence: l[KApp.noticeAnswerKeepingWhat],
                selected: _outcome == NoticeOutcome.keeping,
                enabled: !_saving,
                onSelected: () =>
                    setState(() => _outcome = NoticeOutcome.keeping),
              ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        AppTextField(
          label: l[KApp.noticeAnswerNoteLabel],
          hint: l[KApp.noticeAnswerNoteHint],
          controller: _note,
          maxLength: noticeAnswerNoteMaxLength,
          maxLines: 2,
          enabled: !_saving,
        ),
      ],
    );
  }
}
