import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../deep_link_urls.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/family_invitation.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_db_contracts/models/subscription.dart';
import '../services/admin_mode.dart';
import '../services/analytics_service.dart';
import '../services/custody_data_source.dart';
import '../services/sudo_service.dart';
import '../theme/tokens.dart';
import '../widgets/account_button.dart';
import '../widgets/app_l10n.dart';
import '../widgets/app_snack.dart';
import '../widgets/sudo_sheet.dart';

/// U-35: the observer the Família branch's navigator reports to, so the roster
/// can reload when one of its sub-pages pops back (a plan bought, the mode
/// toggled, a deletion requested). Declared here and handed to the branch in
/// `main.dart`; a widget test that pumps the screen alone never attaches it,
/// and an observer nobody reports to is simply silent.
final RouteObserver<ModalRoute<void>> familyRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// `/family` — port of `FamilyPage.razor`.
///
/// **The page is a roster, not an editor** (F-16): tapping a member opens their
/// profile, where the name, the role and the admin flag actually change. That
/// split is the web's and it survives here, because the profile page is also
/// where e-mail, password, LGPD export and leaving the family live.
///
/// **The page is the family, and only the family** (U-35). Three things that
/// are not the roster used to share its scroll — the F-32/T-39 premium block,
/// the admin-mode card and the S-11 danger zone — and a parent opening the
/// tab to see who is in the family scrolled past a paywall and past "Excluir
/// família" every time. They are sub-pages now, each one tap away behind a
/// navigation row whose subtitle says its state: `/family/plan`,
/// `/family/admin-mode` and `/family/delete`.
///
/// What stays inline is the PENDING deletion: unanimity means every voter has
/// an explicit `agreed` row, a missing answer is not consent — silence never
/// deletes a family — and one refusal ends the request outright. That panel
/// is a countdown the whole family must see, and the shell banner already
/// points here.
class FamilyScreen extends StatefulWidget {
  final CustodyDataSource dataSource;

  /// T-37 — optional: the viral-loop signal never gates an invitation.
  final AnalyticsService? analytics;
  final AdminMode adminMode;
  final SudoService sudo;

  /// Opens the F-41 page. Null hides the link (nothing to navigate to).
  final VoidCallback? onOpenCustomRoles;

  /// Opens a member's profile — own card or, for an admin, anyone's (F-16).
  /// Null leaves the cards inert.
  final void Function(Member member, bool isOwn)? onOpenProfile;

  /// Called when the family is gone — every session must end.
  final Future<void> Function()? onFamilyDeleted;

  /// U-35: the three sub-pages. Each null hides its row — the row is the only
  /// way in, so a page nothing navigates to is a page nobody is offered.
  /// [onOpenPlan] is also where every Premium gate CTA on this screen lands.
  final VoidCallback? onOpenPlan;
  final VoidCallback? onOpenAdminMode;
  final VoidCallback? onOpenDeletion;

  /// F-63: hands the invitation message to the system share sheet. A seam so
  /// a widget test can read what would be sent; null uses share_plus.
  final Future<void> Function(String message)? onShareInvite;

  const FamilyScreen({
    super.key,
    required this.dataSource,
    required this.adminMode,
    required this.sudo,
    this.analytics,
    this.onOpenCustomRoles,
    this.onOpenProfile,
    this.onFamilyDeleted,
    this.onOpenPlan,
    this.onOpenAdminMode,
    this.onOpenDeletion,
    this.onShareInvite,
  });

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> with RouteAware {
  bool _loading = true;
  String? _loadErrorKey;

  Family? _family;
  Member? _me;
  List<Member> _members = const [];
  List<Role> _roles = const [];
  List<FamilyInvitation> _invitations = const [];
  PublicSettings _settings = PublicSettings.unloaded;

  // Rename
  bool _editingName = false;
  final _nameDraft = TextEditingController();

  // Invite form
  final _inviteEmail = TextEditingController();
  // F-56: the form names the person first — that name IS the placeholder.
  final _inviteName = TextEditingController();
  int _inviteRoleId = 0;
  String? _inviteErrorKey;
  bool _sendingInvite = false;

  // The subscription row is read for ONE line here — the plan row's subtitle
  // ("Premium até …"). Entitlement always comes from the family row through
  // the mirror, never from here; everything else about billing is the plan
  // page's (U-35).
  Subscription? _subscription;

  // S-11 family deletion — the PENDING panel only; the request lives on
  // `/family/delete`.
  PendingFamilyDeletion? _deletion;
  bool _confirmingExecute = false;
  bool _deletionBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) familyRouteObserver.subscribe(this, route);
  }

  /// A sub-page popped back onto this one: what it changed (a plan, the mode,
  /// a deletion request) is what the rows summarise, so read it again —
  /// quietly, the roster is already on screen and a skeleton would flash.
  @override
  void didPopNext() => _load(quiet: true);

  @override
  void dispose() {
    familyRouteObserver.unsubscribe(this);
    _nameDraft.dispose();
    _inviteEmail.dispose();
    _inviteName.dispose();
    super.dispose();
  }

  bool get _isAdmin => _me?.isAdmin == true;

  int get _activeMemberCount =>
      _members.where((m) => m.isActiveMember).length;

  /// F-56: a seat is held by everyone still IN the family — a pending member
  /// (invited, not yet joined) as much as a live one. Only the S-11 tombstone
  /// holds none.
  int get _seatedMemberCount => _members.where((m) => !m.hasLeft).length;

  /// Open invitations that are NOT a placeholder's: a placeholder's invitation
  /// is the placeholder's seat, already counted above.
  int get _pendingInvitationCount {
    final now = DateTime.now().toUtc();
    return _invitations
        .where((i) => i.profileId == null && i.isPending(now))
        .length;
  }

  int get _seatsTaken => seatsTaken(
      activeMembers: _seatedMemberCount,
      pendingInvitations: _pendingInvitationCount);

  /// F-56: the open (pending or expired, never accepted/revoked) invitation a
  /// placeholder currently has, if any — decides "Convidar" vs the card below.
  FamilyInvitation? _invitationFor(Member member) {
    for (final i in _invitations) {
      if (i.profileId == member.id) return i;
    }
    return null;
  }

  bool get _isPremium =>
      Family.isPremiumFamily(_family, DateTime.now().toUtc());

  /// How the entitlement was reached — badge, countdown and the state machine
  /// below all read this one snapshot so they cannot disagree.
  PlanStatus get _planStatus => describePlan(
        plan: _family?.plan,
        trialEndsAtUtc: _family?.trialEndsAt,
        nowUtc: DateTime.now().toUtc(),
        compPremiumAtUtc: _family?.compPremiumAt,
      );

  bool get _atFreeCap => atFreeCaregiverCap(
      isPremium: _isPremium,
      seatsTaken: _seatsTaken,
      freeLimit: _settings.freeCaregivers);

  Future<void> _load({bool quiet = false}) async {
    setState(() {
      if (!quiet) _loading = true;
      _loadErrorKey = null;
    });
    try {
      final results = await Future.wait([
        widget.dataSource.fetchOwnFamily(),
        widget.dataSource.fetchMembers(),
        widget.dataSource.fetchRoles(),
        widget.dataSource.fetchOwnProfile(),
        widget.dataSource.fetchPublicSettings(),
      ]);
      final family = results[0] as Family?;
      final members = (results[1] as List<Member>).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      final settings = PublicSettings(results[4] as Map<String, String>);

      // Web parity: the list is only fetched while there is a seat to fill —
      // it also feeds the seat arithmetic, so an empty list at the cap is
      // deliberate, not a bug.
      // F-56: also fetched whenever a placeholder exists, at the cap or not —
      // its card needs to know whether an invitation is out.
      final seated = members.where((m) => !m.hasLeft).length;
      final invitations = seated < settings.maxCaregivers ||
              members.any((m) => m.isPendingMember)
          ? await widget.dataSource.fetchOpenInvitations()
          : <FamilyInvitation>[];
      final deletion = await widget.dataSource.fetchPendingFamilyDeletion();

      // T-39: the subscription row only matters while billing is on — with the
      // master switch off there is no paid period to summarise, and asking for
      // a row we would ignore is a round-trip for nothing.
      final subscription = settings.billingEnabled
          ? await widget.dataSource.fetchSubscription()
          : null;

      if (!mounted) return;
      setState(() {
        _subscription = subscription;
        _deletion = deletion;
        _family = family;
        _members = members;
        _roles = results[2] as List<Role>;
        _me = results[3] as Member?;
        _settings = settings;
        _invitations = invitations;
        _nameDraft.text = family?.name ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadErrorKey = isSessionExpired(e.toString())
            ? KApp.sessionExpired
            : KApp.errCalendarLoad;
      });
    }
  }

  String _roleLabel(int? roleId, AppLanguage language) {
    if (roleId == null) return '';
    for (final role in _roles) {
      if (role.id == roleId) return role.displayLabel(language);
    }
    return '';
  }

  Future<void> _saveName(Localization l) async {
    final name = _nameDraft.text.trim();
    if (name.isEmpty) {
      showAppSnack(context, l[K.famErrFamilyNameRequired],
          type: AppSnackType.error);
      return;
    }
    // No-op short-circuit, as the web does — a rename that changes nothing
    // should not write an audit row.
    if (name == _family?.name) {
      setState(() => _editingName = false);
      return;
    }
    try {
      await widget.dataSource.renameFamily(name);
      if (!mounted) return;
      setState(() => _editingName = false);
      showAppSnack(context, l[K.famToastRenamed]);
      await _load();
    } catch (e) {
      if (!mounted) return;
      // The RPC's own PT-BR refusal is the useful text here.
      showAppSnack(context, translateSaveError(e.toString(), l[K.errSaveFailed], l),
          type: AppSnackType.error);
    }
  }

  /// F-56: every addition is a PENDING member first — `add_pending_member`
  /// creates the placeholder and, when an e-mail was typed, the invitation in
  /// the same transaction (a refused e-mail leaves no orphan). Without an
  /// e-mail the admin plans alone and invites later from the member's card.
  Future<void> _sendInvite(Localization l) async {
    final errorKey = InviteFormRules.validationErrorKey(
      fullName: _inviteName.text,
      email: _inviteEmail.text,
      myEmail: _me?.email,
      roleId: _inviteRoleId,
    );
    if (errorKey != null) {
      setState(() => _inviteErrorKey = errorKey);
      return;
    }
    setState(() {
      _sendingInvite = true;
      _inviteErrorKey = null;
    });
    final name = _inviteName.text.trim();
    final email = _inviteEmail.text.trim();
    try {
      final born = await widget.dataSource.addPendingMember(
        fullName: name,
        roleId: _inviteRoleId,
        email: email.isEmpty ? null : email,
      );
      final invitationId = born.invitationId;
      final mailed = invitationId == null
          ? false
          : await widget.dataSource.sendInvitationEmail(invitationId);
      if (!mounted) return;
      _inviteEmail.clear();
      _inviteName.clear();
      setState(() {
        _inviteRoleId = 0;
        _sendingInvite = false;
      });
      if (invitationId == null) {
        widget.analytics?.trackEvent('invite_sent', props: {'email': 'none'});
        showAppSnack(context, l.format(KApp.famPendingAdded, [name]),
            type: AppSnackType.success);
      } else {
        // T-37: viral loop initiated — whether the e-mail went out or the
        // family will have to share the link themselves.
        widget.analytics?.trackEvent('invite_sent',
            props: {'email': mailed ? 'sent' : 'link_only'});
        showAppSnack(
            context, l[mailed ? K.famInviteEmailSent : K.famInviteEmailFailed],
            type: mailed ? AppSnackType.success : AppSnackType.info);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendingInvite = false);
      // Every cap and permission refusal is the RPC's own sentence — it says
      // exactly which limit was hit, which no generic message could.
      showAppSnack(context, translateSaveError(e.toString(), l[K.errSaveFailed], l),
          type: AppSnackType.error);
    }
  }

  Future<void> _resendInvite(FamilyInvitation invitation, Localization l) async {
    try {
      // Resend semantics live entirely in the RPC: it revokes the previous
      // open invitation for this address before counting seats, so this never
      // trips its own cap. F-56: a placeholder's invitation carries the
      // placeholder along, or the resend would create a placeholder-less one.
      final id = await widget.dataSource.createInvitation(
          email: invitation.email,
          roleId: invitation.roleId,
          profileId: invitation.profileId);
      final mailed = await widget.dataSource.sendInvitationEmail(id);
      if (!mounted) return;
      showAppSnack(
          context,
          l[mailed ? K.famInviteResent : K.famInviteRenewedEmailFailed],
          type: mailed ? AppSnackType.success : AppSnackType.info);
      await _load();
    } catch (_) {
      if (!mounted) return;
      showAppSnack(context, l[K.famErrResendInvite], type: AppSnackType.error);
    }
  }

  Future<void> _revokeInvite(FamilyInvitation invitation, Localization l) async {
    try {
      await widget.dataSource.revokeInvitation(invitation.id);
      if (!mounted) return;
      showAppSnack(context, l[K.famInviteRevoked]);
      await _load();
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, translateSaveError(e.toString(), l[K.errSaveFailed], l),
          type: AppSnackType.error);
    }
  }

  Future<void> _copyLink(FamilyInvitation invitation, Localization l) async {
    final link =
        InviteFormRules.inviteLink(DeepLinkUrls.webOrigin, invitation.token);
    try {
      await Clipboard.setData(ClipboardData(text: link));
      if (!mounted) return;
      showAppSnack(context, l[K.famLinkCopied]);
    } catch (_) {
      if (!mounted) return;
      showAppSnack(context, l[K.famErrCopy], type: AppSnackType.error);
    }
  }

  /// The native improvement over the web's "copy it and send on WhatsApp"
  /// hint: the system share sheet already knows every app this person uses.
  /// F-63: it sends a sentence with the link — a bare URL from a co-parent is
  /// an unexplained link in the chat. "Copiar link" still copies the link only.
  Future<void> _shareLink(FamilyInvitation invitation, Localization l) async {
    final link =
        InviteFormRules.inviteLink(DeepLinkUrls.webOrigin, invitation.token);
    final message =
        InviteFormRules.inviteShareMessage(l[K.famInviteShareText], link);
    final share = widget.onShareInvite;
    if (share != null) {
      await share(message);
    } else {
      await Share.share(message);
    }
  }

  /// F-56: invite a placeholder that has no open invitation — the one moment
  /// the invitee's e-mail enters the system, and only for as long as the
  /// invitation lives.
  Future<void> _invitePending(Member member, Localization l) async {
    final email = await showAppSheet<String>(
      context: context,
      builder: (context) => _InvitePendingSheet(
        title: l.format(KApp.famPendingInviteTitle, [member.fullName]),
        myEmail: _me?.email,
      ),
    );
    if (email == null || !mounted) return;
    try {
      final id = await widget.dataSource.createInvitation(
          email: email, roleId: member.roleId ?? 0, profileId: member.id);
      final mailed = await widget.dataSource.sendInvitationEmail(id);
      if (!mounted) return;
      widget.analytics?.trackEvent('invite_sent',
          props: {'email': mailed ? 'sent' : 'link_only'});
      showAppSnack(
          context, l[mailed ? K.famInviteEmailSent : K.famInviteEmailFailed],
          type: mailed ? AppSnackType.success : AppSnackType.info);
      await _load();
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, translateSaveError(e.toString(), l[K.errSaveFailed], l),
          type: AppSnackType.error);
    }
  }

  /// F-62: a LEGACY invitation — issued before F-56, or by an Android build
  /// not yet promoted — has an e-mail and a role but nobody to plan days for.
  /// The sheet asks the one thing missing, the name, and the RPC attaches a
  /// placeholder to THAT invitation: same row, same token. Resending instead
  /// would revoke the link the person already holds, which is the whole
  /// reason this is not `_resendInvite`.
  Future<void> _attachPending(FamilyInvitation invitation, Localization l) async {
    final name = await showAppSheet<String>(
      context: context,
      builder: (context) => _AttachPendingSheet(
        title: l.format(KApp.famAttachTitle, [invitation.email]),
      ),
    );
    if (name == null || !mounted) return;
    try {
      await widget.dataSource.attachPendingMember(
          invitationId: invitation.id, fullName: name);
      if (!mounted) return;
      showAppSnack(context, l.format(KApp.famAttached, [name]),
          type: AppSnackType.success);
      await _load();
    } catch (e) {
      if (!mounted) return;
      // The RPC's own sentence: which refusal (accepted, revoked, cap) it was.
      showAppSnack(context, translateSaveError(e.toString(), l[K.errSaveFailed], l),
          type: AppSnackType.error);
    }
  }

  /// F-56: a typo must not hold one of four seats forever. The RPC deletes a
  /// never-planned placeholder and freezes one with history (future days
  /// freed, the name kept on the past) — the confirmation says exactly that.
  Future<void> _removePending(Member member, Localization l) async {
    final confirmed = await showAppSheet<bool>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.format(KApp.famPendingRemoveConfirm, [member.fullName])),
          const SizedBox(height: Spacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l[K.commonCancel]),
              ),
              const SizedBox(width: Spacing.sm),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l[KApp.famPendingRemove]),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.dataSource.removePendingMember(member.id);
      if (!mounted) return;
      showAppSnack(context, l.format(KApp.famPendingRemoved, [member.fullName]));
      await _load();
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, translateSaveError(e.toString(), l[K.errSaveFailed], l),
          type: AppSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
            title: Text(l[K.famHeading]),
            actions: const [AppAccountButton()]),
        // U-27: the word "Carregando" said nothing about what was coming; the
        // skeleton outlines the carer cards that are.
        body: AppSkeletonList(semanticsLabel: l[K.famLoading]),
      );
    }
    if (_loadErrorKey != null) {
      return Scaffold(
        appBar: AppBar(
            title: Text(l[K.famHeading]),
            actions: const [AppAccountButton()]),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l[_loadErrorKey!]),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: Text(l[K.layoutErrorReload])),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
            title: Text(l[K.famHeading]),
            actions: const [AppAccountButton()]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _familyNameBlock(l),
            const SizedBox(height: 24),
            _sectionTitle(l[K.famCaregivers]),
            ..._members.map((m) => _memberCard(m, l)),
            const SizedBox(height: 24),
            _inviteSection(l),
            // U-35: the three things that are not the family, one tap away.
            // The plan row is for everyone (the state is the family's); the
            // mode is the admin's tool; the deletion row appears only while
            // this reader may open a request, and a request already open is
            // the inline panel below, never a row.
            const SizedBox(height: 24),
            if (widget.onOpenPlan != null) _planRow(l),
            if (_isAdmin && widget.onOpenAdminMode != null) _adminModeRow(l),
            if (_deletion == null &&
                widget.onOpenDeletion != null &&
                FamilyLifecycleRules.canRequestFamilyDeletion(
                    isAdmin: _isAdmin, activeMemberCount: _activeMemberCount))
              _deletionRow(l),
            if (_deletion case final deletion?) ...[
              const SizedBox(height: 24),
              _deletionPendingPanel(l, deletion),
            ],
          ],
        ),
      ),
    );
  }

  // The 8px that used to follow every call site now lives in the component,
  // which is the point: a section's spacing is not each screen's decision.
  Widget _sectionTitle(String text) =>
      AppSectionHeader(title: text, topSpacing: 0);

  Widget _familyNameBlock(Localization l) {
    if (!_editingName) {
      return Row(
        children: [
          Expanded(
            child: Text(_family?.name ?? '',
                style: Theme.of(context).textTheme.headlineSmall),
          ),
          if (_isAdmin)
            IconButton(
              tooltip: l[K.famRename],
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => setState(() {
                _nameDraft.text = _family?.name ?? '';
                _editingName = true;
              }),
            ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: AppTextField(
            label: l[K.registerFamilyName],
            controller: _nameDraft,
            maxLength: RegisterRules.maxNameLength,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.check),
          onPressed: () => _saveName(l),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => _editingName = false),
        ),
      ],
    );
  }

  Widget _memberCard(Member member, Localization l) {
    final theme = Theme.of(context);
    final role = _roleLabel(member.roleId, l.current);
    final isOwn = member.id == _me?.id;
    // Web parity: my own card always opens; anyone else's only for an admin.
    final canOpen =
        widget.onOpenProfile != null && (isOwn || _isAdmin);
    // U-28: the name gets ONE line and the badges go under it.
    //
    // They used to share the row: the name in a `Flexible` title, the badges in
    // a `Wrap` trailing. `ListTile` gives the trailing what it asks for, so a
    // carer who is both "(você)" and "Admin" squeezed the title to about a
    // third of the row and a full legal name came out four lines tall — which
    // is what made the admin's card twice the height of everyone else's.
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: canOpen ? () => widget.onOpenProfile!(member, isOwn) : null,
        subtitleTextStyle: theme.textTheme.bodyMedium,
        // F-56: a pending member wears its own colour — the grey texture is
        // the departure's, not the missing account's.
        leading: AppAvatar(
            initials: member.initial,
            slot: member.hasLeft
                ? context.tokens.slot(0)
                : context.tokens.slot(member.colorSlot)),
        title: Text(
          member.id == _me?.id
              ? '${member.fullName} ${l[K.famYou]}'
              : member.fullName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (role.isNotEmpty)
                    Text(role, style: theme.textTheme.bodySmall),
                  if (member.hasLeft)
                    AppBadge(
                        text: l[K.famLeftBadge], tone: context.tokens.neutral),
                  if (member.isPendingMember)
                    AppBadge(
                        text: l[KApp.famPendingBadge],
                        tone: context.tokens.info),
                  if (member.isAdmin)
                    AppBadge(
                        text: l[K.famAdminBadge], tone: context.tokens.accent),
                ],
              ),
              // F-56: what a placeholder is, and the admin's two moves on it.
              // "Convidar" only while no invitation is out — the invitation
              // card below carries resend/revoke once one exists.
              if (member.isPendingMember) ...[
                const SizedBox(height: Spacing.xs),
                Text(l[KApp.famPendingHint], style: theme.textTheme.bodySmall),
                if (_isAdmin)
                  Wrap(
                    spacing: Spacing.xs,
                    children: [
                      if (_invitationFor(member) == null)
                        TextButton(
                          onPressed: () => _invitePending(member, l),
                          child: Text(l[KApp.famPendingInvite]),
                        ),
                      TextButton(
                        onPressed: () => _removePending(member, l),
                        child: Text(l[KApp.famPendingRemove]),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
        // U-28: the affordance the port dropped — without it nothing says a
        // row opens anything.
        trailing: canOpen ? const Icon(Icons.chevron_right) : null,
      ),
    );
  }

  Widget _inviteSection(Localization l) {
    // Web parity: the whole block disappears once every seat is filled by a
    // live member — there is nothing to offer and nothing to revoke.
    if (_activeMemberCount >= _settings.maxCaregivers) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now().toUtc();
    final pending = _invitations.where((i) => i.isPending(now)).toList();
    final expired = _invitations.where((i) => i.isExpired(now)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l[K.famInviteSection]),
        // U-28: the panel the web draws around this block. Without it the form,
        // its notices and the buttons were loose on the page background — the
        // "seções soltas" the owner's review named.
        if (!_isAdmin)
          AppCard(
              child: Text(l[K.famOnlyAdminsInvite],
                  style: Theme.of(context).textTheme.bodySmall))
        else ...[
          ...pending.map((i) => _invitationCard(i, l, expired: false)),
          ...expired.map((i) => _invitationCard(i, l, expired: true)),
          if (_atFreeCap)
            // F-37: the cap notice plus the CTA that takes the admin to the
            // plan page. The CTA never carries a price or an external link —
            // it navigates, and the page decides what the CHANNEL may offer
            // (T-38).
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l[K.famFreeCapNotice]),
                    if (widget.onOpenPlan != null)
                      TextButton.icon(
                        onPressed: () => _goToPremium('extra-caregiver'),
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: Text(l[K.famSeePremium]),
                      ),
                  ],
                ),
              ),
            )
          else if (_seatsTaken < _settings.maxCaregivers)
            AppCard(child: _inviteForm(l))
          else if (pending.isEmpty && expired.isEmpty)
            AppCard(
                child: Text(l.format(
                    K.famSeatsFull, [_settings.maxCaregivers]))),
        ],
      ],
    );
  }

  Widget _invitationCard(FamilyInvitation invitation, Localization l,
      {required bool expired}) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // F-56: a placeholder's invitation says whose it is.
            if (_placeholderNameFor(invitation) case final name?)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(name, style: theme.textTheme.titleSmall),
              ),
            Row(
              children: [
                Expanded(child: Text(invitation.email)),
                // U-29: a row's state is an AppBadge everywhere else in the
                // app — this was the one place it was still a grey text run.
                AppBadge(
                  text: expired
                      ? l[K.famInviteExpiredBadge]
                      : l[K.famInviteSentBadge],
                  tone: expired
                      ? context.tokens.warning
                      : context.tokens.info,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_roleLabel(invitation.roleId, l.current),
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            if (expired)
              Text(l[K.famInviteExpiredHint], style: theme.textTheme.bodySmall)
            else
              Text(
                  l.format(K.famInviteValidUntil,
                      [l.formatDate(invitation.expiresAt.toLocal())]),
                  style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                // F-62: no placeholder behind this invitation — offer one
                // without touching the token. Expired or not: the placeholder
                // outlives the link, and a resend afterwards carries it.
                if (invitation.profileId == null)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                    label: Text(l[KApp.famAttachInvite]),
                    onPressed: () => _attachPending(invitation, l),
                  ),
                if (!expired) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(l[K.famCopyLink]),
                    onPressed: () => _copyLink(invitation, l),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: Text(l[KApp.commonShare]),
                    onPressed: () => _shareLink(invitation, l),
                  ),
                ],
                TextButton.icon(
                  onPressed: () => _resendInvite(invitation, l),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l[K.famResendInvite]),
                ),
                TextButton(
                  onPressed: () => _revokeInvite(invitation, l),
                  child: Text(l[K.famRevoke]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// F-56: the name the admin gave a placeholder, for its invitation card.
  String? _placeholderNameFor(FamilyInvitation invitation) {
    final id = invitation.profileId;
    if (id == null) return null;
    for (final m in _members) {
      if (m.id == id) return m.fullName;
    }
    return null;
  }

  Widget _inviteForm(Localization l) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.format(K.famInviteWhoHelps, [_settings.maxCaregivers]),
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        // F-56: the person first. The name is what the calendar shows from
        // today; the e-mail is optional — with it the invitation goes out
        // now, without it the admin plans alone and invites later.
        AppTextField(
          label: l[KApp.famInviteName],
          hint: l[KApp.famInviteNameHint],
          controller: _inviteName,
        ),
        const SizedBox(height: 12),
        AppTextField(
          label: l[K.commonEmail],
          hint: l[K.famInviteEmailPlaceholder],
          controller: _inviteEmail,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 4),
        Text(l[KApp.famInviteEmailOptional], style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _inviteRoleId == 0 ? null : _inviteRoleId,
          decoration: InputDecoration(labelText: l[K.famRoleInFamily]),
          items: [
            for (final role in _roles)
              DropdownMenuItem(
                value: role.id,
                child: Text(role.displayLabel(l.current)),
              ),
          ],
          onChanged: (value) => setState(() => _inviteRoleId = value ?? 0),
        ),
        if (widget.onOpenCustomRoles != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.onOpenCustomRoles,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(l[K.famCustomRolesLink]),
            ),
          ),
        if (_inviteErrorKey != null) ...[
          const SizedBox(height: 8),
          Text(l[_inviteErrorKey!],
              style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 12),
        // The button says what will happen: an invitation when there is an
        // address to send it to, a calendar entry otherwise.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _inviteEmail,
          builder: (context, value, _) => FilledButton(
            onPressed: _sendingInvite ? null : () => _sendInvite(l),
            child: Text(_sendingInvite
                ? l[K.famSending]
                : value.text.trim().isEmpty
                    ? l[KApp.famAddWithoutInvite]
                    : l[K.famSendInvite]),
          ),
        ),
        const SizedBox(height: 8),
        Text(l[K.famInviteWhatsapp], style: theme.textTheme.bodySmall),
      ],
    );
  }

  // ── S-11: deleting the whole family ──────────────────────────────────────

  List<LifecycleMember> get _lifecycleMembers => _members
      .map((m) => LifecycleMember(
          id: m.id, isActiveMember: m.isActiveMember, isAdmin: m.isAdmin))
      .toList();

  List<DeletionVote> get _votes =>
      (_deletion?.responses ?? const [])
          .map((r) => DeletionVote(profileId: r.profileId, agreed: r.agreed))
          .toList();

  bool get _allAgreed {
    final deletion = _deletion;
    if (deletion == null) return false;
    return FamilyLifecycleRules.allAgreed(
      members: _lifecycleMembers,
      requesterProfileId: deletion.request.requestedBy,
      votes: _votes,
    );
  }

  Future<void> _runDeletionAction(
    Localization l, {
    required Future<void> Function() action,
    required bool sudo,
    String? successKey,
  }) async {
    if (_deletionBusy) return;
    setState(() => _deletionBusy = true);
    try {
      final ran = sudo
          ? await runWithSudo(
              context: context, sudo: widget.sudo, action: action)
          : await action().then((_) => true);
      if (!mounted) return;
      setState(() {
        _deletionBusy = false;
        _confirmingExecute = false;
      });
      if (!ran) return;
      if (successKey != null) showAppSnack(context, l[successKey]);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletionBusy = false);
      showAppSnack(
          context, translateSaveError(e.toString(), l[K.errSaveFailed], l),
          type: AppSnackType.error);
    }
  }

  Future<void> _executeNow(Localization l) async {
    if (_deletionBusy) return;
    setState(() => _deletionBusy = true);
    try {
      final ran = await runWithSudo(
        context: context,
        sudo: widget.sudo,
        action: widget.dataSource.executeFamilyDeletion,
      );
      if (!mounted) return;
      if (!ran) {
        setState(() => _deletionBusy = false);
        return;
      }
      // Best-effort: the row is already scheduled for now, so the cron would
      // finish the job anyway — this just makes it immediate.
      await widget.dataSource.purgeNow();
      // Every session ends here, including this one: the family is gone.
      await widget.onFamilyDeleted?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletionBusy = false);
      showAppSnack(
          context, translateSaveError(e.toString(), l[K.errSaveFailed], l),
          type: AppSnackType.error);
    }
  }

  /// A gate CTA was tapped: record the intent signal (T-37, one event family
  /// distinguished by `gate`) and open the plan page. Never a price and never
  /// an external link — what may be OFFERED is that page's call, and it
  /// depends on the channel.
  void _goToPremium(String gate) {
    widget.analytics?.trackEvent('premium-gate-click', props: {'gate': gate});
    widget.onOpenPlan?.call();
  }

  // ── U-35: the rows to the sub-pages. Same shape as the member cards (a
  // `Card` around a `ListTile`, chevron trailing), so the roster reads as one
  // list of things that open; the subtitle is the page's state, so the reader
  // learns it without the tap.

  Widget _navRow({
    required Key key,
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) =>
      Card(
        key: key,
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
        ),
      );

  /// *Plano e pagamento*, subtitled with the plan's state — from the SAME
  /// snapshot the plan page reads, so the two never disagree.
  Widget _planRow(Localization l) {
    final row = describePlanRow(
      plan: _planStatus,
      currentPeriodEndUtc: _subscription?.currentPeriodEnd,
      nowUtc: DateTime.now().toUtc(),
    );
    final subtitle = switch (row.kind) {
      PlanRowKind.trial => l.format(
          row.trialDaysLeft == 1
              ? KApp.famPlanRowTrialOne
              : KApp.famPlanRowTrialMany,
          [row.trialDaysLeft]),
      PlanRowKind.premiumUntil => l.format(KApp.famPlanRowPremiumUntil,
          [l.formatDate(row.untilUtc!.toLocal())]),
      PlanRowKind.premium => l[KApp.famPlanRowPremium],
      PlanRowKind.free => l[KApp.famPlanRowFree],
    };
    return _navRow(
      key: const ValueKey('family-plan-row'),
      icon: Icons.workspace_premium_outlined,
      title: l[KApp.famPlanRow],
      subtitle: subtitle,
      onTap: widget.onOpenPlan!,
    );
  }

  /// *Modo administrador*, subtitled on/off — read live, the mode is a
  /// `Listenable` and the shell banner may turn it off under this page.
  Widget _adminModeRow(Localization l) => ListenableBuilder(
        listenable: widget.adminMode,
        builder: (context, _) => _navRow(
          key: const ValueKey('family-admin-mode-row'),
          icon: widget.adminMode.isActive
              ? Icons.shield
              : Icons.shield_outlined,
          title: l[KApp.famAdminRow],
          subtitle: l[widget.adminMode.isActive
              ? KApp.famAdminRowOn
              : KApp.famAdminRowOff],
          onTap: widget.onOpenAdminMode!,
        ),
      );

  /// *Excluir família* — the row is plain on purpose, and says nothing more:
  /// the danger tone and the consequences belong to the zone it opens, and a
  /// red warning at the end of every roster visit is the thing U-35 exists to
  /// remove.
  Widget _deletionRow(Localization l) => _navRow(
        key: const ValueKey('family-delete-row'),
        icon: Icons.delete_outline,
        title: l[K.famDelReqTitle],
        onTap: widget.onOpenDeletion!,
      );

  Widget _deletionPendingPanel(
      Localization l, PendingFamilyDeletion deletion) {
    final theme = Theme.of(context);
    final request = deletion.request;
    final iAmRequester = request.requestedBy == _me?.id;
    final allAgreed = _allAgreed;
    final myVote =
        _me == null ? null : FamilyLifecycleRules.voteOf(_votes, _me!.id);
    final requesterName = _members
            .where((m) => m.id == request.requestedBy)
            .map((m) => m.fullName)
            .firstOrNull ??
        l[K.famRequesterFallback];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l[K.famDelTitle]),
        if (allAgreed) ...[
          Text(l.format(K.famDelAllAgreed,
              [l.formatDate(request.scheduledFor.toLocal())])),
          const SizedBox(height: 4),
          Text(_isAdmin ? l[K.famDelAllAgreedAdmin] : l[K.famDelAllAgreedMember],
              style: theme.textTheme.bodySmall),
        ] else
          Text(l.format(K.famDelRequested, [
            requesterName,
            l.formatDateShort(request.requestedAt.toLocal()),
            l.formatDate(request.scheduledFor.toLocal()),
          ])),
        const SizedBox(height: 12),
        // U-29: AppBulletList instead of hand-glued `•` — a wrapping notice
        // keeps its second line under the text, which is why the component
        // exists (the danger zones already learned this).
        AppBulletList(items: [
          for (final consequence in [
            K.famDelConsequenceSilence,
            K.famDelConsequenceUnanimity,
            K.famDelConsequenceBlocked,
            K.famDelConsequenceExport,
          ])
            l[consequence],
        ]),
        const SizedBox(height: 12),
        // Who said what — an absent row reads "aguardando", never "concordou".
        for (final voter in FamilyLifecycleRules.voters(
            _lifecycleMembers, request.requestedBy))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${_members.where((m) => m.id == voter.id).map((m) => m.fullName).firstOrNull ?? ''}'
              ' — ${switch (FamilyLifecycleRules.voteOf(_votes, voter.id)) {
                true => l[K.famDelVoteAgreed],
                false => l[K.famDelVoteRefused],
                null => l[K.famDelVoteWaiting],
              }}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 12),
        if (iAmRequester)
          OutlinedButton(
            onPressed: _deletionBusy
                ? null
                : () => _runDeletionAction(
                      l,
                      sudo: true,
                      successKey: K.famToastWithdrawn,
                      action: () async {
                        await widget.dataSource.withdrawFamilyDeletion();
                        await widget.dataSource
                            .sendAccountEmail('family_deletion_withdrawn');
                      },
                    ),
            child: Text(l[K.famDelWithdraw]),
          )
        else ...[
          // Refusing is NOT sudo-gated: it is the safe answer, and putting a
          // password in front of "keep my family" would be backwards.
          OutlinedButton(
            onPressed: _deletionBusy
                ? null
                : () => _runDeletionAction(
                      l,
                      sudo: false,
                      successKey: K.famToastRefused,
                      action: () async {
                        await widget.dataSource.respondFamilyDeletion(false);
                        await widget.dataSource
                            .sendAccountEmail('family_deletion_refused');
                      },
                    ),
            child: Text(l[K.famDelRefuseKeep]),
          ),
          const SizedBox(height: 8),
          if (myVote == true)
            TextButton(
              onPressed: _deletionBusy
                  ? null
                  : () => _runDeletionAction(
                        l,
                        sudo: false,
                        successKey: K.famToastAgreementUndone,
                        // A null answer REMOVES the row — back to waiting,
                        // which is not the same as refusing.
                        action: () =>
                            widget.dataSource.respondFamilyDeletion(null),
                      ),
              child: Text(l[K.famDelUndoAgreement]),
            )
          else
            TextButton(
              onPressed: _deletionBusy
                  ? null
                  : () => _runDeletionAction(
                        l,
                        sudo: false,
                        successKey: K.famToastAgreed,
                        action: () =>
                            widget.dataSource.respondFamilyDeletion(true),
                      ),
              child: Text(l[K.famDelAgree]),
            ),
        ],
        if (FamilyLifecycleRules.canExecuteNow(
            isAdmin: _isAdmin, allAgreed: allAgreed)) ...[
          const SizedBox(height: 12),
          if (!_confirmingExecute)
            OutlinedButton.icon(
              onPressed: () => setState(() => _confirmingExecute = true),
              icon: const Icon(Icons.delete_outline),
              label: Text(l[K.famDelExecuteNowOpen]),
            )
          else ...[
            Text(l[K.famDelExecuteConfirmText],
                style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            // U-29: "Excluir agora" is the most destructive tap in the app —
            // it takes the danger tone, not the brand one.
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: context.tokens.danger.solid,
                  foregroundColor: context.tokens.danger.onSolid),
              onPressed: _deletionBusy ? null : () => _executeNow(l),
              child: Text(l[K.famDelExecuteNow]),
            ),
            TextButton(
              onPressed: () => setState(() => _confirmingExecute = false),
              child: Text(l[K.famDelBack]),
            ),
          ],
        ],
      ],
    );
  }

}

/// F-62: the one question an admin answers to give a legacy invitation its
/// placeholder — the name. E-mail and role are already the invitation's; the
/// sheet hands the name back and the page attaches the placeholder to THAT
/// invitation, token untouched.
class _AttachPendingSheet extends StatefulWidget {
  final String title;

  const _AttachPendingSheet({required this.title});

  @override
  State<_AttachPendingSheet> createState() => _AttachPendingSheetState();
}

class _AttachPendingSheetState extends State<_AttachPendingSheet> {
  final _name = TextEditingController();
  String? _errorKey;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final errorKey = InviteFormRules.nameErrorKey(_name.text);
    if (errorKey != null) {
      setState(() => _errorKey = errorKey);
      return;
    }
    Navigator.of(context).pop(_name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: theme.textTheme.titleMedium),
        const SizedBox(height: Spacing.xs),
        Text(l[KApp.famAttachHint], style: theme.textTheme.bodySmall),
        const SizedBox(height: Spacing.md),
        AppTextField(
          label: l[KApp.famInviteName],
          hint: l[KApp.famInviteNameHint],
          controller: _name,
          maxLength: RegisterRules.maxNameLength,
          errorText: _errorKey == null ? null : l[_errorKey!],
          autofocus: true,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: Spacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l[K.commonCancel]),
            ),
            const SizedBox(width: Spacing.sm),
            FilledButton(
              onPressed: _submit,
              child: Text(l[KApp.famAttachInvite]),
            ),
          ],
        ),
      ],
    );
  }
}

/// F-56: the one question an admin answers to invite a placeholder — the
/// address. Name and role are already the member's; the sheet hands the
/// e-mail back and the page issues the invitation FOR that profile.
class _InvitePendingSheet extends StatefulWidget {
  final String title;
  final String? myEmail;

  const _InvitePendingSheet({required this.title, required this.myEmail});

  @override
  State<_InvitePendingSheet> createState() => _InvitePendingSheetState();
}

class _InvitePendingSheetState extends State<_InvitePendingSheet> {
  final _email = TextEditingController();
  String? _errorKey;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    final clean = _email.text.trim();
    final errorKey = clean.isEmpty
        ? K.famErrInvalidEmail
        : InviteFormRules.emailErrorKey(email: clean, myEmail: widget.myEmail);
    if (errorKey != null) {
      setState(() => _errorKey = errorKey);
      return;
    }
    Navigator.of(context).pop(clean);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: Spacing.md),
        AppTextField(
          label: l[K.commonEmail],
          hint: l[K.famInviteEmailPlaceholder],
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          errorText: _errorKey == null ? null : l[_errorKey!],
          autofocus: true,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: Spacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l[K.commonCancel]),
            ),
            const SizedBox(width: Spacing.sm),
            FilledButton(
              onPressed: _submit,
              child: Text(l[K.famSendInvite]),
            ),
          ],
        ),
      ],
    );
  }
}
