import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/app_l10n.dart';
import '../widgets/ui/ui.dart';

/// What a URL this app does not serve looks like — T-64.
///
/// The three catalog keys are the web client's own 404 strings, ported in lote
/// 1 and classified as web-only ever since, because this stack had no error
/// route: an unknown path was swallowed by the router and the reader landed on
/// the calendar with no hint that the link was wrong. On the web the URL IS the
/// interface, so a path that does not exist has to say so.
class NotFoundScreen extends StatelessWidget {
  /// The path the reader asked for — shown so a mistyped or truncated link is
  /// recognisable, and never made into a link of its own.
  final String location;
  final VoidCallback onBackToStart;

  const NotFoundScreen(
      {super.key, required this.location, required this.onBackToStart});

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppEmptyState(
                  icon: '🧭',
                  title: l[K.notFoundTitle],
                  body: l[K.notFoundBody],
                ),
                Text(location,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: Spacing.lg),
                FilledButton(
                    onPressed: onBackToStart, child: Text(l[K.notFoundBack])),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
