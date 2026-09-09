import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../deep_link_urls.dart';
import 'package:entrelares_db_contracts/models/invite_info.dart';
import '../services/analytics_service.dart';
import '../services/custody_data_source.dart';
import '../theme/tokens.dart';
import '../widgets/app_l10n.dart';
import '../widgets/ui/ui.dart';

/// `/onboarding` (F-57) — where a deferred (social-login) session becomes a
/// member.
///
/// The register screen's two branches, minus what the OAuth session already
/// settled: the e-mail belongs to the provider account and there is no
/// password. The branch is decided the same way — by an invitation — except
/// the token arrives through [SharedPreferences] instead of the URL: it was
/// stashed by the register screen right before the OAuth redirect, because a
/// browser round-trip keeps no widget state.
///
/// S-13 moved here for this path: the consent the register form collects at
/// sign-up is collected on this screen instead, and the server stamps it only
/// after validating the policy version (S-15 posture) — so the deferred
/// account cannot slip past the declaration the form path signs.
class OauthOnboardingScreen extends StatefulWidget {
  /// Where the register screen parks the invite token across the OAuth
  /// redirect, and the only reader of it.
  static const String pendingInviteTokenKey = 'pending_invite_token';

  final CustodyDataSource dataSource;
  final AnalyticsService? analytics;
  final SharedPreferences prefs;

  /// "Entrar com outra conta" — this session is confined here, so signing out
  /// is the only other door.
  final Future<void> Function() onSignOut;

  /// The profile now exists — `main.dart` re-resolves the phase and routes.
  final Future<void> Function() onCompleted;

  const OauthOnboardingScreen({
    super.key,
    required this.dataSource,
    this.analytics,
    required this.prefs,
    required this.onSignOut,
    required this.onCompleted,
  });

  @override
  State<OauthOnboardingScreen> createState() => _OauthOnboardingScreenState();
}

class _OauthOnboardingScreenState extends State<OauthOnboardingScreen> {
  final _fullName = TextEditingController();
  final _familyName = TextEditingController();

  String? _role;
  bool _acceptedTerms = false;

  bool _loadingInvite = false;
  bool _inviteInvalid = false;
  String? _inviteToken;
  InviteInfo? _invite;

  bool _busy = false;

  /// The catalog KEY of the current error, so a language switch re-renders it.
  String? _errorKey;

  /// A message the SERVER wrote (PT-BR) — shown verbatim, never collapsed.
  String? _errorText;

  /// S-11: set while the visitor is being asked to confirm leaving another
  /// family behind — same dialog the register screen shows.
  bool _migrationWarning = false;
  String? _migrationFamilyName;

  bool get _isInvited => _invite != null;

  /// Read once: the session cannot change while this screen is up (the only
  /// way out of it is signing out, which unmounts the screen).
  String? _sessionEmail;

  @override
  void initState() {
    super.initState();
    _sessionEmail = widget.dataSource.sessionEmail();
    _fullName.text = widget.dataSource.sessionDisplayName() ?? '';
    final token =
        widget.prefs.getString(OauthOnboardingScreen.pendingInviteTokenKey);
    if (token != null && token.trim().isNotEmpty) {
      _inviteToken = token.trim();
      _loadingInvite = true;
      _resolveInvite(token.trim());
    }
  }

  @override
  void dispose() {
    _fullName.dispose();
    _familyName.dispose();
    super.dispose();
  }

  Future<void> _resolveInvite(String token) async {
    final info = await widget.dataSource.fetchInviteInfo(token);
    if (!mounted) return;
    setState(() {
      _loadingInvite = false;
      if (info == null) {
        // The stash outlived the invitation (expired, revoked, already used).
        // The founder form stays available below — being locked out of the
        // whole product over a dead token would be worse.
        _inviteInvalid = true;
        return;
      }
      _invite = info;
      // F-56: the admin's name for the placeholder fills an EMPTY field only —
      // the provider's display name, when there is one, is the person's own.
      final suggested = info.inviteeName?.trim() ?? '';
      if (_fullName.text.trim().isEmpty && suggested.isNotEmpty) {
        _fullName.text = suggested;
      }
    });
  }

  Future<void> _clearPendingToken() async {
    try {
      await widget.prefs
          .remove(OauthOnboardingScreen.pendingInviteTokenKey);
    } catch (_) {
      // Best-effort: a stale token resolves to the invalid state next boot.
    }
  }

  Future<void> _submit() async {
    if (_busy) return;

    final errorKey = OauthOnboardingRules.validationErrorKey(
      fullName: _fullName.text,
      familyName: _familyName.text,
      role: _role,
      acceptedTerms: _acceptedTerms,
      isInvited: _isInvited,
    );
    if (errorKey != null) {
      setState(() {
        _errorKey = errorKey;
        _errorText = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _errorKey = null;
      _errorText = null;
    });

    if (_isInvited) {
      await _submitClaim(confirmMigration: false);
    } else {
      await _submitFounder();
    }
  }

  Future<void> _submitFounder() async {
    try {
      await widget.dataSource.completeOauthOnboarding(
        fullName: _fullName.text.trim(),
        role: _role!,
        familyName: _familyName.text.trim(),
      );
      if (!mounted) return;
      // T-37: same funnel event the register form emits — the channel is in
      // the pageview, never a person.
      widget.analytics?.trackEvent('family_created');
      await _clearPendingToken();
      await widget.onCompleted();
    } on OnboardingRefused catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = e.message;
        _errorKey = e.message == null ? KApp.onbErrGeneric : null;
      });
    }
  }

  Future<void> _submitClaim({required bool confirmMigration}) async {
    final result = await widget.dataSource.claimInvitation(
      token: _inviteToken!,
      fullName: _fullName.text.trim(),
      confirmMigration: confirmMigration,
    );
    if (!mounted) return;

    switch (result) {
      case InviteeRegistered():
        // T-37: viral loop closed — an invited caregiver joined a family.
        widget.analytics?.trackEvent('invitee_joined');
        await _clearPendingToken();
        await widget.onCompleted();
      case InviteeNeedsMigration(:final previousFamilyName):
        setState(() {
          _busy = false;
          _migrationWarning = true;
          _migrationFamilyName = previousFamilyName;
          _errorKey = null;
          _errorText = null;
        });
      case InviteeFailed(:final message):
        setState(() {
          _busy = false;
          _errorText = message;
          _errorKey = message == null ? KApp.onbErrGeneric : null;
        });
    }
  }

  Future<void> _openWebPage(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _body(l),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(Localization l) {
    if (_loadingInvite) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(l[K.registerCheckingInvite], textAlign: TextAlign.center),
        ],
      );
    }
    if (_migrationWarning) return _migrationState(l);
    return _form(l);
  }

  /// S-11 — same question, same named consequence as the register screen's.
  Widget _migrationState(Localization l) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l[K.registerMigrationTitle],
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(l.format(K.registerMigrationBody1,
              [_migrationFamilyName ?? '', _invite?.familyName ?? ''])),
          const SizedBox(height: 8),
          Text(l[K.registerMigrationBody2]),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy
                ? null
                : () {
                    setState(() => _busy = true);
                    _submitClaim(confirmMigration: true);
                  },
            child: Text(_busy
                ? l[K.registerMigrationConfirming]
                : l[K.registerMigrationConfirm]),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _migrationWarning = false;
                      _migrationFamilyName = null;
                    }),
            child: Text(l[K.commonCancel]),
          ),
        ],
      );

  Widget _form(Localization l) {
    final invite = _invite;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (invite != null) ...[
          Text(l[K.registerInvitedTitle],
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            // Family and inviter names are free text: rendered as TEXT, never
            // as markup (U-13 rule inherited from the web).
            l.format(K.registerInvitedBody, [
              invite.inviterName,
              invite.familyName,
              RoleCatalog.translate(invite.roleName, l.current),
            ]),
            textAlign: TextAlign.center,
          ),
        ] else ...[
          Text(l[KApp.onbFounderTitle],
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(l[KApp.onbFounderSubtitle],
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
          if (_inviteInvalid) ...[
            const SizedBox(height: 12),
            Text(l[K.registerInviteInvalidBody],
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
        const SizedBox(height: 24),
        AppTextField(
          label: l[K.registerFullName],
          hint: l[K.registerFullNamePlaceholder],
          controller: _fullName,
          maxLength: RegisterRules.maxNameLength,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
        ),
        // F-57: which account this is, and the way out of it — together, right
        // under the prefilled name, because this is where someone realises
        // they picked the wrong Google account. The ADDRESS carries that
        // recognition, not the name: two accounts of the same person routinely
        // share a display name, and only the address always differs. At the
        // bottom of the form the escape hatch arrived after everything had
        // already been filled in.
        if (_sessionEmail != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l.format(KApp.onbSignedInAs, [_sessionEmail]),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: context.tokens.textMuted),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _busy ? null : widget.onSignOut,
            child: Text(l[KApp.onbSwitchAccount]),
          ),
        ),
        if (invite == null) ...[
          const SizedBox(height: 12),
          AppTextField(
            label: l[K.registerFamilyName],
            hint: l[K.registerFamilyNamePlaceholder],
            helper: l[K.registerFamilyNameHint],
            controller: _familyName,
            maxLength: RegisterRules.maxNameLength,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(l[K.registerYouAre],
                style: Theme.of(context).textTheme.titleSmall),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final role in RoleCatalog.all)
                ChoiceChip(
                  label: Text('${role.emoji} ${role.labelFor(l.current)}'),
                  selected: _role == role.canonicalName,
                  onSelected: (_) =>
                      setState(() => _role = role.canonicalName),
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        _consentBlock(l, isInvited: invite != null),
        const SizedBox(height: 20),
        FilledButton(
          // F-18: the gate is the checkbox, not a validation message.
          onPressed: _busy || !_acceptedTerms ? null : _submit,
          child: Text(_busy
              ? l[KApp.onbSubmitting]
              : l[invite != null ? KApp.onbClaimCta : KApp.onbFounderCta]),
        ),
        if (_errorKey != null || _errorText != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorText ?? l[_errorKey!],
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 8),
        const LanguagePickerRow(),
      ],
    );
  }

  /// The register screen's consent block, verbatim in structure: ONE checkbox
  /// covering policy, terms and the path declaration (A-1.1), with the
  /// declaration text branching on how this person joins.
  Widget _consentBlock(Localization l, {required bool isInvited}) {
    final theme = Theme.of(context);
    final bindingNotice = l[K.registerConsentBindingNotice];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // NOT a catalog entry: the declaration and its courtesy translation
          // live together in core so neither can be edited alone.
          ConsentDeclarations.forPath(isInvited, english: l.isEnglish),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _acceptedTerms,
              onChanged: (value) =>
                  setState(() => _acceptedTerms = value ?? false),
            ),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(l[K.registerConsentAccept],
                      style: theme.textTheme.bodySmall),
                  TextButton(
                    onPressed: () => _openWebPage(DeepLinkUrls.privacy),
                    child: Text(l[K.commonPrivacyPolicy],
                        style: theme.textTheme.bodySmall),
                  ),
                  Text(l[K.registerConsentAnd],
                      style: theme.textTheme.bodySmall),
                  TextButton(
                    onPressed: () => _openWebPage(DeepLinkUrls.terms),
                    child: Text(l[K.commonTermsOfUse],
                        style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Empty in PT-BR by construction — the binding version IS the
        // Portuguese one, so only an English reader is told so.
        if (bindingNotice.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(bindingNotice, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}
