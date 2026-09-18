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
import '../widgets/install_hint_sheet.dart';
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

/// U-51 — the invitation to put the web app on an iPhone's Home Screen.
///
/// Data, not a widget, like [AppHandoffBanner]: the shell owns how the strip
/// looks and opens the sheet with the steps; `main.dart` owns whether there
/// is one — which on every native build, on Android, on desktop and in an
/// app already on the Home Screen is "no".
class InstallHintBanner {
  /// The reader asked for the steps. The shell opens the sheet; this only
  /// records that it happened.
  final VoidCallback onOpen;

  /// Puts the hint away for good on this browser.
  final VoidCallback onDismiss;

  const InstallHintBanner({required this.onOpen, required this.onDismiss});
}

/// The authenticated hull — the same four destinations as the web's NavMenu
/// bottom tab bar (Calendário, Família, Notificações, Relatórios). Branch state is
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

  /// U-51: the iPhone install hint, or null. With the other banners for the
  /// same reason as [appHandoff]: which channel the reader is on is a fact
  /// about the whole app. Listened to for the reason [deletionBanner] gives.
  final ValueListenable<InstallHintBanner?>? installHint;

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
      this.installHint,
      this.connectivity,
      this.tourKeys});

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge(
            [adminMode, deletionBanner, appHandoff, installHint, connectivity]),
        builder: (context, _) {
          // T-18 device measurement (14/09/2026): every strip here wrapped
          // itself in a SafeArea, AND the tab below still received the status
          // bar as top padding — so its app bar pushed down by the same inset a
          // second time, a band of empty chrome under the strip. Only the FIRST
          // visible strip takes the inset now, and the tab loses it whenever
          // any strip is showing (two strips used to take it twice as well).
          final deletion = deletionBanner?.value;
          final handoff = appHandoff?.value;
          final install = installHint?.value;
          final offline = connectivity?.value;
          final showsOffline = offline?.offline ?? false;
          final adminTop = adminMode.isActive;
          final deletionTop = !adminTop;
          final handoffTop = deletionTop && deletion == null;
          final installTop = handoffTop && handoff == null;
          final offlineTop = installTop && install == null;
          final anyStrip = adminTop ||
              deletion != null ||
              handoff != null ||
              install != null ||
              showsOffline;
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
                              const Icon(Icons.shield_outlined,
                                  size: 16, color: Colors.white),
                              const SizedBox(width: 6),
                              Expanded(
                                // U-28 QA: one line with an ellipsis, exactly
                                // as the web draws it. Wrapped to two it was
                                // costing the calendar below a whole row.
                                child: Text(
                                  '${l[K.layoutAdminActive]} — '
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
            if (install != null)
              _installHintStrip(context, l, install, top: installTop),
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
        builder: (context, _) => _NavLabelFit(
          labels: [
            l[K.navCalendar],
            l[K.navFamily],
            l[K.navNotificationsShort],
            l[K.navReports],
          ],
          child: NavigationBar(
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
                  icon: _bellIcon(const Icon(Icons.notifications_outlined), l),
                  selectedIcon: _bellIcon(const Icon(Icons.notifications), l),
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.delete_outline,
                      size: 16, color: Colors.white),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    // Unanimity already reached reads differently from a
                    // request still collecting answers — the deadline means
                    // something else in each case.
                    banner.allAgreed
                        ? '${l[K.layoutFamilyDeletionConfirmed]} '
                            '${l.format(K.layoutFamilyDeletionConfirmedUntil, [
                              l.formatDate(banner.scheduledFor.toLocal())
                            ])}'
                        : '${l[K.layoutFamilyDeletionRequested]} — '
                            '${l.format(banner.iAmRequester ? K.layoutFamilyDeletionRequester : K.layoutFamilyDeletionOther, [
                              l.formatDateShort(banner.scheduledFor.toLocal())
                            ])}',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
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

  /// U-51 — the same quiet shape as the T-65 offer: `info` tone, one line, a
  /// way in and a way out. The steps do not fit a strip, so the line is the
  /// invitation and the sheet is the guide. The Share glyph is the one thing
  /// the reader will look for next.
  Widget _installHintStrip(
      BuildContext context, Localization l, InstallHintBanner hint,
      {required bool top}) {
    final tone = context.tokens.info;
    return Material(
      key: const Key('install-hint-strip'),
      color: tone.container,
      child: SafeArea(
        top: top,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Icon(Icons.ios_share, size: 16, color: tone.onContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l[KApp.installHintBanner],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tone.onContainer, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: () {
                  hint.onOpen();
                  showInstallHintSheet(context);
                },
                child: Text(l[KApp.installHintHow]),
              ),
              IconButton(
                onPressed: hint.onDismiss,
                icon: const Icon(Icons.close, size: 18),
                color: tone.onContainer,
                tooltip: l[KApp.installHintDismiss],
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

  /// U-32 (TalkBack, 18/09/2026): the badge's text was its own node, so the
  /// reader heard "2" and then "Notificações". The count rides as the sentence the
  /// tooltip already carries, and the bare number leaves the tree.
  Widget _bellIcon(Icon icon, Localization l) => Semantics(
        label: badge.count > 0
            ? l.format(
                badge.count == 1
                    ? K.navNotificationsOnePending
                    : K.navNotificationsManyPending,
                [badge.count])
            : null,
        excludeSemantics: true,
        child: Badge(
          isLabelVisible: badge.count > 0,
          label: Text(bellBadgeText(badge.count)),
          child: icon,
        ),
      );
}

/// U-34 — the bar's labels fit their slots at the reader's text scale.
///
/// The bell's tab says "Notificações", the word its screen's title says, and
/// with the real font that is 79.7 dp in a 90 dp slot at 1.0× and 101.7 dp at
/// 1.3× — where `NavigationDestination` (a bare `Text`, no overflow rule)
/// breaks it mid-word into a bar that has one line of height. So the whole
/// bar takes ONE ceiling, the U-39 shape: the largest factor at which the
/// widest label still fits, never below 1.0 and never above what the reader
/// asked for. At the default scale this is a no-op (U-48: the adjustment is
/// paid for by the reader who asked for it), and one ceiling for the four
/// labels keeps them the same size as each other.
class _NavLabelFit extends StatelessWidget {
  final List<String> labels;
  final Widget child;

  const _NavLabelFit({required this.labels, required this.child});

  /// Air kept on each side of the widest label, so two neighbours never touch.
  static const double _sideGap = 2;

  /// The SDK already stops the bar's labels here (`navigation_bar.dart`).
  static const double _sdkCeiling = 1.3;

  @override
  Widget build(BuildContext context) {
    final style = NavigationBarTheme.of(context)
        .labelTextStyle
        ?.resolve(const {WidgetState.selected});
    final size = style?.fontSize;
    if (style == null || size == null || labels.isEmpty) return child;
    final reader =
        (MediaQuery.textScalerOf(context).scale(size) / size)
            .clamp(1.0, _sdkCeiling);
    if (reader <= 1.0) return child;

    var widest = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    if (widest <= 0) return child;
    final slot =
        MediaQuery.sizeOf(context).width / labels.length - 2 * _sideGap;
    final ceiling = (slot / widest).clamp(1.0, reader);
    if (ceiling >= reader) return child;
    return MediaQuery.withClampedTextScaling(
        maxScaleFactor: ceiling, child: child);
  }
}
