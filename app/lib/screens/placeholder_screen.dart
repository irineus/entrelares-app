import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import '../widgets/app_l10n.dart';

/// A shell destination whose screen belongs to a later batch of the parity
/// map. The tab bar is complete from lote 1 on (same four destinations as the
/// web's NavMenu); each batch swapped this filling for the real screen, and
/// with Relatórios (lote 6) the last one is gone — what remains is the cheap
/// branch filling the shell/navigation test builds its four destinations from.
class PlaceholderScreen extends StatelessWidget {
  /// Catalog key of the destination's nav label (doubles as the app bar
  /// title, exactly what the web page titles do).
  final String titleKey;

  const PlaceholderScreen({super.key, required this.titleKey});

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return Scaffold(
      appBar: AppBar(title: Text(l[titleKey])),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction,
                  size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(l[KApp.shellUnderConstructionTitle],
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(l[KApp.shellUnderConstructionBody],
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
