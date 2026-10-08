/// F-102 — a non-admin who meets a Premium gate is told WHO can subscribe and
/// may ask them, once a day (owner, 07/10/2026).
///
/// The T-103 audit (04/10/2026): every gate ended on "A assinatura é feita por
/// um administrador da família" — no name, no next step. The server still
/// refuses a non-admin's checkout (who may pay does not change, no billing
/// rail is touched); what changes is that the sentence names the admin(s) and
/// the page offers "Avisar o administrador", which writes ONE notification to
/// the family's admins ("Bruno quer o Premium para a agenda da criança"), at
/// most once per requester per day — the guard is the server's
/// (`request_premium_from_admin`), this file only mirrors the vocabulary.
library;

import 'localization/k.dart';
import 'localization/k_app.dart';

/// What a plan-page visitor is, for the sentence and the button.
typedef PremiumAskMember = ({String fullName, bool isAdmin, bool isActive});

abstract final class PremiumAskRules {
  /// The gate tokens the request may carry — the same tokens
  /// `premium-gate-click` sends (F-79), so the funnel and the ask agree on
  /// what was wanted. Anything else reads as the generic [genericGate].
  static const Set<String> gates = {
    'chat',
    'chat-export',
    'agenda',
    'expenses',
    'pdf',
  };

  /// The ask with no gate behind it — the plan page opened from the Família
  /// row, say.
  static const String genericGate = 'premium';

  /// [raw] as a gate the server knows, else [genericGate].
  static String normalizeGate(String? raw) =>
      raw != null && gates.contains(raw) ? raw : genericGate;

  /// The catalog key of what the gate guards, for "{0} quer o Premium para
  /// {1}." — a closed map, so a future gate token renders the generic words
  /// instead of a hole.
  static String gateLabelKey(String? gate) => switch (gate) {
        'chat' => K.notifRenderPremiumGateChat,
        'chat-export' => K.notifRenderPremiumGateChatExport,
        'agenda' => K.notifRenderPremiumGateAgenda,
        'expenses' => K.notifRenderPremiumGateExpenses,
        'pdf' => K.notifRenderPremiumGatePdf,
        _ => K.notifRenderPremiumGateFamily,
      };

  /// The first names of the family's live admins, in roster order. A viewer
  /// is never an admin; a departed or pending member holds no key.
  static List<String> adminFirstNames(Iterable<PremiumAskMember> members) => [
        for (final m in members)
          if (m.isAdmin && m.isActive && m.fullName.trim().isNotEmpty)
            m.fullName.trim().split(RegExp(r'\s+')).first,
      ];

  /// "Ana" / "Ana e Carla" / "Ana, Carla e Dora" — the reader's "and".
  static String? joinNames(List<String> names, {required String and}) {
    if (names.isEmpty) return null;
    if (names.length == 1) return names.single;
    return '${names.sublist(0, names.length - 1).join(', ')} $and ${names.last}';
  }

  /// The sentence under the offer for a non-admin: one admin or several.
  static String sentenceKey(int adminCount) =>
      adminCount == 1 ? KApp.premAdminNamedOne : KApp.premAdminNamedMany;

  /// The button: singular or plural.
  static String askKey(int adminCount) =>
      adminCount == 1 ? KApp.premAskAdmin : KApp.premAskAdmins;
}
