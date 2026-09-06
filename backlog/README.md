# Improvement Backlog

Tracking of all improvement items for the **Entrelares** application (rebranded from "Guarda Compartilhada" — F-54).
Each item has a defined priority, complexity, and impact to guide implementation order.

> **Status values:** `pending` · `in-progress` · `completed` · `skipped`
> **Priority:** `critical` · `high` · `medium` · `low`
> **Complexity:** `low` · `medium` · `high`
> **Impact:** `low` · `medium` · `high`

## Where things live (changed July 2026)

The **live status board moved to Notion** — database *"Backlog"* under
[Entrelares — Backlog & Roadmap](https://app.notion.com/p/3ae2f3f4b9b28169acd9e642ad4760aa).
It covers BOTH repos (app `F-`/`U-`/`T-`/`S-` + landing `L-`) and is maintained through the Notion
MCP connector, so Claude Code updates it directly. It owns what used to drift here: **status, the
execution order of the pending items, and the effort actually spent** (`Esforço gasto (h)`,
`Início`, `Conclusão`), plus the feature↔story hierarchy (`Item pai` / `Sub-itens`).

**The old Summary Table in this file is gone** — it duplicated 122 rows of status by hand. What
stays in the repo is what belongs next to the code: the **detailed record** of each item and the
**design rationale** below.

| Where | What |
|---|---|
| [Notion → Backlog](https://app.notion.com/p/3ae2f3f4b9b28169acd9e642ad4760aa) | Status, priority/complexity/impact, roadmap order, effort spent, feature→story hierarchy — for both repos |
| [`features.md`](features.md) · [`ui-ux.md`](ui-ux.md) · [`technical.md`](technical.md) · [`security.md`](security.md) | **Pending** items only, with full detail, one `###` entry per item |
| [`archive/`](archive/) | Implementation records of **completed** items, grouped by delivery phase (`phase-1..6.md`, `standalone.md`) — immutable history |
| This file | The forward plan's **rationale** (below): why this order, the per-item caveats, and the ops chores that are not backlog items |

- IDs (`F-`/`U-`/`T-`/`S-` + number) are **stable and never reused**; new items take the next free number of their category. The ID is the join key between the repo and the Notion row.
- When an item is completed: update its `Status` in the entry, enrich it with the implementation record, **move it to the archive file of the current phase**, and **update the Notion row** (status, `Conclusão`, `Esforço gasto (h)`).
- Cross-references between items (e.g. "depends on F-27") use the ID — `grep` finds it regardless of file.


## Roadmap — what's next

> **Phase 6 is CLOSED and Phase 7 is open (03/08/2026, `v1.7.0`).** The minor bump marked the
> paid-launch gate complete — roadmap group 1 has no code and no ops chore left. **Phase 7 =
> "Public Availability & Product Depth"**: the public-availability gate (group 2) plus the
> swap/reports depth block (group 3). **Group 2 emptied on 04/08/2026** — S-16 and T-35 shipped,
> and the owner moved its two ops items (T-36, S-17) to the new group **8 · Início da
> monetização** — so the execution queue now starts at group 3. Items closed from now on take `Fase 7` in Notion and their
> record goes to [`archive/phase-7.md`](archive/phase-7.md). Remember the two axes are
> orthogonal: **`Fase`** is where a delivered item landed, **`Grupo roadmap`** is where a pending
> one is planned — group numbers are stable and are not renumbered when a group empties.

Phases 1–5 (the security/quality/compliance base) and the whole **Phase 6 (Growth, Analytics & Monetization)** feature track are **built**: product analytics (T-37), the co-caregiver invite loop (F-31), the freemium foundation + premium waitlist (F-32), the PDF-report wedge (F-33, "Relatório do histórico em PDF"), all five per-feature gates (F-37/F-38/F-39/F-40, plus the closing **F-41** — custom per-family roles, Aug 2026), the central config table (T-41), **subscription billing (T-39 — Asaas/Pix, v1.6.29–1.6.31)** with the admin payment history (F-43), plus three public-availability items (S-14, T-34 and **S-15 — the legal review, v1.6.34–1.6.39: all 19 findings of the parecer implemented across five deliveries**).

**Production is the FLUTTER app, on both channels, since 23/08/2026** (T-53): the Play package `com.entrelares.app` carries the Flutter bundle and `web.entrelares.app` is served from the `entrelares-flutter` repo. What follows is the **frozen Blazor client's** build history — it ends at `1.8.15`, was published at `legado.entrelares.app` as the documented way back until the 24/08/2026 shutdown (T-56), and it is kept here because it is the record of how the product got where it is. Its last feature release was **v1.8.13** (promoted 20/08/2026 — **F-58**, the platform-operator foundation: the operator role, its own immutable audit trail, the permanent courtesy Premium, the plan transitions written into the family's own account history, and the `admin-update-member-email` support path. It also carries the server half of the redesigned **T-48**, DORMANT behind `billing.store_enabled = false` — the `play` gateway, the unique purchase token and the two store functions — plus the Flutter dev flavour's statement in `assetlinks.json`. Six migrations. This is the promotion that lets the `entrelares-console` prod flavour work at all, and the one that makes the Play Console side of §9-bis possible. Before it, **v1.8.7** (promoted 13/08/2026, the second promotion of that day) — the rebrand's Android half: the Play app `com.entrelares.app` created and its first bundle uploaded to the closed-alpha track, with the **app-signing fingerprint** that only exists after that upload and without which the store-installed app opens with the browser bar; plus the sender cutover finished in code and the Android shell's splash/version fixed before the first upload. No schema change. Before it, **v1.8.4**, earlier the same day — **F-54, the rebrand to Entrelares**: the new name and tagline across every screen, e-mail, report and store listing, the move to `entrelares.app` with the old hosts as permanent 301s, the Emblema Entrelares icon set, the internal code rename `SharedParentalCustody` → `Entrelares`, and the e-mail-sender cutover to `@entrelares.app`. The Play package becomes `com.entrelares.app`, restarting the closed test on a new app. Before it, v1.8.1, 10/08/2026 — the T-38 closing piece: real `assetlinks.json` fingerprints so the Play TWA opens without the browser bar, and the bilingual store listing. Before it, v1.8.0, 07/08/2026 — the minor bump marks the internationalization + first-run milestone: **U-13** the whole app in English, **U-24** dates/times per language, **U-23** first steps + guided tour, plus the 07/08 pre-production QA round that put GoTrue's auth e-mails through our own Send Email Hook and made password recovery work end to end. Before it, `1.7.15` (05/08) — it carries everything Phase 7 accumulated since `1.7.1`: T-35, the group-3 depth block F-44/T-45/F-45/U-20+U-07/F-47, the F-48 monetization set with the promotional price and Pix avulso, and the T-38 Google Play prep; the coupled landing `main` deploy published the same prices, L-14). Before it, `1.7.1` (03/08) had carried **S-16**, the migration off the legacy static keys. The `v1.7.0` minor bump marks the **paid-launch gate complete**: the 03/08 promotion carried the closing freemium gate **F-41** (custom per-family roles), **F-46** (trial credit) and **U-22** (validity dates), so roadmap group 1 has no code left in it. The **billing code** has been in production since `1.6.33` and **charging is LIVE**: the owner ran the go-live checklist and flipped `billing.enabled=true` on **29/07/2026**, so prod already carries real subscriptions and webhook events. The 01/08 promotion had already taken the whole **S-15** legal set (the re-consent gate, the material texts, the invitation purge and the grace warning) plus **F-42** (scheduled reactivation). The re-consent **hard lock starts 16/08/2026** — promotion + the 15-day notice the legal review requires, now pinned in `PolicyVersions.EnforceFrom` and `policy.enforce_from`; until then the gate only warns. The [changelog do cliente Blazor](../docs/changelog-blazor.md) is the authoritative build history. With the go-live done, the **public-availability gate has no development left in it**: **S-16 shipped in `1.7.1`** and **T-35 in `1.7.2`** (the repo left the legacy static keys and the concurrency token stopped being guessable; both are in production since the 05/08 promotion). Its two remaining items are owner ops and were **moved to the new group 8 · Início da monetização** (owner, Aug 2026) — **S-17** waits on the HS256 grace window (runbook section 10.7) and **T-36** on actual revenue, the group's whole point being that additional platform spend waits for income — so the execution queue now continues at **group 3**; the [runbook's section 9](../supabase/README.md#9-billing-go-live-t-39--activating-real-charges-in-production) is kept as the record of what was configured (and as the procedure for a future environment). Full records live in [`archive/`](archive/) (per phase).

This section holds the **rationale** behind the forward plan — why this order, the per-item caveats, and the ops chores that are not backlog items. The **authoritative order and status** of the pending items is the `Grupo roadmap` + `Ordem` of the [Notion board](https://app.notion.com/p/3ae2f3f4b9b28169acd9e642ad4760aa); the groups below match it one-to-one — **including the landing's pending `L-*` items, which sit in the same groups since Aug 2026 (the integrated app+site roadmap)**. Their rationale stays in [`entrelares-site/ROADMAP.md`](https://github.com/irineus/entrelares-site/blob/preview/ROADMAP.md); the rows below carry only a one-line summary.

> **Guiding principles (locked with the product owner) still hold:** measure before building; **never paywall the essential/safety core** (the two-party calendar, swap workflow, in-app notifications and the immutable audit log stay **free forever**); charge **per family**, never per seat; **web-first billing** (Pix + card on `web.entrelares.app`) so the wrapped store apps honour the web subscription.

### 1 · Turn the paid launch on — group COMPLETE (Aug 2026)
The freemium gates bite **and** the revenue mechanism exists (T-39: hosted checkout, webhook, grace/dunning, cancellation; F-43: the admin payment ledger; landing **L-08** already publishes the real price). Every backlog item of this group has shipped — **F-42**, **F-46**, **U-22** (`1.6.44`) and **F-41** (custom per-family roles, the closing freemium gate, `1.6.45`–`1.6.47`) — records in [`archive/phase-6.md`](archive/phase-6.md). **The ops chore is done too:** the owner ran the T-39 go-live checklist (real Asaas account, prod secrets incl. `ASAAS_API_URL`, webhook registered) and flipped `billing.enabled=true` in prod `app_settings` on **29/07/2026**. Production has been **charging for real** since then, on the Free Supabase plan (see the T-36 deferral note below) — prod already carries live subscriptions and webhook events.

> **Consequence for every future session — the billing path is production-critical, not dormant code.** From 29/07/2026 a change to `billing-checkout`/`billing-webhook`, to `set_family_plan` or to the grace/dunning cron can cost a real family money or access. The old "it's all behind `billing.enabled=false`" safety net is gone; the docs kept repeating it for five days after the flip (caught 03/08 while verifying the 1.7.0 promotion against the database, not against the docs — the S-15 lesson applied to our own notes).

> **Already covered, recorded so it is not proposed again (06/08/2026).** An external review
> suggested "liberar o Premium gratuitamente nos primeiros 14 dias, sem cartão, e depois bloquear
> as contas secundárias". **That exists and is more generous:** every new family is created with
> `families.trial_ends_at = now() + 30 days` and `is_premium()` ORs the trial with the paid plan
> (F-32), so the full Premium surface is open for 30 days with no payment method; paying *during*
> the trial adds the remaining days instead of forfeiting them (F-46). The second half was decided
> the other way **on purpose**: the F-37 gate is **add-only** — when the trial ends, a family that
> already has a 3rd caregiver keeps them, and only the *next* addition is blocked. Locking people
> out of a family they already belong to is not a paywall we are willing to build. (The review
> also quoted R$ 14,90 — the promotional price has been **R$ 5,49/mês · R$ 54,90/ano** since F-48
> / L-14.)

### 2 · Public-availability gate — no backlog items left (Aug 2026)
**S-16 shipped and is already in production** (`1.7.1`) — the stack reads the new
publishable/secret keys and the functions authorize in code, so the ES256 promotion stopped
being an incident waiting to happen and became a scheduled step of the
[runbook's section 10](../supabase/README.md#10-s-16--migração-das-chaves-de-api-e-da-assinatura-jwt);
record in [`archive/phase-7.md`](archive/phase-7.md). The rotation ran the same day: new keys on
both projects, CI secrets and cron headers cut over, and **DEV promoted to ES256** with a green
full-pack. What is left there is owner ops on prod (its ES256, then disabling the legacy keys on
both — 10.6/10.7). **T-35 also shipped** (`1.7.2`): the optimistic-concurrency token stopped being
guessable — `care_schedules` now carries a read token re-rolled on every write plus a separate
echo column the writer must fill, so neither guessing the counter's next value nor omitting the
column passes, and the server-side exemption is by role instead of by payload shape
([`archive/phase-7.md`](archive/phase-7.md)).

**The group is now empty of backlog items (owner decision, Aug 2026): S-17 and T-36 moved to the
new group 8 · Início da monetização.** Both are owner ops that wait on something other than
development, so holding the execution queue behind them was buying nothing. The group number
stays 2 even empty (`Fase`/group numbering is stable, and other documents reference it).
*(The S-15 promotion chore that used to sit here — moving `policy.enforce_from` off the
provisional `2026-09-30` — was DONE at the 01/08 promotion, `1.6.42`: both halves now read
`2026-08-16`, promotion date + 15 days. The hard lock starts then; nothing left to do at
later promotions unless a future material policy change restarts the cycle.)*

### 3 · Swap-workflow & reports depth — COMPLETE
Product-depth block (owner, Aug 2026): deepen the core wedge — the swap workflow and the reports
that monetize it (F-33) — **before** scaling acquisition. All six items came out of the owner's
field usage; F-44 → F-45 was a deliberate order (the PDF enrichment pays off once the motivation
text exists). **F-44 delivered** (`1.7.3`/`1.7.4`), **T-45 delivered** (`1.7.5`), **F-45
delivered** (`1.7.6`/`1.7.7`), **U-20 + U-07 delivered together** (`1.7.9` — same cards, same
PDF section) and **F-47 delivered** (`1.7.10`) — the group is empty; all records are in
[`archive/phase-7.md`](archive/phase-7.md). The number stays 3 (group numbering is stable and
other documents reference it). Execution continues at group 4.

### 4 · Distribution
**Store listings come first (owner, Aug 2026): T-38 then T-40.** The previous order put the
landing's SEO cluster first and left iOS last, "after monetization is validated" — that condition
was dropped: the owner wants the app listed on **both** stores as soon as possible, so the two
wrapper items took slots 1 and 2 and the acquisition items that need no gate follow. **T-38 is
DELIVERED** (`1.7.14`/`1.7.15`, record in [`archive/phase-7.md`](archive/phase-7.md)) — the
listing itself continues as owner ops per `store/README.md` (Play account, closed test of ~12
testers/14 days, real fingerprints into `assetlinks.json` as a small future PR).

**F-54 is DELIVERED (12–13/08/2026, `1.8.2`→`1.8.7`, record in
[`archive/phase-7.md`](archive/phase-7.md)).** The rebrand to **Entrelares** jumped to the front
of this group and took everything with it: name, tagline, domain, identity, the internal code
rename, the e-mail sender, and a NEW Play package (`com.entrelares.app`) whose closed test is
running with 12 testers. That last part is why the group's shape changed: the previous listing
work (T-38) applied to a package that is being retired, and what it left behind — the legacy
`assetlinks.json` statement and the old referrer prefix — is a bridge for whoever still has the
old app installed. Removing it is **T-52**, at the end of this group, gated on the old app
being unpublished rather than on any development.

**Execution continues at L-16 (owner, 05/08/2026), inserted AHEAD of T-47** — **U-13 is
DONE** (i18n, `1.7.16` → `1.7.28`, record in [`archive/phase-7.md`](archive/phase-7.md)) and so is
**U-23** (first-run onboarding, `1.7.29` → `1.7.30`, same archive). The
Play listing exists but the closed test could not be filled, and the owner named the two
reasons: the app was **PT-BR only** while most of the developer community he can reach for a test
does not read Portuguese, and there was **no onboarding** — a first-time user landed on an empty
calendar with no explanation of the model or of what to do first. Both were recruitment blockers,
not polish: the store item that precedes them (T-38) is only worth what the test seats it can
fill. **Both are now delivered.** U-13 (i18n) went first deliberately, and that ordering paid off
exactly as argued: the onboarding added ~30 new strings, and **U-23 authored every one of them
through the localization layer** instead of writing them PT-BR-only and retranslating a week
later.
**L-16** (the landing's English half) closes the loop, since the recruited tester reads the site
before the app. The app being **open to the international community** is what turned all three
from "someday" into the head of this group.

**The T-36 tension this section used to flag is settled**: the owner **waived the prerequisite
deliberately** at T-38's start (05/08/2026) — the group-8 rule stands (platform spend waits for
actual revenue) and listing publicly on a project whose only backup is the weekly encrypted dump
(T-19) is a recorded, accepted risk (payment truth lives in Asaas either way). Revisit the
moment revenue starts.

**Aug 2026 additions (architecture/monetization review).** The owner's two concerns — "will
anyone pay outside the stores?" and "will Apple accept the wrapped app when the moment comes?" —
were settled as items instead of a platform migration (a .NET MAUI rewrite was evaluated and
declined: a MAUI Blazor Hybrid faces the same WKWebView review as Capacitor, and full-native
would triple the billing stack while freezing the product for months). **F-48 + L-14** (trust
signals + funnel instrumentation + Pix avulso) took slot 1: they had no gate, they were the
useful work while the T-36 decision above is settled, and they generate the channel-segmented
funnel data the rest of the group consumes (both delivered — see below). **T-47** (a cheap App Review verdict via a spike
submission) sits between the two wrappers as T-40's new prerequisite. **T-48 is COMPLETED** (20/08/2026): it stopped being parked on 19/08 and was delivered in
**redesigned** form inside T-53 lote 5 — the Digital Goods API was a TWA mechanism, and a
native app must use Play Billing, so it moved from "if the funnel says so" to "the store
channel cannot sell without it". Its record is in [`archive/phase-7.md`](archive/phase-7.md).
Go-live is configuration, tracked in `supabase/README.md` §9-bis (same shape as T-39's), not
a backlog row.

**F-48 and L-14 are DELIVERED** (`1.7.11`–`1.7.13` + the landing pair, Aug 2026): trust
signals + promotional launch pricing (R$ 5,49/54,90 — the QA round found the original R$ 4,90
under the Asaas R$ 5 Pix/boleto minimum) + the channel-segmented funnel + Pix
avulso — records in [`archive/phase-7.md`](archive/phase-7.md) and the landing `ROADMAP.md`.
The **CNPJ/company-identity half was carved out to the new pair F-49/L-15 (group 8)**: the
owner has no CNPJ yet and will not expose his personal identity instead.

**U-27 is DELIVERED** (20/08/2026, `entrelares-flutter` `0.2.29+31`…`0.2.31+33`): the Flutter
app has a visual layer — one token file that is the only place a colour may be written (with a
build gate that enforces it), both themes hand-written and dark following the system, the
eleven shared components, Inter embedded, and skeletons where the port had spinners. Two
decisions moved while building and are recorded in
[`archive/phase-7.md`](archive/phase-7.md): the calendar keeps **four** coloured slots (web
parity) and adds a texture per slot, which is a stronger answer than dropping to two colours;
and the brand indigo lightens in dark, because `#4F46E5` on `#111827` measures 2.3:1. It also
makes **U-12** nearly free — both themes exist, so only the user-facing switch is left.

**F-58 is DELIVERED** (`1.8.8`–`1.8.12`, 18/08/2026): the platform-operator role, its
audited RPCs and the courtesy-Premium mechanism live in the database, and the console itself is
a separate **Flutter** app in the new repo `entrelares-console` — the owner's call, so no
operator code ships in the public bundle and the future Flutter migration starts on a
single-user surface. Record in [`archive/phase-7.md`](archive/phase-7.md); the pilot's
device-level lessons are in that repo's `docs/migracao-flutter.md`. It also left **F-53** with
nothing to build: **F-53 is DELIVERED (01/09/2026)**, the day the closed test ended — the cutoff
was settled (accounts created 11/08/2026 → 01/09/2026 inclusive) and the tester families were
granted the permanent comp in the console, keeping the public promise of 11/08/2026. Procedure
and cutoff in [`../supabase/README.md`](../supabase/README.md) §12; record in
[`archive/phase-7.md`](archive/phase-7.md).

> **T-53 left this table on 23/08/2026, delivered.** The Flutter rewrite is no longer a
> plan in the queue: it IS the product on both channels — the Play package
> `com.entrelares.app` has carried the Flutter bundle since the store cut, and
> `web.entrelares.app` has served Flutter Web since the domain move the same day. The
> Blazor client was published at `legado.entrelares.app` as the documented way back
> until **24/08/2026**, when the owner declared the rollback unnecessary and
> `entrelares-app` was shut down (T-56) — so this is now the only client the product
> has. Records in [`archive/phase-7.md`](archive/phase-7.md) (T-53 and T-56); runbook
> and rollback plan in [`docs/flutter-cutover.md`](../docs/flutter-cutover.md), and the
> archiving in [`docs/arquivamento-app.md`](../docs/arquivamento-app.md).

> **Board sweep, 26/08/2026 (post-cutover review):** with the closed alpha nearly done, every pending record was
> re-read against the Flutter reality. In this group: **T-47 was skipped** (its Capacitor premise died with T-53;
> the TestFlight validation pass it contributed is now step 1 of the **rewritten T-40**, a native Flutter build)
> and **T-59** was created — the Play production rollout collector. **L-19's** animated-install premise (the
> installable PWA) should be re-judged when T-40 lands. In group 5, **T-50 was skipped** (its artifact producer,
> the Playwright suite, died with the app repo) and **T-18/F-09/U-12** were rewritten off their Blazor/PWA scope — **F-09 was then DELIVERED on 29/08/2026** after a second re-analysis that kept the direction and corrected the cost.

| Item | What | Notes |
|---|---|---|
| **T-40** | iOS channel: **native Flutter build** + App Store listing | Rewritten 26/08/2026 (post-cutover sweep), **absorbing T-47**: the app is Flutter, so iOS is a native build, not a Capacitor wrapper — the Guideline-4.2 "thin wrapper" risk that T-47 existed to measure collapsed with the cutover. Step 1 is a TestFlight validation pass (the surviving half of T-47). Web-first billing (T-39) still keeps it a "manage your plan on the website" client; **US$99/yr** owner ops. Record in [`technical.md`](technical.md). |
| **F-59** | **Push pode SUBSTITUIR o e-mail?** — medir antes de decidir | Added 29/08/2026 at the close of F-09, which shipped push as an ADDITION and said why: *"há um token vivo"* é uma das mentiras mais comuns em mobile (app desinstalado, permissão revogada, OEM matando o processo), e trocar um e-mail entregue por um push que talvez não chegue perde o aviso **em silêncio** — e os avisos em questão são prazos de um fluxo de duas partes. **A primeira metade do item é MEDIÇÃO, não política**: hoje o despachante devolve `{sent, retired, failed}` para um trigger que descarta, então ninguém consegue responder quantos responsáveis têm dispositivo nem com que frequência um token morre. O espaço de opções é maior que substituir/não: a mais barata é **parar de contar na cota do F-38 sem parar de enviar**. Placed here for SEQUENCE — precisa dos dois canais existirem. Record in [`features.md`](features.md). |
| **L-17** *(landing)* | Animated demo of the immutable history | Added 06/08/2026 from an external site review: the differentiator is *shown* in text and *proven* in nothing. A short muted loop of a swap request + its timestamp landing in the history, replacing a static mockup. Needs PT **and** EN assets (`/en/` exists since L-16). |
| **L-19** *(landing)* | Animated iOS install guide | Same review. The written Compartilhar → "Adicionar à Tela de Início" steps stay as the fallback; the animation is added, never substituted. **The F-09 pairing is dead (29/08/2026):** it read "iOS Web Push needs the installed PWA", and F-09 shipped as native FCM/APNs — the installed PWA buys iOS nothing here any more. What is left to re-judge is whether an install guide is wanted at all once **T-40** puts the app on the App Store. |
| **L-20** *(landing)* | E-mail sequence for the L-09 lead magnet | Same review. **Carries a production risk, not just work**: the Resend allowance is per ACCOUNT and shared with prod GoTrue SMTP (T-49) — a drip campaign competes with sign-up confirmations. Read its record before scheduling anything. |
| **L-11** *(landing)* | Community channels | Ongoing marketing activity, not code; tracked so it is not lost. |
| **L-12** *(landing)* | Lawyer / mediator partnerships | Ongoing; pairs with the app's F-33 PDF report. |
| **T-52** | Retire the legacy Android package `com.guardacompartilhada.app` | Split out of F-54 at its close-out (13/08/2026). The rebrand shipped a NEW Play package, so whoever installed the previous app still has it — and the legacy statement in `assetlinks.json` is what keeps THAT app full-screen. It comes out when the old app is unpublished, not before, or the browser bar returns for the exact people who volunteered to test. Gated on a Play state, not on development. Record in [`technical.md`](technical.md). |
| **T-61** | **Custom domain for the auth endpoint** — the Google screens must say Entrelares | Added 27/08/2026 during the F-57 go-live, measured on a real device: the consent screen and Google's own summary e-mail both name `<ref>.supabase.co`, never the product. **The owner called it a blocker for public availability**, so it sits before T-59. **Decisão de 28/08/2026: os dois caminhos escolhidos são gratuitos** — (A) verificação de marca no Google, sem código nem DNS, e (B) login nativo (`signInWithIdToken`) se A falhar. B conserta Android/iOS e não a web, o que é aceito: o produto é **Android/iOS first**, e o canal web + trilho Asaas são alternativos por decisão. O domínio pago fica documentado como plano de prateleira. O espelho CSP↔`env.dart` e o runbook §9-quater entregaram em 27-28/08/2026. Record in [`technical.md`](technical.md). |
| **U-30** | Account surface must say how you get in (sign-in methods) | Same session: F-57 handled the password-LESS case, but an account that linked Google to an existing password login now has two doors and the profile shows one. Someone who changes their password believing it locks the account would be wrong. Small; folds into **U-21** if that lands first. Record in [`ui-ux.md`](ui-ux.md). |
| **T-59** | Play production rollout: closed alpha → public availability | Added 26/08/2026 by the post-cutover sweep — T-57, S-18, T-36 and F-53 all reference the closed-alpha → public event, and none tracked it. A collector like T-36: the checklist lives in [`technical.md`](technical.md). Mostly owner ops; small PRs where a checkbox turns out to be code. |

### 5 · Progressive enhancement & polish
*(**U-13** left this group on 05/08/2026 — i18n stopped being polish the moment the app opened
to the international community and the language barrier started blocking tester recruitment. It
is now the first item of group 4, rewritten to full scope.)*

| Item | What |
|---|---|
| **U-12** | Dark mode — only the **user-facing theme switch** is left ("sempre claro / sempre escuro / sistema"): U-27 shipped both themes and the app already follows the system. Complexity fell `medium → low`; record rewritten 26/08/2026. |
| **L-04** *(landing)* | Blog image optimization (WebP/AVIF + `srcset`) — hours-level, SEO payoff. |
| **L-07** *(landing)* | Sitemap hygiene (drop noindex pages, `lastmod` convention). |
| **L-18** *(landing)* | Move the founder note up (right after "Como funciona") + calmer typography. Added 06/08/2026 from the external site review; it is a **placement bet**, so it ships with the Umami (L-01) reading that judges it. |
| **T-18** | Offline-first data strategy — record rewritten 26/08/2026 for Flutter (local read cache + "Modo offline" strip with staleness). The split decision stands: the *read* half is the whole user-facing value; the write queue is a separate decision, because a queued write can be legitimately refused when it flushes (T-35 token, frozen days, F-39 horizon). |
| **U-21** | Profile page refinement — read-only groups + pencil-to-edit bottom sheets. |
| **L-13** *(landing)* | Outreach discovery — a time-boxed comparison of where to spend promotion effort (the loop the invite flow already has, product-led surfaces, ASO, search intent, paid as a *measurement*), whose output is a ranked shortlist that becomes real items. Placed here by the owner (Aug 2026): the decision is worth more once the depth of groups 3–5 has landed. Record in the landing [`ROADMAP.md`](https://github.com/irineus/entrelares-site/blob/preview/ROADMAP.md). |
| **F-52** | **Aviso de imprevisto** — a one-tap, stamped, *unapprovable* notice on the current day ("estou atrasado", "imprevisto médico"): the other party is notified and the record keeps it, but the calendar does not move. Added 06/08/2026 from an external product review. It is the deliberate **constrained subset of F-35** (group 6): a closed reason list and one short line, one direction, no reply — which is what lets it ship here instead of opening a messaging surface. Reuses notifications + the immutable log; must never become a shadow swap (if the day really changes hands, that is the swap workflow, and the sheet should offer it). |
| **F-51** | Clear planned days in **one action**, instead of tapping each cell. Two entry points, no scope picker (owner, Aug 2026 — chosen to keep the sheet clean): **"Limpar mês"** (today → end of the displayed month, never the past) and a **"substituir os dias já planejados"** checkbox *inside the rotation wizard*, which clears exactly the range it is about to generate — so a re-plan is one pass. The second one is what makes the feature work at all: the wizard *keeps* days that already exist, so today a re-plan silently produces "0 dias criados". One `SECURITY INVOKER` RPC so the existing day rules (F-40 admin, frozen, approved swap) apply per row, as the caller, in one transaction. |
| **U-25** | **Day sheet decluttered** — stop repeating what the calendar already shows (responsible/handoff collapse to chips), actions behind a discreet edit icon, explicit ✕/voltar in the sheet header. Added 12/08/2026 from closed-alpha feedback (*"essa lista suspensa está muito poluído… falta um botão voltar"*). Standalone, but deliberately the layout groundwork for **F-55** (group 6): the freed sheet body is where the child's day timeline will render. E2E selector migration is the real cost — same delivery. |
| **U-26** | **E-mail dark-mode visibility** — the invite e-mail's pure-black header band and CTA vanish on dark-theme mail clients (Gmail's partial inversion). One pass over the shared template layer (`functions/_shared`): explicit `color` + `background-color` on every element, no `#000` surfaces, brand-color CTA, no reliance on `prefers-color-scheme` (Gmail ignores it). Added 12/08/2026 from closed-alpha feedback with screenshot. It was a candidate to ride F-54's PR 1 (which rewrote every template); that window closed with the rebrand, so it stands on its own — the templates are correct in brand and still wrong in the dark. |
| **T-58** | **The web flow gate must prove it ran** — `web-e2e` blocks the web publish and was passing GREEN with its `setUpAll` throwing: on web `flutter drive` prints `All tests passed.` and exits 0 when zero tests ran, so `set -euo pipefail` cannot see it. It was born (#63, 24/08) five days after the bug that broke its `setUpAll` (19/08), so it never executed a test — the green that justified letting it block production was vacuous. The guard must require POSITIVE proof of execution, and be designed against the first genuinely green run, which has never existed. The correction of the false "144 s / 5 testes" line in `docs/arquivamento-app.md` was its third piece of scope and landed separately in #82 (25/08) — what is left is the guard and the regime decision, which is the owner's. Acceptance: the guard must go red on a suite that runs ZERO tests, not merely on a failing assertion — validating it the easy way reproduces the original defect. **The item grew a second half on 26/08:** now that the lane really executes, it also OSCILLATES — the same test code failed on one docs-only PR and passed on another running concurrently, then passed on re-run a day later. A gate that refuses at random spends the same trust as one that approves without asserting, and teaches everyone to re-run until green. Settle the cause by EXPERIMENT (alone vs. concurrent, and a different calendar shape) before writing a fix. **One cause is now settled (29/08/2026): the calendar-shape hypothesis was right** — re-running the last green `main` sha reproduced the failure, and the lane's `now + 3 days` target rolled into the next month while the grid stayed on the current one. Fixed in #109. Hypotheses 1 and 3 stay open, and the item's own subject — the guard against a vacuous green — is untouched. |
| **S-18** | **The privacy policy and Play's Data safety must catch up with the store billing rail** — the published policy says payment data is handled by Asaas and never mentions Google Play, while the Android channel has been selling through Play Billing since 23/08/2026; the Data safety form was answered when Android sold nothing. Found 25/08 while preparing the first upload since the cutover. *Purchase history* was marked on the spot; what is left is **App interactions** (declared in `store/README.md` §4, missing in the console), the undecided **Messages** call on F-44's free-text notes, and the §7 operator list. The expensive half is whether the policy change is MATERIAL — if it is, it is the four-part blocking delivery, and that is the owner's call. Should precede the next PRODUCTION rollout — the same argument T-57 carried, and **T-57 landed 28/08/2026**, which leaves this the last of that pair still open. |
| **F-60** | **The auto-approval deadline the notice promises must be the one the request has** — F-24's clock is anchored on the DAY (`schedule_date + handoff`, +24h reminder, +48h approval), which is right; the sentences describe a window measured from the REQUEST, which is wrong in both directions. A request made a week ahead is told it expires "em 24h"; a request made on the day itself, after its handoff hour, gets LESS than the 48h it promises. Found in production on 01/09/2026 by the owner: request #32 (31/08, no handoff) was created 16:20 BRT and its "expira em 24h" reminder landed 7h48 later, with ~31h of real window. Nothing malfunctioned — only the product's account of itself. Cheapest honest answer is to state the INSTANT instead of a relative window; re-anchoring on `GREATEST(expiry, created_at)` is a separate rule decision. ⚠️ Three copies of every such sentence (Dart catalog, `_shared/push.ts`, e-mail templates) held together by the F-09 mirror. Record in [`features.md`](features.md). |

### 6 · Co-parenting-hub expansion (candidate second paid wedges)
Larger scope; priority may rise once F-33 proves the premium tier. F-34–F-36 reuse the two-party approval workflow + immutable audit already built; **F-50** is the odd one out on purpose — a new *membership category* rather than a module, placed here (owner, Aug 2026) because it is product expansion with a monetization edge, and because it stays deliberately OUTSIDE the two-party workflow.

| Item | What |
|---|---|
| **F-34** | Shared-expenses module. |
| **F-35** | In-app communication log (court-admissible messaging). |
| **F-36** | Document vault (school / medical / court files) via Supabase Storage. |
| **F-50** | **Viewer member** — a read-only membership category (grandmother, nanny, new partner, lawyer/mediator): sees the plan, generates nothing, never lands on a day and never enters the swap workflow. Promotable to full when a seat *and* a colour slot free up; the reverse is forbidden by design (same reasoning as F-28's scenario C). Viewers sit outside the F-37 caregiver pool with their own cap, and a leaving viewer is erased outright — the S-11 tombstone exists for members the past references, which a viewer never is. Pairs with **L-12** (a read-only seat is what a lawyer wants). |
| **F-55** | **Child day agenda** — per-child, per-day events (school shift, appointment, "remédio às 14h") rendered as a day TIMELINE inside the day sheet (the space U-25 frees), the tester's own model being the Outlook mobile day view. Added 12/08/2026 from closed-alpha feedback — the strongest unprompted field signal for this group so far; candidate to jump the group's queue (owner decision pending). First PR delivers the **child entity** (the `children`-table half of F-07, born multi-child-ready); coordination-only by design: never freezes a day, never touches `actual_parent`. The Observação-do-dia relationship (replace vs coexist) is the item's central design question — the observation is load-bearing for F-47. |
| **F-56** | **Solo mode** — a third member state, `pending` (invited, never signed in), mirroring S-11's tombstone in reverse: assignable to days, visible in the calendar, but never a party to a swap/revert (nothing to approve with). The founder plans everything alone; the ex who finally joins claims the SAME member identity, days intact, and swaps unlock. Added 12/08/2026 from closed-alpha feedback — an adoption blocker for exactly the tester profile the alpha surfaced. ⚠️ Its central design tension is LGPD: the invite e-mail promises a 30-day purge of the invitee's data, so the placeholder must be founder-authored content, not invitee data (see the entry). Candidate to move up in this group: it is an entry door, not a wedge. |

### 7 · Future / low priority
| Item | What |
|---|---|
| **F-07** | Multi-child support (schema-wide; candidate paid wedge for bigger families). |
| **F-08** | Calendar export / iCal. |
| **F-30** | One e-mail linked to multiple families (many-to-many membership). |

### 8 · Início da monetização — parked until revenue starts (owner, Aug 2026)
S-17 and T-36 are **owner ops, not development**, pulled out of the public-availability gate
(group 2) once S-16 and T-35 emptied it of code; **F-49/L-15** (added at the F-48/L-14
close-out) are small development items gated on the same milestone — the company existing.
The group exists so the rule is explicit rather than implicit: **additional platform spend
waits for actual revenue.**
Billing has been charging since 29/07/2026, but on free tiers — this group is where the cost side
starts. Numbered 8 because group numbering is stable and 7 is taken; the number is a label, not a
schedule, and **either item can be pulled forward at any time** (the owner said so when creating
the group).

| Item | What | Notes |
|---|---|---|
| **F-49** | Company identity (CNPJ) on the payment surfaces | The half of F-48 that waits for the company to exist (owner has no CNPJ yet; personal identity will not be exposed instead): CNPJ + razão social on the paywall/checkout and app footer where it fits. **Cross-repo pair of landing L-15 — same delivery.** Check whether the Terms' "Prestador do serviço" wording gains the CNPJ (identity disclosure = non-material, no `PolicyVersions` bump). |
| **S-17** | Disable the legacy API keys + revoke the HS256 secret | **Costs nothing** — it rides in this group because it is owner ops that waits on *time*, not on money: tokens signed with HS256 stay valid for an hour after the ES256 rotation, and the platform refuses to revoke the secret while the keys derived from it are enabled. So it is the one to pull forward first: until it runs, a leaked legacy key still opens either project, which is most of S-16's security benefit unrealised. Runbook 10.7. |
| **T-51** | Register `entrelares.app.br` (brand-protection domain) | Created 12/08/2026 with the F-54 rebrand: `.app.br` was available but deliberately not bought — spend waits for revenue, per this group's rule. ~R$ 40/yr at registro.br + one 301; pull forward at any sign of squatting. Record in [`technical.md`](technical.md). |
| **T-36** | Supabase Pro upgrade + production-ops checklist | The reason the group exists. PITR/daily backups, Leaked-Password Protection, DMARC `p=none`→`quarantine`, prod rate-limit review, Advisors re-run. Deferred out of group 1, then out of group 2, now parked on revenue. **Still blocks T-38** (group 4): a public Play listing on a project without PITR/daily backups is the dependency that survives every reordering. Accepted risk meanwhile: the weekly encrypted dump (T-19) is the only backup net. |
