/// Native half: there is no boot script to stand down, because there is no
/// document. On Android the app IS the process — nothing runs before Dart — so
/// the two error hooks cover the whole life of the app on their own.
void markAppBooted() {}
