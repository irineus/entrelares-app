import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import '../services/custody_data_source.dart';
import '../widgets/account_button.dart';
import '../widgets/app_l10n.dart';
import 'reports_audit_tab.dart';
import 'reports_pdf_tab.dart';
import 'reports_summary_tab.dart';

/// The Relatórios hub — port of the `ReportsTabs` switcher shared by
/// `ReportsSummary.razor`, `ReportsAudit.razor` and `ReportsPdf.razor`.
///
/// **The native improvement the owner directive allows:** the web navigates
/// between three ROUTES (`reports/summary|audit|pdf`) because it has no
/// persistent tab shell; here the three views are a `TabBar` inside the
/// Relatórios destination, so switching never re-enters the shell and each
/// view keeps its own filter state while the user compares them.
class ReportsScreen extends StatelessWidget {
  final CustodyDataSource dataSource;

  const ReportsScreen({super.key, required this.dataSource});

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l[K.navReports]),
          actions: const [AppAccountButton()],
          // U-28: the tab bar joins the app's icon system. Emoji in a tab
          // label sits at a different optical weight from every other icon on
          // the screen and does not follow the selected colour — the rest of
          // the app is Material icons, so these are too. Emoji stays where the
          // catalog owns it: inside sentences the app writes.
          bottom: TabBar(
            tabs: [
              Tab(
                  icon: const Icon(Icons.summarize_outlined),
                  text: l[K.repTabSummary]),
              Tab(
                  icon: const Icon(Icons.history),
                  text: l[K.repTabHistory]),
              Tab(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  text: l[K.repTabPdf]),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ReportsSummaryTab(dataSource: dataSource),
            ReportsAuditTab(dataSource: dataSource),
            ReportsPdfTab(dataSource: dataSource),
          ],
        ),
      ),
    );
  }
}
