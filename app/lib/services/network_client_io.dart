import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// How long a native connect may take before it counts as "no network".
///
/// Long enough for a real handshake on a poor 3G link, short enough that the
/// reader in the lift learns the plan on screen is not current while they are
/// still looking at it.
const Duration connectTimeout = Duration(seconds: 8);

/// Native half: `dart:io` with a bounded connect (see `network_client.dart`).
http.Client createNetworkClient() =>
    IOClient(HttpClient()..connectionTimeout = connectTimeout);
