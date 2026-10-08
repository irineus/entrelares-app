import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:entrelares_db_contracts/models/invite_info.dart';
import '../services/analytics_service.dart';
import '../services/custody_data_source.dart';
import '../theme/tokens.dart';
import '../widgets/app_l10n.dart';
import '../widgets/consent_row.dart';
import '../widgets/role_picker.dart';
import '../widgets/ui/ui.dart';

/// `/onboarding` (F-57) — where a deferred (social-login) session becomes a
/// member.
///
/// The register screen's two branches, minus what the OAuth session already
/// settled: the e-mail belongs to the provider account and there is no
/// password. The branch is decided the same way — by an invitation — except
/// the token arrives from `main.dart` in memory ([initialInviteToken]) instead
/// of the URL: the native Google door (F-71) never leaves the app, so there is
/// nothing to survive and no prefs stash.
///
/// S-13 moved here for this path: the consent the register form collects at
/// sign-up is collected on this screen instead, and the server stamps it only
/// after validating the policy version (S-15 posture) — so the deferred
/// account cannot slip past the declaration the form path signs.
class OauthOnboardingScreen extends StatefulWidget {
  final CustodyDataSource dataSource;
  final AnalyticsService? analytics;
  final SharedPreferences prefs;

  /// F-71 — the invitation the Google sign-in started from. The native door
  /// never leaves the app, so the token arrives in MEMORY — there is no prefs
  /// stash any more (the redirect that needed one is gone).
  final String? initialInviteToken;

  /// "Entrar com outra conta" — this session is confined here, so signing out
  /// is the only other door.
  final Future<void> Function() onSignOut;

  /// F-88: the kept invitation turned out dead (expired, revoked, used).
  final VoidCallback? onInviteDead;

  /// F-89: "Ajuda e contato".
  final VoidCallback? onHelp;

  /// The profile now exists — `main.dart` re-resolves the phase and routes.
  final Future<void> Function() onCompleted;

  /// U-58 — the invitation was claimed: `main.dart` raises the welcome the
  /// calendar shows before the tour. Called before the sign-in that lands.
  final void Function(InviteInfo invite)? onInviteeJoined;

  /// F-80 — this session just FOUNDED a family (never on the claim branch):
  /// `main.dart` attributes a pending referral code, if the module is on.
  /// Called before [onCompleted], and not awaited.
  final VoidCallback? onFamilyFounded;

  /// T-101 — where the family about to be founded came from (`main.dart`:
  /// the web boot URL's verdict, or the Android install's). Asked only on the
  /// founder branch, bounded to 3 s; null or a slow answer is `organic` on
  /// the server.
  final Future<Acquisition?> Function()? acquisition;

  const OauthOnboardingScreen({
    super.key,
    this.onInviteeJoined,
    this.onFamilyFounded,
    this.acquisition,
    required this.dataSource,
    this.analytics,
    required this.prefs,
    this.initialInviteToken,
    required this.onSignOut,
    this.onInviteDead,
    this.onHelp,
    required this.onCompleted,
  });

  @override
  State<OauthOnboardingScreen> createState() => _OauthOnboardingScreenState();
}

class _OauthOnboardingScreenState extends State<OauthOnboardingScreen> {
  final _fullName = TextEditingController();
  final _familyName = TextEditingController();

  /// U-61: the child's first name, OPTIONAL (the register form's field).
  final _childName = TextEditingController();

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
    final token = widget.initialInviteToken;
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
    _childName.dispose();
    super.dispose();
  }

  /// F-88: the invitation could not be checked — the form waits for a retry
  /// instead of becoming the FOUNDER form, which made a second family.
  bool _inviteUnreachable = false;

  Future<void> _resolveInvite(String token) async {
    InviteInfo? info;
    try {
      info = await widget.dataSource.fetchInviteInfo(token);
    } on InviteUnreachable {
      if (!mounted) return;
      setState(() {
        _loadingInvite = false;
        _inviteUnreachable = true;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _loadingInvite = false;
      _inviteUnreachable = false;
      if (info == null) {
        // F-88: a dead token is forgotten, so the next sign-up on this
        // device is not told about it.
        widget.onInviteDead?.call();
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

  /// The stash the redirect door left in prefs (F-57). Nothing writes it since
  /// F-71 and nothing reads it; a build that stashed a token before updating
  /// gets it dropped on the first completion, so no dead invitation lingers.
  static const String _legacyStashKey = 'pending_invite_token';

  Future<void> _clearPendingToken() async {
    try {
      await widget.prefs.remove(_legacyStashKey);
    } catch (_) {
      // Best-effort: nothing reads the key any more.
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
    // U-61: optional, validated only when filled (the RPC's own sentence).
    final childName = ChildRules.normalize(_childName.text);
    final childError =
        childName.isEmpty ? null : ChildRules.validateName(childName);
    if (childError != null) {
      setState(() {
        _busy = false;
        _errorText = childError;
        _errorKey = null;
      });
      return;
    }
    Acquisition? acquisition;
    try {
      acquisition =
          await widget.acquisition?.call().timeout(const Duration(seconds: 3));
    } catch (_) {
      acquisition = null;
    }
    try {
      await widget.dataSource.completeOauthOnboarding(
        fullName: _fullName.text.trim(),
        role: _role!,
        familyName: _familyName.text.trim(),
        acquisition: acquisition,
        childFirstName: childName.isEmpty ? null : childName,
      );
      if (!mounted) return;
      // T-37: same funnel event the register form emits — the channel is in
      // the pageview, never a person. U-61: whether the child was named.
      widget.analytics?.trackEvent(AnalyticsEvents.familyCreated,
          props: {'child': childName.isEmpty ? 'none' : 'named'});
      // F-80: the family now exists and this session founded it — the one
      // moment `attribute_referral` accepts. Fire-and-forget by contract.
      widget.onFamilyFounded?.call();
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
        widget.analytics?.trackEvent(AnalyticsEvents.inviteeJoined);
        final invite = _invite;
        if (invite != null) widget.onInviteeJoined?.call(invite);
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
    if (_inviteUnreachable) {
      return Column(
        key: const ValueKey('invite-unreachable'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l[KApp.inviteUnreachableTitle],
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(l[KApp.inviteUnreachableBody], textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              final token = _inviteToken;
              if (token == null) return;
              setState(() {
                _inviteUnreachable = false;
                _loadingInvite = true;
              });
              _resolveInvite(token);
            },
            child: Text(l[KApp.inviteRetry]),
          ),
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
          const SizedBox(height: 8),
          // F-101: the way to keep both families (F-30 stays deferred).
          Text(l[KApp.registerMigrationOtherEmail]),
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
            // F-50: a viewer is told, before signing up, that it only follows.
            invite.isViewer
                ? l.format(KApp.viewerInvitedBody,
                    [invite.inviterName, invite.familyName])
                : l.format(K.registerInvitedBody, [
                    invite.inviterName,
                    invite.familyName,
                    RoleCatalog.translate(invite.roleName, l.current),
                  ]),
            textAlign: TextAlign.center,
          ),
          // F-88: the invitation names an address, and the claim refuses any
          // other — say so BEFORE the form, while switching accounts still
          // costs nothing (the invitation stays kept).
          if (_sessionEmail != null &&
              invite.invitedEmail.trim().toLowerCase() !=
                  _sessionEmail!.trim().toLowerCase()) ...[
            const SizedBox(height: 12),
            AppBanner(
              key: const ValueKey('invite-email-mismatch'),
              tone: context.tokens.warning,
              icon: Icons.alternate_email,
              message: l.format(KApp.inviteEmailMismatch,
                  [invite.invitedEmail, _sessionEmail!]),
            ),
          ],
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
        // F-89: the onboarding is confined; Help is not.
        if (widget.onHelp != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('onboarding-help'),
              onPressed: widget.onHelp,
              child: Text(l[KApp.helpLoginLink]),
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
          // U-44: the register form's own picker — the two doors into a new
          // family ask "who are you" the same way.
          RolePicker(
            selected: _role,
            onSelected: (role) => setState(() => _role = role),
          ),
          const SizedBox(height: 16),
          // U-61: the register form's optional child field, same words.
          AppTextField(
            label: l[KApp.registerChildName],
            helper: l[KApp.registerChildNameHint],
            controller: _childName,
            maxLength: ChildRules.maxNameLength,
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
        ConsentRow(
          value: _acceptedTerms,
          onChanged: (v) => setState(() => _acceptedTerms = v),
          onOpen: _openWebPage,
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
