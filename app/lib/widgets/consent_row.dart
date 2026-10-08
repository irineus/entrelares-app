import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../deep_link_urls.dart';
import 'app_l10n.dart';

/// The ONE checkbox of sign-up (A-1.1) and the sentence it accepts — shared by
/// the register screen and the Google onboarding, which used to carry two
/// verbatim copies.
///
/// U-64 (T-103 audit, 07/10/2026): the sentence was a `Wrap` of three texts
/// and two 48 dp `TextButton`s, so at 360 dp it read "Li e aceito a |
/// Política de Privacidade", a large gap, then "e os | Termos de Uso" on a
/// second PADDED row — a button's height inside a sentence. It is one
/// paragraph now, the two documents as links inside it: a link in running
/// text is WCAG 2.5.8's inline exception, and the box beside it is the
/// 48 dp target that matters.
class ConsentRow extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Opens one of the two documents (the privacy policy or the terms).
  final void Function(String url) onOpen;

  const ConsentRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onOpen,
  });

  @override
  State<ConsentRow> createState() => _ConsentRowState();
}

class _ConsentRowState extends State<ConsentRow> {
  late final TapGestureRecognizer _privacy = TapGestureRecognizer()
    ..onTap = () => widget.onOpen(DeepLinkUrls.privacy);
  late final TapGestureRecognizer _terms = TapGestureRecognizer()
    ..onTap = () => widget.onOpen(DeepLinkUrls.terms);

  @override
  void dispose() {
    _privacy.dispose();
    _terms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final theme = Theme.of(context);
    final link = TextStyle(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Checkbox(
          value: widget.value,
          // U-32: the box carries the whole sentence — a screen reader heard
          // an unnamed checkbox when the words were only beside it.
          semanticLabel: '${l[K.registerConsentAccept]} '
              '${l[K.commonPrivacyPolicy]} '
              '${l[K.registerConsentAnd]} '
              '${l[K.commonTermsOfUse]}',
          onChanged: (v) => widget.onChanged(v ?? false),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: theme.textTheme.bodySmall,
              children: [
                TextSpan(text: '${l[K.registerConsentAccept]} '),
                TextSpan(
                  text: l[K.commonPrivacyPolicy],
                  recognizer: _privacy,
                  style: link,
                ),
                TextSpan(text: ' ${l[K.registerConsentAnd]} '),
                TextSpan(
                  text: l[K.commonTermsOfUse],
                  recognizer: _terms,
                  style: link,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
