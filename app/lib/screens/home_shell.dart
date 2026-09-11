import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import 'package:go_router/go_router.dart';

import '../services/account_identity.dart';
import '../services/admin_mode.dart';
import '../services/notification_badge.dart';
import '../widgets/account_button.dart';
import '../widgets/app_l10n.dart';
import '../widgets/onboarding.dart';

/// What the shell needs to paint the S-11 banner: the deadline, whether the
/// family already agreed unanimously, and whether I am the one who asked (the
/// requester can withdraw; everyone else has to answer).
class FamilyDeletionBanner {
  final DateTime scheduledFor;
  final bool allAgreed;
  final bool iAmRequester;
  final VoidCallback onTap;

  const FamilyDeletionBanner({
    required this.scheduledFor,
    required this.allAgreed,
    required this.iAmRequester,
    required this.onTap,
  });
}

/// T-65 — the offer to cross from the web channel into the installed app.
///
/// Data, not a widget, for the same reason [FamilyDeletionBanner] is: the shell
/// owns how a banner looks, and the state deciding whether there IS one lives
/// in `main.dart`. Null is the overwhelmingly common case — every native build,
/// and on the web every reader whose browser did not confirm the app is on this
/// device.
class AppHandoffBanner {
  /// Opens the app at the reader's current location.
  final VoidCallback onOpen;

  /// Puts the offer away for good on this browser.
  final VoidCallback onDismiss;

  const AppHandoffBanner({required this.onOpen, required this.onDismiss});
}

/// The authenticated hull — the same four destinations as the web's NavMenu
/// bottom tab bar (Calendário, Família, Avisos, Relatórios). Branch state is
/// preserved per tab by the indexed stack, the native improvement over the
/// web's full page swaps. The bell badge counts the OPEN REQUESTS AWAITING
/// ME (web parity — not unread notifications), capped at "99+".
class HomeShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  final AdminMode adminMode;
  final NotificationBadge badge;

  /// U-28: who is signed in, published by whichever screen loaded them and read
  /// by the account button in every tab's app bar.
  final AccountIdentity identity;

  /// U-28: the defect this closes — sign-out used to be a `CalendarScreen`
  /// parameter, so three of the four tabs had no way out of the app.
  final Future<void> Function() onSignOut;

  final VoidCallback onOpenProfile;

  /// S-11: the live family-deletion request, if there is one. The banner sits
  /// above every tab because the deadline applies to the whole app, and it is
  /// the only way a member who never opens Família learns their family is
  /// scheduled for removal.
  final FamilyDeletionBanner? deletionBanner;

  /// T-65: the web→app offer, or null. It sits with the other banners rather
  /// than inside a screen because the reader's channel is a fact about the
  /// whole app, not about the tab they happen to be on.
  final AppHandoffBanner? appHandoff;

  /// U-23: the notifications tab is the tour's fourth stop, and it lives here
  /// rather than in any screen — so the key registry is shared.
  final TourKeys? tourKeys;

  const HomeShell(
      {super.key,
      required this.shell,
      required this.adminMode,
      required this.badge,
      required this.identity,
      required this.onSignOut,
      required this.onOpenProfile,
      this.deletionBanner,
      this.appHandoff,
      this.tourKeys});

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return Scaffold(
      body: ListenableBuilder(
        listenable: adminMode,
        builder: (context, _) => Column(
          children: [
            // F-14: the persistent, explicit banner while admin mode is on —
            // mirror of the web's MainLayout strip (shown on every tab).
            // U-27: the banner slides in over 400 ms instead of appearing
            // between two frames — a red strip that materialises silently over
            // the whole app reads as a glitch, not as a mode.
            AnimatedSize(
              duration: Motion.page,
              curve: Motion.pageCurve,
              alignment: Alignment.bottomCenter,
              child: !adminMode.isActive
                  ? const SizedBox(width: double.infinity)
                  : Material(
                      color: context.tokens.dangerBar,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                // U-28 QA: one line with an ellipsis, exactly
                                // as the web draws it. Wrapped to two it was
                                // costing the calendar below a whole row.
                                child: Text(
                                  '🛡️ ${l[K.layoutAdminActive]} — '
                                  '${l[K.layoutAdminHint]}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13),
                                ),
                              ),
                              TextButton(
                                onPressed: adminMode.deactivate,
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    visualDensity: VisualDensity.compact),
                                child: Text(l[K.layoutAdminExit]),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
            if (deletionBanner != null) _deletionBanner(context, l),
            if (appHandoff != null) _handoffBanner(context, l),
            Expanded(
              child: AccountScope(
                identity: identity,
                onSignOut: onSignOut,
                onOpenProfile: onOpenProfile,
                child: shell,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: badge,
        builder: (context, _) => NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (index) {
            shell.goBranch(index,
                // Re-tapping the active tab resets it to its root, the
                // platform convention.
                initialLocation: index == shell.currentIndex);
            // Web parity: the badge refreshes on every navigation.
            badge.refresh();
          },
          destinations: [
            NavigationDestination(
                icon: const Icon(Icons.calendar_month_outlined),
                selectedIcon: const Icon(Icons.calendar_month),
                label: l[K.navCalendar]),
            NavigationDestination(
                icon: const Icon(Icons.group_outlined),
                selectedIcon: const Icon(Icons.group),
                label: l[K.navFamily]),
            NavigationDestination(
                key: tourKeys?.keyFor(TourTarget.notificationsTab),
                icon: _bellIcon(const Icon(Icons.notifications_outlined)),
                selectedIcon: _bellIcon(const Icon(Icons.notifications)),
                tooltip: badge.count > 0
                    ? l.format(
                        badge.count == 1
                            ? K.navNotificationsOnePending
                            : K.navNotificationsManyPending,
                        [badge.count])
                    : null,
                label: l[K.navNotificationsShort]),
            NavigationDestination(
                icon: const Icon(Icons.bar_chart_outlined),
                selectedIcon: const Icon(Icons.bar_chart),
                label: l[K.navReports]),
          ],
        ),
      ),
    );
  }

  Widget _deletionBanner(BuildContext context, Localization l) {
    final banner = deletionBanner!;
    return Material(
      color: context.tokens.dangerBarDeep,
      child: InkWell(
        onTap: banner.onTap,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              // Unanimity already reached reads differently from a request
              // still collecting answers — the deadline means something else
              // in each case.
              banner.allAgreed
                  ? '🗑️ ${l[K.layoutFamilyDeletionConfirmed]} '
                      '${l.format(K.layoutFamilyDeletionConfirmedUntil, [
                        l.formatDate(banner.scheduledFor.toLocal())
                      ])}'
                  : '🗑️ ${l[K.layoutFamilyDeletionRequested]} — '
                      '${l.format(banner.iAmRequester ? K.layoutFamilyDeletionRequester : K.layoutFamilyDeletionOther, [
                        l.formatDateShort(banner.scheduledFor.toLocal())
                      ])}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }

  /// T-65 — quiet by construction: the `info` tone, one line, and a way out
  /// that stays out. It is an offer, not a warning, and it must never read
  /// like the two banners above it, which report states the reader did not
  /// choose.
  Widget _handoffBanner(BuildContext context, Localization l) {
    final handoff = appHandoff!;
    final tone = context.tokens.info;
    return Material(
      color: tone.container,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l[KApp.handoffBanner],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tone.onContainer, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: handoff.onOpen,
                child: Text(l[KApp.handoffOpen]),
              ),
              IconButton(
                onPressed: handoff.onDismiss,
                icon: const Icon(Icons.close, size: 18),
                color: tone.onContainer,
                tooltip: l[KApp.handoffDismiss],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bellIcon(Icon icon) => Badge(
        isLabelVisible: badge.count > 0,
        label: Text(bellBadgeText(badge.count)),
        child: icon,
      );
}
