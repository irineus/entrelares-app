import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../deep_link_urls.dart';
import 'package:entrelares_db_contracts/models/invite_info.dart';
import '../services/analytics_service.dart';
import '../services/custody_data_source.dart';
import '../widgets/app_l10n.dart';
import '../widgets/google_sign_in_button.dart';

/// `/register` — port of `Register.razor`.
///
/// One screen, two branches, and the branch is decided by ONE thing: whether
/// the URL carried an `invite` token.
///
/// * **Founder** — names the family, picks a role, and ends on "confirm your
///   e-mail": GoTrue will not let them in until the link is clicked. The family
///   and the profile are created by the `handle_new_user` trigger in a single
///   transaction, so there is no half-created account to clean up.
/// * **Invitee** (U-17) — auto-confirmed by the `register-invitee` Edge
///   Function, so the screen signs them in and lands them on the calendar. The
///   e-mail is read-only (the invitation names it, and the trigger refuses a
///   mismatch), and there is no family/role to choose: the invitation carries
///   both.
///
/// The S-15 consent is ONE checkbox covering policy, terms and the
/// path-specific declaration (A-1.1 decided the form) — and the declaration
/// text differs per branch, which is exactly why [ConsentDeclarations] is
/// shared with the re-consent gate.
class RegisterScreen extends StatefulWidget {
  /// The token from `/register?invite=…`, when this visitor arrived through an
  /// invitation (App Link or a pasted link).
  final String? inviteToken;

  final CustodyDataSource dataSource;

  /// T-37 — optional: the sign-up funnel is instrumentation, never a step.
  final AnalyticsService? analytics;

  /// Signs the freshly created invitee in — the founder never reaches it.
  final Future<void> Function(String email, String password) onSignIn;

  final VoidCallback onBackToLogin;

  /// F-57 — the Google door on BOTH branches. Consent is NOT collected here
  /// for that path: the redirect leaves this form behind, and the onboarding
  /// screen collects it where the profile is actually created (S-13). The
  /// invite branch hands its token over so `main.dart` can stash it across
  /// the browser round-trip. Null keeps the screen pre-F-57.
  final Future<bool>? googleEnabled;
  final Future<void> Function({String? inviteToken})? onSignInWithGoogle;

  const RegisterScreen({
    this.analytics,
    super.key,
    required this.dataSource,
    required this.onSignIn,
    required this.onBackToLogin,
    this.googleEnabled,
    this.onSignInWithGoogle,
    this.inviteToken,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _familyName = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  String? _role;
  bool _acceptedTerms = false;
  bool _obscured = true;

  bool _loadingInvite = false;
  bool _inviteInvalid = false;
  InviteInfo? _invite;

  bool _busy = false;
  bool _signUpDone = false;

  /// The catalog KEY of the current error, so a language switch re-renders it.
  String? _errorKey;

  /// A message the SERVER wrote (the Edge Function's PT-BR text) — shown
  /// verbatim instead of a key, never collapsed into a generic sentence.
  String? _errorText;

  /// S-11: set while the visitor is being asked to confirm leaving another
  /// family behind.
  bool _migrationWarning = false;
  String? _migrationFamilyName;

  bool get _isInvited => _invite != null;

  @override
  void initState() {
    super.initState();
    final token = widget.inviteToken;
    if (token != null && token.trim().isNotEmpty) {
      _loadingInvite = true;
      _resolveInvite(token.trim());
    }
  }

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _familyName.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _resolveInvite(String token) async {
    final info = await widget.dataSource.fetchInviteInfo(token);
    if (!mounted) return;
    setState(() {
      _loadingInvite = false;
      if (info == null) {
        _inviteInvalid = true;
        return;
      }
      _invite = info;
      // The invitation names the address; the trigger refuses any other.
      _email.text = info.invitedEmail;
      // F-56: the name the admin gave the placeholder is a suggestion — the
      // person's own typing wins, at sign-up and forever after.
      final suggested = info.inviteeName?.trim() ?? '';
      if (_fullName.text.trim().isEmpty && suggested.isNotEmpty) {
        _fullName.text = suggested;
      }
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l = AppL10n.of(context).l;

    final errorKey = RegisterRules.validationErrorKey(
      fullName: _fullName.text,
      email: _email.text,
      familyName: _familyName.text,
      role: _role,
      password: _password.text,
      confirmPassword: _confirmPassword.text,
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

    // T-37: funnel entry — the sign-up TYPE and nothing else.
    widget.analytics?.trackEvent('signup_started',
        props: {'type': _isInvited ? 'invitee' : 'founder'});

    if (_isInvited) {
      await _submitInvite(confirmMigration: false, l: l);
    } else {
      await _submitFounder(l);
    }
  }

  Future<void> _submitFounder(Localization l) async {
    try {
      await widget.dataSource.signUpFounder(
        email: _email.text.trim(),
        password: _password.text,
        fullName: _fullName.text.trim(),
        role: _role!,
        familyName: _familyName.text.trim(),
        languageCode: l.current.code,
      );
      if (!mounted) return;
      // T-37: a founder created a new family (activation funnel).
      widget.analytics?.trackEvent('family_created');
      // The account exists but is unusable until the e-mail is confirmed —
      // this screen is the end of the founder's flow, not a step in it.
      setState(() {
        _busy = false;
        _signUpDone = true;
      });
    } on SignUpFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorKey = e.errorKey;
      });
    }
  }

  Future<void> _submitInvite(
      {required bool confirmMigration, required Localization l}) async {
    final result = await widget.dataSource.registerInvitee(
      token: widget.inviteToken!.trim(),
      fullName: _fullName.text.trim(),
      password: _password.text,
      confirmMigration: confirmMigration,
    );
    if (!mounted) return;

    switch (result) {
      case InviteeRegistered():
        // T-37: viral loop closed — an invited caregiver joined a family.
        widget.analytics?.trackEvent('invitee_joined');
        // U-17: already confirmed — sign in and let the router land them.
        try {
          await widget.onSignIn(_email.text.trim(), _password.text);
        } catch (_) {
          // The account exists; only the automatic sign-in failed. Send them
          // to the login screen rather than leaving them on a dead form.
          if (mounted) widget.onBackToLogin();
        }
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
          _errorKey = message == null ? K.authErrSignUpFailed : null;
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
    if (_loadingInvite) return _loadingInviteState(l);
    if (_inviteInvalid) return _inviteInvalidState(l);
    if (_signUpDone) return _confirmEmailState(l);
    if (_migrationWarning) return _migrationState(l);
    return _form(l);
  }

  Widget _loadingInviteState(Localization l) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(l[K.registerCheckingInvite], textAlign: TextAlign.center),
        ],
      );

  Widget _inviteInvalidState(Localization l) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l[K.registerInviteInvalidTitle],
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(l[K.registerInviteInvalidBody], textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: widget.onBackToLogin,
            child: Text(l[K.registerBackToLogin]),
          ),
        ],
      );

  Widget _confirmEmailState(Localization l) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l[K.registerConfirmEmailTitle],
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          // The catalog sentence ends before the address on purpose (the web
          // emphasises it separately) — it carries no placeholder.
          Text(l[K.registerConfirmEmailSentTo], textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(_email.text.trim(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(l[K.registerConfirmEmailBody], textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: widget.onBackToLogin,
            child: Text(l[K.registerGoToLogin]),
          ),
        ],
      );

  /// S-11 — one e-mail belongs to one family. Joining this one hard-deletes the
  /// previous registration, so it is a question with a named consequence, not
  /// an error banner.
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
                    _submitInvite(confirmMigration: true, l: l);
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
          Text(l[K.registerCreateTitle],
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(l[K.registerCreateSubtitle],
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
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
        const SizedBox(height: 12),
        AppTextField(
          label: l[K.commonEmail],
          hint: l[K.commonEmailPlaceholder],
          controller: _email,
          // The invitation names the address — the trigger refuses any other.
          readOnly: invite != null,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
        ),
        // F-57: ABOVE the password fields, deliberately. This button exists so
        // the person never has to invent a password, so offering it after the
        // form has already been filled defeats it — by then the cost it saves
        // is already paid. Everything below is the secondary path: what you
        // fill in only if you would rather not use Google. Same reason it sits
        // above the founder's family/role fields, which the OAuth path
        // re-collects on the onboarding screen anyway.
        if (widget.googleEnabled != null && widget.onSignInWithGoogle != null)
          GoogleSignInButton(
            enabled: widget.googleEnabled!,
            onPressed: () =>
                widget.onSignInWithGoogle!(inviteToken: widget.inviteToken),
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
        const SizedBox(height: 16),
        AppTextField(
          label: l[K.commonPassword],
          hint: l[K.registerPasswordPlaceholder],
          controller: _password,
          obscureText: _obscured,
          autofillHints: const [AutofillHints.newPassword],
          suffixIcon: IconButton(
            tooltip:
                l[_obscured ? K.commonShowPassword : K.commonHidePassword],
            icon: Icon(_obscured ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscured = !_obscured),
          ),
        ),
        const SizedBox(height: 12),
        AppTextField(
          label: l[K.commonConfirmPassword],
          hint: l[K.registerConfirmPasswordPlaceholder],
          controller: _confirmPassword,
          obscureText: _obscured,
        ),
        const SizedBox(height: 20),
        _consentBlock(l, isInvited: invite != null),
        const SizedBox(height: 20),
        FilledButton(
          // F-18: the gate is the checkbox, not a validation message.
          onPressed: _busy || !_acceptedTerms ? null : _submit,
          child: Text(_busy ? l[K.registerSubmitting] : l[K.registerSubmit]),
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
        TextButton(
          onPressed: widget.onBackToLogin,
          child: Text(l[K.registerHaveAccount]),
        ),
        const LanguagePickerRow(),
      ],
    );
  }

  /// A-1.1 decided the FORM as much as the text: ONE checkbox covers the
  /// policy, the terms and the path declaration — there is no second art. 14
  /// §1 consent, because the app collects no structured child data to consent
  /// about.
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
