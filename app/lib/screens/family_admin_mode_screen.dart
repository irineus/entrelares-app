import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import '../services/admin_mode.dart';
import '../services/analytics_service.dart';
import '../services/custody_data_source.dart';
import '../theme/tokens.dart';
import '../widgets/app_l10n.dart';
import '../widgets/ui/ui.dart';

/// `/family/admin-mode` — the F-14 admin-mode card, on its own page (U-35).
///
/// It was a section of the Família scroll. The mode is a rare, deliberate act
/// ("use apenas para correções"), and the roster is the most-visited tab: the
/// Família page keeps one row — *Modo administrador*, subtitled on/off — and
/// this page is what the row opens. The card itself did not change: the
/// tier-aware F-40 copy, the amber toggle (U-28) and the Premium gate CTA are
/// the same; only the gate CTA now NAVIGATES to the plan page instead of
/// scrolling to a section that no longer shares the screen.
///
/// The shell's persistent banner (F-14) is still the way OUT while the mode
/// is on — that never depended on this page.
class FamilyAdminModeScreen extends StatefulWidget {
  final CustodyDataSource dataSource;
  final AdminMode adminMode;

  /// T-37 — optional: the gate signal never gates the page.
  final AnalyticsService? analytics;

  /// Opens `/family/plan` from the free-tier gate. Null leaves the tier copy
  /// as a plain explanation.
  final VoidCallback? onOpenPlan;

  const FamilyAdminModeScreen({
    super.key,
    required this.dataSource,
    required this.adminMode,
    this.analytics,
    this.onOpenPlan,
  });

  @override
  State<FamilyAdminModeScreen> createState() => _FamilyAdminModeScreenState();
}

class _FamilyAdminModeScreenState extends State<FamilyAdminModeScreen> {
  bool _loading = true;
  String? _loadErrorKey;
  bool _isPremium = false;
  bool _isAdmin = false;
  PublicSettings _settings = PublicSettings.unloaded;

  @override
  void initState() {
    super.initState();
    _load();
  }

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
      if (!mounted) return;
      setState(() {
        _isPremium = Family.isPremiumFamily(
            results[0] as Family?, DateTime.now().toUtc());
        _isAdmin = (results[1] as Member?)?.isAdmin == true;
        _settings = PublicSettings(results[2] as Map<String, String>);
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

  /// The gate CTA: record the intent signal (T-37, one event family
  /// distinguished by `gate`) and open the plan page. Never a price and never
  /// an external link — what may be OFFERED is that page's call, and it
  /// depends on the channel.
  void _goToPremium() {
    widget.analytics
        ?.trackEvent(AnalyticsEvents.premiumGateClick, props: {'gate': 'admin-mode'});
    widget.onOpenPlan?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final appBar = AppBar(title: Text(l[K.famAdminSection]));
    if (_loading) {
      return Scaffold(
        appBar: appBar,
        body: AppSkeletonCards(
            count: 1, height: 160, semanticsLabel: l[K.famLoading]),
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // The mode is an admin's tool; someone else who lands here (a typed
          // URL) reads the same sentence the invitation block gives them.
          if (!_isAdmin)
            AppCard(
                child: Text(l[K.famOnlyAdminsInvite],
                    style: Theme.of(context).textTheme.bodySmall))
          else
            _adminModeCard(l),
        ],
      ),
    );
  }

  Widget _adminModeCard(Localization l) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.adminMode,
      builder: (context, _) => AppCard(
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
                  onPressed: _goToPremium,
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
        ),
      ),
    );
  }
}
