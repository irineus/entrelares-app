import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'network_client.dart';

/// T-18 — the ONE connectivity state of the app.
///
/// Written by exactly two hands: [ConnectivityHttpClient], which sees every
/// exchange with Supabase (PostgREST, GoTrue, Edge Functions and Storage all
/// share it), and the calendar, which dates what it shows. Everyone else only
/// listens. Deriving it anywhere else — a reachability plugin, a screen's own
/// catch — would give the app two opinions about the same network, and the
/// strip would contradict the screen under it.
///
/// A [ValueNotifier] because the strip lives in the shell, which a go_router
/// builder caches (see `HomeShell.deletionBanner`): only a listenable reaches it.
/// It notifies on a CHANGE only — the snapshot compares by value, and a
/// transition that changes nothing returns the same instance — so a hundred
/// successful reads repaint nothing.
class ConnectivityStatus extends ValueNotifier<ConnectivitySnapshot> {
  ConnectivityStatus() : super(ConnectivitySnapshot.initial);

  Completer<void>? _loss;

  bool get offline => value.offline;

  void reachedServer() => value = value.reachedServer();

  void lostServer() {
    value = value.lostServer();
    final loss = _loss;
    _loss = null;
    if (loss != null && !loss.isCompleted) loss.complete();
  }

  void loadedData(DateTime at) => value = value.loadedData(at);

  void forgetData() => value = value.forgetData();

  /// Completes at the next transport failure — or now, if the app is already
  /// offline. The session gate races its token refresh against this: gotrue
  /// keeps retrying a refresh for about ten seconds before admitting there is
  /// no network, and the reader at the school door should not stare at the
  /// splash for all of them.
  Future<void> nextLoss() {
    if (value.offline) return Future.value();
    return (_loss ??= Completer<void>()).future;
  }
}

/// T-18 — every HTTP exchange with Supabase, reported to [ConnectivityStatus].
///
/// A response is evidence only when it came from OUR server
/// ([isServerResponse]); a transport error counts only when it is the transport
/// ([isNetworkFailure]). Both rules live in core. The request itself is never
/// touched and every error is rethrown as it came: this client observes, it
/// does not retry, cache or translate — the callers' error handling is exactly
/// what it was.
class ConnectivityHttpClient extends http.BaseClient {
  final ConnectivityStatus _status;
  final http.Client _inner;

  ConnectivityHttpClient(this._status, {http.Client? inner})
      : _inner = inner ?? createNetworkClient();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final http.StreamedResponse response;
    try {
      response = await _inner.send(request);
    } catch (e) {
      if (isNetworkFailure(e.toString())) _status.lostServer();
      rethrow;
    }
    if (isServerResponse(contentType: response.headers['content-type'])) {
      _status.reachedServer();
    } else {
      _status.lostServer();
    }
    return response;
  }

  @override
  void close() => _inner.close();
}
