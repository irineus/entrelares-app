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
import '../services/appearance.dart';
import '../services/custody_data_source.dart';
import '../services/export_service.dart';
import '../services/file_delivery.dart';
import '../services/sudo_service.dart';
import '../widgets/app_l10n.dart';
import '../widgets/app_snack.dart';
import '../widgets/profile_sheets.dart';
import '../widgets/rich_label.dart';
import '../widgets/sudo_sheet.dart';

/// `/profile` and `/profile/{id}` — port of `ProfilePage.razor`.
///
/// This is where every member edit lives (F-16 moved them off the Família
/// page), and it is also the account page: e-mail, password, and the LGPD
/// export. **Everything that grants power or moves personal data is
/// sudo-gated**, and each of those calls goes through [runWithSudo], which
/// asks before acting AND retries once when the server disagrees.
///
/// U-21: the page is READ at rest. Dados, E-mail and Senha are summary cards
/// with a pencil in the title, and the pencil opens a sheet
/// (`profile_sheets.dart`) — no input sits open on the page for someone who
/// only came to look. The gated call stays here, so the sudo prompt stacks
/// over the sheet and a dismissed prompt keeps the draft.
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

  /// F-50: a viewer's exit deleted the account — the session has nothing
  /// left to show, so the app signs out.
  final VoidCallback? onViewerErased;

  /// Opens the Família page, where a pending family deletion is resolved.
  final VoidCallback? onOpenFamily;

  /// U-23 — reopening the first-run checklist / replaying the tour. Both land
  /// on the calendar, which owns those surfaces.
  final Future<void> Function({required bool replayTour})? onReopenOnboarding;

  /// U-12 — the theme choice, owned by the root (it is what `MaterialApp`
  /// reads) and handed down here, where a reader looks for a setting. Optional
  /// like [onReopenOnboarding]: a scene that pumps this screen without a root
  /// simply has no Aparência card, and the production routes always pass one.
  final Appearance? appearance;

  /// F-68: opens "Ajuda e contato". Null in scenes that predate it — the row
  /// simply does not render there, like [onReopenOnboarding].
  final VoidCallback? onOpenHelp;

  const ProfileScreen({
    super.key,
    required this.dataSource,
    required this.sudo,
    this.profileId,
    this.deliverExport,
    this.onLeaving,
    this.onViewerErased,
    this.onOpenFamily,
    this.onReopenOnboarding,
    this.appearance,
    this.onOpenHelp,
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

  /// What the E-mail and Senha cards say after their sheet closed: GoTrue only
  /// applies an e-mail change once the link is clicked, and a reset is a
  /// mail, not a change — both outcomes are sentences on the card.
  bool _emailLinkSent = false;
  bool _passwordLinkSent = false;

  bool _exporting = false;

  /// U-50 — the server's answer to "does this account have a password";
  /// `null` while unanswered. Never derived from the session's providers.
  bool? _hasPassword;

  // S-11 — leaving the family
  PendingFamilyDeletion? _pendingDeletion;
  bool _confirmingLeave = false;
  bool _leaving = false;
  int? _successorId;

  bool get _isOwn => _target?.id == _me?.id;
  bool get _iAmAdmin => _me?.isAdmin == true;

  /// F-50: a viewer is never a successor, a voter or the last member.
  List<LifecycleMember> get _lifecycleMembers => _members
      .map((m) => LifecycleMember(
          id: m.id,
          isActiveMember: m.isActiveMember && !m.isViewer,
          isAdmin: m.isAdmin))
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

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait<Object?>([
      widget.dataSource.fetchMembers(),
      widget.dataSource.fetchOwnProfile(),
      widget.dataSource.fetchRoles(),
      widget.dataSource.fetchOwnFamily(),
      widget.dataSource.fetchPendingFamilyDeletion(),
      // U-50: asked alongside the rest, so the skeleton covers it and the
      // password card never pops in after the page is up (owner, 18/09/2026).
      widget.dataSource.sessionHasPassword(),
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
      _hasPassword = results[5] as bool?;
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

  /// U-21 — the Dados pencil. The sheet validates and shows a refusal; this
  /// side only knows WHICH writer each field goes to.
  Future<void> _editData(Localization l, Member target) async {
    final saved = await showProfileDataSheet(
      context: context,
      initialName: target.fullName,
      initialRoleId: target.roleId,
      roles: _roles,
      // The role is an admin's to set — for anyone, including themselves.
      canEditRole: _iAmAdmin,
      onSave: (name, roleId) async {
        if (name != target.fullName) {
          if (_isOwn) {
            await widget.dataSource.updateOwnName(target.id, name);
          } else {
            await widget.dataSource.updateMemberName(target.id, name);
          }
        }
        if (roleId != null && roleId != target.roleId) {
          await widget.dataSource
              .setMemberRole(profileId: target.id, roleId: roleId);
        }
      },
    );
    if (saved != true || !mounted) return;
    showAppSnack(context, l[K.profDataUpdated]);
    await _reload();
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

  /// U-21 — the E-mail pencil. The sheet refuses a malformed or unchanged
  /// address before any prompt; the gated call runs from HERE, so the sudo
  /// sheet stacks over the editor and a dismissed prompt keeps the draft.
  Future<void> _editEmail(Member target) async {
    setState(() => _emailLinkSent = false);
    final sent = await showProfileEmailSheet(
      context: context,
      currentEmail: target.email ?? '',
      onSubmit: (candidate) => runWithSudo(
        context: context,
        sudo: widget.sudo,
        action: () => widget.dataSource.updateOwnEmail(candidate),
      ),
    );
    if (sent != true || !mounted) return;
    // GoTrue only APPLIES the change once the link is clicked — saying
    // "changed" here would be a lie.
    setState(() => _emailLinkSent = true);
    await widget.dataSource.logAccountAction('email_change_requested');
  }

  /// U-21 — the Senha pencil. Two doors in one sheet: the change, gated by
  /// S-10 (the CURRENT password is always demanded first — otherwise a
  /// borrowed unlocked phone could take the account over), and the reset by
  /// e-mail for whoever cannot answer that prompt.
  Future<void> _editPassword(Localization l, Member target) async {
    setState(() => _passwordLinkSent = false);
    final outcome = await showProfilePasswordSheet(
      context: context,
      onChange: (newPassword) => runWithSudo(
        context: context,
        sudo: widget.sudo,
        action: () => widget.dataSource.updateOwnPassword(newPassword),
      ),
      onReset: () => _sendPasswordReset(l, target.email ?? '', own: true),
    );
    if (outcome != ProfilePasswordOutcome.changed || !mounted) return;
    await widget.dataSource.logAccountAction('password_changed');
    if (mounted) showAppSnack(context, l[K.profPasswordChanged]);
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

  /// F-50: a viewer leaves by being deleted — account included, right away.
  Future<void> _leaveAsViewer(Localization l) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      final ran = await runWithSudo(
        context: context,
        sudo: widget.sudo,
        action: () => widget.dataSource.leaveFamilyAsViewer(),
      );
      if (!mounted) return;
      if (!ran) {
        setState(() => _leaving = false);
        return;
      }
      widget.onViewerErased?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _leaving = false);
      showAppSnack(
          context, translateSaveError(e.toString(), l[K.errSaveFailed], l),
          type: AppSnackType.error);
    }
  }

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
            // U-49: the shared danger banner — this was a Card painted with
            // `errorContainer` by hand, the only one of its kind.
            AppBanner(
              tone: context.tokens.danger,
              icon: Icons.lock_outline,
              message: l[K.profFrozenBanner],
            ),
            const SizedBox(height: 16),
          ],
          _dataSection(l, target),
          if (_iAmAdmin && !_isOwn && target.leftAt == null) ...[
            const SizedBox(height: 24),
            _adminSection(l, target),
          ],
          if (_isOwn) ...[
            // U-30: the doors of the account come FIRST, because the two
            // sections after it are the ones a reader misreads without them —
            // "I changed my e-mail / my password, so…" — and the notes on the
            // rows point forward to both.
            ..._signInMethodsSection(l, target),
            const SizedBox(height: 24),
            _emailSection(l, target),
            if (SignInMethodRules.showsPasswordCard(_signInMethods(target))) ...[
              const SizedBox(height: 24),
              _passwordSection(l, target),
            ],
            const SizedBox(height: 24),
            // U-28: the picker the web has on this page, and the sentence that
            // explains why it matters — both were dropped in the port. The
            // account menu switches the language too, but this is where a
            // reader looks for a SETTING, and `languageHint` is the only place
            // the app says the choice follows them into their e-mail.
            _languageSection(l),
            // U-12: the other display preference, right beside the first one.
            // Both are per device and neither reaches the family's data — the
            // reader who came here for one finds the other without hunting.
            if (widget.appearance != null) ...[
              const SizedBox(height: 24),
              _appearanceSection(l, widget.appearance!),
            ],
            const SizedBox(height: 24),
            _lgpdSection(l),
            if (widget.onReopenOnboarding != null) ...[
              const SizedBox(height: 24),
              _onboardingSection(l),
            ],
            const SizedBox(height: 24),
            _leaveSection(l),
          ],
          // F-68: for every reader of a profile, own or not — the person who
          // needs help is not always on their own page.
          if (widget.onOpenHelp != null) ...[
            const SizedBox(height: 24),
            Card(
              key: const ValueKey('profile-help-row'),
              margin: EdgeInsets.zero,
              child: ListTile(
                onTap: widget.onOpenHelp,
                leading: const Icon(Icons.help_outline),
                title: Text(l[KApp.helpTitle]),
                subtitle: Text(l[KApp.helpProfileRowSub]),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
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

  // U-49: the same header the family screen draws, with its spacing built
  // in — the profile's was a bare Text and an 8 px SizedBox at each call.
  Widget _sectionTitle(String text) =>
      AppSectionHeader(title: text, topSpacing: 0);

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

  /// U-12 — "sempre claro / sempre escuro / seguir o sistema", in the shape
  /// the language picker already taught: one segmented control, the hint above
  /// it. The labels are one word each because the control lives on a 360 dp
  /// phone at up to 1.3× (U-48), and the sentence the short words drop —
  /// per device, and what "Sistema" follows — is the hint's job.
  ///
  /// The [ValueListenableBuilder] is what makes the control move at all when
  /// this screen is pumped on its own: in the app the root rebuilds everything
  /// anyway, but the selection must follow the value, never a local copy of it.
  Widget _appearanceSection(Localization l, Appearance appearance) => AppCard(
        title: l[KApp.appearanceLabel],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l[KApp.appearanceHint],
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: Spacing.md),
            Center(
              child: ValueListenableBuilder<ThemePreference>(
                valueListenable: appearance,
                builder: (_, selected, _) => AppSegmented<ThemePreference>(
                  semantics: l[KApp.appearanceAriaLabel],
                  selected: selected,
                  onChanged: appearance.choose,
                  options: [
                    (
                      value: ThemePreference.light,
                      label: l[KApp.appearanceLight]
                    ),
                    (
                      value: ThemePreference.dark,
                      label: l[KApp.appearanceDark]
                    ),
                    (
                      value: ThemePreference.system,
                      label: l[KApp.appearanceSystem]
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  /// U-21 — the pencil in a card's title. One shape for the three groups, so
  /// a reader who found one knows the other two; the key is what the tests
  /// and the E2E lane hold on to, never the glyph.
  Widget _pencil({
    required String keyName,
    required String tooltip,
    required VoidCallback onPressed,
  }) =>
      IconButton(
        key: ValueKey(keyName),
        tooltip: tooltip,
        icon: const Icon(Icons.edit_outlined),
        onPressed: onPressed,
      );

  /// U-21 — Dados at rest: the name and the role as label/value rows. The
  /// role is READ by everyone (before, only an admin ever saw it, because it
  /// only existed as the admin's dropdown); only the sheet knows who may
  /// change it. A frozen member (S-11) gets no pencil: the banner above
  /// already says nothing here can change, and an editor that the server
  /// refuses would contradict it.
  Widget _dataSection(Localization l, Member target) {
    final theme = Theme.of(context).textTheme;
    final role = _roles.where((r) => r.id == target.roleId).firstOrNull;
    return AppCard(
      title: l[K.profSectionData],
      titleTrailing: target.leftAt == null
          ? _pencil(
              keyName: 'profile-edit-data',
              tooltip: l[KApp.profEditData],
              onPressed: () => _editData(l, target),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppListRow(label: l[K.registerFullName], value: target.fullName),
          if (role != null)
            AppListRow(
                label: l[K.famRoleInFamily],
                value: role.displayLabel(l.current)),
          if (!_iAmAdmin) ...[
            const SizedBox(height: Spacing.sm),
            Text(l[K.profPersonalHint], style: theme.bodySmall),
          ],
        ],
      ),
    );
  }

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

  /// U-21 — E-mail at rest: the current address, and the "link sent" sentence
  /// once the sheet has asked for a change.
  Widget _emailSection(Localization l, Member target) {
    final theme = Theme.of(context).textTheme;
    return AppCard(
      title: l[K.profSectionEmail],
      titleTrailing: _pencil(
        keyName: 'profile-edit-email',
        tooltip: l[K.profChangeEmail],
        onPressed: () => _editEmail(target),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // U-28 defect: the key is a FORMAT string ("E-mail atual: {0}"), and
          // interpolating it printed the placeholder verbatim next to the
          // address — "E-mail atual: {0} irineus@gmail.com".
          Text(l.format(K.profCurrentEmail, [target.email ?? '']),
              style: theme.bodySmall),
          if (_emailLinkSent) ...[
            const SizedBox(height: Spacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.mark_email_read_outlined,
                    size: 16, color: context.tokens.textMuted),
                const SizedBox(width: Spacing.xs),
                Expanded(
                    child: Text(l[K.profEmailLinkSent], style: theme.bodySmall)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// U-30 — the doors this account has. The PROVIDER doors are read from the
  /// session (F-57 exposed the providers; U-30 added the identities, for the
  /// address each door opens under). The PASSWORD door is the server's answer
  /// (U-50): the providers never stand in for it.
  List<SignInMethod> _signInMethods(Member target) =>
      SignInMethodRules.methods(
        providers: widget.dataSource.authProviders(),
        identities: widget.dataSource.signInIdentities(),
        accountEmail: widget.dataSource.sessionEmail() ?? target.email,
        hasPassword: _hasPassword,
      );

  /// U-30 — "Como você entra": one row per door, each with the address it
  /// answers to and one line saying what it means. A Google sign-in with the
  /// address of a password account links the two (F-57's posture), and until
  /// this card the screen showed the password form ALONE — so "I changed my
  /// password, the account is locked" and "I changed my e-mail, I sign in with
  /// the new one" both read as true and were both false. Nothing to list when
  /// the session said nothing.
  ///
  /// The Google row carries the G itself (U-45): the generic account glyph
  /// F-57 used here is exactly the drift that decision forbids.
  List<Widget> _signInMethodsSection(Localization l, Member target) {
    final methods = _signInMethods(target);
    if (methods.isEmpty) return const [];
    final theme = Theme.of(context).textTheme;
    final several = methods.length > 1;

    Widget row(SignInMethod method) {
      final (leading, title, note) = switch (method.kind) {
        SignInMethodKind.password => (
            const Icon(Icons.key_outlined, size: GoogleBrand.logoSize),
            l[KApp.profLoginMethodPassword],
            l[KApp.profLoginMethodPasswordNote],
          ),
        SignInMethodKind.google => (
            Image.asset(GoogleBrand.logoAsset,
                width: GoogleBrand.logoSize,
                height: GoogleBrand.logoSize,
                excludeFromSemantics: true),
            l[KApp.profLoginMethodGoogle],
            // Beside a password, the sentence that survives BOTH changes;
            // alone, the F-57 sentence (there is no password to change) —
            // but only once the server SAID so (U-50). Unanswered, the row
            // claims nothing about a password.
            l[switch (SignInMethodRules.googleNote(
                methods: methods, hasPassword: _hasPassword)) {
              GoogleDoorNote.linked => KApp.profLoginMethodGoogleLinkedNote,
              GoogleDoorNote.noPassword => KApp.profLoginMethodNote,
              GoogleDoorNote.neutral => KApp.profLoginMethodGoogleNeutralNote,
            }],
          ),
        SignInMethodKind.other => (
            const Icon(Icons.login_outlined, size: GoogleBrand.logoSize),
            l.format(KApp.profLoginMethodOther, [method.provider]),
            l[KApp.profLoginMethodOtherNote],
          ),
      };
      return Row(
        key: ValueKey('sign-in-method-${method.provider}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: leading),
          const SizedBox(width: GoogleBrand.logoGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.titleSmall),
                if (method.email != null)
                  Text(method.email!, style: theme.bodyMedium),
                Text(note, style: theme.bodySmall),
              ],
            ),
          ),
        ],
      );
    }

    return [
      const SizedBox(height: 24),
      AppCard(
        title: l[KApp.profLoginMethod],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (several) ...[
              Text(l[KApp.profLoginMethodsIntro], style: theme.bodySmall),
              const SizedBox(height: 12),
            ],
            for (final (i, method) in methods.indexed) ...[
              if (i > 0) const SizedBox(height: 12),
              row(method),
            ],
          ],
        ),
      ),
    ];
  }

  /// F-57 (the U-21 slice this item requires): an account with NO password
  /// gets no "alterar senha" — it would submit against nothing, and "esqueci
  /// a atual" would e-mail a reset for a credential that does not exist. The
  /// caller keeps this card off such an account
  /// (`SignInMethodRules.showsPasswordCard`); its door is listed in
  /// [_signInMethodsSection] instead (U-30). Whether the account has one is
  /// the SERVER's answer since U-50 — F-57 read it off the providers, and one
  /// live account was told it had no password while it had.
  ///
  /// U-21 — at rest the card is one sentence; the two fields, the eye toggle
  /// and the reset-by-e-mail door all live in the sheet.
  Widget _passwordSection(Localization l, Member target) {
    final theme = Theme.of(context).textTheme;
    return AppCard(
      title: l[K.profSectionPassword],
      titleTrailing: _pencil(
        keyName: 'profile-edit-password',
        tooltip: l[K.profChangePassword],
        onPressed: () => _editPassword(l, target),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l[KApp.profPasswordSummary], style: theme.bodySmall),
          if (_passwordLinkSent) ...[
            const SizedBox(height: Spacing.sm),
            // The sentence carries `<strong>` around the address — RichLabel
            // renders it; a plain Text printed the tag to the reader.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.mark_email_read_outlined,
                    size: 16, color: context.tokens.textMuted),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: RichLabel.of(l, K.profPasswordLinkSentTo,
                      args: [target.email ?? ''], style: theme.bodySmall),
                ),
              ],
            ),
          ],
        ],
      ),
    );
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

    // F-50: a viewer's exit is a complete delete — one sentence, one button
    // (sudo asks for the password), no successor, no 30 days.
    if (_me?.isViewer == true) {
      return AppDangerZone(
        key: const ValueKey('viewer-leave'),
        title: l[K.profLeaveTitle],
        intro: l[KApp.viewerLeaveBody],
        notices: const [],
        actionLabel: l[KApp.viewerLeaveButton],
        onAction: _leaving ? null : () => _leaveAsViewer(l),
      );
    }

    // Blocked while the family itself is on the way out — the DB refuses too,
    // and the two flows would race for the same rows.
    if (_pendingDeletion != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(l[last ? K.profLeaveTitleLast : K.profLeaveTitle]),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline,
                  size: 16, color: context.tokens.textMuted),
              const SizedBox(width: Spacing.xs),
              Expanded(
                child: Text(l[K.profLeaveBlocked],
                    style: theme.textTheme.bodySmall),
              ),
            ],
          ),
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
