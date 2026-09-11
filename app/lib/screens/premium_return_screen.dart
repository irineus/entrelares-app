import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import 'package:entrelares_db_contracts/models/family.dart';
import '../services/analytics_service.dart';
import '../services/custody_data_source.dart';
import '../widgets/app_l10n.dart';

/// `/premium/retorno` — port of `PremiumReturn.razor`.
///
/// Where the hosted checkout sends the payer back. Confirmation reaches us
/// ASYNCHRONOUSLY (the billing webhook flips `families.plan`), so this screen
/// polls the family row until the flip arrives — seconds for card, up to a
/// minute for a Pix settling. The three outcomes are three honest sentences:
/// confirmed, still confirming, or "it may take a little longer" — never a
/// success we have not seen.
///
/// The page states a COMMERCIAL promise (the F-48 7-day refund) and what
/// happens to an unconfirmed payment, so each paragraph is ONE catalogue
/// entry — no fragment can land in the wrong clause.
class PremiumReturnScreen extends StatefulWidget {
  final CustodyDataSource dataSource;
  final AnalyticsService? analytics;

  /// Back to the Família page, where the plan state lives.
  final VoidCallback? onBackToFamily;

  /// ~60 s of polling (20 × 3 s) covers card (instant) and typical Pix
  /// settling. Injected so the test does not wait a real minute.
  final int maxAttempts;
  final Duration pollDelay;

  const PremiumReturnScreen({
    super.key,
    required this.dataSource,
    this.analytics,
    this.onBackToFamily,
    this.maxAttempts = 20,
    this.pollDelay = const Duration(seconds: 3),
  });

  @override
  State<PremiumReturnScreen> createState() => _PremiumReturnScreenState();
}

class _PremiumReturnScreenState extends State<PremiumReturnScreen> {
  bool _confirmed = false;
  bool _timedOut = false;

  /// Set on dispose: the poll runs across awaits, and navigating away must
  /// stop it rather than let it finish into a dead widget.
  bool _abandoned = false;

  @override
  void initState() {
    super.initState();
    _poll();
  }

  @override
  void dispose() {
    _abandoned = true;
    super.dispose();
  }

  Future<void> _poll() async {
    // F-48 funnel: landing here means the payer came back from the hosted
    // checkout; the outcome event follows when the poll resolves.
    widget.analytics?.trackEvent('premium-checkout-return',
        props: analyticsFunnelProps(channel: widget.analytics!.channel));

    for (var attempt = 0; attempt < widget.maxAttempts; attempt++) {
      Family? family;
      try {
        family = await widget.dataSource.fetchOwnFamily();
      } catch (_) {
        // A failed read is not a failed payment: keep polling and let the
        // timeout copy (which promises nothing) be the honest ending.
      }
      if (_abandoned) return;
      if (family?.plan.toLowerCase() == 'premium') {
        setState(() => _confirmed = true);
        widget.analytics?.trackEvent('premium-checkout-outcome',
            props: analyticsFunnelProps(
                channel: widget.analytics!.channel, outcome: 'confirmed'));
        return;
      }
      await Future<void>.delayed(widget.pollDelay);
      if (_abandoned) return;
    }

    setState(() => _timedOut = true);
    widget.analytics?.trackEvent('premium-checkout-outcome',
        props: analyticsFunnelProps(
            channel: widget.analytics!.channel, outcome: 'timeout'));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return Scaffold(
      appBar: AppBar(title: Text(l[K.payPageTitle])),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _body(l),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(Localization l) {
    final theme = Theme.of(context);
    if (_confirmed) {
      return [
        Text('🎉', style: theme.textTheme.displaySmall),
        const SizedBox(height: 8),
        Text(l[K.payActiveTitle], style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(l[K.payActiveBody], textAlign: TextAlign.center),
        const SizedBox(height: 8),
        // F-48: the guarantee travels to the confirmation too — the moment of
        // payment is when the promise matters most.
        Text(l[K.payGuarantee],
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: widget.onBackToFamily,
          child: Text(l[K.payBackToFamily]),
        ),
      ];
    }
    if (_timedOut) {
      return [
        Text('⏳', style: theme.textTheme.displaySmall),
        const SizedBox(height: 8),
        Text(l[K.payAlmostTitle], style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(l[K.payAlmostBody], textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(l[K.payAlmostHint],
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: widget.onBackToFamily,
          child: Text(l[K.payBackToFamily]),
        ),
      ];
    }
    return [
      const CircularProgressIndicator(),
      const SizedBox(height: 16),
      Text(l[K.payConfirmingTitle], style: theme.textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(l[K.payConfirmingBody], textAlign: TextAlign.center),
    ];
  }
}
