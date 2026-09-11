import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Keeps the app a phone-shaped column, however wide the window is.
///
/// It exists because the web channel inherits a promise the Blazor PWA always
/// kept: pages lived in a centred column, never edge to edge. Wrapped around
/// `MaterialApp.builder`, it sits above the Navigator and therefore covers
/// every route, sheet and dialog — one place, with no screen to forget.
///
/// A separate widget rather than an inline closure so the ARRANGEMENT can be
/// measured by a test: presence is not position (U-28's most expensive
/// lesson), and a cap that silently stops binding would look like nothing at
/// all in a suite that only asserts what is on screen.
class AppWidthCap extends StatelessWidget {
  const AppWidthCap({super.key, required this.child});

  /// Nullable because `MaterialApp.builder` hands over a nullable child.
  final Widget? child;

  @override
  Widget build(BuildContext context) => ColoredBox(
        // The margins are page background, not a hole in the app.
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxAppWidth),
            child: child,
          ),
        ),
      );
}
