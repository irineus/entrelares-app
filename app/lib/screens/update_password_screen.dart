import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';

import '../widgets/app_l10n.dart';

/// The deep-link landing of the recovery e-mail — port of
/// UpdatePassword.razor. `supabase_flutter` swallows the link's tokens and
/// signs the visitor in BEFORE this screen shows (the passwordRecovery event
/// routes here); without that session the form refuses with the same message
/// as the web.
class UpdatePasswordScreen extends StatefulWidget {
  /// Throws on failure; the screen propagates the server's own text
  /// (pilot lesson 4 — never collapse failures).
  final Future<void> Function(String newPassword) onUpdatePassword;

  /// Whether a session (recovery or regular) exists to change the password of.
  final bool hasSession;

  /// "Ir para o calendário" on the success view.
  final VoidCallback onDone;

  const UpdatePasswordScreen(
      {super.key,
      required this.onUpdatePassword,
      required this.hasSession,
      required this.onDone});

  @override
  State<UpdatePasswordScreen> createState() => _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends State<UpdatePasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _done = false;

  /// U-29 — U-19's eye toggle; one control drives the pair, as register does.
  bool _obscured = true;

  /// Catalog key of a local validation error (mirror), or null.
  String? _errorKey;

  /// Verbatim server error text, when the update itself failed.
  String? _serverError;

  Future<void> _submit() async {
    if (_busy || !widget.hasSession) return;
    final errorKey = UpdatePasswordRules.validationErrorKey(
        _password.text, _confirm.text);
    setState(() {
      _errorKey = errorKey;
      _serverError = null;
    });
    if (errorKey != null) return;

    setState(() => _busy = true);
    try {
      await widget.onUpdatePassword(_password.text);
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _serverError = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _done
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 48, color: theme.colorScheme.primary),
                      const SizedBox(height: 16),
                      Text(l[K.updatePwdDoneTitle],
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(l[K.updatePwdDoneBody],
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: widget.onDone,
                        child: Text(l[K.updatePwdGoToCalendar]),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l[K.updatePwdTitle],
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text(l[K.updatePwdSubtitle],
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 24),
                      if (!widget.hasSession)
                        Text(l[K.updatePwdErrorSession],
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: theme.colorScheme.error))
                      else ...[
                        AppTextField(
                          label: l[K.updatePwdNewPassword],
                          controller: _password,
                          obscureText: _obscured,
                          autofillHints: const [AutofillHints.newPassword],
                          suffixIcon: IconButton(
                            tooltip: l[_obscured
                                ? K.commonShowPassword
                                : K.commonHidePassword],
                            icon: Icon(_obscured
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () =>
                                setState(() => _obscured = !_obscured),
                          ),
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: l[K.commonConfirmPassword],
                          controller: _confirm,
                          obscureText: _obscured,
                          autofillHints: const [AutofillHints.newPassword],
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : Text(l[K.updatePwdSubmit]),
                        ),
                        if (_errorKey != null || _serverError != null) ...[
                          const SizedBox(height: 12),
                          Text(
                              _errorKey != null
                                  ? l[_errorKey!]
                                  : _serverError!,
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: theme.colorScheme.error)),
                        ],
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
