import 'dart:convert';

import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/subscription.dart';
import '../env.dart';
import '../services/analytics_service.dart';
import '../services/checkout_note.dart';
import '../services/custody_data_source.dart';
import '../services/store_billing.dart';
import '../services/store_purchases.dart';
import '../theme/tokens.dart';
import '../widgets/app_l10n.dart';
import '../widgets/app_snack.dart';
import '../widgets/rich_label.dart';
import '../widgets/ui/ui.dart';

/// `/family/plan` — the F-32/T-39/T-48 Premium block, on its own page (U-35).
///
/// It used to be a section of the Família scroll, under the roster and above
/// the danger zone: a parent opening the tab to see who is in the family
/// scrolled past a commercial offer every time. The Família page keeps ONE
/// row — *Plano e pagamento*, with the plan's state as its subtitle — and this
/// page is what the row opens. Nothing about the offer changed in the move:
/// the six-state machine (`computeBillingUi`), both rails, the U-46 offer, the
/// F-42 way back, the F-43 ledger and the waitlist are the same code, in a
/// file of their own.
///
/// The move changes ONE funnel fact, on purpose and recorded on the card:
/// `premium-paywall-view` fires when THIS page loads with the offer on it, no
/// longer on every visit to Família. The denominator of the F-48 funnel is a
/// visit to the plan page from now on.
///
/// The shape of the block depends on the CHANNEL: the store build must never
/// carry an external checkout link (T-38), so on Android the offer is Play's
/// rail or the neutral note, while the web target keeps the Asaas rail.
class FamilyPlanScreen extends StatefulWidget {
  final CustodyDataSource dataSource;

  /// T-37 — optional: the funnel signal never gates the page.
  final AnalyticsService? analytics;

  /// T-38 dropped the TWA shell, so the acquisition channel falls out of the
  /// BUILD: this app IS the store channel and the web target is the web one —
  /// hence the `!kIsWeb` default, the same split `analyticsChannel` makes.
  /// It is a parameter only so widget tests can exercise BOTH rails on the VM;
  /// nothing at runtime ever passes it.
  final bool isStoreChannel;

  /// T-48: the store rail. Null means "no store on this build" — the page
  /// then keeps the T-38 neutral note, which is also what the switch-off state
  /// shows, so a missing service can never become a broken offer.
  final StoreBilling? storeBilling;

  /// F-86: the app-level purchase listener. Null (tests, or a build without
  /// one) makes the page run its own for as long as it is open.
  final StorePurchaseCoordinator? purchases;

  /// Hands a URL to the system browser. Injectable for the same reason: WHERE
  /// the family is sent to pay is a money-critical fact worth asserting, and
  /// the plugin channel does not exist in a widget test.
  final Future<void> Function(String url)? openExternal;

  const FamilyPlanScreen({
    super.key,
    required this.dataSource,
    this.analytics,
    this.isStoreChannel = !kIsWeb,
    this.openExternal,
    this.storeBilling,
    this.purchases,
  });

  @override
  State<FamilyPlanScreen> createState() => _FamilyPlanScreenState();
}

class _FamilyPlanScreenState extends State<FamilyPlanScreen> {
  bool _loading = true;
  String? _loadErrorKey;

  Family? _family;
  Member? _me;
  PublicSettings _settings = PublicSettings.unloaded;

  // F-32/T-39 premium. `_subscription` is bookkeeping only — entitlement
  // always comes from the family row through the mirror, never from here.
  Subscription? _subscription;
  bool _hasPremiumInterest = false;
  bool _premiumBusy = false;
  bool _billingBusy = false;
  bool _cancelConfirming = false;

  /// F-48: one premium-paywall-view per VISIT, however often `_load` reruns.
  bool _paywallViewTracked = false;

  // T-48 store rail. `_storeProducts` empty (for any reason: no store, the
  // query failed, the ids are not published yet) means the neutral note.
  bool _storeAvailable = false;
  List<StoreProduct> _storeProducts = const [];

  // U-46: the ONE question the offer asks first. Annual opens it — the better
  // deal, with its badge and per-month equivalent in view — and a tap flips
  // it. The choice is screen state only: nothing is charged until the CTA.
  String _offerCycle = 'annual';
  bool _storePurchasePending = false;
  StreamSubscription<StorePurchaseOutcome>? _outcomeSubscription;

  /// F-86: the page's own coordinator, only when the app handed none.
  StorePurchaseCoordinator? _ownPurchases;

  // F-43: payment history — lazy on first expand, cached afterwards.
  bool _historyOpen = false;
  bool _historyLoading = false;
  bool _historyLoaded = false;
  List<BillingHistoryEntry> _history = const [];

  @override
  void initState() {
    super.initState();
    _load();
    final store = widget.storeBilling;
    var purchases = widget.purchases;
    if (purchases == null && store != null) {
      purchases = _ownPurchases = StorePurchaseCoordinator(
          store: store, dataSource: widget.dataSource, analytics: widget.analytics);
      unawaited(purchases.activate(restore: false));
    }
    if (purchases != null) {
      _storePurchasePending = purchases.pending.value;
      _outcomeSubscription = purchases.outcomes.listen(_onPurchaseOutcome);
    }
  }

  @override
  void dispose() {
    _outcomeSubscription?.cancel();
    _ownPurchases?.dispose();
    super.dispose();
  }

  bool get _isAdmin => _me?.isAdmin == true;

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

  /// F-79: whether THIS reader is looking at something they can buy — a price
  /// card and "Assinar" are built. The same facts [_offerPanel] branches on,
  /// read in one place so the funnel's `buyable` cannot disagree with the
  /// screen.
  bool get _offerBuyable {
    if (_billingUi != BillingUi.offer || !_isAdmin) return false;
    if (!_isStoreChannel) return true;
    return _storeOfferState == StoreOffer.offer && _storeCycles.isNotEmpty;
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadErrorKey = null;
    });
    try {
      final results = await Future.wait([
        widget.dataSource.fetchOwnFamily(),
        widget.dataSource.fetchOwnProfile(),
        widget.dataSource.fetchPublicSettings(),
      ]);
      final family = results[0] as Family?;
      final settings = PublicSettings(results[2] as Map<String, String>);

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
      setState(() {
        _subscription = subscription;
        _hasPremiumInterest = interest;
        _family = family;
        _me = results[1] as Member?;
        _settings = settings;
        _loading = false;
      });
      // F-48: first funnel step — the offer became VISIBLE. Guarded so a
      // reload within the same visit (e.g. after a cancel) counts once. U-35:
      // "visible" is THIS page now, not the Família tab.
      //
      // F-79 (02/10/2026): same name, same moment — the series goes on — but
      // the view now says WHO saw it. `admin` is whether this reader may pay
      // at all (a member sees only "ask an administrator"), and `buyable` is
      // whether a price card and "Assinar" were actually built for them (the
      // store rail switched off, or a store that did not answer, leaves only
      // a note). Before this date every view counted as a buyer.
      if (_billingUi == BillingUi.offer && !_paywallViewTracked) {
        _paywallViewTracked = true;
        widget.analytics?.trackEvent(AnalyticsEvents.premiumPaywallView,
            props: {
              ...analyticsFunnelProps(channel: _channel),
              'admin': _isAdmin,
              'buyable': _offerBuyable,
            });
      }
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

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final appBar = AppBar(title: Text(l[KApp.famPlanRow]));
    if (_loading) {
      return Scaffold(
        appBar: appBar,
        body: AppSkeletonCards(
            count: 2, height: 160, semanticsLabel: l[K.famLoading]),
      );
    }
    if (_loadErrorKey != null) {
      return Scaffold(
        appBar: appBar,
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
      appBar: appBar,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [_premiumSection(l)],
        ),
      ),
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
      widget.analytics?.trackEvent(AnalyticsEvents.premiumInterest, props: {
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
      widget.analytics?.trackEvent(AnalyticsEvents.premiumCheckoutStart,
          props: analyticsFunnelProps(
              channel: _channel,
              cycle: cycle,
              mode: avulso ? 'avulso' : 'recurring'));
      // F-86: what the family has right now — the return page counts a
      // payment only as a CHANGE against this.
      writeCheckoutNote(jsonEncode(CheckoutBaseline(
        premium: _planStatus.isPremium,
        periodEndUtc: _subscription?.currentPeriodEnd?.toUtc(),
        takenAtUtc: DateTime.now().toUtc(),
      ).toJson()));
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
      return _premiumMark(Text(
        l.format(
            plan.trialDaysLeft == 1 ? K.premBadgeTrialOne : K.premBadgeTrialMany,
            [plan.trialDaysLeft, until]),
        style: theme.textTheme.titleSmall,
      ));
    }
    if (_billingUi == BillingUi.premiumForever) {
      // U-22: grandfathered premium has no date BY DESIGN — say so instead of
      // leaving a bare badge that looks like an omission.
      return _premiumMark(
          Text(l[K.premBadgeForever], style: theme.textTheme.titleSmall));
    }
    if (plan.isPremium) {
      return _premiumMark(
          Text(l[K.premBadgeActive], style: theme.textTheme.titleSmall));
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

  /// F-86: what the app-level listener did with a purchase update. The
  /// verification and the acknowledgement already happened there — wherever
  /// the reader was; this page only says so and reloads.
  void _onPurchaseOutcome(StorePurchaseOutcome outcome) {
    if (!mounted) return;
    final l = AppL10n.of(context).l;
    switch (outcome.kind) {
      case StorePurchaseOutcomeKind.pending:
        setState(() => _storePurchasePending = true);
      case StorePurchaseOutcomeKind.canceled:
        setState(() => _storePurchasePending = false);
      case StorePurchaseOutcomeKind.failed:
        setState(() => _storePurchasePending = false);
        showAppSnack(context, outcome.message ?? l[KApp.storeErrPurchase],
            type: AppSnackType.error);
      case StorePurchaseOutcomeKind.refused:
        setState(() => _storePurchasePending = false);
        showAppSnack(context, outcome.message ?? l[KApp.storeErrPurchase],
            type: AppSnackType.error);
      case StorePurchaseOutcomeKind.verified:
        setState(() => _storePurchasePending = false);
        showAppSnack(context, l[KApp.storeToastActive]);
        unawaited(_load());
    }
  }

  /// U-31: a status line's mark is a vector icon in front of the sentence —
  /// it used to be an emoji INSIDE the catalog string.
  Widget _marked(IconData icon, Color color, Widget label) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(child: label),
        ],
      );

  /// The Premium mark beside a plan badge — the sparkle the catalog used to
  /// carry as "✨", drawn as the app's own icon.
  Widget _premiumMark(Widget label) =>
      _marked(Icons.auto_awesome, context.tokens.accent.solid, label);

  Widget _premiumSection(Localization l) {
    final theme = Theme.of(context);
    final ui = _billingUi;
    // F-79: with the offer on, the decision comes first. On a 360 dp phone
    // the full benefit list (five to ten lines) used to push "Assinar" about
    // two screens down; now the reader meets one line of value, the price and
    // the button, and the list follows as the reasons. The free-essentials
    // sentence and the secondary payment facts (Pix avulso, how to pay, the
    // guarantee) come after it — every sentence the page said before, none
    // dropped. Every other state keeps the old order: there, the list is
    // what the family already has, or what the waitlist promises.
    final offer = ui == BillingUi.offer ? _offerPanel(l) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The block keeps its own heading under the page's app bar: the page
        // is "Plano e pagamento", the thing on sale is still "Premium".
        AppSectionHeader(title: l[K.premTitle], topSpacing: 0),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _premiumBadge(l),
                const SizedBox(height: 8),
                if (offer == null) ...[
                  RichLabel.of(l, K.premIntro,
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  RichLabel.of(
                    l,
                    ui == BillingUi.waitlist
                        ? K.premIntroWaitlist
                        : K.premIntroOffer,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: Spacing.md),
                  _benefitList(l),
                  const SizedBox(height: Spacing.md),
                  ..._premiumStateBlock(l, ui),
                ] else ...[
                  RichLabel.of(l, K.premIntroOffer,
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  ...offer.primary,
                  const SizedBox(height: Spacing.md),
                  _benefitList(l),
                  const SizedBox(height: Spacing.sm),
                  RichLabel.of(l, K.premIntro,
                      style: theme.textTheme.bodyMedium),
                  ...offer.secondary,
                ],
                ..._historyPanel(l),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // U-28: the benefits as a real list with aligned icons.
  //
  // This block is where a Free family decides to spend money, and it was the
  // least composed thing on the screen: one `Text` per line with a literal `•`
  // glued in front of an emoji, so a wrapping benefit restarted under its own
  // bullet and the icons did not line up with each other. `AppBulletList`
  // gives the hanging indent; the icons are the app's own, not emoji, so the
  // list reads as a feature table rather than as chat.
  // U-57: the two numbers are the live `free_caregivers` and
  // `calendar_months_free` — what the server enforces.
  Widget _benefitList(Localization l) {
    final phase6 = _phase6Benefits(l);
    return AppBulletList(
      key: const ValueKey('premium-benefits'),
      items: [
        l.format(K.premFeatureCaregivers, [_settings.freeCaregivers]),
        l.format(K.premFeatureHorizon, [_settings.calendarMonthsFree]),
        l[K.premFeaturePdf],
        l[K.premFeatureAdminMode],
        l[K.premFeatureRoles],
        // S-22: each phase-6 module lists itself while its flag is on AND it
        // is Premium-only (a gate the operator lifted is not a benefit any
        // more). The viewer cap is the live `max_viewers` (U-57).
        for (final b in phase6) b.text,
      ],
      leadingIcons: [
        const Icon(Icons.group_outlined, size: TypeScale.subtitle),
        const Icon(Icons.event_available_outlined, size: TypeScale.subtitle),
        const Icon(Icons.picture_as_pdf_outlined, size: TypeScale.subtitle),
        const Icon(Icons.shield_outlined, size: TypeScale.subtitle),
        const Icon(Icons.sell_outlined, size: TypeScale.subtitle),
        for (final b in phase6) Icon(b.icon, size: TypeScale.subtitle),
      ],
    );
  }

  /// S-22 — the phase-6 Premium benefits, each behind its module's flag and
  /// its own `*.premium_only` gate (viewers: the Premium cap is the benefit).
  List<({String text, IconData icon})> _phase6Benefits(Localization l) => [
        if (_settings.childAgendaEnabled && _settings.agendaPremiumOnly)
          (text: l[KApp.agendaPremiumBenefit], icon: Icons.event_note_outlined),
        if (_settings.reportAttestationEnabled &&
            _settings.reportAttestationPremiumOnly)
          (text: l[KApp.attestPremiumBenefit], icon: Icons.qr_code_2_outlined),
        if (_settings.expensesEnabled && _settings.expensesPremiumOnly)
          (
            text: l[KApp.expensePremiumBenefit],
            icon: Icons.receipt_long_outlined
          ),
        if (_settings.chatEnabled && _settings.chatPremiumOnly)
          (text: l[KApp.chatPremiumBenefit], icon: Icons.forum_outlined),
        if (_settings.viewersEnabled &&
            _settings.maxViewers > _settings.freeViewers)
          (
            text: l.format(KApp.viewerPremiumBenefit, [_settings.maxViewers]),
            icon: Icons.visibility_outlined
          ),
      ];

  /// The block that follows [computeBillingUi] — the same state machine the
  /// web's Premium section runs, one branch per situation.
  List<Widget> _premiumStateBlock(Localization l, BillingUi ui) {
    switch (ui) {
      case BillingUi.premiumForever:
        return [
          _marked(Icons.auto_awesome, context.tokens.accent.solid,
              RichLabel.of(l, K.premForeverNote))
        ];
      case BillingUi.manageActive:
        return _activePanel(l);
      case BillingUi.manageOverdue:
        return _overduePanel(l);
      case BillingUi.manageScheduled:
        return _scheduledPanel(l);
      case BillingUi.offer:
        // [_premiumSection] lays the offer out itself (F-79); this branch
        // only keeps the switch whole.
        final offer = _offerPanel(l);
        return [...offer.primary, ...offer.secondary];
      case BillingUi.waitlist:
        return _waitlistPanel(l);
    }
  }

  List<Widget> _activePanel(Localization l) {
    final subscription = _subscription!;
    final renews = subscription.currentPeriodEnd;
    return [
      _marked(
          Icons.check_circle_outline,
          context.tokens.success.solid,
          RichLabel.of(l, K.premActiveStatus, args: [
            _cycleLabel(l, subscription.cycle),
            formatPriceBrl(subscription.priceCents),
          ])),
      if (renews != null)
        RichLabel.of(l, K.premActiveRenews,
            args: [l.formatDate(renews.toLocal())]),
      if (_isAdmin)
        if (_isPlaySubscription)
          ..._playManagedControls(l)
        else
          ..._cancelControls(l, isScheduled: false),
    ];
  }

  /// F-84: whether the family's subscription row was written by the STORE
  /// rail. Every managed panel branches on it: a Play subscription is Google's
  /// to cancel, so our cancel and our Asaas dunning copy never reach it —
  /// cancelling our row alone left Google charging while the snack said
  /// "Assinatura cancelada".
  bool get _isPlaySubscription => isStoreGateway(_subscription?.gateway);

  /// F-84: what an admin sees instead of our cancel controls when Play owns
  /// the subscription — on BOTH channels, since the web reader of a family
  /// that bought on Android was offered the same false cancel.
  List<Widget> _playManagedControls(Localization l) => [
        const SizedBox(height: 8),
        RichLabel.of(l, K.premPlayManaged),
        _manageOnPlay(l),
      ];

  List<Widget> _overduePanel(Localization l) {
    // U-22: the one state with a hard deadline — show it. Before
    // overdue_since + billing.grace_days the copy promises access until that
    // date; past it the cron already downgraded (status stays 'overdue' so a
    // late payment still reactivates) and keeping the "still available" text
    // would lie.
    final deadline =
        graceDeadline(_subscription?.overdueSince, _settings.graceDays);
    // F-84: the Asaas copy sends the reader to "o e-mail de cobrança
    // (remetente Asaas)", which a Play subscriber never receives — Play
    // retries the charge itself and the fix is the payment method there.
    final play = _isPlaySubscription;
    final ended = deadline != null && !deadline.isAfter(DateTime.now().toUtc());
    final status = ended
        ? _marked(
            Icons.warning_amber_rounded,
            context.tokens.danger.solid,
            RichLabel.of(
                l, play ? K.premPlayOverdueGraceEnded : K.premOverdueGraceEnded,
                args: [l.formatDate(deadline.toLocal())]))
        : _marked(
            Icons.warning_amber_rounded,
            context.tokens.warning.solid,
            deadline == null
                ? RichLabel.of(l,
                    play ? K.premPlayOverdueInGraceNoDate : K.premOverdueInGraceNoDate)
                : RichLabel.of(
                    l, play ? K.premPlayOverdueInGrace : K.premOverdueInGrace,
                    args: [l.formatDate(deadline.toLocal())]));
    return [
      status,
      if (_isAdmin && play)
        _manageOnPlay(l)
      // F-84: the open invoice, one tap away. Web only: on the store channel
      // a link to pay outside Play is exactly what Play's payments policy
      // forbids inside the app, so Android keeps the e-mail guidance.
      else if (_isAdmin && !_isStoreChannel) ...[
        const SizedBox(height: 8),
        FilledButton(
          key: const ValueKey('premium-pay-overdue'),
          onPressed: _billingBusy ? null : () => _payOverdue(l),
          child: Text(l[K.premOverduePay]),
        ),
      ],
    ];
  }

  /// F-84: opens the invoice still open on the gateway — the server reads it
  /// from the ledger, or asks Asaas when the ledger has none. Nothing is paid
  /// here; the payment confirms through the webhook like any other.
  Future<void> _payOverdue(Localization l) async {
    if (_billingBusy) return;
    setState(() => _billingBusy = true);
    try {
      final url = await widget.dataSource.overdueInvoiceUrl();
      await (widget.openExternal ?? _openExternal)(url);
      if (!mounted) return;
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
      _marked(Icons.event_repeat, context.tokens.info.solid,
          RichLabel.of(l, K.premScheduledStatus)),
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
      if (_isAdmin)
        if (_isPlaySubscription)
          ..._playManagedControls(l)
        else
          ..._cancelControls(l, isScheduled: true),
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
                event: AnalyticsEvents.premiumCancel,
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

  /// The offer in two parts (F-79): [primary] is what the reader decides on —
  /// what they already have, then the price and the button (or the note that
  /// they cannot buy) — and goes ABOVE the benefit list; [secondary] is the
  /// rest of the payment surface and goes below it.
  ({List<Widget> primary, List<Widget> secondary}) _offerPanel(
      Localization l) {
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
          _marked(
              Icons.check_circle_outline,
              context.tokens.success.solid,
              RichLabel.of(
                l,
                subscription?.singleCharge == true
                    ? K.premStorePaidUntilAvulso
                    : K.premStorePaidUntilPeriod,
                args: [l.formatDate(stillPaid.toLocal())],
              ))
        else if (_planStatus.onTrial && trialEnd != null)
          _marked(
              Icons.auto_awesome,
              context.tokens.accent.solid,
              RichLabel.of(l, K.premStoreTrialUntil,
                  args: [l.formatDate(trialEnd.toLocal())])),
        const SizedBox(height: 4),
      ];
      // A store that can sell puts the price and the button up top; every
      // other store state is a note (or Play's own management link), which
      // reads better after the list it refers to.
      return _storeOfferState == StoreOffer.offer
          ? (primary: [...status, ..._storeBranch(l)], secondary: const [])
          : (
              primary: status,
              secondary: [const SizedBox(height: Spacing.sm), ..._storeBranch(l)]
            );
    }

    final primary = [
      if (stillPaid != null) ...[
        // T-39 (QA): a canceled-but-paid subscription keeps its Premium until
        // the period end — say so, and that re-subscribing ADDS to that date
        // (the webhook extends from the later of period-end/payment), so
        // nobody waits for the lapse.
        _marked(
            Icons.check_circle_outline,
            context.tokens.success.solid,
            RichLabel.of(
              l,
              subscription?.singleCharge == true
                  ? K.premPaidUntilAvulso
                  : K.premPaidUntilPeriod,
              args: [l.formatDate(stillPaid.toLocal())],
            )),
        if (expiringDaysLeft(stillPaid, now) case final daysLeft?)
          _marked(
              Icons.hourglass_bottom,
              context.tokens.warning.solid,
              RichLabel.of(l,
                  daysLeft == 1 ? K.premExpiringSoonOne : K.premExpiringSoonMany,
                  args: [daysLeft])),
      ],
      if (!_isAdmin)
        _marked(Icons.info_outline, context.tokens.textMuted,
            RichLabel.of(l, K.premAdminOnly))
      else ...[
        if (canReactivate(
          subscriptionStatus: subscription?.status,
          currentPeriodEndUtc: subscription?.currentPeriodEnd,
          billingType: subscription?.billingType,
          externalCustomerId: subscription?.externalCustomerId,
          nowUtc: now,
          singleCharge: subscription?.singleCharge ?? false,
        )) ...[
          ..._reactivateControls(l, subscription!),
          // U-46: the way back is the cheaper choice (F-42) and keeps the ONE
          // filled button; a new subscription is the tonal alternative here.
          ..._checkoutControls(l, primaryTaken: true),
        ] else
          ..._checkoutControls(l, primaryTaken: false),
      ],
      // F-46: a family paying DURING its trial starts the paid cycle at the
      // trial end. F-79: said right under "Assinar" rather than above the
      // price — the same sentence, now where the reader asks "and my trial?".
      if (stillPaid == null && _planStatus.onTrial && trialEnd != null) ...[
        const SizedBox(height: Spacing.sm),
        _marked(
            Icons.auto_awesome,
            context.tokens.accent.solid,
            RichLabel.of(l, K.premTrialAdditive,
                args: [l.formatDate(trialEnd.toLocal())])),
      ],
    ];
    return (
      primary: primary,
      secondary: _isAdmin ? _checkoutSecondary(l) : const <Widget>[],
    );
  }

  // ── U-46: the offer as one decision at a time. The cycle picker and the
  // price card are shared by both rails; what differs is where the number
  // comes from (app_settings on the web, Play's own string on the store) and
  // what the buttons call.

  /// `monthly` | `annual`, restricted to the cycles the rail can actually sell
  /// (the store may answer with one product). The picker never offers a
  /// cycle with nothing behind it.
  Widget _cyclePicker(Localization l, {required List<String> cycles}) =>
      AppSegmented<String>(
        key: const ValueKey('premium-cycle'),
        options: [
          for (final cycle in cycles)
            (
              value: cycle,
              label: l[cycle == 'annual' ? K.premPickAnnual : K.premPickMonthly]
            ),
        ],
        selected: _offerCycle,
        semantics: l[K.premPickSemantics],
        enabled: !_billingBusy,
        onChanged: (cycle) => setState(() => _offerCycle = cycle),
      );

  /// The chosen cycle's price, large, with the two annual facts under and
  /// beside it when the rail can vouch for them. [equivalent] and [freeMonths]
  /// are the WEB rail's: both come from app_settings arithmetic, and the store
  /// rail passes neither — Play's price is a localized string set in the
  /// Console, and the client asserts nothing it cannot compute.
  Widget _priceCard(
    Localization l, {
    required String price,
    String? equivalent,
    int freeMonths = 0,
  }) {
    final theme = Theme.of(context);
    return AppCard(
      key: const ValueKey('premium-price-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            children: [
              Text(price, style: theme.textTheme.headlineSmall),
              if (freeMonths > 0)
                AppBadge(
                  text: l.format(
                      freeMonths == 1
                          ? K.premFreeMonthsOne
                          : K.premFreeMonthsMany,
                      [freeMonths]),
                  tone: context.tokens.success,
                ),
            ],
          ),
          if (equivalent != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(equivalent, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  /// The one primary CTA — filled, unless another block already holds the
  /// primary (the F-42 way back), in which case it is the tonal alternative.
  Widget _subscribeButton(
    Localization l, {
    required bool primaryTaken,
    required VoidCallback? onPressed,
  }) {
    final label = Text(l[K.premSubscribe]);
    return primaryTaken
        ? FilledButton.tonal(
            key: const ValueKey('premium-subscribe'),
            onPressed: onPressed,
            child: label)
        : FilledButton(
            key: const ValueKey('premium-subscribe'),
            onPressed: onPressed,
            child: label);
  }

  /// T-48: what the STORE channel may offer. With the rail off — or with a
  /// store that cannot answer — this is the T-38 neutral note, which is what
  /// Play always accepts and what the app shipped with until now.
  StoreOffer get _storeOfferState => computeStoreOffer(
        storeBillingEnabled: _settings.storeBillingEnabled,
        storeAvailable: _storeAvailable,
        hasProducts: _storeProducts.isNotEmpty,
        purchasePending: _storePurchasePending,
        // F-84: only while the Play subscription still pays — an expired
        // one left the family free, and "managed" would hide the offer from
        // a family that can buy again.
        premiumThroughStore: _isPlaySubscription &&
            paidUntil(
                  subscriptionStatus: _subscription?.status,
                  currentPeriodEndUtc: _subscription?.currentPeriodEnd,
                  nowUtc: DateTime.now().toUtc(),
                ) !=
                null,
      );

  /// The cycles Play answered for, in the picker's order.
  List<String> get _storeCycles => [
        for (final cycle in const ['monthly', 'annual'])
          if (_storeProducts.any((p) => p.cycle == cycle)) cycle,
      ];

  List<Widget> _storeBranch(Localization l) {
    return switch (_storeOfferState) {
      StoreOffer.neutralNote => [RichLabel.of(l, K.premStoreNote)],
      StoreOffer.pendingVerification => [Text(l[KApp.storePending])],
      // F-84: its own sentence. It used to print the neutral note ("managed
      // on the website, not in this app") right above Play's own link.
      StoreOffer.managed => [
          RichLabel.of(l, K.premPlayNotRenewing),
          _manageOnPlay(l),
        ],
      StoreOffer.offer => _storeOffer(l),
    };
  }

  List<Widget> _storeOffer(Localization l) {
    if (!_isAdmin) {
      return [
        _marked(Icons.info_outline, context.tokens.textMuted,
            RichLabel.of(l, K.premAdminOnly))
      ];
    }
    // A selected cycle the store did not answer for falls back to whatever it
    // did — the card never shows a price for a product that does not exist.
    final cycles = _storeCycles;
    // The service already drops ids it does not recognise; this is the same
    // fail-closed default one layer up, so the card can never be built around
    // nothing.
    if (cycles.isEmpty) return [RichLabel.of(l, K.premStoreNote)];
    final selected = cycles.contains(_offerCycle) ? _offerCycle : cycles.first;
    final product = _storeProducts.firstWhere((p) => p.cycle == selected);
    return [
      const SizedBox(height: 12),
      if (cycles.length > 1) ...[
        _cyclePicker(l, cycles: cycles),
        const SizedBox(height: Spacing.sm),
      ],
      // The price is PLAY's, formatted by the store for this buyer's country —
      // never a number from app_settings, which rules the web rail only. No
      // per-month equivalent and no free-months badge: both would be
      // arithmetic on a localized string, i.e. a claim the client cannot check.
      _priceCard(
        l,
        price: l.format(
            selected == 'annual' ? K.premPriceAnnual : K.premPriceMonthly,
            [product.price]),
      ),
      const SizedBox(height: Spacing.sm),
      _subscribeButton(
        l,
        primaryTaken: false,
        onPressed: _billingBusy ? null : () => _buyFromStore(l, product),
      ),
      TextButton(
        onPressed: _billingBusy ? null : () => _restoreFromStore(l),
        child: Text(l[KApp.storeRestore]),
      ),
    ];
  }

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
      widget.analytics?.trackEvent(AnalyticsEvents.premiumCheckoutStart,
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

  /// The web rail's price for the cycle the picker holds — the card, the
  /// subscribe button and the Pix avulso button all quote this one number.
  String get _webOfferPrice => formatPriceBrl(_offerCycle == 'annual'
      ? _settings.priceAnnualCents
      : _settings.priceMonthlyCents);

  /// The web rail's decision: picker, price card, "Assinar".
  List<Widget> _checkoutControls(Localization l, {required bool primaryTaken}) {
    final monthlyCents = _settings.priceMonthlyCents;
    final annualCents = _settings.priceAnnualCents;
    final annual = _offerCycle == 'annual';
    final price = _webOfferPrice;
    return [
      const SizedBox(height: 12),
      _cyclePicker(l, cycles: const ['monthly', 'annual']),
      const SizedBox(height: Spacing.sm),
      // "2 meses grátis" is a factual claim and holds by construction: the
      // badge is COMPUTED from the same app_settings prices the checkout
      // charges (annual = 10 × monthly today), and so is the per-month line.
      _priceCard(
        l,
        price: l.format(
            annual ? K.premPriceAnnual : K.premPriceMonthly, [price]),
        equivalent: annual
            ? l.format(K.premPriceEquivalent,
                [formatPriceBrl(monthlyEquivalentCents(annualCents))])
            : null,
        freeMonths: annual
            ? annualFreeMonths(
                monthlyCents: monthlyCents, annualCents: annualCents)
            : 0,
      ),
      const SizedBox(height: Spacing.sm),
      _subscribeButton(
        l,
        primaryTaken: primaryTaken,
        onPressed: _billingBusy
            ? null
            : () => _startCheckout(l, _offerCycle, avulso: false),
      ),
    ];
  }

  /// The rest of the web rail's payment surface, below the benefit list
  /// (F-79): the second way to pay, how paying works, and the guarantee.
  List<Widget> _checkoutSecondary(Localization l) {
    final price = _webOfferPrice;
    return [
      const SizedBox(height: Spacing.md),
      // F-48: Pix avulso — the no-recurrence rail. One single charge for one
      // period: no card on file, no auto-renew, renewing later is an explicit
      // new payment (additive). It follows the cycle chosen above.
      RichLabel.of(l, K.premAvulsoLead),
      OutlinedButton(
        key: const ValueKey('premium-avulso'),
        onPressed: _billingBusy
            ? null
            : () => _startCheckout(l, _offerCycle, avulso: true),
        child: Text(l.format(K.premAvulsoButton, [price])),
      ),
      const SizedBox(height: 8),
      // F-48: trust signals on the payment surface — Pix first (no card data
      // leaves your bank app), then the 7-day guarantee, a visible mirror of
      // Terms §10 / CDC art. 49. Same promise, same channel — NOT a new
      // commitment, so no PolicyVersions bump.
      RichLabel.of(l, K.premPaymentHint,
          style: Theme.of(context).textTheme.bodySmall),
      _marked(
          Icons.verified_user_outlined,
          context.tokens.success.solid,
          // F-79: the sentence ends on the address it promises — the support
          // constant, never typed into the catalog.
          RichLabel.of(l, K.premGuarantee,
              args: [SupportRules.supportEmail],
              style: Theme.of(context).textTheme.bodySmall)),
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
                event: AnalyticsEvents.premiumReactivate,
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
      // U-49: the open/closed state is a vector chevron, not a glyph glued
      // to the label — the label is the catalog's word alone.
      TextButton.icon(
        onPressed: () => _toggleHistory(l),
        icon: Icon(_historyOpen ? Icons.expand_more : Icons.chevron_right),
        label: Text(l[K.premHistoryToggle]),
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
    if (_hasPremiumInterest) {
      return [
        _marked(Icons.check_circle_outline, context.tokens.success.solid,
            Text(l[K.premInterestDone]))
      ];
    }
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
}
