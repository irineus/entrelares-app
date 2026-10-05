import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import '../services/auth_failed.dart';
import 'app_l10n.dart';

/// F-87 — "Reenviar e-mail de confirmação", on the login (when GoTrue answers
/// `email_not_confirmed`) and on the sign-up's last screen. A founder who
/// missed the e-mail, or found it in spam days later, used to have no way to
/// ask for it again. After a send the button rests for [cooldown] — GoTrue
/// limits sends per address, and a second tap a second later only spends it.
class ResendConfirmationButton extends StatefulWidget {
  final String email;
  final Future<void> Function(String email) onResend;
  final Duration cooldown;

  const ResendConfirmationButton({
    super.key,
    required this.email,
    required this.onResend,
    this.cooldown = const Duration(seconds: 60),
  });

  @override
  State<ResendConfirmationButton> createState() =>
      _ResendConfirmationButtonState();
}

class _ResendConfirmationButtonState extends State<ResendConfirmationButton> {
  bool _busy = false;
  int _waitSeconds = 0;
  String? _messageKey;
  bool _failed = false;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _send() async {
    final email = widget.email.trim();
    if (_busy || _waitSeconds > 0 || email.isEmpty) return;
    setState(() {
      _busy = true;
      _messageKey = null;
    });
    try {
      await widget.onResend(email);
      if (!mounted) return;
      setState(() {
        _failed = false;
        _messageKey = KApp.authResendSent;
      });
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      final kind = AuthFailed.of(e);
      setState(() {
        _failed = true;
        _messageKey = switch (kind) {
          AuthFailure.rateLimited => K.authErrRateLimited,
          AuthFailure.network => K.authErrConnection,
          _ => K.authErrGeneric,
        };
      });
      if (kind == AuthFailure.rateLimited) _startCooldown();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCooldown() {
    _ticker?.cancel();
    setState(() => _waitSeconds = widget.cooldown.inSeconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _waitSeconds--);
      if (_waitSeconds <= 0) t.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          key: const ValueKey('auth-resend-confirmation'),
          onPressed: _busy || _waitSeconds > 0 ? null : _send,
          child: Text(_waitSeconds > 0
              ? l.format(KApp.authResendWait, [_waitSeconds])
              : l[KApp.authResendConfirmation]),
        ),
        if (_messageKey != null) ...[
          const SizedBox(height: 8),
          Text(l[_messageKey!],
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _failed
                      ? theme.colorScheme.error
                      : theme.textTheme.bodySmall?.color)),
        ],
      ],
    );
  }
}
