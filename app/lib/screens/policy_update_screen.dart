import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../deep_link_urls.dart';
import '../widgets/ui/ui.dart';
import '../services/custody_data_source.dart';
import '../widgets/app_l10n.dart';
import '../widgets/app_snack.dart';

/// `/policy-update` — the S-15/B-4 re-consent gate. Port of
/// `PolicyUpdate.razor`.
///
/// A PAGE and not a dismissible sheet, deliberately: past the notice window
/// this is the only screen the app offers, and a sheet invites the idea that it
/// can be waved away.
///
/// The one subtlety worth guarding: **nothing consent-related renders until
/// `joined_via_invite` is known**. The declaration differs per path (A-1.1
/// founder vs A-1.2 invitee), and guessing would stamp an acceptance for a
/// statement the person never made.
class PolicyUpdateScreen extends StatefulWidget {
  final CustodyDataSource dataSource;

  /// Called after the acceptance is recorded — the app reopens with a fresh
  /// stamp (the web's `forceLoad`).
  final VoidCallback onAccepted;

  final Future<void> Function() onSignOut;

  const PolicyUpdateScreen({
    super.key,
    required this.dataSource,
    required this.onAccepted,
    required this.onSignOut,
  });

  @override
  State<PolicyUpdateScreen> createState() => _PolicyUpdateScreenState();
}

class _PolicyUpdateScreenState extends State<PolicyUpdateScreen> {
  bool _loading = true;

  /// Null until the profile is read — see the class doc.
  bool? _joinedViaInvite;

  bool _accepted = false;
  bool _busy = false;
  String? _errorKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await widget.dataSource.fetchOwnProfile();
      if (!mounted) return;
      setState(() {
        _joinedViaInvite = me?.joinedViaInvite;
        _errorKey = me == null ? K.policyErrProfileLoad : null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorKey = K.policyErrProfileLoadRetry;
        _loading = false;
      });
    }
  }

  Future<void> _accept(Localization l) async {
    if (!_accepted || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.dataSource.acceptCurrentPolicy();
      if (!mounted) return;
      showAppSnack(context, l[K.policyToastAccepted]);
      widget.onAccepted();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      // A client behind the server fails LOUDLY here (the RPC refuses a
      // version that is not the declared one) instead of silently stamping an
      // unconsented version.
      showAppSnack(context, translateSaveError(e.toString(), l[K.errSaveFailed], l),
          type: AppSnackType.error);
    }
  }

  Future<void> _openWebPage(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final theme = Theme.of(context);
    final joined = _joinedViaInvite;

    return Scaffold(
      appBar: AppBar(title: Text(l[K.policyPageTitle])),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l[K.policyHeading],
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(l[K.policyIntro]),
                const SizedBox(height: 20),
                Text(l[K.policyWhatChanged],
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                // LGPD art. 9: nobody is asked to accept a diff they cannot
                // see, and the English reader gets the courtesy rendering.
                // U-29: AppBulletList, so a wrapping change keeps its second
                // line under the text instead of under the bullet.
                AppBulletList(
                  items: PolicyVersions.changeSummaryFor(english: l.isEnglish),
                ),
                const SizedBox(height: 12),
                Text(l[K.policyReadInFull], style: theme.textTheme.bodySmall),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => _openWebPage(DeepLinkUrls.privacy),
                      child: Text(l[K.commonPrivacyPolicy]),
                    ),
                    TextButton(
                      onPressed: () => _openWebPage(DeepLinkUrls.terms),
                      child: Text(l[K.commonTermsOfUse]),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (joined == null) ...[
                  Text(l[_errorKey ?? K.policyErrProfileLoad],
                      style: TextStyle(color: theme.colorScheme.error)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _load,
                    child: Text(l[K.layoutErrorReload]),
                  ),
                ] else ...[
                  Text(
                    // The path declaration — shared with the sign-up screen so
                    // the two can never state different things.
                    ConsentDeclarations.forPath(joined, english: l.isEnglish),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _accepted,
                        onChanged: (value) =>
                            setState(() => _accepted = value ?? false),
                      ),
                      Expanded(
                          child: Text(
                              '${l[K.registerConsentAccept]} '
                              '${l[K.commonPrivacyPolicy]} '
                              '${l[K.registerConsentAnd]} '
                              '${l[K.commonTermsOfUse]} '
                              '${l[K.policyAcceptUpdated]}')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: !_accepted || _busy ? null : () => _accept(l),
                    child: Text(_busy
                        ? l[K.policyRegistering]
                        : l[K.policyAcceptAndContinue]),
                  ),
                ],
                const SizedBox(height: 20),
                // Declining is a real option, and saying so is part of the
                // consent being free.
                Text(l[K.policyDeclinePrefix],
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall),
                TextButton(
                  onPressed: () => widget.onSignOut(),
                  child: Text(l[K.policyDeclineSignOut]),
                ),
                Text(l[K.policyDeclineSuffix],
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall),
                Text('privacidade@entrelares.app',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
