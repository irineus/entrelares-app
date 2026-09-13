import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import 'package:entrelares_db_contracts/models/member.dart';
import '../services/custody_data_source.dart';
import '../services/sudo_service.dart';
import '../theme/tokens.dart';
import '../widgets/app_l10n.dart';
import '../widgets/app_snack.dart';
import '../widgets/sudo_sheet.dart';
import '../widgets/ui/ui.dart';

/// `/family/delete` — the S-11 family-deletion REQUEST, on its own page (U-35).
///
/// The most destructive block of the app used to close the most-visited tab:
/// every look at the roster ended on "Excluir família…". The Família page
/// keeps one row — *Excluir família*, shown only while the reader may open a
/// request — and this page is what the row opens: the U-28 danger zone, the
/// two-step confirmation and the sudo gate, unchanged.
///
/// What does NOT move here is the PENDING request: that panel is a countdown
/// the whole family must see, and the shell banner already points at the
/// Família page — so it stays inline there. Once a request is open, this page
/// has nothing to offer and says so.
class FamilyDeleteScreen extends StatefulWidget {
  final CustodyDataSource dataSource;
  final SudoService sudo;

  /// Called once a request was opened: the roster is where the countdown
  /// lives, so the caller takes the reader back to it.
  final VoidCallback? onRequested;

  const FamilyDeleteScreen({
    super.key,
    required this.dataSource,
    required this.sudo,
    this.onRequested,
  });

  @override
  State<FamilyDeleteScreen> createState() => _FamilyDeleteScreenState();
}

class _FamilyDeleteScreenState extends State<FamilyDeleteScreen> {
  bool _loading = true;
  String? _loadErrorKey;

  /// Whether the reader may open a request HERE: an admin with company and no
  /// request already pending. A lone member deletes the family by LEAVING,
  /// which is the profile page's flow.
  bool _canRequest = false;
  bool _confirming = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadErrorKey = null;
    });
    try {
      final results = await Future.wait([
        widget.dataSource.fetchMembers(),
        widget.dataSource.fetchOwnProfile(),
        widget.dataSource.fetchPendingFamilyDeletion(),
      ]);
      final members = results[0] as List<Member>;
      final me = results[1] as Member?;
      final pending = results[2] != null;
      if (!mounted) return;
      setState(() {
        _canRequest = !pending &&
            FamilyLifecycleRules.canRequestFamilyDeletion(
                isAdmin: me?.isAdmin == true,
                activeMemberCount:
                    members.where((m) => m.isActiveMember).length);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadErrorKey = isSessionExpired(e.toString())
            ? KApp.sessionExpired
            : KApp.errCalendarLoad;
      });
    }
  }

  Future<void> _request(Localization l) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ran = await runWithSudo(
        context: context,
        sudo: widget.sudo,
        action: () async {
          await widget.dataSource.requestFamilyDeletion();
          await widget.dataSource.sendAccountEmail('family_deletion_requested');
        },
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _confirming = false;
      });
      if (!ran) return;
      showAppSnack(context, l[K.famToastDeletionRequested]);
      widget.onRequested?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppSnack(
          context, translateSaveError(e.toString(), l[K.errSaveFailed], l),
          type: AppSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final appBar = AppBar(title: Text(l[K.famDelReqTitle]));
    if (_loading) {
      return Scaffold(
        appBar: appBar,
        body: AppSkeletonCards(
            count: 1, height: 200, semanticsLabel: l[K.famLoading]),
      );
    }
    if (_loadErrorKey != null) {
      return Scaffold(
        appBar: appBar,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l[_loadErrorKey!]),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: Text(l[K.layoutErrorReload])),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: appBar,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (!_canRequest)
            AppCard(child: Text(l[KApp.famDelReqUnavailable]))
          else if (!_confirming)
            // U-28 — the family's danger zone, as [AppDangerZone]: the notices
            // inside the red frame and a filled red button. Two steps on
            // purpose: this press opens a question, the next one answers it.
            // Nothing destructive is one tap away.
            AppDangerZone(
              title: l[K.famDelReqTitle],
              intro: l[K.famDelReqIntro],
              notices: [
                for (final consequence in [
                  K.famDelReqConsequenceData,
                  K.famDelReqConsequenceNotice,
                  K.famDelReqConsequenceUnanimity,
                  K.famDelReqConsequenceWithdraw,
                ])
                  l[consequence],
              ],
              actionLabel: l[K.famDelReqOpen],
              onAction: () => setState(() => _confirming = true),
            )
          else ...[
            Text(l[K.famDelReqConfirmText]),
            const SizedBox(height: 8),
            // U-29: a destructive confirm wears the danger tone, never the
            // brand indigo — the AppDangerZone that opened this question
            // already does.
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: context.tokens.danger.solid,
                  foregroundColor: context.tokens.danger.onSolid),
              onPressed: _busy ? null : () => _request(l),
              child: Text(l[K.famDelReqConfirm]),
            ),
            TextButton(
              onPressed: () => setState(() => _confirming = false),
              child: Text(l[K.famDelReqKeep]),
            ),
          ],
        ],
      ),
    );
  }
}
