import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart'
    show GoogleSignInException;

import '../env.dart';
import '../services/google_identity.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'app_l10n.dart';
import 'google_web_button.dart';

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
/// guideline written down. The reason given here used to be that T-61's brand
/// verification was a human review of this product's OAuth surfaces; T-61
/// closed on 10/09/2026 and there was no such review — for non-sensitive
/// scopes Google requires no submission at all. The spec still binds: it is
/// Google's published guideline for this button, and it is the surface a
/// person meets one screen before handing over their identity.
///
/// **F-71 — on the web with the native flow, the button is Google's.** GIS
/// hands an ID token only to its own `renderButton`, so there the widget below
/// is replaced by it and [onIdToken] receives each token the button produces.
/// Everywhere else (Android, and every build still on the redirect) it is the
/// U-45 button calling [onPressed].
class GoogleSignInButton extends StatefulWidget {
  final Future<bool> enabled;
  final Future<void> Function() onPressed;

  /// F-71: where the GIS button's ID token goes (web, native flow only).
  final Future<void> Function(String idToken)? onIdToken;

  const GoogleSignInButton({
    super.key,
    required this.enabled,
    required this.onPressed,
    this.onIdToken,
  });

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  StreamSubscription<String>? _tokens;

  /// The web's GIS button replaces ours only when the environment is on the
  /// native flow AND the caller can take a token.
  bool get _gis =>
      kIsWeb && Env.current.nativeGoogleSignIn && widget.onIdToken != null;

  @override
  void initState() {
    super.initState();
    if (_gis) {
      _tokens = GoogleIdentity.webIdTokens().listen(
        (token) => _run(() => widget.onIdToken!(token)),
        onError: (Object e) {
          if (e is GoogleSignInException && GoogleIdentity.isBackOut(e.code)) {
            return;
          }
          _reportFailure();
        },
      );
    }
  }

  @override
  void dispose() {
    _tokens?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      _reportFailure();
    }
  }

  /// The one failure mode that is OURS to report: the sign-in could not even
  /// start, or the token was refused. Backing out of Google's own sheet is a
  /// choice, and says nothing.
  void _reportFailure() {
    if (!mounted) return;
    final l = AppL10n.of(context).l;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l[KApp.authGoogleErr])));
  }

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
      future: widget.enabled,
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        if (_gis) {
          // F-71: the GIS script loads only here, once the provider exists —
          // a page that never shows the button never fetches it.
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FutureBuilder<void>(
              future: GoogleIdentity.ensureInitialized(),
              builder: (context, init) {
                if (init.connectionState != ConnectionState.done ||
                    init.hasError) {
                  return const SizedBox(height: GoogleBrand.height);
                }
                return LayoutBuilder(
                  builder: (context, box) => SizedBox(
                    height: GoogleBrand.height,
                    child: googleWebButton(
                      dark: dark,
                      width: box.maxWidth,
                      locale: AppL10n.of(context).l.current.code,
                    ),
                  ),
                );
              },
            ),
          );
        }
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
                // The family is written HERE, not inherited. A widget-level
                // `ButtonStyle` beats the theme property by property, and the
                // label's `AnimatedDefaultTextStyle` replaces the inherited
                // style with this one — so U-52's theme-wide Inter never
                // reached this sentence, which painted in the platform font
                // (Roboto on Android, the system font on the web) while every
                // other button on the screen was Inter. Divergence (1) from
                // the guideline — our family instead of Google Sans Medium,
                // at the guideline's own 14/20 — only holds if it is spelled
                // out at the call site (U-53).
                textStyle: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: GoogleBrand.fontSize,
                    fontWeight: FontWeight.w500,
                    height: GoogleBrand.lineHeight / GoogleBrand.fontSize),
                // The spec's 40 dp IS the button. Material's padded tap target
                // would grow the box to 48 and break the height it asks for;
                // the button is full width, so the target stays generous.
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              // The redirect could not even launch (no browser, platform
              // refusal), or the device's token was refused — the failures
              // that are OURS to report; a closed picker is not one (F-71).
              onPressed: () => _run(widget.onPressed),
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
