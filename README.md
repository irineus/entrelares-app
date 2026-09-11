# Entrelares — o app de produto (Flutter/Dart)

**Este repositório É o produto, nos dois canais.** O pacote Play `com.entrelares.app` carrega
este bundle e `web.entrelares.app` é servido daqui — desde o cutover do T-53, em **23/08/2026**.
Um merge em `main` chega a usuário real.

Nasceu como spike do estágio 1 (GO do owner em 19/08/2026) e foi construído lote a lote pelo
mapa de paridade ([`docs/flutter-paridade.md`](docs/flutter-paridade.md)) atrás do plano de
cutover ([`docs/flutter-cutover.md`](docs/flutter-cutover.md)). O cliente Blazor que ele
substituiu ficou publicado em `legado.entrelares.app` como rota de rollback até **24/08/2026**,
quando o owner declarou a rota desnecessária; o cliente foi desligado e o `entrelares-app-legacy` está
**arquivado** desde 25/08/2026, somente-leitura
(T-56, [`docs/arquivamento-app.md`](docs/arquivamento-app.md)). **Não há mais volta**, que é a
consequência ordinária de um cutover que deu certo.

## Os nomes antigos, e o que eles querem dizer (T-69, 11/09/2026)

Este repositório se chamou **`entrelares-flutter`** e o app morou em **`apps/entrelares_app`** —
os dois eram nomes do cutover C#→Flutter (T-53/T-56), um momento que acabou. Hoje o repositório é
`entrelares-app` e o app é `app/`.

**`docs/` e `backlog/` NÃO foram reescritos**: são história congelada, e lá dentro os nomes valem
para a data que descrevem. Em particular, **`entrelares-app` naqueles documentos é o cliente
Blazor** — que hoje é [`entrelares-app-legacy`](https://github.com/irineus/entrelares-app-legacy),
arquivado. Linhas como *"`entrelares-flutter` #51 + `entrelares-app` #303"* falam de dois
repositórios diferentes, e é por isso que trocar o nome nelas as tornaria mentira.

Ponteiro vivo — workflow, script, comando, este arquivo — carrega o nome de hoje. Prosa datada
carrega o nome do dia.

## Estrutura (molde `irineus/desmalha`)

```
.fvmrc                        # pin do Flutter (3.44.7) — só o .fvmrc é versionado, .fvm/ não
tool/setup_env.sh             # bootstrap idempotente de ambiente Linux (JDK 17, FVM, Android SDK)
app/                          # o app Flutter (só orquestra e apresenta)
app/lib/theme/                # U-27: tokens.dart (a única fonte de cor) + app_theme.dart
app/tool/                     # subset_inter.py — regenera a fonte embarcada (U-27)
packages/entrelares_core/     # Dart puro: espelhos-cliente das regras do servidor, testáveis com `dart test`
packages/entrelares_core/test/mirrors/   # T-56/F-09/T-62: os seis espelhos (i18n.ts, migrations, service worker)
packages/entrelares_db_contracts/        # T-56 PR 6: as formas de linha do PostgREST, lidas pelo app E pelo gate
packages/entrelares_db_gate/  # T-56 PRs 6-16 + F-57 + F-09 + F-56 + F-62: o gate de banco (256 testes), Dart puro
supabase/                     # T-56 PR 3: migrations, Edge Functions e o runbook de deploy
backlog/                      # T-56 PR 4a: a memória escrita do produto (registros + archive/)
store/                        # T-56 PR 4c: listagens da Play, masters de marca e seus geradores
```

> Nenhum pacote sob `packages/` pode importar Flutter: o gate tem de rodar sob `dart test` puro,
> e os contratos precisam ser importáveis pelos dois lados.

## Comandos

```
fvm flutter --version                                  # 3.44.7 (pinado)
cd packages/entrelares_core && fvm dart test           # regras puras, sem emulador
cd app && fvm flutter analyze && fvm flutter test
cd app && fvm flutter build apk --debug --flavor dev --split-per-abi
# Preview do alvo web em 127.0.0.1:8080 — é o caminho mais rápido para conferir a
# camada visual (U-27), inclusive o tema escuro pelo prefers-color-scheme do
# navegador. Mesmo comando que `.claude/launch.json` roda.
cd app && fvm flutter run -d web-server --web-port 8080
# E2E (lote 3): app real em emulador contra o projeto dev — exige a service_role key
cd app && fvm flutter test integration_test/swap_workflow_test.dart \
  --flavor dev --dart-define=E2E_SUPABASE_SERVICE_ROLE_KEY=<chave dev>
# Gate de banco: 256 testes de RLS/RPC/trigger contra o projeto dev, com família
# descartável. Exige a service_role do DEV (nunca a de produção); sem ela a suíte
# aborta com instruções em vez de rodar pela metade.
cd packages/entrelares_db_gate && E2E_SUPABASE_SERVICE_ROLE_KEY=<chave dev> fvm dart test
```

**Flavors (estágio 3):** todo build Android exige `--flavor dev` ou `--flavor prod` —
ambientes são variantes de build (o singleton do Supabase inicializa uma vez por
processo), nunca um switcher de runtime. `dev` = `com.entrelares.flutter` contra o
projeto dev ("Entrelares Dev" no launcher, título com `[Dev]`); `prod` =
`com.entrelares.app` (o pacote da Play) contra produção. Builds release assinam por
flavor via `key.properties` (T-55 — ver "Assinatura (release)" abaixo). `fvm flutter
test` não tem flavor e cai em dev por construção.

**CI (T-54):** todo push/PR roda `.github/workflows/verify.yml` — analyze + `dart test`
no core e analyze + `flutter test` no app, com o Flutter lido do `.fvmrc`. O build de
APK fica FORA do gate (cota de 2000 min/mês da conta, compartilhada com os repos do
produto) — para gerar APK pela CI, use o `workflow_dispatch` com `build-apk`. O APK
da CI é **debug** (o runner não tem — e nunca terá — os keystores do T-55; release é
build local por construção).

**Lane E2E (aberta pelo lote 3 do T-53):** `integration_test/` dirige o app REAL em
emulador contra o projeto dev, no primeiro fluxo de 2 usuários (workflow de troca) —
o **banco é a asserção**, não a UI. Família descartável por execução no mesmo padrão
da suíte web (`E2E-<runId>`, e-mails `@resend.dev`, teardown sempre via
`purge_e2e_family`, cuja guarda de assinatura dupla vive no BANCO; varredura de
órfãs > 2h no início). Também fora do gate por custo de minutos: roda **agendada
(06:10 UTC diário)** e sob demanda pelo `workflow_dispatch` (`run-e2e`, com
`e2e-pack` = `p0` de fumaça ou `full`). A `service_role` do dev chega só pelo secret
`SUPABASE_SERVICE_ROLE_DEV` → `--dart-define`; nunca entra no repositório.
O job `web-e2e` (esse SIM no gate) roda os mesmos arquivos num Chrome headless, mais
`deep_link_test` — o único que é web por construção: uma entrada fria numa URL interna
só se comporta mal onde o navegador entrega o próprio endereço ao app (T-64).

## Gate de banco (`packages/entrelares_db_gate/`)

**256 testes** sobre RLS, RPCs `SECURITY DEFINER`, triggers e o ledger de cobrança,
rodando contra o projeto **dev** real com família descartável. É a camada que prova o
invariante do produto — *o cliente ESPELHA, o banco IMPÕE* — e veio do `entrelares-app-legacy`,
que está sendo arquivado (ver [`docs/arquivamento-app.md`](docs/arquivamento-app.md)).

Chegou em **C#** e é **Dart puro desde 24/08/2026** (T-56, PRs 6 a 16): cada PR da travessia
traduziu um grupo e apagou, **no mesmo commit**, as classes C# que substituiu — o gate nunca
ficou descoberto, e a soma `C# + Dart` fechou 225 em todos eles. O que sobreviveu à travessia
como decisão de arquitetura são três coisas: os contratos PostgREST viraram um pacote próprio
(`packages/entrelares_db_contracts`), lido pelo app **e** pelo gate; o `supabase` puro (nunca
o `supabase_flutter`, que é singleton por processo e não sabe conviver com cinco identidades
na mesma execução); e um **entrypoint agregador** — `dart test` dá um `setUpAll` por ARQUIVO,
então as 43 suítes são bibliotecas chamadas por um único `_test.dart`, que é o que mantém
**uma** família descartável por execução em vez de 43.

No CI é o job `db-gate` do `verify.yml`, nos mesmos eventos do `verify` e **bloqueando o
`deploy-web` junto com ele**. Roda serializado no repo inteiro (`concurrency: db-gate`):
famílias são únicas por execução, mas as seeds de billing do T-39 usam ids externos FIXOS
(`sub_e2e_*`), e duas execuções sobrepostas apagariam as linhas uma da outra.

## Assinatura (release) — T-55

Builds **release** exigem `app/android/key.properties` (git-ignorado);
sem ele o build **falha com erro claro** — nunca sai APK release assinado com as chaves
de debug desta máquina (lição 2.2 do piloto: keystore de debug é por máquina, e um
aparelho que instalou um build debug-signed precisa DESINSTALAR — perdendo dados locais —
para aceitar build de outra origem). Builds debug não são afetados.

Os keystores vivem **FORA do repositório** e as senhas nunca entram no repo nem numa
sessão cloud (regra permanente 1). O `key.properties` tem entradas **por flavor**:

```properties
# dev — keystore dedicado de sideload (T-55), gerado em 19/08/2026. Para
# recriar do zero (PowerShell — a pasta primeiro, o keytool não a cria):
#   New-Item -ItemType Directory -Force "$env:USERPROFILE\keystores"
#   keytool -genkey -v -keystore "$env:USERPROFILE\keystores\entrelares-app.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias entrelares
dev.storeFile=C:/Users/irineu/keystores/entrelares-app.jks
dev.storePassword=...
dev.keyAlias=entrelares
dev.keyPassword=...

# prod — o keystore de UPLOAD do produto (F-54). O pacote da Play
# (com.entrelares.app) só aceita essa assinatura de upload (achado do estágio 0) —
# nunca aponte prod.* para outro keystore. Ele nasceu em
# `entrelares-app-legacy/store/android.keystore` e SAIU DE LÁ em 25/08/2026: aquele
# repositório está arquivado (T-56), e uma chave de publicação não pode morar num
# clone que ninguém tem mais motivo para manter no disco. A cópia é byte a byte, e
# a impressão SHA-256 é a mesma que o assetlinks.json declara como upload.
prod.storeFile=C:/Users/irineu/keystores/entrelares-upload.keystore
prod.storePassword=...
prod.keyAlias=android
prod.keyPassword=...
```

As entradas são separadas por construção para o upload da Play nunca sair assinado com a
chave de sideload por engano. O keystore deste card (`dev.*`) é só para distribuição
direta/sideload; ele NÃO cria uma segunda identidade na Play.

**Os dois keystores existem em UM lugar só, e é fora de qualquer repositório.** Perder o
de upload não é fatal — o pacote usa **Play App Signing**, então a chave que assina o que
o usuário instala é do Google e a nossa é só a de upload, que o suporte da Play redefine
a pedido. Mas a redefinição custa dias de fila num canal que publica produção, então
`~/keystores/` merece o mesmo backup que qualquer segredo: cópia fora da máquina, senhas
no gerenciador. Para conferir que o Gradle enxerga os dois — sem abrir nenhuma senha:

```
cd app/android && ./gradlew :app:signingReport
```

O `Variant: prodRelease` tem que imprimir a impressão SHA-256 que o
`app/web/.well-known/assetlinks.json` declara para `com.entrelares.app`.
Se divergir, o build sai assinado com a chave errada e a Play recusa o upload.

## i18n (U-13/U-24 — lote 1)

Bilíngue por leitor (PT-BR / EN), portado do app web:

- **Catálogos gerados, nunca editados à mão:** `packages/entrelares_core/lib/src/localization/`
  (`k.dart` + `strings_pt_br.dart` + `strings_en.dart`, 961 chaves) são espelhos mecânicos
  dos `K.cs`/`StringsPtBr.cs`/`StringsEn.cs` do repo `entrelares-app-legacy`, regenerados por
  `python tool/port_catalogs.py <caminho-do-entrelares-app-legacy>`. Strings que só existem
  neste cliente vivem em `k_app.dart` (prefixo `app.`), à mão.
- **Resolução** (`LanguageResolver`): escolha local > `profiles.language` > locale do
  aparelho > PT-BR. Idioma fixo no boot; a troca (picker no login e no calendário)
  reconstrói a árvore da raiz — o análogo do `forceLoad` do web. Adoção cross-device e
  gravação de `language_detected` seguem as mesmas regras puras do web
  (`Localization.shouldAdopt` / `shouldRecordDetected`).
- **Display por idioma, wire congelado** (U-24): EN = `05 Aug 2026` + relógio 12h; PT =
  `dd/MM/yyyy` + 24h. Transporte continua ISO `yyyy-MM-dd` (`CareSchedule.isoDate`) e
  nunca passa pelos formatadores de display. Tabelas de nomes hardcoded (sem `intl`/ICU),
  espelhando a decisão anti-drift do `_shared/i18n.ts`.
- **Renderer de notificações** (`NotificationRenderer`): `type` + `params` viram a frase
  no idioma do leitor; linhas legadas/payloads desconhecidos caem para o texto armazenado.
  PT-BR é byte-idêntico ao que os triggers gravam (tabela de ~35 casos em
  `notification_renderer_test.dart`).
- **Push renderiza no SERVIDOR** (F-09): um push não tem dispositivo onde renderizar, e no
  iOS uma mensagem data-only não tem entrega garantida — então `_shared/push.ts` monta o
  texto por destinatário, em Deno, a partir de `language_effective`. É duplicação
  deliberada do catálogo, e `push_notification_mirror_test.dart` compara os dois lados
  string por string nas duas línguas.
- **E na WEB o toque também sai do Dart** (T-62): um clique em notificação exibida por
  service worker é tratado contra o WORKER — `onMessageOpenedApp` não tem implementação
  web nenhuma —, então `web/firebase-messaging-sw.js` reespelha `PushRouting` e abre
  `/notifications?tab=…&n=…`, a mesma URL que o `main.dart` monta no Android.
  `push_routing_worker_mirror_test.dart` é o sexto espelho, e o primeiro que não é
  Dart↔Deno. O canal web sobe DARK: sem a config do §11-bis do runbook o controle diz
  `unsupported` por escrito, em vez de oferecer um botão que não funciona.
- **Gate cobrado no fechamento do lote 6:** `catalog_call_sites_test.dart` prova que toda
  chave declarada ou tem call site, ou está classificada (web-only · o app tem frase própria
  em `k_app` · dívida anotada). As listas falham nos DOIS sentidos — uma chave órfã nova
  quebra o teste, e uma entrada que ganhou call site também. **O lote 5 fez a lista de
  billing zerar**: as 82 chaves ganharam call site e a lista foi REMOVIDA, que era
  exatamente o que o gate existia para forçar.

## Casco e deep links (lote 1 — PR2)

- **Navegação:** `go_router` com `StatefulShellRoute` — os mesmos 4 destinos do NavMenu
  web (Calendário, Família, Avisos, Relatórios); cada lote trocou um placeholder pelo
  miolo real, e com Relatórios (lote 6) não sobrou nenhum. Guard estilo S-02 no `redirect`: tudo é
  protegido exceto `/login`, `/reset-password` e `/update-password`. Desde o F-57 há uma
  quarta fase de auth: sessão validada SEM perfil (cadastro Google diferido) fica confinada
  em `/onboarding` até fundar a família ou reivindicar o convite.
- **URL como interface (T-64, 08/09/2026):** **o app não constrói roteador nenhum enquanto o
  portão da sessão não responde** — o `builder:` do `MaterialApp.router` recebe o próprio
  `Router` como `child`, então não devolvê-lo é passar a fase `gate` sem rotear, mostrando o
  splash. É a correção inteira, e ela apagou uma máquina: não existe mais destino lembrado
  (`pendingLocation`, `isRestorable*`). Antes, um roteador que monta sem saber quem está
  perguntando tinha de INVENTAR uma resposta — estacionar em `/splash`, guardar o destino,
  devolvê-lo depois —, e na web isso não fecha: o go_router roda o redirect de topo no máximo
  uma vez por navegação e reporta aquele `/splash` tarde demais, então o destino era gasto por
  uma avaliação que não chegava ao leitor e a barra de endereço passava a mentir. Medido num
  navegador: `/family` → `/splash` → calendário. Agora a URL do navegador continua sendo a URL
  quando o roteamento começa, e a primeira decisão sobre ela já é a certa. Bônus: nenhuma tela
  monta durante o portão, então nenhuma requisição anônima é disparada. `RouteRules` (core)
  segue sendo o espelho puro do S-02; `AppRouteGate` (`lib/routing/`) é ele mais os dois
  portões que precisam de estado (S-11 saída, S-15 consentimento). Uma URL que o app não serve
  responde 404 (`NotFoundScreen`) em vez de ser engolida.
- **Deep links (App Links):** host `web.entrelares.app` (a origem do PWA — o apex é a
  landing), path `/update-password`, `autoVerify`. O `assetlinks.json` de produção já
  listava o prod (`com.entrelares.app`, F-54); o statement do dev
  (`com.entrelares.flutter`, certificado de sideload T-55) entra por PR pareado no
  `entrelares-app-legacy`. Build DEBUG nunca verifica (certificado por máquina) — QA de deep
  link usa o release dev.
- **Entrega entre canais (T-65, 11/09/2026):** quem lê `web.entrelares.app` no Chrome do
  Android e TAMBÉM tem o app instalado ganha um convite para atravessar — e ele existe
  justamente porque **nenhum endereço `https` muda de dono**. Cobrir `/` com App Link não
  conserta o canal web, acaba com ele; App Link por rota interna tem o mesmo defeito em
  miniatura (a MESMA URL, colada ou mandada por e-mail, passaria a abrir o app para todo
  mundo que o tenha). Então o convite usa o scheme que o app já possui, num segundo host ao
  lado do `login-callback`: `<applicationId>://open/<rota>`. A rota viaja no PATH porque o
  embedding do Android monta a rota inicial com `getPath()` + query + fragment — o go_router
  recebe a localização inteira, sem listener nosso, e `…://open/` cai no `initialLocation`
  em vez de num erro. Nada de sessão viaja junto. O banner só aparece quando o NAVEGADOR
  confirma o app no aparelho (`navigator.getInstalledRelatedApps()`), o que exige as três
  fontes que falham caladas — `asset_statements` (app→site, em `res/values/strings.xml`),
  `assetlinks.json` (site→app) e `related_applications` (em `web/manifest.json`): faltando
  qualquer uma a API devolve lista VAZIA, igualzinho a "não instalado". Fora do Chrome
  Android não aparece nada (fail-closed, forma do T-38), e o convite para INSTALAR fica de
  fora de propósito enquanto a Play não for pública — é checkbox do T-59. Regra pura em
  `ChannelHandoffRules`; as três fontes e a ausência de App Link em `/` são presas no
  `web_channel_test`.
- **Recovery:** "Esqueci minha senha" → `resetPasswordForEmail` com `redirectTo` para o
  deep link; o `supabase_flutter` consome os tokens do link e emite `passwordRecovery`,
  que roteia para a tela de nova senha (validação espelhada em `UpdatePasswordRules`).
  ⚠️ Config de ambiente: o projeto Supabase DEV precisa de
  `https://web.entrelares.app/update-password` no allowlist de redirect de auth.
- **S-01 throttling:** espelho `LoginThrottle` (≥3 falhas → falhas×5 s; ≥5 → 60 s),
  estado em prefs locais (o análogo do sessionStorage web) — sobrevive a restart.
- **Login com Google (F-57, 27/08/2026):** botão fail-closed nas telas de auth — só
  aparece quando o `/auth/v1/settings` do projeto diz que o provider existe, então a
  config do console É o interruptor. Cadastro novo tem o perfil DIFERIDO pelo trigger e
  completa em `/onboarding` (papel + família + consentimento S-13, ou claim do convite
  via Edge Function `claim-invitation`, com a migração S-11 preservando a sessão). No
  Android o retorno é por scheme próprio por flavor (`<applicationId>://login-callback`);
  runbook do owner em `supabase/README.md` §9-ter. Sessão sem senha vê o método de login
  no perfil no lugar do cartão de senha — e, **desde o S-21 (10/09/2026), passa pelo gate
  de sudo com um código enviado por e-mail**, que é o que lhe devolveu sair da família,
  promover admin e apagar a própria conta. **Desde a U-45 (10/09/2026) o botão segue as
  diretrizes de marca do *Sign in with Google*:** o "G" oficial como imagem em
  `assets/brand/google-g.png` (1×/2×/3×), superfície/borda/tinta da spec em `GoogleBrand`
  (dentro do `tokens.dart`, o único lugar onde uma cor se escreve), 40 dp de altura, e a
  frase continua sendo nossa — em PT-BR ou inglês, conforme o leitor. Provenência e
  licença do asset em `store/README.md` §2. Coberto por `google_sign_in_button_test`.
- **S-04 inatividade:** espelho `InactivityPolicy` (30 min, poll de 30 s) — pointer-down
  em qualquer lugar reseta; o resume do lifecycle reavalia na hora (tempo em background
  conta, como a aba escondida no web). Expirou → signOut local + banner no login.

## Espelhos e Today at a Glance (lote 1 — PR3)

- **Card Today at a Glance:** port do `TodayCard.razor` no topo do calendário — responsável
  de hoje (efetivo `actual ?? scheduled`), badges 🔄/⏰, próxima troca (janela de 90 dias,
  primeiro dia com responsável efetivo diferente — mesmo scan do web), nudge de convite
  F-31 (admin sozinho na família) e "voltar para hoje" quando navegando outro mês. A
  projeção que no web vivia inline (sem teste) virou regra pura em `today_rules.dart`.
- **Espelho T-41 (settings):** seam `parseIntSetting`/`parseBoolSetting` (semântica .NET
  `TryParse`) + `PublicSettings` com os 10 acessores e fallbacks dos seeds; o fetch
  (`app_settings` público via RLS) está no data source — o primeiro consumidor é o clamp
  de horizonte (lote 2).
- **Espelho F-32 (entitlement):** `computeIsPremium` (premium OR comp F-58 OR trial
  estritamente futuro) + `describePlan` (countdown com piso de 1 dia), fail-closed por
  construção (`Family` null → free); consumo de UI chega com os gates (lotes 2/5).
- **UX feedback:** `showAppSnack` (sucesso/erro/info, um por vez, toque dispensa, duração
  espelhada `3 s + 35 ms/char > 40, teto 8 s`) — primeiro uso: "Salvo com sucesso" no save
  do sheet; banner âmbar de dia passado no sheet (`K.editorPastReadonly`). O gate "toast
  nunca com literal" (port do `NoToast_CarriesALiteralString`) entrou junto, como o
  registro do PR1 prometia.

## Relatórios, analytics e plataforma (lote 6)

- **Hub de Relatórios** com 3 abas (`ReportsScreen`): Resumo · Histórico · PDF. Melhoria
  nativa sobre o web, que navega entre três rotas — cada aba guarda o próprio filtro.
- **Resumo do Período:** cards por membro com Programado/Realizado/Previsto (U-20) e o
  split U-07 (`cedeu · recebeu`). A contagem é UMA função em core (`caregiverStats`),
  chamada também pelo documento F-33 — no web isso era um comentário pedindo que dois
  trechos não divergissem.
- **Histórico de Ajustes:** quatro abas sobre dois registros (`activity_logs` e os
  `account_logs` do S-10), diff campo-a-campo, "carregar mais" incremental e a entrada
  sintética de fim de trial (F-58 QA 2). **F-45** entra aqui: a alteração vinda de um
  workflow nomeia a origem e carrega as duas mensagens F-44; a busca é enriquecimento e
  nunca derruba a timeline. **F-61** (09/09/2026): cada linha diz também, em bloco neutro,
  se o responsável atribuído **ainda não tinha conta** naquele instante e se foi
  **alteração direta pela pessoa administradora** — fatos carimbados pelo trigger em
  `activity_logs.context` (`authorshipLines` em core); linha anterior ao F-61 não diz nada.
- **Relatório em PDF (F-33) — o redesign:** o `print()` do navegador não existe, então o
  documento é montado no aparelho (`pdf`) e entregue pelo sistema (`printing`: share sheet
  ou impressão nativa). Gate F-32 com falha fechada e **upsell neutro** (T-38).
  **Roboto embarcado**: a Helvetica embutida do dart_pdf não tem Unicode e derruba os
  acentos. **F-61**: as mesmas frases de autoria em cada linha do histórico, e a seção
  **2 · Responsáveis e acesso ao aplicativo** antes do histórico — por responsável, uma
  linha datada por fato (`caregiverTimelines`: adicionado ao calendário por quem, convite
  enviado, criou a conta, sem conta até a geração, saiu). Nenhuma frase qualifica conduta;
  o teste de neutralidade dos catálogos garante.
- **Analytics T-37:** POST direto na Events API do Umami (`text/plain`, sem preflight),
  desligado enquanto não houver website id — o flavor **dev vem vazio de propósito**. O
  contrato no-PII é espelho puro (`sanitizeAnalyticsPath`): query e fragmento caem sempre,
  GUID e id numérico viram `:id`. Eventos portados: `signup_started`, `family_created`,
  `invitee_joined`, `invite_sent`, `wizard_completed`, `swap_requested`. Os
  `premium-gate-click` chegaram no lote 5, junto das CTAs que eles medem.
- **Alvo web:** habilitado (tensão 1 — Flutter Web substitui o PWA). `flutter build web`
  entra no `verify.yml` e o run imprime o peso gzip do first-load; a medição de aceite do
  canal (Android mediano/4G) é do owner.

## Premium e billing (lote 5)

- **A seção Premium na Família** roda a máquina de estados do `BillingService` da web
  (`computeBillingUi`): waitlist, oferta, ativa, em atraso, agendada (F-42) e premium sem
  assinatura. O cancelamento pede confirmação e a frase **promete o tempo já pago**; o
  caminho de volta F-42 só aparece para método faturável com cliente no gateway — cartão
  nunca, porque retomar débito automático exige um token que o fluxo hospedado não guarda e
  o servidor recusaria o clique.
- **Dois trilhos, decididos pelo BUILD.** O alvo web usa o rail Asaas (checkout T-39 e Pix
  avulso F-48, abertos no navegador, com `/premium/retorno` fazendo poll até o webhook virar
  o plano). O Android é o canal loja: a política de pagamentos da Play proíbe direcionar
  para compra externa, então ali a oferta é **Play Billing** ou a **nota neutra T-38** —
  nunca um link de checkout.
- **O preço do canal loja é o da Play**, formatado pela loja para o país do comprador. O
  `app_settings` (`billing.price_*`) rege só o rail web. Não existe aritmética de preço no
  trilho da loja de propósito.
- **A nota neutra é o padrão de FALHA, não só o estado desligado**: com
  `billing.store_enabled=false`, sem loja no aparelho, com a consulta de produtos estourando
  ou sem produto publicado, o ramo de loja cai nela. Oferta que a loja não honra é pior que
  oferta nenhuma.
- **O cliente não concede nada.** A compra é alegação: o token vai ao
  `billing-store-verify`, que pergunta à Play Developer API se ela é real e até quando paga.
  O acknowledge à Play só acontece **depois** que o servidor aceita — a Play estorna compra
  não reconhecida em três dias, e reconhecer uma que o servidor recusou deixaria a família
  paga e sem direito.
- **Histórico F-43** preguiçoso na primeira abertura e cacheado depois; some para quem não é
  admin (o RPC recusaria) e para família sem assinatura.
- **Funil T-37 completo** com a dimensão `channel` derivada do mesmo fato de build que
  escolhe o trilho — é ela que separa a coorte da loja da coorte web no Umami.
- **Falta configuração de console (do owner)** para o trilho da loja vender:
  `entrelares-app-legacy/supabase/README.md` §9-bis.

## Fundação visual (U-27)

Antes do cutover, o item **U-27** trocou a camada visual do porte — que trazia 100% das
regras e ~0% do visual — por um sistema de tokens. O que ela estabelece:

- **`lib/theme/tokens.dart` é o ÚNICO lugar onde uma cor pode ser escrita.** Os 79 literais
  `Color(0x…)` que estavam espalhados por 13 arquivos viraram tokens semânticos
  (`accent`/`neutral`/`success`/`warning`/`danger`/`info`, cada um com solid, container,
  onContainer e border). O gate `no_color_literal_test` quebra o build se um literal
  aparecer fora desse arquivo — sem ele, os literais voltam a crescer.
- **Modo escuro entrou JUNTO com os tokens**, seguindo o sistema
  (`themeMode: ThemeMode.system`). Uma chave visível para o usuário é a U-12, não este
  item. O único desvio da tabela de tokens do registro: no escuro o indigo da marca clareia
  para `#818CF8` — `#4F46E5` sobre `#111827` mede 2,3:1 e deixaria todo rótulo acentuado
  ilegível. Mesma matiz, tom legível.
- **`ColorScheme` escrito à mão**, nunca `fromSeed`: semear a partir do indigo tinge todos
  os cinzas e destrói a neutralidade que a identidade compra.
- **Cor nunca é o único vetor.** Cada slot do calendário carrega uma textura
  (`SlotPattern`) além da matiz — os quatro slots ativos do web continuam coloridos
  (paridade), e com a textura o grid é legível sem visão de cores nenhuma. O dia
  **trocado** voltou à convenção do web (âmbar + borda tracejada), o que libera o rosa
  `#E11D48` para voltar a ser um papel.
- **Onze componentes compartilhados** em `lib/widgets/ui/` (barril `ui.dart`): cabeçalho de
  seção, cartão, badge, estado vazio, linha rótulo/valor, cabeçalho de folha, par de ações,
  banner, campo de texto, segmentado e avatar. Cada um substituiu de três a seis cópias que
  já tinham divergido entre telas. Duas convenções ficam gravadas neles: **o par de ações
  põe a confirmação PRIMEIRO** (ordem do Blazor — quem chega no cutover tem essa memória
  muscular) e **todo campo tem rótulo permanente**, que é como a WCAG 1.4.11 é satisfeita
  sem engrossar a borda.
- **Skeletons no lugar dos spinners** onde a forma do que vem é conhecida: o grid do mês, as
  listas de Notificações e de auditoria, os cartões do resumo, Família, Perfil, papéis
  personalizados e o histórico premium. Ficam spinner de propósito: botão em ação (o giro é
  sobre AQUELE toque), barra determinada (o lote e o assistente sabem o progresso — trocar
  por shimmer jogaria informação fora) e espera sem forma conhecida (splash, retorno do
  pagamento). O shimmer é translação horizontal pura, 1500 ms `easeInOutSine`.
- **Tipografia Inter** (SIL OFL, de `google/fonts`), instanciada nos quatro pesos estáticos
  da escala e subsetada para o range `latin` — 438 glifos, ~57 KB cada, ~96 KB gzip no
  conjunto. Regenerável por `tool/subset_inter.py`. O PDF continua com Roboto: relatório é
  peça quase probatória e uma fonte completa não imprime tofu para um nome incomum.

## Versionamento

| Componente | Versão atual |
|---|---|
| `app` | `0.2.31+33` (U-27 PR3 — skeletons e movimento; **U-27 fechado**) |

Trilha do estágio 3: `0.2.0+2` abertura de flavors → `0.2.1+3` T-55 → `0.2.2+4`…`0.2.4+6`
lote 1 → `0.2.5+7`…`0.2.8+10` lote 2 → `0.2.9+11`…`0.2.13+15` lote 3 →
`0.2.14+16`…`0.2.19+21` lote 4 → `0.2.20+22`…`0.2.24+26` lote 6 →
`0.2.25+27`…`0.2.28+30` lote 5. **Os seis lotes estão entregues** — o app está
funcionalmente completo. Depois deles, a fundação visual do cutover: `0.2.29+31`…`0.2.31+33` U-27, **fechado em
20/08/2026**.

Regra herdada do produto: bump em toda mudança funcional entregue ao owner.

## Decisões herdadas (não reabrir aqui)

- Flutter **3.44.7** via FVM; JDK **17**; `minSdk` **26**.
- `applicationId` por flavor (estágio 3): **dev = `com.entrelares.flutter`** — DIFERENTE
  do pacote da Play de propósito, para o APK dev coexistir com o app instalado da loja no
  aparelho do owner — e **prod = `com.entrelares.app`** (mesma assinatura de upload —
  validado no estágio 0; assinatura release por flavor entregue no T-55).
- O cliente ESPELHA, o banco IMPÕE — RLS, RPCs, sudo S-10 e revision/revision_token são a
  segurança; este app é só mais um caller.
- Paridade é piso, não teto: onde o Flutter der melhoria natural (Realtime no lugar do
  poll, swipe entre meses, bottom sheet nativo), a fatia usa — sem mudar regra de servidor.
