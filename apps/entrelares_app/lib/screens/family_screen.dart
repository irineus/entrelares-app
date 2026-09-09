import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../deep_link_urls.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/family_invitation.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_db_contracts/models/subscription.dart';
import '../services/admin_mode.dart';
import '../services/analytics_service.dart';
import '../env.dart';
import '../services/custody_data_source.dart';
import '../services/store_billing.dart';
import '../services/sudo_service.dart';
import '../theme/tokens.dart';
import '../widgets/account_button.dart';
import '../widgets/app_l10n.dart';
import '../widgets/app_snack.dart';
import '../widgets/rich_label.dart';
import '../widgets/sudo_sheet.dart';

/// `/family` — port of `FamilyPage.razor`.
///
/// **The page is a roster, not an editor** (F-16): tapping a member opens their
/// profile, where the name, the role and the admin flag actually change. That
/// split is the web's and it survives here, because the profile page is also
/// where e-mail, password, LGPD export and leaving the family live.
///
/// The F-32/T-39 premium block lives here too (lote 5), and its shape depends
/// on the CHANNEL: the store build must never carry an external checkout link
/// (T-38), so on Android the offer collapses into a neutral note while the web
/// target keeps the Asaas rail.
///
/// The S-11 family-deletion panel DOES live here, and its rule is unusual
/// enough to state: unanimity means every voter has an explicit `agreed` row.
/// A missing answer is not consent — silence never deletes a family — and one
/// refusal ends the request outright.
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

  /// T-38 dropped the TWA shell, so the acquisition channel falls out of the
  /// BUILD: this app IS the store channel and the web target is the web one —
  /// hence the `!kIsWeb` default, the same split `analyticsChannel` makes.
  /// It is a parameter only so widget tests can exercise BOTH rails on the VM;
  /// nothing at runtime ever passes it.
  final bool isStoreChannel;

  /// T-48: the store rail. Null means "no store on this build" — the section
  /// then keeps the T-38 neutral note, which is also what the switch-off state
  /// shows, so a missing service can never become a broken offer.
  final StoreBilling? storeBilling;

  /// Hands a URL to the system browser. Injectable for the same reason: WHERE
  /// the family is sent to pay is a money-critical fact worth asserting, and
  /// the plugin channel does not exist in a widget test.
  final Future<void> Function(String url)? openExternal;

  const FamilyScreen({
    super.key,
    required this.dataSource,
    required this.adminMode,
    required this.sudo,
    this.analytics,
    this.onOpenCustomRoles,
    this.onOpenProfile,
    this.onFamilyDeleted,
    this.isStoreChannel = !kIsWeb,
    this.openExternal,
    this.storeBilling,
  });

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
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

  // F-32/T-39 premium. `_subscription` is bookkeeping only — entitlement
  // always comes from the family row through the mirror, never from here.
  Subscription? _subscription;
  bool _hasPremiumInterest = false;
  bool _premiumBusy = false;
  bool _billingBusy = false;
  bool _cancelConfirming = false;

  /// F-48: one premium-paywall-view per VISIT, however often `_load` reruns.
  bool _paywallViewTracked = false;

  /// The web's `href="#premium-section"` has no equivalent here — a key the
  /// gate CTAs scroll to is the native way to keep the same promise.
  final _premiumSectionKey = GlobalKey();

  // T-48 store rail. `_storeProducts` empty (for any reason: no store, the
  // query failed, the ids are not published yet) means the neutral note.
  bool _storeAvailable = false;
  List<StoreProduct> _storeProducts = const [];
  bool _storePurchasePending = false;
  StreamSubscription<StorePurchase>? _storeSubscription;

  // F-43: payment history — lazy on first expand, cached afterwards.
  bool _historyOpen = false;
  bool _historyLoading = false;
  bool _historyLoaded = false;
  List<BillingHistoryEntry> _history = const [];

  // S-11 family deletion
  PendingFamilyDeletion? _deletion;
  bool _confirmingRequest = false;
  bool _confirmingExecute = false;
  bool _deletionBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
    final store = widget.storeBilling;
    if (store != null) _storeSubscription = store.purchases.listen(_onPurchase);
  }

  @override
  void dispose() {
    _storeSubscription?.cancel();
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

  BillingUi get _billingUi {
    final plan = _planStatus;
    return computeBillingUi(
      billingEnabled: _settings.billingEnabled,
      isPremium: plan.isPremium,
      onTrial: plan.onTrial,
      subscriptionStatus: _subscription?.status,
    );
  }

  /// Play's payments policy forbids steering a Play-distributed app to an
  /// external purchase flow, so the store branch of the offer carries no price
  /// and no checkout link (Play Billing itself arrives in this batch, behind
  /// its own switch).
  bool get _isStoreChannel => widget.isStoreChannel;

  /// The funnel dimension that separates the store cohort from the web one —
  /// derived from the SAME build fact, so a channel-tagged event can never
  /// disagree with the rail the family was actually offered.
  String get _channel => analyticsChannel(isWeb: !widget.isStoreChannel);

  bool get _atFreeCap => atFreeCaregiverCap(
      isPremium: _isPremium,
      seatsTaken: _seatsTaken,
      freeLimit: _settings.freeCaregivers);

  Future<void> _load() async {
    setState(() {
      _loading = true;
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
      // master switch off the section short-circuits to the F-32 waitlist, and
      // asking for a row we would ignore is a round-trip for nothing.
      final subscription = settings.billingEnabled
          ? await widget.dataSource.fetchSubscription()
          : null;
      final plan = describePlan(
        plan: family?.plan,
        trialEndsAtUtc: family?.trialEndsAt,
        nowUtc: DateTime.now().toUtc(),
        compPremiumAtUtc: family?.compPremiumAt,
      );
      // Grandfathered premium never sees the waitlist CTA, so the web does not
      // even ask — same here.
      final interest = plan.isPremium && !plan.onTrial
          ? false
          : await widget.dataSource.hasRegisteredPremiumInterest();

      // T-48: only ask the store when the rail is on AND this build is the
      // store channel. On the web target there is no store to ask.
      if (widget.isStoreChannel && settings.storeBillingEnabled) {
        await _loadStore();
      }

      if (!mounted) return;
      // F-48: first funnel step — the offer became VISIBLE. Guarded so a
      // reload within the same visit (e.g. after an invite) counts once.
      final ui = computeBillingUi(
        billingEnabled: settings.billingEnabled,
        isPremium: plan.isPremium,
        onTrial: plan.onTrial,
        subscriptionStatus: subscription?.status,
      );
      if (ui == BillingUi.offer && !_paywallViewTracked) {
        _paywallViewTracked = true;
        widget.analytics?.trackEvent('premium-paywall-view',
            props: analyticsFunnelProps(channel: _channel));
      }
      setState(() {
        _subscription = subscription;
        _hasPremiumInterest = interest;
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
  Future<void> _shareLink(FamilyInvitation invitation) async {
    final link =
        InviteFormRules.inviteLink(DeepLinkUrls.webOrigin, invitation.token);
    await Share.shareUri(Uri.parse(link));
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
            if (_isAdmin) ...[
              const SizedBox(height: 24),
              _adminModeSection(l),
            ],
            const SizedBox(height: 24),
            _premiumSection(l),
            const SizedBox(height: 24),
            _deletionSection(l),
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
            // Premium section. The CTA never carries a price or an external
            // link — it scrolls, and the section decides what the CHANNEL may
            // offer (T-38).
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l[K.famFreeCapNotice]),
                    TextButton(
                      onPressed: () => _goToPremium('extra-caregiver'),
                      child: Text(l[K.famSeePremium]),
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
                if (!expired) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(l[K.famCopyLink]),
                    onPressed: () => _copyLink(invitation, l),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: Text(l[KApp.commonShare]),
                    onPressed: () => _shareLink(invitation),
                  ),
                ],
                TextButton(
                  onPressed: () => _resendInvite(invitation, l),
                  child: Text(l[K.famResendInvite]),
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
            child: TextButton(
              onPressed: widget.onOpenCustomRoles,
              child: Text(l[K.famCustomRolesLink]),
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
        _confirmingRequest = false;
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

  Widget _deletionSection(Localization l) {
    final deletion = _deletion;
    if (deletion != null) return _deletionPendingPanel(l, deletion);

    // Nothing pending: an admin with company may open one. A lone member
    // deletes the family by LEAVING, which is the profile page's flow.
    if (!FamilyLifecycleRules.canRequestFamilyDeletion(
        isAdmin: _isAdmin, activeMemberCount: _activeMemberCount)) {
      return const SizedBox.shrink();
    }
    return _deletionRequestPanel(l);
  }

  /// U-28 — the family's danger zone, as [AppDangerZone].
  ///
  /// The web frames this in red, with the notices inside the frame and a filled
  /// red button. The port had loose paragraphs with hand-glued `•` bullets (so
  /// a wrapping notice started under its own bullet) and a plain text link at
  /// the bottom — the least weight in the section, for the action that deletes
  /// everything the family has.
  Widget _deletionRequestPanel(Localization l) {
    if (!_confirmingRequest) {
      return AppDangerZone(
        title: l[K.famDelReqTitle],
        intro: l[K.famDelReqIntro],
        notices: [
          for (final consequence in [
            K.famDelReqConsequenceData,
            K.famDelReqConsequenceNotice,
            K.famDelReqConsequenceUnanimity,
            K.famDelReqConsequenceWithdraw,
          ])
            l[consequence],
        ],
        actionLabel: l[K.famDelReqOpen],
        // Two steps on purpose: this press opens a question, the next one
        // answers it. Nothing destructive is one tap away.
        onAction: () => setState(() => _confirmingRequest = true),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l[K.famDelReqTitle]),
        ...[
          Text(l[K.famDelReqConfirmText]),
          const SizedBox(height: 8),
          // U-29: a destructive confirm wears the danger tone, never the brand
          // indigo — the AppDangerZone that opened this question already does.
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: context.tokens.danger.solid,
                foregroundColor: context.tokens.danger.onSolid),
            onPressed: _deletionBusy
                ? null
                : () => _runDeletionAction(
                      l,
                      sudo: true,
                      successKey: K.famToastDeletionRequested,
                      action: () async {
                        await widget.dataSource.requestFamilyDeletion();
                        await widget.dataSource
                            .sendAccountEmail('family_deletion_requested');
                      },
                    ),
            child: Text(l[K.famDelReqConfirm]),
          ),
          TextButton(
            onPressed: () => setState(() => _confirmingRequest = false),
            child: Text(l[K.famDelReqKeep]),
          ),
        ],
      ],
    );
  }

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
            OutlinedButton(
              onPressed: () => setState(() => _confirmingExecute = true),
              child: Text(l[K.famDelExecuteNowOpen]),
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

  // ── F-32/T-39: Premium — plan status, feature preview and the paid rails ──
  // Every paragraph below is ONE catalogue entry rendered with RichLabel,
  // keeping its inline <strong>. This block states when money is charged, how
  // much and what happens to the data — assembling those sentences from
  // fragments is how a translation turns into a false commercial statement,
  // and charging is live in production.

  Future<void> _registerPremiumInterest(Localization l) async {
    if (_premiumBusy) return;
    setState(() => _premiumBusy = true);
    try {
      await widget.dataSource.registerPremiumInterest(feature: 'family');
      widget.analytics?.trackEvent('premium-interest', props: {
        'source': 'family',
        'trial': _planStatus.onTrial,
      });
      if (!mounted) return;
      setState(() {
        _premiumBusy = false;
        _hasPremiumInterest = true;
      });
      showAppSnack(context, l[K.famInterestRegistered]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _premiumBusy = false);
      showAppSnack(
          context, translateSaveError(e.toString(), l[K.errSaveFailed], l),
          type: AppSnackType.error);
    }
  }

  /// The two in-app money actions. Both are refusable by the server with text
  /// written for the payer, so [BillingRefused] wins over any local guess.
  Future<void> _runBillingAction(
    Localization l,
    Future<void> Function() action, {
    required String successKey,
    required String event,
  }) async {
    if (_billingBusy) return;
    setState(() => _billingBusy = true);
    try {
      await action();
      widget.analytics?.trackEvent(event,
          props: analyticsFunnelProps(
              channel: _channel, cycle: _subscription?.cycle ?? '?'));
      if (!mounted) return;
      setState(() {
        _billingBusy = false;
        _cancelConfirming = false;
      });
      showAppSnack(context, l[successKey]);
      // Reload rather than patch state locally: what the family is entitled to
      // after a cancel is the SERVER's answer (paid time is honored there).
      await _load();
    } on BillingRefused catch (e) {
      if (!mounted) return;
      setState(() => _billingBusy = false);
      showAppSnack(context, e.serverMessage ?? l[K.errSaveFailed],
          type: AppSnackType.error);
    } catch (e) {
      if (!mounted) return;
      setState(() => _billingBusy = false);
      showAppSnack(
          context, translateSaveError(e.toString(), l[K.errSaveFailed], l),
          type: AppSnackType.error);
    }
  }

  /// T-39/F-48: leaves the app for the hosted checkout. Recurring and avulso
  /// share everything but the action and the funnel's `mode` — the family sees
  /// two rails, the server sees one function.
  Future<void> _startCheckout(
    Localization l,
    String cycle, {
    required bool avulso,
  }) async {
    if (_billingBusy) return;
    setState(() => _billingBusy = true);
    try {
      final url = avulso
          ? await widget.dataSource.startAvulso(cycle)
          : await widget.dataSource.startCheckout(cycle);
      widget.analytics?.trackEvent('premium-checkout-start',
          props: analyticsFunnelProps(
              channel: _channel,
              cycle: cycle,
              mode: avulso ? 'avulso' : 'recurring'));
      await (widget.openExternal ?? _openExternal)(url);
      if (!mounted) return;
      // The payment happens outside the app and confirms ASYNCHRONOUSLY (the
      // webhook), so there is nothing to await here — the return screen polls.
      setState(() => _billingBusy = false);
    } on BillingRefused catch (e) {
      if (!mounted) return;
      setState(() => _billingBusy = false);
      showAppSnack(context, e.serverMessage ?? l[K.errSaveFailed],
          type: AppSnackType.error);
    } catch (e) {
      if (!mounted) return;
      setState(() => _billingBusy = false);
      showAppSnack(
          context, translateSaveError(e.toString(), l[K.errSaveFailed], l),
          type: AppSnackType.error);
    }
  }

  static Future<void> _openExternal(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  String _cycleLabel(Localization l, String? cycle) =>
      l[cycle == 'annual' ? K.premCycleAnnual : K.premCycleMonthly];

  Widget _premiumBadge(Localization l) {
    final theme = Theme.of(context);
    final plan = _planStatus;
    final trialEnd = _family?.trialEndsAt;

    if (plan.isPremium && plan.onTrial) {
      // U-22: the countdown alone hid the actual end date — show both, from
      // the SAME source as the additive-renewal copy, so they cannot disagree.
      final until = trialEnd == null
          ? ''
          : l.format(K.premBadgeTrialUntil, [l.formatDate(trialEnd.toLocal())]);
      return Text(
        l.format(
            plan.trialDaysLeft == 1 ? K.premBadgeTrialOne : K.premBadgeTrialMany,
            [plan.trialDaysLeft, until]),
        style: theme.textTheme.titleSmall,
      );
    }
    if (_billingUi == BillingUi.premiumForever) {
      // U-22: grandfathered premium has no date BY DESIGN — say so instead of
      // leaving a bare badge that looks like an omission.
      return Text(l[K.premBadgeForever], style: theme.textTheme.titleSmall);
    }
    if (plan.isPremium) {
      return Text(l[K.premBadgeActive], style: theme.textTheme.titleSmall);
    }

    final expired = describeExpiredPremium(
      isPremium: plan.isPremium,
      subscriptionStatus: _subscription?.status,
      currentPeriodEndUtc: _subscription?.currentPeriodEnd,
      trialEndsAtUtc: trialEnd,
      nowUtc: DateTime.now().toUtc(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l[K.premBadgeFree], style: theme.textTheme.titleSmall),
        if (expired != null) ...[
          const SizedBox(height: 4),
          RichLabel.of(
            l,
            expired.wasTrial ? K.premExpiredTrial : K.premExpiredPaid,
            args: [l.formatDate(expired.endedAtUtc.toLocal())],
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Future<void> _loadStore() async {
    final store = widget.storeBilling;
    if (store == null) return;
    try {
      final available = await store.isAvailable();
      final products =
          available ? await store.loadProducts() : const <StoreProduct>[];
      if (!mounted) return;
      setState(() {
        _storeAvailable = available;
        _storeProducts = products;
      });
    } catch (_) {
      // Fail closed to the neutral note: a store that will not answer must
      // not leave a half-drawn offer on a Play-distributed build.
      if (!mounted) return;
      setState(() {
        _storeAvailable = false;
        _storeProducts = const [];
      });
    }
  }

  /// A purchase update arrived. The client NEVER grants premium here: it hands
  /// the token to the server, and only the reload that follows can show the
  /// new plan.
  Future<void> _onPurchase(StorePurchase purchase) async {
    final l = AppL10n.of(context).l;
    if (purchase.status == StorePurchaseStatus.pending) {
      setState(() => _storePurchasePending = true);
      return;
    }
    if (!purchase.isOwned) {
      setState(() => _storePurchasePending = false);
      if (purchase.status == StorePurchaseStatus.failed) {
        showAppSnack(context, purchase.errorMessage ?? l[KApp.storeErrPurchase],
            type: AppSnackType.error);
      }
      return;
    }

    setState(() => _storePurchasePending = true);
    try {
      await widget.dataSource.verifyStorePurchase(
        productId: purchase.productId,
        purchaseToken: purchase.verificationToken ?? '',
      );
      // Acknowledge ONLY after the server accepted it — Play refunds an
      // unacknowledged purchase after three days, and acknowledging one the
      // server refused would strand the family without the entitlement.
      await widget.storeBilling?.complete(purchase);
      widget.analytics?.trackEvent('premium-checkout-outcome',
          props: analyticsFunnelProps(
              channel: _channel,
              cycle: cycleForStoreProduct(purchase.productId),
              mode: 'store',
              outcome: 'confirmed'));
      if (!mounted) return;
      showAppSnack(context, l[KApp.storeToastActive]);
      setState(() => _storePurchasePending = false);
      await _load();
    } on BillingRefused catch (e) {
      if (!mounted) return;
      setState(() => _storePurchasePending = false);
      showAppSnack(context, e.serverMessage ?? l[KApp.storeErrPurchase],
          type: AppSnackType.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _storePurchasePending = false);
      showAppSnack(context, l[KApp.storeErrPurchase],
          type: AppSnackType.error);
    }
  }

  /// A gate CTA was tapped: record the intent signal (T-37, one event family
  /// distinguished by `gate`) and take the admin to the section. Never a price
  /// and never an external link — what may be OFFERED is the section's call,
  /// and it depends on the channel.
  void _goToPremium(String gate) {
    widget.analytics?.trackEvent('premium-gate-click', props: {'gate': gate});
    final target = _premiumSectionKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(target,
          duration: const Duration(milliseconds: 300));
    }
  }

  Widget _premiumSection(Localization l) {
    final theme = Theme.of(context);
    final ui = _billingUi;
    return Column(
      key: _premiumSectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l[K.premTitle]),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _premiumBadge(l),
                const SizedBox(height: 8),
                RichLabel.of(l, K.premIntro, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 4),
                RichLabel.of(
                  l,
                  ui == BillingUi.waitlist
                      ? K.premIntroWaitlist
                      : K.premIntroOffer,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.md),
                // U-28: the benefits as a real list with aligned icons.
                //
                // This block is where a Free family decides to spend money, and
                // it was the least composed thing on the screen: one `Text` per
                // line with a literal `•` glued in front of an emoji, so a
                // wrapping benefit restarted under its own bullet and the icons
                // did not line up with each other. `AppBulletList` gives the
                // hanging indent; the icons are the app's own, not emoji, so
                // the list reads as a feature table rather than as chat.
                AppBulletList(
                  items: const [
                    K.premFeatureCaregivers,
                    K.premFeatureHorizon,
                    K.premFeaturePdf,
                    K.premFeatureAdminMode,
                    K.premFeatureRoles,
                  ].map((k) => l[k]).toList(),
                  leadingIcons: const [
                    Icon(Icons.group_outlined, size: TypeScale.subtitle),
                    Icon(Icons.event_available_outlined,
                        size: TypeScale.subtitle),
                    Icon(Icons.picture_as_pdf_outlined,
                        size: TypeScale.subtitle),
                    Icon(Icons.shield_outlined, size: TypeScale.subtitle),
                    Icon(Icons.sell_outlined, size: TypeScale.subtitle),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                ..._premiumStateBlock(l, ui),
                ..._historyPanel(l),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The block that follows [computeBillingUi] — the same state machine the
  /// web's Premium section runs, one branch per situation.
  List<Widget> _premiumStateBlock(Localization l, BillingUi ui) {
    switch (ui) {
      case BillingUi.premiumForever:
        return [RichLabel.of(l, K.premForeverNote)];
      case BillingUi.manageActive:
        return _activePanel(l);
      case BillingUi.manageOverdue:
        return _overduePanel(l);
      case BillingUi.manageScheduled:
        return _scheduledPanel(l);
      case BillingUi.offer:
        return _offerPanel(l);
      case BillingUi.waitlist:
        return _waitlistPanel(l);
    }
  }

  List<Widget> _activePanel(Localization l) {
    final subscription = _subscription!;
    final renews = subscription.currentPeriodEnd;
    return [
      RichLabel.of(l, K.premActiveStatus, args: [
        _cycleLabel(l, subscription.cycle),
        formatPriceBrl(subscription.priceCents),
      ]),
      if (renews != null)
        RichLabel.of(l, K.premActiveRenews,
            args: [l.formatDate(renews.toLocal())]),
      if (_isAdmin) ..._cancelControls(l, isScheduled: false),
    ];
  }

  List<Widget> _overduePanel(Localization l) {
    // U-22: the one state with a hard deadline — show it. Before
    // overdue_since + billing.grace_days the copy promises access until that
    // date; past it the cron already downgraded (status stays 'overdue' so a
    // late payment still reactivates) and keeping the "still available" text
    // would lie.
    final deadline =
        graceDeadline(_subscription?.overdueSince, _settings.graceDays);
    if (deadline != null && !deadline.isAfter(DateTime.now().toUtc())) {
      return [
        RichLabel.of(l, K.premOverdueGraceEnded,
            args: [l.formatDate(deadline.toLocal())])
      ];
    }
    return [
      deadline == null
          ? RichLabel.of(l, K.premOverdueInGraceNoDate)
          : RichLabel.of(l, K.premOverdueInGrace,
              args: [l.formatDate(deadline.toLocal())]),
    ];
  }

  List<Widget> _scheduledPanel(Localization l) {
    // F-42: reactivated without paying — say plainly that nothing was charged,
    // WHEN the first charge lands and how much, since this is the one state
    // where the family owes money later without having authorised a payment.
    final subscription = _subscription!;
    final dueAt = subscription.currentPeriodEnd;
    final methodKey = billingTypeKey(subscription.billingType);
    final cycle = _cycleLabel(l, subscription.cycle);
    final price = formatPriceBrl(subscription.priceCents);
    return [
      RichLabel.of(l, K.premScheduledStatus),
      if (dueAt != null)
        RichLabel.of(
          l,
          methodKey == null
              ? K.premScheduledDetail
              : K.premScheduledDetailMethod,
          args: [
            l.formatDate(dueAt.toLocal()),
            price,
            cycle,
            if (methodKey != null) l[methodKey],
          ],
        ),
      if (_isAdmin) ..._cancelControls(l, isScheduled: true),
    ];
  }

  List<Widget> _cancelControls(Localization l, {required bool isScheduled}) {
    if (!_cancelConfirming) {
      return [
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => setState(() => _cancelConfirming = true),
          child: Text(l[
              isScheduled ? K.premScheduledCancelButton : K.premCancelButton]),
        ),
      ];
    }
    // Two whole sentences rather than one with an optional clause: the
    // "until X" version is what tells the family they keep what they paid for.
    final paidEnd = _subscription?.currentPeriodEnd;
    return [
      const SizedBox(height: 8),
      if (isScheduled)
        RichLabel.of(l, K.premScheduledCancelWarning)
      else if (paidEnd != null)
        RichLabel.of(l, K.premCancelWarningUntil,
            args: [l.formatDate(paidEnd.toLocal())])
      else
        RichLabel.of(l, K.premCancelWarning),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: _billingBusy
            ? null
            : () => _runBillingAction(
                l,
                widget.dataSource.cancelSubscription,
                successKey: K.famSubscriptionCancelled,
                event: 'premium-cancel',
              ),
        child: Text(l[K.premCancelConfirm]),
      ),
      TextButton(
        onPressed: _billingBusy
            ? null
            : () => setState(() => _cancelConfirming = false),
        child: Text(
            l[isScheduled ? K.premScheduledCancelKeep : K.premCancelKeep]),
      ),
    ];
  }

  List<Widget> _offerPanel(Localization l) {
    final subscription = _subscription;
    final now = DateTime.now().toUtc();
    final stillPaid = paidUntil(
      subscriptionStatus: subscription?.status,
      currentPeriodEndUtc: subscription?.currentPeriodEnd,
      nowUtc: now,
    );
    final trialEnd = _family?.trialEndsAt;

    if (_isStoreChannel) {
      // The informational status lines are the same whichever way the store
      // branch goes — they say what the family already has, never what is for
      // sale.
      final status = [
        if (stillPaid != null)
          RichLabel.of(
            l,
            subscription?.singleCharge == true
                ? K.premStorePaidUntilAvulso
                : K.premStorePaidUntilPeriod,
            args: [l.formatDate(stillPaid.toLocal())],
          )
        else if (_planStatus.onTrial && trialEnd != null)
          RichLabel.of(l, K.premStoreTrialUntil,
              args: [l.formatDate(trialEnd.toLocal())]),
        const SizedBox(height: 4),
      ];
      return [...status, ..._storeBranch(l)];
    }

    return [
      if (stillPaid != null) ...[
        // T-39 (QA): a canceled-but-paid subscription keeps its Premium until
        // the period end — say so, and that re-subscribing ADDS to that date
        // (the webhook extends from the later of period-end/payment), so
        // nobody waits for the lapse.
        RichLabel.of(
          l,
          subscription?.singleCharge == true
              ? K.premPaidUntilAvulso
              : K.premPaidUntilPeriod,
          args: [l.formatDate(stillPaid.toLocal())],
        ),
        if (expiringDaysLeft(stillPaid, now) case final daysLeft?)
          RichLabel.of(
              l,
              daysLeft == 1 ? K.premExpiringSoonOne : K.premExpiringSoonMany,
              args: [daysLeft]),
      ] else if (_planStatus.onTrial && trialEnd != null)
        // F-46: a family paying DURING its trial starts the paid cycle at the
        // trial end — say it before any checkout button.
        RichLabel.of(l, K.premTrialAdditive,
            args: [l.formatDate(trialEnd.toLocal())]),
      if (!_isAdmin)
        RichLabel.of(l, K.premAdminOnly)
      else ...[
        if (canReactivate(
          subscriptionStatus: subscription?.status,
          currentPeriodEndUtc: subscription?.currentPeriodEnd,
          billingType: subscription?.billingType,
          externalCustomerId: subscription?.externalCustomerId,
          nowUtc: now,
          singleCharge: subscription?.singleCharge ?? false,
        ))
          ..._reactivateControls(l, subscription!),
        ..._checkoutControls(l),
      ],
    ];
  }

  /// T-48: what the STORE channel may offer. With the rail off — or with a
  /// store that cannot answer — this is the T-38 neutral note, which is what
  /// Play always accepts and what the app shipped with until now.
  List<Widget> _storeBranch(Localization l) {
    final state = computeStoreOffer(
      storeBillingEnabled: _settings.storeBillingEnabled,
      storeAvailable: _storeAvailable,
      hasProducts: _storeProducts.isNotEmpty,
      purchasePending: _storePurchasePending,
      premiumThroughStore: isStoreGateway(_subscription?.gateway),
    );
    return switch (state) {
      StoreOffer.neutralNote => [RichLabel.of(l, K.premStoreNote)],
      StoreOffer.pendingVerification => [Text(l[KApp.storePending])],
      StoreOffer.managed => [
          RichLabel.of(l, K.premStoreNote),
          _manageOnPlay(l),
        ],
      StoreOffer.offer => _storeOffer(l),
    };
  }

  List<Widget> _storeOffer(Localization l) => [
        if (!_isAdmin)
          RichLabel.of(l, K.premAdminOnly)
        else ...[
          for (final product in _storeProducts)
            FilledButton(
              onPressed: _billingBusy ? null : () => _buyFromStore(l, product),
              child: Text(l.format(
                  product.cycle == 'annual'
                      ? K.premSubscribeAnnual
                      : K.premSubscribeMonthly,
                  // The price is PLAY's, formatted by the store for this
                  // buyer's country — never a number from app_settings, which
                  // rules the web rail only.
                  [product.price])),
            ),
          TextButton(
            onPressed: _billingBusy ? null : () => _restoreFromStore(l),
            child: Text(l[KApp.storeRestore]),
          ),
        ],
      ];

  Widget _manageOnPlay(Localization l) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => (widget.openExternal ?? _openExternal)(
            playManageSubscriptionUrl(
              packageName: Env.current.androidPackage,
              productId: storeProductForCycle(_subscription?.cycle),
            ),
          ),
          child: Text(l[KApp.storeManage]),
        ),
      );

  Future<void> _buyFromStore(Localization l, StoreProduct product) async {
    final store = widget.storeBilling;
    if (store == null) return;
    setState(() => _billingBusy = true);
    try {
      widget.analytics?.trackEvent('premium-checkout-start',
          props: analyticsFunnelProps(
              channel: _channel, cycle: product.cycle, mode: 'store'));
      await store.buy(product);
    } catch (_) {
      if (!mounted) return;
      showAppSnack(context, l[KApp.storeErrPurchase],
          type: AppSnackType.error);
    } finally {
      if (mounted) setState(() => _billingBusy = false);
    }
  }

  Future<void> _restoreFromStore(Localization l) async {
    final store = widget.storeBilling;
    if (store == null) return;
    try {
      // The answer arrives on the purchase stream, like a new purchase — a
      // restored one is verified by the server exactly the same way.
      await store.restore();
    } catch (_) {
      if (!mounted) return;
      showAppSnack(context, l[KApp.storeUnavailable],
          type: AppSnackType.error);
    }
  }

  List<Widget> _checkoutControls(Localization l) {
    final monthly = formatPriceBrl(_settings.priceMonthlyCents);
    final annual = formatPriceBrl(_settings.priceAnnualCents);
    return [
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _billingBusy
            ? null
            : () => _startCheckout(l, 'monthly', avulso: false),
        child: Text(l.format(K.premSubscribeMonthly, [monthly])),
      ),
      // "2 meses grátis" is a factual claim and holds by construction: the
      // annual price is exactly ten times the monthly one, both from
      // app_settings.
      FilledButton(
        onPressed: _billingBusy
            ? null
            : () => _startCheckout(l, 'annual', avulso: false),
        child: Text(l.format(K.premSubscribeAnnual, [annual])),
      ),
      const SizedBox(height: 8),
      // F-48: Pix avulso — the no-recurrence rail. One single charge for one
      // period: no card on file, no auto-renew, renewing later is an explicit
      // new payment (additive).
      RichLabel.of(l, K.premAvulsoLead),
      OutlinedButton(
        onPressed:
            _billingBusy ? null : () => _startCheckout(l, 'monthly', avulso: true),
        child: Text(l.format(K.premAvulsoMonthly, [monthly])),
      ),
      OutlinedButton(
        onPressed:
            _billingBusy ? null : () => _startCheckout(l, 'annual', avulso: true),
        child: Text(l.format(K.premAvulsoAnnual, [annual])),
      ),
      const SizedBox(height: 8),
      // F-48: trust signals on the payment surface — Pix first (no card data
      // leaves your bank app), then the 7-day guarantee, a visible mirror of
      // Terms §10 / CDC art. 49. Same promise, same channel — NOT a new
      // commitment, so no PolicyVersions bump.
      RichLabel.of(l, K.premPaymentHint,
          style: Theme.of(context).textTheme.bodySmall),
      RichLabel.of(l, K.premGuarantee,
          style: Theme.of(context).textTheme.bodySmall),
    ];
  }

  List<Widget> _reactivateControls(Localization l, Subscription subscription) {
    // F-42: the way back that costs nothing today, offered ABOVE the checkout
    // buttons because it is the cheaper choice for the family. Card families
    // never see it — resuming an auto-debit needs a token we never hold.
    final methodKey = billingTypeKey(subscription.billingType);
    final cycle = _cycleLabel(l, subscription.cycle);
    final price = formatPriceBrl(subscription.cycle == 'annual'
        ? _settings.priceAnnualCents
        : _settings.priceMonthlyCents);
    final resumeOn = subscription.currentPeriodEnd == null
        ? null
        : l.formatDate(subscription.currentPeriodEnd!.toLocal());

    // Four whole sentences, picked by which facts exist — the method and the
    // date are each optional and this states WHEN money leaves the account.
    final (hintKey, hintArgs) = switch ((methodKey, resumeOn)) {
      (null, null) => (K.premReactivateHint, [price, cycle]),
      (null, final on) => (K.premReactivateHintDate, [price, cycle, on]),
      (final key, null) => (K.premReactivateHintMethod, [price, cycle, l[key!]]),
      (final key, final on) => (
          K.premReactivateHintMethodDate,
          [price, cycle, l[key!], on]
        ),
    };

    return [
      const SizedBox(height: 8),
      FilledButton(
        onPressed: _billingBusy
            ? null
            : () => _runBillingAction(
                l,
                widget.dataSource.reactivateSubscription,
                successKey: K.famSubscriptionReactivated,
                event: 'premium-reactivate',
              ),
        child: Text(l[K.premReactivateButton]),
      ),
      RichLabel.of(l, hintKey,
          args: hintArgs, style: Theme.of(context).textTheme.bodySmall),
    ];
  }

  // ── F-43: payment history (admins only; the sanitized ledger comes from an
  // RPC the DATABASE guards, and it is loaded only when the panel is opened).

  Future<void> _toggleHistory(Localization l) async {
    final opening = !_historyOpen;
    setState(() => _historyOpen = opening);
    if (!opening || _historyLoaded) return;

    setState(() => _historyLoading = true);
    try {
      final entries = await widget.dataSource.fetchBillingHistory();
      if (!mounted) return;
      setState(() {
        _history = entries;
        _historyLoaded = true;
        _historyLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _historyLoading = false;
        _historyOpen = false;
      });
      showAppSnack(context, l[K.famBillingHistoryLoadFailed],
          type: AppSnackType.error);
    }
  }

  List<Widget> _historyPanel(Localization l) {
    // No subscription row means no ledger to show — and with billing off the
    // whole surface is the waitlist.
    if (!_settings.billingEnabled || !_isAdmin || _subscription == null) {
      return const [];
    }
    return [
      const SizedBox(height: 12),
      TextButton(
        onPressed: () => _toggleHistory(l),
        child: Text('${_historyOpen ? '▾' : '▸'} ${l[K.premHistoryToggle]}'),
      ),
      if (_historyOpen)
        if (_historyLoading)
          AppSkeletonCards(
              count: 2, height: 40, semanticsLabel: l[K.premHistoryLoading])
        else if (_history.isEmpty)
          Text(l[K.premHistoryEmpty])
        else
          for (final entry in _history) _historyRow(l, entry),
    ];
  }

  Widget _historyRow(Localization l, BillingHistoryEntry entry) {
    final theme = Theme.of(context);
    final methodKey = billingTypeKey(entry.billingType);
    final cents = entry.amountCents;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${l.formatDate(entry.occurredAt.toLocal())} · '
              '${l[historyCategoryKey(entry.category)]}'
              '${methodKey == null ? '' : ' · ${l[methodKey]}'}',
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (cents != null)
            Text(formatPriceBrl(cents), style: theme.textTheme.bodySmall),
          if (entry.invoiceUrl case final url?)
            TextButton(
              onPressed: () => (widget.openExternal ?? _openExternal)(url),
              child: Text(l[K.premHistoryReceipt]),
            ),
        ],
      ),
    );
  }

  List<Widget> _waitlistPanel(Localization l) {
    if (_hasPremiumInterest) return [Text(l[K.premInterestDone])];
    return [
      FilledButton(
        onPressed:
            _premiumBusy ? null : () => _registerPremiumInterest(l),
        child: Text(
            l[_planStatus.onTrial ? K.premInterestKeepTrial : K.premInterestWant]),
      ),
      const SizedBox(height: 4),
      Text(l[K.premInterestHint],
          style: Theme.of(context).textTheme.bodySmall),
    ];
  }

  Widget _adminModeSection(Localization l) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.adminMode,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(l[K.famAdminSection]),
          AppCard(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          Text(
              widget.adminMode.isActive
                  ? l[K.famAdminActiveNote]
                  : l[K.famAdminInactiveNote],
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          // F-40 is tier-aware, and saying so here is what stops a free-plan
          // admin from discovering the limit only when the trigger refuses.
          Text(
              _isPremium
                  ? l.format(K.famAdminTierPremium,
                      [_settings.overridePremiumMonths])
                  : l.format(K.famAdminTierFree, [
                      _settings.overrideFreeDays,
                      _settings.overridePremiumMonths
                    ]),
              style: theme.textTheme.bodySmall),
          if (!_isPremium)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _goToPremium('admin-mode'),
                child: Text(l[K.famActivatePremiumLink]),
              ),
            ),
          const SizedBox(height: 12),
          // U-28: entering admin mode is not the same KIND of action as
          // sending an invite, and the port painted both in the same brand
          // indigo. The web framed this one in amber, and it should: the mode
          // unlocks editing days the app otherwise protects. Same token
          // vocabulary, different tone — warning, not accent.
          widget.adminMode.isActive
              ? FilledButton.icon(
                  onPressed: widget.adminMode.deactivate,
                  icon: const Icon(Icons.shield),
                  label: Text(l[K.famAdminDeactivate]),
                  style: FilledButton.styleFrom(
                      backgroundColor: context.tokens.warning.solid,
                      foregroundColor: context.tokens.warning.onSolid),
                )
              : OutlinedButton.icon(
                  onPressed: widget.adminMode.toggle,
                  icon: const Icon(Icons.shield_outlined),
                  label: Text(l[K.famAdminActivate]),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: context.tokens.warning.onContainer,
                      backgroundColor: context.tokens.warning.container,
                      side: BorderSide(color: context.tokens.warning.border)),
                ),
            ],
          )),
        ],
      ),
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
