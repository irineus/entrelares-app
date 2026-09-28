import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import '../screens/reports_pdf_tab.dart';
import '../services/custody_data_source.dart';
import '../theme/tokens.dart';
import 'app_l10n.dart';
import 'ui/ui.dart';

/// U-59 — *Exportar conversa*: the Conversa's door to the EXISTING PDF
/// report (F-33/F-64). No new PDF code — the sheet hosts [ReportsPdfTab]
/// pre-filled with the last [ChatExportRules.days] days and the Conversa's
/// switch on, and everything stays editable there.
///
/// A family without Premium gets the gate instead: an [AppBanner] whose CTA
/// opens `/family/plan` (U-35/U-49). The QR sentence is said only where the
/// PDF can carry one ([ChatExportRules.saysQr]) — never to a viewer.
Future<void> showChatExportSheet(
  BuildContext context, {
  required CustodyDataSource dataSource,
  required bool premium,
  required bool viewer,
  required bool attestationEnabled,
  required DateTime Function() now,
  VoidCallback? onOpenPlan,
}) =>
    showAppSheet<void>(
      context: context,
      builder: (context) => ChatExportSheet(
        dataSource: dataSource,
        premium: premium,
        viewer: viewer,
        attestationEnabled: attestationEnabled,
        now: now,
        onOpenPlan: onOpenPlan,
      ),
    );

class ChatExportSheet extends StatelessWidget {
  final CustodyDataSource dataSource;
  final bool premium;
  final bool viewer;
  final bool attestationEnabled;
  final DateTime Function() now;
  final VoidCallback? onOpenPlan;

  const ChatExportSheet({
    super.key,
    required this.dataSource,
    required this.premium,
    required this.viewer,
    required this.attestationEnabled,
    required this.now,
    this.onOpenPlan,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final openPlan = onOpenPlan;
    return AppSheetFrame(
      title: l[KApp.chatExportTitle],
      subtitle: premium
          ? l.format(KApp.chatExportLead, [ChatExportRules.days])
          : null,
      children: [
        if (!premium)
          AppBanner(
            key: const ValueKey('chat-export-premium'),
            tone: tokens.info,
            icon: Icons.workspace_premium_outlined,
            message: l[KApp.chatExportPremium],
            actionLabel: openPlan == null ? null : l[K.famSeePremium],
            onAction: openPlan == null
                ? null
                : () {
                    dataSource.analytics?.trackEvent(
                        AnalyticsEvents.premiumGateClick,
                        props: {'gate': 'chat-export'});
                    Navigator.of(context).pop();
                    openPlan();
                  },
          )
        else ...[
          if (ChatExportRules.saysQr(
              viewer: viewer, attestationEnabled: attestationEnabled)) ...[
            Row(
              key: const ValueKey('chat-export-qr'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.qr_code_2, size: 20, color: tokens.info.solid),
                const SizedBox(width: Spacing.sm),
                Expanded(
                    child: Text(l[KApp.chatExportQr],
                        style: textTheme.bodyMedium)),
              ],
            ),
            const SizedBox(height: Spacing.md),
          ],
          ReportsPdfTab(
            dataSource: dataSource,
            now: now,
            initialPeriod: ChatExportRules.initialPeriod(now()),
            initialIncludeChat: true,
            analyticsSource: 'chat',
            embedded: true,
          ),
        ],
      ],
    );
  }
}
