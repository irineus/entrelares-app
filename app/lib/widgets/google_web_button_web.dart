import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as gis;

/// The GIS button. `continueWith` is GIS's own "Continuar com o Google"
/// (localized by [locale]); the outline theme on light, the black one on dark
/// — the two surfaces Google's guideline names, as U-45 draws on Android.
/// GIS caps the width at 400 px and floors it at 200.
Widget googleWebButton(
    {required bool dark, required double width, required String locale}) {
  return gis.renderButton(
    configuration: gis.GSIButtonConfiguration(
      type: gis.GSIButtonType.standard,
      theme: dark ? gis.GSIButtonTheme.filledBlack : gis.GSIButtonTheme.outline,
      size: gis.GSIButtonSize.large,
      text: gis.GSIButtonText.continueWith,
      shape: gis.GSIButtonShape.rectangular,
      logoAlignment: gis.GSIButtonLogoAlignment.center,
      minimumWidth: width.clamp(200, 400).toDouble(),
      locale: locale,
    ),
  );
}
