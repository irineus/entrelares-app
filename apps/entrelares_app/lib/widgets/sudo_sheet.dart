import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'ui/ui.dart';

import '../services/sudo_service.dart';
import 'app_l10n.dart';

/// S-10 — the 🔐 re-entry sheet, port of `SudoPrompt.razor`, with the S-21
/// second proof beside the first.
///
/// Returns true when the window is now open, false when the user backed out.
/// The web splits chrome and content across two files for a CSS-isolation
/// reason that does not exist here, so this is one widget; the Escape/back
/// dismissal the web only wired on the Profile page works on every caller.
Future<bool> showSudoSheet({
  required BuildContext context,
  required SudoService sudo,
}) async {
  final granted = await showAppSheet<bool>(
    context: context,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _SudoSheet(sudo: sudo),
    ),
  );
  return granted ?? false;
}

/// The two-layer S-10 gate, in one call: ask BEFORE acting when the client
/// knows it is not elevated, and ask AGAIN when the action itself comes back
/// with the `ELEVATION_REQUIRED:` marker.
///
/// The second layer is what makes this correct rather than merely optimistic —
/// the window can expire between the check and the RPC, and a device with a
/// drifted clock never gets the first layer right at all.
///
/// [action] must surface the server's error by throwing it. Returns true when
/// the action ran to completion; false when the user dismissed the prompt.
/// Any non-elevation failure is rethrown for the caller to translate.
Future<bool> runWithSudo({
  required BuildContext context,
  required SudoService sudo,
  required Future<void> Function() action,
}) async {
  if (!sudo.isElevated) {
    if (!await showSudoSheet(context: context, sudo: sudo)) return false;
  }

  try {
    await action();
    return true;
  } catch (error) {
    if (!SudoRules.isElevationRequired(error)) rethrow;
    // The server disagreed with our optimism — prompt and retry ONCE.
    if (!context.mounted) return false;
    if (!await showSudoSheet(context: context, sudo: sudo)) return false;
    await action();
    return true;
  }
}

class _SudoSheet extends StatefulWidget {
  final SudoService sudo;

  const _SudoSheet({required this.sudo});

  @override
  State<_SudoSheet> createState() => _SudoSheetState();
}

/// Which proof the sheet is asking for right now.
///
/// S-21: BOTH are offered to every session, and the sheet never tries to guess
/// which one applies. It cannot: the only client-side signal is the identity
/// providers on the token, and production carries an account whose providers
/// are `google` alone and which nonetheless HAS a password. The server is the
/// only side that knows, and it accepts either — so the honest prompt shows the
/// password field with a way across, rather than a branch built on a proxy.
enum _Proof { password, code }

class _SudoSheetState extends State<_SudoSheet> {
  final _controller = TextEditingController();
  final _codeController = TextEditingController();
  bool _obscured = true;
  bool _busy = false;
  bool _sendingCode = false;
  String? _error;
  String? _note;
  _Proof _proof = _Proof.password;

  @override
  void dispose() {
    _controller.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _confirm(Localization l) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final message = _proof == _Proof.password
        ? await widget.sudo.elevate(_controller.text, l)
        : await widget.sudo.elevateWithCode(_codeController.text, l);
    if (!mounted) return;
    // The proof never survives an attempt — right or wrong (web parity). It
    // holds for the code too: a wrong one is spent, and the server has already
    // counted it.
    _controller.clear();
    _codeController.clear();
    if (message == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  Future<void> _sendCode(Localization l) async {
    if (_sendingCode) return;
    setState(() {
      _sendingCode = true;
      _error = null;
      _note = null;
    });
    final result = await widget.sudo.requestCode(l);
    if (!mounted) return;
    setState(() {
      _sendingCode = false;
      if (result.codeReady) {
        _proof = _Proof.code;
        _controller.clear();
        _note = result.message;
      } else {
        _error = result.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final cooling = widget.sudo.isCoolingDown;
    final onCode = _proof == _Proof.code;
    final canSubmit = !_busy &&
        !_sendingCode &&
        (onCode
            // The shape check is the keyboard's, never a verdict: it only stops
            // the sheet spending a round-trip on four characters.
            ? SudoRules.isCodeShaped(_codeController.text)
            // The password cooldown is the password's alone — it must not
            // disable a code the server is perfectly willing to judge.
            : !cooling && _controller.text.isNotEmpty);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l[K.sudoTitle],
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(l[K.sudoHint],
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            if (onCode) ..._codeFace(l) else ..._passwordFace(l),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      _busy ? null : () => Navigator.of(context).pop(false),
                  child: Text(l[K.commonCancel]),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: canSubmit ? () => _confirm(l) : null,
                  child: Text(l[K.sudoConfirm]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _passwordFace(Localization l) => [
        AppTextField(
          label: l[K.sudoCurrentPassword],
          controller: _controller,
          autofocus: true,
          obscureText: _obscured,
          enabled: !_busy && !widget.sudo.isCoolingDown,
          errorText: _error,
          suffixIcon: IconButton(
            tooltip:
                l[_obscured ? K.commonShowPassword : K.commonHidePassword],
            icon: Icon(_obscured ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscured = !_obscured),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _confirm(l),
        ),
        const SizedBox(height: 12),
        // The way across. Before S-21 this was the same sentence as a dead end:
        // it pointed at a password-reset card that a Google session does not
        // even see.
        Text(l[K.sudoForgot], style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _sendingCode ? null : () => _sendCode(l),
          icon: const Icon(Icons.mail_outline),
          label: Text(
              _sendingCode ? l[KApp.sudoSendingCode] : l[KApp.sudoSendCode]),
        ),
      ];

  List<Widget> _codeFace(Localization l) {
    final email = widget.sudo.accountEmail ?? '';
    final minutes = widget.sudo.codeMinutes ?? SudoRules.codeTtl.inMinutes;
    return [
      Text(l.format(KApp.sudoCodeSentTo, [email, '$minutes']),
          style: Theme.of(context).textTheme.bodySmall),
      if (_note != null) ...[
        const SizedBox(height: 8),
        Text(_note!, style: Theme.of(context).textTheme.bodySmall),
      ],
      const SizedBox(height: 12),
      AppTextField(
        label: l[KApp.sudoCodeLabel],
        controller: _codeController,
        autofocus: true,
        enabled: !_busy,
        errorText: _error,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _confirm(l),
      ),
      const SizedBox(height: 12),
      // The way back, for someone who pressed the button and then remembered
      // their password. Never a dead end in either direction.
      TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                  _proof = _Proof.password;
                  _codeController.clear();
                  _error = null;
                  _note = null;
                }),
        child: Text(l[KApp.sudoUsePassword]),
      ),
    ];
  }
}
