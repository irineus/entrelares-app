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
import '../services/custody_data_source.dart';
import '../services/store_billing.dart';
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
  StreamSubscription<StorePurchase>? _storeSubscription;

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
    if (store != null) _storeSubscription = store.purchases.listen(_onPurchase);
  }

  @override
  void dispose() {
    _storeSubscription?.cancel();
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
      // F-48: first funnel step — the offer became VISIBLE. Guarded so a
      // reload within the same visit (e.g. after a cancel) counts once. U-35:
      // "visible" is THIS page now, not the Família tab.
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
        _family = family;
        _me = results[1] as Member?;
        _settings = settings;
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
        return _offerPanel(l);
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
        _marked(
            Icons.warning_amber_rounded,
            context.tokens.danger.solid,
            RichLabel.of(l, K.premOverdueGraceEnded,
                args: [l.formatDate(deadline.toLocal())]))
      ];
    }
    return [
      _marked(
          Icons.warning_amber_rounded,
          context.tokens.warning.solid,
          deadline == null
              ? RichLabel.of(l, K.premOverdueInGraceNoDate)
              : RichLabel.of(l, K.premOverdueInGrace,
                  args: [l.formatDate(deadline.toLocal())])),
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
      return [...status, ..._storeBranch(l)];
    }

    return [
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
      ] else if (_planStatus.onTrial && trialEnd != null)
        // F-46: a family paying DURING its trial starts the paid cycle at the
        // trial end — say it before any checkout button.
        _marked(
            Icons.auto_awesome,
            context.tokens.accent.solid,
            RichLabel.of(l, K.premTrialAdditive,
                args: [l.formatDate(trialEnd.toLocal())])),
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
    ];
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

  List<Widget> _storeOffer(Localization l) {
    if (!_isAdmin) {
      return [
        _marked(Icons.info_outline, context.tokens.textMuted,
            RichLabel.of(l, K.premAdminOnly))
      ];
    }
    // The cycles Play answered for, in the picker's order. A selected cycle
    // the store did not answer for falls back to whatever it did — the card
    // never shows a price for a product that does not exist.
    final cycles = [
      for (final cycle in const ['monthly', 'annual'])
        if (_storeProducts.any((p) => p.cycle == cycle)) cycle,
    ];
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

  List<Widget> _checkoutControls(Localization l, {required bool primaryTaken}) {
    final monthlyCents = _settings.priceMonthlyCents;
    final annualCents = _settings.priceAnnualCents;
    final annual = _offerCycle == 'annual';
    final price = formatPriceBrl(annual ? annualCents : monthlyCents);
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
      const SizedBox(height: 8),
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
          RichLabel.of(l, K.premGuarantee,
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
