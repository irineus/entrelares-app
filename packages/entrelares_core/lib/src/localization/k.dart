// U-13: every localizable string key, as compile-time constants. Born as a
// mechanical port of the Blazor client's `K.cs` (T-53); HAND-MAINTAINED since
// T-56, and the porter itself was deleted in T-70 (the source repo is archived,
// and a re-run would have overwritten the live catalogs with an older, smaller
// set). Never add a key here: new keys go to k_app.dart (prefix `app.`).

/// A typo in `K.loginSubmitt` fails to compile; a bare string key would
/// render itself in front of a user. Key parity with both catalogs is a
/// `dart test` gate (localization_test.dart).
abstract final class K {
  // ── Shared vocabulary ──
  static const String commonCancel = 'common.cancel';
  static const String commonClose = 'common.close';
  static const String commonPrivacyPolicy = 'common.privacyPolicy';
  static const String commonTermsOfUse = 'common.termsOfUse';
  static const String commonEmail = 'common.email';
  static const String commonEmailPlaceholder = 'common.emailPlaceholder';
  static const String commonPassword = 'common.password';
  static const String commonConfirmPassword = 'common.confirmPassword';

  // ── Language picker ──
  static const String languageLabel = 'language.label';
  static const String languageAriaLabel = 'language.ariaLabel';
  static const String languagePtBr = 'language.ptBr';
  static const String languageEn = 'language.en';
  static const String languageHint = 'language.hint';

  // ── Splash ──
  /// U-28: the tagline under the animated calendar, ported from the web's U-10
  /// splash. It is NOT `loginSubtitle` — that one names the product's promise
  /// ("two homes, one childhood"); this one names what the app answers today.
  static const String splashTagline = 'splash.tagline';

  // ── Login ──
  static const String loginPageTitle = 'login.pageTitle';
  static const String loginHeading = 'login.heading';
  static const String loginSubtitle = 'login.subtitle';
  static const String loginPasswordPlaceholder = 'login.passwordPlaceholder';
  static const String loginSubmit = 'login.submit';
  static const String loginSubmitting = 'login.submitting';
  static const String loginLockout = 'login.lockout';
  static const String loginForgot = 'login.forgot';
  static const String loginSignupCta = 'login.signupCta';
  static const String loginSignupLink = 'login.signupLink';
  static const String loginDismissNotice = 'login.dismissNotice';
  static const String loginExpiredInactivity = 'login.expired.inactivity';
  static const String loginExpiredToken = 'login.expired.token';
  static const String loginExpiredFamilyDeleted = 'login.expired.familyDeleted';

  // ── Sign-up / invitation ──
  static const String registerPageTitle = 'register.pageTitle';
  static const String registerCheckingInvite = 'register.checkingInvite';
  static const String registerInviteInvalidTitle = 'register.inviteInvalid.title';
  static const String registerInviteInvalidBody = 'register.inviteInvalid.body';
  static const String registerBackToLogin = 'register.backToLogin';
  static const String registerConfirmEmailTitle = 'register.confirmEmail.title';
  static const String registerConfirmEmailSentTo = 'register.confirmEmail.sentTo';
  static const String registerConfirmEmailBody = 'register.confirmEmail.body';
  static const String registerGoToLogin = 'register.goToLogin';
  static const String registerInvitedTitle = 'register.invited.title';
  static const String registerInvitedBody = 'register.invited.body';
  static const String registerCreateTitle = 'register.create.title';
  static const String registerCreateSubtitle = 'register.create.subtitle';
  static const String registerFullName = 'register.fullName';
  static const String registerFullNamePlaceholder = 'register.fullNamePlaceholder';
  static const String registerFamilyName = 'register.familyName';
  static const String registerFamilyNamePlaceholder = 'register.familyNamePlaceholder';
  static const String registerFamilyNameHint = 'register.familyNameHint';
  static const String registerYouAre = 'register.youAre';
  static const String registerPasswordPlaceholder = 'register.passwordPlaceholder';
  static const String registerConfirmPasswordPlaceholder = 'register.confirmPasswordPlaceholder';
  static const String registerConsentAccept = 'register.consent.accept';
  static const String registerConsentAnd = 'register.consent.and';
  static const String registerConsentBindingNotice = 'register.consent.bindingNotice';
  static const String registerSubmit = 'register.submit';
  static const String registerSubmitting = 'register.submitting';
  static const String registerHaveAccount = 'register.haveAccount';
  static const String registerMigrationTitle = 'register.migration.title';
  static const String registerMigrationBody1 = 'register.migration.body1';
  static const String registerMigrationBody2 = 'register.migration.body2';
  static const String registerMigrationConfirm = 'register.migration.confirm';
  static const String registerMigrationConfirming = 'register.migration.confirming';
  static const String registerErrorNameRequired = 'register.error.nameRequired';
  static const String registerErrorEmailRequired = 'register.error.emailRequired';
  static const String registerErrorFamilyRequired = 'register.error.familyRequired';
  static const String registerErrorRoleRequired = 'register.error.roleRequired';
  static const String registerErrorPasswordShort = 'register.error.passwordShort';
  static const String registerErrorPasswordMismatch = 'register.error.passwordMismatch';
  static const String registerErrorConsentRequired = 'register.error.consentRequired';

  // ── Password recovery ──
  static const String resetPageTitle = 'reset.pageTitle';
  static const String resetTitle = 'reset.title';
  static const String resetSubtitle = 'reset.subtitle';
  static const String resetSubmit = 'reset.submit';
  static const String resetSentTitle = 'reset.sent.title';
  static const String resetSentBody = 'reset.sent.body';
  static const String resetBackToLogin = 'reset.backToLogin';
  static const String updatePwdPageTitle = 'updatePwd.pageTitle';
  static const String updatePwdDoneTitle = 'updatePwd.done.title';
  static const String updatePwdDoneBody = 'updatePwd.done.body';
  static const String updatePwdGoToCalendar = 'updatePwd.goToCalendar';
  static const String updatePwdTitle = 'updatePwd.title';
  static const String updatePwdSubtitle = 'updatePwd.subtitle';
  static const String updatePwdNewPassword = 'updatePwd.newPassword';
  static const String updatePwdNewPasswordPlaceholder = 'updatePwd.newPasswordPlaceholder';
  static const String updatePwdConfirmPlaceholder = 'updatePwd.confirmPlaceholder';
  static const String updatePwdSubmit = 'updatePwd.submit';
  static const String updatePwdErrorSession = 'updatePwd.error.session';
  static const String updatePwdErrorShort = 'updatePwd.error.short';
  static const String updatePwdErrorMismatch = 'updatePwd.error.mismatch';

  // ── Navigation chrome ──
  static const String navCalendar = 'nav.calendar';
  static const String navFamily = 'nav.family';
  static const String navNotifications = 'nav.notifications';
  static const String navNotificationsShort = 'nav.notificationsShort';
  static const String navNotificationsOnePending = 'nav.notificationsOnePending';
  static const String navNotificationsManyPending = 'nav.notificationsManyPending';
  static const String navReports = 'nav.reports';
  static const String navLogout = 'nav.logout';
  /// U-28: the account button that carries Perfil / Idioma / Sair on every tab.
  /// Logout used to exist only on the calendar's app bar, so three of the four
  /// tabs had no way out of the app at all.
  /// U-28 QA — the one word the app uses to mark a field as optional.
  ///
  /// Required is the default and goes UNMARKED: most fields in this product are
  /// required, so marking those would put a badge on nearly every row. The
  /// explanations that used to ride in parentheses after a label moved into an
  /// [AppInfoTip], which is why the hint strings below lost their brackets.
  static const String commonOptional = 'common.optional';

  /// U-29 — the accessible name of the password eye toggle. U-19 gave every
  /// obscured field a show/hide control; these are what a screen reader (and a
  /// long-press) calls it, in the state it would SWITCH TO.
  static const String commonShowPassword = 'common.showPassword';
  static const String commonHidePassword = 'common.hidePassword';

  /// U-28 QA — the two halves of a handoff time. They exist because the pickers
  /// became real form fields with integrated labels: a bare "19" and "00" side
  /// by side say nothing about which is which.
  /// U-28 QA — the wizard's block row became two real form fields, and a field
  /// needs a label of its own: "Fernanda" and "7" side by side said nothing
  /// about which was the carer and which the number of days.
  static const String wizBlockParentLabel = 'wiz.blockParentLabel';

  static const String navAccount = 'nav.account';
  static const String navProfile = 'nav.profile';
  static const String navAdmin = 'nav.admin';
  static const String navAdminEnter = 'nav.adminEnter';
  static const String navAdminExit = 'nav.adminExit';

  // ── App chrome (MainLayout) ──
  static const String layoutAdminActive = 'layout.adminActive';
  static const String layoutAdminHint = 'layout.adminHint';
  static const String layoutAdminExit = 'layout.adminExit';
  static const String layoutPolicyNoticeTitle = 'layout.policyNotice.title';
  static const String layoutPolicyNoticeHint = 'layout.policyNotice.hint';
  static const String layoutFamilyDeletionConfirmed = 'layout.familyDeletion.confirmed';
  static const String layoutFamilyDeletionConfirmedUntil = 'layout.familyDeletion.confirmedUntil';
  static const String layoutFamilyDeletionRequested = 'layout.familyDeletion.requested';
  static const String layoutFamilyDeletionRequester = 'layout.familyDeletion.requester';
  static const String layoutFamilyDeletionOther = 'layout.familyDeletion.other';
  static const String layoutErrorTitle = 'layout.error.title';
  static const String layoutErrorBody = 'layout.error.body';
  static const String layoutErrorReload = 'layout.error.reload';
  static const String layoutInstallTitle = 'layout.install.title';
  static const String layoutInstallHint = 'layout.install.hint';
  static const String layoutInstallAction = 'layout.install.action';
  static const String layoutInstallDismiss = 'layout.install.dismiss';
  static const String layoutInstallIosTitle = 'layout.install.iosTitle';
  static const String layoutInstallIosTapOn = 'layout.install.iosTapOn';
  static const String layoutInstallIosShare = 'layout.install.iosShare';
  static const String layoutInstallIosThen = 'layout.install.iosThen';
  static const String layoutInstallIosAddToHome = 'layout.install.iosAddToHome';

  // ── Calendar (Home) ──
  static const String homeSystemAlert = 'home.systemAlert';
  static const String homeBackToLogin = 'home.backToLogin';
  static const String homeNotDefined = 'home.notDefined';
  static const String homeTapToDefine = 'home.tapToDefine';
  /// U-28 QA — the chip in the month bar that goes back to the current month.
  /// whole sentence would push them off centre.
  static const String calToday = 'cal.today';

  static const String calPrevMonth = 'cal.prevMonth';
  static const String calNextMonth = 'cal.nextMonth';
  static const String calSelectDays = 'cal.selectDays';
  static const String calWizard = 'cal.wizard';
  static const String calAriaCalendarOf = 'cal.ariaCalendarOf';
  static const String calMemberLeft = 'cal.memberLeft';
  static const String calSwapped = 'cal.swapped';
  static const String calWeekdayInitials = 'cal.weekdayInitials';
  static const String calOverdueAwaitingYou = 'cal.overdueAwaitingYou';
  static const String calAwaitingYou = 'cal.awaitingYou';
  static const String calAwaitingFrom = 'cal.awaitingFrom';
  static const String calOtherCaregiver = 'cal.otherCaregiver';
  static const String calEmptyTitle = 'cal.emptyTitle';
  static const String calEmptyHint = 'cal.emptyHint';
  static const String calAriaToday = 'cal.aria.today';
  static const String calAriaNoResponsible = 'cal.aria.noResponsible';
  static const String calAriaResponsible = 'cal.aria.responsible';
  static const String calAriaNotDefined = 'cal.aria.notDefined';
  static const String calAriaSwapDone = 'cal.aria.swapDone';
  static const String calAriaHandoffAt = 'cal.aria.handoffAt';
  static const String calAriaRequestAwaitingYou = 'cal.aria.requestAwaitingYou';
  static const String calAriaRequestPending = 'cal.aria.requestPending';
  static const String calAriaSelected = 'cal.aria.selected';
  static const String selectionResolve = 'selection.resolve';
  static const String selectionEdit = 'selection.edit';
  static const String selectionCancel = 'selection.cancel';
  static const String navGuardSelectedOne = 'navGuard.selectedOne';
  static const String navGuardSelectedMany = 'navGuard.selectedMany';
  static const String navGuardBody = 'navGuard.body';
  static const String navGuardYes = 'navGuard.yes';
  static const String navGuardNo = 'navGuard.no';

  // ── Today card ──
  static const String cardBackToCurrentMonth = 'card.backToCurrentMonth';
  static const String cardGreeting = 'card.greeting';
  static const String cardInviteTitle = 'card.inviteTitle';
  static const String cardInviteHint = 'card.inviteHint';
  static const String cardInviteAction = 'card.inviteAction';
  static const String cardResponsibleToday = 'card.responsibleToday';
  static const String cardNextHandoff = 'card.nextHandoff';
  static const String cardSwappedBadge = 'card.swappedBadge';
  static const String cardNoResponsibleTitle = 'card.noResponsibleTitle';
  static const String cardNoResponsibleHint = 'card.noResponsibleHint';

  // ── Relative days (CalendarHelpers.GetDaysUntil) ──
  static const String relDaysAgo = 'rel.daysAgo';
  static const String relYesterday = 'rel.yesterday';
  static const String relToday = 'rel.today';
  static const String relTomorrow = 'rel.tomorrow';
  static const String relInDays = 'rel.inDays';

  // ── Day editor sheet ──
  static const String editorAriaLabel = 'editor.ariaLabel';
  static const String editorTitle = 'editor.title';
  static const String editorAdminOverride = 'editor.adminOverride';
  static const String editorPastReadonly = 'editor.pastReadonly';
  static const String editorFrozenReadonly = 'editor.frozenReadonly';
  static const String editorScheduledParent = 'editor.scheduledParent';

  /// U-29 — the parenthetical explainers left the labels for the ⓘ tip,
  /// completing in PT-BR what the English catalog had already done.
  static const String editorScheduledParentHint = 'editor.scheduledParentHint';
  static const String editorActualParentHint = 'editor.actualParentHint';
  static const String editorSelectPlaceholder = 'editor.selectPlaceholder';
  static const String editorLockedHint = 'editor.lockedHint';
  static const String editorActualParent = 'editor.actualParent';
  static const String editorSameAsPlanned = 'editor.sameAsPlanned';
  static const String editorDayNote = 'editor.dayNote';
  static const String editorDayNoteHint = 'editor.dayNoteHint';
  static const String editorDayNotePlaceholder = 'editor.dayNotePlaceholder';
  static const String editorHandoffTime = 'editor.handoffTime';
  static const String editorHandoffHint = 'editor.handoffHint';

  /// U-37: the single time field — what it says while empty, and the name of
  /// the ✕ that clears it (the dropdowns' "--" option, now one tap).
  static const String editorHandoffEmpty = 'editor.handoffEmpty';
  static const String editorHandoffClear = 'editor.handoffClear';
  static const String editorNoTransitionHint = 'editor.noTransitionHint';
  static const String editorMessageLabel = 'editor.messageLabel';
  static const String editorMessagePlaceholder = 'editor.messagePlaceholder';
  static const String editorWorkflowHint = 'editor.workflowHint';
  static const String editorAdminChangeWarning = 'editor.adminChangeWarning';
  static const String editorYesChange = 'editor.yesChange';
  static const String editorNoGoBack = 'editor.noGoBack';
  static const String editorRevertNotesQuestion = 'editor.revertNotesQuestion';
  static const String editorRevertNotesCurrent = 'editor.revertNotesCurrent';
  static const String editorRevertNotesBefore = 'editor.revertNotesBefore';
  static const String editorNoNote = 'editor.noNote';
  static const String editorKeepCurrent = 'editor.keepCurrent';
  static const String editorRestorePrevious = 'editor.restorePrevious';
  static const String editorClearDay = 'editor.clearDay';
  static const String commonSave = 'common.save';

  // ── Bulk edit sheet ──
  static const String bulkAriaLabel = 'bulk.ariaLabel';
  static const String bulkTitleOne = 'bulk.titleOne';
  static const String bulkTitleMany = 'bulk.titleMany';
  static const String bulkDeleteAllWarning = 'bulk.deleteAllWarning';
  static const String bulkYesDelete = 'bulk.yesDelete';
  static const String bulkClearDaysAction = 'bulk.clearDaysAction';
  static const String bulkClearDaysTitle = 'bulk.clearDaysTitle';
  static const String bulkKeptScheduledOne = 'bulk.keptScheduledOne';
  static const String bulkKeptScheduledMany = 'bulk.keptScheduledMany';
  static const String bulkClear = 'bulk.clear';
  static const String bulkNotePlaceholder = 'bulk.notePlaceholder';
  static const String bulkMessageHint = 'bulk.messageHint';
  static const String bulkMessagePlaceholder = 'bulk.messagePlaceholder';
  static const String bulkOverwriteWarningOne = 'bulk.overwriteWarningOne';
  static const String bulkOverwriteWarningMany = 'bulk.overwriteWarningMany';
  static const String bulkErrNoEligibleDays = 'bulk.err.noEligibleDays';
  static const String bulkErrPickScheduled = 'bulk.err.pickScheduled';
  static const String bulkConflictSuffixOne = 'bulk.conflictSuffixOne';
  static const String bulkConflictSuffixMany = 'bulk.conflictSuffixMany';
  static const String bulkHandoffSuffix = 'bulk.handoffSuffix';
  static const String bulkKeptSuffixOne = 'bulk.keptSuffixOne';
  static const String bulkKeptSuffixMany = 'bulk.keptSuffixMany';

  // ── Resolve-requests sheet ──
  static const String wfAriaLabel = 'wf.ariaLabel';
  static const String wfTitle = 'wf.title';
  static const String wfAwaitingYou = 'wf.awaitingYou';
  static const String wfMessage = 'wf.message';
  static const String wfRejectHint = 'wf.rejectHint';
  static const String wfRejectPlaceholder = 'wf.rejectPlaceholder';
  static const String wfApprove = 'wf.approve';
  static const String wfReject = 'wf.reject';
  static const String wfSentByYouOne = 'wf.sentByYouOne';
  static const String wfSentByYouMany = 'wf.sentByYouMany';
  static const String wfCancel = 'wf.cancel';
  static const String wfApprovedSwaps = 'wf.approvedSwaps';
  static const String wfRequestRevert = 'wf.requestRevert';
  static const String wfClose = 'wf.close';

  // ── Frozen-day panel ──
  static const String frozenRevertTitle = 'frozen.revertTitle';
  static const String frozenSwapTitle = 'frozen.swapTitle';
  static const String frozenUrgent = 'frozen.urgent';
  static const String frozenOverdue = 'frozen.overdue';
  static const String frozenDay = 'frozen.day';
  static const String frozenRequester = 'frozen.requester';
  static const String frozenRevertTo = 'frozen.revertTo';
  static const String frozenProposedParent = 'frozen.proposedParent';
  static const String frozenProposedTime = 'frozen.proposedTime';
  static const String frozenRequesterMessage = 'frozen.requesterMessage';
  static const String frozenRequestedAt = 'frozen.requestedAt';
  static const String frozenNoteLabel = 'frozen.noteLabel';
  static const String frozenNoteHint = 'frozen.noteHint';
  static const String frozenNotePlaceholder = 'frozen.notePlaceholder';
  static const String frozenConfirmRevert = 'frozen.confirmRevert';
  static const String frozenApprove = 'frozen.approve';
  static const String frozenRejectAction = 'frozen.rejectAction';
  static const String frozenCancelRevert = 'frozen.cancelRevert';
  static const String frozenCancelRequest = 'frozen.cancelRequest';
  static const String frozenObserver = 'frozen.observer';

  // ── Rotation wizard ──
  static const String wizTitle = 'wiz.title';
  static const String wizSubtitle = 'wiz.subtitle';
  static const String wizClose = 'wiz.close';
  static const String wizPreset = 'wiz.preset';
  static const String wizPresetCustom = 'wiz.presetCustom';
  static const String wizPreset77 = 'wiz.preset77';
  static const String wizPreset1414 = 'wiz.preset1414';
  static const String wizPreset11 = 'wiz.preset11';
  static const String wizPreset5225 = 'wiz.preset5225';
  static const String wizPreset223 = 'wiz.preset223';
  static const String wizCycleBlocks = 'wiz.cycleBlocks';
  static const String wizBlockParent = 'wiz.blockParent';
  static const String wizDays = 'wiz.days';
  static const String wizRemoveBlock = 'wiz.removeBlock';
  static const String wizAddBlock = 'wiz.addBlock';
  static const String wizStartDate = 'wiz.startDate';
  static const String wizDuration = 'wiz.duration';
  static const String wizMonthsOne = 'wiz.monthsOne';
  static const String wizMonthsMany = 'wiz.monthsMany';
  static const String wizHandoffTime = 'wiz.handoffTime';
  static const String wizHandoffHint = 'wiz.handoffHint';
  static const String wizCyclePreview = 'wiz.cyclePreview';
  static const String wizGenerate = 'wiz.generate';
  static const String wizCycleSummary = 'wiz.cycleSummary';
  static const String wizErrPickParentPerBlock = 'wiz.err.pickParentPerBlock';
  static const String wizErrStartInPast = 'wiz.err.startInPast';
  static const String wizErrStartBeyondFree = 'wiz.err.startBeyondFree';
  static const String wizErrStartBeyondMax = 'wiz.err.startBeyondMax';
  static const String wizErrGenerate = 'wiz.err.generate';
  static const String wizErrToast = 'wiz.err.toast';
  static const String wizDoneCreated = 'wiz.done.created';
  static const String wizDoneKept = 'wiz.done.kept';
  static const String wizDoneClampedFree = 'wiz.done.clampedFree';
  static const String wizDoneClampedMax = 'wiz.done.clampedMax';

  // ── Bulk summary (BulkSummary) ──
  static const String sumSwapRequestOne = 'sum.swapRequestOne';
  static const String sumSwapRequestMany = 'sum.swapRequestMany';
  static const String sumRevertOne = 'sum.revertOne';
  static const String sumRevertMany = 'sum.revertMany';
  static const String sumUnchangedOne = 'sum.unchangedOne';
  static const String sumUnchangedMany = 'sum.unchangedMany';
  static const String sumSkippedOne = 'sum.skippedOne';
  static const String sumSkippedMany = 'sum.skippedMany';
  static const String sumNothingToDo = 'sum.nothingToDo';
  static const String sumUpdatedOne = 'sum.updatedOne';
  static const String sumUpdatedMany = 'sum.updatedMany';
  static const String sumIgnoredOne = 'sum.ignoredOne';
  static const String sumIgnoredMany = 'sum.ignoredMany';
  static const String sumApprovedOne = 'sum.approvedOne';
  static const String sumApprovedMany = 'sum.approvedMany';
  static const String sumRejectedOne = 'sum.rejectedOne';
  static const String sumRejectedMany = 'sum.rejectedMany';
  static const String sumCancelledOne = 'sum.cancelledOne';
  static const String sumCancelledMany = 'sum.cancelledMany';
  static const String sumDeletedOne = 'sum.deletedOne';
  static const String sumDeletedMany = 'sum.deletedMany';
  static const String bulkProgressDeleting = 'bulk.progress.deleting';

  // ── Toasts and save errors the ACTING user reads ──
  static const String toastRevertRequested = 'toast.revertRequested';
  static const String toastSwapRequested = 'toast.swapRequested';
  static const String toastRequestCancelled = 'toast.requestCancelled';
  static const String toastRevertConfirmed = 'toast.revertConfirmed';
  static const String toastRevertRejected = 'toast.revertRejected';
  static const String toastRevertCancelled = 'toast.revertCancelled';
  static const String errProfileNotFound = 'err.profileNotFound';
  static const String errConnection = 'err.connection';
  static const String errPastDay = 'err.pastDay';
  static const String errFrozenDay = 'err.frozenDay';
  static const String errStaleClient = 'err.staleClient';
  static const String errConcurrentSave = 'err.concurrentSave';
  static const String errSaveFailed = 'err.saveFailed';
  static const String errDeleteFailed = 'err.deleteFailed';
  static const String errApproveFailed = 'err.approveFailed';
  static const String errRejectFailed = 'err.rejectFailed';
  static const String errCancelFailed = 'err.cancelFailed';
  static const String errConfirmRevertFailed = 'err.confirmRevertFailed';
  static const String errRejectRevertFailed = 'err.rejectRevertFailed';
  static const String errCancelRevertFailed = 'err.cancelRevertFailed';
  static const String errBulkWorkflowFailed = 'err.bulkWorkflowFailed';
  static const String horizonPremium = 'horizon.premium';
  static const String horizonFree = 'horizon.free';

  // ── Family page ──
  static const String famPageTitle = 'fam.pageTitle';
  static const String famHeading = 'fam.heading';
  static const String famRename = 'fam.rename';
  static const String famLoading = 'fam.loading';
  static const String famCaregivers = 'fam.caregivers';
  static const String famOpenProfileOf = 'fam.openProfileOf';
  static const String famYou = 'fam.you';
  static const String famLeftBadge = 'fam.leftBadge';
  static const String famAdminBadge = 'fam.adminBadge';
  static const String famInviteSection = 'fam.inviteSection';
  static const String famOnlyAdminsInvite = 'fam.onlyAdminsInvite';
  static const String famInviteExpiredBadge = 'fam.inviteExpiredBadge';
  static const String famInviteSentBadge = 'fam.inviteSentBadge';
  static const String famInviteValidUntil = 'fam.inviteValidUntil';
  static const String famCopyInviteLink = 'fam.copyInviteLink';
  static const String famCopyLink = 'fam.copyLink';
  static const String famInviteWhatsapp = 'fam.inviteWhatsapp';
  static const String famInviteExpiredHint = 'fam.inviteExpiredHint';
  static const String famSending = 'fam.sending';
  static const String famResendInvite = 'fam.resendInvite';
  static const String famRevoke = 'fam.revoke';
  static const String famFreeCapNotice = 'fam.freeCapNotice';
  static const String famSeePremium = 'fam.seePremium';
  static const String famInviteWhoHelps = 'fam.inviteWhoHelps';
  static const String famInviteEmailPlaceholder = 'fam.inviteEmailPlaceholder';
  static const String famRoleInFamily = 'fam.roleInFamily';
  static const String famCustomRolesLink = 'fam.customRolesLink';
  static const String famSendInvite = 'fam.sendInvite';
  static const String famSeatsFull = 'fam.seatsFull';
  static const String famAdminSection = 'fam.adminSection';
  static const String famAdminActiveNote = 'fam.adminActiveNote';
  static const String famAdminInactiveNote = 'fam.adminInactiveNote';
  static const String famAdminTierPremium = 'fam.adminTierPremium';
  static const String famAdminTierFree = 'fam.adminTierFree';
  static const String famActivatePremiumLink = 'fam.activatePremiumLink';
  static const String famAdminDeactivate = 'fam.adminDeactivate';
  static const String famAdminActivate = 'fam.adminActivate';

  // ── Premium / billing block (U-13 PR 3a-Premium) ──
  static const String premTitle = 'prem.title';
  static const String premBadgeTrialOne = 'prem.badge.trialOne';
  static const String premBadgeTrialMany = 'prem.badge.trialMany';
  static const String premBadgeTrialUntil = 'prem.badge.trialUntil';
  static const String premBadgeForever = 'prem.badge.forever';
  static const String premBadgeActive = 'prem.badge.active';
  static const String premBadgeFree = 'prem.badge.free';
  static const String premExpiredTrial = 'prem.expired.trial';
  static const String premExpiredPaid = 'prem.expired.paid';
  static const String premIntro = 'prem.intro';
  static const String premIntroWaitlist = 'prem.intro.waitlist';
  static const String premIntroOffer = 'prem.intro.offer';
  static const String premFeatureCaregivers = 'prem.feature.caregivers';
  static const String premFeatureHorizon = 'prem.feature.horizon';
  static const String premFeaturePdf = 'prem.feature.pdf';
  static const String premFeatureAdminMode = 'prem.feature.adminMode';
  static const String premFeatureRoles = 'prem.feature.roles';
  static const String premCycleMonthly = 'prem.cycle.monthly';
  static const String premCycleAnnual = 'prem.cycle.annual';
  static const String premMethodPix = 'prem.method.pix';
  static const String premMethodCard = 'prem.method.card';
  static const String premMethodBoleto = 'prem.method.boleto';
  static const String premForeverNote = 'prem.foreverNote';
  static const String premActiveStatus = 'prem.active.status';
  static const String premActiveRenews = 'prem.active.renews';
  static const String premCancelWarning = 'prem.cancel.warning';
  static const String premCancelWarningUntil = 'prem.cancel.warningUntil';
  static const String premCancelConfirm = 'prem.cancel.confirm';
  static const String premCancelKeep = 'prem.cancel.keep';
  static const String premCancelButton = 'prem.cancel.button';
  static const String premOverdueGraceEnded = 'prem.overdue.graceEnded';
  static const String premOverdueInGrace = 'prem.overdue.inGrace';
  static const String premOverdueInGraceNoDate = 'prem.overdue.inGraceNoDate';
  static const String premScheduledStatus = 'prem.scheduled.status';
  static const String premScheduledDetail = 'prem.scheduled.detail';
  static const String premScheduledDetailMethod = 'prem.scheduled.detailMethod';
  static const String premScheduledCancelWarning = 'prem.scheduled.cancelWarning';
  static const String premScheduledCancelKeep = 'prem.scheduled.cancelKeep';
  static const String premScheduledCancelButton = 'prem.scheduled.cancelButton';
  static const String premStorePaidUntilAvulso = 'prem.store.paidUntilAvulso';
  static const String premStorePaidUntilPeriod = 'prem.store.paidUntilPeriod';
  static const String premStoreTrialUntil = 'prem.store.trialUntil';
  static const String premStoreNote = 'prem.store.note';
  static const String premPaidUntilAvulso = 'prem.paidUntil.avulso';
  static const String premPaidUntilPeriod = 'prem.paidUntil.period';
  static const String premExpiringSoonOne = 'prem.expiringSoon.one';
  static const String premExpiringSoonMany = 'prem.expiringSoon.many';
  static const String premTrialAdditive = 'prem.trialAdditive';
  static const String premReactivateButton = 'prem.reactivate.button';
  static const String premReactivateHint = 'prem.reactivate.hint';
  static const String premReactivateHintDate = 'prem.reactivate.hintDate';
  static const String premReactivateHintMethod = 'prem.reactivate.hintMethod';
  static const String premReactivateHintMethodDate = 'prem.reactivate.hintMethodDate';
  static const String premSubscribeMonthly = 'prem.subscribe.monthly';
  static const String premSubscribeAnnual = 'prem.subscribe.annual';
  static const String premAvulsoLead = 'prem.avulso.lead';
  static const String premAvulsoMonthly = 'prem.avulso.monthly';
  static const String premAvulsoAnnual = 'prem.avulso.annual';
  static const String premPaymentHint = 'prem.paymentHint';
  static const String premGuarantee = 'prem.guarantee';
  static const String premAdminOnly = 'prem.adminOnly';
  static const String premInterestDone = 'prem.interest.done';
  static const String premInterestKeepTrial = 'prem.interest.keepTrial';
  static const String premInterestWant = 'prem.interest.want';
  static const String premInterestHint = 'prem.interest.hint';
  static const String premHistoryToggle = 'prem.history.toggle';
  static const String premHistoryLoading = 'prem.history.loading';
  static const String premHistoryEmpty = 'prem.history.empty';
  static const String premHistoryReceipt = 'prem.history.receipt';
  static const String premHistoryPayment = 'prem.history.payment';
  static const String premHistoryRefund = 'prem.history.refund';
  static const String premHistoryOverdue = 'prem.history.overdue';
  static const String premHistoryCanceled = 'prem.history.canceled';
  static const String premHistoryDowngraded = 'prem.history.downgraded';
  static const String premHistoryOther = 'prem.history.other';
  static const String famDelTitle = 'famDel.title';
  static const String famDelAllAgreed = 'famDel.allAgreed';
  static const String famDelAllAgreedAdmin = 'famDel.allAgreedAdmin';
  static const String famDelAllAgreedMember = 'famDel.allAgreedMember';
  static const String famDelRequested = 'famDel.requested';
  static const String famDelConsequenceSilence = 'famDel.consequence.silence';
  static const String famDelConsequenceUnanimity = 'famDel.consequence.unanimity';
  static const String famDelConsequenceBlocked = 'famDel.consequence.blocked';
  static const String famDelConsequenceExport = 'famDel.consequence.export';
  static const String famDelVoteAgreed = 'famDel.vote.agreed';
  static const String famDelVoteRefused = 'famDel.vote.refused';
  static const String famDelVoteWaiting = 'famDel.vote.waiting';
  static const String famDelWithdraw = 'famDel.withdraw';
  static const String famDelRefuseKeep = 'famDel.refuseKeep';
  static const String famDelUndoAgreement = 'famDel.undoAgreement';
  static const String famDelAgree = 'famDel.agree';
  static const String famDelExecuteNowOpen = 'famDel.executeNowOpen';
  static const String famDelExecuteConfirmText = 'famDel.executeConfirmText';
  static const String famDelExecuteNow = 'famDel.executeNow';
  static const String famDelBack = 'famDel.back';
  static const String famDelReqTitle = 'famDelReq.title';
  static const String famDelReqIntro = 'famDelReq.intro';
  static const String famDelReqConsequenceData = 'famDelReq.consequence.data';
  static const String famDelReqConsequenceNotice = 'famDelReq.consequence.notice';
  static const String famDelReqConsequenceUnanimity = 'famDelReq.consequence.unanimity';
  static const String famDelReqConsequenceWithdraw = 'famDelReq.consequence.withdraw';
  static const String famDelReqOpen = 'famDelReq.open';
  static const String famDelReqConfirmText = 'famDelReq.confirmText';
  static const String famDelReqConfirm = 'famDelReq.confirm';
  static const String famDelReqKeep = 'famDelReq.keep';
  static const String famRequesterFallback = 'fam.requesterFallback';
  static const String famToastDeletionRequested = 'fam.toast.deletionRequested';
  static const String famToastAgreed = 'fam.toast.agreed';
  static const String famToastRefused = 'fam.toast.refused';
  static const String famToastAgreementUndone = 'fam.toast.agreementUndone';
  static const String famToastWithdrawn = 'fam.toast.withdrawn';
  static const String famProgressDeleting = 'fam.progress.deleting';
  static const String famErrInvalidEmail = 'fam.err.invalidEmail';
  static const String famErrOwnEmail = 'fam.err.ownEmail';
  static const String famErrResendInvite = 'fam.err.resendInvite';
  static const String famErrFamilyNameRequired = 'fam.err.familyNameRequired';
  static const String famToastRenamed = 'fam.toast.renamed';
  static const String famErrCopy = 'fam.err.copy';

  // ── Audit trail: field labels, action labels, origin sentence (U-13 PR 5) ──
  static const String auditFieldScheduledParent = 'audit.field.scheduledParent';
  static const String auditFieldActualParent = 'audit.field.actualParent';
  static const String auditFieldHandoffTime = 'audit.field.handoffTime';
  static const String auditFieldDayNote = 'audit.field.dayNote';
  static const String auditActionAdminGranted = 'audit.action.adminGranted';
  static const String auditActionAdminRevoked = 'audit.action.adminRevoked';
  static const String auditActionRoleChanged = 'audit.action.roleChanged';
  static const String auditActionNameChanged = 'audit.action.nameChanged';
  static const String auditActionEmailChanged = 'audit.action.emailChanged';
  static const String auditActionFamilyRenamed = 'audit.action.familyRenamed';
  static const String auditActionInvitationCreated = 'audit.action.invitationCreated';
  static const String auditActionInvitationRevoked = 'audit.action.invitationRevoked';
  static const String auditActionInvitationAccepted = 'audit.action.invitationAccepted';
  static const String auditActionLeaveRequested = 'audit.action.leaveRequested';
  static const String auditActionLeaveCancelled = 'audit.action.leaveCancelled';
  static const String auditActionPasswordChanged = 'audit.action.passwordChanged';
  static const String auditActionEmailChangeRequested = 'audit.action.emailChangeRequested';
  static const String auditActionDataExported = 'audit.action.dataExported';
  static const String auditActionCompGranted = 'audit.action.compGranted';
  static const String auditActionCompRevoked = 'audit.action.compRevoked';
  static const String auditActionPlanPremiumPayment = 'audit.action.planPremiumPayment';
  static const String auditActionPlanPremiumAvulso = 'audit.action.planPremiumAvulso';
  static const String auditActionPlanPremiumSet = 'audit.action.planPremiumSet';
  static const String auditActionPlanFreeOverdue = 'audit.action.planFreeOverdue';
  static const String auditActionPlanFreeCanceled = 'audit.action.planFreeCanceled';
  static const String auditActionPlanFreeSet = 'audit.action.planFreeSet';
  static const String auditTrialEnded = 'audit.trialEnded';
  static const String auditDayLabel = 'audit.dayLabel';
  static const String auditScheduleChange = 'audit.scheduleChange';
  static const String auditOriginSwapManual = 'audit.origin.swapManual';
  static const String auditOriginSwapAuto = 'audit.origin.swapAuto';
  static const String auditOriginRevertManual = 'audit.origin.revertManual';
  static const String auditOriginRevertAuto = 'audit.origin.revertAuto';
  static const String auditOriginSomeCaregiver = 'audit.origin.someCaregiver';
  static const String auditOriginOtherCaregiver = 'audit.origin.otherCaregiver';
  // F-61: the dated facts beyond the diff — shared by the timeline and the PDF.
  static const String auditAuthorshipNoAccount = 'audit.authorship.noAccount';
  static const String auditAuthorshipAdminOverride =
      'audit.authorship.adminOverride';

  // ── PDF report (F-33) — the page AND the printed document ──
  static const String pdfPageTitle = 'pdf.pageTitle';
  static const String pdfHeading = 'pdf.heading';
  static const String pdfSubtitle = 'pdf.subtitle';
  static const String pdfLoading = 'pdf.loading';
  static const String pdfUpsellBadge = 'pdf.upsell.badge';
  static const String pdfUpsellTitle = 'pdf.upsell.title';
  static const String pdfUpsellText = 'pdf.upsell.text';
  static const String pdfUpsellButton = 'pdf.upsell.button';
  static const String pdfPeriodAria = 'pdf.periodAria';
  static const String pdfByMonth = 'pdf.byMonth';
  static const String pdfByYear = 'pdf.byYear';
  static const String pdfCustom = 'pdf.custom';
  static const String pdfFrom = 'pdf.from';
  static const String pdfTo = 'pdf.to';
  static const String pdfChildName = 'pdf.childName';
  static const String pdfChildOptional = 'pdf.childOptional';
  static const String pdfChildPlaceholder = 'pdf.childPlaceholder';
  static const String pdfIncludeFutureSwaps = 'pdf.includeFutureSwaps';
  static const String pdfGenerate = 'pdf.generate';
  static const String pdfGenerating = 'pdf.generating';
  static const String pdfPrintButton = 'pdf.printButton';
  static const String pdfPrintHint = 'pdf.printHint';
  static const String pdfErrEndBeforeStart = 'pdf.err.endBeforeStart';
  static const String pdfErrLoad = 'pdf.err.load';
  static const String pdfErrGenerate = 'pdf.err.generate';
  static const String pdfErrPrint = 'pdf.err.print';
  static const String pdfDocTitle = 'pdf.doc.title';
  static const String pdfDocSubtitle = 'pdf.doc.subtitle';
  static const String pdfDocFamily = 'pdf.doc.family';
  static const String pdfDocChild = 'pdf.doc.child';
  static const String pdfDocPeriod = 'pdf.doc.period';
  static const String pdfDocPeriodValue = 'pdf.doc.periodValue';
  static const String pdfDocCriterion = 'pdf.doc.criterion';
  static const String pdfDocCriterionValue = 'pdf.doc.criterionValue';
  static const String pdfDocGeneratedAt = 'pdf.doc.generatedAt';
  static const String pdfDocGeneratedBy = 'pdf.doc.generatedBy';
  static const String pdfDocImmutability = 'pdf.doc.immutability';
  static const String pdfDocSection1 = 'pdf.doc.section1';
  static const String pdfDocSection2 = 'pdf.doc.section2';
  static const String pdfDocEmptySummary = 'pdf.doc.emptySummary';
  static const String pdfDocEmptyHistory = 'pdf.doc.emptyHistory';
  static const String pdfDocColCaregiver = 'pdf.doc.col.caregiver';
  static const String pdfDocColRole = 'pdf.doc.col.role';
  static const String pdfDocColPlanned = 'pdf.doc.col.planned';
  static const String pdfDocColActual = 'pdf.doc.col.actual';
  static const String pdfDocColProjected = 'pdf.doc.col.projected';
  static const String pdfDocColSwaps = 'pdf.doc.col.swaps';
  static const String pdfDocTotalSwaps = 'pdf.doc.totalSwaps';
  static const String pdfDocTotalSwapsFuture = 'pdf.doc.totalSwapsFuture';
  static const String pdfDocRequesterMessage = 'pdf.doc.requesterMessage';
  static const String pdfDocApproverMessage = 'pdf.doc.approverMessage';
  static const String pdfDocFooter = 'pdf.doc.footer';
  static const String pdfDocActionInsert = 'pdf.doc.action.insert';
  static const String pdfDocActionDelete = 'pdf.doc.action.delete';
  static const String pdfDocActionUpdate = 'pdf.doc.action.update';
  static const String pdfDocSystem = 'pdf.doc.system';
  static const String pdfDocFallbackFamily = 'pdf.doc.fallbackFamily';
  // F-61: section 2 — each caregiver's dated account timeline.
  static const String pdfDocSection3 = 'pdf.doc.section3';
  static const String pdfDocCaregiversLead = 'pdf.doc.caregiversLead';
  static const String pdfDocEmptyCaregivers = 'pdf.doc.emptyCaregivers';
  static const String pdfDocTlAdded = 'pdf.doc.tl.added';
  static const String pdfDocTlInvited = 'pdf.doc.tl.invited';
  static const String pdfDocTlAccountCreated = 'pdf.doc.tl.accountCreated';
  static const String pdfDocTlNoAccountYet = 'pdf.doc.tl.noAccountYet';
  static const String pdfDocTlRemoved = 'pdf.doc.tl.removed';
  static const String pdfDocTlLeft = 'pdf.doc.tl.left';

  // ── LGPD export (F-17) ──
  static const String exportLgpdNote = 'export.lgpdNote';
  static const String exportFileNamePrefix = 'export.fileNamePrefix';

  // ── Notification renderer (U-13) ──
  static const String notifRenderTitleAutoReminder = 'notifRender.title.autoReminder';
  static const String notifRenderTitleAutoApproved = 'notifRender.title.autoApproved';
  static const String notifRenderTitleCalendarUpdated = 'notifRender.title.calendarUpdated';
  static const String notifRenderAutoReminder = 'notifRender.autoReminder';
  static const String notifRenderAutoApprovedRequester = 'notifRender.autoApproved.requester';
  static const String notifRenderAutoApprovedApprover = 'notifRender.autoApproved.approver';
  static const String notifRenderFamilyAutoSwap = 'notifRender.family.autoSwap';
  static const String notifRenderFamilyAutoRevert = 'notifRender.family.autoRevert';
  static const String notifRenderMsgSuffix = 'notifRender.msgSuffix';
  static const String notifRenderTagUrgent = 'notifRender.tag.urgent';
  static const String notifRenderTagOverdue = 'notifRender.tag.overdue';
  static const String notifRenderFbOtherCap = 'notifRender.fb.otherCap';
  static const String notifRenderFbOtherThe = 'notifRender.fb.otherThe';
  static const String notifRenderFbOtherLower = 'notifRender.fb.otherLower';
  static const String notifRenderFbPlanned = 'notifRender.fb.planned';
  static const String notifRenderFbSomeone = 'notifRender.fb.someone';

  // ── Swap workflow (written by SwapRequestService) ──
  static const String notifRenderTitleSwapSent = 'notifRender.title.swapSent';
  static const String notifRenderTitleSwapRequested = 'notifRender.title.swapRequested';
  static const String notifRenderTitleSwapApproved = 'notifRender.title.swapApproved';
  static const String notifRenderTitleSwapApprovedSelf = 'notifRender.title.swapApprovedSelf';
  static const String notifRenderTitleSwapRejected = 'notifRender.title.swapRejected';
  static const String notifRenderTitleSwapCancelled = 'notifRender.title.swapCancelled';
  static const String notifRenderTitleRevertSent = 'notifRender.title.revertSent';
  static const String notifRenderTitleRevertRequested = 'notifRender.title.revertRequested';
  static const String notifRenderTitleRevertApproved = 'notifRender.title.revertApproved';
  static const String notifRenderTitleRevertApprovedSelf = 'notifRender.title.revertApprovedSelf';
  static const String notifRenderTitleRevertRejected = 'notifRender.title.revertRejected';
  static const String notifRenderTitleRevertCancelled = 'notifRender.title.revertCancelled';
  static const String notifRenderSwapSent = 'notifRender.swapSent';
  static const String notifRenderSwapRequestedTarget = 'notifRender.swapRequested.target';
  static const String notifRenderSwapRequestedRequester = 'notifRender.swapRequested.requester';
  static const String notifRenderSwapApprovedTarget = 'notifRender.swapApproved.target';
  static const String notifRenderSwapApprovedRequester = 'notifRender.swapApproved.requester';
  static const String notifRenderSwapApprovedSelfTarget = 'notifRender.swapApprovedSelf.target';
  static const String notifRenderSwapApprovedSelfRequester = 'notifRender.swapApprovedSelf.requester';
  static const String notifRenderSwapRejected = 'notifRender.swapRejected';
  static const String notifRenderSwapCancelledByRequester = 'notifRender.swapCancelled.byRequester';
  static const String notifRenderSwapCancelledMemberLeft = 'notifRender.swapCancelled.memberLeft';
  static const String notifRenderRevertSent = 'notifRender.revertSent';
  static const String notifRenderRevertRequested = 'notifRender.revertRequested';
  static const String notifRenderRevertApproved = 'notifRender.revertApproved';
  static const String notifRenderRevertApprovedSelf = 'notifRender.revertApprovedSelf';
  static const String notifRenderRevertRejected = 'notifRender.revertRejected';
  static const String notifRenderRevertCancelled = 'notifRender.revertCancelled';
  static const String notifRenderFamilySwap = 'notifRender.family.swap';
  static const String notifRenderFamilyRevert = 'notifRender.family.revert';

  // ── Membership + account / family deletion (written by DB triggers) ──
  static const String notifRenderTitleMemberJoined = 'notifRender.title.memberJoined';
  static const String notifRenderTitleMemberReturned = 'notifRender.title.memberReturned';
  static const String notifRenderTitleLeaveRequested = 'notifRender.title.leaveRequested';
  static const String notifRenderTitleFamilyDeletionRequested = 'notifRender.title.familyDeletionRequested';
  static const String notifRenderTitleMemberLeft = 'notifRender.title.memberLeft';
  static const String notifRenderTitleFamilyDeletionAnswer = 'notifRender.title.familyDeletionAnswer';
  static const String notifRenderTitleFamilyDeletionCancelled = 'notifRender.title.familyDeletionCancelled';
  static const String notifRenderTitleFamilyDeletionWithdrawn = 'notifRender.title.familyDeletionWithdrawn';
  static const String notifRenderTitleFamilyDeletionNear = 'notifRender.title.familyDeletionNear';
  static const String notifRenderMemberJoined = 'notifRender.memberJoined';
  static const String notifRenderMemberReturned = 'notifRender.memberReturned';
  static const String notifRenderLeaveSelf = 'notifRender.leave.self';
  static const String notifRenderLeaveSelfLast = 'notifRender.leave.selfLast';
  static const String notifRenderLeaveOther = 'notifRender.leave.other';
  static const String notifRenderFamDelRequestedSelf = 'notifRender.famDel.requestedSelf';
  static const String notifRenderFamDelRequestedOther = 'notifRender.famDel.requestedOther';
  static const String notifRenderFamDelAgreed = 'notifRender.famDel.agreed';
  static const String notifRenderFamDelAgreementUndone = 'notifRender.famDel.agreementUndone';
  static const String notifRenderFamDelRefused = 'notifRender.famDel.refused';
  static const String notifRenderFamDelWithdrawn = 'notifRender.famDel.withdrawn';
  static const String notifRenderFamDelReminder = 'notifRender.famDel.reminder';

  // ── E-mail quota (F-38) + billing grace (S-15) ──
  static const String notifRenderTitleEmailCapPremium = 'notifRender.title.emailCapPremium';
  static const String notifRenderTitleEmailCapFree = 'notifRender.title.emailCapFree';
  static const String notifRenderTitleEmailCapLast = 'notifRender.title.emailCapLast';
  static const String notifRenderTitleEmailCap80 = 'notifRender.title.emailCap80';
  static const String notifRenderTitleBillingGrace = 'notifRender.title.billingGrace';
  static const String notifRenderEmailCapPremium = 'notifRender.emailCap.premium';
  static const String notifRenderEmailCapFree = 'notifRender.emailCap.free';
  static const String notifRenderEmailCapLast = 'notifRender.emailCap.last';
  static const String notifRenderEmailCap80 = 'notifRender.emailCap.eighty';
  static const String notifRenderBillingGrace = 'notifRender.billingGrace';

  // ── Notifications page ──
  static const String notifPageTitle = 'notif.pageTitle';
  static const String notifFilterAria = 'notif.filterAria';
  static const String notifTabIncoming = 'notif.tab.incoming';
  static const String notifTabSent = 'notif.tab.sent';
  static const String notifTabHistory = 'notif.tab.history';
  static const String notifEmptyIncoming = 'notif.empty.incoming';
  static const String notifEmptySent = 'notif.empty.sent';
  static const String notifEmptyHistory = 'notif.empty.history';
  static const String notifRevertPendingBadge = 'notif.badge.revertPending';
  static const String notifPendingBadge = 'notif.badge.pending';
  static const String notifLabelRequester = 'notif.label.requester';
  static const String notifLabelRequesterMessage = 'notif.label.requesterMessage';
  static const String notifLabelRevertTo = 'notif.label.revertTo';
  static const String notifLabelProposes = 'notif.label.proposes';
  static const String notifLabelTime = 'notif.label.time';
  static const String notifLabelRequestedAt = 'notif.label.requestedAt';
  static const String notifLabelTo = 'notif.label.to';
  static const String notifLabelProposed = 'notif.label.proposed';
  static const String notifLabelYourMessage = 'notif.label.yourMessage';
  static const String notifLabelApproverMessage = 'notif.label.approverMessage';
  static const String notifResolvedStateTitle = 'notif.resolvedStateTitle';
  static const String notifAutoBadge = 'notif.autoBadge';
  static const String notifAutoBadgeTitle = 'notif.autoBadgeTitle';
  static const String notifStatusPending = 'notif.status.pending';
  static const String notifStatusApproved = 'notif.status.approved';
  static const String notifStatusRejected = 'notif.status.rejected';
  static const String notifStatusCancelled = 'notif.status.cancelled';
  static const String notifStatusReverted = 'notif.status.reverted';
  static const String notifStatusRevertPending = 'notif.status.revertPending';
  static const String notifStatusRevertApproved = 'notif.status.revertApproved';
  static const String notifStatusRevertRejected = 'notif.status.revertRejected';
  static const String notifStatusRevertCancelled = 'notif.status.revertCancelled';
  static const String notifTagOverdueShort = 'notif.tag.overdueShort';
  static const String notifTagUrgentShort = 'notif.tag.urgentShort';
  static const String notifProposesSuffix = 'notif.proposesSuffix';
  static const String notifNotePlaceholder = 'notif.notePlaceholder';
  static const String notifBtnConfirmRevert = 'notif.btn.confirmRevert';
  static const String notifBtnReject = 'notif.btn.reject';
  static const String notifBtnApprove = 'notif.btn.approve';
  static const String notifBtnCancelRevert = 'notif.btn.cancelRevert';
  static const String notifBtnCancelRequest = 'notif.btn.cancelRequest';
  static const String notifErrApprove = 'notif.err.approve';
  static const String notifErrReject = 'notif.err.reject';
  static const String notifErrCancel = 'notif.err.cancel';
  static const String notifErrConfirmRevert = 'notif.err.confirmRevert';
  static const String notifErrRejectRevert = 'notif.err.rejectRevert';
  static const String notifErrCancelRevert = 'notif.err.cancelRevert';

  // ── Reports: period summary ──
  static const String sumPageTitle = 'rep.sum.pageTitle';
  static const String sumSubtitle = 'rep.sum.subtitle';
  static const String repPeriodAria = 'rep.periodAria';
  static const String repByYear = 'rep.byYear';
  static const String repByMonth = 'rep.byMonth';
  static const String repFilter = 'rep.filter';
  static const String sumEmptyTitle = 'rep.sum.emptyTitle';
  static const String sumEmptyBody = 'rep.sum.emptyBody';
  static const String sumPlanned = 'rep.sum.planned';
  static const String sumActual = 'rep.sum.actual';
  static const String sumProjected = 'rep.sum.projected';
  static const String sumGiven = 'rep.sum.given';
  static const String sumReceived = 'rep.sum.received';
  static const String repErrInit = 'rep.err.init';

  // ── Reports: adjustment history ──
  static const String auditPageTitle = 'rep.audit.pageTitle';
  static const String auditSubtitle = 'rep.audit.subtitle';
  static const String famBillingHistoryLoadFailed = 'toast.famBillingHistoryLoadFailed';
  static const String famInterestRegistered = 'toast.famInterestRegistered';
  static const String famSubscriptionCancelled = 'toast.famSubscriptionCancelled';
  static const String famSubscriptionReactivated = 'toast.famSubscriptionReactivated';
  static const String famInviteEmailSent = 'toast.famInviteEmailSent';
  static const String famInviteEmailFailed = 'toast.famInviteEmailFailed';
  static const String famInviteResent = 'toast.famInviteResent';
  static const String famInviteRenewedEmailFailed = 'toast.famInviteRenewedEmailFailed';
  static const String famInviteRevoked = 'toast.famInviteRevoked';
  static const String famLinkCopied = 'toast.famLinkCopied';
  static const String toastSaved = 'toast.toastSaved';
  static const String toastSwapApproved = 'toast.toastSwapApproved';
  static const String toastSwapRejected = 'toast.toastSwapRejected';
  static const String toastDayCleared = 'toast.toastDayCleared';
  static const String profDataUpdated = 'toast.profDataUpdated';
  static const String profPasswordChanged = 'toast.profPasswordChanged';
  static const String repErrorTitle = 'rep.error.title';
  static const String sumFutureToggle = 'rep.sum.futureToggle';
  static const String sumDaysOne = 'rep.sum.daysOne';
  static const String sumDaysMany = 'rep.sum.daysMany';
  static const String sumTotalSwaps = 'rep.sum.totalSwaps';
  static const String sumTotalSwapsProjected = 'rep.sum.totalSwapsProjected';
  static const String auditTabRecent = 'rep.audit.tabRecent';
  static const String auditTabAccount = 'rep.audit.tabAccount';
  static const String auditEmptyAccountTitle = 'rep.audit.emptyAccountTitle';
  static const String auditEmptyAccountBody = 'rep.audit.emptyAccountBody';
  static const String auditEmptyTitle = 'rep.audit.emptyTitle';
  static const String auditEmptyBody = 'rep.audit.emptyBody';
  static const String auditRequesterMessage = 'rep.audit.requesterMessage';
  static const String auditApproverMessage = 'rep.audit.approverMessage';
  static const String auditLoadingMore = 'rep.audit.loadingMore';
  static const String auditLoadMore = 'rep.audit.loadMore';
  static const String auditErrLoad = 'rep.audit.errLoad';
  /// U-28: the Resumo and Histórico tabs name themselves the way the PDF tab
  /// already did (`pdfHeading`). Without a heading, a description scrolled
  /// halfway up read as an orphan sentence under the tab strip.
  static const String sumHeading = 'sum.heading';
  static const String auditHeading = 'audit.heading';

  static const String repTabSummary = 'rep.tab.summary';
  static const String repTabHistory = 'rep.tab.history';
  static const String repTabPdf = 'rep.tab.pdf';
  static const String repTabsAria = 'rep.tabsAria';
  static const String auditSystemActor = 'rep.audit.systemActor';
  static const String auditSystemTrigger = 'rep.audit.systemTrigger';
  static const String auditCreatedSchedule = 'rep.audit.createdSchedule';
  static const String auditDeletedSchedule = 'rep.audit.deletedSchedule';
  static const String auditUpdatedSchedule = 'rep.audit.updatedSchedule';
  static const String auditErrLoadMore = 'rep.audit.errLoadMore';
  static const String sumErrProcess = 'rep.sum.errProcess';

  // ── Profile page ──
  static const String profPageTitle = 'prof.pageTitle';
  static const String profNotFound = 'prof.notFound';
  static const String profFrozenBanner = 'prof.frozenBanner';
  static const String profSectionData = 'prof.section.data';
  static const String profSaveData = 'prof.saveData';
  static const String profSectionAdmin = 'prof.section.admin';
  static const String profIsAdmin = 'prof.isAdmin';
  static const String profIsNotAdmin = 'prof.isNotAdmin';
  static const String profRemoveAdmin = 'prof.removeAdmin';
  static const String profMakeAdmin = 'prof.makeAdmin';
  static const String profSendPasswordReset = 'prof.sendPasswordReset';
  static const String profPersonalHint = 'prof.personalHint';
  static const String profSectionEmail = 'prof.section.email';
  static const String profCurrentEmail = 'prof.currentEmail';
  static const String profNewEmail = 'prof.newEmail';
  static const String profNewEmailPlaceholder = 'prof.newEmailPlaceholder';
  static const String profEmailLinkSent = 'prof.emailLinkSent';
  static const String profChangeEmail = 'prof.changeEmail';
  static const String profSectionPassword = 'prof.section.password';
  static const String profNewPasswordPlaceholder = 'prof.newPasswordPlaceholder';
  static const String profConfirmNewPassword = 'prof.confirmNewPassword';
  static const String profConfirmNewPasswordPlaceholder = 'prof.confirmNewPasswordPlaceholder';
  static const String profChangePassword = 'prof.changePassword';
  static const String profForgotCurrent = 'prof.forgotCurrent';
  static const String profPasswordLinkSentTo = 'prof.passwordLinkSentTo';
  static const String profResetByEmail = 'prof.resetByEmail';
  static const String profSectionLgpd = 'prof.section.lgpd';
  static const String profExportHint = 'prof.exportHint';
  static const String profExportAction = 'prof.exportAction';
  static const String profLeaveTitleLast = 'prof.leave.titleLast';
  static const String profLeaveTitle = 'prof.leave.title';
  static const String profLeaveLastIntro = 'prof.leave.lastIntro';
  static const String profLeaveLastConsequenceData = 'prof.leave.lastConsequenceData';
  static const String profLeaveLastConsequenceCancel = 'prof.leave.lastConsequenceCancel';
  static const String profLeaveIntro = 'prof.leave.intro';
  static const String profLeaveConsequenceAccount = 'prof.leave.consequenceAccount';
  static const String profLeaveConsequenceDays = 'prof.leave.consequenceDays';
  static const String profLeaveConsequenceHistory = 'prof.leave.consequenceHistory';
  static const String profLeaveConsequenceNotice = 'prof.leave.consequenceNotice';
  static const String profLeaveConsequenceSuccessor = 'prof.leave.consequenceSuccessor';
  static const String profSuccessorLabel = 'prof.successorLabel';
  static const String profSuccessorPlaceholder = 'prof.successorPlaceholder';
  static const String profLeaveBlocked = 'prof.leave.blocked';
  static const String profFamilyPageLink = 'prof.familyPageLink';
  static const String profLeaveOpenLast = 'prof.leave.openLast';
  static const String profLeaveOpen = 'prof.leave.open';
  static const String profLeaveConfirmTextLast = 'prof.leave.confirmTextLast';
  static const String profLeaveConfirmText = 'prof.leave.confirmText';
  static const String profLeaveConfirmLast = 'prof.leave.confirmLast';
  static const String profLeaveConfirm = 'prof.leave.confirm';
  static const String profLeaveKeepFamily = 'prof.leave.keepFamily';
  static const String profLeaveKeepAccount = 'prof.leave.keepAccount';
  static const String profErrSaveData = 'prof.err.saveData';
  static const String profToastNowAdmin = 'prof.toast.nowAdmin';
  static const String profToastNoLongerAdmin = 'prof.toast.noLongerAdmin';
  static const String profToastResetSentTo = 'prof.toast.resetSentTo';
  static const String profErrSendEmail = 'prof.err.sendEmail';
  static const String profErrInvalidEmail = 'prof.err.invalidEmail';
  static const String profErrSameEmail = 'prof.err.sameEmail';
  static const String profErrPasswordMismatch = 'prof.err.passwordMismatch';
  static const String profToastExported = 'prof.toast.exported';
  static const String profErrExport = 'prof.err.export';

  // ── Payment return (F-43) ──
  static const String payPageTitle = 'pay.pageTitle';
  static const String payActiveTitle = 'pay.activeTitle';
  static const String payBackToFamily = 'pay.backToFamily';
  static const String payAlmostTitle = 'pay.almostTitle';
  static const String payConfirmingTitle = 'pay.confirmingTitle';
  static const String payConfirmingBody = 'pay.confirmingBody';
  static const String payActiveBody = 'pay.activeBody';
  static const String payGuarantee = 'pay.guarantee';
  static const String payAlmostBody = 'pay.almostBody';
  static const String payAlmostHint = 'pay.almostHint';

  // ── Re-consent gate (S-15/B-4) ──
  static const String policyPageTitle = 'policy.pageTitle';
  static const String policyHeading = 'policy.heading';
  static const String policyIntro = 'policy.intro';
  static const String policyWhatChanged = 'policy.whatChanged';
  static const String policyReadInFull = 'policy.readInFull';
  static const String policyAcceptUpdated = 'policy.acceptUpdated';
  static const String policyRegistering = 'policy.registering';
  static const String policyAcceptAndContinue = 'policy.acceptAndContinue';
  static const String policyDeclinePrefix = 'policy.declinePrefix';
  static const String policyDeclineSignOut = 'policy.declineSignOut';
  static const String policyDeclineSuffix = 'policy.declineSuffix';
  static const String policyErrNoSession = 'policy.err.noSession';
  static const String policyErrProfileLoad = 'policy.err.profileLoad';
  static const String policyErrProfileLoadRetry = 'policy.err.profileLoadRetry';
  static const String policyToastAccepted = 'policy.toast.accepted';

  // ── Leaving screen (S-11) ──
  static const String leavePageTitle = 'leave.pageTitle';
  static const String leaveFamilyRemovalTitle = 'leave.familyRemovalTitle';
  static const String leaveTitle = 'leave.title';
  static const String leaveNonePending = 'leave.nonePending';
  static const String leaveBackToApp = 'leave.backToApp';
  static const String leaveFamilyRemovalText = 'leave.familyRemovalText';
  static const String leaveAccountText = 'leave.accountText';
  static const String leaveChangedMind = 'leave.changedMind';
  static const String leaveIn30Days = 'leave.in30Days';
  static const String leaveCancelAndReturn = 'leave.cancelAndReturn';
  static const String leaveSignOut = 'leave.signOut';
  static const String leaveToastCancelled = 'leave.toast.cancelled';

  // ── Custom roles page (F-41) ──
  static const String rolesPageTitle = 'roles.pageTitle';
  static const String rolesBackToFamily = 'roles.backToFamily';
  static const String rolesHeading = 'roles.heading';
  static const String rolesIntro = 'roles.intro';
  static const String rolesDeleteConfirm = 'roles.deleteConfirm';
  static const String rolesYes = 'roles.yes';
  static const String rolesNo = 'roles.no';
  static const String rolesEditRole = 'roles.editRole';
  static const String rolesDeleteRole = 'roles.deleteRole';
  static const String rolesEmpty = 'roles.empty';
  static const String rolesNameLabel = 'roles.nameLabel';
  static const String rolesNamePlaceholder = 'roles.namePlaceholder';
  static const String rolesEmojiLabel = 'roles.emojiLabel';
  static const String rolesSaving = 'roles.saving';
  static const String rolesCreate = 'roles.create';
  static const String rolesSaveEdit = 'roles.saveEdit';
  static const String rolesPremiumGate = 'roles.premiumGate';
  static const String rolesToastCreated = 'roles.toast.created';

  // ── Sudo prompt ──
  static const String sudoTitle = 'sudo.title';
  static const String sudoHint = 'sudo.hint';
  static const String sudoCurrentPassword = 'sudo.currentPassword';
  static const String sudoConfirm = 'sudo.confirm';
  static const String sudoForgot = 'sudo.forgot';

  // ── Not found ──
  static const String notFoundTitle = 'notFound.title';
  static const String notFoundBody = 'notFound.body';
  static const String notFoundBack = 'notFound.back';

  // ── Authentication errors (AuthService) ──
  static const String authErrSignInFailed = 'auth.err.signInFailed';
  static const String authErrRateLimited = 'auth.err.rateLimited';
  static const String authErrRateLimitedReset = 'auth.err.rateLimitedReset';
  static const String authErrConnection = 'auth.err.connection';
  static const String authErrMissingConfig = 'auth.err.missingConfig';
  static const String authErrSignUpFailed = 'auth.err.signUpFailed';
  static const String authErrInvalidCredentials = 'auth.err.invalidCredentials';
  static const String authErrEmailNotConfirmed = 'auth.err.emailNotConfirmed';
  static const String authErrGeneric = 'auth.err.generic';
  static const String authErrAlreadyRegistered = 'auth.err.alreadyRegistered';
  static const String authErrPasswordWeak = 'auth.err.passwordWeak';
  static const String authErrEmailFormat = 'auth.err.emailFormat';
  static const String authErrDatabaseSignUp = 'auth.err.databaseSignUp';
  static const String authErrSignUpGeneric = 'auth.err.signUpGeneric';
  static const String authErrResetSend = 'auth.err.resetSend';
  static const String authErrPasswordUpdate = 'auth.err.passwordUpdate';
  static const String authErrEmailInUse = 'auth.err.emailInUse';
  static const String authErrEmailInvalid = 'auth.err.emailInvalid';
  static const String authErrEmailChange = 'auth.err.emailChange';

  // ── First-run onboarding (U-23) ──
  static const String onbChecklistTitle = 'onb.checklist.title';
  static const String onbChecklistIntro = 'onb.checklist.intro';
  static const String onbChecklistProgress = 'onb.checklist.progress';
  static const String onbChecklistDismiss = 'onb.checklist.dismiss';
  static const String onbChecklistDismissAria = 'onb.checklist.dismissAria';
  static const String onbLauncherOpenAria = 'onb.launcher.openAria';
  static const String onbChecklistReopen = 'onb.checklist.reopen';
  static const String onbChecklistReopenHint = 'onb.checklist.reopenHint';
  static const String onbStepDone = 'onb.step.done';
  static const String onbStepTodo = 'onb.step.todo';
  static const String onbStepInviteTitle = 'onb.step.invite.title';
  static const String onbStepInviteHint = 'onb.step.invite.hint';
  static const String onbStepInviteDoneHint = 'onb.step.invite.doneHint';
  static const String onbStepInviteAction = 'onb.step.invite.action';
  static const String onbStepPlanTitle = 'onb.step.plan.title';
  static const String onbStepPlanHint = 'onb.step.plan.hint';
  static const String onbStepPlanDoneHint = 'onb.step.plan.doneHint';
  static const String onbStepPlanAction = 'onb.step.plan.action';
  static const String onbStepSwapTitle = 'onb.step.swap.title';
  static const String onbStepSwapHint = 'onb.step.swap.hint';
  static const String onbStepSwapDoneHint = 'onb.step.swap.doneHint';
  static const String onbStepSwapAction = 'onb.step.swap.action';

  // ── "Como funciona a troca" explanation (U-23) ──
  static const String onbSwapSheetTitle = 'onb.swapSheet.title';
  static const String onbSwapSheetIntro = 'onb.swapSheet.intro';
  static const String onbSwapPlannedTitle = 'onb.swapSheet.planned.title';
  static const String onbSwapPlannedBody = 'onb.swapSheet.planned.body';
  static const String onbSwapApprovalTitle = 'onb.swapSheet.approval.title';
  static const String onbSwapApprovalBody = 'onb.swapSheet.approval.body';
  static const String onbSwapFrozenTitle = 'onb.swapSheet.frozen.title';
  static const String onbSwapFrozenBody = 'onb.swapSheet.frozen.body';
  static const String onbSwapHistoryTitle = 'onb.swapSheet.history.title';
  static const String onbSwapHistoryBody = 'onb.swapSheet.history.body';
  static const String onbSwapSheetGotIt = 'onb.swapSheet.gotIt';
  static const String onbChecklistReplayTour = 'onb.checklist.replayTour';

  // ── Guided tour (U-23) ──
  static const String tourAriaLabel = 'tour.ariaLabel';
  static const String tourProgress = 'tour.progress';
  static const String tourPrevious = 'tour.previous';
  static const String tourNext = 'tour.next';
  static const String tourFinish = 'tour.finish';
  static const String tourSkip = 'tour.skip';
  static const String tourTodayTitle = 'tour.today.title';
  static const String tourTodayBody = 'tour.today.body';
  static const String tourColoursTitle = 'tour.colours.title';
  static const String tourColoursBody = 'tour.colours.body';
  static const String tourWizardTitle = 'tour.wizard.title';
  static const String tourWizardBody = 'tour.wizard.body';
  static const String tourNotificationsTitle = 'tour.notifications.title';
  static const String tourNotificationsBody = 'tour.notifications.body';

  /// Every declared key, in declaration order — the Dart stand-in for the
  /// C# reflection scan in `LocalizationTests.DeclaredKeys()`. The parity
  /// tests iterate this list; the generator keeps it complete by construction.
  static const List<String> allKeys = [
    commonCancel,
    commonClose,
    commonPrivacyPolicy,
    commonTermsOfUse,
    commonEmail,
    commonEmailPlaceholder,
    commonPassword,
    commonConfirmPassword,
    languageLabel,
    languageAriaLabel,
    languagePtBr,
    languageEn,
    languageHint,
    splashTagline,
    loginPageTitle,
    loginHeading,
    loginSubtitle,
    loginPasswordPlaceholder,
    loginSubmit,
    loginSubmitting,
    loginLockout,
    loginForgot,
    loginSignupCta,
    loginSignupLink,
    loginDismissNotice,
    loginExpiredInactivity,
    loginExpiredToken,
    loginExpiredFamilyDeleted,
    registerPageTitle,
    registerCheckingInvite,
    registerInviteInvalidTitle,
    registerInviteInvalidBody,
    registerBackToLogin,
    registerConfirmEmailTitle,
    registerConfirmEmailSentTo,
    registerConfirmEmailBody,
    registerGoToLogin,
    registerInvitedTitle,
    registerInvitedBody,
    registerCreateTitle,
    registerCreateSubtitle,
    registerFullName,
    registerFullNamePlaceholder,
    registerFamilyName,
    registerFamilyNamePlaceholder,
    registerFamilyNameHint,
    registerYouAre,
    registerPasswordPlaceholder,
    registerConfirmPasswordPlaceholder,
    registerConsentAccept,
    registerConsentAnd,
    registerConsentBindingNotice,
    registerSubmit,
    registerSubmitting,
    registerHaveAccount,
    registerMigrationTitle,
    registerMigrationBody1,
    registerMigrationBody2,
    registerMigrationConfirm,
    registerMigrationConfirming,
    registerErrorNameRequired,
    registerErrorEmailRequired,
    registerErrorFamilyRequired,
    registerErrorRoleRequired,
    registerErrorPasswordShort,
    registerErrorPasswordMismatch,
    registerErrorConsentRequired,
    resetPageTitle,
    resetTitle,
    resetSubtitle,
    resetSubmit,
    resetSentTitle,
    resetSentBody,
    resetBackToLogin,
    updatePwdPageTitle,
    updatePwdDoneTitle,
    updatePwdDoneBody,
    updatePwdGoToCalendar,
    updatePwdTitle,
    updatePwdSubtitle,
    updatePwdNewPassword,
    updatePwdNewPasswordPlaceholder,
    updatePwdConfirmPlaceholder,
    updatePwdSubmit,
    updatePwdErrorSession,
    updatePwdErrorShort,
    updatePwdErrorMismatch,
    navCalendar,
    navFamily,
    navNotifications,
    navNotificationsShort,
    navNotificationsOnePending,
    navNotificationsManyPending,
    navReports,
    navLogout,
    commonOptional,
    commonShowPassword,
    commonHidePassword,
    wizBlockParentLabel,
    navAccount,
    navProfile,
    navAdmin,
    navAdminEnter,
    navAdminExit,
    layoutAdminActive,
    layoutAdminHint,
    layoutAdminExit,
    layoutPolicyNoticeTitle,
    layoutPolicyNoticeHint,
    layoutFamilyDeletionConfirmed,
    layoutFamilyDeletionConfirmedUntil,
    layoutFamilyDeletionRequested,
    layoutFamilyDeletionRequester,
    layoutFamilyDeletionOther,
    layoutErrorTitle,
    layoutErrorBody,
    layoutErrorReload,
    layoutInstallTitle,
    layoutInstallHint,
    layoutInstallAction,
    layoutInstallDismiss,
    layoutInstallIosTitle,
    layoutInstallIosTapOn,
    layoutInstallIosShare,
    layoutInstallIosThen,
    layoutInstallIosAddToHome,
    homeSystemAlert,
    homeBackToLogin,
    homeNotDefined,
    homeTapToDefine,
    calToday,
    calPrevMonth,
    calNextMonth,
    calSelectDays,
    calWizard,
    calAriaCalendarOf,
    calMemberLeft,
    calSwapped,
    calWeekdayInitials,
    calOverdueAwaitingYou,
    calAwaitingYou,
    calAwaitingFrom,
    calOtherCaregiver,
    calEmptyTitle,
    calEmptyHint,
    calAriaToday,
    calAriaNoResponsible,
    calAriaResponsible,
    calAriaNotDefined,
    calAriaSwapDone,
    calAriaHandoffAt,
    calAriaRequestAwaitingYou,
    calAriaRequestPending,
    calAriaSelected,
    selectionResolve,
    selectionEdit,
    selectionCancel,
    navGuardSelectedOne,
    navGuardSelectedMany,
    navGuardBody,
    navGuardYes,
    navGuardNo,
    cardBackToCurrentMonth,
    cardGreeting,
    cardInviteTitle,
    cardInviteHint,
    cardInviteAction,
    cardResponsibleToday,
    cardNextHandoff,
    cardSwappedBadge,
    cardNoResponsibleTitle,
    cardNoResponsibleHint,
    relDaysAgo,
    relYesterday,
    relToday,
    relTomorrow,
    relInDays,
    editorAriaLabel,
    editorTitle,
    editorAdminOverride,
    editorPastReadonly,
    editorFrozenReadonly,
    editorScheduledParent,
    editorScheduledParentHint,
    editorActualParentHint,
    editorSelectPlaceholder,
    editorLockedHint,
    editorActualParent,
    editorSameAsPlanned,
    editorDayNote,
    editorDayNoteHint,
    editorDayNotePlaceholder,
    editorHandoffTime,
    editorHandoffHint,
    editorHandoffEmpty,
    editorHandoffClear,
    editorNoTransitionHint,
    editorMessageLabel,
    editorMessagePlaceholder,
    editorWorkflowHint,
    editorAdminChangeWarning,
    editorYesChange,
    editorNoGoBack,
    editorRevertNotesQuestion,
    editorRevertNotesCurrent,
    editorRevertNotesBefore,
    editorNoNote,
    editorKeepCurrent,
    editorRestorePrevious,
    editorClearDay,
    commonSave,
    bulkAriaLabel,
    bulkTitleOne,
    bulkTitleMany,
    bulkDeleteAllWarning,
    bulkYesDelete,
    bulkClearDaysAction,
    bulkClearDaysTitle,
    bulkKeptScheduledOne,
    bulkKeptScheduledMany,
    bulkClear,
    bulkNotePlaceholder,
    bulkMessageHint,
    bulkMessagePlaceholder,
    bulkOverwriteWarningOne,
    bulkOverwriteWarningMany,
    bulkErrNoEligibleDays,
    bulkErrPickScheduled,
    bulkConflictSuffixOne,
    bulkConflictSuffixMany,
    bulkHandoffSuffix,
    bulkKeptSuffixOne,
    bulkKeptSuffixMany,
    wfAriaLabel,
    wfTitle,
    wfAwaitingYou,
    wfMessage,
    wfRejectHint,
    wfRejectPlaceholder,
    wfApprove,
    wfReject,
    wfSentByYouOne,
    wfSentByYouMany,
    wfCancel,
    wfApprovedSwaps,
    wfRequestRevert,
    wfClose,
    frozenRevertTitle,
    frozenSwapTitle,
    frozenUrgent,
    frozenOverdue,
    frozenDay,
    frozenRequester,
    frozenRevertTo,
    frozenProposedParent,
    frozenProposedTime,
    frozenRequesterMessage,
    frozenRequestedAt,
    frozenNoteLabel,
    frozenNoteHint,
    frozenNotePlaceholder,
    frozenConfirmRevert,
    frozenApprove,
    frozenRejectAction,
    frozenCancelRevert,
    frozenCancelRequest,
    frozenObserver,
    wizTitle,
    wizSubtitle,
    wizClose,
    wizPreset,
    wizPresetCustom,
    wizPreset77,
    wizPreset1414,
    wizPreset11,
    wizPreset5225,
    wizPreset223,
    wizCycleBlocks,
    wizBlockParent,
    wizDays,
    wizRemoveBlock,
    wizAddBlock,
    wizStartDate,
    wizDuration,
    wizMonthsOne,
    wizMonthsMany,
    wizHandoffTime,
    wizHandoffHint,
    wizCyclePreview,
    wizGenerate,
    wizCycleSummary,
    wizErrPickParentPerBlock,
    wizErrStartInPast,
    wizErrStartBeyondFree,
    wizErrStartBeyondMax,
    wizErrGenerate,
    wizErrToast,
    wizDoneCreated,
    wizDoneKept,
    wizDoneClampedFree,
    wizDoneClampedMax,
    sumSwapRequestOne,
    sumSwapRequestMany,
    sumRevertOne,
    sumRevertMany,
    sumUnchangedOne,
    sumUnchangedMany,
    sumSkippedOne,
    sumSkippedMany,
    sumNothingToDo,
    sumUpdatedOne,
    sumUpdatedMany,
    sumIgnoredOne,
    sumIgnoredMany,
    sumApprovedOne,
    sumApprovedMany,
    sumRejectedOne,
    sumRejectedMany,
    sumCancelledOne,
    sumCancelledMany,
    sumDeletedOne,
    sumDeletedMany,
    bulkProgressDeleting,
    toastRevertRequested,
    toastSwapRequested,
    toastRequestCancelled,
    toastRevertConfirmed,
    toastRevertRejected,
    toastRevertCancelled,
    errProfileNotFound,
    errConnection,
    errPastDay,
    errFrozenDay,
    errStaleClient,
    errConcurrentSave,
    errSaveFailed,
    errDeleteFailed,
    errApproveFailed,
    errRejectFailed,
    errCancelFailed,
    errConfirmRevertFailed,
    errRejectRevertFailed,
    errCancelRevertFailed,
    errBulkWorkflowFailed,
    horizonPremium,
    horizonFree,
    famPageTitle,
    famHeading,
    famRename,
    famLoading,
    famCaregivers,
    famOpenProfileOf,
    famYou,
    famLeftBadge,
    famAdminBadge,
    famInviteSection,
    famOnlyAdminsInvite,
    famInviteExpiredBadge,
    famInviteSentBadge,
    famInviteValidUntil,
    famCopyInviteLink,
    famCopyLink,
    famInviteWhatsapp,
    famInviteExpiredHint,
    famSending,
    famResendInvite,
    famRevoke,
    famFreeCapNotice,
    famSeePremium,
    famInviteWhoHelps,
    famInviteEmailPlaceholder,
    famRoleInFamily,
    famCustomRolesLink,
    famSendInvite,
    famSeatsFull,
    famAdminSection,
    famAdminActiveNote,
    famAdminInactiveNote,
    famAdminTierPremium,
    famAdminTierFree,
    famActivatePremiumLink,
    famAdminDeactivate,
    famAdminActivate,
    premTitle,
    premBadgeTrialOne,
    premBadgeTrialMany,
    premBadgeTrialUntil,
    premBadgeForever,
    premBadgeActive,
    premBadgeFree,
    premExpiredTrial,
    premExpiredPaid,
    premIntro,
    premIntroWaitlist,
    premIntroOffer,
    premFeatureCaregivers,
    premFeatureHorizon,
    premFeaturePdf,
    premFeatureAdminMode,
    premFeatureRoles,
    premCycleMonthly,
    premCycleAnnual,
    premMethodPix,
    premMethodCard,
    premMethodBoleto,
    premForeverNote,
    premActiveStatus,
    premActiveRenews,
    premCancelWarning,
    premCancelWarningUntil,
    premCancelConfirm,
    premCancelKeep,
    premCancelButton,
    premOverdueGraceEnded,
    premOverdueInGrace,
    premOverdueInGraceNoDate,
    premScheduledStatus,
    premScheduledDetail,
    premScheduledDetailMethod,
    premScheduledCancelWarning,
    premScheduledCancelKeep,
    premScheduledCancelButton,
    premStorePaidUntilAvulso,
    premStorePaidUntilPeriod,
    premStoreTrialUntil,
    premStoreNote,
    premPaidUntilAvulso,
    premPaidUntilPeriod,
    premExpiringSoonOne,
    premExpiringSoonMany,
    premTrialAdditive,
    premReactivateButton,
    premReactivateHint,
    premReactivateHintDate,
    premReactivateHintMethod,
    premReactivateHintMethodDate,
    premSubscribeMonthly,
    premSubscribeAnnual,
    premAvulsoLead,
    premAvulsoMonthly,
    premAvulsoAnnual,
    premPaymentHint,
    premGuarantee,
    premAdminOnly,
    premInterestDone,
    premInterestKeepTrial,
    premInterestWant,
    premInterestHint,
    premHistoryToggle,
    premHistoryLoading,
    premHistoryEmpty,
    premHistoryReceipt,
    premHistoryPayment,
    premHistoryRefund,
    premHistoryOverdue,
    premHistoryCanceled,
    premHistoryDowngraded,
    premHistoryOther,
    famDelTitle,
    famDelAllAgreed,
    famDelAllAgreedAdmin,
    famDelAllAgreedMember,
    famDelRequested,
    famDelConsequenceSilence,
    famDelConsequenceUnanimity,
    famDelConsequenceBlocked,
    famDelConsequenceExport,
    famDelVoteAgreed,
    famDelVoteRefused,
    famDelVoteWaiting,
    famDelWithdraw,
    famDelRefuseKeep,
    famDelUndoAgreement,
    famDelAgree,
    famDelExecuteNowOpen,
    famDelExecuteConfirmText,
    famDelExecuteNow,
    famDelBack,
    famDelReqTitle,
    famDelReqIntro,
    famDelReqConsequenceData,
    famDelReqConsequenceNotice,
    famDelReqConsequenceUnanimity,
    famDelReqConsequenceWithdraw,
    famDelReqOpen,
    famDelReqConfirmText,
    famDelReqConfirm,
    famDelReqKeep,
    famRequesterFallback,
    famToastDeletionRequested,
    famToastAgreed,
    famToastRefused,
    famToastAgreementUndone,
    famToastWithdrawn,
    famProgressDeleting,
    famErrInvalidEmail,
    famErrOwnEmail,
    famErrResendInvite,
    famErrFamilyNameRequired,
    famToastRenamed,
    famErrCopy,
    auditFieldScheduledParent,
    auditFieldActualParent,
    auditFieldHandoffTime,
    auditFieldDayNote,
    auditActionAdminGranted,
    auditActionAdminRevoked,
    auditActionRoleChanged,
    auditActionNameChanged,
    auditActionEmailChanged,
    auditActionFamilyRenamed,
    auditActionInvitationCreated,
    auditActionInvitationRevoked,
    auditActionInvitationAccepted,
    auditActionLeaveRequested,
    auditActionLeaveCancelled,
    auditActionPasswordChanged,
    auditActionEmailChangeRequested,
    auditActionDataExported,
    auditActionCompGranted,
    auditActionCompRevoked,
    auditActionPlanPremiumPayment,
    auditActionPlanPremiumAvulso,
    auditActionPlanPremiumSet,
    auditActionPlanFreeOverdue,
    auditActionPlanFreeCanceled,
    auditActionPlanFreeSet,
    auditTrialEnded,
    auditDayLabel,
    auditScheduleChange,
    auditOriginSwapManual,
    auditOriginSwapAuto,
    auditOriginRevertManual,
    auditOriginRevertAuto,
    auditOriginSomeCaregiver,
    auditOriginOtherCaregiver,
    auditAuthorshipNoAccount,
    auditAuthorshipAdminOverride,
    pdfPageTitle,
    pdfHeading,
    pdfSubtitle,
    pdfLoading,
    pdfUpsellBadge,
    pdfUpsellTitle,
    pdfUpsellText,
    pdfUpsellButton,
    pdfPeriodAria,
    pdfByMonth,
    pdfByYear,
    pdfCustom,
    pdfFrom,
    pdfTo,
    pdfChildName,
    pdfChildOptional,
    pdfChildPlaceholder,
    pdfIncludeFutureSwaps,
    pdfGenerate,
    pdfGenerating,
    pdfPrintButton,
    pdfPrintHint,
    pdfErrEndBeforeStart,
    pdfErrLoad,
    pdfErrGenerate,
    pdfErrPrint,
    pdfDocTitle,
    pdfDocSubtitle,
    pdfDocFamily,
    pdfDocChild,
    pdfDocPeriod,
    pdfDocPeriodValue,
    pdfDocCriterion,
    pdfDocCriterionValue,
    pdfDocGeneratedAt,
    pdfDocGeneratedBy,
    pdfDocImmutability,
    pdfDocSection1,
    pdfDocSection2,
    pdfDocEmptySummary,
    pdfDocEmptyHistory,
    pdfDocColCaregiver,
    pdfDocColRole,
    pdfDocColPlanned,
    pdfDocColActual,
    pdfDocColProjected,
    pdfDocColSwaps,
    pdfDocTotalSwaps,
    pdfDocTotalSwapsFuture,
    pdfDocRequesterMessage,
    pdfDocApproverMessage,
    pdfDocFooter,
    pdfDocActionInsert,
    pdfDocActionDelete,
    pdfDocActionUpdate,
    pdfDocSystem,
    pdfDocFallbackFamily,
    pdfDocSection3,
    pdfDocCaregiversLead,
    pdfDocEmptyCaregivers,
    pdfDocTlAdded,
    pdfDocTlInvited,
    pdfDocTlAccountCreated,
    pdfDocTlNoAccountYet,
    pdfDocTlRemoved,
    pdfDocTlLeft,
    exportLgpdNote,
    exportFileNamePrefix,
    notifRenderTitleAutoReminder,
    notifRenderTitleAutoApproved,
    notifRenderTitleCalendarUpdated,
    notifRenderAutoReminder,
    notifRenderAutoApprovedRequester,
    notifRenderAutoApprovedApprover,
    notifRenderFamilyAutoSwap,
    notifRenderFamilyAutoRevert,
    notifRenderMsgSuffix,
    notifRenderTagUrgent,
    notifRenderTagOverdue,
    notifRenderFbOtherCap,
    notifRenderFbOtherThe,
    notifRenderFbOtherLower,
    notifRenderFbPlanned,
    notifRenderFbSomeone,
    notifRenderTitleSwapSent,
    notifRenderTitleSwapRequested,
    notifRenderTitleSwapApproved,
    notifRenderTitleSwapApprovedSelf,
    notifRenderTitleSwapRejected,
    notifRenderTitleSwapCancelled,
    notifRenderTitleRevertSent,
    notifRenderTitleRevertRequested,
    notifRenderTitleRevertApproved,
    notifRenderTitleRevertApprovedSelf,
    notifRenderTitleRevertRejected,
    notifRenderTitleRevertCancelled,
    notifRenderSwapSent,
    notifRenderSwapRequestedTarget,
    notifRenderSwapRequestedRequester,
    notifRenderSwapApprovedTarget,
    notifRenderSwapApprovedRequester,
    notifRenderSwapApprovedSelfTarget,
    notifRenderSwapApprovedSelfRequester,
    notifRenderSwapRejected,
    notifRenderSwapCancelledByRequester,
    notifRenderSwapCancelledMemberLeft,
    notifRenderRevertSent,
    notifRenderRevertRequested,
    notifRenderRevertApproved,
    notifRenderRevertApprovedSelf,
    notifRenderRevertRejected,
    notifRenderRevertCancelled,
    notifRenderFamilySwap,
    notifRenderFamilyRevert,
    notifRenderTitleMemberJoined,
    notifRenderTitleMemberReturned,
    notifRenderTitleLeaveRequested,
    notifRenderTitleFamilyDeletionRequested,
    notifRenderTitleMemberLeft,
    notifRenderTitleFamilyDeletionAnswer,
    notifRenderTitleFamilyDeletionCancelled,
    notifRenderTitleFamilyDeletionWithdrawn,
    notifRenderTitleFamilyDeletionNear,
    notifRenderMemberJoined,
    notifRenderMemberReturned,
    notifRenderLeaveSelf,
    notifRenderLeaveSelfLast,
    notifRenderLeaveOther,
    notifRenderFamDelRequestedSelf,
    notifRenderFamDelRequestedOther,
    notifRenderFamDelAgreed,
    notifRenderFamDelAgreementUndone,
    notifRenderFamDelRefused,
    notifRenderFamDelWithdrawn,
    notifRenderFamDelReminder,
    notifRenderTitleEmailCapPremium,
    notifRenderTitleEmailCapFree,
    notifRenderTitleEmailCapLast,
    notifRenderTitleEmailCap80,
    notifRenderTitleBillingGrace,
    notifRenderEmailCapPremium,
    notifRenderEmailCapFree,
    notifRenderEmailCapLast,
    notifRenderEmailCap80,
    notifRenderBillingGrace,
    notifPageTitle,
    notifFilterAria,
    notifTabIncoming,
    notifTabSent,
    notifTabHistory,
    notifEmptyIncoming,
    notifEmptySent,
    notifEmptyHistory,
    notifRevertPendingBadge,
    notifPendingBadge,
    notifLabelRequester,
    notifLabelRequesterMessage,
    notifLabelRevertTo,
    notifLabelProposes,
    notifLabelTime,
    notifLabelRequestedAt,
    notifLabelTo,
    notifLabelProposed,
    notifLabelYourMessage,
    notifLabelApproverMessage,
    notifResolvedStateTitle,
    notifAutoBadge,
    notifAutoBadgeTitle,
    notifStatusPending,
    notifStatusApproved,
    notifStatusRejected,
    notifStatusCancelled,
    notifStatusReverted,
    notifStatusRevertPending,
    notifStatusRevertApproved,
    notifStatusRevertRejected,
    notifStatusRevertCancelled,
    notifTagOverdueShort,
    notifTagUrgentShort,
    notifProposesSuffix,
    notifNotePlaceholder,
    notifBtnConfirmRevert,
    notifBtnReject,
    notifBtnApprove,
    notifBtnCancelRevert,
    notifBtnCancelRequest,
    notifErrApprove,
    notifErrReject,
    notifErrCancel,
    notifErrConfirmRevert,
    notifErrRejectRevert,
    notifErrCancelRevert,
    sumPageTitle,
    sumSubtitle,
    repPeriodAria,
    repByYear,
    repByMonth,
    repFilter,
    sumEmptyTitle,
    sumEmptyBody,
    sumPlanned,
    sumActual,
    sumProjected,
    sumGiven,
    sumReceived,
    repErrInit,
    auditPageTitle,
    auditSubtitle,
    famBillingHistoryLoadFailed,
    famInterestRegistered,
    famSubscriptionCancelled,
    famSubscriptionReactivated,
    famInviteEmailSent,
    famInviteEmailFailed,
    famInviteResent,
    famInviteRenewedEmailFailed,
    famInviteRevoked,
    famLinkCopied,
    toastSaved,
    toastSwapApproved,
    toastSwapRejected,
    toastDayCleared,
    profDataUpdated,
    profPasswordChanged,
    repErrorTitle,
    sumFutureToggle,
    sumDaysOne,
    sumDaysMany,
    sumTotalSwaps,
    sumTotalSwapsProjected,
    auditTabRecent,
    auditTabAccount,
    auditEmptyAccountTitle,
    auditEmptyAccountBody,
    auditEmptyTitle,
    auditEmptyBody,
    auditRequesterMessage,
    auditApproverMessage,
    auditLoadingMore,
    auditLoadMore,
    auditErrLoad,
    sumHeading,
    auditHeading,
    repTabSummary,
    repTabHistory,
    repTabPdf,
    repTabsAria,
    auditSystemActor,
    auditSystemTrigger,
    auditCreatedSchedule,
    auditDeletedSchedule,
    auditUpdatedSchedule,
    auditErrLoadMore,
    sumErrProcess,
    profPageTitle,
    profNotFound,
    profFrozenBanner,
    profSectionData,
    profSaveData,
    profSectionAdmin,
    profIsAdmin,
    profIsNotAdmin,
    profRemoveAdmin,
    profMakeAdmin,
    profSendPasswordReset,
    profPersonalHint,
    profSectionEmail,
    profCurrentEmail,
    profNewEmail,
    profNewEmailPlaceholder,
    profEmailLinkSent,
    profChangeEmail,
    profSectionPassword,
    profNewPasswordPlaceholder,
    profConfirmNewPassword,
    profConfirmNewPasswordPlaceholder,
    profChangePassword,
    profForgotCurrent,
    profPasswordLinkSentTo,
    profResetByEmail,
    profSectionLgpd,
    profExportHint,
    profExportAction,
    profLeaveTitleLast,
    profLeaveTitle,
    profLeaveLastIntro,
    profLeaveLastConsequenceData,
    profLeaveLastConsequenceCancel,
    profLeaveIntro,
    profLeaveConsequenceAccount,
    profLeaveConsequenceDays,
    profLeaveConsequenceHistory,
    profLeaveConsequenceNotice,
    profLeaveConsequenceSuccessor,
    profSuccessorLabel,
    profSuccessorPlaceholder,
    profLeaveBlocked,
    profFamilyPageLink,
    profLeaveOpenLast,
    profLeaveOpen,
    profLeaveConfirmTextLast,
    profLeaveConfirmText,
    profLeaveConfirmLast,
    profLeaveConfirm,
    profLeaveKeepFamily,
    profLeaveKeepAccount,
    profErrSaveData,
    profToastNowAdmin,
    profToastNoLongerAdmin,
    profToastResetSentTo,
    profErrSendEmail,
    profErrInvalidEmail,
    profErrSameEmail,
    profErrPasswordMismatch,
    profToastExported,
    profErrExport,
    payPageTitle,
    payActiveTitle,
    payBackToFamily,
    payAlmostTitle,
    payConfirmingTitle,
    payConfirmingBody,
    payActiveBody,
    payGuarantee,
    payAlmostBody,
    payAlmostHint,
    policyPageTitle,
    policyHeading,
    policyIntro,
    policyWhatChanged,
    policyReadInFull,
    policyAcceptUpdated,
    policyRegistering,
    policyAcceptAndContinue,
    policyDeclinePrefix,
    policyDeclineSignOut,
    policyDeclineSuffix,
    policyErrNoSession,
    policyErrProfileLoad,
    policyErrProfileLoadRetry,
    policyToastAccepted,
    leavePageTitle,
    leaveFamilyRemovalTitle,
    leaveTitle,
    leaveNonePending,
    leaveBackToApp,
    leaveFamilyRemovalText,
    leaveAccountText,
    leaveChangedMind,
    leaveIn30Days,
    leaveCancelAndReturn,
    leaveSignOut,
    leaveToastCancelled,
    rolesPageTitle,
    rolesBackToFamily,
    rolesHeading,
    rolesIntro,
    rolesDeleteConfirm,
    rolesYes,
    rolesNo,
    rolesEditRole,
    rolesDeleteRole,
    rolesEmpty,
    rolesNameLabel,
    rolesNamePlaceholder,
    rolesEmojiLabel,
    rolesSaving,
    rolesCreate,
    rolesSaveEdit,
    rolesPremiumGate,
    rolesToastCreated,
    sudoTitle,
    sudoHint,
    sudoCurrentPassword,
    sudoConfirm,
    sudoForgot,
    notFoundTitle,
    notFoundBody,
    notFoundBack,
    authErrSignInFailed,
    authErrRateLimited,
    authErrRateLimitedReset,
    authErrConnection,
    authErrMissingConfig,
    authErrSignUpFailed,
    authErrInvalidCredentials,
    authErrEmailNotConfirmed,
    authErrGeneric,
    authErrAlreadyRegistered,
    authErrPasswordWeak,
    authErrEmailFormat,
    authErrDatabaseSignUp,
    authErrSignUpGeneric,
    authErrResetSend,
    authErrPasswordUpdate,
    authErrEmailInUse,
    authErrEmailInvalid,
    authErrEmailChange,
    onbChecklistTitle,
    onbChecklistIntro,
    onbChecklistProgress,
    onbChecklistDismiss,
    onbChecklistDismissAria,
    onbLauncherOpenAria,
    onbChecklistReopen,
    onbChecklistReopenHint,
    onbStepDone,
    onbStepTodo,
    onbStepInviteTitle,
    onbStepInviteHint,
    onbStepInviteDoneHint,
    onbStepInviteAction,
    onbStepPlanTitle,
    onbStepPlanHint,
    onbStepPlanDoneHint,
    onbStepPlanAction,
    onbStepSwapTitle,
    onbStepSwapHint,
    onbStepSwapDoneHint,
    onbStepSwapAction,
    onbSwapSheetTitle,
    onbSwapSheetIntro,
    onbSwapPlannedTitle,
    onbSwapPlannedBody,
    onbSwapApprovalTitle,
    onbSwapApprovalBody,
    onbSwapFrozenTitle,
    onbSwapFrozenBody,
    onbSwapHistoryTitle,
    onbSwapHistoryBody,
    onbSwapSheetGotIt,
    onbChecklistReplayTour,
    tourAriaLabel,
    tourProgress,
    tourPrevious,
    tourNext,
    tourFinish,
    tourSkip,
    tourTodayTitle,
    tourTodayBody,
    tourColoursTitle,
    tourColoursBody,
    tourWizardTitle,
    tourWizardBody,
    tourNotificationsTitle,
    tourNotificationsBody,
  ];
}
