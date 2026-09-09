// U-23's promised gate, cashed in at the close of lote 6 (README: "o teste
// 'toda chave declarada tem call site' só faz sentido com as telas todas
// portadas — entra no fechamento do lote 6").
//
// The catalogs were ported WHOLE in lote 1, so they carry entries for screens
// this stack does not have (and some it will never have). A key with no call
// site is therefore not automatically a bug — but an UNCLASSIFIED one is: it
// means someone catalogued a sentence and forgot to show it.
//
// The lists below are the inventory. Both directions are asserted: a new
// orphan fails, and so does a stale entry — which is what made lote 5 delete
// the billing list instead of quietly leaving it there.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Where the keys are declared; also the files whose own references do NOT
/// count as call sites (a catalog naming its keys proves nothing).
const _catalogFiles = {
  'k.dart',
  'k_app.dart',
  'strings_en.dart',
  'strings_pt_br.dart',
};

// Lote 5 closed the billing list: the Premium section, both checkout rails,
// the payment return page and the F-43 ledger are all wired, so the set that
// used to hold 82 keys is GONE rather than left empty. This is what the gate
// was written to force — the classification is a debt register, not a
// permanent home.

/// Web-only by construction, or replaced by a native affordance: document
/// <title> (an app has app bars), the PWA install banner and shell chrome (the
/// map DROPS them), ARIA strings the app expresses through Semantics
/// differently, the month buttons that became a swipe, the "Filtrar" button
/// that became reload-on-change, and the browser print hint the F-33 redesign
/// replaced with the share sheet.
///
/// The 404 route left this list in T-64 (08/09/2026): it was classified here
/// while this stack had no error route at all, and an unknown path was
/// swallowed by the router — the reader landed on the calendar with no hint
/// that the link was wrong. On a channel whose URLs ARE its interface that is
/// not a web-only concern, so `NotFoundScreen` says it now.
const _webOnly = <String>{
  'K.auditPageTitle',
  'K.bulkAriaLabel',
  'K.calAriaCalendarOf',
  'K.calAriaHandoffAt',
  'K.calAriaNoResponsible',
  'K.calAriaNotDefined',
  'K.calAriaRequestAwaitingYou',
  'K.calAriaRequestPending',
  'K.calAriaResponsible',
  'K.calAriaSelected',
  'K.calAriaSwapDone',
  'K.calAriaToday',
  'K.editorAriaLabel',
  'K.famCopyInviteLink',
  'K.famPageTitle',
  'K.layoutErrorBody',
  'K.layoutErrorTitle',
  'K.layoutInstallAction',
  'K.layoutInstallDismiss',
  'K.layoutInstallHint',
  'K.layoutInstallIosAddToHome',
  'K.layoutInstallIosShare',
  'K.layoutInstallIosTapOn',
  'K.layoutInstallIosThen',
  'K.layoutInstallIosTitle',
  'K.layoutInstallTitle',
  'K.layoutPolicyNoticeHint',
  'K.layoutPolicyNoticeTitle',
  'K.loginDismissNotice',
  'K.loginPageTitle',
  'K.navAdmin',
  'K.notifFilterAria',
  'K.onbChecklistDismiss',
  'K.onbLauncherOpenAria',
  'K.pdfErrPrint',
  'K.pdfPageTitle',
  'K.pdfPrintHint',
  'K.pdfUpsellButton',
  'K.registerPageTitle',
  'K.repFilter',
  'K.repTabsAria',
  'K.resetPageTitle',
  'K.rolesPageTitle',
  'K.sumPageTitle',
  'K.updatePwdPageTitle',
  'K.wfAriaLabel',
};

/// The app says the same thing with its OWN entry in `k_app.dart` — the web's
/// version stays in the catalog because the catalog is a byte-identical port.
const _appHasItsOwnPhrase = <String>{
  'K.errConcurrentSave',
  'K.errConnection',
  'K.errProfileNotFound',
  'K.famOpenProfileOf',
  'K.homeBackToLogin',
  'K.homeTapToDefine',
  'K.loginPasswordPlaceholder',
  'K.loginSubmitting',
  'K.navNotifications',
  'K.rolesBackToFamily',
  'K.updatePwdConfirmPlaceholder',
  'K.updatePwdNewPasswordPlaceholder',
  'KApp.sheetNote',
  'KApp.sheetSave',
  'KApp.sheetWhoQuestion',
};

/// Honest debt: a sentence the web distinguishes and this app does not (yet).
/// Nothing here is a wrong screen — it is a screen that says something more
/// generic than it could. Shrinking this list is cheap, one key at a time.
const _notWiredYet = <String>{
  'K.authErrEmailChange',
  'K.authErrEmailInUse',
  'K.authErrEmailInvalid',
  'K.authErrEmailNotConfirmed',
  'K.authErrGeneric',
  'K.authErrMissingConfig',
  'K.authErrPasswordUpdate',
  'K.authErrRateLimitedReset',
  'K.authErrSignInFailed',
  'K.bulkClearDaysTitle',
  'K.calEmptyHint',
  'K.calEmptyTitle',
  'K.cardBackToCurrentMonth',
  'K.editorTitle',
  'K.famProgressDeleting',
  'K.homeSystemAlert',
  'K.loginExpiredFamilyDeleted',
  'K.loginExpiredToken',
  'K.notifErrApprove',
  'K.notifErrCancel',
  'K.notifErrCancelRevert',
  'K.notifErrConfirmRevert',
  'K.notifErrReject',
  'K.notifErrRejectRevert',
  'K.policyErrNoSession',
  'K.profErrSaveData',
  'K.repErrInit',
  'K.wizErrToast',
  'KApp.sudoErrNoSession',
};

void main() {
  test('every catalog key is either wired to a screen or classified', () {
    final declared = _declaredKeys();
    final used = _usedKeys();
    final orphans = declared.difference(used);
    final classified = {..._webOnly, ..._appHasItsOwnPhrase, ..._notWiredYet};

    expect(
      orphans.difference(classified),
      isEmpty,
      reason: 'A catalog key with no call site: wire it to a screen, or add it '
          'to one of the lists in this file saying WHY it has none.',
    );

    expect(
      classified.difference(orphans),
      isEmpty,
      reason: 'These keys are listed here as having no call site, but they DO '
          'have one now — remove them from the list.',
    );
  });
}

Set<String> _declaredKeys() {
  final keys = <String>{};
  for (final entry in {'K': 'k.dart', 'KApp': 'k_app.dart'}.entries) {
    final source = File(
            '../../packages/entrelares_core/lib/src/localization/${entry.value}')
        .readAsStringSync();
    for (final match
        in RegExp(r'static const String (\w+)\s*=').allMatches(source)) {
      keys.add('${entry.key}.${match.group(1)}');
    }
  }
  return keys;
}

Set<String> _usedKeys() {
  final used = <String>{};
  final pattern = RegExp(r'\b(K|KApp)\.(\w+)');
  for (final dir in [
    Directory('lib'),
    Directory('../../packages/entrelares_core/lib/src'),
  ]) {
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      if (_catalogFiles.contains(file.uri.pathSegments.last)) continue;
      for (final match in pattern.allMatches(file.readAsStringSync())) {
        used.add('${match.group(1)}.${match.group(2)}');
      }
    }
  }
  return used;
}
