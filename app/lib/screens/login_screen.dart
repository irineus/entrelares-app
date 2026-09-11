import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../deep_link_urls.dart';
import '../env.dart';
import '../theme/tokens.dart';
import '../widgets/app_l10n.dart';
import '../widgets/app_splash.dart';
import '../widgets/google_sign_in_button.dart';

/// Why the visitor was sent back here, so the banner reads the right message
/// (the web's `session_expired` sessionStorage flag).
enum SessionExpiredReason { none, restored, inactivity }

/// What a `signedOut` auth event means for the login screen's banner — the
/// decision that told people "sua sessão anterior expirou" when all they had
/// done was press Sair.
///
/// It lives next to the enum, and as a pure function, because the bug was NOT
/// in the branch: it was that the branch ran from an event whose arrival order
/// nobody controls. Pure, it can be asserted for all four combinations without
/// a Supabase client; wired, `main.dart` only has to pass the flag.
SessionExpiredReason reasonForSignedOut({
  required bool userInitiated,
  required SessionExpiredReason current,
  required bool wasAuthed,
}) =>
    !userInitiated && current == SessionExpiredReason.none && wasAuthed
        ? SessionExpiredReason.restored
        : current;

class LoginScreen extends StatefulWidget {
  /// Throws on failure; the screen translates the error for display.
  final Future<void> Function(String email, String password) onSignIn;

  final SessionExpiredReason expiredReason;

  final VoidCallback onForgotPassword;

  /// Opens `/register` — live since lote 4.
  final VoidCallback onSignUp;

  /// S-01 throttle state store — the web keeps it in sessionStorage; local
  /// prefs here so a process restart does not reset the clock.
  final SharedPreferences prefs;

  /// F-57 — whether the Google provider exists (GoTrue's settings endpoint,
  /// fail-closed) and what pressing the button does. Null keeps the screen
  /// exactly as it was before F-57 — tests and callers that predate the
  /// feature never see the button.
  final Future<bool>? googleEnabled;
  final Future<void> Function()? onSignInWithGoogle;

  const LoginScreen(
      {super.key,
      required this.onSignIn,
      required this.onForgotPassword,
      required this.onSignUp,
      required this.prefs,
      this.googleEnabled,
      this.onSignInWithGoogle,
      this.expiredReason = SessionExpiredReason.none});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  /// Same store names as the web's sessionStorage keys.
  static const _failsKey = 'login_fails';
  static const _lockoutUntilKey = 'login_lockout_until';

  final _email = TextEditingController();
  final _password = TextEditingController();

  /// The catalog KEY of the current error, so a language switch re-renders it.
  String? _errorKey;
  bool _busy = false;

  /// U-29 — U-19's eye toggle, which the port kept on register and sudo but
  /// dropped here, on the field people type a password into most often.
  bool _obscured = true;

  // S-01 — progressive throttling (mirror in LoginThrottle).
  int _failedAttempts = 0;
  int _lockoutSecondsLeft = 0;
  Timer? _lockoutTicker;

  bool get _lockedOut => _lockoutSecondsLeft > 0;

  @override
  void initState() {
    super.initState();
    _failedAttempts = widget.prefs.getInt(_failsKey) ?? 0;
    final untilSeconds = widget.prefs.getInt(_lockoutUntilKey);
    if (untilSeconds != null) {
      final remaining = LoginThrottle.remainingSeconds(
          DateTime.fromMillisecondsSinceEpoch(untilSeconds * 1000, isUtc: true),
          DateTime.now().toUtc());
      if (remaining > 0) _startLockout(remaining, persist: false);
    }
  }

  @override
  void dispose() {
    _lockoutTicker?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _lockedOut) return;
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      await widget.onSignIn(_email.text.trim(), _password.text);
      // Success routes away from this screen (auth listener in main).
      await widget.prefs.remove(_failsKey);
      await widget.prefs.remove(_lockoutUntilKey);
    } catch (e) {
      final raw = e.toString();
      _failedAttempts++;
      await widget.prefs.setInt(_failsKey, _failedAttempts);
      final lockout = LoginThrottle.lockoutSecondsFor(_failedAttempts);
      if (lockout > 0) _startLockout(lockout);
      if (mounted) {
        setState(() {
          _errorKey = raw.contains('Invalid login credentials')
              ? K.authErrInvalidCredentials
              : K.authErrConnection;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startLockout(int seconds, {bool persist = true}) {
    if (persist) {
      final until = DateTime.now().toUtc().add(Duration(seconds: seconds));
      widget.prefs
          .setInt(_lockoutUntilKey, until.millisecondsSinceEpoch ~/ 1000);
    }
    _lockoutTicker?.cancel();
    setState(() => _lockoutSecondsLeft = seconds);
    _lockoutTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _lockoutSecondsLeft--);
      if (_lockoutSecondsLeft <= 0) timer.cancel();
    });
  }

  /// A legal link, sized to its text: the default `TextButton` padding is what
  /// made the pair too wide for one line.
  Widget _legalLink(String label, VoidCallback onTap) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      );

  Future<void> _openWebPage(String url) async {
    // Legal pages live on the web until lote 4 ports them.
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final expiredText = switch (widget.expiredReason) {
      SessionExpiredReason.none => null,
      SessionExpiredReason.restored => l[KApp.sessionRestoredExpired],
      SessionExpiredReason.inactivity => l[K.loginExpiredInactivity],
    };
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
                // U-28: the mark the web puts above the name. Without it the
                // screen opened on two lines of text over an empty page — the
                // one screen every user meets first had no identity on it.
                const Center(child: AppBrandMark()),
                const SizedBox(height: Spacing.md),
                Text(l[K.loginHeading],
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(l[K.loginSubtitle],
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 24),
                if (expiredText != null) ...[
                  Text(expiredText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 12),
                ],
                AppTextField(
                  label: l[K.commonEmail],
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: l[K.commonPassword],
                  controller: _password,
                  obscureText: _obscured,
                  autofillHints: const [AutofillHints.password],
                  suffixIcon: IconButton(
                    tooltip: l[_obscured
                        ? K.commonShowPassword
                        : K.commonHidePassword],
                    icon: Icon(
                        _obscured ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscured = !_obscured),
                  ),
                  onSubmitted: (_) => _busy || _lockedOut ? null : _submit(),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy || _lockedOut ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_lockedOut
                          ? l.format(K.loginLockout, [_lockoutSecondsLeft])
                          : l[K.loginSubmit]),
                ),
                if (_errorKey != null) ...[
                  const SizedBox(height: 12),
                  Text(l[_errorKey!],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: widget.onForgotPassword,
                  child: Text(l[K.loginForgot]),
                ),
                // F-57: below the password flow, above the U-28 rule — still
                // "signing in", just another door. Renders nothing while the
                // provider is not enabled on this environment's project.
                if (widget.googleEnabled != null &&
                    widget.onSignInWithGoogle != null)
                  GoogleSignInButton(
                    enabled: widget.googleEnabled!,
                    onPressed: widget.onSignInWithGoogle!,
                  ),
                // U-28: the rule the web draws here. Everything above it is
                // signing in; everything below is about the app. Without it the
                // screen was one undifferentiated stack of links.
                const Divider(height: Spacing.lg),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(l[K.loginSignupCta],
                        style: Theme.of(context).textTheme.bodySmall),
                    TextButton(
                      onPressed: widget.onSignUp,
                      child: Text(l[K.loginSignupLink]),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // U-28: ONE line, always. As a `Wrap` of two default-padded
                // `TextButton`s the pair broke in two on a phone and left the
                // screen tall and strewn; `FittedBox` gives up a couple of
                // percent of type size on the narrowest screens instead.
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _legalLink(l[K.commonPrivacyPolicy],
                            () => _openWebPage(DeepLinkUrls.privacy)),
                        Text('·', style: Theme.of(context).textTheme.bodySmall),
                        _legalLink(l[K.commonTermsOfUse],
                            () => _openWebPage(DeepLinkUrls.terms)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // U-13: the picker must exist BEFORE a session does — the
                // recruited tester meets this screen first.
                const LanguagePickerRow(),
                const SizedBox(height: Spacing.md),
                // U-28: the version the web prints in its own footer. It is the
                // first thing a tester is asked for when they report something.
                Text(Env.appVersion,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: context.tokens.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
