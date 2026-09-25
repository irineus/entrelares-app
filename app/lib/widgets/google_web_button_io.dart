import 'package:flutter/widgets.dart';

/// Native: Android draws its own button (U-45/U-53); this is never shown.
Widget googleWebButton(
        {required bool dark, required double width, required String locale}) =>
    const SizedBox.shrink();
