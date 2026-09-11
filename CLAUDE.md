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
| The old Blazor client | `entrelares-app`, **archived** since 25/08/2026. Nothing there needs to be read |

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
| GitHub secrets (app) | https://github.com/irineus/entrelares-flutter/settings/secrets/actions | `SUPABASE_SERVICE_ROLE_DEV`, `CLOUDFLARE_API_TOKEN`, … |
| GitHub variables (app) | https://github.com/irineus/entrelares-flutter/settings/variables/actions | public config (`UMAMI_APP_WEBSITE_ID` and friends) |
| GitHub Actions (app) | https://github.com/irineus/entrelares-flutter/actions | `workflow_dispatch`: `run-e2e`, `build-apk`, full run on a docs-only branch |
| GitHub branches (app) | https://github.com/irineus/entrelares-flutter/branches | branch deletion — the cloud session CANNOT do it (403 by design) |
| Landing repo | https://github.com/irineus/entrelares-site | `L-*` items, branch `preview` |
| Cloudflare Pages | https://dash.cloudflare.com/?to=/:account/pages/view/entrelares-web | project `entrelares-web` serves `web.entrelares.app`; the `?to=/:account/…` form resolves the account itself |
| Play Console — the app | https://play.google.com/console/u/0/developers/5188946194088545235/app/4976020657794164634/app-dashboard | package `com.entrelares.app`. Bundle promotion is the owner's, always. Developer `5188946194088545235`, app `4976020657794164634` — keep these, they are the only way to deep-link a Play screen |
| Firebase **prod** | https://console.firebase.google.com/project/entrelares-prod | FCM / web push. Sender `575356979434` |
| Firebase **dev** | https://console.firebase.google.com/project/entrelares-dev | Sender `51960618124` |
| Asaas (prod / sandbox) | https://www.asaas.com · https://sandbox.asaas.com | billing rail. Prod must OPT IN via `ASAAS_API_URL` |
| Umami | https://cloud.umami.is | prod site `6fdd6c5a-4bce-449f-8188-3b7399a859d8` |

⚠️ The **sub-paths inside** these consoles (which tab holds Edge Function secrets, which screen
registers a webhook) move between product redesigns. So a handoff block always pairs the URL with
the **in-UI navigation path** as plan B — and when an exact deep link needs an internal numeric id
this repo does not hold (the Cloudflare account id is the one still missing), say so and ask for it
once instead of guessing a URL that 404s.

## Repository layout

Monorepo: `apps/entrelares_app` (Flutter) + three pure-Dart packages — `packages/entrelares_core`
(the client mirrors of the server rules), `packages/entrelares_db_contracts` (the PostgREST row
shapes) and `packages/entrelares_db_gate` (the database gate). **Nothing under `packages/` may
import Flutter:** the gate has to run under plain `dart test`, and the contracts have to be
importable by both sides. Migrations and Edge Functions in `supabase/`; Play listing and brand
masters in `store/`.

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
# Nesse lane moram os sete ESPELHOS (test/mirrors/, T-56 + F-09 + T-62 + S-21): rótulos
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
# dois lados compilando, e quem não passa é justamente quem não tem senha). Cinco leem
# supabase/functions/_shared/i18n.ts e supabase/migrations — as duplicações que
# existem de propósito porque Deno não chama Dart; o sexto lê um service worker e o
# sétimo uma Edge Function, pela mesma razão em outras linguagens. Um espelho que
# ninguém confere apodrece calado, e é o lane mais barato do run.
cd packages/entrelares_db_contracts && fvm dart analyze --fatal-infos
cd apps/entrelares_app && fvm flutter analyze && fvm flutter test
# The three source gates live in that suite: no_literal_snack_test (catalog strings),
# no_color_literal_test (U-27 — colours only in lib/theme/tokens.dart) e o
# web_channel_test, que prova como FONTE o que só se manifestaria SERVIDO — a CSP,
# o _redirects, o assetlinks, a config Firebase Web e, desde o T-66, o host do
# Sentry dentro de connect-src (sem ele o navegador bloqueia o POST e o canal web
# reporta NADA, em silêncio, porque o reporter engole a própria falha por contrato)
# mais o espelho do watcher pré-Flutter do index.html.
cd apps/entrelares_app && fvm flutter build apk --debug --flavor dev --split-per-abi
# Canal web: os dois flags NÃO são opcionais — sem o define o build aponta para o
# banco de QA, e sem o --no-web-resources-cdn o CanvasKit vem do gstatic.
cd apps/entrelares_app && fvm flutter build web --release --no-web-resources-cdn --dart-define=APP_ENV=prod
# O DEPLOY faz três coisas a mais que este comando local (T-66, runbook §13.6):
# compila com --source-maps, sobe os mapas para o Sentry numa release nomeada
# `entrelares-app@<versão do pubspec>` — a mesma string que o cliente manda, senão
# mapas e eventos nunca se encontram — e APAGA todo .map antes de publicar, porque
# um mapa servido da nossa origem entrega o fonte Dart inteiro a quem pedir.
# Gate de banco (279 testes de RLS/RPC/trigger contra o projeto dev), Dart puro
# desde o PR 16 do T-56. Exige a service_role do DEV — nunca a de produção. Sem
# ela a suíte aborta com instruções em vez de rodar pela metade.
cd packages/entrelares_db_gate && fvm dart analyze --fatal-infos
cd packages/entrelares_db_gate && E2E_SUPABASE_SERVICE_ROLE_KEY=<chave dev> fvm dart test
# Gate de fluxo na web: os mesmos arquivos integration_test/ num Chrome headless,
# MAIS deep_link_test — o único web por construção (T-64: uma entrada fria numa
# URL interna só se comporta mal onde o navegador entrega o endereço ao app).
# Exige chromedriver no PATH (`chromedriver --port=4444 &` antes).
cd apps/entrelares_app && fvm flutter drive --driver=test_driver/integration_test.dart   --target=integration_test/swap_workflow_test.dart -d web-server --browser-name=chrome --headless   --dart-define=E2E_SUPABASE_SERVICE_ROLE_KEY=<chave dev>
```
⚠️ **Uma mudança só de markdown NÃO roda CI nenhum** (`paths-ignore: ['**/*.md']`,
29/08/2026). A economia não são os três minutos do `verify`: são o `db-gate`, que segura
um grupo de concorrência do REPOSITÓRIO INTEIRO — um PR de docs nessa fila é o que faz um
terceiro pretendente ser despejado —, e o `web-e2e`, que cria família descartável no
projeto dev compartilhado para não provar nada sobre um parágrafo. Duas premissas
sustentam isso e as duas são GUARDADAS em `web_channel_test.dart`: nenhuma suíte lê um
`.md` (se alguma passar a ler, o filtro a transformaria num teste que para de rodar
justamente para as mudanças que ela vigia — o verde vazio do T-58), e nada sob
`apps/entrelares_app/web/` é markdown (tudo ali é copiado verbatim para o build). Para
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
Lane E2E (aberta no lote 3): `apps/entrelares_app/integration_test/` — app real em
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
