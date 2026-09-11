/// Native half: there is no second channel to hand anyone over to. A reader
/// holding the app IS the app — the question only exists in a browser.
Future<bool> isStoreAppInstalled(String androidPackage) async => false;
