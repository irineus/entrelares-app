/// F-68 — "Ajuda e contato": one place to ask a question, report a problem or
/// talk to the team, on BOTH sides of the login.
///
/// Why it exists: family 19 (19/09/2026) tried to record a past-day fact
/// through a channel that could not carry it, gave up twice and had nobody to
/// ask. The screen writes to `send-support-request`, which records the request
/// and e-mails the team with the person's address as Reply-To.
///
/// What it promises is what the function does:
///   * signed in, the reply goes to the ACCOUNT's address — shown, not asked;
///   * signed out, the person types it;
///   * the technical block is sent only while the box stays ticked, and the
///     preview lists exactly the map that goes (`SupportDiagnostics`);
///   * the mailto stays on screen whatever happens — the fallback when the send
///     fails, and the door for whoever prefers their own mail app.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/support_service.dart';
import '../theme/tokens.dart';
import '../widgets/app_l10n.dart';
import '../widgets/ui/ui.dart';

class HelpScreen extends StatefulWidget {
  /// The signed-in account's address, or null when nobody is signed in — which
  /// is what decides whether the e-mail field exists.
  final String? accountEmail;

  /// The block this device would send, already built for the route the person
  /// came from.
  final Map<String, String> diagnostics;

  final SendSupportRequest onSend;

  /// Leaves the screen (back to where the person came from).
  final VoidCallback onClose;

  /// Opens a `mailto:`. A seam for tests; production launches the mail app.
  final Future<void> Function(Uri uri)? openMail;

  /// T-83: reads the public settings for `support.message_max_chars`. Only a
  /// signed-in person can read them; null (signed out) keeps the seed.
  final Future<Map<String, String>> Function()? loadSettings;

  const HelpScreen({
    super.key,
    required this.accountEmail,
    required this.diagnostics,
    required this.onSend,
    required this.onClose,
    this.openMail,
    this.loadSettings,
  });

  static const Key categoryKey = ValueKey('help-category');
  static const Key messageKey = ValueKey('help-message');
  static const Key emailKey = ValueKey('help-email');
  static const Key diagnosticsKey = ValueKey('help-diagnostics');
  static const Key sendKey = ValueKey('help-send');
  static const Key mailtoKey = ValueKey('help-mailto');

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _message = TextEditingController();
  final _email = TextEditingController();
  SupportCategory _category = SupportCategory.question;
  bool _includeDiagnostics = true;
  bool _busy = false;
  bool _submitted = false;
  SupportOutcome? _failure;
  SupportResult? _sent;

  /// T-83: the operator's maximum when it could be read, the seed otherwise.
  int _maxChars = SupportRules.messageMaxChars;

  @override
  void initState() {
    super.initState();
    final load = widget.loadSettings;
    if (load != null) {
      load().then((values) {
        if (!mounted) return;
        setState(() =>
            _maxChars = PublicSettings(values).supportMessageMaxChars);
      }).catchError((_) {/* the seed stands */});
    }
  }

  @override
  void dispose() {
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  bool get _signedIn => widget.accountEmail != null;

  String get _inbox => SupportRules.inboxFor(_category);

  Future<void> _send() async {
    setState(() => _submitted = true);
    final messageOk =
        SupportRules.isValidMessage(_message.text, max: _maxChars);
    final emailOk = _signedIn || SupportRules.isValidEmail(_email.text);
    if (!messageOk || !emailOk) return;

    setState(() {
      _busy = true;
      _failure = null;
    });
    final result = await widget.onSend(SupportDraft(
      category: _category,
      message: _message.text,
      replyEmail: _signedIn ? null : _email.text,
      language: AppL10n.of(context).l.current.code,
      diagnostics: _includeDiagnostics ? widget.diagnostics : null,
    ));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.outcome == SupportOutcome.sent) {
        _sent = result;
      } else {
        _failure = result.outcome;
      }
    });
  }

  Future<void> _openMail() async {
    final uri = Uri(scheme: 'mailto', path: _inbox);
    final open = widget.openMail ??
        (u) async {
          await launchUrl(u, mode: LaunchMode.externalApplication);
        };
    await open(uri);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: l[KApp.helpBack],
          onPressed: widget.onClose,
        ),
        title: Text(l[KApp.helpTitle]),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _sent != null ? _sentView(l) : _form(l),
          ),
        ),
      ),
    );
  }

  Widget _sentView(Localization l) {
    final replyTo = _signedIn ? widget.accountEmail! : _email.text.trim();
    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        AppBanner(
          tone: context.tokens.success,
          icon: Icons.check_circle_outline,
          title: l[KApp.helpSentTitle],
          message: l.format(
              KApp.helpSentBody, ['${_sent!.requestId ?? '—'}', replyTo]),
        ),
        const SizedBox(height: Spacing.md),
        FilledButton(
          onPressed: widget.onClose,
          child: Text(l[KApp.helpBack]),
        ),
      ],
    );
  }

  String? _failureText(Localization l) => switch (_failure) {
        null || SupportOutcome.sent => null,
        SupportOutcome.rateLimited =>
          l.format(KApp.helpErrRateLimited, [_inbox]),
        SupportOutcome.sendFailed => l.format(KApp.helpErrSendFailed, [_inbox]),
        SupportOutcome.offline => l[KApp.helpErrOffline],
        SupportOutcome.invalidMessage => l.format(
            KApp.helpMessageTooShort, ['${SupportRules.messageMinChars}']),
        SupportOutcome.invalidEmail => l[KApp.helpEmailInvalid],
        SupportOutcome.failed => l.format(KApp.helpErrFailed, [_inbox]),
      };

  Widget _form(Localization l) {
    final messageError = _submitted &&
            !SupportRules.isValidMessage(_message.text, max: _maxChars)
        ? l.format(KApp.helpMessageTooShort, ['${SupportRules.messageMinChars}'])
        : null;
    final emailError =
        _submitted && !_signedIn && !SupportRules.isValidEmail(_email.text)
            ? l[KApp.helpEmailInvalid]
            : null;
    final failure = _failureText(l);
    final categories = <(SupportCategory, String)>[
      (SupportCategory.question, l[KApp.helpCatQuestion]),
      (SupportCategory.problem, l[KApp.helpCatProblem]),
      (SupportCategory.suggestion, l[KApp.helpCatSuggestion]),
      (SupportCategory.privacy, l[KApp.helpCatPrivacy]),
      (SupportCategory.other, l[KApp.helpCatOther]),
    ];
    final muted = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: context.tokens.textMuted);

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        Text(l[KApp.helpIntro]),
        const SizedBox(height: Spacing.md),
        AppFieldLabel(l[KApp.helpCategoryLabel]),
        Wrap(
          key: HelpScreen.categoryKey,
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final (value, label) in categories)
              ChoiceChip(
                label: Text(label),
                selected: _category == value,
                onSelected: _busy ? null : (_) => setState(() => _category = value),
              ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        AppTextField(
          key: HelpScreen.messageKey,
          label: l[KApp.helpMessageLabel],
          hint: l[KApp.helpMessageHint],
          controller: _message,
          maxLines: 6,
          maxLength: _maxChars,
          showCounter: true,
          enabled: !_busy,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.multiline,
          errorText: messageError,
          onChanged: (_) {
            if (_submitted) setState(() {});
          },
        ),
        const SizedBox(height: Spacing.sm),
        if (_signedIn)
          Text(l.format(KApp.helpReplyTo, [widget.accountEmail!]), style: muted)
        else
          AppTextField(
            key: HelpScreen.emailKey,
            label: l[KApp.helpEmailLabel],
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            errorText: emailError,
            onChanged: (_) {
              if (_submitted) setState(() {});
            },
          ),
        const SizedBox(height: Spacing.sm),
        CheckboxListTile(
          key: HelpScreen.diagnosticsKey,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _includeDiagnostics,
          onChanged: _busy
              ? null
              : (v) => setState(() => _includeDiagnostics = v ?? false),
          title: Text(l[KApp.helpDiagLabel]),
          subtitle: Text(l[KApp.helpDiagHelper]),
        ),
        if (_includeDiagnostics)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(l[KApp.helpDiagPreview],
                style: Theme.of(context).textTheme.bodyMedium),
            childrenPadding: const EdgeInsets.only(bottom: Spacing.sm),
            children: [
              for (final entry in widget.diagnostics.entries)
                AppListRow(
                  label: l[_diagLabel(entry.key)],
                  value: entry.value,
                ),
            ],
          ),
        if (failure != null) ...[
          const SizedBox(height: Spacing.sm),
          AppBanner(tone: context.tokens.danger, message: failure),
        ],
        const SizedBox(height: Spacing.md),
        FilledButton(
          key: HelpScreen.sendKey,
          onPressed: _busy ? null : _send,
          child: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l[KApp.helpSend]),
        ),
        const SizedBox(height: Spacing.lg),
        Text(l[KApp.helpMailtoLead], textAlign: TextAlign.center, style: muted),
        Center(
          child: TextButton(
            key: HelpScreen.mailtoKey,
            onPressed: _openMail,
            child: Text(_inbox),
          ),
        ),
      ],
    );
  }

  static String _diagLabel(String key) => switch (key) {
        'appVersion' => KApp.helpDiagVersion,
        'channel' => KApp.helpDiagChannel,
        'platform' => KApp.helpDiagPlatform,
        'language' => KApp.helpDiagLanguage,
        _ => KApp.helpDiagRoute,
      };
}
