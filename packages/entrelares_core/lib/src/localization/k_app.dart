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

  // ── Day sheet (native read view — the web's editor has no read mode) ──
  static const String sheetNoResponsible = 'app.sheet.noResponsible';
  static const String sheetResponsible = 'app.sheet.responsible';
  static const String sheetSwappedSuffix = 'app.sheet.swappedSuffix';
  static const String sheetTransitionAt = 'app.sheet.transitionAt';
  static const String sheetTransition = 'app.sheet.transition';
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
  static const String profLoginMethod = 'app.prof.loginMethod';
  static const String profLoginMethodGoogle = 'app.prof.loginMethodGoogle';
  static const String profLoginMethodNote = 'app.prof.loginMethodNote';

  // ── F-09 push (the Notificações control) ──
  static const String pushTitle = 'app.push.title';
  static const String pushHintOff = 'app.push.hintOff';
  static const String pushHintOn = 'app.push.hintOn';
  static const String pushHintBlocked = 'app.push.hintBlocked';
  static const String pushHintUnsupported = 'app.push.hintUnsupported';
  static const String pushEnable = 'app.push.enable';
  static const String pushDisable = 'app.push.disable';
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

  /// See `K.allKeys`.
  static const List<String> allKeys = [
    sessionRestoredExpired,
    sessionExpired,
    errCalendarLoad,
    sheetNoResponsible,
    sheetResponsible,
    sheetSwappedSuffix,
    sheetTransitionAt,
    sheetTransition,
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
    profLoginMethod,
    profLoginMethodGoogle,
    profLoginMethodNote,
    pushTitle,
    pushHintOff,
    pushHintOn,
    pushHintBlocked,
    pushHintUnsupported,
    pushEnable,
    pushDisable,
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
  ];
}

/// PT-BR — the original text of this client, verbatim from the stage-1 spike.
abstract final class StringsAppPtBr {
  static const Map<String, String> values = {
    KApp.sessionRestoredExpired: 'Sua sessão anterior expirou.',
    KApp.sessionExpired: 'Sessão expirada — saia e entre novamente.',
    KApp.errCalendarLoad: 'Não foi possível carregar o calendário.',
    KApp.sheetNoResponsible: 'Dia sem responsável definido.',
    KApp.sheetResponsible: 'Responsável: {0}',
    KApp.sheetSwappedSuffix: ' (trocado)',
    KApp.sheetTransitionAt: 'Dia de transição — troca às {0}',
    KApp.sheetTransition: 'Dia de transição',
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
    KApp.profLoginMethod: 'Método de login',
    KApp.profLoginMethodGoogle: 'Conta Google',
    KApp.profLoginMethodNote:
        'Você entra com sua conta Google — não há senha para alterar aqui.',
    KApp.pushTitle: 'Avisos no celular',
    KApp.pushHintOff:
        'Receba um aviso quando alguém pedir uma troca ou responder a sua — '
            'mesmo com o app fechado.',
    KApp.pushHintOn: 'Este aparelho recebe avisos de trocas e prazos.',
    KApp.pushHintBlocked:
        'As notificações estão bloqueadas para o Entrelares nas configurações '
            'do seu aparelho. Libere-as por lá para voltar a receber avisos.',
    KApp.pushHintUnsupported:
        'Avisos no celular funcionam no aplicativo instalado. Aqui no '
            'navegador, você continua vendo tudo nesta tela e por e-mail.',
    KApp.pushEnable: 'Ativar avisos',
    KApp.pushDisable: 'Desativar',
    KApp.pushToastOn: 'Avisos ativados neste aparelho.',
    KApp.pushToastOff: 'Avisos desativados neste aparelho.',
    KApp.pushErrEnable:
        'Não foi possível ativar os avisos agora. Você continua recebendo '
            'tudo nesta tela e por e-mail.',
    KApp.onbStepPushTitle: 'Ativar avisos no celular',
    KApp.onbStepPushHint:
        'Uma troca costuma ser pedida em cima da hora. Com os avisos ligados '
            'você fica sabendo na mesma hora, mesmo com o app fechado.',
    KApp.onbStepPushDoneHint:
        'Este aparelho avisa você sobre pedidos de troca e prazos.',
    KApp.onbStepPushAction: 'Ativar avisos',
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
  };
}

/// EN — same rules as the main catalog: placeholder SETS match PT-BR.
abstract final class StringsAppEn {
  static const Map<String, String> values = {
    KApp.sessionRestoredExpired: 'Your previous session expired.',
    KApp.sessionExpired: 'Session expired — sign out and sign in again.',
    KApp.errCalendarLoad: 'Could not load the calendar.',
    KApp.sheetNoResponsible: 'No caregiver assigned to this day.',
    KApp.sheetResponsible: 'Caregiver: {0}',
    KApp.sheetSwappedSuffix: ' (swapped)',
    KApp.sheetTransitionAt: 'Transition day — handoff at {0}',
    KApp.sheetTransition: 'Transition day',
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
    KApp.profLoginMethod: 'Sign-in method',
    KApp.profLoginMethodGoogle: 'Google account',
    KApp.profLoginMethodNote:
        'You sign in with your Google account — there is no password to '
            'change here.',
    KApp.pushTitle: 'Phone alerts',
    KApp.pushHintOff:
        'Get an alert when someone asks for a swap, or answers yours — even '
            'with the app closed.',
    KApp.pushHintOn: 'This device receives swap and deadline alerts.',
    KApp.pushHintBlocked:
        'Notifications are blocked for Entrelares in your device settings. '
            'Allow them there to start receiving alerts again.',
    KApp.pushHintUnsupported:
        'Phone alerts work in the installed app. Here in the browser you '
            'still see everything on this screen and by e-mail.',
    KApp.pushEnable: 'Turn alerts on',
    KApp.pushDisable: 'Turn off',
    KApp.pushToastOn: 'Alerts are on for this device.',
    KApp.pushToastOff: 'Alerts are off for this device.',
    KApp.pushErrEnable:
        'Could not turn alerts on right now. You still get everything on this '
            'screen and by e-mail.',
    KApp.onbStepPushTitle: 'Turn on phone alerts',
    KApp.onbStepPushHint:
        'A swap is usually asked for at short notice. With alerts on you hear '
            'about it right away, even with the app closed.',
    KApp.onbStepPushDoneHint:
        'This device alerts you about swap requests and deadlines.',
    KApp.onbStepPushAction: 'Turn alerts on',
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
  };
}
