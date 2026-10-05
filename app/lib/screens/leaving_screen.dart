import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import 'package:entrelares_db_contracts/models/member.dart';
import '../services/custody_data_source.dart';
import '../services/sudo_service.dart';
import '../widgets/app_l10n.dart';
import '../widgets/app_snack.dart';
import '../widgets/sudo_sheet.dart';

/// `/leaving` — port of `Leaving.razor`.
///
/// Where a member who asked to leave lands, and the ONLY screen they can reach
/// until they either come back or sign out (the router enforces it, mirroring
/// `MainLayout.EnforceLeaving`). The confinement is the point: the account is
/// scheduled for deletion, so letting it wander the app would show a calendar
/// that is about to stop existing for them.
///
/// The 30-day window exists so the decision is reversible, and coming back is
/// deliberately as easy as one sudo-gated button.
class LeavingScreen extends StatefulWidget {
  final CustodyDataSource dataSource;
  final SudoService sudo;

  /// Signs out and returns to the login screen.
  /// F-89: "Ajuda e contato" — the exit is confined, Help is not.
  final VoidCallback? onHelp;

  final Future<void> Function() onSignOut;

  /// Called after a successful cancellation — the member is staying, so the
  /// app reopens.
  final VoidCallback onReturned;

  const LeavingScreen({
    super.key,
    required this.dataSource,
    required this.sudo,
    required this.onSignOut,
    this.onHelp,
    required this.onReturned,
  });

  @override
  State<LeavingScreen> createState() => _LeavingScreenState();
}

class _LeavingScreenState extends State<LeavingScreen> {
  bool _loading = true;
  bool _busy = false;

  /// F-89: the load failed (weak signal) — a way to retry, never a spinner
  /// with no exit on a screen the router confines the person to.
  bool _loadFailed = false;
  Member? _me;

  /// True when nobody live stays behind — leaving takes the whole family with
  /// it, and the copy has to say that instead of "your account".
  bool _isFamilyRemoval = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    final List<Object?> results;
    try {
      results = await Future.wait<Object?>([
        widget.dataSource.fetchOwnProfile(),
        widget.dataSource.fetchMembers(),
      ]);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
      return;
    }
    if (!mounted) return;
    final me = results[0] as Member?;
    final members = results[1] as List<Member>;
    setState(() {
      _me = me;
      _isFamilyRemoval = me != null &&
          FamilyLifecycleRules.isFamilyRemoval(myId: me.id, members: [
            for (final m in members)
              (id: m.id, isActiveMember: m.isActiveMember, isViewer: m.isViewer)
          ]);
      _loading = false;
    });
  }

  Future<void> _cancel(Localization l) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ran = await runWithSudo(
        context: context,
        sudo: widget.sudo,
        action: widget.dataSource.cancelAccountDeletion,
      );
      if (!mounted || !ran) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      // Best-effort, exactly as the web: the return already happened.
      await widget.dataSource
          .sendAccountEmail('member_returned', profileId: _me?.id);
      if (!mounted) return;
      showAppSnack(context, l[K.leaveToastCancelled]);
      widget.onReturned();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      // "A família já preencheu a vaga" lives here — the server's sentence
      // says which door closed, and no generic message could.
      showAppSnack(context, translateSaveError(e.toString(), l[K.errSaveFailed], l),
          type: AppSnackType.error);
    }
  }

  /// The web's `DeletionDateText`: the real deadline once the server stamped
  /// it, and the generic "30 dias" only while it has not.
  String _deadlineText(Localization l) {
    final scheduled = _me?.deletionScheduledFor;
    return scheduled == null
        ? l[K.leaveIn30Days]
        : l.formatDate(scheduled.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final me = _me;

    return Scaffold(
      appBar: AppBar(title: Text(l[K.leavePageTitle])),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_loadFailed)
                  _failed(l)
                else if (me == null || me.leftAt == null)
                  _nothingPending(l)
                else
                  _pending(l),
                // F-89: the two doors out of a confined screen, in every
                // state — signing out (also while loading) and Help.
                if (_loading || _loadFailed) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => widget.onSignOut(),
                    child: Text(l[K.leaveSignOut]),
                  ),
                ],
                if (widget.onHelp != null)
                  TextButton(
                    key: const ValueKey('leaving-help'),
                    onPressed: widget.onHelp,
                    child: Text(l[KApp.helpLoginLink]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _failed(Localization l) => Column(
        key: const ValueKey('leaving-load-failed'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l[KApp.leavingLoadFailed], textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _load,
            child: Text(l[K.layoutErrorReload]),
          ),
        ],
      );

  /// Reached by a stale link or a cancellation on another device — not an
  /// error, just nothing to do here.
  Widget _nothingPending(Localization l) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l[K.leaveNonePending], textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: widget.onReturned,
            child: Text(l[K.leaveBackToApp]),
          ),
        ],
      );

  Widget _pending(Localization l) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              _isFamilyRemoval
                  ? l[K.leaveFamilyRemovalTitle]
                  : l[K.leaveTitle],
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text(
              l.format(
                  _isFamilyRemoval
                      ? K.leaveFamilyRemovalText
                      : K.leaveAccountText,
                  [_deadlineText(l)]),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(l[K.leaveChangedMind], textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : () => _cancel(l),
            child: Text(l[K.leaveCancelAndReturn]),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => widget.onSignOut(),
            child: Text(l[K.leaveSignOut]),
          ),
        ],
      );
}
