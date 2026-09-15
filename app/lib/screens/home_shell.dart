import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/foundation.dart';
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
  ///
  /// A [ValueListenable], not a value, and the reason is the T-65 device
  /// measurement of 13/09/2026. The shell is built inside a go_router route
  /// `builder`, and go_router caches the pages it built: a `setState` in the
  /// app's root re-runs `MaterialApp.router`, but the route builders run again
  /// only when the location changes or an inherited widget notifies. Both
  /// banners are decided AFTER the shell has mounted — one by a network read,
  /// the other by asking the browser — so a plain value handed to the builder
  /// would sit in the app's state, correct, and never reach the screen until
  /// the reader happened to switch tabs. Listening here is what makes a late
  /// answer paint, the way [adminMode] and [badge] already do.
  final ValueListenable<FamilyDeletionBanner?>? deletionBanner;

  /// T-65: the web→app offer, or null. It sits with the other banners rather
  /// than inside a screen because the reader's channel is a fact about the
  /// whole app, not about the tab they happen to be on. Listened to for the
  /// reason [deletionBanner] gives.
  final ValueListenable<AppHandoffBanner?>? appHandoff;

  /// T-18: the "Sem conexão · dados de HH:mm" strip. Above every tab because
  /// connectivity is a fact about the app, and because the calendar is not the
  /// only screen whose data stops being current. Listened to for the reason
  /// [deletionBanner] gives — the network drops long after the shell mounted.
  final ValueListenable<ConnectivitySnapshot>? connectivity;

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
      this.connectivity,
      this.tourKeys});

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge(
            [adminMode, deletionBanner, appHandoff, connectivity]),
        builder: (context, _) {
          // T-18 device measurement (14/09/2026): every strip here wrapped
          // itself in a SafeArea, AND the tab below still received the status
          // bar as top padding — so its app bar pushed down by the same inset a
          // second time, a band of empty chrome under the strip. Only the FIRST
          // visible strip takes the inset now, and the tab loses it whenever
          // any strip is showing (two strips used to take it twice as well).
          final deletion = deletionBanner?.value;
          final handoff = appHandoff?.value;
          final offline = connectivity?.value;
          final showsOffline = offline?.offline ?? false;
          final adminTop = adminMode.isActive;
          final deletionTop = !adminTop;
          final handoffTop = deletionTop && deletion == null;
          final offlineTop = handoffTop && handoff == null;
          final anyStrip =
              adminTop || deletion != null || handoff != null || showsOffline;
          final tab = AccountScope(
            identity: identity,
            onSignOut: onSignOut,
            onOpenProfile: onOpenProfile,
            child: shell,
          );
          return Column(
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
                        top: adminTop,
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
            if (deletion != null)
              _deletionBanner(context, l, deletion, top: deletionTop),
            if (handoff != null)
              _handoffBanner(context, l, handoff, top: handoffTop),
            if (showsOffline)
              _offlineStrip(context, l, offline!, top: offlineTop),
            Expanded(
              child: anyStrip
                  ? MediaQuery.removePadding(
                      context: context, removeTop: true, child: tab)
                  : tab,
            ),
          ],
        );
        },
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

  Widget _deletionBanner(
      BuildContext context, Localization l, FamilyDeletionBanner banner,
      {required bool top}) {
    return Material(
      color: context.tokens.dangerBarDeep,
      child: InkWell(
        onTap: banner.onTap,
        child: SafeArea(
          top: top,
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
  Widget _handoffBanner(
      BuildContext context, Localization l, AppHandoffBanner handoff,
      {required bool top}) {
    final tone = context.tokens.info;
    return Material(
      color: tone.container,
      child: SafeArea(
        top: top,
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

  /// T-18 — the `warning` tone: not the danger of the two banners above (the
  /// reader did nothing wrong and nothing is lost), not the quiet `info` of
  /// an offer either — what is on screen may no longer be the plan, and the
  /// sentence says since when. No close button: the strip leaves on its own
  /// the moment the server answers again, and a dismissed strip over an old
  /// plan is the exact mistake it exists to prevent.
  Widget _offlineStrip(
      BuildContext context, Localization l, ConnectivitySnapshot snapshot,
      {required bool top}) {
    final tone = context.tokens.warning;
    return Material(
      key: const Key('offline-strip'),
      color: tone.container,
      child: SafeArea(
        top: top,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.cloud_off_outlined, size: 16, color: tone.onContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  offlineStripText(l,
                      dataAsOf: snapshot.dataAsOf?.toLocal(),
                      now: DateTime.now()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tone.onContainer, fontSize: 13),
                ),
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
