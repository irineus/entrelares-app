import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';

import '../widgets/app_l10n.dart';

/// "Esqueci minha senha" — the port of ResetPassword.razor. Sends the
/// recovery e-mail whose link is the lote-1 deep link (`/update-password`).
/// The sent view is deliberately non-committal about the account existing,
/// same as the web.
class ResetPasswordScreen extends StatefulWidget {
  /// Throws on failure; the screen shows the catalog error.
  final Future<void> Function(String email) onSendReset;
  final VoidCallback onBackToLogin;

  const ResetPasswordScreen(
      {super.key, required this.onSendReset, required this.onBackToLogin});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  bool _failed = false;

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (_busy || email.isEmpty) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.onSendReset(email);
      if (mounted) setState(() => _sent = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_sent) ...[
                  Text(l[K.resetSentTitle],
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Text(l[K.resetSentBody],
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall),
                ] else ...[
                  Text(l[K.resetTitle],
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(l[K.resetSubtitle],
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 24),
                  AppTextField(
                    label: l[K.commonEmail],
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(l[K.resetSubmit]),
                  ),
                  if (_failed) ...[
                    const SizedBox(height: 12),
                    Text(l[K.authErrResetSend],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                ],
                const SizedBox(height: 16),
                TextButton(
                  onPressed: widget.onBackToLogin,
                  child: Text(l[K.resetBackToLogin]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
