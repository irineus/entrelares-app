/// U-27 — the components that carry STRUCTURE: what a section looks like, what
/// a card looks like, what a label/value row looks like.
///
/// U-28 QA moved the sheet's own chrome out to `sheets.dart` and retired
/// `AppSheetHeader` with it: a title that only ever appeared inside a sheet
/// belongs to the sheet frame, and a second component drawing the same block
/// would drift from it.
///
/// None of these invents a look. They fix the one the app already had in six
/// slightly different versions — `_sectionTitle` in Família, the same title
/// with different padding in Relatórios, `_infoRow` in Notificações against a
/// hand-built `Row` in the day sheet.
library;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// A section's title, with an optional action on the right (the "editar" of a
/// panel, the "ver tudo" of a list).
class AppSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  /// Spacing above. Zero for the first section on a screen, which already has
  /// the app bar above it.
  final double topSpacing;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.topSpacing = Spacing.lg,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topSpacing, bottom: Spacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A bordered surface with the app's padding. The colour, the border and the
/// radius come from `CardTheme`; what this adds is the padding every screen was
/// re-deciding, and an optional header so a titled card is one widget.
class AppCard extends StatelessWidget {
  final Widget child;
  final String? title;
  final Widget? titleTrailing;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.title,
    this.titleTrailing,
    this.padding = const EdgeInsets.all(Spacing.md),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: title == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSectionHeader(
                    title: title!,
                    trailing: titleTrailing,
                    topSpacing: 0),
                child,
              ],
            ),
    );
    return Card(
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(Radii.md),
              child: content,
            ),
    );
  }
}

/// A label on the left, its value on the right — the shape of every detail
/// panel in the app (a swap's dates, a subscription's next charge).
class AppListRow extends StatelessWidget {
  final String label;

  /// The value as text. Mutually exclusive with [valueWidget].
  final String? value;
  final Widget? valueWidget;

  /// How much wider the value column is than the label's. The app's panels all
  /// settled on 2:1, which is why it is the default rather than a parameter
  /// every call site has to think about.
  final int valueFlex;

  const AppListRow({
    super.key,
    required this.label,
    this.value,
    this.valueWidget,
    this.valueFlex = 2,
  }) : assert(value != null || valueWidget != null,
            'A row with no value is a section header, not a row.');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child:
                Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            flex: valueFlex,
            child: valueWidget ??
                Text(value!, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

/// A bulleted list with a hanging indent — the shape of every "you declare you
/// are aware that…" block in the app (family deletion, leaving, the Premium
/// benefits).
///
/// It exists because the port wrote these as one `Text` per line with a literal
/// `•` glued to the front: the second line of a wrapping item then starts under
/// the bullet instead of under the text, which is what made the Premium block
/// and both danger zones read as loose paragraphs.
class AppBulletList extends StatelessWidget {
  final List<String> items;

  /// The bullet glyph. A `•` for a notice, `—` for an enumeration that must not
  /// look like a checklist.
  final String bullet;

  /// Overrides the text colour — a list inside a toned block takes that block's
  /// `onContainer`, never the page's default text colour.
  final Color? color;

  /// Rendered before the item's text, one per item, when the list is a set of
  /// features rather than a set of warnings (the Premium benefits carry them).
  final List<Widget>? leadingIcons;

  const AppBulletList({
    super.key,
    required this.items,
    this.bullet = '•',
    this.color,
    this.leadingIcons,
  });

  @override
  Widget build(BuildContext context) {
    // Checked here and not in the constructor: `List.length` is not a constant
    // expression, so an assert on it would make every `const AppBulletList`
    // with icons fail to COMPILE — which is how this was found.
    assert(leadingIcons == null || leadingIcons!.length == items.length,
        'One icon per item, or none at all.');
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: color ?? context.tokens.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : Spacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: Spacing.lg,
                  // The glyph sits on the text's own baseline box, so a
                  // wrapping item keeps its second line under the text.
                  child: leadingIcons == null
                      ? Text(bullet, style: style)
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: leadingIcons![i]),
                ),
                Expanded(child: Text(items[i], style: style)),
              ],
            ),
          ),
      ],
    );
  }
}

/// One entry of an event log — the shape the web's audit and history lists use
/// and the port flattened into stacked cards.
///
/// The rail (the dot and the line under it) is the whole point: it says these
/// entries are ONE sequence in time. Without it a reader has to infer the order
/// from the timestamps, which is exactly the work a log exists to save.
class AppTimelineEntry extends StatelessWidget {
  /// The dot's tone — `neutral` for a plain record, `warning`/`danger` for one
  /// the reader should stop at.
  final ToneColors tone;

  /// What the dot carries. The app writes these as emoji, in the catalog.
  final String marker;

  /// The small line above the title ("Dia: 21/08/2026").
  final String? overline;

  final Widget title;
  final Widget? body;

  /// An inset block for the entry's own detail — the "Responsável real /
  /// Horário da troca" panel, the origin of an automatic change.
  final Widget? detail;

  final String timestamp;

  /// The last entry stops the rail at its dot instead of running it into the
  /// padding.
  final bool isLast;

  const AppTimelineEntry({
    super.key,
    required this.tone,
    required this.marker,
    required this.title,
    required this.timestamp,
    this.overline,
    this.body,
    this.detail,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: Spacing.xl,
            child: Column(
              children: [
                Container(
                  width: Spacing.lg,
                  height: Spacing.lg,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone.container,
                    shape: BoxShape.circle,
                    border: Border.all(color: tone.border),
                  ),
                  child: Text(marker,
                      style: const TextStyle(fontSize: TypeScale.label)),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: tokens.outline),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (overline != null)
                    Text(overline!,
                        style: textTheme.labelSmall
                            ?.copyWith(color: tokens.textMuted)),
                  title,
                  if (body != null) ...[
                    const SizedBox(height: Spacing.xs),
                    body!,
                  ],
                  if (detail != null) ...[
                    const SizedBox(height: Spacing.sm),
                    detail!,
                  ],
                  const SizedBox(height: Spacing.xs),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(timestamp,
                        style: textTheme.labelSmall
                            ?.copyWith(color: tokens.textMuted)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
