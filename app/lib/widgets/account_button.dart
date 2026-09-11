import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import '../services/account_identity.dart';
import '../theme/tokens.dart';
import 'app_l10n.dart';
import 'ui/ui.dart';

/// What the account button needs, handed down once by the shell so every tab's
/// app bar can carry the same button without threading five callbacks through
/// five screens.
class AccountScope extends InheritedWidget {
  final AccountIdentity identity;

  /// Throws nothing: the app's sign-out already falls back to a local scope and
  /// navigates either way (pilot lesson 3).
  final Future<void> Function() onSignOut;

  final VoidCallback onOpenProfile;

  const AccountScope({
    super.key,
    required this.identity,
    required this.onSignOut,
    required this.onOpenProfile,
    required super.child,
  });

  static AccountScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountScope>();

  /// For a screen that has just LOADED the signed-in member and wants to
  /// publish it. Deliberately not `dependOn…`: a screen that writes the
  /// identity must not also rebuild because of it.
  static AccountIdentity? identityOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AccountScope>()?.identity;

  @override
  bool updateShouldNotify(AccountScope oldWidget) =>
      identity != oldWidget.identity ||
      onSignOut != oldWidget.onSignOut ||
      onOpenProfile != oldWidget.onOpenProfile;
}

enum _AccountAction { profile, ptBr, en, signOut }

/// U-28 — the account entry point, in the app bar of every tab.
///
/// It replaces four loose icons on the calendar's app bar (which had pushed the
/// month name into an ellipsis) and closes a real defect: `onSignOut` was a
/// parameter of `CalendarScreen`, so a reader sitting on Família, Avisos or
/// Relatórios had no way to leave the app.
///
/// Renders nothing at all when no [AccountScope] is above it — the sign-in
/// screens have no account to offer, and a dead button there would be worse
/// than none.
class AppAccountButton extends StatelessWidget {
  const AppAccountButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AccountScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    final app = AppL10n.of(context);
    final l = app.l;

    return ListenableBuilder(
      listenable: scope.identity,
      builder: (context, _) {
        final slot = scope.identity.colorSlot;
        return PopupMenuButton<_AccountAction>(
          tooltip: l[K.navAccount],
          // U-28 QA: the avatar alone was not a discoverable affordance — the
          // owner could not find sign-out at all, and sign-out lives in here.
          // A bare circle reads as a decoration; a circle with a caret reads as
          // a menu, which is the convention every account menu uses.
          icon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The avatar wears the reader's own calendar colour, so the
              // button says WHOSE account as well as "account".
              AppAvatar(
                initials: scope.identity.initial,
                slot: slot == null ? null : context.tokens.slot(slot),
                radius: 14,
              ),
              Icon(Icons.arrow_drop_down,
                  size: TypeScale.title, color: context.tokens.textMuted),
            ],
          ),
          onSelected: (action) => switch (action) {
            _AccountAction.profile => scope.onOpenProfile(),
            _AccountAction.ptBr => app.setLanguage(AppLanguage.ptBr),
            _AccountAction.en => app.setLanguage(AppLanguage.en),
            _AccountAction.signOut => scope.onSignOut(),
          },
          itemBuilder: (context) => [
            if (scope.identity.fullName != null)
              PopupMenuItem(
                enabled: false,
                child: Text(scope.identity.fullName!,
                    style: Theme.of(context).textTheme.labelSmall),
              ),
            PopupMenuItem(
              value: _AccountAction.profile,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(l[K.navProfile]),
              ),
            ),
            const PopupMenuDivider(),
            // U-13's picker, which used to live as its own icon on the calendar
            // app bar. The current language is DISABLED rather than hidden:
            // seeing both is how a reader learns the app has the other one.
            for (final (action, language, label) in [
              (_AccountAction.ptBr, AppLanguage.ptBr, l[K.languagePtBr]),
              (_AccountAction.en, AppLanguage.en, l[K.languageEn]),
            ])
              CheckedPopupMenuItem(
                value: action,
                checked: l.current == language,
                enabled: l.current != language,
                child: Text(label),
              ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: _AccountAction.signOut,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.logout, color: context.tokens.danger.solid),
                title: Text(l[K.navLogout],
                    style: TextStyle(color: context.tokens.danger.onContainer)),
              ),
            ),
          ],
        );
      },
    );
  }
}
