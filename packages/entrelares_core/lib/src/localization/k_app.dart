/// U-13 (T-53 port) — keys that exist ONLY in the Flutter app, hand-written.
///
/// The main catalogs (`k.dart`, `strings_pt_br.dart`, `strings_en.dart`) are
/// GENERATED mirrors of the web app's — they must never gain a key the web
/// catalog does not have, or the re-sync tool would silently drop it. Strings
/// born in this client (the pilot's session-gate messages, the native day
/// sheet's read view) live here instead, under an `app.` prefix so the two
/// namespaces cannot collide. Same parity gates apply (localization_test).
library;

abstract final class KApp {
  // ── Session gate (pilot lessons 1.1/1.2) ──
  static const String sessionRestoredExpired = 'app.session.restoredExpired';
  static const String sessionExpired = 'app.session.expired';

  // ── Calendar screen ──
  static const String errCalendarLoad = 'app.calendar.loadError';

  // ── Day sheet (native summary — the web's editor has no read mode) ──
  static const String sheetNoResponsible = 'app.sheet.noResponsible';
  // U-25: the summary's chips. The responsible sentence and its "(trocado)"
  // suffix became pills; the planned carer and the handoff are what the grid
  // cell does NOT say, so they are the words that stayed.
  static const String sheetPlanned = 'app.sheet.planned';
  static const String sheetHandoffAt = 'app.sheet.handoffAt';
  static const String sheetNote = 'app.sheet.note';
  static const String sheetWhoQuestion = 'app.sheet.whoQuestion';
  static const String sheetSave = 'app.sheet.save';
  static const String errDaySave = 'app.sheet.saveError';

  // ── Save errors (mirrors of TranslateSaveError's inline literals, which
  //    the frozen web app never extracted) ──
  static const String errSwapPendingExists = 'app.save.swapPendingExists';
  static const String errConcurrentSaveRetry = 'app.save.concurrentRetry';

  // ── F-40 proactive hint (lote 2) — the web never warns upfront (the
  //    trigger refuses and the text propagates); this native editor explains
  //    BEFORE the attempt, so the copy mirrors the trigger's own messages ──
  static const String editorRetroBeyondFree = 'app.editor.retroBeyondFree';
  static const String editorRetroBeyondPremium =
      'app.editor.retroBeyondPremium';

  // ── Bulk edit (lote 2) — the web's "Salvando {x}/{y}..." progress label was
  //    a pre-U-13 hardcoded literal (Home.razor:2491), frozen with the Blazor
  //    app; the catalogued rule ports, the residue does not ──
  static const String bulkProgressSaving = 'app.bulk.progressSaving';

  // ── Rotation wizard (lote 2) — two validation sentences the web kept as
  //    pre-U-13 hardcoded PT literals (ScheduleWizard.razor:223/236) ──
  static const String wizErrTooFewBlocks = 'app.wiz.errTooFewBlocks';
  static const String wizErrBlockDays = 'app.wiz.errBlockDays';

  // ── 🔔 Resolver (lote 3) — the web's "Processando {x}/{y}..." progress
  //    label was a pre-U-13 hardcoded literal (Home.razor:2145), frozen with
  //    the Blazor app; same treatment as bulkProgressSaving ──
  static const String wfProgressProcessing = 'app.wf.progressProcessing';

  // ── Native affordances the web has no word for (lote 4) — the system share
  //    sheet replaces "copie o link e mande no WhatsApp" ──
  static const String commonShare = 'app.common.share';
  // U-47: the tooltip of a card's overflow menu (⋮).
  static const String commonMoreActions = 'app.common.moreActions';

  // ── Sudo S-10 (lote 4) — the outcomes `SudoService.ElevateAsync` builds
  //    itself in the web, as hardcoded PT literals; the catalogued rule ports,
  //    the residue does not. The SERVER's own message is preferred whenever the
  //    response carries one (pilot QA round 2) — these are the fallbacks ──
  static const String sudoErrCooldown = 'app.sudo.errCooldown';
  static const String sudoErrNoSession = 'app.sudo.errNoSession';
  static const String sudoErrWrongPassword = 'app.sudo.errWrongPassword';
  static const String sudoErrGeneric = 'app.sudo.errGeneric';
  static const String sudoErrConnection = 'app.sudo.errConnection';

  // ── Sudo S-21 — the gate's SECOND proof. The sheet offers BOTH to every
  //    session: production carries an account with a password and no `email`
  //    identity, so the client was never in a position to know which one a
  //    person can give. Asking is cheaper than guessing wrong ──
  static const String sudoSendCode = 'app.sudo.sendCode';
  static const String sudoSendingCode = 'app.sudo.sendingCode';
  static const String sudoCodeSentTo = 'app.sudo.codeSentTo';
  static const String sudoCodeLabel = 'app.sudo.codeLabel';
  static const String sudoUsePassword = 'app.sudo.usePassword';
  static const String sudoErrCodeShape = 'app.sudo.errCodeShape';
  static const String sudoErrCodeSend = 'app.sudo.errCodeSend';

  // ── Custom roles F-41 (lote 4) — four labels the web left as pre-U-13
  //    literals (CustomRolesPage.razor:73/86/216). Client-only strings with no
  //    server twin, so cataloguing them is a strict improvement ──
  static const String rolesCreateTitle = 'app.roles.createTitle';
  static const String rolesEditTitle = 'app.roles.editTitle';
  static const String rolesToastUpdated = 'app.roles.toastUpdated';
  static const String rolesNoEmoji = 'app.roles.noEmoji';

  // ── Profile page (lote 4) — two refusals the web left as pre-U-13 literals
  //    (ProfilePage.razor:493/652); client-only, no server twin ──
  static const String profErrNameTooShort = 'app.prof.errNameTooShort';
  static const String profErrPasswordShort = 'app.prof.errPasswordShort';

  // ── Invite form (lote 4) — the web kept the "pick a role" refusal as a
  //    pre-U-13 hardcoded PT literal (FamilyPage.razor:1311); same treatment
  //    as the wizard's, and safe to catalogue because this sentence has no
  //    server twin to stay byte-identical with (unlike CustomRoleRules') ──
  static const String inviteErrRoleRequired = 'app.invite.errRoleRequired';

  // ── Navigation shell (lote 1) — screens the later batches fill in ──
  static const String shellUnderConstructionTitle =
      'app.shell.underConstructionTitle';
  static const String shellUnderConstructionBody =
      'app.shell.underConstructionBody';

  // ── Play Billing (lote 5, T-48) — the store rail has no web counterpart by
  //    construction: the web catalog was written for a checkout that redirects
  //    to a payment page, and Play's flow is a system sheet the app only asks
  //    for. The PRICE never appears here: it comes from the Play product and
  //    is passed into K.premSubscribe* as an argument ──
  static const String storeManage = 'app.store.manage';
  static const String storeRestore = 'app.store.restore';
  static const String storeUnavailable = 'app.store.unavailable';
  static const String storePending = 'app.store.pending';
  static const String storeErrPurchase = 'app.store.errPurchase';
  static const String storeToastActive = 'app.store.toastActive';

  // ── F-57 social login — strings born in this client: the web app never had
  //    an OAuth button, an onboarding screen or a password-less profile ──
  static const String authGoogle = 'app.auth.google';
  static const String authGoogleErr = 'app.auth.googleErr';
  static const String onbFounderTitle = 'app.onb.founderTitle';
  static const String onbFounderSubtitle = 'app.onb.founderSubtitle';
  static const String onbFounderCta = 'app.onb.founderCta';
  static const String onbClaimCta = 'app.onb.claimCta';
  static const String onbSubmitting = 'app.onb.submitting';
  static const String onbSwitchAccount = 'app.onb.switchAccount';
  static const String onbSignedInAs = 'app.onb.signedInAs';
  static const String onbErrGeneric = 'app.onb.errGeneric';

  // ── U-44 — the founder's sign-up in two steps, and the role picker both
  //    sign-up screens share: a shortlist of chips plus "Outro…" ──
  static const String signupStep = 'app.signup.step';
  static const String signupStepAccount = 'app.signup.stepAccount';
  static const String signupStepFamily = 'app.signup.stepFamily';
  static const String signupContinue = 'app.signup.continue';
  static const String signupBack = 'app.signup.back';
  static const String roleOther = 'app.role.other';
  static const String roleOtherTitle = 'app.role.otherTitle';
  static const String profLoginMethod = 'app.prof.loginMethod';
  static const String profLoginMethodGoogle = 'app.prof.loginMethodGoogle';
  static const String profLoginMethodNote = 'app.prof.loginMethodNote';

  // ── U-30 — the account lists EVERY door it has, not just the one that
  //    happens to have a form. A Google sign-in with the address of a
  //    password account links the two (F-57), and the screen said nothing ──
  static const String profLoginMethodsIntro = 'app.prof.loginMethodsIntro';
  static const String profLoginMethodPassword = 'app.prof.loginMethodPassword';
  static const String profLoginMethodPasswordNote =
      'app.prof.loginMethodPasswordNote';
  static const String profLoginMethodGoogleLinkedNote =
      'app.prof.loginMethodGoogleLinkedNote';
  // U-50: the Google row while the server has not said whether a password
  // exists — only what is true either way.
  static const String profLoginMethodGoogleNeutralNote =
      'app.prof.loginMethodGoogleNeutralNote';
  static const String profLoginMethodOther = 'app.prof.loginMethodOther';
  static const String profLoginMethodOtherNote = 'app.prof.loginMethodOtherNote';

  // ── U-21 — the profile is read at rest and edited in a sheet. The pencil
  //    on Dados needs a name of its own (the e-mail and password pencils
  //    reuse the action labels the page already had), and the Senha card
  //    needs one line to stand in for the form it no longer shows ──
  static const String profEditData = 'app.prof.editData';
  static const String profPasswordSummary = 'app.prof.passwordSummary';

  // ── F-09 push (the Notificações control) ──
  static const String pushTitle = 'app.push.title';
  static const String pushHintOff = 'app.push.hintOff';
  static const String pushHintOn = 'app.push.hintOn';
  static const String pushHintUnsupported = 'app.push.hintUnsupported';
  // ── U-54 — the one next step for a device without push (PushNudgeRules).
  //    The iPhone lines state Apple's CONDITION (a web app receives
  //    notifications only from the Home Screen — Apple's own guide, below),
  //    never that our delivery works there: T-75 measures that. The re-allow
  //    paths were read on 21/09/2026 from each vendor's own guide:
  //    support.apple.com/pt-br/guide/iphone/iph7c3d96bab/ios (iOS 27/26),
  //    support.google.com/android/answer/9079661 and
  //    support.google.com/chrome/answer/3220216. Re-check there first. ──
  static const String pushHintInstallIos = 'app.push.hintInstallIos';
  static const String pushInstallHow = 'app.push.installHow';
  static const String pushHintNeedsSafari = 'app.push.hintNeedsSafari';
  static const String pushHintReallowApp = 'app.push.hintReallowApp';
  static const String pushHintReallowIos = 'app.push.hintReallowIos';
  static const String pushHintReallowBrowser = 'app.push.hintReallowBrowser';
  static const String pushHintUnsupportedHere = 'app.push.hintUnsupportedHere';
  static const String pushEnable = 'app.push.enable';
  static const String pushDisable = 'app.push.disable';
  /// U-43: the app-bar icon that replaces the card once push is on — its
  /// tooltip is also the name a screen reader gives the button.
  static const String pushStatusOnTooltip = 'app.push.statusOnTooltip';
  static const String pushToastOn = 'app.push.toastOn';
  static const String pushToastOff = 'app.push.toastOff';
  static const String pushErrEnable = 'app.push.errEnable';
  static const String onbStepPushTitle = 'app.onbStep.push.title';
  static const String onbStepPushHint = 'app.onbStep.push.hint';
  static const String onbStepPushDoneHint = 'app.onbStep.push.doneHint';
  static const String onbStepPushAction = 'app.onbStep.push.action';

  // ── F-56 pending member (invited, not yet joined) ──
  static const String famPendingBadge = 'app.fam.pendingBadge';
  static const String famPendingHint = 'app.fam.pendingHint';
  static const String famInviteName = 'app.fam.inviteName';
  static const String famInviteNameHint = 'app.fam.inviteNameHint';
  static const String famInviteEmailOptional = 'app.fam.inviteEmailOptional';
  static const String famAddWithoutInvite = 'app.fam.addWithoutInvite';
  static const String famPendingAdded = 'app.fam.pendingAdded';
  static const String famPendingInvite = 'app.fam.pendingInvite';
  static const String famPendingInviteTitle = 'app.fam.pendingInviteTitle';
  static const String famPendingRemove = 'app.fam.pendingRemove';
  static const String famPendingRemoveConfirm = 'app.fam.pendingRemoveConfirm';
  static const String famPendingRemoved = 'app.fam.pendingRemoved';
  // U-47: the two questions a roster card asks before a destructive move.
  static const String famPendingRemoveTitle = 'app.fam.pendingRemoveTitle';
  static const String famRevokeTitle = 'app.fam.revokeTitle';
  static const String famRevokeConfirm = 'app.fam.revokeConfirm';
  // ── F-62 legacy invitation → placeholder ("Adicionar ao calendário") ──
  static const String famAttachInvite = 'app.fam.attachInvite';
  static const String famAttachTitle = 'app.fam.attachTitle';
  static const String famAttachHint = 'app.fam.attachHint';
  static const String famAttached = 'app.fam.attached';
  static const String inviteErrNameRequired = 'app.invite.errNameRequired';
  static const String sheetSwapUnavailablePending =
      'app.sheet.swapUnavailablePending';
  static const String calMemberPending = 'app.cal.memberPending';
  static const String onbStepInviteDoneHintPending =
      'app.onbStep.invite.doneHintPending';
  static const String auditActionPendingAdded = 'app.audit.pendingAdded';
  static const String auditActionPendingRemoved = 'app.audit.pendingRemoved';
  static const String auditActionPendingClaimed = 'app.audit.pendingClaimed';

  // ── T-65 web→app handoff. Shown ONLY on the web channel, and only when the
  //    browser confirms the Play app is on this device. ──
  static const String handoffBanner = 'app.handoff.banner';
  static const String handoffOpen = 'app.handoff.open';
  static const String handoffDismiss = 'app.handoff.dismiss';

  // ── U-51 iPhone install hint. Shown ONLY on the web channel, in Safari on
  //    an iPhone or iPad that has not added the app to the Home Screen. The
  //    two steps mirror the landing's L-19 guide, which was checked against
  //    Apple's own iOS 26 guide on 11/09/2026
  //    (support.apple.com/pt-br/guide/iphone/iph42ab2f3a7/ios): the Share
  //    button is not always in view, the list must be SCROLLED, and the flow
  //    ends on "Adicionar". U-54 (21/09/2026) re-read Apple's current guide,
  //    iOS 27 and 26 alike (support.apple.com/pt-br/guide/iphone/iphea86e5236/ios):
  //    before "Adicionar" it now says to turn on "Abrir como App da Web" —
  //    without it the icon opens Safari, not the standalone app, and there is
  //    no push. Re-check there before changing a word. ──
  static const String installHintBanner = 'app.installHint.banner';
  static const String installHintHow = 'app.installHint.how';
  static const String installHintDismiss = 'app.installHint.dismiss';
  static const String installHintTitle = 'app.installHint.title';
  static const String installHintSubtitle = 'app.installHint.subtitle';
  static const String installHintStepShare = 'app.installHint.stepShare';
  static const String installHintStepAdd = 'app.installHint.stepAdd';
  static const String installHintNote = 'app.installHint.note';

  // ── T-18 offline strip. Says how OLD what is on screen is, never just
  //    "offline" — an undated old plan reads as the current one. ──
  static const String offlineStrip = 'app.offline.strip';
  static const String offlineStripNoData = 'app.offline.stripNoData';
  static const String offlineMonthNotLoaded = 'app.offline.monthNotLoaded';
  static const String offlineWriteBlocked = 'app.offline.writeBlocked';

  // ── U-35 Família split: the roster's three navigation rows and the pages
  //    behind them. Row TITLES reuse what already names the thing (the
  //    danger zone's `K.famDelReqTitle`); these are the words the split added.
  static const String famPlanRow = 'app.fam.planRow';

  // F-68 — Help & contact.
  static const String helpTitle = 'app.help.title';
  static const String helpProfileRowSub = 'app.help.profileRowSub';
  static const String helpLoginLink = 'app.help.loginLink';
  static const String helpIntro = 'app.help.intro';
  static const String helpCategoryLabel = 'app.help.categoryLabel';
  static const String helpCatQuestion = 'app.help.cat.question';
  static const String helpCatProblem = 'app.help.cat.problem';
  static const String helpCatSuggestion = 'app.help.cat.suggestion';
  static const String helpCatPrivacy = 'app.help.cat.privacy';
  static const String helpCatOther = 'app.help.cat.other';
  static const String helpMessageLabel = 'app.help.messageLabel';
  static const String helpMessageHint = 'app.help.messageHint';
  static const String helpMessageTooShort = 'app.help.messageTooShort';
  static const String helpEmailLabel = 'app.help.emailLabel';
  static const String helpEmailInvalid = 'app.help.emailInvalid';
  static const String helpReplyTo = 'app.help.replyTo';
  static const String helpDiagLabel = 'app.help.diagLabel';
  static const String helpDiagHelper = 'app.help.diagHelper';
  static const String helpDiagPreview = 'app.help.diagPreview';
  static const String helpDiagVersion = 'app.help.diag.version';
  static const String helpDiagChannel = 'app.help.diag.channel';
  static const String helpDiagPlatform = 'app.help.diag.platform';
  static const String helpDiagLanguage = 'app.help.diag.language';
  static const String helpDiagRoute = 'app.help.diag.route';
  static const String helpSend = 'app.help.send';
  static const String helpSentTitle = 'app.help.sentTitle';
  static const String helpSentBody = 'app.help.sentBody';
  static const String helpBack = 'app.help.back';
  static const String helpErrRateLimited = 'app.help.err.rateLimited';
  static const String helpErrSendFailed = 'app.help.err.sendFailed';
  static const String helpErrOffline = 'app.help.err.offline';
  static const String helpErrFailed = 'app.help.err.failed';
  static const String helpMailtoLead = 'app.help.mailtoLead';
  static const String famPlanRowFree = 'app.fam.planRowFree';
  static const String famPlanRowTrialOne = 'app.fam.planRowTrialOne';
  static const String famPlanRowTrialMany = 'app.fam.planRowTrialMany';
  static const String famPlanRowPremiumUntil = 'app.fam.planRowPremiumUntil';
  static const String famPlanRowPremium = 'app.fam.planRowPremium';
  static const String famAdminRow = 'app.fam.adminRow';
  static const String famAdminRowOn = 'app.fam.adminRowOn';
  static const String famAdminRowOff = 'app.fam.adminRowOff';
  static const String famDelReqUnavailable = 'app.fam.delReqUnavailable';

  // ── U-12 appearance: the reader's own theme, beside the language on the
  //    profile page. The three labels are deliberately ONE WORD each — the
  //    card's prose ("sempre claro", "seguir o sistema") does not fit a
  //    segmented control at the 1.3× scale U-48 measures every screen at, and
  //    U-34's defect was exactly a label breaking mid-word there. The hint
  //    carries what the short words drop. ──
  static const String appearanceLabel = 'app.appearance.label';
  static const String appearanceHint = 'app.appearance.hint';
  static const String appearanceAriaLabel = 'app.appearance.ariaLabel';
  static const String appearanceLight = 'app.appearance.light';
  static const String appearanceDark = 'app.appearance.dark';
  static const String appearanceSystem = 'app.appearance.system';

  // ── F-52 aviso de imprevisto ──
  // "Aviso" is the third term beside Observação do dia and Mensagem, and
  // `vocabulary_test` now pins the word to the keys below and nowhere else.
  //
  // **Every choice states its consequence** (owner, 18/09/2026). The three
  // requests do visibly different things — one asks nothing, one asks for help
  // now, and one puts TODAY on offer — and the third can hand the day to
  // whoever answers, with no second confirmation from the sender. A person
  // cannot consent to that by reading a four-word label, so each request
  // carries a sentence saying what will happen, shown beside the choice and
  // not hidden behind a tooltip or a help page.
  static const String noticeAction = 'app.notice.action';
  static const String noticeTitle = 'app.notice.title';
  static const String noticeSubtitle = 'app.notice.subtitle';
  static const String noticeReasonLabel = 'app.notice.reasonLabel';
  static const String noticeReasonDelay = 'app.notice.reason.delay';
  static const String noticeReasonMedical = 'app.notice.reason.medical';
  static const String noticeReasonTraffic = 'app.notice.reason.traffic';
  static const String noticeReasonOther = 'app.notice.reason.other';
  static const String noticeEtaLabel = 'app.notice.etaLabel';
  static const String noticeEtaMinutes = 'app.notice.eta.minutes';
  static const String noticeEtaNone = 'app.notice.eta.none';
  static const String noticeRequestLabel = 'app.notice.requestLabel';
  static const String noticeRequestInfo = 'app.notice.request.info';
  static const String noticeRequestPickup = 'app.notice.request.pickup';
  static const String noticeRequestKeep = 'app.notice.request.keep';
  static const String noticeConsequenceInfo = 'app.notice.consequence.info';
  static const String noticeConsequencePickup = 'app.notice.consequence.pickup';
  static const String noticeConsequenceKeep = 'app.notice.consequence.keep';
  static const String noticeConsequenceKeepClearsEta = 'app.notice.consequence.keepClearsEta';
  static const String noticeConsequenceKeepNotMyDay = 'app.notice.consequence.keepNotMyDay';
  static const String noticeNoteLabel = 'app.notice.noteLabel';
  static const String noticeNoteHint = 'app.notice.noteHint';
  static const String noticeSend = 'app.notice.send';
  static const String noticeCapHint = 'app.notice.capHint';
  static const String noticeCapReached = 'app.notice.capReached';
  static const String noticeSent = 'app.notice.sent';
  static const String noticeErrSend = 'app.notice.errSend';
  static const String noticeOpenMine = 'app.notice.openMine';
  static const String noticeCancel = 'app.notice.cancel';
  static const String noticeCancelConfirm = 'app.notice.cancelConfirm';
  static const String noticeCancelKeep = 'app.notice.cancelKeep';
  static const String noticeCancelled = 'app.notice.cancelled';
  static const String noticeErrCancel = 'app.notice.errCancel';

  // ── F-52 PR 2: answering ──
  // The same rule as the requests, from the other side: each answer SAYS what
  // it will do. "Vou ficar com a criança hoje" is the only tap in this product
  // that moves a day with no second confirmation from anyone, so the sentence
  // under it names the swap, says it is already approved, and says where it
  // will be readable afterwards.
  static const String noticeAnswerTitle = 'app.notice.answer.title';
  static const String noticeAnswerHelping = 'app.notice.answer.helping';
  static const String noticeAnswerKeeping = 'app.notice.answer.keeping';
  static const String noticeAnswerHelpingWhat = 'app.notice.answer.helpingWhat';
  static const String noticeAnswerKeepingWhat = 'app.notice.answer.keepingWhat';
  static const String noticeAnswerNoteLabel = 'app.notice.answer.noteLabel';
  static const String noticeAnswerNoteHint = 'app.notice.answer.noteHint';
  static const String noticeAnswerSend = 'app.notice.answer.send';
  static const String noticeAnsweredHelping = 'app.notice.answeredHelping';
  static const String noticeAnsweredKeeping = 'app.notice.answeredKeeping';
  static const String noticeErrAnswer = 'app.notice.errAnswer';

  // ── F-67 Part B: the admin mode offered where it is needed ──
  // One sentence per place an ADMIN with the mode off reaches for something
  // only the mode allows (`AdminModeAction`); each names the action, so the
  // question is never a generic "are you sure". The past-day one also says
  // what the F-61 record will print, so the plan editor is not used to tell a
  // story.
  static const String adminOfferEditPastDay = 'app.adminOffer.editPastDay';
  static const String adminOfferClearDay = 'app.adminOffer.clearDay';
  static const String adminOfferChangePlanned =
      'app.adminOffer.changePlanned';
  static const String adminOfferBulkClear = 'app.adminOffer.bulkClear';
  static const String adminOfferBulkOverwrite =
      'app.adminOffer.bulkOverwrite';
  static const String adminOfferWizardReplace =
      'app.adminOffer.wizardReplace';
  static const String adminOfferClearMonth = 'app.adminOffer.clearMonth';
  static const String adminOfferHow = 'app.adminOffer.how';
  static const String adminOfferCorrectPlan = 'app.adminOffer.correctPlan';
  static const String adminOfferBulkBanner = 'app.adminOffer.bulkBanner';

  // ── F-67 Part A: the relato do dia ──
  // "Relato" is this item's word (owner, 21/09/2026): Histórico is the audit
  // trail, Observação the plan note, Aviso the F-52 notice, Mensagem the swap
  // message. Every sentence about a relato is a dated fact — the F-61 rule.
  static const String dayAccountErrEmpty = 'app.dayAccount.errEmpty';
  static const String dayAccountErrTooLong = 'app.dayAccount.errTooLong';
  static const String dayAccountByline = 'app.dayAccount.byline';
  static const String dayAccountCorrected = 'app.dayAccount.corrected';
  static const String dayAccountSection = 'app.dayAccount.section';
  static const String dayAccountAction = 'app.dayAccount.action';
  static const String dayAccountFieldLabel = 'app.dayAccount.fieldLabel';
  static const String dayAccountFieldHint = 'app.dayAccount.fieldHint';
  static const String dayAccountAppendOnly = 'app.dayAccount.appendOnly';
  static const String dayAccountSave = 'app.dayAccount.save';
  static const String dayAccountCorrect = 'app.dayAccount.correct';
  static const String dayAccountCorrecting = 'app.dayAccount.correcting';
  static const String dayAccountOutOfWindow = 'app.dayAccount.outOfWindow';
  static const String dayAccountCapLeftOne = 'app.dayAccount.capLeftOne';
  static const String dayAccountCapLeftMany = 'app.dayAccount.capLeftMany';
  static const String dayAccountCapReached = 'app.dayAccount.capReached';
  static const String dayAccountSaved = 'app.dayAccount.saved';
  static const String dayAccountErrSave = 'app.dayAccount.errSave';
  static const String dayAccountErrLoad = 'app.dayAccount.errLoad';
  static const String dayAccountAuditNew = 'app.dayAccount.auditNew';
  static const String dayAccountAuditCorrection = 'app.dayAccount.auditCorrection';
  static const String pdfDayAccountsSection = 'app.dayAccount.pdfSection';
  static const String pdfDayAccountsLead = 'app.dayAccount.pdfLead';
  static const String pdfDayAccountsEmpty = 'app.dayAccount.pdfEmpty';
  static const String pdfDayAccountLine = 'app.dayAccount.pdfLine';
  static const String pdfDayAccountCorrectionLine = 'app.dayAccount.pdfCorrectionLine';

  /// See `K.allKeys`.
  // ── F-55 the child entity (PR 1): the Família row and its page; only an
  //    admin writes, every member reads. The name is family data, shown as
  //    typed in both languages. ──
  static const String famChildRow = 'app.fam.childRow';
  static const String famChildRowEmpty = 'app.fam.childRowEmpty';
  static const String childAnd = 'app.child.and';
  static const String childTitle = 'app.child.title';
  static const String childLead = 'app.child.lead';
  static const String childEmpty = 'app.child.empty';
  static const String childAdminOnly = 'app.child.adminOnly';
  static const String childNameLabel = 'app.child.nameLabel';
  static const String childAdd = 'app.child.add';
  static const String childRename = 'app.child.rename';
  static const String childRemove = 'app.child.remove';
  static const String childRemoveConfirm = 'app.child.removeConfirm';
  static const String childAdded = 'app.child.added';
  static const String childRenamed = 'app.child.renamed';
  static const String childRemoved = 'app.child.removed';
  static const String childErrLoad = 'app.child.errLoad';

  // ── F-55 the day agenda (PR 2). Every key lives under `app.agenda.` — the
  //    ADDRESS vocabulary_test pins the words "agenda" and "nota" to. ──
  static const String agendaSection = 'app.agenda.section';
  static const String agendaKindSchool = 'app.agenda.kind.school';
  static const String agendaKindHealth = 'app.agenda.kind.health';
  static const String agendaKindMedicine = 'app.agenda.kind.medicine';
  static const String agendaKindActivity = 'app.agenda.kind.activity';
  static const String agendaKindFree = 'app.agenda.kind.free';
  static const String agendaKindNote = 'app.agenda.kind.note';
  static const String agendaKindOther = 'app.agenda.kind.other';
  static const String agendaAdd = 'app.agenda.add';
  static const String agendaEmpty = 'app.agenda.empty';
  static const String agendaNewTitle = 'app.agenda.newTitle';
  static const String agendaEditTitle = 'app.agenda.editTitle';
  static const String agendaKindLabel = 'app.agenda.kindLabel';
  static const String agendaChildLabel = 'app.agenda.childLabel';
  static const String agendaStartLabel = 'app.agenda.startLabel';
  static const String agendaEndLabel = 'app.agenda.endLabel';
  static const String agendaNoTime = 'app.agenda.noTime';
  static const String agendaClearTime = 'app.agenda.clearTime';
  static const String agendaBodyLabel = 'app.agenda.bodyLabel';
  static const String agendaNoteBodyLabel = 'app.agenda.noteBodyLabel';
  static const String agendaDelete = 'app.agenda.delete';
  static const String agendaDeleteConfirm = 'app.agenda.deleteConfirm';
  static const String agendaSaved = 'app.agenda.saved';
  static const String agendaDeleted = 'app.agenda.deleted';
  static const String agendaErrLoad = 'app.agenda.errLoad';
  static const String agendaFreeNotesOne = 'app.agenda.freeNotesOne';
  static const String agendaFreeNotesMany = 'app.agenda.freeNotesMany';
  static const String agendaReadOnlyPast = 'app.agenda.readOnlyPast';
  static const String agendaReadOnlyPremium = 'app.agenda.readOnlyPremium';
  static const String agendaNoChildAdmin = 'app.agenda.noChildAdmin';
  static const String agendaNoChildMember = 'app.agenda.noChildMember';
  static const String agendaBy = 'app.agenda.by';
  static const String agendaFromObservation = 'app.agenda.fromObservation';
  static const String agendaAuditAdded = 'app.agenda.auditAdded';
  static const String agendaAuditDeleted = 'app.agenda.auditDeleted';
  static const String agendaPdfSection = 'app.agenda.pdfSection';
  static const String agendaPdfLead = 'app.agenda.pdfLead';
  static const String agendaPdfEmpty = 'app.agenda.pdfEmpty';

  // ── F-50: the Visualizador ──
  static const String viewerBadge = 'app.viewer.badge';
  static const String viewerSection = 'app.viewer.section';
  static const String viewerInviteButton = 'app.viewer.inviteButton';
  static const String viewerReadOnly = 'app.viewer.readOnly';
  static const String viewerInviteLead = 'app.viewer.inviteLead';
  static const String viewerInviteNeedsEmail = 'app.viewer.inviteNeedsEmail';
  static const String viewerFreeCapOne = 'app.viewer.freeCapOne';
  static const String viewerFreeCapMany = 'app.viewer.freeCapMany';
  static const String viewerMaxCap = 'app.viewer.maxCap';
  static const String viewerInviteSent = 'app.viewer.inviteSent';
  static const String viewerPromote = 'app.viewer.promote';
  static const String viewerPromoteConfirm = 'app.viewer.promoteConfirm';
  static const String viewerPromoted = 'app.viewer.promoted';
  static const String viewerRemove = 'app.viewer.remove';
  static const String viewerRemoveConfirm = 'app.viewer.removeConfirm';
  static const String viewerRemoved = 'app.viewer.removed';
  static const String viewerLeaveBody = 'app.viewer.leaveBody';
  static const String viewerLeaveButton = 'app.viewer.leaveButton';
  static const String viewerInvitedBody = 'app.viewer.invitedBody';
  // ── F-64: the verifiable report ──
  static const String attestPageTitle = 'app.attest.pageTitle';
  static const String attestValid = 'app.attest.valid';
  static const String attestPending = 'app.attest.pending';
  static const String attestRevoked = 'app.attest.revoked';
  static const String attestExpired = 'app.attest.expired';
  static const String attestUnknown = 'app.attest.unknown';
  static const String attestError = 'app.attest.error';
  static const String attestIssuedAt = 'app.attest.issuedAt';
  static const String attestPeriod = 'app.attest.period';
  static const String attestValidUntil = 'app.attest.validUntil';
  static const String attestFingerprint = 'app.attest.fingerprint';
  static const String attestSummary = 'app.attest.summary';
  static const String attestDaysPlanned = 'app.attest.daysPlanned';
  static const String attestDaysBy = 'app.attest.daysBy';
  static const String attestDaysSwapped = 'app.attest.daysSwapped';
  static const String attestSwaps = 'app.attest.swaps';
  static const String attestDayAccounts = 'app.dayAccount.attestCount';
  static const String attestInitialsNote = 'app.attest.initialsNote';
  static const String attestCompare = 'app.attest.compare';
  static const String attestCompareHint = 'app.attest.compareHint';
  static const String attestMatch = 'app.attest.match';
  static const String attestMismatch = 'app.attest.mismatch';
  static const String attestNoPicker = 'app.attest.noPicker';
  static const String attestSection = 'app.attest.section';
  static const String attestSectionLead = 'app.attest.sectionLead';
  static const String attestRowState = 'app.attest.rowState';
  static const String attestStateValid = 'app.attest.stateValid';
  static const String attestStatePending = 'app.attest.statePending';
  static const String attestStateRevoked = 'app.attest.stateRevoked';
  static const String attestStateExpired = 'app.attest.stateExpired';
  static const String attestRevoke = 'app.attest.revoke';
  static const String attestRevokeConfirm = 'app.attest.revokeConfirm';
  static const String attestRevoked2 = 'app.attest.revokedDone';
  static const String attestHashFailed = 'app.attest.hashFailed';
  static const String agendaNotifyLabel = 'app.agenda.notifyLabel';
  static const String agendaNotifyNone = 'app.agenda.notifyNone';
  static const String agendaNotifySelf = 'app.agenda.notifySelf';
  static const String agendaNotifyResponsible = 'app.agenda.notifyResponsible';
  static const String agendaNotifyFamily = 'app.agenda.notifyFamily';
  static const String agendaNotifyPush = 'app.agenda.notifyPush';
  static const String agendaNotifyInApp = 'app.agenda.notifyInApp';
  static const String agendaNotifyLead = 'app.agenda.notifyLead';
  static const String agendaRemindLabel = 'app.agenda.remindLabel';
  static const String agendaRemindNone = 'app.agenda.remindNone';
  static const String agendaRemindAtStart = 'app.agenda.remindAtStart';
  static const String agendaRemindBefore = 'app.agenda.remindBefore';
  static const String agendaRemindNeedsStart = 'app.agenda.remindNeedsStart';
  static const String agendaRepeat = 'app.agenda.repeat';
  static const String agendaRepeatLead = 'app.agenda.repeatLead';
  static const String agendaRepeatDays = 'app.agenda.repeatDays';
  static const String agendaRoutineApplied = 'app.agenda.routineApplied';
  static const String agendaRoutinePart = 'app.agenda.routinePart';
  static const String agendaRoutineEdit = 'app.agenda.routineEdit';
  static const String agendaRoutineEditTitle = 'app.agenda.routineEditTitle';
  static const String agendaRoutineEditLead = 'app.agenda.routineEditLead';
  static const String agendaRoutineStop = 'app.agenda.routineStop';
  static const String agendaRoutineStopConfirm = 'app.agenda.routineStopConfirm';
  static const String agendaRoutineStopped = 'app.agenda.routineStopped';
  static const String agendaAuditRoutineAdded = 'app.agenda.auditRoutineAdded';
  static const String agendaAuditRoutineDeleted = 'app.agenda.auditRoutineDeleted';
  // ── F-34: shared expenses ──
  static const String expenseNav = 'app.expense.nav';
  static const String expenseLead = 'app.expense.lead';
  static const String expenseErrLoad = 'app.expense.errLoad';
  static const String expenseOff = 'app.expense.off';
  static const String expenseViewer = 'app.expense.viewer';
  static const String expensePremium = 'app.expense.premium';
  static const String expenseAdd = 'app.expense.add';
  static const String expenseEdit = 'app.expense.edit';
  static const String expenseEmpty = 'app.expense.empty';
  static const String expenseEmptyBody = 'app.expense.emptyBody';
  static const String expenseGroupFamily = 'app.expense.groupFamily';
  static const String expenseGroupLabel = 'app.expense.groupLabel';
  static const String expenseBalance = 'app.expense.balance';
  static const String expenseBalanceEven = 'app.expense.balanceEven';
  static const String expensePays = 'app.expense.pays';
  static const String expenseNetGets = 'app.expense.netGets';
  static const String expenseNetOwes = 'app.expense.netOwes';
  static const String expenseSettle = 'app.expense.settle';
  static const String expenseSettleTitle = 'app.expense.settleTitle';
  static const String expenseSettleLead = 'app.expense.settleLead';
  static const String expenseSettleTo = 'app.expense.settleTo';
  static const String expenseSettleNobody = 'app.expense.settleNobody';
  static const String expenseAmount = 'app.expense.amount';
  static const String expenseSettleSent = 'app.expense.settleSent';
  static const String expensePending = 'app.expense.pending';
  static const String expensePendingToMe = 'app.expense.pendingToMe';
  static const String expensePendingFromMe = 'app.expense.pendingFromMe';
  static const String expensePendingOthers = 'app.expense.pendingOthers';
  static const String expenseConfirm = 'app.expense.confirm';
  static const String expenseReject = 'app.expense.reject';
  static const String expenseTakeBack = 'app.expense.takeBack';
  static const String expenseConfirmed = 'app.expense.confirmed';
  static const String expenseRejected = 'app.expense.rejected';
  static const String expenseTakenBack = 'app.expense.takenBack';
  static const String expenseListSection = 'app.expense.listSection';
  static const String expenseRow = 'app.expense.row';
  static const String expenseDesc = 'app.expense.desc';
  static const String expenseCategory = 'app.expense.category';
  static const String expenseDate = 'app.expense.date';
  static const String expensePaidBy = 'app.expense.paidBy';
  static const String expenseSplit = 'app.expense.split';
  static const String expenseSplitEqual = 'app.expense.splitEqual';
  static const String expenseSplitExact = 'app.expense.splitExact';
  static const String expenseSplitPercent = 'app.expense.splitPercent';
  static const String expenseSplitShares = 'app.expense.splitShares';
  static const String expenseParticipants = 'app.expense.participants';
  static const String expenseValueExact = 'app.expense.valueExact';
  static const String expenseValuePercent = 'app.expense.valuePercent';
  static const String expenseValueShares = 'app.expense.valueShares';
  static const String expenseShareOf = 'app.expense.shareOf';
  static const String expenseErrNoParts = 'app.expense.errNoParts';
  static const String expenseErrExact = 'app.expense.errExact';
  static const String expenseErrPercent = 'app.expense.errPercent';
  static const String expenseErrZero = 'app.expense.errZero';
  static const String expenseErrAmount = 'app.expense.errAmount';
  static const String expenseErrMax = 'app.expense.errMax';
  static const String expenseErrDesc = 'app.expense.errDesc';
  static const String expenseErrDescLong = 'app.expense.errDescLong';
  static const String expenseSaved = 'app.expense.saved';
  static const String expenseDelete = 'app.expense.delete';
  static const String expenseDeleteConfirm = 'app.expense.deleteConfirm';
  static const String expenseDeleted = 'app.expense.deleted';
  static const String expenseDetailSplit = 'app.expense.detailSplit';
  static const String expenseChanges = 'app.expense.changes';
  static const String expenseChangeCreated = 'app.expense.changeCreated';
  static const String expenseChangeUpdated = 'app.expense.changeUpdated';
  static const String expenseChangeDeleted = 'app.expense.changeDeleted';
  static const String expenseChangeBefore = 'app.expense.changeBefore';
  static const String expenseOpen = 'app.expense.open';
  static const String expenseFormerMember = 'app.expense.formerMember';
  static const String expensePdfSection = 'app.expense.pdfSection';
  static const String expensePdfLead = 'app.expense.pdfLead';
  static const String expensePdfEmpty = 'app.expense.pdfEmpty';
  static const String expensePdfTotals = 'app.expense.pdfTotals';
  static const String expensePdfSettlements = 'app.expense.pdfSettlements';
  static const String expensePdfSettlement = 'app.expense.pdfSettlement';
  static const String expensePdfChanges = 'app.expense.pdfChanges';
  static const String expensePdfChange = 'app.expense.pdfChange';
  static const String expensePdfUpdated = 'app.expense.pdfUpdated';
  static const String expensePdfDeleted = 'app.expense.pdfDeleted';
  // ── F-35: the family's Conversa ──
  static const String chatNav = 'app.chat.nav';
  static const String chatTabChat = 'app.chat.tabChat';
  static const String chatTabNotifications = 'app.chat.tabNotifications';
  static const String chatTabCount = 'app.chat.tabCount';
  static const String chatNotice = 'app.chat.notice';
  static const String chatEmpty = 'app.chat.empty';
  static const String chatHint = 'app.chat.hint';
  static const String chatSend = 'app.chat.send';
  static const String chatReply = 'app.chat.reply';
  static const String chatQuoting = 'app.chat.quoting';
  static const String chatCancelQuote = 'app.chat.cancelQuote';
  static const String chatCiteDay = 'app.chat.citeDay';
  static const String chatCitedDay = 'app.chat.citedDay';
  static const String chatRemoveDay = 'app.chat.removeDay';
  static const String chatReadBy = 'app.chat.readBy';
  static const String chatNotRead = 'app.chat.notRead';
  static const String chatReadEntry = 'app.chat.readEntry';
  static const String chatSearch = 'app.chat.search';
  static const String chatSearchClose = 'app.chat.searchClose';
  static const String chatSearchEmpty = 'app.chat.searchEmpty';
  static const String chatMute = 'app.chat.mute';
  static const String chatMuteLead = 'app.chat.muteLead';
  static const String chatMuted = 'app.chat.muted';
  static const String chatUnmuted = 'app.chat.unmuted';
  static const String chatReadOnly = 'app.chat.readOnly';
  static const String chatPremium = 'app.chat.premium';
  static const String chatOff = 'app.chat.off';
  static const String chatErrLoad = 'app.chat.errLoad';
  static const String chatTooLong = 'app.chat.tooLong';
  static const String chatYou = 'app.chat.you';
  static const String chatFormerMember = 'app.chat.formerMember';
  static const String chatSendFailed = 'app.chat.sendFailed';
  static const String chatPdfInclude = 'app.chat.pdfInclude';
  static const String chatPdfSection = 'app.chat.pdfSection';
  static const String chatPdfLead = 'app.chat.pdfLead';
  static const String chatPdfEmpty = 'app.chat.pdfEmpty';
  static const String chatPdfReply = 'app.chat.pdfReply';

  static const List<String> allKeys = [
    sessionRestoredExpired,
    sessionExpired,
    errCalendarLoad,
    sheetNoResponsible,
    sheetPlanned,
    sheetHandoffAt,
    sheetNote,
    sheetWhoQuestion,
    sheetSave,
    errDaySave,
    errSwapPendingExists,
    errConcurrentSaveRetry,
    editorRetroBeyondFree,
    editorRetroBeyondPremium,
    bulkProgressSaving,
    wizErrTooFewBlocks,
    wizErrBlockDays,
    wfProgressProcessing,
    commonShare,
    commonMoreActions,
    sudoErrCooldown,
    sudoErrNoSession,
    sudoErrWrongPassword,
    sudoErrGeneric,
    sudoErrConnection,
    sudoSendCode,
    sudoSendingCode,
    sudoCodeSentTo,
    sudoCodeLabel,
    sudoUsePassword,
    sudoErrCodeShape,
    sudoErrCodeSend,
    profErrNameTooShort,
    profErrPasswordShort,
    rolesCreateTitle,
    rolesEditTitle,
    rolesToastUpdated,
    rolesNoEmoji,
    inviteErrRoleRequired,
    shellUnderConstructionTitle,
    shellUnderConstructionBody,
    storeManage,
    storeRestore,
    storeUnavailable,
    storePending,
    storeErrPurchase,
    storeToastActive,
    authGoogle,
    authGoogleErr,
    onbFounderTitle,
    onbFounderSubtitle,
    onbFounderCta,
    onbClaimCta,
    onbSubmitting,
    onbSwitchAccount,
    onbSignedInAs,
    onbErrGeneric,
    signupStep,
    signupStepAccount,
    signupStepFamily,
    signupContinue,
    signupBack,
    roleOther,
    roleOtherTitle,
    profLoginMethod,
    profLoginMethodGoogle,
    profLoginMethodNote,
    profLoginMethodsIntro,
    profLoginMethodPassword,
    profLoginMethodPasswordNote,
    profLoginMethodGoogleLinkedNote,
    profLoginMethodGoogleNeutralNote,
    profLoginMethodOther,
    profLoginMethodOtherNote,
    profEditData,
    profPasswordSummary,
    pushTitle,
    pushHintOff,
    pushHintOn,
    pushHintUnsupported,
    pushHintInstallIos,
    pushInstallHow,
    pushHintNeedsSafari,
    pushHintReallowApp,
    pushHintReallowIos,
    pushHintReallowBrowser,
    pushHintUnsupportedHere,
    pushEnable,
    pushDisable,
    pushStatusOnTooltip,
    pushToastOn,
    pushToastOff,
    pushErrEnable,
    onbStepPushTitle,
    onbStepPushHint,
    onbStepPushDoneHint,
    onbStepPushAction,
    famPendingBadge,
    famPendingHint,
    famInviteName,
    famInviteNameHint,
    famInviteEmailOptional,
    famAddWithoutInvite,
    famPendingAdded,
    famPendingInvite,
    famPendingInviteTitle,
    famPendingRemove,
    famPendingRemoveConfirm,
    famPendingRemoved,
    famPendingRemoveTitle,
    famRevokeTitle,
    famRevokeConfirm,
    famAttachInvite,
    famAttachTitle,
    famAttachHint,
    famAttached,
    inviteErrNameRequired,
    sheetSwapUnavailablePending,
    calMemberPending,
    onbStepInviteDoneHintPending,
    auditActionPendingAdded,
    auditActionPendingRemoved,
    auditActionPendingClaimed,
    handoffBanner,
    handoffOpen,
    handoffDismiss,
    installHintBanner,
    installHintHow,
    installHintDismiss,
    installHintTitle,
    installHintSubtitle,
    installHintStepShare,
    installHintStepAdd,
    installHintNote,
    offlineStrip,
    offlineStripNoData,
    offlineMonthNotLoaded,
    offlineWriteBlocked,
    famPlanRow,
    helpTitle,
    helpProfileRowSub,
    helpLoginLink,
    helpIntro,
    helpCategoryLabel,
    helpCatQuestion,
    helpCatProblem,
    helpCatSuggestion,
    helpCatPrivacy,
    helpCatOther,
    helpMessageLabel,
    helpMessageHint,
    helpMessageTooShort,
    helpEmailLabel,
    helpEmailInvalid,
    helpReplyTo,
    helpDiagLabel,
    helpDiagHelper,
    helpDiagPreview,
    helpDiagVersion,
    helpDiagChannel,
    helpDiagPlatform,
    helpDiagLanguage,
    helpDiagRoute,
    helpSend,
    helpSentTitle,
    helpSentBody,
    helpBack,
    helpErrRateLimited,
    helpErrSendFailed,
    helpErrOffline,
    helpErrFailed,
    helpMailtoLead,
    famPlanRowFree,
    famPlanRowTrialOne,
    famPlanRowTrialMany,
    famPlanRowPremiumUntil,
    famPlanRowPremium,
    famAdminRow,
    famAdminRowOn,
    famAdminRowOff,
    famDelReqUnavailable,
    appearanceLabel,
    appearanceHint,
    appearanceAriaLabel,
    appearanceLight,
    appearanceDark,
    appearanceSystem,
    noticeAction,
    noticeTitle,
    noticeSubtitle,
    noticeReasonLabel,
    noticeReasonDelay,
    noticeReasonMedical,
    noticeReasonTraffic,
    noticeReasonOther,
    noticeEtaLabel,
    noticeEtaMinutes,
    noticeEtaNone,
    noticeRequestLabel,
    noticeRequestInfo,
    noticeRequestPickup,
    noticeRequestKeep,
    noticeConsequenceInfo,
    noticeConsequencePickup,
    noticeConsequenceKeep,
    noticeConsequenceKeepClearsEta,
    noticeConsequenceKeepNotMyDay,
    noticeNoteLabel,
    noticeNoteHint,
    noticeSend,
    noticeCapHint,
    noticeCapReached,
    noticeSent,
    noticeErrSend,
    noticeOpenMine,
    noticeCancel,
    noticeCancelConfirm,
    noticeCancelKeep,
    noticeCancelled,
    noticeErrCancel,
    noticeAnswerTitle,
    noticeAnswerHelping,
    noticeAnswerKeeping,
    noticeAnswerHelpingWhat,
    noticeAnswerKeepingWhat,
    noticeAnswerNoteLabel,
    noticeAnswerNoteHint,
    noticeAnswerSend,
    noticeAnsweredHelping,
    noticeAnsweredKeeping,
    noticeErrAnswer,
    adminOfferEditPastDay,
    adminOfferClearDay,
    adminOfferChangePlanned,
    adminOfferBulkClear,
    adminOfferBulkOverwrite,
    adminOfferWizardReplace,
    adminOfferClearMonth,
    adminOfferHow,
    adminOfferCorrectPlan,
    adminOfferBulkBanner,
    dayAccountErrEmpty,
    dayAccountErrTooLong,
    dayAccountByline,
    dayAccountCorrected,
    dayAccountSection,
    dayAccountAction,
    dayAccountFieldLabel,
    dayAccountFieldHint,
    dayAccountAppendOnly,
    dayAccountSave,
    dayAccountCorrect,
    dayAccountCorrecting,
    dayAccountOutOfWindow,
    dayAccountCapLeftOne,
    dayAccountCapLeftMany,
    dayAccountCapReached,
    dayAccountSaved,
    dayAccountErrSave,
    dayAccountErrLoad,
    dayAccountAuditNew,
    dayAccountAuditCorrection,
    pdfDayAccountsSection,
    pdfDayAccountsLead,
    pdfDayAccountsEmpty,
    pdfDayAccountLine,
    pdfDayAccountCorrectionLine,
    famChildRow,
    famChildRowEmpty,
    childAnd,
    childTitle,
    childLead,
    childEmpty,
    childAdminOnly,
    childNameLabel,
    childAdd,
    childRename,
    childRemove,
    childRemoveConfirm,
    childAdded,
    childRenamed,
    childRemoved,
    childErrLoad,
    agendaSection,
    agendaKindSchool,
    agendaKindHealth,
    agendaKindMedicine,
    agendaKindActivity,
    agendaKindFree,
    agendaKindNote,
    agendaKindOther,
    agendaAdd,
    agendaEmpty,
    agendaNewTitle,
    agendaEditTitle,
    agendaKindLabel,
    agendaChildLabel,
    agendaStartLabel,
    agendaEndLabel,
    agendaNoTime,
    agendaClearTime,
    agendaBodyLabel,
    agendaNoteBodyLabel,
    agendaDelete,
    agendaDeleteConfirm,
    agendaSaved,
    agendaDeleted,
    agendaErrLoad,
    agendaFreeNotesOne,
    agendaFreeNotesMany,
    agendaReadOnlyPast,
    agendaReadOnlyPremium,
    agendaNoChildAdmin,
    agendaNoChildMember,
    agendaBy,
    agendaFromObservation,
    agendaAuditAdded,
    agendaAuditDeleted,
    agendaPdfSection,
    agendaPdfLead,
    agendaPdfEmpty,
    viewerBadge,
    viewerSection,
    viewerInviteButton,
    viewerReadOnly,
    viewerInviteLead,
    viewerInviteNeedsEmail,
    viewerFreeCapOne,
    viewerFreeCapMany,
    viewerMaxCap,
    viewerInviteSent,
    viewerPromote,
    viewerPromoteConfirm,
    viewerPromoted,
    viewerRemove,
    viewerRemoveConfirm,
    viewerRemoved,
    viewerLeaveBody,
    viewerLeaveButton,
    viewerInvitedBody,
    attestPageTitle,
    attestValid,
    attestPending,
    attestRevoked,
    attestExpired,
    attestUnknown,
    attestError,
    attestIssuedAt,
    attestPeriod,
    attestValidUntil,
    attestFingerprint,
    attestSummary,
    attestDaysPlanned,
    attestDaysBy,
    attestDaysSwapped,
    attestSwaps,
    attestDayAccounts,
    attestInitialsNote,
    attestCompare,
    attestCompareHint,
    attestMatch,
    attestMismatch,
    attestNoPicker,
    attestSection,
    attestSectionLead,
    attestRowState,
    attestStateValid,
    attestStatePending,
    attestStateRevoked,
    attestStateExpired,
    attestRevoke,
    attestRevokeConfirm,
    attestRevoked2,
    attestHashFailed,
    agendaNotifyLabel,
    agendaNotifyNone,
    agendaNotifySelf,
    agendaNotifyResponsible,
    agendaNotifyFamily,
    agendaNotifyPush,
    agendaNotifyInApp,
    agendaNotifyLead,
    agendaRemindLabel,
    agendaRemindNone,
    agendaRemindAtStart,
    agendaRemindBefore,
    agendaRemindNeedsStart,
    agendaRepeat,
    agendaRepeatLead,
    agendaRepeatDays,
    agendaRoutineApplied,
    agendaRoutinePart,
    agendaRoutineEdit,
    agendaRoutineEditTitle,
    agendaRoutineEditLead,
    agendaRoutineStop,
    agendaRoutineStopConfirm,
    agendaRoutineStopped,
    agendaAuditRoutineAdded,
    agendaAuditRoutineDeleted,
    expenseNav,
    expenseLead,
    expenseErrLoad,
    expenseOff,
    expenseViewer,
    expensePremium,
    expenseAdd,
    expenseEdit,
    expenseEmpty,
    expenseEmptyBody,
    expenseGroupFamily,
    expenseGroupLabel,
    expenseBalance,
    expenseBalanceEven,
    expensePays,
    expenseNetGets,
    expenseNetOwes,
    expenseSettle,
    expenseSettleTitle,
    expenseSettleLead,
    expenseSettleTo,
    expenseSettleNobody,
    expenseAmount,
    expenseSettleSent,
    expensePending,
    expensePendingToMe,
    expensePendingFromMe,
    expensePendingOthers,
    expenseConfirm,
    expenseReject,
    expenseTakeBack,
    expenseConfirmed,
    expenseRejected,
    expenseTakenBack,
    expenseListSection,
    expenseRow,
    expenseDesc,
    expenseCategory,
    expenseDate,
    expensePaidBy,
    expenseSplit,
    expenseSplitEqual,
    expenseSplitExact,
    expenseSplitPercent,
    expenseSplitShares,
    expenseParticipants,
    expenseValueExact,
    expenseValuePercent,
    expenseValueShares,
    expenseShareOf,
    expenseErrNoParts,
    expenseErrExact,
    expenseErrPercent,
    expenseErrZero,
    expenseErrAmount,
    expenseErrMax,
    expenseErrDesc,
    expenseErrDescLong,
    expenseSaved,
    expenseDelete,
    expenseDeleteConfirm,
    expenseDeleted,
    expenseDetailSplit,
    expenseChanges,
    expenseChangeCreated,
    expenseChangeUpdated,
    expenseChangeDeleted,
    expenseChangeBefore,
    expenseOpen,
    expenseFormerMember,
    expensePdfSection,
    expensePdfLead,
    expensePdfEmpty,
    expensePdfTotals,
    expensePdfSettlements,
    expensePdfSettlement,
    expensePdfChanges,
    expensePdfChange,
    expensePdfUpdated,
    expensePdfDeleted,
    chatNav,
    chatTabChat,
    chatTabNotifications,
    chatTabCount,
    chatNotice,
    chatEmpty,
    chatHint,
    chatSend,
    chatReply,
    chatQuoting,
    chatCancelQuote,
    chatCiteDay,
    chatCitedDay,
    chatRemoveDay,
    chatReadBy,
    chatNotRead,
    chatReadEntry,
    chatSearch,
    chatSearchClose,
    chatSearchEmpty,
    chatMute,
    chatMuteLead,
    chatMuted,
    chatUnmuted,
    chatReadOnly,
    chatPremium,
    chatOff,
    chatErrLoad,
    chatTooLong,
    chatYou,
    chatFormerMember,
    chatSendFailed,
    chatPdfInclude,
    chatPdfSection,
    chatPdfLead,
    chatPdfEmpty,
    chatPdfReply,
  ];
}

/// PT-BR — the original text of this client, verbatim from the stage-1 spike.
abstract final class StringsAppPtBr {
  static const Map<String, String> values = {
    KApp.sessionRestoredExpired: 'Sua sessão anterior expirou.',
    KApp.sessionExpired: 'Sessão expirada — saia e entre novamente.',
    KApp.errCalendarLoad: 'Não foi possível carregar o calendário.',
    KApp.sheetNoResponsible: 'Dia sem responsável definido.',
    KApp.sheetPlanned: 'Planejado: {0}',
    KApp.sheetHandoffAt: 'Troca às {0}',
    KApp.sheetNote: 'Observação: {0}',
    KApp.sheetWhoQuestion: 'Quem fica com a criança neste dia?',
    KApp.sheetSave: 'Salvar',
    KApp.errDaySave: 'Não foi possível salvar o dia.',
    KApp.errSwapPendingExists:
        'Já existe uma solicitação pendente para este dia — o calendário foi '
            'atualizado.',
    KApp.errConcurrentSaveRetry:
        'Outro responsável salvou este dia primeiro — atualize o calendário e '
            'tente novamente.',
    KApp.editorRetroBeyondFree:
        'O plano gratuito corrige apenas os últimos {0} dias. Ative o Premium '
            'para corrigir dias mais antigos (até {1} meses).',
    KApp.editorRetroBeyondPremium:
        'Correções retroativas vão até {0} meses atrás.',
    KApp.bulkProgressSaving: 'Salvando {0}/{1}...',
    KApp.wizErrTooFewBlocks: 'O ciclo deve ter pelo menos 1 bloco.',
    KApp.wizErrBlockDays: 'Cada bloco deve ter pelo menos 1 dia.',
    KApp.wfProgressProcessing: 'Processando {0}/{1}...',
    KApp.commonShare: 'Compartilhar',
    KApp.commonMoreActions: 'Mais ações',
    KApp.sudoErrCooldown: 'Muitas tentativas. Aguarde {0} segundos.',
    KApp.sudoErrNoSession: 'Sessão inválida. Entre novamente.',
    KApp.sudoErrWrongPassword: 'Senha incorreta.',
    KApp.sudoErrGeneric: 'Não foi possível confirmar. Tente novamente.',
    KApp.sudoErrConnection:
        'Falha na conexão com o servidor. Verifique sua internet e tente '
            'novamente.',
    KApp.sudoSendCode: 'Receber um código por e-mail',
    KApp.sudoSendingCode: 'Enviando...',
    KApp.sudoCodeSentTo:
        'Enviamos um código para {0}. Ele vale por {1} minutos.',
    KApp.sudoCodeLabel: 'Código de 6 dígitos',
    KApp.sudoUsePassword: 'Confirmar com a senha',
    KApp.sudoErrCodeShape: 'O código tem 6 dígitos.',
    KApp.sudoErrCodeSend:
        'Não foi possível enviar o código. Tente novamente.',
    KApp.profErrNameTooShort: 'Informe um nome com pelo menos 2 caracteres.',
    KApp.profErrPasswordShort: 'A senha precisa ter pelo menos 8 caracteres.',
    KApp.rolesCreateTitle: 'Criar papel',
    KApp.rolesEditTitle: 'Editar papel',
    KApp.rolesToastUpdated: 'Papel atualizado!',
    KApp.rolesNoEmoji: 'Sem emoji',
    KApp.inviteErrRoleRequired: 'Selecione o papel da pessoa convidada.',
    KApp.shellUnderConstructionTitle: 'Em construção',
    KApp.shellUnderConstructionBody:
        'Esta tela chega em uma próxima atualização.',
    KApp.storeManage: 'Gerenciar assinatura no Google Play',
    KApp.storeRestore: 'Já assinei — restaurar compra',
    KApp.storeUnavailable:
        'A loja não respondeu agora. Tente de novo em instantes — se você já '
            'assinou, seu Premium continua valendo.',
    KApp.storePending:
        'Estamos confirmando sua compra com o Google. Isso costuma levar '
            'alguns segundos.',
    KApp.storeErrPurchase:
        'Não foi possível concluir a compra. Nada foi cobrado sem confirmação '
            'do Google.',
    KApp.storeToastActive: 'Premium ativo!',
    KApp.authGoogle: 'Continuar com Google',
    KApp.authGoogleErr:
        'Não foi possível abrir o login do Google. Tente novamente.',
    KApp.onbFounderTitle: 'Complete seu cadastro',
    KApp.onbFounderSubtitle:
        'Sua conta Google está pronta. Agora conte quem você é para criar a '
            'sua família.',
    KApp.onbFounderCta: 'Criar minha família',
    KApp.onbClaimCta: 'Entrar na família',
    KApp.onbSubmitting: 'Enviando...',
    KApp.onbSwitchAccount: 'Entrar com outra conta',
    KApp.onbSignedInAs: 'Conectado como {0}',
    KApp.onbErrGeneric: 'Não foi possível concluir o cadastro. Tente novamente.',
    KApp.signupStep: 'Passo {0} de {1} · {2}',
    KApp.signupStepAccount: 'Sua conta',
    KApp.signupStepFamily: 'Sua família',
    KApp.signupContinue: 'Continuar',
    KApp.signupBack: 'Voltar',
    KApp.roleOther: 'Outro…',
    KApp.roleOtherTitle: 'Qual é o seu papel na família?',
    KApp.profLoginMethod: 'Como você entra',
    KApp.profLoginMethodGoogle: 'Conta Google',
    KApp.profLoginMethodNote:
        'Você entra com sua conta Google — não há senha para alterar aqui.',
    KApp.profLoginMethodsIntro:
        'Esta conta tem mais de uma porta de entrada. Qualquer uma delas abre '
            'o login sozinha.',
    KApp.profLoginMethodPassword: 'E-mail e senha',
    KApp.profLoginMethodPasswordNote:
        'Seu e-mail e a senha que você define na seção Senha, abaixo.',
    KApp.profLoginMethodGoogleLinkedNote:
        'Abre este login sozinha — mesmo depois de você trocar a senha ou o '
            'e-mail nesta tela.',
    KApp.profLoginMethodGoogleNeutralNote: 'Abre este login sozinha.',
    KApp.profLoginMethodOther: 'Outro provedor: {0}',
    KApp.profLoginMethodOtherNote: 'Abre este login sozinho.',
    KApp.profEditData: 'Editar dados',
    KApp.profPasswordSummary:
        'Senha definida. Altere aqui ou redefina por e-mail.',
    KApp.pushTitle: 'Notificações no celular',
    KApp.pushHintOff:
        'Receba uma notificação quando alguém pedir uma troca ou responder a sua — '
            'mesmo com o app fechado.',
    KApp.pushHintOn: 'Este aparelho recebe notificações de trocas e prazos.',
    KApp.pushHintUnsupported:
        'Notificações no celular funcionam no aplicativo instalado. Aqui no '
            'navegador, você continua vendo tudo nesta tela e por e-mail.',
    KApp.pushHintInstallIos:
        'No iPhone, as notificações só funcionam com o Entrelares na Tela de '
            'Início.',
    KApp.pushInstallHow: 'Como instalar',
    KApp.pushHintNeedsSafari:
        'No iPhone, as notificações só funcionam com o Entrelares na Tela de '
            'Início. Para instalar, abra este endereço no Safari — os passos '
            'que mostramos são os dele.',
    KApp.pushHintReallowApp:
        'As notificações do Entrelares estão bloqueadas neste aparelho. Para '
            'liberar: abra Configurações > Notificações > Notificações de apps, '
            'toque em Entrelares e ative as notificações. Os nomes podem variar '
            'conforme o fabricante.',
    KApp.pushHintReallowIos:
        'As notificações do Entrelares estão bloqueadas neste iPhone. Para '
            'liberar: abra Ajustes > Notificações, toque em Entrelares e ative '
            'Permitir Notificações.',
    KApp.pushHintReallowBrowser:
        'As notificações do Entrelares estão bloqueadas neste navegador. Para '
            'liberar: toque no ícone à esquerda do endereço, ative Notificações '
            'e recarregue a página.',
    KApp.pushHintUnsupportedHere:
        'Este aparelho não recebe notificações do Entrelares. Você continua '
            'vendo tudo nesta tela e por e-mail.',
    KApp.pushEnable: 'Ativar notificações',
    KApp.pushDisable: 'Desativar',
    KApp.pushStatusOnTooltip: 'Notificações no celular: ativadas',
    KApp.pushToastOn: 'Notificações ativadas neste aparelho.',
    KApp.pushToastOff: 'Notificações desativadas neste aparelho.',
    KApp.pushErrEnable:
        'Não foi possível ativar as notificações agora. Você continua recebendo '
            'tudo nesta tela e por e-mail.',
    KApp.onbStepPushTitle: 'Ativar notificações no celular',
    KApp.onbStepPushHint:
        'Uma troca costuma ser pedida em cima da hora. Com as notificações ligadas '
            'você fica sabendo na mesma hora, mesmo com o app fechado.',
    KApp.onbStepPushDoneHint:
        'Este aparelho notifica você sobre pedidos de troca e prazos.',
    KApp.onbStepPushAction: 'Ativar notificações',
    KApp.famPendingBadge: 'Ainda não entrou',
    KApp.famPendingHint:
        'Sem conta ainda: você planeja os dias dessa pessoa, e as trocas '
            'ficam disponíveis quando ela entrar.',
    KApp.famInviteName: 'Nome',
    KApp.famInviteNameHint: 'Como essa pessoa aparece no calendário',
    KApp.famInviteEmailOptional:
        'Opcional: com o e-mail, o convite sai agora. Sem ele, você planeja '
            'os dias e convida depois.',
    KApp.famAddWithoutInvite: 'Adicionar ao calendário',
    KApp.famPendingAdded:
        '{0} já aparece no calendário. Convide quando fizer sentido.',
    KApp.famPendingInvite: 'Convidar',
    KApp.famPendingInviteTitle: 'Convidar {0}',
    KApp.famPendingRemove: 'Remover',
    KApp.famPendingRemoveConfirm:
        'Remover {0} do calendário? Os dias futuros planejados para essa '
            'pessoa serão liberados; os passados ficam no histórico.',
    KApp.famPendingRemoved: '{0} foi removido do calendário.',
    KApp.famPendingRemoveTitle: 'Remover {0}',
    KApp.famRevokeTitle: 'Revogar convite',
    KApp.famRevokeConfirm:
        'Revogar o convite de {0}? O link que essa pessoa recebeu deixa de '
            'funcionar.',
    KApp.famAttachInvite: 'Adicionar ao calendário',
    KApp.famAttachTitle: 'Adicionar {0} ao calendário',
    KApp.famAttachHint:
        'Você já pode planejar os dias dessa pessoa. O convite enviado '
            'continua valendo — é o mesmo link.',
    KApp.famAttached:
        '{0} já aparece no calendário. O convite enviado continua valendo.',
    KApp.inviteErrNameRequired:
        'Informe o nome de quem você está adicionando.',
    KApp.sheetSwapUnavailablePending:
        '{0} ainda não entrou no aplicativo. Você pode mudar o responsável '
            'planejado; a troca fica disponível quando a conta for criada.',
    KApp.calMemberPending: '(pendente)',
    KApp.onbStepInviteDoneHintPending:
        'O outro responsável já está no calendário. Convide quando fizer '
            'sentido.',
    KApp.auditActionPendingAdded: 'Responsável adicionado ao calendário',
    KApp.auditActionPendingRemoved: 'Responsável removido do calendário',
    KApp.auditActionPendingClaimed: 'Responsável entrou pelo convite',
    KApp.handoffBanner: 'Você já tem o app neste aparelho.',
    KApp.handoffOpen: 'Abrir no app',
    KApp.handoffDismiss: 'Agora não',
    KApp.installHintBanner: 'Coloque o Entrelares na sua Tela de Início.',
    KApp.installHintHow: 'Como fazer',
    KApp.installHintDismiss: 'Agora não',
    KApp.installHintTitle: 'Instalar no iPhone ou iPad',
    KApp.installHintSubtitle:
        'O Entrelares abre como um app, com ícone na sua tela, sem loja. '
            'Dois toques no Safari:',
    KApp.installHintStepShare:
        'Toque no botão <strong>Compartilhar</strong> (quadrado com seta '
            'para cima). Se ele não estiver à vista, toque em '
            '<strong>⋯</strong> e escolha <strong>Compartilhar</strong>.',
    KApp.installHintStepAdd:
        '<strong>Role a lista</strong> até <strong>Adicionar à Tela de '
            'Início</strong>, ative <strong>Abrir como App da Web</strong> (se '
            'aparecer) e toque em <strong>Adicionar</strong>.',
    KApp.installHintNote:
        'Os nomes dos botões podem variar um pouco conforme a versão do iOS.',
    KApp.offlineStrip: 'Sem conexão · dados de {0}',
    KApp.offlineStripNoData: 'Sem conexão · nada carregado ainda',
    KApp.offlineMonthNotLoaded:
        'Sem conexão — este mês ainda não foi carregado neste aparelho.',
    KApp.offlineWriteBlocked:
        'Sem conexão — conecte-se para fazer alterações. Nada foi enviado.',
    // ── U-35 Família split ──
    KApp.famPlanRow: 'Plano e pagamento',
    KApp.helpTitle: 'Ajuda e contato',
    KApp.helpProfileRowSub: 'Tire uma dúvida ou conte um problema',
    KApp.helpLoginLink: 'Precisa de ajuda?',
    KApp.helpIntro: 'Escreva para a equipe do Entrelares — uma dúvida, um problema, uma sugestão. A resposta chega por e-mail.',
    KApp.helpCategoryLabel: 'Sobre o quê?',
    KApp.helpCatQuestion: 'Dúvida',
    KApp.helpCatProblem: 'Problema ou erro',
    KApp.helpCatSuggestion: 'Sugestão',
    KApp.helpCatPrivacy: 'Privacidade e dados',
    KApp.helpCatOther: 'Outro',
    KApp.helpMessageLabel: 'Mensagem',
    KApp.helpMessageHint: 'Conte o que aconteceu ou o que você quer saber.',
    KApp.helpMessageTooShort: 'Escreva pelo menos {0} caracteres.',
    KApp.helpEmailLabel: 'Seu e-mail, para a resposta',
    KApp.helpEmailInvalid: 'Informe um e-mail válido.',
    KApp.helpReplyTo: 'A resposta vai para {0}.',
    KApp.helpDiagLabel: 'Incluir informações técnicas',
    KApp.helpDiagHelper: 'Ajuda a entender um problema. Nunca inclui o seu calendário nem dados da família.',
    KApp.helpDiagPreview: 'Ver o que será enviado',
    KApp.helpDiagVersion: 'Versão',
    KApp.helpDiagChannel: 'Canal',
    KApp.helpDiagPlatform: 'Sistema',
    KApp.helpDiagLanguage: 'Idioma',
    KApp.helpDiagRoute: 'Tela',
    KApp.helpSend: 'Enviar',
    KApp.helpSentTitle: 'Mensagem enviada',
    KApp.helpSentBody: 'Pedido #{0}. Respondemos em até 2 dias úteis, no e-mail {1}.',
    KApp.helpBack: 'Voltar',
    KApp.helpErrRateLimited: 'Você enviou várias mensagens em pouco tempo. Tente de novo mais tarde, ou escreva direto para {0}.',
    KApp.helpErrSendFailed: 'Não conseguimos entregar sua mensagem agora. Escreva direto para {0}.',
    KApp.helpErrOffline: 'Sem conexão. A mensagem não foi enviada — tente de novo quando tiver sinal.',
    KApp.helpErrFailed: 'Não foi possível enviar. Tente de novo, ou escreva para {0}.',
    KApp.helpMailtoLead: 'Prefere escrever por e-mail?',
    KApp.famPlanRowFree: 'Gratuito',
    KApp.famPlanRowTrialOne: 'Avaliação Premium — {0} dia restante',
    KApp.famPlanRowTrialMany: 'Avaliação Premium — {0} dias restantes',
    KApp.famPlanRowPremiumUntil: 'Premium até {0}',
    KApp.famPlanRowPremium: 'Premium',
    KApp.famAdminRow: 'Modo administrador',
    KApp.famAdminRowOn: 'Ativo',
    KApp.famAdminRowOff: 'Desativado',
    KApp.famDelReqUnavailable:
        'Não há pedido de exclusão para abrir aqui. Só um administrador com outros responsáveis na família pode abrir um — e um pedido já aberto aparece na tela Família.',
    // ── U-12 ──
    KApp.appearanceLabel: 'Aparência',
    KApp.appearanceHint:
        'Guardada só neste aparelho. "Sistema" segue o tema que o aparelho '
            'já usa.',
    KApp.appearanceAriaLabel: 'Escolher tema',
    KApp.appearanceLight: 'Claro',
    KApp.appearanceDark: 'Escuro',
    KApp.appearanceSystem: 'Sistema',
    // ── F-52 ──
    KApp.noticeAction: 'Enviar um aviso',
    KApp.noticeTitle: 'Aviso de imprevisto',
    KApp.noticeSubtitle:
        'Para o dia de hoje. Um aviso sozinho não muda quem está com a '
            'criança.',
    KApp.noticeReasonLabel: 'O que aconteceu',
    KApp.noticeReasonDelay: 'Vou atrasar',
    KApp.noticeReasonMedical: 'Imprevisto médico',
    KApp.noticeReasonTraffic: 'Trânsito',
    KApp.noticeReasonOther: 'Outro',
    KApp.noticeEtaLabel: 'Previsão',
    KApp.noticeEtaMinutes: '{0} min',
    KApp.noticeEtaNone: 'Sem previsão',
    KApp.noticeRequestLabel: 'O que você precisa',
    KApp.noticeRequestInfo: 'Só avisando',
    KApp.noticeRequestPickup: 'Alguém pode buscar a criança?',
    KApp.noticeRequestKeep: 'Alguém pode ficar com a criança hoje?',
    KApp.noticeConsequenceInfo:
        'Ninguém precisa responder e o calendário não muda.',
    KApp.noticeConsequencePickup:
        'Quem receber pode se oferecer para ajudar agora. O calendário não '
            'muda: o dia de hoje continua sendo seu.',
    KApp.noticeConsequenceKeep:
        'Quem receber pode se oferecer para ficar com a criança. Se alguém '
            'aceitar, uma troca já aprovada passa o dia de hoje para essa '
            'pessoa, sem precisar de outra confirmação sua. Você verá quem '
            'aceitou, e a troca fica no histórico.',
    KApp.noticeConsequenceKeepClearsEta:
        'Escolher esta opção tira a previsão de tempo: um atraso com hora '
            'marcada não passa o dia para ninguém.',
    KApp.noticeConsequenceKeepNotMyDay:
        'Só quem está com o dia de hoje pode oferecê-lo. Hoje o dia é de '
            'outra pessoa.',
    KApp.noticeNoteLabel: 'Detalhe (opcional)',
    KApp.noticeNoteHint: 'Onde você está, o que ajuda quem for responder',
    KApp.noticeSend: 'Enviar aviso',
    KApp.noticeCapHint: 'Você pode enviar até {0} avisos por dia.',
    KApp.noticeCapReached:
        'Você já enviou {0} avisos hoje. O limite volta amanhã.',
    KApp.noticeSent: 'Aviso enviado.',
    KApp.noticeErrSend: 'Não foi possível enviar o aviso.',
    KApp.noticeOpenMine: 'Seu aviso de hoje está aberto.',
    KApp.noticeCancel: 'Cancelar aviso',
    KApp.noticeCancelConfirm:
        'Cancelar este aviso? Quem recebeu será informado de que não é mais '
            'necessário. Ele continua contando no seu limite do dia.',
    KApp.noticeCancelKeep: 'Manter',
    KApp.noticeCancelled: 'Aviso cancelado.',
    KApp.noticeErrCancel: 'Não foi possível cancelar o aviso.',
    KApp.noticeAnswerTitle: 'Responder ao aviso',
    KApp.noticeAnswerHelping: 'Vou ajudar agora',
    KApp.noticeAnswerKeeping: 'Vou ficar com a criança hoje',
    KApp.noticeAnswerHelpingWhat:
        'Quem enviou o aviso é informado de que você vai ajudar. O calendário '
            'não muda: o dia de hoje continua com quem já está.',
    KApp.noticeAnswerKeepingWhat:
        'Uma troca já aprovada passa o dia de hoje para você, agora — foi o '
            'que quem enviou o aviso pediu. Ela fica no histórico, com a data '
            'e quem fez, e pode ser revertida como qualquer outra troca.',
    KApp.noticeAnswerNoteLabel: 'Detalhe (opcional)',
    KApp.noticeAnswerNoteHint: 'Onde você vai estar, a que horas você chega',
    KApp.noticeAnswerSend: 'Enviar resposta',
    KApp.noticeAnsweredHelping: 'Resposta enviada.',
    KApp.noticeAnsweredKeeping: 'O dia de hoje passou para você.',
    KApp.noticeErrAnswer: 'Não foi possível responder ao aviso.',
    KApp.adminOfferEditPastDay:
        'Corrigir um dia que já passou exige o modo administrador. A correção '
            'fica registrada como feita pelo administrador, no histórico e no '
            'relatório.',
    KApp.adminOfferClearDay:
        'Limpar um dia já planejado exige o modo administrador.',
    KApp.adminOfferChangePlanned:
        'Mudar quem está planejado num dia já atribuído exige o modo '
            'administrador.',
    KApp.adminOfferBulkClear:
        'Limpar dias planejados exige o modo administrador.',
    KApp.adminOfferBulkOverwrite:
        'Aplicar esta edição aos dias que já passaram e a quem está planejado '
            'nos dias já atribuídos exige o modo administrador.',
    KApp.adminOfferWizardReplace:
        'Substituir os dias já planejados exige o modo administrador.',
    KApp.adminOfferClearMonth:
        'Limpar o mês exige o modo administrador.',
    KApp.adminOfferHow:
        'Ativar agora? Enquanto ele estiver ligado, uma faixa no topo da tela '
            'mostra isso, com o botão Sair.',
    KApp.adminOfferCorrectPlan: 'Corrigir o planejamento',
    KApp.adminOfferBulkBanner:
        'Sem o modo administrador, esta edição pula os dias que já passaram e '
            'mantém quem está planejado nos dias já atribuídos.',
    KApp.dayAccountErrEmpty: 'Escreva o que aconteceu.',
    KApp.dayAccountErrTooLong: 'O relato é limitado a {0} caracteres.',
    KApp.dayAccountByline: 'Registrado por {0} em {1} às {2}',
    KApp.dayAccountCorrected: 'Corrigido em {0} às {1}',
    KApp.dayAccountSection:
        'Relatos do dia',
    KApp.dayAccountAction:
        'Relatar o que aconteceu',
    KApp.dayAccountFieldLabel:
        'O que aconteceu',
    KApp.dayAccountFieldHint:
        'Quem buscou, a que horas, onde deixou',
    KApp.dayAccountAppendOnly:
        'Um relato não pode ser editado nem apagado depois de registrado. Para corrigir, registre uma correção: o texto anterior continua no registro, marcado como corrigido.',
    KApp.dayAccountSave:
        'Registrar relato',
    KApp.dayAccountCorrect:
        'Corrigir',
    KApp.dayAccountCorrecting:
        'Correção do relato registrado em {0}',
    KApp.dayAccountOutOfWindow:
        'Relatos podem ser registrados até {0} dias depois do dia.',
    KApp.dayAccountCapLeftOne:
        'Você ainda pode registrar 1 relato hoje.',
    KApp.dayAccountCapLeftMany:
        'Você ainda pode registrar {0} relatos hoje.',
    KApp.dayAccountCapReached:
        'Você já registrou {0} relatos hoje. O limite volta amanhã.',
    KApp.dayAccountSaved:
        'Relato registrado.',
    KApp.dayAccountErrSave:
        'Não foi possível registrar o relato.',
    KApp.dayAccountErrLoad:
        'Não foi possível carregar os relatos deste dia.',
    KApp.dayAccountAuditNew:
        '{0} registrou um relato',
    KApp.dayAccountAuditCorrection:
        '{0} corrigiu um relato',
    KApp.pdfDayAccountsSection:
        '4. Relatos do dia',
    KApp.pdfDayAccountsLead:
        'Relatos registrados pelos responsáveis depois do dia a que se referem. Um relato não altera o planejamento. Uma correção é um novo relato, e o texto corrigido continua neste documento.',
    KApp.pdfDayAccountsEmpty:
        'Nenhum relato do dia no período.',
    KApp.pdfDayAccountLine:
        'Sobre {0} — registrado por {1} em {2}.',
    KApp.pdfDayAccountCorrectionLine:
        'Sobre {0} — correção registrada por {1} em {2}.',
    // ── F-55 the child entity ──
    KApp.famChildRow: 'Criança',
    KApp.famChildRowEmpty: 'Nenhuma criança cadastrada',
    KApp.childAnd: 'e',
    KApp.childTitle: 'Criança',
    KApp.childLead: 'Só o primeiro nome. O relatório e a agenda do dia usam este nome.',
    KApp.childEmpty: 'Nenhuma criança cadastrada ainda.',
    KApp.childAdminOnly: 'Só um administrador da família cadastra ou muda a criança.',
    KApp.childNameLabel: 'Primeiro nome',
    KApp.childAdd: 'Cadastrar a criança',
    KApp.childRename: 'Mudar o nome',
    KApp.childRemove: 'Remover',
    KApp.childRemoveConfirm: 'Remover {0} da família? A agenda de {0} sai junto.',
    KApp.childAdded: 'Criança cadastrada.',
    KApp.childRenamed: 'Nome atualizado.',
    KApp.childRemoved: 'Criança removida.',
    KApp.childErrLoad: 'Não foi possível carregar a criança.',
    // ── F-55 the day agenda ──
    KApp.agendaSection: 'Agenda',
    KApp.agendaKindSchool: 'Escola',
    KApp.agendaKindHealth: 'Saúde',
    KApp.agendaKindMedicine: 'Remédio',
    KApp.agendaKindActivity: 'Atividade',
    KApp.agendaKindFree: 'Livre',
    KApp.agendaKindNote: 'Nota',
    KApp.agendaKindOther: 'Outro',
    KApp.agendaAdd: 'Adicionar à agenda',
    KApp.agendaEmpty: 'Nada na agenda deste dia.',
    KApp.agendaNewTitle: 'Novo na agenda',
    KApp.agendaEditTitle: 'Editar na agenda',
    KApp.agendaKindLabel: 'Tipo',
    KApp.agendaChildLabel: 'Criança',
    KApp.agendaStartLabel: 'Início',
    KApp.agendaEndLabel: 'Fim',
    KApp.agendaNoTime: 'Sem horário',
    KApp.agendaClearTime: 'Tirar o horário',
    KApp.agendaBodyLabel: 'Texto (opcional)',
    KApp.agendaNoteBodyLabel: 'Texto da nota',
    KApp.agendaDelete: 'Apagar da agenda',
    KApp.agendaDeleteConfirm: 'Apagar este item da agenda? O Histórico guarda quem apagou.',
    KApp.agendaSaved: 'Agenda atualizada.',
    KApp.agendaDeleted: 'Item apagado da agenda.',
    KApp.agendaErrLoad: 'Não foi possível carregar a agenda deste dia.',
    KApp.agendaFreeNotesOne: 'No plano gratuito, a agenda tem {0} nota por dia. Escola, saúde, remédio e atividades são Premium.',
    KApp.agendaFreeNotesMany: 'No plano gratuito, a agenda tem {0} notas por dia. Escola, saúde, remédio e atividades são Premium.',
    KApp.agendaReadOnlyPast: 'Um dia que já passou é só leitura na agenda.',
    KApp.agendaReadOnlyPremium: 'Este item é da agenda Premium e fica só para leitura no plano gratuito.',
    KApp.agendaNoChildAdmin: 'Cadastre a criança em Família para usar a agenda completa.',
    KApp.agendaNoChildMember: 'Para a agenda completa, o administrador cadastra a criança em Família.',
    KApp.agendaBy: 'por {0}',
    KApp.agendaFromObservation: 'da antiga observação do dia',
    KApp.agendaAuditAdded: '{0} adicionou à agenda',
    KApp.agendaAuditDeleted: '{0} apagou da agenda',
    KApp.agendaPdfSection: '5. Agenda da criança',
    KApp.agendaPdfLead: 'O que a família registrou na agenda para os dias do período. A agenda não muda o planejamento: não troca quem fica com a criança em nenhum dia.',
    KApp.agendaPdfEmpty: 'Nenhum item na agenda no período.',
    KApp.viewerBadge: 'Visualizador',
    KApp.viewerSection: 'Visualizadores',
    KApp.viewerInviteButton: 'Convidar visualizador',
    KApp.viewerReadOnly: 'Você é visualizador: acompanha o plano da família sem alterar nada.',
    KApp.viewerInviteLead: 'O visualizador vê o calendário, a agenda e os relatórios, e recebe no app e no celular as notificações informativas. Não altera nada, não entra em trocas, não vê as mensagens das trocas e não recebe e-mail.',
    KApp.viewerInviteNeedsEmail: 'Para convidar um visualizador, informe o e-mail.',
    KApp.viewerFreeCapOne: 'No plano gratuito, a família inclui {0} visualizador. Para convidar mais, ative o Premium.',
    KApp.viewerFreeCapMany: 'No plano gratuito, a família inclui {0} visualizadores. Para convidar mais, ative o Premium.',
    KApp.viewerMaxCap: 'A família já tem {0} visualizadores, o limite.',
    KApp.viewerInviteSent: 'Convite de visualizador enviado.',
    KApp.viewerPromote: 'Promover a responsável',
    KApp.viewerPromoteConfirm: 'Promover {0} a responsável? {0} passa a poder cuidar de dias, pedir e aprovar trocas, e ganha uma cor. Um responsável não volta a ser visualizador.',
    KApp.viewerPromoted: '{0} agora é responsável.',
    KApp.viewerRemove: 'Remover visualizador',
    KApp.viewerRemoveConfirm: 'Remover {0}? A conta de {0} é apagada na hora, com tudo o que era dela.',
    KApp.viewerRemoved: '{0} foi removido da família.',
    KApp.viewerLeaveBody: 'Como visualizador, ao sair você é apagado na hora: sua conta e seus dados. Nada no histórico da família depende de você.',
    KApp.viewerLeaveButton: 'Sair e apagar minha conta',
    KApp.viewerInvitedBody: '{0} convidou você para acompanhar o calendário da família {1} como visualizador: você vê o plano, a agenda e as notificações informativas, sem alterar nada.',
    KApp.attestPageTitle: 'Conferir relatório',
    KApp.attestValid: 'Este relatório foi emitido pelo Entrelares e está válido.',
    KApp.attestPending: 'Este relatório foi iniciado, mas o PDF não foi concluído: não há impressão digital para conferir.',
    KApp.attestRevoked: 'Este relatório foi revogado pela família em {0}. Ele não vale mais como conferência.',
    KApp.attestExpired: 'Este relatório venceu em {0}. A conferência vale por um prazo; depois dele, o resumo é apagado.',
    KApp.attestUnknown: 'Não encontramos este relatório. Confira se o endereço está completo.',
    KApp.attestError: 'Não foi possível consultar agora. Tente de novo em instantes.',
    KApp.attestIssuedAt: 'Emitido em',
    KApp.attestPeriod: 'Período',
    KApp.attestValidUntil: 'Conferível até',
    KApp.attestFingerprint: 'Impressão digital (SHA-256) do PDF',
    KApp.attestSummary: 'O que o Entrelares registrou no período',
    KApp.attestDaysPlanned: 'Dias planejados: {0}',
    KApp.attestDaysBy: '{0}: {1} dia(s)',
    KApp.attestDaysSwapped: 'Dias mudados por troca: {0}',
    KApp.attestSwaps: 'Pedidos de troca: {0}',
    KApp.attestDayAccounts: 'Relatos: {0}',
    KApp.attestInitialsNote: 'Os responsáveis aparecem por iniciais: esta página é pública e não mostra nomes.',
    KApp.attestCompare: 'Conferir um PDF',
    KApp.attestCompareHint: 'Escolha o arquivo (ou arraste-o para esta página). Ele é lido só no seu aparelho: nada é enviado.',
    KApp.attestMatch: 'Confere: este PDF é o documento emitido.',
    KApp.attestMismatch: 'Não confere: este PDF não é o documento emitido, ou foi alterado.',
    KApp.attestNoPicker: 'Para conferir o arquivo, abra esta página num navegador de computador ou compare a impressão digital acima com a do arquivo.',
    KApp.attestSection: 'Relatórios verificáveis emitidos',
    KApp.attestSectionLead: 'Cada PDF gerado sai com um QR que abre a página de conferência. O administrador pode revogar um relatório que não deve mais valer.',
    KApp.attestRowState: '{0} · {1}',
    KApp.attestStateValid: 'Válido',
    KApp.attestStatePending: 'Não concluído',
    KApp.attestStateRevoked: 'Revogado',
    KApp.attestStateExpired: 'Vencido',
    KApp.attestRevoke: 'Revogar',
    KApp.attestRevokeConfirm: 'Revogar o relatório de {0}? Quem conferir o QR verá que ele foi revogado.',
    KApp.attestRevoked2: 'Relatório revogado.',
    KApp.attestHashFailed: 'O PDF foi gerado, mas a impressão digital não foi gravada: a página de conferência dirá "não concluído". Gere de novo para um PDF conferível.',
    KApp.agendaNotifyLabel: 'Notificar',
    KApp.agendaNotifyNone: 'Ninguém',
    KApp.agendaNotifySelf: 'Só eu',
    KApp.agendaNotifyResponsible: 'Responsável do dia',
    KApp.agendaNotifyFamily: 'Família toda',
    KApp.agendaNotifyPush: 'No celular',
    KApp.agendaNotifyInApp: 'No app',
    KApp.agendaNotifyLead: 'Ao salvar um item novo, quem você escolheu recebe uma notificação (você não recebe a sua). O lembrete vai para todos os escolhidos. Nunca por e-mail.',
    KApp.agendaRemindLabel: 'Lembrete',
    KApp.agendaRemindNone: 'Sem lembrete',
    KApp.agendaRemindAtStart: 'Na hora',
    KApp.agendaRemindBefore: '{0} min antes',
    KApp.agendaRemindNeedsStart: 'Para ter lembrete, escolha o horário de início.',
    KApp.agendaRepeat: 'Repetir toda semana',
    KApp.agendaRepeatLead: 'De {0} até o último dia planejado do calendário, nos dias marcados.',
    KApp.agendaRepeatDays: 'Dias da semana',
    KApp.agendaRoutineApplied: 'Rotina aplicada: {0} dia(s), até {1}.',
    KApp.agendaRoutinePart: 'Parte de uma rotina ({0}).',
    KApp.agendaRoutineEdit: 'Editar a rotina',
    KApp.agendaRoutineEditTitle: 'Rotina da agenda',
    KApp.agendaRoutineEditLead: 'A mudança vale de {0} em diante; os dias antes ficam como estão. Um item mudado à mão já saiu da rotina.',
    KApp.agendaRoutineStop: 'Parar a rotina',
    KApp.agendaRoutineStopConfirm: 'Parar a rotina? Os itens dela a partir de {0} saem da agenda.',
    KApp.agendaRoutineStopped: 'Rotina parada: {0} item(ns) saíram da agenda.',
    KApp.agendaAuditRoutineAdded: '{0} aplicou uma rotina à agenda',
    KApp.agendaAuditRoutineDeleted: '{0} tirou uma rotina da agenda',
    KApp.expenseNav: 'Despesas',
    KApp.expenseLead: 'O que foi gasto com a criança, quem pagou e como dividir. O saldo diz quem paga quanto a quem, com o menor número de pagamentos.',
    KApp.expenseErrLoad: 'Não foi possível carregar as despesas.',
    KApp.expenseOff: 'As despesas ainda não estão disponíveis.',
    KApp.expenseViewer: 'As despesas da família não aparecem para quem só acompanha o plano.',
    KApp.expensePremium: 'Lançar despesas e acertar contas é um recurso Premium. Sem o Premium, as despesas lançadas ficam só para leitura.',
    KApp.expenseAdd: 'Lançar despesa',
    KApp.expenseEdit: 'Editar despesa',
    KApp.expenseEmpty: 'Nenhuma despesa lançada ainda.',
    KApp.expenseEmptyBody: 'Lance o que foi gasto com a criança — escola, saúde, roupas — e escolha como dividir.',
    KApp.expenseGroupFamily: 'Família',
    KApp.expenseGroupLabel: 'Grupo de despesas',
    KApp.expenseBalance: 'Saldo',
    KApp.expenseBalanceEven: 'Tudo acertado: ninguém deve nada.',
    KApp.expensePays: '{0} paga {1} a {2}',
    KApp.expenseNetGets: '{0}: tem a receber {1}',
    KApp.expenseNetOwes: '{0}: deve {1}',
    KApp.expenseSettle: 'Registrar pagamento',
    KApp.expenseSettleTitle: 'Acertar contas',
    KApp.expenseSettleLead: 'Registre um pagamento que você fez. Ele só entra no saldo quando quem recebeu confirmar.',
    KApp.expenseSettleTo: 'Pago a',
    KApp.expenseSettleNobody: 'Ninguém mais na família tem conta para confirmar um pagamento.',
    KApp.expenseAmount: 'Valor (R\$)',
    KApp.expenseSettleSent: 'Pagamento registrado. Falta a confirmação de quem recebeu.',
    KApp.expensePending: 'Pagamentos esperando confirmação',
    KApp.expensePendingToMe: '{0} diz que pagou {1} a você.',
    KApp.expensePendingFromMe: 'Você registrou {0} pagos a {1}. Falta a confirmação.',
    KApp.expensePendingOthers: '{0} registrou {1} pagos a {2}.',
    KApp.expenseConfirm: 'Recebi',
    KApp.expenseReject: 'Não recebi',
    KApp.expenseTakeBack: 'Desfazer registro',
    KApp.expenseConfirmed: 'Pagamento confirmado.',
    KApp.expenseRejected: 'Pagamento marcado como não recebido.',
    KApp.expenseTakenBack: 'Registro desfeito.',
    KApp.expenseListSection: 'Despesas lançadas',
    KApp.expenseRow: '{0} · {1} · pago por {2}',
    KApp.expenseDesc: 'Descrição',
    KApp.expenseCategory: 'Categoria',
    KApp.expenseDate: 'Data',
    KApp.expensePaidBy: 'Quem pagou',
    KApp.expenseSplit: 'Como dividir',
    KApp.expenseSplitEqual: 'Igual',
    KApp.expenseSplitExact: 'Valor',
    KApp.expenseSplitPercent: '%',
    KApp.expenseSplitShares: 'Cotas',
    KApp.expenseParticipants: 'Quem divide',
    KApp.expenseValueExact: 'Valor de {0}',
    KApp.expenseValuePercent: '% de {0}',
    KApp.expenseValueShares: 'Cotas de {0}',
    KApp.expenseShareOf: 'Parte: {0}',
    KApp.expenseErrNoParts: 'Escolha quem participa da despesa.',
    KApp.expenseErrExact: 'Os valores da divisão somam {0}, e a despesa é de {1}.',
    KApp.expenseErrPercent: 'Os percentuais da divisão precisam somar 100%.',
    KApp.expenseErrZero: 'A divisão precisa de pelo menos uma parte maior que zero.',
    KApp.expenseErrAmount: 'Informe o valor.',
    KApp.expenseErrMax: 'O valor passa do limite de {0}.',
    KApp.expenseErrDesc: 'Descreva a despesa.',
    KApp.expenseErrDescLong: 'A descrição da despesa é limitada a {0} caracteres.',
    KApp.expenseSaved: 'Despesa salva.',
    KApp.expenseDelete: 'Apagar despesa',
    KApp.expenseDeleteConfirm: 'Apagar "{0}"? Ela sai do saldo, e as alterações guardam quem apagou e quando.',
    KApp.expenseDeleted: 'Despesa apagada.',
    KApp.expenseDetailSplit: 'Divisão',
    KApp.expenseChanges: 'Alterações',
    KApp.expenseChangeCreated: '{0} lançou em {1}',
    KApp.expenseChangeUpdated: '{0} alterou em {1}',
    KApp.expenseChangeDeleted: '{0} apagou em {1}',
    KApp.expenseChangeBefore: 'Antes: {0} · {1}',
    KApp.expenseOpen: 'Abrir Despesas',
    KApp.expenseFormerMember: 'Ex-membro',
    KApp.expensePdfSection: '{0}. Despesas',
    KApp.expensePdfLead: 'O que a família lançou como despesa da criança no período, quem pagou e a parte de cada um. Um pagamento entre responsáveis só aparece depois que quem recebeu confirmou.',
    KApp.expensePdfEmpty: 'Nenhuma despesa no período.',
    KApp.expensePdfTotals: '{0}: pagou {1} · parte {2}',
    KApp.expensePdfSettlements: 'Pagamentos confirmados',
    KApp.expensePdfSettlement: '{0} — {1} pagou {2} a {3}',
    KApp.expensePdfChanges: 'Alterações e exclusões',
    KApp.expensePdfChange: '{0} — {1}: {2}',
    KApp.expensePdfUpdated: 'alterou "{0}" (antes: {1})',
    KApp.expensePdfDeleted: 'apagou "{0}" ({1})',
    KApp.chatNav: 'Comunicação',
    KApp.chatTabChat: 'Conversa',
    KApp.chatTabNotifications: 'Notificações',
    KApp.chatTabCount: '{0} ({1})',
    KApp.chatNotice: 'O que se escreve aqui é permanente: não se edita nem se apaga, toda a família lê, e pode ir ao PDF ou a um processo.',
    KApp.chatEmpty: 'A conversa da família começa aqui.',
    KApp.chatHint: 'Escreva para a família',
    KApp.chatSend: 'Enviar',
    KApp.chatReply: 'Responder citando',
    KApp.chatQuoting: 'Respondendo a {0}',
    KApp.chatCancelQuote: 'Tirar a citação',
    KApp.chatCiteDay: 'Citar um dia',
    KApp.chatCitedDay: 'Dia citado: {0}',
    KApp.chatRemoveDay: 'Tirar o dia citado',
    KApp.chatReadBy: 'Lida por {0}',
    KApp.chatNotRead: 'Ainda não lida',
    KApp.chatReadEntry: '{0} ({1})',
    KApp.chatSearch: 'Buscar na conversa',
    KApp.chatSearchClose: 'Fechar a busca',
    KApp.chatSearchEmpty: 'Nada encontrado para "{0}".',
    KApp.chatMute: 'Silenciar o push da Conversa',
    KApp.chatMuteLead: 'A notificação continua no app; só o celular deixa de tocar.',
    KApp.chatMuted: 'Push da Conversa silenciado.',
    KApp.chatUnmuted: 'Push da Conversa ligado.',
    KApp.chatReadOnly: 'Você acompanha o plano: lê a Conversa, mas não escreve nela.',
    KApp.chatPremium: 'Escrever na Conversa é um recurso Premium. Sem o Premium, o que já foi dito fica para leitura.',
    KApp.chatOff: 'A Conversa ainda não está disponível.',
    KApp.chatErrLoad: 'Não foi possível carregar a Conversa.',
    KApp.chatTooLong: 'Um envio é limitado a {0} caracteres.',
    KApp.chatYou: 'Você',
    KApp.chatFormerMember: 'Ex-membro',
    KApp.chatSendFailed: 'Não foi possível enviar. Tente de novo.',
    KApp.chatPdfInclude: 'Incluir a Conversa do período',
    KApp.chatPdfSection: '{0}. Conversa da família',
    KApp.chatPdfLead: 'O que a família escreveu na Conversa no período, na ordem, como foi escrito. Nada na Conversa se edita ou se apaga.',
    KApp.chatPdfEmpty: 'Nada foi escrito na Conversa no período.',
    KApp.chatPdfReply: 'em resposta a {0}',
  };
}

/// EN — same rules as the main catalog: placeholder SETS match PT-BR.
abstract final class StringsAppEn {
  static const Map<String, String> values = {
    KApp.sessionRestoredExpired: 'Your previous session expired.',
    KApp.sessionExpired: 'Session expired — sign out and sign in again.',
    KApp.errCalendarLoad: 'Could not load the calendar.',
    KApp.sheetNoResponsible: 'No caregiver assigned to this day.',
    KApp.sheetPlanned: 'Planned: {0}',
    KApp.sheetHandoffAt: 'Handoff at {0}',
    KApp.sheetNote: 'Note: {0}',
    KApp.sheetWhoQuestion: 'Who has the child on this day?',
    KApp.sheetSave: 'Save',
    KApp.errDaySave: 'Could not save the day.',
    KApp.errSwapPendingExists:
        'There is already a pending request for this day — the calendar has '
            'been refreshed.',
    KApp.errConcurrentSaveRetry:
        'The other caregiver saved this day first — refresh the calendar and '
            'try again.',
    KApp.editorRetroBeyondFree:
        'The free plan corrects only the last {0} days. Activate Premium to '
            'correct older days (up to {1} months).',
    KApp.editorRetroBeyondPremium:
        'Retroactive corrections reach up to {0} months back.',
    KApp.bulkProgressSaving: 'Saving {0}/{1}...',
    KApp.wizErrTooFewBlocks: 'The cycle needs at least 1 block.',
    KApp.wizErrBlockDays: 'Each block needs at least 1 day.',
    KApp.wfProgressProcessing: 'Processing {0}/{1}...',
    KApp.commonShare: 'Share',
    KApp.commonMoreActions: 'More actions',
    KApp.sudoErrCooldown: 'Too many attempts. Wait {0} seconds.',
    KApp.sudoErrNoSession: 'Invalid session. Sign in again.',
    KApp.sudoErrWrongPassword: 'Wrong password.',
    KApp.sudoErrGeneric: 'Could not confirm. Try again.',
    KApp.sudoErrConnection:
        'Connection to the server failed. Check your internet and try again.',
    KApp.sudoSendCode: 'Get a code by e-mail',
    KApp.sudoSendingCode: 'Sending...',
    KApp.sudoCodeSentTo: 'We sent a code to {0}. It is valid for {1} minutes.',
    KApp.sudoCodeLabel: '6-digit code',
    KApp.sudoUsePassword: 'Confirm with your password',
    KApp.sudoErrCodeShape: 'The code has 6 digits.',
    KApp.sudoErrCodeSend: 'Could not send the code. Try again.',
    KApp.profErrNameTooShort: 'Enter a name with at least 2 characters.',
    KApp.profErrPasswordShort: 'The password needs at least 8 characters.',
    KApp.rolesCreateTitle: 'Create role',
    KApp.rolesEditTitle: 'Edit role',
    KApp.rolesToastUpdated: 'Role updated!',
    KApp.rolesNoEmoji: 'No emoji',
    KApp.inviteErrRoleRequired: 'Select the role of the person you are inviting.',
    KApp.shellUnderConstructionTitle: 'Under construction',
    KApp.shellUnderConstructionBody:
        'This screen arrives in an upcoming update.',
    KApp.storeManage: 'Manage subscription on Google Play',
    KApp.storeRestore: 'Already subscribed — restore purchase',
    KApp.storeUnavailable:
        'The store did not answer just now. Try again in a moment — if you '
            'already subscribed, your Premium is still valid.',
    KApp.storePending:
        'We are confirming your purchase with Google. This usually takes a few '
            'seconds.',
    KApp.storeErrPurchase:
        'Could not complete the purchase. Nothing is charged without Google '
            'confirming it.',
    KApp.storeToastActive: 'Premium active!',
    KApp.authGoogle: 'Continue with Google',
    KApp.authGoogleErr: 'Could not open Google sign-in. Try again.',
    KApp.onbFounderTitle: 'Complete your sign-up',
    KApp.onbFounderSubtitle:
        'Your Google account is ready. Now tell us who you are to create '
            'your family.',
    KApp.onbFounderCta: 'Create my family',
    KApp.onbClaimCta: 'Join the family',
    KApp.onbSubmitting: 'Sending...',
    KApp.onbSwitchAccount: 'Sign in with another account',
    KApp.onbSignedInAs: 'Signed in as {0}',
    KApp.onbErrGeneric: 'Could not finish the sign-up. Try again.',
    KApp.signupStep: 'Step {0} of {1} · {2}',
    KApp.signupStepAccount: 'Your account',
    KApp.signupStepFamily: 'Your family',
    KApp.signupContinue: 'Continue',
    KApp.signupBack: 'Back',
    KApp.roleOther: 'Other…',
    KApp.roleOtherTitle: 'What is your role in the family?',
    KApp.profLoginMethod: 'How you sign in',
    KApp.profLoginMethodGoogle: 'Google account',
    KApp.profLoginMethodNote:
        'You sign in with your Google account — there is no password to '
            'change here.',
    KApp.profLoginMethodsIntro:
        'This account has more than one way in. Any one of them opens it on '
            'its own.',
    KApp.profLoginMethodPassword: 'E-mail and password',
    KApp.profLoginMethodPasswordNote:
        'Your e-mail and the password you set in the Password section below.',
    KApp.profLoginMethodGoogleLinkedNote:
        'Opens this login on its own — even after you change the password or '
            'the e-mail on this screen.',
    KApp.profLoginMethodGoogleNeutralNote: 'Opens this login on its own.',
    KApp.profLoginMethodOther: 'Another provider: {0}',
    KApp.profLoginMethodOtherNote: 'Opens this login on its own.',
    KApp.profEditData: 'Edit details',
    KApp.profPasswordSummary:
        'Password set. Change it here or reset it by e-mail.',
    KApp.pushTitle: 'Phone notifications',
    KApp.pushHintOff:
        'Get a notification when someone asks for a swap, or answers yours — even '
            'with the app closed.',
    KApp.pushHintOn: 'This device receives swap and deadline notifications.',
    KApp.pushHintUnsupported:
        'Phone notifications work in the installed app. Here in the browser you '
            'still see everything on this screen and by e-mail.',
    KApp.pushHintInstallIos:
        'On iPhone, notifications only work with Entrelares on your Home '
            'Screen.',
    KApp.pushInstallHow: 'How to install',
    KApp.pushHintNeedsSafari:
        'On iPhone, notifications only work with Entrelares on your Home '
            'Screen. To install it, open this address in Safari — the steps we '
            "show are Safari's.",
    KApp.pushHintReallowApp:
        'Notifications from Entrelares are blocked on this device. To allow '
            'them: open Settings > Notifications > App notifications, tap '
            'Entrelares and turn notifications on. Names may vary by '
            'manufacturer.',
    KApp.pushHintReallowIos:
        'Notifications from Entrelares are blocked on this iPhone. To allow '
            'them: open Settings > Notifications, tap Entrelares and turn on '
            'Allow Notifications.',
    KApp.pushHintReallowBrowser:
        'Notifications from Entrelares are blocked in this browser. To allow '
            'them: tap the icon to the left of the address, turn Notifications '
            'on and reload the page.',
    KApp.pushHintUnsupportedHere:
        'This device does not receive notifications from Entrelares. You still '
            'see everything on this screen and by e-mail.',
    KApp.pushEnable: 'Turn notifications on',
    KApp.pushDisable: 'Turn off',
    KApp.pushStatusOnTooltip: 'Phone notifications: on',
    KApp.pushToastOn: 'Notifications are on for this device.',
    KApp.pushToastOff: 'Notifications are off for this device.',
    KApp.pushErrEnable:
        'Could not turn notifications on right now. You still get everything on this '
            'screen and by e-mail.',
    KApp.onbStepPushTitle: 'Turn on phone notifications',
    KApp.onbStepPushHint:
        'A swap is usually asked for at short notice. With notifications on you hear '
            'about it right away, even with the app closed.',
    KApp.onbStepPushDoneHint:
        'This device notifies you about swap requests and deadlines.',
    KApp.onbStepPushAction: 'Turn notifications on',
    KApp.famPendingBadge: 'Not joined yet',
    KApp.famPendingHint:
        'No account yet: you plan this person\'s days, and swaps become '
            'available once they join.',
    KApp.famInviteName: 'Name',
    KApp.famInviteNameHint: 'How this person appears on the calendar',
    KApp.famInviteEmailOptional:
        'Optional: with an e-mail the invitation goes out now. Without it, '
            'you plan the days and invite later.',
    KApp.famAddWithoutInvite: 'Add to the calendar',
    KApp.famPendingAdded:
        '{0} is on the calendar now. Invite them whenever it makes sense.',
    KApp.famPendingInvite: 'Invite',
    KApp.famPendingInviteTitle: 'Invite {0}',
    KApp.famPendingRemove: 'Remove',
    KApp.famPendingRemoveConfirm:
        'Remove {0} from the calendar? Future days planned for them are '
            'freed; past ones stay in the history.',
    KApp.famPendingRemoved: '{0} was removed from the calendar.',
    KApp.famPendingRemoveTitle: 'Remove {0}',
    KApp.famRevokeTitle: 'Revoke invitation',
    KApp.famRevokeConfirm:
        'Revoke the invitation to {0}? The link they received stops working.',
    KApp.famAttachInvite: 'Add to the calendar',
    KApp.famAttachTitle: 'Add {0} to the calendar',
    KApp.famAttachHint:
        'You can plan this person\'s days right away. The invitation already '
            'sent still stands — same link.',
    KApp.famAttached:
        '{0} is on the calendar now. The invitation already sent still stands.',
    KApp.inviteErrNameRequired: 'Enter the name of the person you are adding.',
    KApp.sheetSwapUnavailablePending:
        '{0} has not joined the app yet. You can change the planned parent; '
            'swaps become available once the account is created.',
    KApp.calMemberPending: '(pending)',
    KApp.onbStepInviteDoneHintPending:
        'The other caregiver is already on the calendar. Invite them '
            'whenever it makes sense.',
    KApp.auditActionPendingAdded: 'Caregiver added to the calendar',
    KApp.auditActionPendingRemoved: 'Caregiver removed from the calendar',
    KApp.auditActionPendingClaimed: 'Caregiver joined through the invitation',
    KApp.handoffBanner: 'You already have the app on this device.',
    KApp.handoffOpen: 'Open in the app',
    KApp.handoffDismiss: 'Not now',
    KApp.installHintBanner: 'Put Entrelares on your Home Screen.',
    KApp.installHintHow: 'Show me how',
    KApp.installHintDismiss: 'Not now',
    KApp.installHintTitle: 'Install on iPhone or iPad',
    KApp.installHintSubtitle:
        'Entrelares opens like an app, with an icon on your screen and no '
            'app store. Two taps in Safari:',
    KApp.installHintStepShare:
        'Tap the <strong>Share</strong> button (a square with an arrow '
            'pointing up). If it is not in view, tap <strong>⋯</strong> and '
            'choose <strong>Share</strong>.',
    KApp.installHintStepAdd:
        '<strong>Scroll the list</strong> to <strong>Add to Home '
            'Screen</strong>, turn on <strong>Open as Web App</strong> (if it '
            'shows) and tap <strong>Add</strong>.',
    KApp.installHintNote:
        'Button names may vary slightly with your iOS version.',
    KApp.offlineStrip: 'Offline · data from {0}',
    KApp.offlineStripNoData: 'Offline · nothing loaded yet',
    KApp.offlineMonthNotLoaded:
        'Offline — this month has not been loaded on this device yet.',
    KApp.offlineWriteBlocked:
        'Offline — connect to make changes. Nothing was sent.',
    // ── U-35 Família split ──
    KApp.famPlanRow: 'Plan and payment',
    KApp.helpTitle: 'Help & contact',
    KApp.helpProfileRowSub: 'Ask a question or report a problem',
    KApp.helpLoginLink: 'Need help?',
    KApp.helpIntro: 'Write to the Entrelares team — a question, a problem, a suggestion. The reply arrives by e-mail.',
    KApp.helpCategoryLabel: 'What is it about?',
    KApp.helpCatQuestion: 'Question',
    KApp.helpCatProblem: 'Problem or error',
    KApp.helpCatSuggestion: 'Suggestion',
    KApp.helpCatPrivacy: 'Privacy and data',
    KApp.helpCatOther: 'Other',
    KApp.helpMessageLabel: 'Message',
    KApp.helpMessageHint: 'Tell us what happened or what you want to know.',
    KApp.helpMessageTooShort: 'Write at least {0} characters.',
    KApp.helpEmailLabel: 'Your e-mail, for the reply',
    KApp.helpEmailInvalid: 'Enter a valid e-mail.',
    KApp.helpReplyTo: 'The reply goes to {0}.',
    KApp.helpDiagLabel: 'Include technical information',
    KApp.helpDiagHelper: 'Helps us understand a problem. It never includes your calendar or family data.',
    KApp.helpDiagPreview: 'See what will be sent',
    KApp.helpDiagVersion: 'Version',
    KApp.helpDiagChannel: 'Channel',
    KApp.helpDiagPlatform: 'System',
    KApp.helpDiagLanguage: 'Language',
    KApp.helpDiagRoute: 'Screen',
    KApp.helpSend: 'Send',
    KApp.helpSentTitle: 'Message sent',
    KApp.helpSentBody: 'Request #{0}. We reply within 2 business days, to {1}.',
    KApp.helpBack: 'Back',
    KApp.helpErrRateLimited: 'You sent several messages in a short time. Try again later, or write directly to {0}.',
    KApp.helpErrSendFailed: 'We could not deliver your message right now. Write directly to {0}.',
    KApp.helpErrOffline: 'No connection. The message was not sent — try again when you have signal.',
    KApp.helpErrFailed: 'It could not be sent. Try again, or write to {0}.',
    KApp.helpMailtoLead: 'Prefer to write by e-mail?',
    KApp.famPlanRowFree: 'Free',
    KApp.famPlanRowTrialOne: 'Premium trial — {0} day left',
    KApp.famPlanRowTrialMany: 'Premium trial — {0} days left',
    KApp.famPlanRowPremiumUntil: 'Premium until {0}',
    KApp.famPlanRowPremium: 'Premium',
    KApp.famAdminRow: 'Administrator mode',
    KApp.famAdminRowOn: 'On',
    KApp.famAdminRowOff: 'Off',
    KApp.famDelReqUnavailable:
        'There is no deletion request to open here. Only an administrator with other caregivers in the family can open one — and an open request shows on the Família screen.',
    // ── U-12 ──
    KApp.appearanceLabel: 'Appearance',
    KApp.appearanceHint:
        'Kept on this device only. "System" follows the theme your device '
            'already uses.',
    KApp.appearanceAriaLabel: 'Choose theme',
    KApp.appearanceLight: 'Light',
    KApp.appearanceDark: 'Dark',
    KApp.appearanceSystem: 'System',
    // ── F-52 ──
    KApp.noticeAction: 'Send a notice',
    KApp.noticeTitle: 'Notice about today',
    KApp.noticeSubtitle:
        'For today only. A notice on its own does not change who has the '
            'child.',
    KApp.noticeReasonLabel: 'What happened',
    KApp.noticeReasonDelay: 'I am running late',
    KApp.noticeReasonMedical: 'Medical emergency',
    KApp.noticeReasonTraffic: 'Traffic',
    KApp.noticeReasonOther: 'Something else',
    KApp.noticeEtaLabel: 'Estimate',
    KApp.noticeEtaMinutes: '{0} min',
    KApp.noticeEtaNone: 'No estimate',
    KApp.noticeRequestLabel: 'What you need',
    KApp.noticeRequestInfo: 'Just letting you know',
    KApp.noticeRequestPickup: 'Can someone collect the child?',
    KApp.noticeRequestKeep: 'Can someone keep the child today?',
    KApp.noticeConsequenceInfo:
        'Nobody has to answer, and the calendar does not change.',
    KApp.noticeConsequencePickup:
        'Whoever receives it can offer to help now. The calendar does not '
            'change: today stays yours.',
    KApp.noticeConsequenceKeep:
        'Whoever receives it can offer to keep the child. If someone '
            'accepts, an already-approved swap moves today to them, with no '
            'further confirmation from you. You will see who accepted, and '
            'the swap stays in the history.',
    KApp.noticeConsequenceKeepClearsEta:
        'Choosing this clears the estimate: a delay with a time on it does '
            'not hand the day to anyone.',
    KApp.noticeConsequenceKeepNotMyDay:
        'Only the carer whose day it is can offer it. Today belongs to '
            'someone else.',
    KApp.noticeNoteLabel: 'Detail (optional)',
    KApp.noticeNoteHint: 'Where you are, what helps whoever answers',
    KApp.noticeSend: 'Send notice',
    KApp.noticeCapHint: 'You can send up to {0} notices a day.',
    KApp.noticeCapReached:
        'You have already sent {0} notices today. The limit resets tomorrow.',
    KApp.noticeSent: 'Notice sent.',
    KApp.noticeErrSend: 'The notice could not be sent.',
    KApp.noticeOpenMine: 'Your notice for today is open.',
    KApp.noticeCancel: 'Cancel notice',
    KApp.noticeCancelConfirm:
        'Cancel this notice? Whoever received it will be told it is no '
            'longer needed. It still counts towards your daily limit.',
    KApp.noticeCancelKeep: 'Keep it',
    KApp.noticeCancelled: 'Notice cancelled.',
    KApp.noticeErrCancel: 'The notice could not be cancelled.',
    KApp.noticeAnswerTitle: 'Answer the notice',
    KApp.noticeAnswerHelping: 'I can help now',
    KApp.noticeAnswerKeeping: 'I will keep the child today',
    KApp.noticeAnswerHelpingWhat:
        'Whoever sent the notice is told you are helping. The calendar does '
            'not change: today stays with whoever already has it.',
    KApp.noticeAnswerKeepingWhat:
        'An already-approved swap moves today to you, now — it is what '
            'whoever sent the notice asked for. It stays in the history, with '
            'the date and who did it, and can be reverted like any other swap.',
    KApp.noticeAnswerNoteLabel: 'Detail (optional)',
    KApp.noticeAnswerNoteHint: 'Where you will be, what time you arrive',
    KApp.noticeAnswerSend: 'Send answer',
    KApp.noticeAnsweredHelping: 'Answer sent.',
    KApp.noticeAnsweredKeeping: 'Today has moved to you.',
    KApp.noticeErrAnswer: 'The notice could not be answered.',
    KApp.adminOfferEditPastDay:
        'Correcting a day that has passed needs administrator mode. The '
            'correction is recorded as made by the administrator, in the '
            'history and in the report.',
    KApp.adminOfferClearDay:
        'Clearing a day that is already planned needs administrator mode.',
    KApp.adminOfferChangePlanned:
        'Changing who is planned on a day already assigned needs '
            'administrator mode.',
    KApp.adminOfferBulkClear:
        'Clearing planned days needs administrator mode.',
    KApp.adminOfferBulkOverwrite:
        'Applying this edit to days that have passed, and to who is planned '
            'on days already assigned, needs administrator mode.',
    KApp.adminOfferWizardReplace:
        'Replacing the days already planned needs administrator mode.',
    KApp.adminOfferClearMonth:
        'Clearing the month needs administrator mode.',
    KApp.adminOfferHow:
        'Turn it on now? While it is on, a strip at the top of the screen '
            'says so, with the Exit button.',
    KApp.adminOfferCorrectPlan: 'Correct the plan',
    KApp.adminOfferBulkBanner:
        'Without administrator mode, this edit skips the days that have '
            'passed and keeps who is planned on days already assigned.',
    KApp.dayAccountErrEmpty: 'Write what happened.',
    KApp.dayAccountErrTooLong: 'A day account is limited to {0} characters.',
    KApp.dayAccountByline: 'Recorded by {0} on {1} at {2}',
    KApp.dayAccountCorrected: 'Corrected on {0} at {1}',
    KApp.dayAccountSection:
        'Day accounts',
    KApp.dayAccountAction:
        'Report what happened',
    KApp.dayAccountFieldLabel:
        'What happened',
    KApp.dayAccountFieldHint:
        'Who picked up, at what time, where they left',
    KApp.dayAccountAppendOnly:
        'A day account cannot be edited or deleted once recorded. To correct it, record a correction: the earlier text stays on the record, marked as corrected.',
    KApp.dayAccountSave:
        'Record account',
    KApp.dayAccountCorrect:
        'Correct',
    KApp.dayAccountCorrecting:
        'Correction of the account recorded on {0}',
    KApp.dayAccountOutOfWindow:
        'Day accounts can be recorded up to {0} days after the day.',
    KApp.dayAccountCapLeftOne:
        'You can still record 1 day account today.',
    KApp.dayAccountCapLeftMany:
        'You can still record {0} day accounts today.',
    KApp.dayAccountCapReached:
        'You have already recorded {0} day accounts today. The limit resets tomorrow.',
    KApp.dayAccountSaved:
        'Day account recorded.',
    KApp.dayAccountErrSave:
        'The day account could not be recorded.',
    KApp.dayAccountErrLoad:
        'The day accounts of this day could not be loaded.',
    KApp.dayAccountAuditNew:
        '{0} recorded a day account',
    KApp.dayAccountAuditCorrection:
        '{0} corrected a day account',
    KApp.pdfDayAccountsSection:
        '4. Day accounts',
    KApp.pdfDayAccountsLead:
        'Accounts recorded by the caregivers after the day they are about. A day account does not change the plan. A correction is a new account, and the corrected text stays in this document.',
    KApp.pdfDayAccountsEmpty:
        'No day accounts in the period.',
    KApp.pdfDayAccountLine:
        'About {0} — recorded by {1} on {2}.',
    KApp.pdfDayAccountCorrectionLine:
        'About {0} — correction recorded by {1} on {2}.',
    // ── F-55 the child entity ──
    KApp.famChildRow: 'Child',
    KApp.famChildRowEmpty: 'No child added yet',
    KApp.childAnd: 'and',
    KApp.childTitle: 'Child',
    KApp.childLead: 'First name only. The report and the day agenda use this name.',
    KApp.childEmpty: 'No child added yet.',
    KApp.childAdminOnly: 'Only a family administrator adds or changes the child.',
    KApp.childNameLabel: 'First name',
    KApp.childAdd: 'Add the child',
    KApp.childRename: 'Change the name',
    KApp.childRemove: 'Remove',
    KApp.childRemoveConfirm: 'Remove {0} from the family? {0}\'s agenda goes with it.',
    KApp.childAdded: 'Child added.',
    KApp.childRenamed: 'Name updated.',
    KApp.childRemoved: 'Child removed.',
    KApp.childErrLoad: 'The child could not be loaded.',
    // ── F-55 the day agenda ──
    KApp.agendaSection: 'Agenda',
    KApp.agendaKindSchool: 'School',
    KApp.agendaKindHealth: 'Health',
    KApp.agendaKindMedicine: 'Medicine',
    KApp.agendaKindActivity: 'Activity',
    KApp.agendaKindFree: 'Free time',
    KApp.agendaKindNote: 'Note',
    KApp.agendaKindOther: 'Other',
    KApp.agendaAdd: 'Add to the agenda',
    KApp.agendaEmpty: 'Nothing on this day\'s agenda.',
    KApp.agendaNewTitle: 'New on the agenda',
    KApp.agendaEditTitle: 'Edit on the agenda',
    KApp.agendaKindLabel: 'Type',
    KApp.agendaChildLabel: 'Child',
    KApp.agendaStartLabel: 'Start',
    KApp.agendaEndLabel: 'End',
    KApp.agendaNoTime: 'No time',
    KApp.agendaClearTime: 'Remove the time',
    KApp.agendaBodyLabel: 'Text (optional)',
    KApp.agendaNoteBodyLabel: 'Note text',
    KApp.agendaDelete: 'Delete from the agenda',
    KApp.agendaDeleteConfirm: 'Delete this item from the agenda? The History keeps who deleted it.',
    KApp.agendaSaved: 'Agenda updated.',
    KApp.agendaDeleted: 'Item deleted from the agenda.',
    KApp.agendaErrLoad: 'This day\'s agenda could not be loaded.',
    KApp.agendaFreeNotesOne: 'On the free plan, the agenda has {0} note per day. School, health, medicine and activities are Premium.',
    KApp.agendaFreeNotesMany: 'On the free plan, the agenda has {0} notes per day. School, health, medicine and activities are Premium.',
    KApp.agendaReadOnlyPast: 'A past day is read-only on the agenda.',
    KApp.agendaReadOnlyPremium: 'This item belongs to the Premium agenda and is read-only on the free plan.',
    KApp.agendaNoChildAdmin: 'Add the child under Family to use the full agenda.',
    KApp.agendaNoChildMember: 'For the full agenda, the administrator adds the child under Family.',
    KApp.agendaBy: 'by {0}',
    KApp.agendaFromObservation: 'from the old day\'s observation',
    KApp.agendaAuditAdded: '{0} added to the agenda',
    KApp.agendaAuditDeleted: '{0} deleted from the agenda',
    KApp.agendaPdfSection: '5. The child\'s agenda',
    KApp.agendaPdfLead: 'What the family recorded on the agenda for the days of the period. The agenda does not change the plan: it never changes who has the child on any day.',
    KApp.agendaPdfEmpty: 'No agenda items in the period.',
    KApp.viewerBadge: 'Viewer',
    KApp.viewerSection: 'Viewers',
    KApp.viewerInviteButton: 'Invite viewer',
    KApp.viewerReadOnly: 'You are a viewer: you follow the family\'s plan without changing anything.',
    KApp.viewerInviteLead: 'A viewer sees the calendar, the agenda and the reports, and gets the informative notifications in the app and on the phone. They change nothing, take no part in swaps, do not see the swap messages and get no e-mail.',
    KApp.viewerInviteNeedsEmail: 'To invite a viewer, enter their e-mail.',
    KApp.viewerFreeCapOne: 'On the free plan, the family includes {0} viewer. To invite more, activate Premium.',
    KApp.viewerFreeCapMany: 'On the free plan, the family includes {0} viewers. To invite more, activate Premium.',
    KApp.viewerMaxCap: 'The family already has {0} viewers, the limit.',
    KApp.viewerInviteSent: 'Viewer invitation sent.',
    KApp.viewerPromote: 'Promote to caregiver',
    KApp.viewerPromoteConfirm: 'Promote {0} to caregiver? {0} will be able to hold days, request and approve swaps, and gets a colour. A caregiver never goes back to being a viewer.',
    KApp.viewerPromoted: '{0} is now a caregiver.',
    KApp.viewerRemove: 'Remove viewer',
    KApp.viewerRemoveConfirm: 'Remove {0}? {0}\'s account is deleted right away, with everything that was theirs.',
    KApp.viewerRemoved: '{0} was removed from the family.',
    KApp.viewerLeaveBody: 'As a viewer, leaving deletes you right away: your account and your data. Nothing in the family history depends on you.',
    KApp.viewerLeaveButton: 'Leave and delete my account',
    KApp.viewerInvitedBody: '{0} invited you to follow the {1} family\'s calendar as a viewer: you see the plan, the agenda and the informative notifications, without changing anything.',
    KApp.attestPageTitle: 'Check a report',
    KApp.attestValid: 'This report was issued by Entrelares and is valid.',
    KApp.attestPending: 'This report was started, but the PDF was never finished: there is no fingerprint to check.',
    KApp.attestRevoked: 'This report was revoked by the family on {0}. It no longer counts as a check.',
    KApp.attestExpired: 'This report expired on {0}. A check is valid for a limited time; after it, the summary is deleted.',
    KApp.attestUnknown: 'We could not find this report. Check that the address is complete.',
    KApp.attestError: 'Could not check right now. Try again in a moment.',
    KApp.attestIssuedAt: 'Issued on',
    KApp.attestPeriod: 'Period',
    KApp.attestValidUntil: 'Can be checked until',
    KApp.attestFingerprint: 'PDF fingerprint (SHA-256)',
    KApp.attestSummary: 'What Entrelares recorded in the period',
    KApp.attestDaysPlanned: 'Planned days: {0}',
    KApp.attestDaysBy: '{0}: {1} day(s)',
    KApp.attestDaysSwapped: 'Days changed by a swap: {0}',
    KApp.attestSwaps: 'Swap requests: {0}',
    KApp.attestDayAccounts: 'Day accounts: {0}',
    KApp.attestInitialsNote: 'Caregivers appear by initials: this page is public and shows no names.',
    KApp.attestCompare: 'Check a PDF',
    KApp.attestCompareHint: 'Choose the file (or drop it on this page). It is read on your device only: nothing is sent.',
    KApp.attestMatch: 'Match: this PDF is the document that was issued.',
    KApp.attestMismatch: 'No match: this PDF is not the document that was issued, or it was altered.',
    KApp.attestNoPicker: 'To check the file, open this page in a computer\'s browser, or compare the fingerprint above with the file\'s.',
    KApp.attestSection: 'Verifiable reports issued',
    KApp.attestSectionLead: 'Each PDF comes with a QR that opens the check page. The admin can revoke a report that should no longer count.',
    KApp.attestRowState: '{0} · {1}',
    KApp.attestStateValid: 'Valid',
    KApp.attestStatePending: 'Not finished',
    KApp.attestStateRevoked: 'Revoked',
    KApp.attestStateExpired: 'Expired',
    KApp.attestRevoke: 'Revoke',
    KApp.attestRevokeConfirm: 'Revoke the report for {0}? Whoever checks the QR will see it was revoked.',
    KApp.attestRevoked2: 'Report revoked.',
    KApp.attestHashFailed: 'The PDF was generated, but its fingerprint was not recorded: the check page will say "not finished". Generate again for a checkable PDF.',
    KApp.agendaNotifyLabel: 'Notify',
    KApp.agendaNotifyNone: 'Nobody',
    KApp.agendaNotifySelf: 'Only me',
    KApp.agendaNotifyResponsible: 'The day\'s caregiver',
    KApp.agendaNotifyFamily: 'Whole family',
    KApp.agendaNotifyPush: 'On the phone',
    KApp.agendaNotifyInApp: 'In the app',
    KApp.agendaNotifyLead: 'When a new item is saved, whoever you chose gets a notification (you do not get your own). The reminder goes to everyone chosen. Never by e-mail.',
    KApp.agendaRemindLabel: 'Reminder',
    KApp.agendaRemindNone: 'No reminder',
    KApp.agendaRemindAtStart: 'At the time',
    KApp.agendaRemindBefore: '{0} min before',
    KApp.agendaRemindNeedsStart: 'To get a reminder, set a start time.',
    KApp.agendaRepeat: 'Repeat every week',
    KApp.agendaRepeatLead: 'From {0} to the calendar\'s last planned day, on the days marked.',
    KApp.agendaRepeatDays: 'Weekdays',
    KApp.agendaRoutineApplied: 'Routine applied: {0} day(s), until {1}.',
    KApp.agendaRoutinePart: 'Part of a routine ({0}).',
    KApp.agendaRoutineEdit: 'Edit the routine',
    KApp.agendaRoutineEditTitle: 'Agenda routine',
    KApp.agendaRoutineEditLead: 'The change applies from {0} on; earlier days stay as they are. An item changed by hand has already left the routine.',
    KApp.agendaRoutineStop: 'Stop the routine',
    KApp.agendaRoutineStopConfirm: 'Stop the routine? Its items from {0} on leave the agenda.',
    KApp.agendaRoutineStopped: 'Routine stopped: {0} item(s) left the agenda.',
    KApp.agendaAuditRoutineAdded: '{0} applied a routine to the agenda',
    KApp.agendaAuditRoutineDeleted: '{0} removed a routine from the agenda',
    KApp.expenseNav: 'Expenses',
    KApp.expenseLead: 'What was spent on the child, who paid and how it is split. The balance says who pays how much to whom, with the fewest payments.',
    KApp.expenseErrLoad: 'Could not load the expenses.',
    KApp.expenseOff: 'Expenses are not available yet.',
    KApp.expenseViewer: 'Viewers do not see the family\'s expenses.',
    KApp.expensePremium: 'Adding expenses and settling up is a Premium feature. Without Premium, the expenses already added are read-only.',
    KApp.expenseAdd: 'Add expense',
    KApp.expenseEdit: 'Edit expense',
    KApp.expenseEmpty: 'No expenses yet.',
    KApp.expenseEmptyBody: 'Add what was spent on the child — school, health, clothes — and choose how to split it.',
    KApp.expenseGroupFamily: 'Family',
    KApp.expenseGroupLabel: 'Expense group',
    KApp.expenseBalance: 'Balance',
    KApp.expenseBalanceEven: 'All settled: nobody owes anything.',
    KApp.expensePays: '{0} pays {1} to {2}',
    KApp.expenseNetGets: '{0}: is owed {1}',
    KApp.expenseNetOwes: '{0}: owes {1}',
    KApp.expenseSettle: 'Record a payment',
    KApp.expenseSettleTitle: 'Settle up',
    KApp.expenseSettleLead: 'Record a payment you made. It counts in the balance only once the person who received it confirms.',
    KApp.expenseSettleTo: 'Paid to',
    KApp.expenseSettleNobody: 'Nobody else in the family has an account to confirm a payment.',
    KApp.expenseAmount: 'Amount (R\$)',
    KApp.expenseSettleSent: 'Payment recorded. It waits for the receiver to confirm.',
    KApp.expensePending: 'Payments awaiting confirmation',
    KApp.expensePendingToMe: '{0} says they paid you {1}.',
    KApp.expensePendingFromMe: 'You recorded {0} paid to {1}. Waiting for confirmation.',
    KApp.expensePendingOthers: '{0} recorded {1} paid to {2}.',
    KApp.expenseConfirm: 'I received it',
    KApp.expenseReject: 'I did not receive it',
    KApp.expenseTakeBack: 'Take it back',
    KApp.expenseConfirmed: 'Payment confirmed.',
    KApp.expenseRejected: 'Payment marked as not received.',
    KApp.expenseTakenBack: 'Record taken back.',
    KApp.expenseListSection: 'Expenses added',
    KApp.expenseRow: '{0} · {1} · paid by {2}',
    KApp.expenseDesc: 'Description',
    KApp.expenseCategory: 'Category',
    KApp.expenseDate: 'Date',
    KApp.expensePaidBy: 'Paid by',
    KApp.expenseSplit: 'How to split',
    KApp.expenseSplitEqual: 'Equal',
    KApp.expenseSplitExact: 'Amount',
    KApp.expenseSplitPercent: '%',
    KApp.expenseSplitShares: 'Shares',
    KApp.expenseParticipants: 'Split between',
    KApp.expenseValueExact: '{0}\'s amount',
    KApp.expenseValuePercent: '{0}\'s %',
    KApp.expenseValueShares: '{0}\'s shares',
    KApp.expenseShareOf: 'Share: {0}',
    KApp.expenseErrNoParts: 'Choose who shares the expense.',
    KApp.expenseErrExact: 'The split adds up to {0}, and the expense is {1}.',
    KApp.expenseErrPercent: 'The percentages must add up to 100%.',
    KApp.expenseErrZero: 'The split needs at least one part greater than zero.',
    KApp.expenseErrAmount: 'Enter the amount.',
    KApp.expenseErrMax: 'The amount is over the {0} limit.',
    KApp.expenseErrDesc: 'Describe the expense.',
    KApp.expenseErrDescLong: 'An expense description is limited to {0} characters.',
    KApp.expenseSaved: 'Expense saved.',
    KApp.expenseDelete: 'Delete expense',
    KApp.expenseDeleteConfirm: 'Delete "{0}"? It leaves the balance, and the changes keep who deleted it and when.',
    KApp.expenseDeleted: 'Expense deleted.',
    KApp.expenseDetailSplit: 'Split',
    KApp.expenseChanges: 'Changes',
    KApp.expenseChangeCreated: '{0} added it on {1}',
    KApp.expenseChangeUpdated: '{0} changed it on {1}',
    KApp.expenseChangeDeleted: '{0} deleted it on {1}',
    KApp.expenseChangeBefore: 'Before: {0} · {1}',
    KApp.expenseOpen: 'Open Expenses',
    KApp.expenseFormerMember: 'Former member',
    KApp.expensePdfSection: '{0}. Expenses',
    KApp.expensePdfLead: 'What the family added as the child\'s expenses in the period, who paid and each one\'s share. A payment between caregivers shows only after the receiver confirmed it.',
    KApp.expensePdfEmpty: 'No expenses in the period.',
    KApp.expensePdfTotals: '{0}: paid {1} · share {2}',
    KApp.expensePdfSettlements: 'Confirmed payments',
    KApp.expensePdfSettlement: '{0} — {1} paid {2} to {3}',
    KApp.expensePdfChanges: 'Changes and deletions',
    KApp.expensePdfChange: '{0} — {1}: {2}',
    KApp.expensePdfUpdated: 'changed "{0}" (before: {1})',
    KApp.expensePdfDeleted: 'deleted "{0}" ({1})',
    KApp.chatNav: 'Inbox',
    KApp.chatTabChat: 'Chat',
    KApp.chatTabNotifications: 'Notifications',
    KApp.chatTabCount: '{0} ({1})',
    KApp.chatNotice: 'What is written here is permanent: it cannot be edited or deleted, the whole family reads it, and it may go into the PDF or a court case.',
    KApp.chatEmpty: 'The family chat starts here.',
    KApp.chatHint: 'Write to the family',
    KApp.chatSend: 'Send',
    KApp.chatReply: 'Reply quoting',
    KApp.chatQuoting: 'Replying to {0}',
    KApp.chatCancelQuote: 'Remove the quote',
    KApp.chatCiteDay: 'Cite a day',
    KApp.chatCitedDay: 'Day cited: {0}',
    KApp.chatRemoveDay: 'Remove the cited day',
    KApp.chatReadBy: 'Read by {0}',
    KApp.chatNotRead: 'Not read yet',
    KApp.chatReadEntry: '{0} ({1})',
    KApp.chatSearch: 'Search the chat',
    KApp.chatSearchClose: 'Close the search',
    KApp.chatSearchEmpty: 'Nothing found for "{0}".',
    KApp.chatMute: 'Silence the chat\'s push',
    KApp.chatMuteLead: 'The notification stays in the app; only the phone stops ringing.',
    KApp.chatMuted: 'Chat push silenced.',
    KApp.chatUnmuted: 'Chat push on.',
    KApp.chatReadOnly: 'You follow the plan: you read the chat, but do not write in it.',
    KApp.chatPremium: 'Writing in the chat is a Premium feature. Without Premium, what was said stays readable.',
    KApp.chatOff: 'The chat is not available yet.',
    KApp.chatErrLoad: 'Could not load the chat.',
    KApp.chatTooLong: 'A text is limited to {0} characters.',
    KApp.chatYou: 'You',
    KApp.chatFormerMember: 'Former member',
    KApp.chatSendFailed: 'Could not send. Try again.',
    KApp.chatPdfInclude: 'Include the period\'s chat',
    KApp.chatPdfSection: '{0}. Family chat',
    KApp.chatPdfLead: 'What the family wrote in the chat during the period, in order, as written. Nothing in the chat is edited or deleted.',
    KApp.chatPdfEmpty: 'Nothing was written in the chat in the period.',
    KApp.chatPdfReply: 'in reply to {0}',
  };
}
