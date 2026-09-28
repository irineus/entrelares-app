import 'package:entrelares_core/entrelares_core.dart';

/// Native half: there is no second channel to hand anyone over to. A reader
/// holding the app IS the app — the question only exists in a browser, so the
/// answer here is "no answer", which offers no crossing and invites nobody.
Future<StoreAppPresence> storeAppPresence(String androidPackage) async =>
    StoreAppPresence.unknown;
