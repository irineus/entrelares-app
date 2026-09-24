# CLAUDE.md — Project context for Claude Code

**The Entrelares product app**, in Flutter/Dart, on **both channels**: the Play package
`com.entrelares.app` carries this bundle, and `web.entrelares.app` is served from here by the
Cloudflare Pages project `entrelares-web`. **A merge to `main` reaches real users** — there is no
QA branch and no rollback.

## Read these before doing anything (T-63, 07/09/2026)

1. **This file**, for how to build, test and lay the repo out — that is all it carries now.
2. The Notion page **[Entrelares — Decisões vigentes](https://app.notion.com/p/3d42f3f4b9b2819db0d8c845b7aa1ae5)**,
   sections **1 to 6**. It holds the locked decisions, the product invariants, the security rules
   and the hard-won gotchas. **In any conflict with a document in this repository, the Notion page
   wins** — it is written at the moment of the decision; a file can lag. If the divergence matters,
   say so and fix the file in the same delivery.
3. Only then execute. For "próxima tarefa" / "próximo item" / "concluí esse item" / "status do
   board", use the skill **`next-item`** (`.claude/skills/next-item/SKILL.md`).

**Do NOT read at start-up**, on purpose:

- the **chronological log** — it lives in the sub-page **📜 Decision history**, and is consulted
  when the task asks for it (tracing an item, a document or an old defect);
- the **detail behind each rule** — reasoning, measurements and counter-proofs live in **six domain
  sub-pages** of Decisões vigentes. Open the one for the domain you are touching, and only that one.

Sections 2 and 3 of the mother page hold the **enunciado** of each rule plus the concrete trap it
already cost, with a ceiling of **6 lines per rule**. Anything longer belongs in a domain sub-page.

If the Notion MCP connector is not available in the session, **say so before proceeding** — the
board and the decisions live there, and guessing an item's status is the exact defect this
structure exists to prevent.

## Identifiers

| What | Where |
|---|---|
| Board (data source) | `109b1b02-5b6b-48ef-b3b6-990374a3d10f` — database *"Backlog"* under [Entrelares — Backlog & Roadmap](https://app.notion.com/p/3ae2f3f4b9b28169acd9e642ad4760aa) |
| Decisões vigentes | Notion page `3d42f3f4-b9b2-819d-b0d8-c845b7aa1ae5` |
| 📜 Decision history | Notion page `3d42f3f4-b9b2-817d-9681-d2e3a47f277d` |
| Product app + backlog + migrations + DB gate + Play listing | this repo, branch **`main`** (= production) |
| Landing (`L-*` items) | `entrelares-site`, branch **`preview`** |
| The old Blazor client | `entrelares-app-legacy`, **archived** since 25/08/2026. Nothing there needs to be read |

Do not confuse this board with **Gestão IM360** (`e50abe7f-1688-402a-96b5-c6049b24ce82`) or
**Desmalha** (`d50a2925-fb74-4f67-b0db-af03ef41d1b4`). Never touch them from this repository.

### Consoles — where an OWNER-ONLY action actually happens

Any delivery that needs a click the owner alone can make gets a **handoff block** written as
`~/.claude/CLAUDE.md` ("Handoff de ação manual") prescribes — what, where (clickable URL), when, the
literal values, how to verify, and what happens next. This table exists so the "where" is a **real**
URL with the ids already in it, never `https://<console>` with a placeholder.

| Console | Direct URL | Note |
|---|---|---|
| Supabase **prod** | https://supabase.com/dashboard/project/jptqbwfziyzlhlmoekzu | ref `jptqbwfziyzlhlmoekzu`. **A merge reaches real users from here** |
| Supabase **dev/QA** | https://supabase.com/dashboard/project/buroanotfjcgvbfmacuh | ref `buroanotfjcgvbfmacuh`. The DB gate and the E2E lane run against THIS one |
| GitHub secrets (app) | https://github.com/irineus/entrelares-app/settings/secrets/actions | `SUPABASE_SERVICE_ROLE_DEV`, `CLOUDFLARE_API_TOKEN`, … |
| GitHub Environments (app) | https://github.com/irineus/entrelares-app/settings/environments | T-79: `play-internal` (deploy from `main` only; `PLAY_RELEASE_SERVICE_ACCOUNT` + the four `ANDROID_UPLOAD_*` secrets) and `play-production` (deploy from `main` only, required reviewer = owner; `PLAY_RELEASE_SERVICE_ACCOUNT`). The branch rule is what keeps a same-repo PR branch of this PUBLIC repo from reading the upload key |
| GitHub variables (app) | https://github.com/irineus/entrelares-app/settings/variables/actions | public config (`UMAMI_APP_WEBSITE_ID` and friends) |
| GitHub Actions (app) | https://github.com/irineus/entrelares-app/actions | **`play-promote`** (T-79): `promote` Internal → Production at a fraction, `rollout`, `halt`, `dry_run` — the run waits for the owner's approval on the `play-production` Environment, and `promote` refuses a versionCode without `store/release-notes/<code>/{pt-BR,en-US}.txt`. `verify`'s `workflow_dispatch`: `run-e2e`, `build-apk`, full run on a docs-only branch — and, ON `main`, **republish HEAD** through the same gates → `db-prod` → `deploy-web` (since 15/09/2026: the squash-merge of #187 created no run at all, and the publish jobs used to accept only `push`). A merge with no run in `gh run list --branch main` after ~5 min is that case: dispatch `verify` on `main` |
| GitHub branches (app) | https://github.com/irineus/entrelares-app/branches | branch deletion — the cloud session CANNOT do it (403 by design) |
| Landing repo | https://github.com/irineus/entrelares-site | `L-*` items, branch `preview` |
| Cloudflare Pages | https://dash.cloudflare.com/1185ad84960bdaf12e52096fe8df0dc9/pages/view/entrelares-web | project `entrelares-web` serves `web.entrelares.app`. Same account as the landing's workers — confirmed by the owner opening this exact link on 12/09/2026 (L-26) |
| Cloudflare Pages — **QA** | https://dash.cloudflare.com/1185ad84960bdaf12e52096fe8df0dc9/pages/view/entrelares-web-qa | project `entrelares-web-qa` (T-79), created by the first `qa-web`/`qa-preview` run: the DEV build (no `APP_ENV`), `main` at `qa.entrelares.app` (the custom domain, attached by the owner) and each PR at `pr-<N>.entrelares-web-qa.pages.dev`. `qa_channel_test` refuses a QA deploy to `entrelares-web` or with `APP_ENV=prod`. `Env.dev.webOrigin` is this host, so every link a dev build hands out opens here. The dev Supabase project's redirect allowlist must carry it |
| Firebase App Distribution — dev | https://console.firebase.google.com/project/entrelares-dev/appdistribution | T-79: the `qa-preview` job sends each PR's dev APK (`com.entrelares.flutter`) to the tester group alias `qa`, with the `FIREBASE_APP_DISTRIBUTION_SERVICE_ACCOUNT` repo secret |
| Cloudflare Web Analytics — site `entrelares.app` | https://dash.cloudflare.com/1185ad84960bdaf12e52096fe8df0dc9/web-analytics/edit/385f3763880b460ea8d275547d52a2c5 | ONE zone-level site covers BOTH `entrelares.app` and `web.entrelares.app`. RUM is **Disabled** since 14/09/2026 (T-73): with automatic setup on, the edge injected a beacon the app's CSP blocks and the landing (no CSP) ran. Re-enabling it turns `deploy-web` red at *Refuse a served script the CSP would block*. Plan B: Analytics → Web analytics → entrelares.app → Manage site |
| Cloudflare Email Routing — `entrelares.app` | https://dash.cloudflare.com/1185ad84960bdaf12e52096fe8df0dc9/email-service/routing/ee630874f02bd5f2ed79d97b636fe177/routing-rules (confirmed in the owner's browser, 21/09/2026, F-68) | zone `ee630874f02bd5f2ed79d97b636fe177`. MX `route{1,2,3}.mx.cloudflare.net`. Rules `contato@`, `suporte@`, `privacidade@` and the catch-all → `irineus@gmail.com` (Gmail labels *Entrelares/…*). `suporte@` is where `send-support-request` delivers; a rule turned off makes the form's messages vanish with the function answering 200. Plan B: Account home → Compute → Email Service → Email Routing → Routing rules |
| Play Console — the app | https://play.google.com/console/u/0/developers/5188946194088545235/app/4976020657794164634/app-dashboard | package `com.entrelares.app`. Since T-79 (22/09/2026) no bundle is uploaded by hand: a merge that bumps the version lands on **Internal testing** by itself (`play-internal` job), and **Production** is the owner's *Approve* on the `play-promote` run (Environment `play-production`). Developer `5188946194088545235`, app `4976020657794164634` — keep these, they are the only way to deep-link a Play screen |
| Firebase **prod** | https://console.firebase.google.com/project/entrelares-prod | FCM / web push. Sender `575356979434` |
| Firebase **dev** | https://console.firebase.google.com/project/entrelares-dev | Sender `51960618124` |
| Asaas (prod / sandbox) | https://www.asaas.com · https://sandbox.asaas.com | billing rail. Prod must OPT IN via `ASAAS_API_URL` |
| Umami — the **app**'s site | https://cloud.umami.is/analytics/us/websites/6fdd6c5a-4bce-449f-8188-3b7399a859d8 (same URL shape as the landing's: `/events` + `?date=range%3A<startMs>%3A<endMs>` — confirmed in the owner's browser, 15/09/2026, L-13) | login **`irineus@gmail.com`**. Website `6fdd6c5a-4bce-449f-8188-3b7399a859d8` = `web.entrelares.app`, the id `env.dart` sends. **Its first event is 02/08/2026** — read a zero as "since then" (L-13). **Hobby tier, no API** ("API access requires a Pro plan", verified 12/09/2026): every reading is the owner's dashboard — ask for a screenshot, never for an API key (L-26) |
| Umami — the **landing**'s site | https://cloud.umami.is/analytics/us/websites/8b182992-68ce-4f2e-abb9-e798c33e48d8 (append `/events` for the Events tab; `?date=range%3A<startMs>%3A<endMs>` pre-fills a window — confirmed in the owner's browser, 14/09/2026, L-18) | login **`irineus.adp@gmail.com`** — a SECOND account, because the free tier allowed one website per account when T-37/L-01 created them (July 2026). Website `8b182992-68ce-4f2e-abb9-e798c33e48d8` = `entrelares.app`. Two accounts, one provider: L-25 lost a whole round trip because no document said which login held which site (L-26) |
| Google Search Console | https://search.google.com/search-console/performance/search-analytics?resource_id=sc-domain%3Aentrelares.app (swap the path for `/sitemaps`, `/index` … — the `resource_id` is the part that selects the property; both confirmed in the owner's browser, 15/09/2026, L-29) | login **`irineus@gmail.com`**. ONE **Domain property** `sc-domain:entrelares.app` covers the apex, `www.`, `web.` and `preview.`; a second one, `guardacompartilhada.com`, is KEPT on purpose (it shows the old URLs leaving the index after the 301s). Both already existed before L-29 said "never configured" — nobody had READ them. **Performance data starts 27/08/2026**; the sitemap was malformed XML until 15/09/2026 ("Sitemap is HTML", 0 pages), so read everything before that date as "sitemap never read". No API credential enters the repo or the chat: screenshots (L-29) |
| Bing Webmaster Tools | https://www.bing.com/webmasters/sitemaps?siteUrl=https://entrelares.app/ (confirmed in the owner's browser, 15/09/2026, L-29) | login **Google → `irineus@gmail.com`**. Site `https://entrelares.app/`, imported from Search Console (the import verifies ownership, no DNS record) — but the import did NOT bring the sitemap; it was submitted by hand. Bing's index also feeds DuckDuckGo, which is how L-29 saw `web.entrelares.app` competing for the brand |

⚠️ The **sub-paths inside** these consoles (which tab holds Edge Function secrets, which screen
registers a webhook) move between product redesigns. So a handoff block always pairs the URL with
the **in-UI navigation path** as plan B — and when an exact deep link needs an internal numeric id
this repo does not hold, say so and ask for it once instead of guessing a URL that 404s. The
Cloudflare account id is **`1185ad84960bdaf12e52096fe8df0dc9`** — declared as `account_id` in the
landing's `wrangler.jsonc`, confirmed by L-25 for the landing's two workers and KV namespaces and
by L-26 for the Pages project `entrelares-web` (nothing in this repo proves the latter — the
`deploy-web` job reads the id from the `CLOUDFLARE_ACCOUNT_ID` secret — so it was the owner
opening the direct link, 12/09/2026).

## Repository layout

Monorepo: `app` (Flutter) + three pure-Dart packages — `packages/entrelares_core` (the
client mirrors of the server rules), `packages/entrelares_db_contracts` (the PostgREST row
shapes) and `packages/entrelares_db_gate` (the database gate). **Nothing under `packages/` may
import Flutter:** the gate has to run under plain `dart test`, and the contracts have to be
importable by both sides. Migrations and Edge Functions in `supabase/`; Play listing and brand
masters in `store/`.

**The names inside `docs/` and `backlog/` are the names of their own time (T-69, 11/09/2026).**
This repo was `entrelares-flutter` and the app lived in `apps/entrelares_app`; the archived Blazor
client was `entrelares-app`. Those documents are frozen history and were deliberately NOT rewritten
— inside them `entrelares-app` still means the Blazor repo, today `entrelares-app-legacy`, and a
line like *"`entrelares-flutter` #51 + `entrelares-app` #303"* names two different repositories.
Live pointers — workflows, scripts, this file — carry today's names; dated prose carries its own.

`backlog/` is **frozen history** since T-63: `archive/` holds the records of completed items and
the four category files are tombstones. **The card is the record now** — see
[`backlog/README.md`](backlog/README.md), which keeps the forward plan's rationale and the ops
chores that are not backlog items.

## Language conventions

- **UI text, notifications, e-mails: PT-BR.** Code, comments, docs, file names, titles and backlog
  cards: **English**.
- **Commit messages: PT-BR**, conventional-commit style (`feat(calendario): …`).
- **Finding/sub-item IDs must never start with a backlog prefix** (`F-`/`U-`/`T-`/`S-`/`L-` + two
  digits). The T-32 findings were `F-32-1…5` and every ID reader matched them as the feature
  **F-32**, mis-attributing effort and commits; they are `T32-A1…A5` now.
- The `Backlog: <ID>` commit trailer was **dropped with its only reader** (T-63, 07/09/2026).

## Build & test
```
cd packages/entrelares_core && fvm dart analyze --fatal-infos && fvm dart test
# Nesse lane moram os dez ESPELHOS (test/mirrors/, T-56 + F-09 + T-62 + S-21 + F-60 + F-68 + T-78): rótulos
# de papel em inglês, formato de data dos e-mails, a chave `lang` do redirect de reset,
# a cobertura de `params` de todo writer de notificação, o catálogo de push
# (F-09: o texto do push é montado no servidor, então `_shared/push.ts` duplica de
# propósito um subconjunto do catálogo Dart — o espelho compara string por string nas
# duas línguas e exige que o filtro do trigger e o `PUSH_TYPES` nomeiem os mesmos tipos),
# e o roteamento do toque na web (T-62: o clique numa notificação é tratado pelo SERVICE
# WORKER, que não chama Dart, então `firebase-messaging-sw.js` reespelha `PushRouting` —
# o espelho compara os dois lados para TODO tipo pushável, porque errar aqui abre a aba
# errada sem erro nenhum), e os números do gate de sudo (S-21: 6 dígitos, 10 min, 60 s
# entre pedidos e a própria janela de elevação moram em `elevate/index.ts`, e o espelho
# lê ESSE arquivo — errar aqui recusa no cliente o código que o e-mail mandou, com os
# dois lados compilando, e quem não passa é justamente quem não tem senha), e o prazo
# da auto-aprovação (F-60: a MESMA promessa é dita em quatro lugares — catálogo Dart,
# push, e-mail e a frase que a RPC GRAVA — e a do e-mail não tinha espelho nenhum, então
# `_shared/i18n.ts` podia seguir prometendo 24h enquanto o app dizia o instante, as duas
# frases bem formadas e o build calado; o espelho lê os TRÊS lados fora do Dart, o corpo
# VIVO de `auto_approve_expired` inclusive, e recusa janela citada numa FRASE — o
# `interval '48 hours'` ao lado dela é a regra, que o item não tocou), e os números da porta
# de suporte (F-68: tamanho da mensagem, os limites por hora/dia e as cinco categorias moram
# em `send-support-request/index.ts`; o espelho lê esse arquivo e o CHECK da migração —
# errar aqui recusa depois do Enviar justamente quem já estava travado; desde o T-83 os
# limites e o tamanho máximo são chaves `support.*` do app_settings, as constantes são só o
# fallback e o espelho as prende ao seed da migração), e os canais e a
# retenção da atividade por membro (T-78: `member_activity_days` aceita android/web/
# web-installed no CHECK e na guarda de `touch_activity`, e o purge guarda 400 dias — o prazo
# da §11 da política; o app chama fire-and-forget, então um canal recusado sumiria dos dados
# sem sintoma). Cinco leem
# supabase/functions/_shared/i18n.ts e supabase/migrations — as duplicações que
# existem de propósito porque Deno não chama Dart; o sexto lê um service worker, o
# sétimo uma Edge Function, o oitavo um catálogo de e-mail ao lado de uma migração e o
# nono uma Edge Function ao lado de uma migração e o décimo uma migração só,
# pela mesma razão em outras linguagens. Um espelho que
# ninguém confere apodrece calado, e é o lane mais barato do run.
# Também no lane core, desde o T-78 (23/09/2026), analytics_catalog_test: todo evento que o
# app manda ao Umami está em AnalyticsEvents (core), com as chaves de prop que declara; o
# transporte descarta chave não declarada e valor que não é token curto, e o teste prende a
# LISTA de nomes — renomear um evento encerra uma série (o degrau do U-35). No lane do app,
# analytics_t78_test recusa nome de evento escrito como literal num call site.
# Fora de mirrors/, no mesmo lane, a guarda do U-26 (email_layout_guard_test): todo e-mail
# sai de supabase/functions/_shared/email_layout.ts, e a suíte lê esse arquivo e os quatro
# send-* (o send-support-request desde o F-68): estilo só na tabela literal `S`, `color` E `background-color` em toda entrada,
# contraste AA, nenhuma superfície escura e nenhum `style=` num remetente. O
# no_color_literal_test só lê o lib/ do Flutter; sem esta, um #212529 voltaria calado.
# Também fora de mirrors/, desde o U-34 (18/09/2026), vocabulary_test lê os DOIS catálogos
# como conjunto: a aba do shell e o título da tela são a mesma palavra, nenhuma aba interna
# repete rótulo de outra ("Histórico" é só a trilha de auditoria; a de Notificações é
# "Todas"), o que o sistema envia é "notificação"/"notification" — e "alert" não nomeia
# push —, e scheduled_parent é "planejado", nunca "agendado".
# Desde o F-52 (18/09/2026) a reserva de "aviso" foi GASTA e a asserção inverteu: a palavra
# é um ENDEREÇO — as chaves `app.notice.*` e `notifRender.dayNotice.*`, e mais nenhuma (o
# sobrevivente é o tooltip que fecha uma faixa). Um segundo teste prende a metade que
# apodrece calada: a superfície do F-52 tem de continuar se chamando aviso, senão o
# glossário aponta para o vazio e o primeiro teste fica verde sobre nada.
# Desde o F-67 (21/09/2026) "relato" tem a mesma forma: é o relato do dia (o que aconteceu
# num dia que já passou, anexado e nunca editado), endereço `app.dayAccount.*` e
# `notifRender.*dayAccount*`, e a superfície tem de continuar dizendo-o; "relatório" (o PDF)
# é outra palavra e segue livre. No mesmo item a regex do "agendado" deixou de ter dois
# bytes de backspace no lugar do \b — por meses ela não casava com nada.
# String nova com uma dessas palavras derruba o lane core; as exceções são presas pelo nome
# da chave. O glossário do produto mora na subpágina Design system and UX.
# Desde o U-57 (23/09/2026), settings_copy_guard_test: toda frase que AFIRMA o valor de uma
# chave do app_settings (free_caregivers, calendar_months_free/premium) usa placeholder e não
# carrega o seed escrito (nem "dois"/"two"), e nenhum catálogo conta meses ou responsáveis com
# dígito digitado — senão uma edição no console faz o servidor recusar num número enquanto a
# tela promete o antigo. Frase nova que afirma um desses números entra no registro do teste.
cd packages/entrelares_db_contracts && fvm dart analyze --fatal-infos
cd app && fvm flutter analyze && fvm flutter test
# The four source gates live in that suite: no_literal_snack_test (catalog strings),
# no_color_literal_test (U-27 — colours only in lib/theme/tokens.dart),
# no_emoji_in_ui_test (U-31 — nenhum emoji em lib/, nos dois catálogos nem em
# supabase/functions/**/*.ts: push, e-mail e cabeçalho do layout; marca é Icon
# vetorial no call site, e o emoji de papel personalizado, dado da família, fica
# de fora por não morar em nenhum desses caminhos) e o
# web_channel_test, que prova como FONTE o que só se manifestaria SERVIDO — a CSP,
# o _redirects, o assetlinks, a config Firebase Web e, desde o T-66, o host do
# Sentry dentro de connect-src (sem ele o navegador bloqueia o POST e o canal web
# reporta NADA, em silêncio, porque o reporter engole a própria falha por contrato),
# desde o T-72 toda imagem que o manifest.json nomeia (host coberto pelo img-src,
# ou arquivo que existe em web/ — a mesma família de defeito, noutra diretiva)
# mais o espelho do watcher pré-Flutter do index.html e, desde o T-58, a prova de
# execução do web-e2e (driver próprio, toda suíte reporta, contagens espelhadas).
# Desde o U-32 (17/09/2026) a mesma suíte carrega accessibility_guidelines_test:
# toda tela num celular de 360 dp, nos DOIS temas, com a Inter real — alvo de
# toque (48 dp; 44 dp na grade do mês, decisão do U-28; 40 dp no botão do Google,
# U-45), rótulo em todo nó tocável (o que o TalkBack lê como "botão" quando
# falta), e contraste lido dos TOKENS, não amostrado de pixels: o
# textContrastGuideline do SDK mediu 2,60 num par que os tokens põem em 4,83 e
# 1,00 em todo emoji que a fonte do host não desenha. Cor nova em tokens.dart
# passa por esse gate; o que a suíte NÃO mede — ordem de leitura, live region,
# como uma dica soa — é a passada com leitor de tela em aparelho, do owner.
# Desde o U-48 (17/09/2026) cada cena roda uma TERCEIRA vez, no claro a 1,3× —
# a escala "grande" dos dois sistemas — e um overflow aí é vermelho: "toda tela
# segura a 1,3× em 360 dp" é fato da suíte, não esperança. No mesmo item, o
# quinto gate de fonte, no_tiny_text_test: nenhum fontSize < 11 em lib/ (o PDF,
# Roboto em pontos no papel, é o único arquivo fora da varredura), o tema nomeado
# nunca abaixo de 11, e as TRÊS exceções que o owner manteve em 17/09 presas pelo
# nome — a célula compacta do calendário (inicial 9, horário 9, medida do U-28),
# só a linha do horário no degrau confortável quando "12:00 PM" não cabe (U-39)
# e as iniciais do AppAvatar r14 (0,7 × raio = 9,8) — para que uma quarta não
# entre calada e nenhuma das três desça. E o FittedBox.scaleDown deixou de existir
# em lib/: um texto de uma linha que precisa caber usa AppShrinkToFit (widgets/ui/),
# que encolhe até 0,85× e, abaixo disso, entrega ao filho a largura do piso — Text
# faz reticência, Wrap quebra a linha — em vez de desfazer a fonte que o leitor pediu.
# Desde o U-48 (17/09/2026, parte 2) o canal web tem modelo de entrada:
# web_input_u48_test prende ←/→ com a barra do mês focada e PageUp/PageDown de
# qualquer lugar do calendário (a tela toma o foco ao montar, num nó que o Tab
# pula), Enter/Espaço abrindo a célula focada, Escape fechando a sheet, e o hover
# da célula pintado DENTRO da caixa tingida (Material transparente entre o fill e
# o InkWell — antes o ripple caía no Material do Scaffold, embaixo do fill). O
# título do documento por rota é regra pura no core (DocumentTitle, com teste):
# "Calendário · Entrelares", prefixo [Dev] na frente, e os *PageTitle herdados
# do Blazor perdem o " - Entrelares" para toda rota ler numa forma só.
cd app && fvm flutter build apk --debug --flavor dev --split-per-abi
# Canal web: os dois flags NÃO são opcionais — sem o define o build aponta para o
# banco de QA, e sem o --no-web-resources-cdn o CanvasKit vem do gstatic.
cd app && fvm flutter build web --release --no-web-resources-cdn --dart-define=APP_ENV=prod
# O DEPLOY faz SEIS coisas a mais que este comando local. Três são do T-66
# (runbook §13.6), duas do T-68 (runbook §14) e uma do T-73 (runbook §14.7):
# depois da prova, lê a página servida pedindo HTML como um navegador pede e
# recusa todo script externo de host que o `script-src` SERVIDO bloqueia — a
# borda do Cloudflare injetava um beacon de Web Analytics que o web_channel_test,
# que só lê fonte, nunca teria como ver. As duas do T-68: carimba `build/web/build-id.txt`
# com o `$GITHUB_SHA` logo antes do upload e, DEPOIS de publicar, lê esse
# arquivo de volta de `web.entrelares.app` e compara o corpo — porque o código
# de saída 0 do `wrangler` não é prova, e porque `_redirects` responde 200 com o
# index.html para um arquivo que NÃO existe (um `curl -f` passaria no vazio).
# Se a publicação não se provar, o job `ops-alert` alarma no Sentry de produção
# e abre uma issue; `main` vermelha nunca mais fica só no e-mail do GitHub.
# As três do T-66 (runbook §13.6):
# compila com --source-maps, sobe os mapas para o Sentry numa release nomeada
# `entrelares-app@<versão do pubspec>` — a mesma string que o cliente manda, senão
# mapas e eventos nunca se encontram — e APAGA todo .map antes de publicar, porque
# um mapa servido da nossa origem entrega o fonte Dart inteiro a quem pedir.
# Gate de banco (392 testes de RLS/RPC/trigger contra o projeto dev, 24/09/2026), Dart puro
# desde o PR 16 do T-56. Exige a service_role do DEV — nunca a de produção. Sem
# ela a suíte aborta com instruções em vez de rodar pela metade.
cd packages/entrelares_db_gate && fvm dart analyze --fatal-infos
cd packages/entrelares_db_gate && E2E_SUPABASE_SERVICE_ROLE_KEY=<chave dev> fvm dart test
# Gate de fluxo na web: os mesmos arquivos integration_test/ num Chrome headless,
# MAIS deep_link_test — o único web por construção (T-64: uma entrada fria numa
# URL interna só se comporta mal onde o navegador entrega o endereço ao app).
# Exige chromedriver no PATH (`chromedriver --port=4444 &` antes).
cd app && fvm flutter drive --driver=test_driver/integration_test.dart   --target=integration_test/swap_workflow_test.dart -d web-server --browser-name=chrome --headless   --dart-define=E2E_SUPABASE_SERVICE_ROLE_KEY=<chave dev>
# T-58 (12/09/2026): esse gate tem de PROVAR que rodou. Na web o `flutter drive`
# imprime "All tests passed." e sai 0 também com ZERO testes (um setUpAll que
# estoura — foi assim por cinco dias, e reproduz-se aqui rodando sem a chave), então
# cada suíte reporta os testes que chegaram ao fim (integration_test/e2e_proof.dart,
# `proveExecution(binding)` antes do primeiro testWidgets), o driver é NOSSO
# (test_driver/integration_test.dart, veredito em test_driver/e2e_proof.dart) e
# recusa run sem relatório, com zero testes ou com contagem diferente de
# E2E_EXPECTED_TESTS — que o verify.yml fixa por alvo e por pack (`alvo:p0:full`) e o
# web_channel_test espelha contra as declarações `testWidgets(` de cada arquivo:
# teste novo = bump no verify.yml na MESMA entrega, ou o lane barato fica vermelho.
# Sem a variável (rodada à mão, como acima) vale "pelo menos um". A prova fica em
# app/build/e2e_proof.json e o sumário do run lista os testes pelo nome. Teste "só
# full" usa `skip: pack == 'p0'`, nunca `return` na primeira linha — um corpo que
# retorna conta como executado. Runbook §15.
# T-71 (13/09/2026): o setUpAll é registrado por `provedSetUpAll(binding, …)`, nunca
# cru (o web_channel_test recusa): a janela dele (início/fim UTC) entra no relatório em
# todo run e, quando estoura, a exceção e a pilha vão junto — `-d web-server` não tem
# DWDS, então é o ÚNICO caminho pelo qual a causa de um "não reportou NADA" chega ao
# log do job. Um vermelho no setUpAll se lê no veredito e em app/build/e2e_proof.json;
# a janela sai no sumário, por alvo, para cruzar com a do db-gate (H1).
```
⚠️ **Uma mudança só de markdown NÃO roda CI nenhum** (`paths-ignore: ['**/*.md']`,
29/08/2026). A economia não são os três minutos do `verify`: são o `db-gate`, que segura
um grupo de concorrência do REPOSITÓRIO INTEIRO — um PR de docs nessa fila é o que faz um
terceiro pretendente ser despejado —, e o `web-e2e`, que cria família descartável no
projeto dev compartilhado para não provar nada sobre um parágrafo. Duas premissas
sustentam isso e as duas são GUARDADAS em `web_channel_test.dart`: nenhuma suíte lê um
`.md` (se alguma passar a ler, o filtro a transformaria num teste que para de rodar
justamente para as mudanças que ela vigia — o verde vazio do T-58), e nada sob
`app/web/` é markdown (tudo ali é copiado verbatim para o build). Para
forçar um run completo num branch só de docs: `workflow_dispatch`, que não tem filtro.

⚠️ O lane core do `verify.yml` roda **`dart analyze --fatal-infos`**, não `dart analyze`:
uma info (ex.: `unnecessary_brace_in_string_interps` num `reason:` de teste) derruba o job
— e como esse é o PRIMEIRO passo, os lanes de app e web nem chegam a rodar. Rodar o
comando acima antes do push é o que separa um push verde de um `main` vermelho (lote 5,
20/08/2026).

**Alvo web (lote 6):** habilitado em 19/08/2026 — Flutter Web SUBSTITUI o PWA (tensão 1)
e o `verify.yml` compila o web em todo push, imprimindo o peso gzip do first-load no
summary do run. O aceite do CANAL — medição real em Android mediano/4G contra o PWA —
foi **concedido pelo owner em 23/08/2026**.
Lane E2E (aberta no lote 3): `app/integration_test/` — app real em
emulador contra o projeto dev, família descartável (`E2E-<runId>`, `@resend.dev`,
`purge_e2e_family` no teardown). Fora do gate por custo de minutos: agendada
(06:10 UTC) + `workflow_dispatch` (`run-e2e`, `e2e-pack` p0/full). A service_role do
dev chega só por `--dart-define` a partir do secret `SUPABASE_SERVICE_ROLE_DEV`.
Cloud sessions: `bash tool/setup_env.sh && source tool/env` (hosts needed:
`storage.googleapis.com`, `dl.google.com`, `pub.dev` — all reachable in this product's
cloud policy; if one is blocked, STOP and report the domain, no unofficial mirrors).

## Rules

The product's standing rules — architecture, domain invariants, security, billing, compliance and
the working agreement — live in **[Entrelares — Decisões vigentes](https://app.notion.com/p/3d42f3f4b9b2819db0d8c845b7aa1ae5)**,
sections 1 to 6. Two that bear repeating here because they bite at the keyboard:

1. **Secrets never enter the repo.** `env.dart` carries only PUBLIC client config; the anon key has
   zero privilege by construction (T-44).
2. **Flutter version changes only by explicit owner decision recorded on the board.**
