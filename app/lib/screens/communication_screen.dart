import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import '../services/notification_badge.dart';
import '../widgets/account_button.dart';
import '../widgets/app_l10n.dart';

/// F-35 — Comunicação: the bar's third tab while the Conversa is on.
///
/// Two tabs on top, each with its counter — Conversa (texts I have not read)
/// and Notificações (requests waiting on me) — and no tabs inside tabs: the
/// Notificações lists are chips there. `/notifications` and every push route
/// keep working; a chat push lands on the Conversa, every other one on
/// Notificações with its own list.
class CommunicationScreen extends StatefulWidget {
  final NotificationBadge badge;
  final Widget chat;
  final Widget notifications;

  /// Open on the Conversa (a chat push) or on Notificações (anything else).
  final bool openOnChat;

  /// Changes with every landing, so a second push re-selects the tab.
  final String? landingNonce;

  const CommunicationScreen({
    super.key,
    required this.badge,
    required this.chat,
    required this.notifications,
    this.openOnChat = false,
    this.landingNonce,
  });

  @override
  State<CommunicationScreen> createState() => _CommunicationScreenState();
}

class _CommunicationScreenState extends State<CommunicationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 2, vsync: this, initialIndex: widget.openOnChat ? 0 : 1);

  @override
  void didUpdateWidget(CommunicationScreen old) {
    super.didUpdateWidget(old);
    if (widget.landingNonce != old.landingNonce ||
        widget.openOnChat != old.openOnChat) {
      _tabs.animateTo(widget.openOnChat ? 0 : 1);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String _label(Localization l, String key, int count) =>
      count == 0 ? l[key] : l.format(KApp.chatTabCount, [l[key], count]);

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return Scaffold(
      appBar: AppBar(
        title: Text(l[KApp.chatNav]),
        actions: const [AppAccountButton()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kTextTabBarHeight),
          child: ListenableBuilder(
            listenable: widget.badge,
            builder: (context, _) => TabBar(
              controller: _tabs,
              tabs: [
                Tab(
                    key: const ValueKey('comm-tab-chat'),
                    text: _label(l, KApp.chatTabChat, widget.badge.chatUnread)),
                Tab(
                    key: const ValueKey('comm-tab-notifications'),
                    text: _label(
                        l, KApp.chatTabNotifications, widget.badge.count)),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [widget.chat, widget.notifications],
      ),
    );
  }
}
