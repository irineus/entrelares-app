import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'app_l10n.dart';

/// F-57 — "Continuar com Google", shared by the login and register screens.
///
/// It renders NOTHING until [enabled] answers `true`, and [enabled] is
/// GoTrue's own settings endpoint saying the provider exists — the fail-closed
/// switch: while the owner has not configured the provider in a project's
/// console, that project's builds simply have no button, and a network failure
/// looks the same. The password form above it never depends on this answer.
///
/// **U-45 — the button follows Google's spec, not ours.** It used to be an
/// `OutlinedButton.icon` carrying `Icons.account_circle_outlined`: a generic
/// "account" glyph exactly where a person looks for the G. Every number and
/// colour below comes from [GoogleBrand], which is the *Sign in with Google*
/// guideline written down — the T-61 brand verification is a HUMAN review of
/// this product's OAuth surfaces, and an off-spec button is the cheapest thing
/// on that checklist to get wrong.
class GoogleSignInButton extends StatelessWidget {
  final Future<bool> enabled;
  final Future<void> Function() onPressed;

  const GoogleSignInButton({
    super.key,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    // The guideline names two surfaces and no others, so the theme decides
    // WHICH of Google's pairs is drawn — never how it is tinted.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface =
        dark ? GoogleBrand.darkSurface : GoogleBrand.lightSurface;
    final stroke = dark ? GoogleBrand.darkStroke : GoogleBrand.lightStroke;
    final ink = dark ? GoogleBrand.darkText : GoogleBrand.lightText;

    return FutureBuilder<bool>(
      future: enabled,
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        // The spacing rides INSIDE the visible state, so the disabled state
        // collapses to nothing instead of leaving a hole in the layout.
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SizedBox(
            height: GoogleBrand.height,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: surface,
                foregroundColor: ink,
                side: BorderSide(
                    color: stroke, width: GoogleBrand.strokeWidth),
                shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.all(Radius.circular(GoogleBrand.radius))),
                padding:
                    const EdgeInsets.symmetric(horizontal: GoogleBrand.padding),
                textStyle: const TextStyle(
                    fontSize: GoogleBrand.fontSize,
                    fontWeight: FontWeight.w500,
                    height: GoogleBrand.lineHeight / GoogleBrand.fontSize),
                // The spec's 40 dp IS the button. Material's padded tap target
                // would grow the box to 48 and break the height it asks for;
                // the button is full width, so the target stays generous.
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () async {
                try {
                  await onPressed();
                } catch (_) {
                  // The redirect could not even launch (no browser, platform
                  // refusal) — the one failure mode that is OURS to report;
                  // everything after the launch belongs to the provider page.
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l[KApp.authGoogleErr])));
                  }
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The mark may not be recoloured or redrawn, so it is an
                  // image and never an icon font. The sentence beside it is
                  // the accessible name; a second label here would read the
                  // button twice.
                  Image.asset(GoogleBrand.logoAsset,
                      width: GoogleBrand.logoSize,
                      height: GoogleBrand.logoSize,
                      excludeFromSemantics: true),
                  const SizedBox(width: GoogleBrand.logoGap),
                  Flexible(
                    child: Text(l[KApp.authGoogle],
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
