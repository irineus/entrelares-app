import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../deep_link_urls.dart';
import '../theme/tokens.dart';
import '../env.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import '../services/custody_data_source.dart';
import '../services/export_service.dart';
import '../services/file_delivery.dart';
import '../services/sudo_service.dart';
import '../widgets/app_l10n.dart';
import '../widgets/app_snack.dart';
import '../widgets/sudo_sheet.dart';

/// `/profile` and `/profile/{id}` — port of `ProfilePage.razor`.
///
/// This is where every member edit lives (F-16 moved them off the Família
/// page), and it is also the account page: e-mail, password, and the LGPD
/// export. **Everything that grants power or moves personal data is
/// sudo-gated**, and each of those calls goes through [runWithSudo], which
/// asks before acting AND retries once when the server disagrees.
///
/// The U-23 reopen door lives here too: a first-run guide that cannot be
/// reopened is a guide you can only read once, by accident.
class ProfileScreen extends StatefulWidget {
  final CustodyDataSource dataSource;
  final SudoService sudo;

  /// Null opens my own profile; an id opens that member's (admins only — a
  /// non-admin is bounced to their own, as in the web).
  final int? profileId;

  /// How the finished export leaves the app. The default writes the file and
  /// opens the system share sheet; it is injectable because that step needs a
  /// real device (temp directory + platform channel) and the PAYLOAD is what
  /// tests need to reach.
  final Future<void> Function(String fileName, String json)? deliverExport;

  /// Called once the exit is scheduled — the shell routes to `/leaving` and
  /// keeps them there.
  final VoidCallback? onLeaving;

  /// Opens the Família page, where a pending family deletion is resolved.
  final VoidCallback? onOpenFamily;

  /// U-23 — reopening the first-run checklist / replaying the tour. Both land
  /// on the calendar, which owns those surfaces.
  final Future<void> Function({required bool replayTour})? onReopenOnboarding;

  const ProfileScreen({
    super.key,
    required this.dataSource,
    required this.sudo,
    this.profileId,
    this.deliverExport,
    this.onLeaving,
    this.onOpenFamily,
    this.onReopenOnboarding,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  Member? _me;
  Member? _target;
  List<Member> _members = const [];
  List<Role> _roles = const [];
  Family? _family;

  final _nameDraft = TextEditingController();
  int? _roleDraft;
  String? _dataError;
  bool _savingData = false;

  final _newEmail = TextEditingController();
  String? _emailError;
  bool _emailLinkSent = false;

  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  String? _passwordError;
  bool _passwordLinkSent = false;

  /// U-29 — U-19's eye toggle; one control drives the pair, as register does.
  bool _passwordObscured = true;

  bool _exporting = false;

  // S-11 — leaving the family
  PendingFamilyDeletion? _pendingDeletion;
  bool _confirmingLeave = false;
  bool _leaving = false;
  int? _successorId;

  bool get _isOwn => _target?.id == _me?.id;
  bool get _iAmAdmin => _me?.isAdmin == true;

  List<LifecycleMember> get _lifecycleMembers => _members
      .map((m) => LifecycleMember(
          id: m.id, isActiveMember: m.isActiveMember, isAdmin: m.isAdmin))
      .toList();

  /// Leaving as the last live member is really deleting the family, and the
  /// screen must say so BEFORE the button is pressed.
  bool get _isLastMember =>
      _me != null &&
      FamilyLifecycleRules.isLastActiveMember(_lifecycleMembers, _me!.id);

  /// The only admin has to name a successor: the DB promotes them before
  /// letting me go, because a family with no admin could never invite, rename
  /// or resolve anything again.
  bool get _needsSuccessor =>
      _me != null &&
      FamilyLifecycleRules.needsSuccessor(_lifecycleMembers, _me!.id);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameDraft.dispose();
    _newEmail.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      widget.dataSource.fetchMembers(),
      widget.dataSource.fetchOwnProfile(),
      widget.dataSource.fetchRoles(),
      widget.dataSource.fetchOwnFamily(),
      widget.dataSource.fetchPendingFamilyDeletion(),
    ]);
    if (!mounted) return;
    final members = results[0] as List<Member>;
    final me = results[1] as Member?;
    final requested = widget.profileId;
    Member? target = requested == null
        ? me
        : members.where((m) => m.id == requested).firstOrNull;
    // F-16: another member's profile is an ADMIN surface. A non-admin who
    // lands here (stale link, back button) gets their own instead of an error.
    if (target != null && me != null && target.id != me.id && !me.isAdmin) {
      target = me;
    }
    setState(() {
      _members = members;
      _me = me;
      _target = target;
      _roles = results[2] as List<Role>;
      _family = results[3] as Family?;
      _pendingDeletion = results[4] as PendingFamilyDeletion?;
      _nameDraft.text = target?.fullName ?? '';
      _roleDraft = target?.roleId;
      _loading = false;
    });
  }

  Future<void> _reload() async {
    final members = await widget.dataSource.fetchMembers();
    if (!mounted) return;
    final id = _target?.id;
    setState(() {
      _members = members;
      _target = members.where((m) => m.id == id).firstOrNull ?? _target;
      _me = members.where((m) => m.id == _me?.id).firstOrNull ?? _me;
    });
  }

  Future<void> _saveData(Localization l) async {
    final target = _target;
    if (target == null) return;
    final clean = _nameDraft.text.trim();
    if (clean.length < 2) {
      setState(() => _dataError = l[KApp.profErrNameTooShort]);
      return;
    }
    setState(() {
      _savingData = true;
      _dataError = null;
    });
    try {
      if (clean != target.fullName) {
        if (_isOwn) {
          await widget.dataSource.updateOwnName(target.id, clean);
        } else {
          await widget.dataSource.updateMemberName(target.id, clean);
        }
      }
      // The role is an admin's to set — for anyone, including themselves.
      if (_iAmAdmin && _roleDraft != null && _roleDraft != target.roleId) {
        await widget.dataSource
            .setMemberRole(profileId: target.id, roleId: _roleDraft!);
      }
      if (!mounted) return;
      showAppSnack(context, l[K.profDataUpdated]);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _dataError = translateSaveError(e.toString(), l[K.errSaveFailed], l));
    } finally {
      if (mounted) setState(() => _savingData = false);
    }
  }

  Future<void> _toggleAdmin(Localization l) async {
    final target = _target;
    if (target == null) return;
    final granting = !target.isAdmin;
    try {
      await runWithSudo(
        context: context,
        sudo: widget.sudo,
        action: () => widget.dataSource
            .setMemberAdmin(profileId: target.id, isAdmin: granting),
      );
      if (!mounted) return;
      showAppSnack(context,
          l[granting ? K.profToastNowAdmin : K.profToastNoLongerAdmin]);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, translateSaveError(e.toString(), l[K.errSaveFailed], l),
          type: AppSnackType.error);
    }
  }

  Future<void> _sendPasswordReset(Localization l, String email,
      {required bool own}) async {
    try {
      if (own) {
        // My own reset needs no elevation: the mail goes to MY address, so
        // the mailbox is the proof.
        await widget.dataSource.sendPasswordReset(email, l.current);
      } else {
        await runWithSudo(
          context: context,
          sudo: widget.sudo,
          action: () => widget.dataSource.sendPasswordReset(email, l.current),
        );
      }
      if (!mounted) return;
      if (own) {
        setState(() => _passwordLinkSent = true);
      } else {
        showAppSnack(context, l.format(K.profToastResetSentTo, [email]));
      }
    } catch (_) {
      if (!mounted) return;
      showAppSnack(context, l[K.profErrSendEmail], type: AppSnackType.error);
    }
  }

  Future<void> _changeEmail(Localization l) async {
    final candidate = _newEmail.text.trim();
    setState(() {
      _emailError = null;
      _emailLinkSent = false;
    });
    if (!candidate.contains('@')) {
      setState(() => _emailError = l[K.profErrInvalidEmail]);
      return;
    }
    if (candidate.toLowerCase() == (_target?.email ?? '').toLowerCase()) {
      setState(() => _emailError = l[K.profErrSameEmail]);
      return;
    }
    try {
      final ran = await runWithSudo(
        context: context,
        sudo: widget.sudo,
        action: () => widget.dataSource.updateOwnEmail(candidate),
      );
      if (!mounted || !ran) return;
      _newEmail.clear();
      // GoTrue only APPLIES the change once the link is clicked — saying
      // "changed" here would be a lie.
      setState(() => _emailLinkSent = true);
      await widget.dataSource.logAccountAction('email_change_requested');
    } catch (e) {
      if (!mounted) return;
      setState(() => _emailError = e.toString());
    }
  }

  Future<void> _changePassword(Localization l) async {
    setState(() => _passwordError = null);
    if (_newPassword.text.length < RegisterRules.minPasswordLength) {
      setState(() => _passwordError = l[KApp.profErrPasswordShort]);
      return;
    }
    if (_newPassword.text != _confirmPassword.text) {
      setState(() => _passwordError = l[K.profErrPasswordMismatch]);
      return;
    }
    try {
      final ran = await runWithSudo(
        context: context,
        sudo: widget.sudo,
        // S-10: the CURRENT password is always demanded first — otherwise a
        // borrowed unlocked phone could take the account over.
        action: () => widget.dataSource.updateOwnPassword(_newPassword.text),
      );
      if (!mounted || !ran) return;
      _newPassword.clear();
      _confirmPassword.clear();
      await widget.dataSource.logAccountAction('password_changed');
      if (mounted) showAppSnack(context, l[K.profPasswordChanged]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _passwordError = e.toString());
    }
  }

  Future<void> _export(Localization l) async {
    final me = _me;
    if (me == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final ran = await runWithSudo(
        context: context,
        sudo: widget.sudo,
        action: () async {
          final bundle = await widget.dataSource.fetchExportData(me.id);
          final payload = ExportService.buildPayload(
            me: me,
            family: _family,
            members: _members,
            roles: _roles,
            bundle: bundle,
            l: l,
            appVersion: Env.appVersion,
            generatedAtUtc: DateTime.now().toUtc(),
          );
          final deliver = widget.deliverExport ?? _shareFile;
          await deliver(ExportService.fileName(l, DateTime.now()),
              ExportService.encode(payload));
        },
      );
      if (!mounted || !ran) return;
      await widget.dataSource.logAccountAction('data_exported');
      if (mounted) showAppSnack(context, l[K.profToastExported]);
    } catch (e) {
      if (!mounted) return;
      // The catalog sentence carries a `{0}` for the reason — reading it with
      // `l[...]` printed the placeholder itself to the user, and swallowing
      // the exception hid the one clue about what failed (pilot lesson 4:
      // never collapse heterogeneous failures into one message).
      showAppSnack(context, l.format(K.profErrExport, [e.toString()]),
          type: AppSnackType.error);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Delivery is per PLATFORM, and that is not a detail: the native half
  /// (share sheet over a temp file) needs `dart:io`, so on the web every
  /// export used to die in the generic failure snack. See `file_delivery.dart`.
  Future<void> _shareFile(String fileName, String json) =>
      deliverTextFile(fileName, json, mimeType: 'application/json');

  Future<void> _leaveFamily(Localization l) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      final ran = await runWithSudo(
        context: context,
        sudo: widget.sudo,
        action: () => widget.dataSource.requestAccountDeletion(
            successorProfileId: _needsSuccessor ? _successorId : null),
      );
      if (!mounted) return;
      if (!ran) {
        setState(() => _leaving = false);
        return;
      }
      // Best-effort, as in the web: the exit is already scheduled.
      await widget.dataSource
          .sendAccountEmail('member_left', profileId: _me?.id);
      if (!mounted) return;
      // From here the router confines them to /leaving until they cancel or
      // sign out.
      widget.onLeaving?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _leaving = false);
      showAppSnack(
          context, translateSaveError(e.toString(), l[K.errSaveFailed], l),
          type: AppSnackType.error);
    }
  }

  Future<void> _openWebPage(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final target = _target;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l[K.profPageTitle])),
        body: AppSkeletonCards(count: 2, semanticsLabel: l[K.famLoading]),
      );
    }
    if (target == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l[K.profPageTitle])),
        body: Center(child: Text(l[K.profNotFound])),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(target.fullName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (target.leftAt != null) ...[
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(l[K.profFrozenBanner]),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _dataSection(l, target),
          if (_iAmAdmin && !_isOwn && target.leftAt == null) ...[
            const SizedBox(height: 24),
            _adminSection(l, target),
          ],
          if (_isOwn) ...[
            const SizedBox(height: 24),
            _emailSection(l, target),
            const SizedBox(height: 24),
            _passwordSection(l, target),
            const SizedBox(height: 24),
            // U-28: the picker the web has on this page, and the sentence that
            // explains why it matters — both were dropped in the port. The
            // account menu switches the language too, but this is where a
            // reader looks for a SETTING, and `languageHint` is the only place
            // the app says the choice follows them into their e-mail.
            _languageSection(l),
            const SizedBox(height: 24),
            _lgpdSection(l),
            if (widget.onReopenOnboarding != null) ...[
              const SizedBox(height: 24),
              _onboardingSection(l),
            ],
            const SizedBox(height: 24),
            _leaveSection(l),
          ],
          const SizedBox(height: 24),
          _legalFooter(l),
          const SizedBox(height: Spacing.sm),
          // U-28: the version the web prints in its own footer — the first
          // thing a tester is asked for when they report something.
          Text('Entrelares v${Env.appVersion}',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: context.tokens.textMuted)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) =>
      Text(text, style: Theme.of(context).textTheme.titleMedium);

  /// U-28 — the language setting, back on the page that holds settings.
  Widget _languageSection(Localization l) => AppCard(
        title: l[K.languageLabel],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l[K.languageHint],
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: Spacing.md),
            const LanguagePickerRow(),
          ],
        ),
      );

  Widget _dataSection(Localization l, Member target) => AppCard(
        title: l[K.profSectionData],
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            label: l[K.registerFullName],
            controller: _nameDraft,
            maxLength: RegisterRules.maxNameLength,
            errorText: _dataError,
          ),
          if (_iAmAdmin) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _roleDraft,
              decoration: InputDecoration(labelText: l[K.famRoleInFamily]),
              items: [
                for (final role in _roles)
                  DropdownMenuItem(
                    value: role.id,
                    child: Text(role.displayLabel(l.current)),
                  ),
              ],
              onChanged: (value) => setState(() => _roleDraft = value),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(l[K.profPersonalHint],
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _savingData ? null : () => _saveData(l),
            icon: const Icon(Icons.save_outlined),
            label: Text(l[K.profSaveData]),
          ),
        ],
      ));

  Widget _adminSection(Localization l, Member target) => AppCard(
        title: l[K.profSectionAdmin],
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(target.isAdmin ? l[K.profIsAdmin] : l[K.profIsNotAdmin],
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          // U-29: the shield moved from an emoji in the string to the app's
          // own icon, pairing with the mail button below.
          OutlinedButton.icon(
            onPressed: () => _toggleAdmin(l),
            icon: const Icon(Icons.shield_outlined),
            label: Text(
                target.isAdmin ? l[K.profRemoveAdmin] : l[K.profMakeAdmin]),
          ),
          const SizedBox(height: 8),
          // U-28: an OutlinedButton, not a bare link. As text these read as
          // captions floating under the section rather than as things to press.
          OutlinedButton.icon(
            onPressed: () => _sendPasswordReset(l, target.email ?? '',
                own: false),
            icon: const Icon(Icons.mail_outline),
            label: Text(l[K.profSendPasswordReset]),
          ),
        ],
      ));

  Widget _emailSection(Localization l, Member target) => AppCard(
        title: l[K.profSectionEmail],
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // U-28 defect: the key is a FORMAT string ("E-mail atual: {0}"), and
          // interpolating it printed the placeholder verbatim next to the
          // address — "E-mail atual: {0} irineus@gmail.com".
          Text(l.format(K.profCurrentEmail, [target.email ?? '']),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          AppTextField(
            label: l[K.profNewEmail],
            hint: l[K.profNewEmailPlaceholder],
            controller: _newEmail,
            keyboardType: TextInputType.emailAddress,
            errorText: _emailError,
          ),
          if (_emailLinkSent) ...[
            const SizedBox(height: 8),
            Text(l[K.profEmailLinkSent],
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _changeEmail(l),
            icon: const Icon(Icons.alternate_email),
            label: Text(l[K.profChangeEmail]),
          ),
        ],
      ));

  /// F-57 (the U-21 slice this item requires): a session whose identity
  /// providers do not include `email` has NO password — offering "alterar
  /// senha" to it would submit against nothing, and "esqueci a atual" would
  /// e-mail a reset for a credential that does not exist. Such a session sees
  /// its sign-in METHOD instead.
  Widget _passwordSection(Localization l, Member target) {
    final providers = widget.dataSource.authProviders();
    final passwordless =
        providers.isNotEmpty && !providers.contains('email');
    if (passwordless) {
      return AppCard(
        title: l[KApp.profLoginMethod],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_circle_outlined, size: 20),
                const SizedBox(width: 8),
                Text(l[KApp.profLoginMethodGoogle],
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(l[KApp.profLoginMethodNote],
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }
    return AppCard(
        title: l[K.profSectionPassword],
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // U-29: the only two fields in the app that were raw `TextField`s —
          // now the shared component, which also brings U-19's eye toggle back.
          AppTextField(
            label: l[K.updatePwdNewPassword],
            hint: l[K.profNewPasswordPlaceholder],
            controller: _newPassword,
            obscureText: _passwordObscured,
            errorText: _passwordError,
            suffixIcon: IconButton(
              tooltip: l[_passwordObscured
                  ? K.commonShowPassword
                  : K.commonHidePassword],
              icon: Icon(_passwordObscured
                  ? Icons.visibility
                  : Icons.visibility_off),
              onPressed: () =>
                  setState(() => _passwordObscured = !_passwordObscured),
            ),
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: l[K.profConfirmNewPassword],
            hint: l[K.profConfirmNewPasswordPlaceholder],
            controller: _confirmPassword,
            obscureText: _passwordObscured,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _changePassword(l),
            icon: const Icon(Icons.key_outlined),
            label: Text(l[K.profChangePassword]),
          ),
          const SizedBox(height: 8),
          Text(l[K.profForgotCurrent],
              style: Theme.of(context).textTheme.bodySmall),
          if (_passwordLinkSent)
            Text(l.format(K.profPasswordLinkSentTo, [target.email ?? '']),
                style: Theme.of(context).textTheme.bodySmall),
          OutlinedButton.icon(
            onPressed: () =>
                _sendPasswordReset(l, target.email ?? '', own: true),
            icon: const Icon(Icons.mail_outline),
            label: Text(l[K.profResetByEmail]),
          ),
        ],
      ));
  }

  Widget _lgpdSection(Localization l) => AppCard(
        title: l[K.profSectionLgpd],
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l[K.profExportHint],
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _exporting ? null : () => _export(l),
            icon: const Icon(Icons.download_outlined),
            label: Text(l[K.profExportAction]),
          ),
        ],
      ));

  /// U-23 — the permanent way back into the first-run guide.
  Widget _onboardingSection(Localization l) => AppCard(
        title: l[K.onbChecklistReopen],
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l[K.onbChecklistReopenHint],
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          // U-28: two buttons on one row, as the web has them. The second was
          // a bare TextButton under the first, which read as a caption rather
          // than as the alternative it is.
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () =>
                      widget.onReopenOnboarding!(replayTour: false),
                  child: Text(l[K.onbChecklistReopen],
                      textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      widget.onReopenOnboarding!(replayTour: true),
                  child: Text(l[K.onbChecklistReplayTour],
                      textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ],
      ));

  /// S-11 — leaving. Two different acts share one button, and the copy is what
  /// tells them apart: the LAST live member is deleting the family, everyone
  /// else is only deleting their own account.
  Widget _leaveSection(Localization l) {
    final theme = Theme.of(context);
    final last = _isLastMember;

    // Blocked while the family itself is on the way out — the DB refuses too,
    // and the two flows would race for the same rows.
    if (_pendingDeletion != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(l[last ? K.profLeaveTitleLast : K.profLeaveTitle]),
          const SizedBox(height: 8),
          Text(l[K.profLeaveBlocked], style: theme.textTheme.bodySmall),
          TextButton(
            onPressed: widget.onOpenFamily,
            child: Text(l[K.profFamilyPageLink]),
          ),
        ],
      );
    }

    final successorPicker = !_needsSuccessor
        ? null
        : DropdownButtonFormField<int>(
            initialValue: _successorId,
            decoration: InputDecoration(
              labelText: l[K.profSuccessorLabel],
              hintText: l[K.profSuccessorPlaceholder],
            ),
            items: [
              for (final candidate in FamilyLifecycleRules.successorCandidates(
                  _lifecycleMembers, _me!.id))
                DropdownMenuItem(
                  value: candidate.id,
                  child: Text(_members
                          .where((m) => m.id == candidate.id)
                          .map((m) => m.fullName)
                          .firstOrNull ??
                      ''),
                ),
            ],
            onChanged: (value) => setState(() => _successorId = value),
          );

    // U-28: the same danger zone the family screen uses. This action deletes
    // the reader's own account (or the whole family, when they are the last
    // one), and it was rendered as loose paragraphs under an OutlinedButton —
    // less visual weight than "Salvar dados" two sections above it.
    if (!_confirmingLeave) {
      return AppDangerZone(
        title: l[last ? K.profLeaveTitleLast : K.profLeaveTitle],
        intro: l[last ? K.profLeaveLastIntro : K.profLeaveIntro],
        notices: [
          for (final consequence in last
              ? [
                  K.profLeaveLastConsequenceData,
                  K.profLeaveLastConsequenceCancel
                ]
              : [
                  K.profLeaveConsequenceAccount,
                  K.profLeaveConsequenceDays,
                  K.profLeaveConsequenceHistory,
                  K.profLeaveConsequenceNotice,
                  if (_needsSuccessor) K.profLeaveConsequenceSuccessor,
                ])
            l[consequence],
        ],
        actionLabel: l[last ? K.profLeaveOpenLast : K.profLeaveOpen],
        onAction: () => setState(() => _confirmingLeave = true),
        child: successorPicker,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l[last ? K.profLeaveTitleLast : K.profLeaveTitle]),
        const SizedBox(height: 8),
        ...[
          Text(l[last ? K.profLeaveConfirmTextLast : K.profLeaveConfirmText],
              style: TextStyle(color: theme.colorScheme.error)),
          if (successorPicker != null) ...[
            const SizedBox(height: 12),
            successorPicker,
          ],
          const SizedBox(height: 8),
          // U-29: the destructive confirm wears the danger tone, never the
          // brand indigo — same rule AppDangerZone and AppActionPair encode.
          FilledButton(
            onPressed: _leaving || (_needsSuccessor && _successorId == null)
                ? null
                : () => _leaveFamily(l),
            style: FilledButton.styleFrom(
                backgroundColor: context.tokens.danger.solid,
                foregroundColor: context.tokens.danger.onSolid),
            child:
                Text(l[last ? K.profLeaveConfirmLast : K.profLeaveConfirm]),
          ),
          TextButton(
            onPressed: () => setState(() => _confirmingLeave = false),
            child: Text(
                l[last ? K.profLeaveKeepFamily : K.profLeaveKeepAccount]),
          ),
        ],
      ],
    );
  }

  /// The stores accept an external legal link, and one copy of the text beats
  /// three that can drift (owner decision, lote 4).
  Widget _legalFooter(Localization l) => Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton(
            onPressed: () => _openWebPage(DeepLinkUrls.privacy),
            child: Text(l[K.commonPrivacyPolicy],
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Text('·', style: Theme.of(context).textTheme.bodySmall),
          TextButton(
            onPressed: () => _openWebPage(DeepLinkUrls.terms),
            child: Text(l[K.commonTermsOfUse],
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      );
}
