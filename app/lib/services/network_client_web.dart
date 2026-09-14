import 'package:http/http.dart' as http;

/// Web half: the browser's own client, which bounds a dead connect by itself.
http.Client createNetworkClient() => http.Client();
