import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

/// U-13 — renders the catalog entries that carry inline emphasis (the web's
/// `L.Rich`). The parsing is the pure mirror ([parseRichText]); this only
/// turns segments into spans, so a screen never shows `<strong>` to a user.
class RichLabel extends StatelessWidget {
  /// Already-substituted catalog text (use [RichLabel.of] for the common
  /// case of a key plus arguments).
  final String value;
  final TextStyle? style;
  final TextAlign? textAlign;

  const RichLabel(this.value, {super.key, this.style, this.textAlign});

  /// The everyday form: a catalog key with its positional arguments.
  factory RichLabel.of(
    Localization l,
    String catalogKey, {
    List<Object?> args = const [],
    TextStyle? style,
    TextAlign? textAlign,
  }) =>
      RichLabel(
        args.isEmpty ? l[catalogKey] : l.format(catalogKey, args),
        style: style,
        textAlign: textAlign,
      );

  @override
  Widget build(BuildContext context) {
    final segments = parseRichText(value);
    if (segments.length == 1 && !segments.first.bold) {
      return Text(segments.first.text, style: style, textAlign: textAlign);
    }
    return Text.rich(
      TextSpan(children: [
        for (final segment in segments)
          TextSpan(
            text: segment.text,
            style: segment.bold
                ? const TextStyle(fontWeight: FontWeight.bold)
                : null,
          ),
      ]),
      style: style,
      textAlign: textAlign,
      // The emphasis is decoration; readers of the semantics tree get the
      // sentence itself.
      semanticsLabel: stripRichText(value),
    );
  }
}
