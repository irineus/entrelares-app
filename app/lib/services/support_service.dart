/// F-68 — the one call the "Ajuda e contato" screen makes:
/// `send-support-request`, signed in or not.
///
/// The Supabase client already sends the member's access token when there is a
/// session and the public key when there is none, which is exactly the split
/// the function reads — so there is nothing to choose here. Every answer comes
/// back as a [SupportResult]; nothing throws to the screen.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'install_hint.dart';

/// What the form hands over.
class SupportDraft {
  final SupportCategory category;
  final String message;

  /// Only for a signed-out person — a signed-in one is answered at the
  /// account's own address, which the function reads server-side.
  final String? replyEmail;
  final String language;
  final Map<String, String>? diagnostics;

  const SupportDraft({
    required this.category,
    required this.message,
    required this.language,
    this.replyEmail,
    this.diagnostics,
  });
}

class SupportResult {
  final SupportOutcome outcome;

  /// The number both e-mails print. Null unless [outcome] is `sent`.
  final int? requestId;

  const SupportResult(this.outcome, [this.requestId]);
}

typedef SendSupportRequest = Future<SupportResult> Function(SupportDraft draft);

class SupportService {
  SupportService(this._client);

  final SupabaseClient _client;

  Future<SupportResult> send(SupportDraft draft) async {
    try {
      final response = await _client.functions.invoke(
        'send-support-request',
        body: {
          'category': draft.category.wire,
          'message': draft.message.trim(),
          if (draft.replyEmail != null) 'replyEmail': draft.replyEmail!.trim(),
          'language': draft.language,
          'diagnostics': draft.diagnostics,
        },
      );
      final data = response.data;
      final id = data is Map ? (data['requestId'] as num?)?.toInt() : null;
      return SupportResult(SupportOutcome.sent, id);
    } on FunctionException catch (e) {
      final details = e.details;
      final error = details is Map ? details['error'] as String? : null;
      return SupportResult(SupportRules.outcomeOf(e.status, error));
    } catch (e) {
      // T-18: no signal is a state — the request never reached the server.
      return SupportResult(isNetworkFailure(e.toString())
          ? SupportOutcome.offline
          : SupportOutcome.failed);
    }
  }
}

/// The technical block for the screen the person came from, read from THIS
/// device: coarse by construction (`SupportDiagnostics`).
Map<String, String> currentSupportDiagnostics({
  required String appVersion,
  required String language,
  required String route,
}) {
  final facts = kIsWeb ? readBrowserInstallFacts() : null;
  return SupportDiagnostics.build(
    appVersion: appVersion,
    channel: SupportDiagnostics.channel(
      isWeb: kIsWeb,
      standalone: facts != null && InstallHintRules.isStandalone(facts),
    ),
    platform: SupportDiagnostics.platformLabel(
      userAgent: facts?.userAgent,
      nativeOs: kIsWeb ? null : defaultTargetPlatform.name,
    ),
    language: language,
    route: route,
  );
}
