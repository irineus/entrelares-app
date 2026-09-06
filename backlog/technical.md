# Backlog — Technical / Architecture (pending)

Active technical items. Completed records live in [`archive/`](archive/). Conventions and the forward plan: [`README.md`](README.md). Live status: the [Notion board](https://app.notion.com/p/3ae2f3f4b9b28169acd9e642ad4760aa).

---

_T-08 (item 4.2), T-09 + T-11 (item 4.3) and T-07 + T-13 + T-27 (item 4.4) were completed in Phase 4 — records live in [`archive/phase-4.md`](archive/phase-4.md)._

_**T-34** (privacy e-mail address), **T-37** (Umami product analytics), **T-41** (`app_settings` config table) and **T-42** (`npm:` Deno imports) were completed in Phase 6 — records live in [`archive/phase-6.md`](archive/phase-6.md)._

_**T-35** (non-guessable concurrency token), **T-45** (next-day handoff consistency) and **T-49** (the test suite no longer spends the Resend allowance) were completed in Phase 7 — records live in [`archive/phase-7.md`](archive/phase-7.md)._

---

### T-18 — Offline-first data strategy (read cache + offline indicator)

| Field | Value |
|---|---|
| **Status** | `pending` |
| **Priority** | `medium` |
| **Complexity** | `high` |
| **Impact** | `medium` |

**Description**
With no connectivity the app fails silently: every PostgREST call errors and the calendar
renders empty. Cache the last successful read locally and serve it when the network fails, so
the plan is still visible offline — the door-of-the-school moment ("ver o calendário na porta
da escola ou no elevador") that an external product review asked for by name.

> **Rewritten 26/08/2026 (post-cutover board sweep).** The original record was written for the
> Blazor PWA — `service-worker.published.js`, IndexedDB via JS interop, `RealtimeBridgeService`,
> `RetryHelper` — and every one of those surfaces died with the T-53 cutover (the shipped
> `service-worker.js` is deliberately a TOMBSTONE and must stay one). The product decisions
> survive unchanged; the implementation is Flutter's.

- **PR 1 — read offline (the whole user-facing value).** Persist the last successful read of
  the current month + the today card in a small local cache service (`shared_preferences` or a
  file; a real local DB only if the shape ever demands it), serve it when the fetch fails,
  refresh on reconnect. Nothing else in the item is needed for that moment.
- **A visible "Modo offline" strip, reading ONE connectivity state.** Derive the state once, in
  one service, from what the app already has — the native Realtime channel state and the
  success/failure of the PostgREST calls — never from a bare reachability probe alone (it
  reports the interface, not reachability; a captive portal is "online"). The strip must say
  **how stale** what is on screen is ("dados de HH:mm"), otherwise it invites the opposite
  mistake: trusting an old plan as current.
- **The strings go through the localization catalogs** (U-13, both languages) and the date/time
  through the per-language formats (U-24).
- **A write queue is NOT a free extension of the read cache — it is a separate decision.**
  Every day rule lives in the **database**, and a write parked offline can be legitimately
  refused when it flushes: the T-35 `submitted_token` echo is **stale by construction** if
  anyone else wrote the day in the meantime (the flush is *supposed* to fail); the day may have
  been frozen by a swap request in the interval; the F-39 planning horizon may have moved; and
  a day that was in the future when queued may be in the past when it flushes. So background
  sync needs a per-item conflict UI and a replay policy, not just a queue — and a silent
  "saved" that later evaporates is worse than an honest "sem conexão". Ship the read half
  first and take that decision on its own.
- The store raises the stakes, not the web: the Play-installed app IS this codebase now — an
  empty calendar offline reads as a broken *app*, never as a browser with no signal.

**Files affected**
- New cache + connectivity service under `apps/entrelares_app/lib/services/`; the pure state
  machine (online → degraded → offline) and the staleness sentence mirrored in
  `packages/entrelares_core` with `dart test`
- Calendar/today reads go through the cache; "Modo offline" strip in the app shell
- Catalog keys for every new string (U-13/U-24)

---

_T-19 (Phase 5 item 5.6) was completed in July 2026 (v1.5.6) — its record lives in [`archive/phase-5.md`](archive/phase-5.md)._

---

_T-22 (item 4.6) was investigated and **skipped** in Phase 4 — no newer SDK exists for its goal (Gotrue is already at the latest published version). Findings and the revisit trigger live in [`archive/phase-4.md`](archive/phase-4.md)._

---

_T-29 was completed at the start of Phase 4 — its record lives in [`archive/phase-4.md`](archive/phase-4.md)._

---

_T-30 (Phase 5 item 5.1, first delivery) was completed in July 2026 — its record lives in [`archive/phase-5.md`](archive/phase-5.md). Scenario expansion: T-31 (done) and T-32 (below)._

---

_T-31 (Phase 5 item 5.2) was completed in July 2026 across three incremental PRs — its record lives in [`archive/phase-5.md`](archive/phase-5.md)._


---

_T-32 (Phase 5 item 5.16) was completed in July 2026 (test-only, no version bump) — its record + full findings report live in [`archive/phase-5.md`](archive/phase-5.md) and [`t32-findings.md`](t32-findings.md). Two batches of adversarial/boundary scenarios, all proving the app fails safely. Findings: T32-A1→**T-35** (guessable optimistic token, low — closed in `1.7.2`), T32-A2 (integration suite rate-limit flake — fixed with sign-in backoff in the fixture), T32-A3 (100-char notes limit is UI-only, accepted). **Closes Phase 5.**_

---

_T-33 (Phase 5 item 5.15) was completed in July 2026 (v1.5.24) — its record, including the full mutation-by-mutation concurrency inventory, lives in [`archive/phase-5.md`](archive/phase-5.md). Stale calendar UPDATEs now fail loudly via a `revision` guard (scope decision: care_schedules only — single-field profile/family edits stay last-writer-wins, accepted); bulk skips-and-reports conflicted days; the wizard survives batch INSERT collisions._

---

_T-35 was completed in August 2026 (`1.7.2`) — its record lives in [`archive/phase-7.md`](archive/phase-7.md). The T-33 counter kept its guard and gained a **non-guessable** half: `care_schedules.revision_token` is re-rolled on every write and the writer must echo it in `submitted_token`, so neither guessing the next value nor omitting the column passes. Server-side flows are exempt **by role** (`postgres`/`service_role`), which is what makes the guard unbypassable from outside. Closes T-32 finding T32-A1._

---

### T-36 — Supabase Pro upgrade + production-ops checklist for public availability

| Field | Value |
|---|---|
| **Status** | `pending` |
| **Priority** | `medium` |
| **Complexity** | `low` |
| **Impact** | `high` |

**Description**
Consolidates every operational decision that was deliberately deferred "until
public availability" into one checklist, so none is lost when the switch flips.
Most items are a paid-plan decision plus Dashboard toggles — no code.

1. **Upgrade the PROD project to Pro** (billed per organization; the dev/QA
   account can stay Free). Unlocks the two deferred protections:
   - **PITR / automated daily backups** (Free has none — today's only net is
     the weekly encrypted R2 dump, T-19). Recommended durability step in the
     deploy runbook (`supabase/README.md` §1).
   - **Leaked Password Protection** (HaveIBeenPwned check on sign-up/reset) —
     Pro-gated, confirmed July 2026; on Free the mitigation is the server-side
     8-char minimum. Closes the accepted `auth_leaked_password_protection`
     Advisor warning (see S-14 triage note).
2. **DMARC hardening** on `guardacompartilhada.com`: after a few weeks of clean
   reports, tighten `_dmarc` from `p=none` to `p=quarantine` (Cloudflare TXT
   edit — runbook §5.5 already flags it).
3. **Auth rate-limit review on prod** (Authentication → Rate Limits): confirm
   the e-mail limit (~30/h with custom SMTP) and the sign-in/OTP limits are
   sane for a public user base.
4. **Re-run the Security Advisors + RLS sweep** (runbook §6.4) as the final
   gate once S-14/S-15/T-34 are done.

**Justification**
Each of these was individually accepted as "fine for a single-family beta,
revisit before public availability" (T-19, S-12/S-13, S-14 triage, runbook
§5.5). Public availability is the trigger; this item is the collector so the
trigger actually fires.

**Scheduling decision (owner, Aug 2026), revised twice.** First it left group 1
for the END of the public-availability gate (group 2). Then, once S-16 (`1.7.1`)
and T-35 (`1.7.2`) emptied that group of development work, it **moved again to
the new group 8 · Início da monetização**
together with S-17: both are owner ops that wait on something other than
development — this one on revenue — so holding the queue behind them was buying
nothing. The group makes the owner's rule explicit instead of implicit:
**additional platform spend waits for actual revenue**, and it can be pulled
forward the moment that changes. The Pro fee is a recurring cost that only makes
sense once the app has actual revenue; the billing go-live for the current base
proceeds on the Free plan (consistent with the T-39 activation decision, which
already waived this gate for the current base). It still cannot slide past
**T-38**, whose public Play listing requires this green. Accepted risk while
deferred:
prod runs without PITR/daily backups — the weekly encrypted dump (T-19) is the
only backup net (payment truth lives in Asaas either way); revisit immediately
when revenue starts.

**Files affected**
- None in the app — Supabase/Cloudflare Dashboard operations; update the
  runbook (`supabase/README.md`) and the S-14/T-19 notes as each box is ticked.

---

### T-40 — iOS channel: native Flutter build + App Store listing

| Field | Value |
|---|---|
| **Status** | `pending` |
| **Priority** | `low` |
| **Complexity** | `high` |
| **Impact** | `medium` |
| **Roadmap** | Roadmap group 4 (distribution) |
| **Prerequisites** | Store assets exist (T-38/F-54; **T-57 landed 28/08/2026**, so the listing art is the current app and an App Store listing can be derived from it instead of being born stale); **F-09 landed 29/08/2026 with the push rail already iOS-ready** — this item inherits it and adds only the APNs key, the capability and a device round; Apple Developer Program — **US$99/yr, owner ops** |

**Description**
Put the app on the App Store as a **native Flutter iOS build** (`flutter build ipa`) — the
same codebase that ships the Android and web channels.

> **Rewritten 26/08/2026 (post-cutover board sweep), absorbing T-47.** The item was born as a
> Capacitor wrapper around the Blazor WASM app, and **T-47** existed to buy Apple's verdict on
> that wrapper's "thin wrapper" risk (Guideline 4.2) before this item's budget was spent. A
> native Flutter app is not a wrapper: that risk collapsed with the T-53 cutover, so T-47 was
> closed `skipped` (owner, 26/08/2026) and its surviving idea — a cheap validation pass through
> TestFlight before the real submission — became step 1 here.

- **Step 1 — TestFlight validation pass (the surviving half of T-47).** First
  `flutter build ipa`, signing, upload, one internal TestFlight round. Surfaces the platform
  work — icons, launch screen, `Info.plist` permission strings, the iOS side of
  `url_launcher`/`printing`/share — with zero users affected and before the listing work starts.
- **Push: the rail is already built and waiting.** F-09 DELIVERED on 29/08/2026 and was
  deliberately written iOS-ready — the server sends a `notification` payload (the only kind iOS
  displays with the app dead) with an `apns` block already in it, `push_subscriptions` already
  accepts `platform = 'ios'`, and `firebase_messaging` carries APNs. What iOS still needs is
  console work and a device: an APNs auth key (`.p8`) uploaded to the `entrelares-prod` Firebase
  project, the push capability in the Xcode project, and one real handset to prove delivery.
  **The reason F-09 stopped at Android is this item:** there is no `apps/entrelares_app/ios/` at
  all, so iOS push was not merely harder, it was untestable. Shipping iOS without push is still
  possible and is still a choice; the cost of NOT deferring it is now close to zero.
- **Billing:** the web-first rail (T-39) is what lets the iOS app stay a "manage your plan on
  the website" client and avoid Apple's IAP cut — re-verify the App Store external-link rules
  at build time. If store-cohort data ever justifies native purchase on iOS, StoreKit via
  `in_app_purchase` is the incremental path (the iOS mirror of T-48) — explicitly out of this
  item's scope.
- **Build lane decided at execution:** GitHub Actions macOS runner (**10× minutes multiplier**
  on the private-repo 2000/mo budget — a submission fits, a build loop does not) vs a
  local/cloud Mac. The owner is on Windows, so signing/upload steps must be written
  click-by-click.
- Apple Developer Program (US$99/yr), provisioning, TestFlight, store assets — **reuse the
  T-57 set** (28/08/2026), which is already the Flutter app under the U-27 system in both
  languages; the T-38 set it replaced was the Blazor client.

**Files affected**
- `apps/entrelares_app/ios/` — icons, launch screen, `Info.plist` permission strings, signing
- New `store/ios/README.md` — build + signing + submission runbook (click-by-click)
- CI: an optional macOS lane for the ipa build (`workflow_dispatch`, never per-push)

---

_T-47 (iOS publishability spike) was **skipped** on 26/08/2026 — its premise, a Capacitor
shell around the Blazor WASM app needing Apple's verdict on the "thin wrapper" risk
(Guideline 4.2), died with the T-53 cutover: the iOS channel is now a native Flutter build.
The surviving idea (a cheap TestFlight validation pass before the real submission) is step 1
of the rewritten **T-40**. Record in [`archive/phase-7.md`](archive/phase-7.md)._

---

_T-50 (move the Playwright traces to R2) was **skipped** on 26/08/2026 — the artifact producer
died with the archiving of `entrelares-app` (T-56): the Playwright suite is gone, and this
repo's only CI artifact is the debug APK at 1-day retention. If the `web-e2e`/emulator lanes
ever record heavy diagnostics, a new item with real scope replaces it. Record in
[`archive/phase-7.md`](archive/phase-7.md)._

---

### T-51 — Register `entrelares.app.br` (brand-protection domain)

| Field | Value |
|---|---|
| **Status** | `pending` |
| **Priority** | `low` (by construction — waits on revenue, owner decision 12/08/2026) |
| **Complexity** | `low` (registration + one redirect; no code) |
| **Impact** | `medium` — squatting protection for the brand the Play listing makes public |
| **Roadmap** | Group 8 (Início da monetização), after F-49/L-15 — same shelf as everything that waits for the app to earn |

> **Created 12/08/2026 with the F-54 rebrand.** The rebrand bought `entrelares.app` (primary
> domain); `entrelares.app.br` was verified AVAILABLE the same day but deliberately not bought —
> the owner deferred it until the app has actual revenue, consistent with the group-8 rule
> (additional spend follows revenue). This item exists so the deferral has a reminder attached.

**Description**
Register `entrelares.app.br` at https://registro.br (~R$ 40/year; needs a CPF or CNPJ — if
F-49 has happened by then, register under the company's CNPJ so the domain follows the
business, not the person). Then a single ops step: add the zone to Cloudflare (or use
registro.br's own DNS) and 301-redirect apex + `www` to `https://entrelares.app`. No
mailboxes, no subdomains, nothing in either repo changes — `entrelares.app` remains the only
canonical host everywhere.

**Risk while it stays unregistered**
`.app.br` is the variant a Brazilian guesses when typing, and the brand is public in the Play
listing from the F-54 redeploy onwards. Anyone can take it for R$ 40 and hold it. That is an
accepted, revocable risk: if the app starts getting real traction (or any sign of squatting
appears on the name), pull this item forward instead of waiting for revenue — the whole point
of registering early is that it only works BEFORE someone else does.

**Related**
F-54 (the rebrand that created the split), F-49 (CNPJ — the ideal registrant), the group-8
rationale in `backlog/README.md`.

---

### T-52 — Retire the legacy Android package `com.guardacompartilhada.app`

| Field | Value |
|---|---|
| **Status** | `pending` |
| **Priority** | `low` — nothing is broken while it waits; the cost of waiting is only that two brand traces stay live |
| **Complexity** | `low` (one Console action + a two-line diff) |
| **Impact** | `low` for users, `medium` for the "no trace of the old brand" directive |
| **Roadmap** | Group 4 (distribution), after the closed test — it is gated on a Play state, not on development |

> **Split out of F-54 at its close-out (13/08/2026).** The rebrand shipped complete, with one
> thing deliberately left standing: the app is a NEW Play package, so whoever installed the
> previous one still has it, and the pairing that keeps THAT app full-screen is the legacy
> statement in `assetlinks.json`. Removing it while those installs exist would put the browser
> bar back on their screens — a regression for the exact people who volunteered to test.
> F-54 could not stay open waiting for an external trigger with no date (a row left behind
> reads as current to every future session), so the bridge became its own item with the
> trigger written down.

**Description**
When the legacy app is unpublished — i.e. when its remaining testers have migrated to
`com.entrelares.app`, or the Play closed test of the new package reaches production —, remove
the bridge:

1. **Play Console**: unpublish `com.guardacompartilhada.app` (*Test and release → Setup →
   Advanced settings → App availability → Unpublish*). Warn its testers first; they lose
   updates, not their data — the account and history live on the server and are reachable at
   `web.entrelares.app` from any browser.
2. `apps/entrelares_app/web/.well-known/assetlinks.json` — drop the whole
   `com.guardacompartilhada.app` statement (both fingerprints), keeping the two that stay
   (`com.entrelares.flutter`, `com.entrelares.app`). **This is the file the cutover moved**:
   since 23/08/2026 `web.entrelares.app` is served from this repo, so the statement that keeps a
   legacy install full-screen is published from here — the Blazor copy at
   `entrelares-app/Entrelares/wwwroot/` now serves `legado.` only and dies with it.
3. Nothing else has a client half left, and since 24/08/2026 nothing else has a client at all:
   the two Blazor arms the original record listed — the
   `android-app://com.guardacompartilhada.app` referrer check in `index.html` and the
   transitional comment in `Helpers/StoreContext.cs` — went out of service with the shutdown of
   that client (T-56), never having been this item's to remove. The Flutter store rail reads the
   platform, not a referrer. **So this item is now exactly two things**: the Play Console
   unpublish and the `assetlinks.json` statement in step 2.

**Justification**
The store-shell flag (T-38) and the Digital Asset Links pairing are the two places where a
retired package can still change behaviour, and both are invisible in normal use — nobody
notices a stale statement until an install proves it. Keeping the removal as a written item,
with its trigger and its file list, is what stops it from being discovered years later by
someone wondering why the repo names a brand that no longer exists.

**Files affected**
- `apps/entrelares_app/web/.well-known/assetlinks.json`
- Play Console (owner ops, no code)

---

### T-58 — The web flow gate must prove it ran (guard against a vacuous green)

| Field | Value |
|---|---|
| **Status** | `pending` |
| **Priority** | `high` — it is the alarm on the gate that stands between a merge and production |
| **Complexity** | `medium` — the guard is small; deciding what a real gate is allowed to block is not |
| **Impact** | `high` — every web publish since 24/08/2026 went out past a gate that asserted nothing |
| **Roadmap** | Group 5 (polish), right behind T-57 |
| **Repo** | `flutter` |
| **Depends on** | the E2E lane actually executing — PR #81's three defects. This item starts when that lands |

**The finding**
`web-e2e` has blocked the web publish since [#64](https://github.com/irineus/entrelares-flutter/pull/64) (24/08/2026), and it was passing **green while its `setUpAll` was throwing**. On web, `flutter drive` prints `All tests passed.` and exits **0** when zero tests ran — so an empty run is indistinguishable from a full one, and `set -euo pipefail` cannot see it, because the process really does exit 0.

Measured on 25/08/2026, same two files, same pack, one commit apart:

| Lane | before `2bcfcfb` (run `32832807358`, `main`) | after (run `32839493354`) |
|---|---|---|
| `web-e2e` | `All tests passed.` **2 s** after the debug service connected, exit 0 — **green** | names the test, exit 1 — **red** |
| `e2e` (emulator) | `setUpAll` throws — 0 passed / 2 failed | 1 passed / 1 failed |

Two seconds is not enough for a single round trip to Supabase, let alone a seeded family.

**The dating is what makes it structural, not a slip**
`role_name` entered in `ffb28b4` (19/08, the day the E2E lane was born). `web-e2e` was created in `ba5d192` ([#63](https://github.com/irineus/entrelares-flutter/pull/63)) on 24/08 and started blocking the publish in `ed8c3c4` (#64) — **five days after the bug**. It therefore never had a working `setUpAll`, which means it **never executed a test**. The green that justified letting it block production was vacuous from the first run.

**Scope**

1. **The guard: require positive proof of execution**, not the absence of an error. Suggested shape — the suites record how many tests ran in `binding.reportData` (a `tearDownAll`), `test_driver/integration_test.dart` swaps `integrationDriver()` for `integrationDriver(responseDataCallback: …)` writing that out, and the workflow step fails when the file is missing or the count is zero / below expectation. **Design it against the first genuinely green web run** — at the time of writing none has ever existed, so nobody knows what `flutter drive` prints on a real web success. A guard that greps expected output is how this class of bug is written a second time.
2. **Decide the regime, and that part is the owner's.** A gate that actually asserts can actually block a publish. That is its declared purpose, but in practice it is a change of regime, not a repaired test — which is exactly why it is an item and not a fix folded into someone's PR.

**Already done, and by someone else (25/08/2026).** This item opened carrying a third piece of
scope — correcting the false PR-5 line in [`docs/arquivamento-app.md`](../docs/arquivamento-app.md),
which recorded *"144 s para os dois packs (5 testes)"* while having timed **compilation** (2 targets
× ~42 s + startup) with zero tests executed. That correction landed in
[#82](https://github.com/irineus/entrelares-flutter/pull/82) hours later, written by the session
that owned the T-56 record: the "(5 testes)" claim is gone and the row now carries an explicit
`⚠️ CORRIGIDO` saying the lane was not blocking anything. Nothing is left of that piece.

**The method lesson that PR left, and the reason it belongs here rather than there.** It is the
rule the guard has to satisfy, stated better than this record first stated it:

> A probe proves what it exercises and nothing more. That one proved the lane can report a failing
> **assertion**; it never asked whether the lane can report a suite that **never got as far as
> asserting**. When a test exists precisely because the TOOL lies about success, the probe has to
> cover every way the run can end — and the record has to say which ways were covered.

Read against this item: a guard validated only by "we broke a test and the job went red" would
reproduce the original defect exactly. The acceptance for the guard is that it goes red on a suite
that runs **zero** tests — which is the case nobody checked, and the whole reason this item exists.


**And now the second half of the same question: the lane also OSCILLATES (26/08/2026).** The
first measured non-determinism since the lane started genuinely executing. Three jobs of the
same test code, no source change between them:

| Job | Result | Window (UTC) |
|---|---|---|
| `web-e2e` of [#86](https://github.com/irineus/entrelares-flutter/pull/86) ([97881850874](https://github.com/irineus/entrelares-flutter/actions/runs/32872255730/job/97881850874)) | pass | 25/08 **16:29:24 → 16:38:33** |
| `web-e2e` of [#87](https://github.com/irineus/entrelares-flutter/pull/87) ([97881998833](https://github.com/irineus/entrelares-flutter/actions/runs/32872300613/job/97881998833)) | **fail** | 25/08 **16:29:51 → 16:37:53** |
| the same job, re-run ([98124411440](https://github.com/irineus/entrelares-flutter/actions/runs/32872300613/job/98124411440)) | pass | 26/08 09:12:12 → 09:21:28 |

The failure: `Bad state: No element` from `ensureVisible` at `account_flows_test.dart:106`, in
*"p0 — an invitation is created and revoked through the real Família page"*. A finder matched
nothing. Both PRs were **documentation only** — neither touched a line the lane executes.

**Two variables change between the red and the green, and neither is established.** The re-run is
both *another day* and *alone*; the failure ran *alongside a sibling*. Read the windows: the two
runs of 25/08 started 27 seconds apart and the failing one lived entirely inside the passing
one's window. `web-e2e` is serialized **per ref** (`group: web-e2e-${{ github.ref }}`), so two
PRs run the lane against the same dev project simultaneously — by design.

Three candidate mechanisms, none of them demonstrated:

1. **Two concurrent runs on one dev project.** The job's own comment states non-collision as a
   *design assumption*, not a measurement: *"each invents its own `E2E-<runId>` family and both
   orphan sweeps spare anything younger than 2h"*. That reasoning covers per-family state and
   says nothing about what two runs SHARE — the Resend allowance is per ACCOUNT (a documented
   gotcha: the suite once spent production's), and S-01 throttling is per identity. An
   invitation e-mail that a shared limit refuses is exactly a finder that matches nothing.
2. **A date-dependent path.** There is precedent in this product: the Blazor `BulkUiTests`
   failure that held the `dev`→`master` promotion at the cutover was deterministic *only when
   the allocated days fall on the last row of the month*. A calendar-shaped failure looks like
   flakiness until somebody plots it against the date.
3. **An ordinary render/timing race** in `ensureVisible`, which is the dullest explanation and
   therefore the one most likely to be true.

> **HYPOTHESIS 2 IS CONFIRMED — and it was a real, deterministic defect (29/08/2026, found
> while delivering F-09).** The lane went red on a PR that touched no client code at all. The
> decisive experiment is the one this record already prescribed, and it took one command: the
> `web-e2e` job of the last GREEN `main` run was re-run, on the same sha, and **failed** — so the
> cause was the calendar, not the change.
>
> `targetDay` is `DateTime.now() + 3 days`; the grid opens on the CURRENT month and renders
> blanks then `1..daysInMonth`, with no tail of any neighbouring month. On the last three days of
> a month the target rolls over: on 29/08 the seeded day was 01/09, and `openDay(1)` found the
> only cell reading '1' — **01/08, a PAST day**, which opens the sheet in read mode with no chips
> at all. The symptom was `Bad state: No element` on a `ChoiceChip` finder, which names the
> widget and hides the cause entirely. The lane had been green until 21:48 on the 28th purely
> because `now + 3` had not yet crossed a month, and the p1 test carries the same trap with
> `now + 5`. Fixed in #109: `openDay` takes the DATE and navigates to its month first.
>
> **What this changes for the item.** One documented cause of the oscillation is gone, and the
> precedent the record cited (the Blazor `BulkUiTests` month-shape failure) now has a second
> instance in the same product — a calendar-shaped failure reads as flakiness twice over.
> Hypotheses 1 and 3 are untouched and unmeasured; this does not close T-58, whose subject is
> the guard against a VACUOUS green. It does remove the strongest current argument for
> re-running until green.

**Why this belongs to T-58 rather than to a new item.** T-58 asks whether the gate can be
*trusted*, and there are two ways to fail that: it can approve without asserting (the original
finding) and it can refuse for reasons unrelated to the change (this one). Both spend the same
trust, and the second is the more corrosive in practice — a lane that goes red at random teaches
everyone to re-run until green, which is indistinguishable from not having a gate at all. **The
re-run above is exactly that behaviour**, done knowingly and recorded here rather than quietly.

**How to settle it cheaply, before writing any fix.** Do not start from the code. Re-run the
FAILING sha alone, on a day whose calendar shape differs, and separately push two branches on
purpose within a minute of each other and watch both lanes. One of those two experiments
separates the variables; guessing between them writes the wrong fix confidently.

**Deliberately NOT in scope:** the three stacked E2E defects themselves (the `roles.role_name` column, `bootApp`'s inverted order, the unpinned language). Those belong to PR #81. This item is about the lane being *unable to lie*, not about the tests it happens to be running today.

**Justification**
A gate that approves without asserting is worse than no gate: it spends the trust a gate is for. The failure mode is silent by construction — there is no red build, no error, no slow step, only a green check that means nothing — so it is only ever found by accident, and it was: while chasing an unrelated scheduled failure. Writing the guard is what converts that accident into a rule.

**Files affected**
- `apps/entrelares_app/test_driver/integration_test.dart` — the driver's `responseDataCallback`
- `apps/entrelares_app/integration_test/*.dart` — the executed-count report
- `.github/workflows/verify.yml` — the assertion in the `web-e2e` step

---

### T-59 — Play production rollout: closed alpha → public availability

| Field | Value |
|---|---|
| **Status** | `pending` |
| **Priority** | `high` |
| **Complexity** | `low` |
| **Impact** | `high` |
| **Roadmap** | Roadmap group 4 (distribution), after T-52 — the collector for the event the surrounding items keep referencing |

**Description**
The step every nearby item points at but none tracked: promoting the Play track from the
closed alpha to production/open testing. Created 26/08/2026 by the post-cutover board sweep —
T-57 and S-18 both say "should precede the next PRODUCTION rollout", T-36 gates a public
listing, F-53 fulfils a public promise to the testers, and the Play Billing go-live is
console ops (§9-bis) — but the rollout itself had no row. Like T-36, this is a **collector**:
mostly owner ops, plus small PRs wherever a checkbox turns out to be code.

**Checklist (each box names its own item where one exists)**
- [x] **F-53 executed** (01/09/2026) — the closed test ended that day, the cutoff was settled
  (accounts created 11/08/2026 → 01/09/2026 inclusive, i.e. `families.id` up to 17) and those
  families were granted the permanent comp in the console under the note `Closed Alpha Gift`.
  The public promise of 11/08/2026 is kept; procedure and cutoff in
  [`supabase/README.md`](../supabase/README.md) §12, record in
  [`archive/phase-7.md`](archive/phase-7.md).
- [ ] **S-18 settled** — Play Data safety caught up (App interactions, the Messages call on
  F-44 notes, the §7 operator list) + the materiality call on the policy text.
- [x] **T-57 shot** (28/08/2026, Console submission 9) — the listing must not go public with screenshots of the dead Blazor
  client under the pre-U-27 visual system.
- [ ] **The landing's "no app store" framing flips with this event.** While the Play listing is
  a CLOSED test it is invisible to a visitor, so `entrelares-site`'s hero bullet *"Sem loja de
  apps"* / *"No app store"* and the install section's *"instala direto do navegador, sem loja"*
  are all TRUE — they describe the path that page offers. Public availability falsifies the
  first and leaves the second merely incomplete. Both pages already carry a **Google Play badge
  block, commented out**, whose comment says to uncomment it "when the T-38 listing is LIVE";
  that moment is this item, not T-38. Found while closing T-57 (28/08/2026), and deliberately
  NOT changed then — correct copy should not be edited early to look thorough.
- [ ] **T-36 decision** — the no-PITR/no-daily-backup risk was accepted for a closed test
  with ~12 testers; a public listing reopens that acceptance (T-36 is the dependency that
  survived every reordering).
- [ ] **Play Billing go-live** (§9-bis in [`supabase/README.md`](../supabase/README.md)) — or
  an explicit decision to launch with the store rail dark (`billing.store_enabled = false`
  shows the T-38 neutral note by design, and the web rail keeps selling).
- [ ] **The rollout itself** — promote the bundle/track in the Play Console, verify the
  public listing, record the date here and on the board.

**Justification**
The closed alpha is nearly done. Without a collector, the prerequisites live only as
cross-references inside other items' prose — which is exactly how launch-week surprises
happen (the S-15 lesson, applied to our own plan). One row makes the gate explicit and gives
the board a place to record the date the product became publicly available.

**Files affected**
- Mostly none (Play Console + Supabase dashboard ops); small PRs may fall out of S-18/T-57

### T-60 — Flutter upgrade package: SDK pin + share_plus/KGP + dependency refresh

| Field | Value |
|---|---|
| **Status** | `pending` |
| **Priority** | `low` |
| **Complexity** | `medium` |
| **Impact** | `medium` |
| **Roadmap** | Roadmap group 7 (future / low priority) — fires only on the owner's explicit decision to move the Flutter pin (locked decision: the version changes by board-recorded owner decision only) |

**Description**
Created 27/08/2026 from the owner's 2.0.0 release build: the build log carries a warning with
a real deadline — `share_plus` still applies the Kotlin Gradle Plugin, and **future Flutter
versions will refuse to build** apps whose plugins do (Flutter's built-in Kotlin migration).
Today it is noise; the day the SDK pin moves, it is a build failure. This item packages the
three things that must travel TOGETHER so none becomes a surprise:

1. **Flutter SDK pin** (`.fvmrc`, currently 3.44.7) — owner decision, recorded on the board;
   CI and every dev machine follow FVM, so the pin move is one commit plus a full gate run.
2. **`share_plus` major bump** to a release that supports built-in Kotlin (13.x already
   exists), plus whatever its platform-interface drags along.
3. **General dependency refresh** — `flutter pub outdated` lists ~18 majors held back by
   constraints (`go_router` 18, `intl`, `archive`, …). Bump deliberately, one suite run per
   cluster, never as a side effect of a release build.

**Also as a package on purpose:** upgrading the SDK re-baselines the Gradle/AGP/Kotlin
toolchain, which is what silences the `java.lang.System::load` native-access warnings the
release build prints today (they come from Gradle 9 on a modern JDK, not from our code).

**Out of scope**
- Any behaviour change riding along "while we're at it" — the gates (485+ widget tests,
  806 core, db-gate) are the acceptance, unchanged.

**Files affected**
- `.fvmrc` · `apps/entrelares_app/pubspec.yaml` + lockfiles across the workspace ·
  possibly `android/settings.gradle`/AGP versions if the SDK bump asks for them


---

### T-61 — The Google sign-in screens must say Entrelares, not the project ref

| Field | Value |
|---|---|
| **Status** | `pending` |
| **Priority** | `high` — **the owner named it a blocker for public availability** (27/08/2026, during the F-57 go-live): "vamos ter que ver uma solução para isso antes de fazer o release público" |
| **Complexity** | `low` on the decided path (**A**: a console submission, no code, no DNS, no spend) · `medium` on the fallback (**B**: ~1 session of client code + one OAuth client per flavor) |
| **Impact** | `high` (first-contact trust, on the one screen where the user hands over their identity) |
| **Depends on / relates** | **F-57** (which surfaced it), **T-59** (public rollout — this should land first), **T-40** (iOS inherits whichever path wins) |

> **Found 27/08/2026, testing F-57 on a real device.** Not a hypothesis: measured on the
> device, twice, in the two places Google names the relying party.

**The problem.** Google identifies the relying party by the **host of the redirect URI**, and
today that host is the Supabase project itself. So the consent screen reads *"Fazer login no
serviço `buroanotfjcgvbfmacuh.supabase.co`"* (`jptqbwfziyzlhlmoekzu…` in production) — and it
does not stop at the screen the user is looking at: Google then sends a summary e-mail titled
*"You shared some Google Account data with buroanotfjcgvbfmacuh.supabase.co"*, which lands in
the inbox hours later with no way to connect it back to Entrelares.

**Why this is worth spending on, in this product specifically.** The app's whole proposition
is trust between separated caregivers around a child's routine. The moment we ask someone to
hand over their Google identity is the moment that proposition is tested, and what they are
shown is a random string. A user who backs out there does not report a bug — they simply do
not sign up, and the closed alpha's own feedback (the F-57 origin) says sign-up friction is
already the product's most failure-prone stretch.

**The decision (owner, 28/08/2026): A now, B if A fails — both free.** The first analysis
proposed the paid Custom Domain add-on and recorded that "no free configuration reaches those
lines". That was wrong on both counts, and the correction is the substance of this item.

| | Path | Cost | Android | Web |
|---|---|---|---|---|
| **A** | **Google brand verification** — decided first move | zero | fixes | fixes |
| **B** | **Native sign-in** (`signInWithIdToken`) — decided fallback | zero | fixes | **does not** |
| C | Vanity subdomain (`entrelares.supabase.co`) | zero | partial | partial |
| D | Custom domain (`auth.entrelares.app`) | ~US$10/mo | fixes | fixes |

**A — why it is the first move.** Supabase's own Google guide states that Branding **and
Verification** *"show a logo and name instead of the Supabase project ID in the consent
screen"*. §9-ter.0 configured Branding and PUBLISHED the Audience — but published ≠ verified,
and verification is a separate submission with human review. So the device measurement above and
this path do not contradict each other: an unverified app showing the ref is exactly the
expected state. The app requests only non-sensitive scopes (`main.dart` passes no `scopes`, so
`openid`/`email`/`profile`), which is the light review path. **Open risk:** Google requires
authorized domains you can prove you own and infers them from the redirect URIs; if `supabase.co`
is pulled into that list the submission may be refused. That refusal — or a review that returns
with the ref still on screen — is the ONLY trigger for B.

**B — what the fallback is, and what it accepts.** Google issues an ID token to the app and
`signInWithIdToken` exchanges it for a Supabase session; GoTrue's redirect never happens, so no
host is displayed at all — the native account picker shows the app's own name, which is also
better UX than today's Custom Tab. Most of F-57 survives untouched: the `/auth/v1/settings`
fail-closed switch (the provider still has to be enabled), `OauthOnboardingScreen`,
`completeOauthOnboarding`, migration `20260827140000` and the `oauth_onboarding` /
`claim_invitation` / `joined_via_invite` gate suites all live downstream of "a Google session
exists". What changes is the body of `_signInWithGoogle`, a `google_sign_in ^7.x` dependency, one
Android OAuth client per flavor, and the manifest scheme filter becoming dead code.

> **B does not fix the web, and that is accepted.** `google_sign_in_web` reports
> `supportsAuthentication: false` and throws on `authenticate()`; the only web path is Google's
> rendered GIS button, which would put a third-party SCRIPT source in the CSP and replace the
> U-27 button with an iframe — reversing the owner decision of 23/08/2026 that fonts may come
> from a third party and executable code may not.
>
> **The positioning this rests on (owner, 28/08/2026):** Entrelares is an **Android/iOS
> product**. `web.entrelares.app` and the Asaas rail it sells through are the **alternative
> channel, deliberately not the main focus.** Write that down rather than infer it: the repo
> builds both channels to the same standard and ranks neither, so a future reader looking at the
> web gap would read it as an oversight instead of a priced trade.

**The client side — "no application code" was wrong.** It is true of A (nothing changes) but of
nothing else. B rewrites the sign-in callback; C and D each move the host, and **three files name
it**: `lib/env.dart` (`Env.prod.supabaseUrl`), `web/_headers` — whose `connect-src` wildcard
`*.supabase.co` does **not** cover `auth.entrelares.app`, and a host the CSP misses is not a
degraded login but an app that reaches no API at all — and `pubspec.yaml` for the version bump.

**C and D, kept on the shelf.** Vanity subdomains and the Custom Domain add-on are **mutually
exclusive**, so the cheap one now would buy a second host migration later with real accounts
already created. D also carries a fact worth keeping visible: activation is a hard cutover —
*"your project's third-party auth providers will no longer function on the Supabase-provisioned
subdomain"* — so the client flip and a Play promotion must ride the same window.

**Delivered (PR 1, 27-28/08/2026), before any spend:** `web_channel_test` now asserts that
`connect-src` covers the host `Env.prod.supabaseUrl` names, in both `https` and `wss`, so any
future host change is a red gate until `_headers` follows it instead of a silent outage. Plus the
runbook: `supabase/README.md` §9-quater carries all four paths, A first, with D's full ordered
procedure preserved for the day it is needed.

**Remaining:** execute §9-quater.A (console submission, then re-measure the consent screen AND
the summary e-mail on a real device). If it fails, §9-quater.B.

**Sequencing.** Doing this BEFORE the public rollout avoids a second migration of the redirect
URI while real accounts exist — a change of auth host mid-flight is the kind of thing that
invalidates in-progress sign-ins.

