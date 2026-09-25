/// U-21 — the profile page is READ at rest and EDITED in a sheet.
///
/// Every editable field used to sit open on the page (name, role, new e-mail,
/// new password twice), which read as a giant form to someone who only came
/// to look. The page now shows summary cards with a pencil per group, and the
/// pencil opens one of these — the bottom-sheet pattern the app already
/// settled on for the day editor and the sudo prompt (decision Aug/2026,
/// chosen over sub-pages and inline toggles).
///
/// What the sheets do NOT own: the gated call. Each takes a callback the page
/// supplies, and the page runs it through `runWithSudo` where S-10 demands.
/// So the sudo prompt opens ON TOP of the edit sheet — a dismissed prompt
/// hands the reader back their half-typed sheet instead of throwing it away.
/// A callback returns `true` when the action ran, `false` when the reader
/// backed out of the prompt (the sheet stays open, not busy), and THROWS on a
/// server refusal (the sheet shows the sentence and stays open).
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import 'package:entrelares_db_contracts/models/role.dart';
import '../theme/tokens.dart';
import 'app_l10n.dart';
import 'ui/ui.dart';

/// Opens the Dados editor: the name, plus the role when [canEditRole] (an
/// admin's power, for anyone including themselves). Resolves `true` when
/// [onSave] ran to completion; null when dismissed.
Future<bool?> showProfileDataSheet({
  required BuildContext context,
  required String initialName,
  required int? initialRoleId,
  required List<Role> roles,
  required bool canEditRole,
  required Future<void> Function(String name, int? roleId) onSave,
}) =>
    showAppSheet<bool>(
      context: context,
      builder: (_) => _ProfileDataSheet(
        initialName: initialName,
        initialRoleId: initialRoleId,
        roles: roles,
        canEditRole: canEditRole,
        onSave: onSave,
      ),
    );

/// Opens the e-mail editor. [onSubmit] receives the candidate address and
/// returns whether the change request went through; the page then says
/// "link sent", because GoTrue only APPLIES it once the link is clicked.
Future<bool?> showProfileEmailSheet({
  required BuildContext context,
  required String currentEmail,
  required Future<bool> Function(String candidate) onSubmit,
}) =>
    showAppSheet<bool>(
      context: context,
      builder: (_) => _ProfileEmailSheet(
        currentEmail: currentEmail,
        onSubmit: onSubmit,
      ),
    );

/// What the password sheet closed with.
enum ProfilePasswordOutcome {
  /// [onChange] ran to completion.
  changed,

  /// The reader took the way out for a forgotten password: [onReset] ran.
  resetSent,
}

/// Opens the password editor. [onChange] receives the validated new password;
/// [onReset] is the "esqueci a senha atual" door, which needs no elevation
/// (the mailbox is the proof) and lives here so the page keeps one line.
Future<ProfilePasswordOutcome?> showProfilePasswordSheet({
  required BuildContext context,
  required Future<bool> Function(String newPassword) onChange,
  required Future<void> Function() onReset,
}) =>
    showAppSheet<ProfilePasswordOutcome>(
      context: context,
      builder: (_) => _ProfilePasswordSheet(
        onChange: onChange,
        onReset: onReset,
      ),
    );

class _ProfileDataSheet extends StatefulWidget {
  final String initialName;
  final int? initialRoleId;
  final List<Role> roles;
  final bool canEditRole;
  final Future<void> Function(String name, int? roleId) onSave;

  const _ProfileDataSheet({
    required this.initialName,
    required this.initialRoleId,
    required this.roles,
    required this.canEditRole,
    required this.onSave,
  });

  @override
  State<_ProfileDataSheet> createState() => _ProfileDataSheetState();
}

class _ProfileDataSheetState extends State<_ProfileDataSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);
  late int? _roleId = widget.initialRoleId;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save(Localization l) async {
    if (_busy) return;
    final clean = _name.text.trim();
    if (clean.length < 2) {
      setState(() => _error = l[KApp.profErrNameTooShort]);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(clean, widget.canEditRole ? _roleId : null);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = translateSaveError(e.toString(), l[K.errSaveFailed], l);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return AppSheetFrame(
      title: l[K.profSectionData],
      busy: _busy,
      primaryLabel: l[K.profSaveData],
      onPrimary: () => _save(l),
      secondaryLabel: l[K.commonCancel],
      onSecondary: () => Navigator.of(context).pop(),
      children: [
        AppTextField(
          label: l[K.registerFullName],
          controller: _name,
          maxLength: RegisterRules.maxNameLength,
          errorText: _error,
          autofocus: true,
          textInputAction:
              widget.canEditRole ? TextInputAction.next : TextInputAction.done,
          onSubmitted: widget.canEditRole ? null : (_) => _save(l),
        ),
        if (widget.canEditRole) ...[
          const SizedBox(height: Spacing.sm),
          DropdownButtonFormField<int>(
            // A name or label never pushes the field past the screen
            // (owner's validation, 25/09/2026: "Quem pagou" overflowed).
            isExpanded: true,
            initialValue: _roleId,
            decoration: InputDecoration(labelText: l[K.famRoleInFamily]),
            items: [
              for (final role in widget.roles)
                DropdownMenuItem(
                  value: role.id,
                  child: Text(role.displayLabel(l.current)),
                ),
            ],
            onChanged: _busy ? null : (value) => setState(() => _roleId = value),
          ),
        ],
      ],
    );
  }
}

class _ProfileEmailSheet extends StatefulWidget {
  final String currentEmail;
  final Future<bool> Function(String candidate) onSubmit;

  const _ProfileEmailSheet({
    required this.currentEmail,
    required this.onSubmit,
  });

  @override
  State<_ProfileEmailSheet> createState() => _ProfileEmailSheetState();
}

class _ProfileEmailSheetState extends State<_ProfileEmailSheet> {
  final _email = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit(Localization l) async {
    if (_busy) return;
    final candidate = _email.text.trim();
    // The two refusals the page always made BEFORE asking for the password:
    // a prompt for an address that cannot be accepted is a wasted proof.
    if (!candidate.contains('@')) {
      setState(() => _error = l[K.profErrInvalidEmail]);
      return;
    }
    if (candidate.toLowerCase() == widget.currentEmail.toLowerCase()) {
      setState(() => _error = l[K.profErrSameEmail]);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ran = await widget.onSubmit(candidate);
      if (!mounted) return;
      if (ran) {
        Navigator.of(context).pop(true);
        return;
      }
      // Backed out of the prompt: the draft survives, nothing was sent.
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final theme = Theme.of(context).textTheme;
    return AppSheetFrame(
      title: l[K.profSectionEmail],
      busy: _busy,
      primaryLabel: l[K.profChangeEmail],
      onPrimary: () => _submit(l),
      secondaryLabel: l[K.commonCancel],
      onSecondary: () => Navigator.of(context).pop(),
      children: [
        Text(l.format(K.profCurrentEmail, [widget.currentEmail]),
            style: theme.bodySmall),
        const SizedBox(height: Spacing.sm),
        AppTextField(
          label: l[K.profNewEmail],
          hint: l[K.profNewEmailPlaceholder],
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          errorText: _error,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(l),
        ),
      ],
    );
  }
}

class _ProfilePasswordSheet extends StatefulWidget {
  final Future<bool> Function(String newPassword) onChange;
  final Future<void> Function() onReset;

  const _ProfilePasswordSheet({
    required this.onChange,
    required this.onReset,
  });

  @override
  State<_ProfilePasswordSheet> createState() => _ProfilePasswordSheetState();
}

class _ProfilePasswordSheetState extends State<_ProfilePasswordSheet> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  /// U-29 — U-19's eye toggle; one control drives the pair, as register does.
  bool _obscured = true;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _change(Localization l) async {
    if (_busy) return;
    if (_password.text.length < RegisterRules.minPasswordLength) {
      setState(() => _error = l[KApp.profErrPasswordShort]);
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = l[K.profErrPasswordMismatch]);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ran = await widget.onChange(_password.text);
      if (!mounted) return;
      if (ran) {
        Navigator.of(context).pop(ProfilePasswordOutcome.changed);
        return;
      }
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.onReset();
    if (!mounted) return;
    Navigator.of(context).pop(ProfilePasswordOutcome.resetSent);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final theme = Theme.of(context).textTheme;
    return AppSheetFrame(
      title: l[K.profSectionPassword],
      busy: _busy,
      primaryLabel: l[K.profChangePassword],
      onPrimary: () => _change(l),
      secondaryLabel: l[K.commonCancel],
      onSecondary: () => Navigator.of(context).pop(),
      // The way out for a forgotten password rides WITH the actions, not in
      // the scroll: a reader who cannot answer the sudo prompt must see it.
      extraAction: OutlinedButton.icon(
        onPressed: _busy ? null : _reset,
        icon: const Icon(Icons.mail_outline),
        label: Text(l[K.profResetByEmail]),
      ),
      children: [
        AppTextField(
          label: l[K.updatePwdNewPassword],
          hint: l[K.profNewPasswordPlaceholder],
          controller: _password,
          obscureText: _obscured,
          errorText: _error,
          autofocus: true,
          textInputAction: TextInputAction.next,
          suffixIcon: IconButton(
            tooltip:
                l[_obscured ? K.commonShowPassword : K.commonHidePassword],
            icon: Icon(_obscured ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscured = !_obscured),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        AppTextField(
          label: l[K.profConfirmNewPassword],
          hint: l[K.profConfirmNewPasswordPlaceholder],
          controller: _confirm,
          obscureText: _obscured,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _change(l),
        ),
        const SizedBox(height: Spacing.md),
        Text(l[K.profForgotCurrent], style: theme.bodySmall),
      ],
    );
  }
}
