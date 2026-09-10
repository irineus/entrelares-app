# T-53 — Estágio 3: plano de cutover

O registro do T-53 ([`backlog/technical.md`](../backlog/technical.md)) exige três coisas
para o estágio 3 existir: **política de freeze escrita** (está no
[`flutter-paridade.md`](flutter-paridade.md), vigente desde 19/08/2026), **checklist de
aceitação por tela** e **plano de rollback válido até o último usuário migrar**. Este
documento entrega as duas últimas e registra as decisões operacionais da abertura do
estágio. O mapa de paridade continua sendo a lista do QUE construir; este plano define
COMO cada entrega é aceita e como se volta atrás.

**Data da abertura:** 19/08/2026 · **Ordem dos lotes:** 1→2→3→4→6→5 (billing por último,
decisão do owner nas três tensões).

## Ambientes e flavors (decisão da abertura, 19/08/2026)

Ambientes são variantes de build — o singleton do Supabase inicializa uma vez por
processo (lição 8 do piloto), então nunca há switcher de runtime:

| Flavor | `applicationId` | Backend | Uso |
|---|---|---|---|
| `dev` | `com.entrelares.flutter` | Projeto dev (`buroanotfjcgvbfmacuh`) | Todo o desenvolvimento e o QA do owner; coexiste com o app da loja no mesmo aparelho ("Entrelares Dev" no launcher, título com `[Dev]`) |
| `prod` | `com.entrelares.app` | Produção (config pública do `appsettings.json` do web app) | O canal loja — o pacote da Play aceita build Flutter com a mesma assinatura de upload (estágio 0). Assinatura release por flavor via `key.properties` (**T-55**, entregue 19/08/2026): `prod.*` aponta para o keystore de upload do PRODUTO, nunca outro |

`flutter test` e alvos sem flavor caem em dev por construção — produção nunca é alvo
acidental. Os dois configs são públicos (chaves de privilégio zero, T-44); segredo nenhum
entra no repo.

## Checklist de aceitação por tela

Cada lote vira PR(s) no repo `entrelares-flutter`; **cada tela do PR carrega este
checklist preenchido no corpo do PR**. O rollback abaixo referencia esses checklists: uma
tela só conta como "portada" quando todos os itens estão marcados.

```
### Aceitação — <tela> (lote N, linha "<feature>" do mapa)
- [ ] Paridade funcional com a linha do mapa (veredito port/redesign honrado;
      melhoria nativa é permitida, regra de servidor intocada)
- [ ] Toda regra pura da tela tem espelho em `entrelares_core` com `dart test`
      (nenhuma regra nova sem espelho — disciplina herdada dos helpers C#)
- [ ] Cobertura na camada que a coluna Testes da linha exige (core/widget/patrol)
- [ ] UI PT-BR; quando U-13 portar (lote 1): display pelos catálogos por leitor,
      transporte SEMPRE ISO `yyyy-MM-dd` (o invariante U-24 não se move)
- [ ] Erros mapeados: 42501/sessão morta → "sessão expirada" central; conflito
      T-33/T-35 com a mensagem traduzida; texto de erro do servidor propagado
- [ ] `flutter analyze` + suítes verdes no CI (verify.yml)
- [ ] Aceite do owner no build dev (QA no aparelho real)
```

## Plano de rollback — válido até o último usuário migrar

O rollback é barato por construção, e o plano existe para MANTÊ-LO barato até o fim:

1. **O banco não bifurca.** As duas stacks chamam as MESMAS RLS/RPCs/Edge Functions
   (política de freeze, item 3); nenhum lote do estágio 3 pode introduzir schema ou RPC
   que o Blazor não tolere. Consequência: rollback nunca envolve dados — é sempre e
   somente "qual cliente o usuário abre".
2. **Enquanto o cutover não acontece, o Blazor É o produto.** Continua deployado,
   monitorado e com QA (freeze ≠ abandono, política item 4). Rollback nesta fase =
   não fazer nada: nenhum usuário depende do Flutter.
3. **Teste fechado do canal loja** (quando o lote 5 destravar o build prod): rollback =
   interromper o rollout na Play. Os testers voltam ao PWA/web sem perda — conta e
   histórico vivem no servidor.
4. **No cutover (estágio 4)**: passo único, datado e anunciado. Até o último usuário
   migrar, o PWA Blazor permanece publicado como rota de volta; o desligamento do Blazor
   é a ÚLTIMA ação do estágio 4, nunca condição de nenhum lote do estágio 3.
5. **O ponto em que o rollback morre** é explícito: Blazor desligado no estágio 4. Cada
   PR de lote referencia os checklists aceitos; se um lote regride em QA, o item volta
   para o lote sem afetar produção.

## Aceites de canal (das três tensões, decididas 19/08/2026)

- **Web: ACEITO pelo owner em 23/08/2026**, medido no aparelho contra o PWA em
  produção — a última das três tensões a fechar, aberta desde 19/08. O critério nunca foi
  um valor absoluto, e sim *"não pior que o PWA"*, e é por isso que a medição é
  comparativa: mesmo aparelho, mesma rede, os dois endereços. Com isso a tensão 1 está
  inteiramente executada: o alvo web existe, entra no gate, publica sozinho e passou no
  aceite. O texto abaixo fica como registro do critério.

- **Web (o critério, como estava escrito):** Flutter Web substitui o PWA; o **first-load
  em Android mediano/4G é critério de aceite do canal web dentro do estágio 3** — aceite
  de canal, não reabertura da decisão. **O target entrou no `verify.yml` em 19/08/2026 (lote 6)** e cada run imprime
  o peso gzip do first-load (`main.dart.js` ≈ 1,4 MB, `canvaskit.wasm` ≈ 2,9 MB); a
  medição no aparelho — a que decide o aceite — continua pendente com o owner.
- **Loja:** até o card de billing (lote 5) ficar pronto, o build da Play usa o paywall
  neutro (padrão T-38) — nunca link externo de checkout no build da loja.
- **Pré-requisitos de esteira:** **T-55** (keystore próprio) — **ENTREGUE 19/08/2026**,
  cadeia completa: assinatura por flavor, keystore de sideload do owner gerado e build
  release verificado com o certificado dele; **T-54 GANHOU a lane E2E em 19/08/2026**
  com o lote 3 (o primeiro fluxo de 2 usuários): `integration_test` dirige o app real
  em emulador contra o projeto dev, com família descartável (`E2E-<runId>`,
  `@resend.dev`, `purge_e2e_family` no teardown) — agendada (06:10 UTC) e sob demanda,
  fora do gate por push. Falta só o secret `SUPABASE_SERVICE_ROLE_DEV` no repo Flutter.

## Estágio 4 — o cutover (aberto 23/08/2026)

O estágio 3 acabou: os seis lotes, o U-27 e o U-28 estão fechados, e o trilho de loja
está **no ar** (T-48, 23/08/2026, provado por compra real). O que resta não é construir o
app — é **trocar quem atende o usuário**, e desligar o que sobrar quando não sobrar
ninguém.

### As quatro decisões da abertura (owner, 23/08/2026)

1. **O Flutter fica com `web.entrelares.app`**, e o Blazor passa a ser publicado em
   **`legado.entrelares.app`** como rota de volta. É o host que a landing linka em 8
   arquivos, o que o `autoVerify` do App Link declara e o que as redirect URLs do Auth
   já autorizam — trocar o CONTEÚDO do host mexe em nada disso; trocar o ENDEREÇO
   mexeria em tudo.
2. **A loja corta primeiro, o web depois.** O bundle Flutter já está na faixa de teste
   interno e já vendeu de verdade; promovê-lo é ops de Play Console, sem código. O corte
   web vem em seguida, com a esteira já provada em QA. Cada canal com sua data e seu
   rollback.
3. **O anúncio é um banner datado no próprio Blazor**, sem disparo de e-mail: são 17
   famílias, 18 logins em 30 dias — quem tem algo a migrar abre o app.
4. **Três PRs**, com merge direto autorizado.

### O que já está entregue (código)

| Onde | O que |
|---|---|
| `entrelares-flutter` #48/#49 | A **esteira do canal web**: job `deploy-web` no `verify.yml` (Cloudflare Pages, atrás de `needs: verify`, só em `main`, auto-desarmado enquanto faltarem os secrets), `_redirects`, `_headers` com a CSP do CanvasKit, `.well-known/assetlinks.json`, o manifest de instalação e a **lápide do service worker** do Blazor. Mais a correção que o PR revelou: `flutter build web` **não aceita `--flavor`**, então todo build web resolvia para o projeto de QA — o alvo web passa a dizer produção por `--dart-define=APP_ENV=prod`, com gate de fonte (`web_channel_test`) |
| `entrelares-app` #298 | O **aviso datado** no cliente antigo (`CutoverNotice` + `app_settings.cutover.web_date`, semeado vazio), que também é quem diz "esta é a rota de volta" depois que o Blazor mudar de host. App `1.8.14` |

### A armadilha que decide o corte web: o service worker instalado

O SW do PWA Blazor responde **toda navegação pelo próprio cache**. Reapontar o domínio
não alcança quem tem o PWA instalado: o navegador nunca chega a baixar o `index.html` do
Flutter. O que ainda alcança essas instalações é a **checagem de atualização de
`/service-worker.js`** (que o `_headers` sempre serviu como `no-store`). Por isso o build
Flutter serve, nessa URL exata, um worker que limpa os caches, se desregistra e recarrega
as janelas — e por isso esse arquivo **não pode ser removido** enquanto existir aparelho
que possa carregar o worker antigo.

O mesmo mecanismo é o que mantém o rollback barato: se o domínio voltar para o projeto do
Blazor, o SW do Flutter é substituído pelo caminho simétrico.

### Runbook — canal LOJA (primeiro) — **EXECUTADO 23/08/2026**

> Feito: a release `44 (0.2.42)` foi promovida de *Internal testing* para
> **Closed testing – Alpha**, ativa em 177 países. O bundle do TWA (`version code 1`,
> `1.8.4`) passou a **Inactive** na mesma ação — dentro de uma faixa vale o `versionCode`
> mais alto, então a promoção FOI a remoção e o passo 2 não teve o que fazer. Três fatos
> tornaram o passo barato: *managed publishing* desligado (rollout imediato, sem fila),
> **install base 0,00%** nos dois bundles (ninguém tinha o app da loja instalado — as
> famílias estão todas no canal web) e um único testador, que é também o testador
> licenciado (nenhuma cobrança real em jogo, com `billing.store_enabled` já ligado).
> **A partir daqui o pacote `com.entrelares.app` da Play É o app Flutter.**

1. Play Console → o bundle Flutter da faixa de **teste interno** é promovido para a faixa
   em que o produto distribui hoje (alfa fechada). O que conferir antes **não é o
   `versionCode`**: a Play recusa upload com código repetido ou menor, então um bundle que
   chegou à faixa interna já satisfaz isso por construção. O que a Play NÃO julga — e por
   isso é o único item que pede olho humano — é **qual versão do app** está naquela faixa:
   promover um bundle anterior ao U-28 entregaria aos testadores a interface de antes das
   seis rodadas de QA no aparelho. *Verificado em 23/08/2026: a faixa interna carrega
   `44 (0.2.42)`, que é o build homologado; o `0.2.43+45` de `main` mexeu só em canal web
   e não altera nada no Android.*
2. Remover o TWA das faixas — a partir daqui o pacote da Play **é** o app Flutter.
3. **Rollback — e ele NÃO é simétrico.** Interromper o lançamento impede quem ainda não
   atualizou, mas a Play **não empurra downgrade**: quem já recebeu o Flutter fica nele.
   Voltar de verdade exigiria republicar o TWA com um `versionCode` MAIOR que o do bundle
   Flutter. Dado nenhum se perde — conta e histórico vivem no servidor, e as duas cascas
   falam com o mesmo banco —, mas este passo é **bem menos reversível que o do canal web**,
   onde o rollback é mover um domínio no painel. É a assimetria que justifica cortar a
   loja primeiro: ela é a decisão mais difícil de desfazer, e vale tomá-la enquanto o canal
   web ainda está inteiro como rota de saída.
4. T-52 (aposentar `com.guardacompartilhada.app`) segue item próprio, independente disto.
   *CONCLUÍDO em 09/09/2026: o pacote foi deletado no Play Console e a declaração dele saiu do
   `assetlinks.json` (PR #132).*
5. **A faixa de teste interno FICA** — é a pista rápida de QA, e é dela que se promove.
   Mas guarde a regra que ela impõe: a Play tem **precedência entre faixas**, e *interno
   vence fechado*. Quem está nas duas listas — o owner está — recebe sempre o build da
   INTERNA. Hoje isso é indiferente (as duas carregam o mesmo bundle 44), mas no dia em
   que a interna receber um build mais novo, o aparelho do owner deixa de ser amostra do
   que o grupo alfa vê. Para conferir a experiência real do testador nesse dia: `Pause
   track` na interna (reversível; desinstalar e reinstalar depois) ou uma conta
   secundária que só esteja na Alpha. Não existe apagar faixa na Play — existe pausar.

### Runbook — canal WEB (depois) — **EXECUTADO 23/08/2026**

> Feito, nesta ordem: `legado.entrelares.app` anexado ao projeto Pages do Blazor e
> acrescentado às Redirect URLs do Auth; `web.entrelares.app` removido do projeto antigo e
> anexado ao **`entrelares-web`**. Conferido de fora da conta: o hostname de produção serve
> Flutter `0.2.48+50`, rota profunda responde 200, `/privacy` faz 301 para a landing, o
> `assetlinks.json` está servido — o App Link do app instalado continua verificando — e a
> **lápide do service worker responde na origem de produção**, que é o único caminho que
> alcança um aparelho com o PWA antigo instalado. `qa.entrelares.app` ficou onde estava.
>
> **Duas pontas soltas, deliberadamente fora do corte:** (1) a promoção `dev`→`master` está
> presa por um E2E VERMELHO (`BulkUiTests`, determinístico, só quando os dias alocados caem
> na última linha do mês — caminho exclusivo do Blazor, intocado pelo diff), e com ela a
> cópia `1.8.15` da política dentro do cliente antigo; a exigência jurídica JÁ está cumprida
> porque o app Flutter linka a LANDING, publicada em Versão 1.7 com o Google declarado como
> operador. (2) Sem essa promoção, o `legado.` fica **mudo** — o código do aviso
> (`CutoverNotice`) está no `1.8.14`, que é justamente o que ficou preso. Como o `legado.` é
> rota de rollback e não destino anunciado, isso não bloqueou o corte; quando a promoção
> passar, ele ganha a frase sozinho.

1. **Owner, uma vez:** criar o projeto Cloudflare Pages **`entrelares-web`** (o nome é
   imutável — está fixado no workflow) e definir no repo `entrelares-flutter` os secrets
   `CLOUDFLARE_API_TOKEN` e `CLOUDFLARE_ACCOUNT_ID`. Enquanto faltarem, o job compila e
   **pula** a publicação, sem pintar `main` de vermelho.
2. **QA sem risco:** o primeiro push em `main` publica em `entrelares-web.pages.dev`. Esse
   endereço já fala com **produção** — é o app de verdade, só que sem o domínio. É aqui
   que o aceite por tela e a medição de first-load em Android mediano/4G (o aceite do
   CANAL, tensão 1) acontecem.

   **FEITO em 23/08/2026, e pagou-se sozinho: SEIS defeitos, todos invisíveis no
   Android.** Nenhum teria sido pego por suíte, porque nenhum é sobre lógica — são sobre
   o que a plataforma faz de diferente:

   | # | Defeito | Por que só no web |
   |---|---|---|
   | 1 | A CSP barrava o *fallback* de fontes do CanvasKit | O Android desenha emoji com a fonte do sistema; o CanvasKit precisa BUSCAR o glifo |
   | 2 | Rotas por `#` (`/#/family`) | O estrago real seria depois do corte: o token do convite viaja no CAMINHO, que um roteador de hash nunca vê |
   | 3 | Export LGPD morria no snack genérico | A entrega usava `dart:io` + folha de compartilhamento; no navegador é `<a download>` — o mesmo motivo pelo qual o PDF já funcionava |
   | 4 | A mensagem de erro imprimia `{0}` | O call site lia a chave em vez de formatá-la, e engolia a exceção |
   | 5 | "Sua sessão anterior expirou" ao clicar em Sair | Corrida entre o evento `signedOut` e o próprio logout; a ordem de chegada difere na web |
   | 6 | Calendário de ponta a ponta no desktop | Quebra de paridade: o PWA Blazor sempre viveu numa coluna (`max-width: 500px`); o Flutter agora usa 600 |

   Mais o F5, que precisou de DUAS correções: a estratégia de URL (defeito 2) arrumou o
   endereço, e o destino continuava perdido — o portão de sessão lembrava a tela e só a
   devolvia a visitante ANÔNIMO. Verificado no fim: F5 volta para a tela certa, o splash
   pisca sem sujar o histórico (um "voltar" sai do site, não caminha pelo splash), e as
   rotas profundas, o Realtime, o PDF e o modo escuro passam.

   **A lição que fica:** o canal web exercita caminhos que o Android nunca tocou —
   recarga, histórico do navegador, entrega de arquivo, CSP. Um lote inteiro de QA em
   aparelho não substitui uma hora de QA no navegador.
3. **Anunciar:** escrever a data no setting público —
   `update app_settings set value = '2026-08-DD' where key = 'cutover.web_date';` — em
   produção. A partir daí todo mundo que abre o Blazor vê o aviso datado.
4. **O corte, no dia:**
   a. adicionar `legado.entrelares.app` como domínio customizado do projeto Pages
      `entrelares-app` (o Blazor), e conferir que ele responde;
   b. adicionar `legado.entrelares.app` às **Redirect URLs** do Auth do Supabase, para que
      recuperação de senha e convites ainda funcionem por lá;
   c. mover o domínio **`web.entrelares.app`** do projeto `entrelares-app` para o projeto
      `entrelares-web`;
   d. conferir, num aparelho com o PWA antigo instalado, que a lápide roda: o app recarrega
      sozinho no Flutter;
   e. conferir um App Link real (link de convite) abrindo no app instalado — é o teste que
      prova que o `assetlinks.json` viajou junto.
5. **Rollback (enquanto o Blazor estiver publicado):** mover o domínio de volta para o
   projeto `entrelares-app`. Sem migração, sem dado, sem release — o banco nunca bifurcou
   (item 1 do plano acima).

### Onde o rollback morre — ACONTECEU em 24/08/2026

> **Esta seção é história, e uma das suas frases foi REVOGADA um dia depois de escrita.** O que
> aconteceu de fato está no **T-56** ([`arquivamento-app.md`](arquivamento-app.md), e o registro
> em [`../backlog/archive/phase-7.md`](../backlog/archive/phase-7.md)). O texto original fica
> abaixo porque a revogação só se lê com ele.

O desligamento veio no dia seguinte ao corte, não por medição: **o owner declarou a rota de
rollback desnecessária em 24/08/2026**. Dos três marcadores previstos abaixo, dois se cumpriram
como escritos (domínio e projeto Pages; a metade do `deploy.yml` que publicava) e **o terceiro
foi invertido**: a suíte Playwright e a de integração C# saíram ANTES, no esvaziamento, porque o
repo Flutter ganhou gate de fluxo próprio (`web-e2e`) e gate de banco próprio — a premissa de
"até lá ela continua sendo o gate de fluxo" expirou quando esses dois passaram a existir aqui.

**A frase revogada é a do meio.** "O repo `entrelares-app` NÃO é aposentado" valia enquanto este
repositório era a aposta e o Blazor era o produto; o cutover inverteu os dois papéis no dia
seguinte, e manter o banco, o gate e a memória escrita num repositório que ninguém mais abre é o
caminho mais curto para perdê-los. Decisão nova do owner, 24/08/2026 — é o T-56 inteiro.

*Texto original, para leitura da revogação:*

> No **desligamento do Blazor**, que é a ÚLTIMA ação do estágio e não tem data marcada
> aqui: acontece quando o owner constatar que ninguém mais chega pelo `legado.`. Nesse dia,
> e só nesse dia:
>
> - remover o domínio `legado.entrelares.app` e o projeto Pages `entrelares-app`;
> - retirar do `deploy.yml` a metade que publica o cliente Blazor — **o repo `entrelares-app`
>   NÃO é aposentado**: ele continua sendo o repo do banco, das Edge Functions, do backlog e
>   do gate de integração;
> - **só então** aposentar a suíte Playwright (`Entrelares.E2ETests`), que testa a UI que
>   deixou de existir. Até lá ela continua sendo o gate de fluxo da promoção para
>   produção — a lane `integration_test` do repo Flutter é agendada, não roda por push, e
>   retirar o Playwright antes deixaria a promoção sem gate de fluxo nenhum.

## Registro das entregas do estágio

| Data | Entrega | Onde |
|---|---|---|
| 19/08/2026 | Abertura: este plano + flavors dev/prod (`--flavor` obrigatório, tag `[Dev]`, `app 0.2.0+2`) | `entrelares-flutter` PR da abertura |
| 19/08/2026 | **Lote 1 (fundação) ENTREGUE** em 3 PRs: i18n bilíngue U-13/U-24 (`0.2.2+4`), casco go_router + App Links de recovery + S-01/S-04 (`0.2.3+5`; assetlinks dev pareado neste repo), card Today at a Glance + espelhos T-41/F-32 + SnackBar/banner âmbar (`0.2.4+6`). Checklists de aceitação preenchidos nos corpos dos PRs; **pendências de QA do owner no aparelho**: aceite por tela e App Links (exige build RELEASE dev + promoção dev→master do assetlinks) | `entrelares-flutter` #6, #9, #10 + `entrelares-app` #279 |
| 19/08/2026 | **Lote 2 (calendário completo) ENTREGUE** em 4 PRs: regras core (FreemiumGates/BulkSummary/proteção de dia F-40/wizard) + clamp F-39 na paginação (`0.2.5+7`), editor completo do dia + modo administrador F-14 com F-40 proativo (`0.2.6+8`), multi-seleção U-11 + Bulk Edit + guard de navegação (`0.2.7+9`), Rotation Wizard com escrita insert-only que preserva dias existentes (`0.2.8+10`). Fatia deliberada: sem workflow — congelados, responsável real geral e F-44 chegam com o lote 3; cobertura core + widget (403 + 67 testes), patrol acumula para a lane do lote 3. Checklists nos corpos dos PRs; **aceite por tela do owner no build dev pendente** | `entrelares-flutter` #11, #12, #13, #14 |
| 19/08/2026 | **Lote 3 (workflow de troca + notificações) ENTREGUE** em 5 PRs: espelho core do `SwapRequestService` + data source do workflow (`0.2.9+11`), dias congelados 🔔/⏳ + painel do dia congelado (`0.2.10+12`), roteamento de workflow no editor e no Bulk Edit + 🔔 Resolver (`0.2.11+13`), página de Notificações de 3 abas + badge do sino + poll F-23 (`0.2.12+14`), **lane E2E do primeiro fluxo de 2 usuários** (`0.2.13+15`). Decisões do lote: poll F-23 mantido como rede de segurança (25 s socket caído / 120 s saudável) até o socket provar-se sob carga real; lane E2E **agendada (06:10 UTC) + sob demanda**, nunca por push — mesma aritmética de minutos que manteve o APK fora do gate; enriquecimento F-45 do histórico adiado para o lote 6 (chega com o espelho de auditoria). Cobertura: 484 core + 95 widget + a lane E2E. Checklists nos corpos dos PRs; **aceite por tela do owner no build dev pendente**, e a lane E2E precisa do secret `SUPABASE_SERVICE_ROLE_DEV` no repo Flutter para a primeira execução verde | `entrelares-flutter` #15, #16, #17, #18, #19 |
| 19/08/2026 | **Lote 4 (conta, família e legal) ENTREGUE** em 6 PRs: espelhos core (RoleCatalog, CustomRoleRules, ConsentDeclarations, PolicyVersions, SudoRules, OnboardingSteps/TourSteps, Register/InviteFormRules) + cliente sudo S-10 com a folha 🔐 e as DUAS camadas do `runWithSudo` (`0.2.14+16`), `/register` nativo com os ramos fundador × convidado + consentimento S-15 por ramo + convite como App Link + migração cross-family (`0.2.15+17`), página Família (roster, rename, convites com share sheet, aritmética de assentos F-37) + `/custom-roles` F-41 (`0.2.16+18`), `/profile` e `/profile/{id}` + troca de papel + toggle admin sob sudo + e-mail/senha + export LGPD pelo share sheet (`0.2.17+19`), saída S-11 + `/leaving` + painel de exclusão da família com unanimidade + banner persistente + portão de re-consentimento `/policy-update` (`0.2.18+20`), onboarding U-23 (checklist de estado real, folha da troca, tour de 4 paradas com spotlight nativo) + **pack E2E de conta** (`0.2.19+21`). Decisões do lote: **páginas legais abrem no NAVEGADOR** (uma cópia só do texto jurídico; link externo é aceito pelas lojas), **edição de membro segue o produto e não o mapa** (F-16 — promote/demote e troca de papel vivem em `/profile/{id}`, e a página `/profile` NÃO estava no mapa), bloco premium/billing deliberadamente fora (lote 5, padrão T-38 de paywall neutro). Cobertura: 678 core + 255 widget + 2 packs E2E. Checklists nos corpos dos PRs; **aceite por tela do owner no build dev pendente** (o tour, o share sheet do export e os App Links de convite pedem aparelho real) | `entrelares-flutter` #20, #21, #22, #23, #24, #25 |
| 19/08/2026 | **Lote 6 (relatórios, analytics e plataforma) ENTREGUE** em 5 PRs: espelhos core de relatórios e auditoria — contagens U-20/U-07 numa função só usada pela tela E pelo documento, diff de auditoria, as quatro frases de origem F-45, rótulos S-10 e a entrada sintética de fim de trial (`0.2.20+22`), casca de Relatórios com 3 abas + Resumo do Período (`0.2.21+23`), Histórico de Ajustes com as 4 abas, "carregar mais" e **F-45** (`0.2.22+24`), **relatório F-33 em PDF nativo** com share sheet/impressão e gate F-32 com upsell neutro (`0.2.23+25`), analytics T-37 + **alvo web** + fecho do lote (`0.2.24+26`). Decisões do lote: **abas em vez de rotas** no hub (o web navega entre três rotas por não ter casca persistente); **sem visualizador de PDF embutido** — o passo nativo útil é entregar o arquivo ao sistema; **Roboto embarcado** no documento porque a Helvetica do `dart_pdf` não tem Unicode e derrubava os acentos; **upsell neutro** (T-38) até o lote 5; `premium-gate-click` adiado com as CTAs que ele mede. **Tensão 1 executada**: target web habilitado e `flutter build web` no `verify.yml`, que imprime o peso gzip do first-load (hoje `main.dart.js` ≈ 1,4 MB + `canvaskit.wasm` ≈ 2,9 MB gzip) — o **aceite do canal continua pendente**: medição real em Android mediano/4G é do owner. Cobertura: 738 core + 312 widget + 2 packs E2E, mais o gate `catalog_call_sites_test` (toda chave do catálogo tem call site ou classificação). Checklists nos corpos dos PRs; **aceite por tela do owner no build dev pendente** | `entrelares-flutter` #26, #27, #28, #29, #30 |
| 20/08/2026 | **Lote 5 (premium e billing) ENTREGUE** em 5 PRs — o ÚLTIMO lote funcional do estágio 3: espelhos core de billing + modelo e leituras da assinatura (`0.2.25+27`), seção Premium na Família com os seis estados + waitlist + cancelamento + caminho de volta F-42 (`0.2.26+28`), rail web (checkout T-39 e Pix avulso F-48) + `/premium/retorno` + histórico F-43 + o funil T-37 completo, incluindo o `premium-gate-click` que o lote 6 adiou (`0.2.27+29`), **Play Billing no cliente** atrás do interruptor `billing.store_enabled` (`0.2.28+30`), e a metade SERVIDOR do T-48 neste repo (migração do gateway `play` + purchase token UNIQUE, `billing-store-verify` e `billing-store-webhook` de RTDN, ambos passando pelo MESMO `set_family_plan` e pelo MESMO ledger `billing_events`; app `1.8.13`). Decisões do lote: **T-48 completo atrás de master switch** (o código existe inteiro e dorme até o Play Console existir), **o preço do canal loja é o da Play** (o produto carrega o próprio preço; o `app_settings` rege só o rail web), e a **nota neutra T-38 é o padrão de FALHA** do ramo de loja, não só o estado desligado. O gate `catalog_call_sites_test` fechou a lista de billing: as 82 chaves têm call site, e a lista foi REMOVIDA. Cobertura: 782 core + 367 widget + 2 packs E2E; suíte de integração C# ganhou `BillingStoreTests` (gateway, token único entre famílias, RLS das colunas novas, interruptor público em `false`, recusa anônima do verify). **Pendências do owner, sem as quais o trilho da loja não vende**: criar os dois produtos de assinatura no Play Console, publicar a faixa fechada, ligar as RTDN via Pub/Sub, criar a service account com acesso à Play Developer API, definir os secrets `PLAY_SERVICE_ACCOUNT`, `PLAY_RTDN_TOKEN` e `PLAY_PACKAGE_NAME`, e só então virar `billing.store_enabled` para `true`. **Aceite por tela pendente**, e o da compra exige aparelho real com conta de teste de licença | `entrelares-flutter` #31, #32, #33, #34, #35 + `entrelares-app` (este PR) |
| 23/08/2026 | **Estágio 4 ABERTO**: decisões da abertura + runbook dos dois canais (acima). Entregas de código: a **esteira do canal web** no repo Flutter (`deploy-web` no `verify.yml`, `_redirects`/`_headers`/`assetlinks`/lápide do SW, e a correção do `APP_ENV=prod` — sem ela todo build web apontava para o banco de QA; `0.2.43+45`), e o **aviso datado** no cliente Blazor (`CutoverNotice` + `cutover.web_date` semeado vazio; app `1.8.14`). O corte em si é ops do owner e **não aconteceu**: T-53 segue `in-progress` | `entrelares-flutter` #48, #49 + `entrelares-app` #298 e este PR |
| 23/08/2026 | **Canal LOJA CORTADO**: `44 (0.2.42)` promovida para *Closed testing – Alpha* (177 países); o bundle do TWA (`versionCode 1`) virou `Inactive` na mesma ação. Install base era 0,00% nos dois — nenhum usuário interrompido. Na mesma leva, o QA do canal web pegou o primeiro defeito antes de qualquer usuário: a CSP barrava o *fallback* de fontes do CanvasKit (`fonts.gstatic.com`), e sem ele o emoji do produto sairia como caixinha SÓ no web; liberado por decisão do owner, com o Google declarado operador na §7 da política (app `1.8.15`, landing Versão 1.7) | `entrelares-flutter` #51 + `entrelares-app` #301, #302 e este PR + `entrelares-site` #59 |
| 23/08/2026 | **CANAL WEB CORTADO — o estágio 4 cumpriu seu passo, e o T-53 FECHA.** `web.entrelares.app` passou a ser servido pelo projeto `entrelares-web` (Flutter `0.2.48+50`), com `legado.entrelares.app` publicado como rota de volta e autorizado no Auth. Com a loja já cortada de manhã, **os dois canais são Flutter** — a aposta declarada em 12/08/2026 entregue em onze dias. O QA do canal, feito antes do corte, achou e consertou seis defeitos invisíveis no Android, e mais um que só a preparação do corte revelaria: as páginas legais apontavam para o host que estava mudando de dono, e teriam ficado inalcançáveis de dentro do produto no minuto seguinte à troca. O que resta NÃO é deste item: o desligamento do Blazor, que é quando o rollback morre | `entrelares-flutter` #51…#56 + `entrelares-app` #303…#306 e este PR + `entrelares-site` #59 |
