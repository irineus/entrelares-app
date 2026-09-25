/// S-13/S-15 — the policy version the sign-up consent refers to, and the pure
/// decision of the re-consent gate. Ported from `entrelares-app`
/// `Entrelares/Helpers/PolicyVersions.cs`; that repo was archived with the
/// Blazor client (T-56, 25/08/2026), so this is now the only copy.
///
/// A bump is not just a record: it DRIVES the gate. Bumping [current] makes
/// every profile stamped with an older version pass through [evaluate], and
/// from [enforceFrom] the app blocks until the new text is accepted.
/// MATERIAL-CHANGE CHECKLIST, all in the same delivery — it still spans two
/// repos, but the second one is now `entrelares-site`, which holds the ONLY
/// copy of the legal TEXT: the app has no `/privacy` route of its own and links
/// straight to the landing (see `deep_link_urls.dart`).
///   0. the text itself, in `entrelares-site/public/{privacidade,termos}.html`;
///   1. [current];
///   2. [enforceFrom] = publication date + 15 days — and "publication" there is
///      the landing's `preview`→`main` promotion, which is deploy-on-demand in
///      that repo, never the merge that only reaches `preview`;
///   3. the `policy.current_version` / `policy.enforce_from` rows in
///      `app_settings` (migration) — the RPC validates against them and REFUSES
///      an accept whose version does not match, so a forgotten migration is a
///      loud failure, never a silent unconsented change;
///   4. an entry in [changeSummary] AND [changeSummaryEn], shown on the
///      acceptance screen.
library;

import 'date_math.dart';

/// S-15/B-4: what the re-consent gate decided for a profile.
enum ConsentGateState {
  /// The profile already accepted the current version — nothing to do.
  upToDate,

  /// Behind the current version, but still inside the notice window: warn,
  /// never block (legal review B-4: "aviso de 15 dias").
  notice,

  /// Behind the current version and the notice window has elapsed: the hard
  /// lock applies.
  blocked,
}

abstract final class PolicyVersions {
  /// The version the shipped policy/terms text corresponds to.
  static const String current = '2026-09-25';

  /// Date from which a missing accept of [current] blocks the app. Always the
  /// date the text becomes VISIBLE to users, plus 15 days — the window exists
  /// so the subject can READ the new text before losing access, so it counts
  /// from the production promotion, never from the QA merge.
  ///
  /// Do NOT shorten it afterwards: an already-published notice period is a
  /// promise. The migration `20260801200000_s15_enforce_from_promotion` carries
  /// the other half — S-22 moves it again for the phase-6 version, in
  /// `20260925100000_s22_phase6_live`.
  static const String enforceFrom = '2026-10-10';

  /// [enforceFrom] parsed once. Invalid content would be an authoring mistake,
  /// and `DateTime.parse` throws rather than defaulting to "never block" — a
  /// silent default would disable the gate exactly when it matters.
  static final DateTime enforceFromDate = DateTime.parse(enforceFrom);

  /// Plain-PT-BR summary of what changed in the current version, rendered on
  /// the acceptance screen so nobody is asked to accept a diff they cannot see
  /// (LGPD art. 9 — clear and adequate information).
  static const List<String> changeSummary = [
    'Agenda da criança: a pessoa administradora pode cadastrar a criança pelo primeiro nome, e os responsáveis registram compromissos por dia (Escola, Saúde, Remédio, Atividade, Livre, Nota ou Outro), com rotinas, avisos e lembretes. As observações dos dias passam a ser Notas da agenda. A política explica como tratamos esses dados, inclusive as informações de saúde que a família registrar.',
    'Visualizador: um novo tipo de membro, convidado para acompanhar o planejamento sem editá-lo. Ele vê o calendário, a agenda e a conversa da família, mas não vê as despesas nem as mensagens das trocas, e recebe só notificações informativas, nunca por e-mail.',
    'Despesas compartilhadas: os responsáveis podem registrar despesas da criança e pagamentos entre si, que só contam depois que quem recebeu confirma. O aplicativo não movimenta dinheiro; cada alteração ou exclusão fica guardada numa trilha que não se altera.',
    'Conversa da família: o que é enviado não pode ser editado nem apagado, todos veem quem leu cada texto e quando, e o início de cada texto vai nas notificações. A operação da plataforma não lê a conversa.',
    'Relatório verificável: o PDF pode trazer um QR code que abre uma página pública com um resumo sem nomes e a impressão digital do arquivo; guardamos só esse resumo e a impressão digital, pelo prazo de validade do relatório.',
    'A declaração de quem cria a família foi atualizada: o aplicativo passou a ter um campo para o primeiro nome da criança, e quem cria a família se compromete a inserir apenas os dados da criança necessários à rotina.',
  ];

  /// U-13 — COURTESY translation of [changeSummary], so an English reader is
  /// not asked to accept a diff in a language they cannot read. NOT a second
  /// normative text. **Entries must stay index-aligned with [changeSummary].**
  static const List<String> changeSummaryEn = [
    "The child's agenda: the family's administrator may register the child by first name, and the caregivers record appointments per day (School, Health, Medicine, Activity, Free, Note or Other), with routines, notices and reminders. The days' notes become agenda Notes. The policy explains how we handle this data, including the health information the family may record.",
    'Viewer: a new kind of member, invited to follow the plan without editing it. A viewer sees the calendar, the agenda and the family chat, but not the expenses nor the swap messages, and receives only informative notifications, never by e-mail.',
    "Shared expenses: caregivers may record the child's expenses and payments between them, which count only after the receiver confirms. The app moves no money; every change or deletion is kept in a trail that cannot be altered.",
    'Family chat: what is sent can never be edited or deleted, everyone sees who read each text and when, and the start of each text goes into the notifications. The platform operator does not read the chat.',
    'Verifiable report: the PDF may carry a QR code that opens a public page with a summary without names and the file\'s fingerprint; we keep only that summary and the fingerprint, for the report\'s validity period.',
    "The declaration of whoever creates the family was updated: the app now has a field for the child's first name, and whoever creates the family undertakes to enter only the child's data the routine needs.",
  ];

  /// The change summary in the reader's language.
  static List<String> changeSummaryFor({required bool english}) =>
      english ? changeSummaryEn : changeSummary;

  /// Pure decision of the re-consent gate. [stampedVersion] is
  /// `profiles.consent_policy_version` — NULL on legacy profiles, which this
  /// same gate captures on purpose (the S-13 migration deliberately left them
  /// NULL rather than backfilling, which would have fabricated evidence).
  ///
  /// The comparison is EXACT: no trim, no case-fold, no date parse. A stamp of
  /// " 2026-07-30" or "2026-7-30" is not the current version, and an unknown
  /// FUTURE version is not an acceptance either — both fall through to the
  /// notice/block decision.
  static ConsentGateState evaluate(String? stampedVersion, DateTime today) {
    if (stampedVersion == current) return ConsentGateState.upToDate;
    // Anything else — an older version OR the legacy null — needs the new
    // accept; the notice window decides whether it warns or blocks. The
    // boundary is strict, so the enforce date itself already BLOCKS.
    return dateOnly(today).isBefore(dateOnly(enforceFromDate))
        ? ConsentGateState.notice
        : ConsentGateState.blocked;
  }
}
