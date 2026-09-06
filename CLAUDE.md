# CLAUDE.md — Project context for Claude Code

## What this repo is
**The Entrelares product app**, in Flutter/Dart, on **both channels**: the Play package
`com.entrelares.app` carries this bundle, and `web.entrelares.app` is served from here by the
Cloudflare Pages project `entrelares-web`.

It was born as the T-53 stage-1 spike (GO verdict, 19/08/2026), was built batch by batch
against the parity map ([`docs/flutter-paridade.md`](docs/flutter-paridade.md)) behind the
cutover plan ([`docs/flutter-cutover.md`](docs/flutter-cutover.md)), and **T-53 CLOSED on
23/08/2026, when both channels were cut** — the store first, because its rollback is the less
reversible one, and the web hours later. Everything that came before is history in those two
documents; what matters day to day is that **a merge to `main` reaches real users**.

**The rollback is dead, and that is the end of T-56 (24/08/2026).** The Blazor client was frozen
on 19/08 and published at `legado.entrelares.app` as the documented way back; the owner declared
that way back no longer needed the day after the cutover; the client was shut down and
`entrelares-app` is **archived** since 25/08/2026 — read-only, kept for its history. There is no way back any more, which is the ordinary consequence of a
cutover that worked: **this repo is the only client the product has**, and a merge to `main`
reaches real users with nothing behind it.

**This file is the authority.** Until 24/08/2026 it deferred to `entrelares-app/CLAUDE.md` for
the product invariants (language rules, the trailer convention, the working agreement, the
domain model, the hard-won gotchas); those sections were triaged and moved here by **T-56**,
and what stayed behind is what dies with the Blazor client — its DI scopes and `forceLoad`
navigation, the C# retry helper, the gotrue-csharp quirks, the Realtime WebSocket that never
worked in WASM, the `csproj`+manifest versioning and every Playwright gotcha. **Nothing in the
old repo needs to be consulted to work here.**

**The rule that this repo "never carries its own backlog" was REVOKED on 24/08/2026**, and
`backlog/` now lives here. It was a deliberate rule, so here is why it fell: it existed while
this repo was the T-53 spike and `entrelares-app` was the product. The cutover inverted both
roles on 23/08, and keeping the written memory of a product in a repository nobody opens is
the shortest path to losing it. The board in Notion stays the owner of status and order; the
markdown here stays the source of truth for what each item IS. The decisions, the measurements
behind them and the PR-by-PR plan are in [`docs/arquivamento-app.md`](docs/arquivamento-app.md).

**`.claude/skills/next-item/SKILL.md` §0 carries the table of what lives where** — the move
finished with T-56, so that table is now the settled layout rather than a transition; check it
before assuming a path.

## Locked decisions
| Decision | Value |
|---|---|
| Flutter | **3.44.7 (stable)** via FVM (`.fvmrc`) — same pin as desmalha/console |
| JDK | 17 |
| `minSdk` | 26 |
| `applicationId` (per flavor) | **dev = `com.entrelares.flutter`** — different from the Play package on purpose, so the dev APK coexists with the store-installed app on the owner's device. **prod = `com.entrelares.app`** (stage 0 proved the Play package accepts a Flutter build with the same upload signature). Release signing is per flavor via git-ignored `android/key.properties` (T-55): `dev.*` = dedicated sideload keystore, `prod.*` = the PRODUCT's upload keystore — never swap them; without the file, release builds fail fast (debug unaffected). |
| Structure | Monorepo: `apps/entrelares_app` (Flutter) + three pure-Dart packages — `packages/entrelares_core` (the client mirrors of the server rules), `packages/entrelares_db_contracts` (the PostgREST row shapes, which left `lib/models/` in T-56 PR 6 when the ported gate became their second reader) and `packages/entrelares_db_gate` (the database gate itself). Nothing under `packages/` may import Flutter: the gate has to run under plain `dart test`, and the contracts have to be importable by both sides. |
| Environment | Build flavors (stage 3): `dev` → project `buroanotfjcgvbfmacuh`, `prod` → production — both PUBLIC configs hardcoded in `env.dart`, selected at compile time via `appFlavor`. Every Android build requires `--flavor`; flavor-less targets (`flutter test`) fall back to dev by construction. The Supabase singleton initializes once per process, so environments are per build variant, NEVER a runtime switcher. |
| Targets | Android **and web** (batch 6, tension 1: Flutter Web replaces the PWA). The CHANNEL acceptance — first load on a mid-range Android over 4G, measured against the PWA — was **granted by the owner on 23/08/2026**, which closes the last of the three product tensions. |
| Web channel (stage 4) | **`flutter build web` accepts NO `--flavor`** — on web `appFlavor` is always null, so a flavor-only rule resolves the web build to DEV. Production says so with **`--dart-define=APP_ENV=prod`**, and `web_channel_test` fails the build if that define (or `--no-web-resources-cdn`, which keeps CanvasKit on our own origin) leaves the workflow. Published by the `deploy-web` job of `verify.yml` to Cloudflare Pages project **`entrelares-web`**, behind `needs: verify`, only from `main`, and self-disarming while the CF secrets are absent. Everything in `apps/entrelares_app/web/` is copied verbatim into the build — including `.well-known/assetlinks.json` (the App Link of the INSTALLED app is verified against this host) and `service-worker.js`, which is the **tombstone** of the Blazor PWA's worker: the only thing that reaches an installed PWA is the browser's update check of that exact URL, so the file must never be deleted while a device may still carry the old worker. Since T-62 the directory also carries `firebase-messaging-sw.js` (the push worker, at its own scope) and the vendored `firebasejs/<version>/` — see the Push row. |
| Billing | **Two rails, decided by the BUILD** (T-48 redesign, lote 5). The web target sells through the Asaas rail (`billing.enabled`, live in production since 29/07/2026); Android sells through **Play Billing** behind its own switch `billing.store_enabled`, which is PUBLIC and starts `false`. While it is false — or the device has no store, or no product comes back — the store branch shows the **T-38 neutral note**, which is also the fail-closed default. The **store price is Play's** (the product carries it; `app_settings` prices rule the web rail only), and **the client never grants Premium**: the purchase token goes to `billing-store-verify`, which asks the Play Developer API, and the acknowledge to Play happens only after the server accepted. Product ids `premium_monthly`/`premium_annual` are pinned by test — renaming one orphans real purchases. Go-live is console work: [`supabase/README.md`](supabase/README.md) §9-bis. |
| Visual system | **U-27 (20/08/2026)**: `apps/entrelares_app/lib/theme/tokens.dart` is the ONE place a colour may be written — `no_color_literal_test` fails the build on a `Color(0x` anywhere else in `lib/`. Both themes are hand-written (never `ColorScheme.fromSeed`: seeding tints the greys with the brand indigo and kills the neutral identity), and **dark ships with the tokens**, following the system — a user-facing switch is U-12's. Colour is never the only vector: each calendar slot carries a `SlotPattern` texture too, and the swapped day is amber with a dashed border (web parity), which is what freed the rose `#E11D48` to be a role again. The eleven shared components live in `apps/entrelares_app/lib/widgets/ui/` (barrel `ui.dart`) and encode two conventions: the action pair puts the CONFIRMATION FIRST (the Blazor order — parity with the muscle memory people arrive with) and every field carries a permanent label, which is how WCAG 1.4.11 is met without a heavier border. Loading states are SKELETONS wherever the shape of what is coming is known; a spinner survives only for a button mid-press, a determinate bar, and a wait with no shape (splash, payment return). Type is **Inter**, four static weights subset to `latin` (~96 KB gzip), regenerable with `apps/entrelares_app/tool/subset_inter.py`; the PDF keeps Roboto on purpose (F-33). |
| Push (F-09) | **FCM, hung off the SINGLE WRITER.** Every push-worthy moment already writes a `notifications` row, so an `AFTER INSERT` trigger on that table (pg_net → `send-push-notification`) is the dispatcher — push, in-app and e-mail are three renderings of ONE event, and a future writer gets push for free. **Ten types only**, and the rule is "push only what the recipient did NOT just do" (the self-receipts and the F-28 fan-out are out, pinned by test). The text is rendered **server-side** per recipient (`_shared/push.ts`), because a push has no device to render on and iOS does not guarantee a data-only message — that duplication of the Dart catalog is deliberate and gated by `push_notification_mirror_test`. `push_subscriptions` is the **only table that is not family-scoped**: a token is the capability to interrupt someone's phone. Armed per environment by Vault secrets + `FCM_SERVICE_ACCOUNT` (runbook §11) and **self-disarming without them**. Android is live; iOS rides T-40. **The WEB channel is built (T-62) and ships DARK**: everything server-side was already platform-agnostic, so the item is a client one — `push_messaging_web.dart`, a worker of its own, and the Firebase JS SDK **vendored** under `web/firebasejs/<version>/` because `firebase_core_web` fetches it from gstatic at runtime and this channel's CSP forbids third-party executable code (`tool/vendor_firebase_js.py`; re-vendor when the plugin's `supportedFirebaseJsSdkVersion` moves — a red gate, not a console warning). Three workers share the origin and none contends: the Blazor tombstone and Flutter's shell at `/`, FCM's at `/firebase-cloud-messaging-push-scope` — which is why the transport passes `serviceWorkerScriptPath: null`, since FlutterFire would otherwise register it over the app shell. The SDK is loaded LAZILY, so first load costs +10 KB gzip and a person who never enables push fetches none of it. Two web-only traps are pinned by test: `getToken` opens the browser prompt by itself when the permission is `default` (so `token()` reads the permission first — `PushService.start` must never prompt), and the tap never reaches Dart (`onMessageOpenedApp` has no web implementation), so `PushRouting` is mirrored in the worker. Go-live is console work: [`supabase/README.md`](supabase/README.md) §11-bis. |
| Analytics | T-37 via Umami Events API. The website id is PUBLIC and per environment: **dev is empty on purpose** (every call becomes a no-op, so QA never pollutes production statistics); prod carries the product's site. No PII ever — the sanitizer is a pure mirror with its own suite. |

> **Owner directive (18/08/2026), still standing:** parity is the floor, not the ceiling —
> where Flutter offers a natural improvement over the Blazor behaviour (native Realtime instead
> of the F-23 poll, month swipe, native bottom sheet, pull-to-refresh, haptics), take it. The
> improvement is UX/platform only, never a rule change.

## Language conventions
- **UI text, notifications, e-mails: PT-BR.** Code, comments, docs, file names and **titles**
  (including backlog record headings): **English**. Bilingual display per reader is U-13/U-24 —
  the catalogs decide what the user sees; the wire format never changes with it.
- **Commit messages: PT-BR**, conventional-commit style (`feat(calendario): …`).
- **Every commit that DELIVERS a backlog item ends with the trailer `Backlog: <ID>`** (several
  comma-separated). That trailer is the ONLY mark meaning "this commit delivers this item":
  mentioning an ID in prose stays free and never counts, so a message can say "reusa o fluxo de
  convite (F-15/F-28)" without polluting those items' history. *Why it exists:* before it,
  linking commits to items meant guessing from prose, and both guesses failed — "ID in the
  subject" hid ~70 genuine deliveries from Phases 1–2, while "any mention counts" credited items
  for commits that merely cited them as background.
- **The trailer does NOT survive an API or CLI merge on its own.** GitHub pre-fills the squash
  message from the PR body on the **web merge button only**. Through the REST API or
  `gh pr merge --squash`, GitHub builds the message from the branch commits instead and the
  trailer is silently dropped — it happened twice (F-42) and was rescued only by the subject
  heuristic this convention exists to replace. So an API/CLI merge MUST pass `--subject` **and**
  `--body`, with the trailer as the body's last line.
  **Put `(#N)` in the subject too**, the way the web button does: `tool/notion_mirror.py`
  extracts the PR number from the subject's trailing `(#N)`, and a squash without it delivers the
  item but cannot link its PR (T-56 #57 lost exactly that, 24/08/2026).
  **Verify right after merging — it costs one command:**
  `git log -1 --format='%h %s%n%(trailers:key=Backlog,valueonly)'`.
- **Finding/sub-item IDs must never start with a backlog prefix** (`F-`/`U-`/`T-`/`S-`/`L-` +
  two digits). The T-32 findings were `F-32-1…5` and every ID reader matched them as the feature
  **F-32**, mis-attributing effort and commits; they are `T32-A1…A5` now.

## Working agreement
- **Per item:** detailed analysis + gap questions (AskUserQuestion) BEFORE any code; once the
  decisions are locked, implement with tests, commit and push to the session's work branch.
  **PR + squash-merge only with the owner's explicit OK — never automatic.** Big items split into
  2–3 incremental PRs, each carrying its own docs/backlog close-out inline.
- **Standing exception:** a RED CI gate fixed by correcting the TESTS (flaky, rate-limit, wrong
  assertion — no behaviour change) may be merged directly, without waiting for the OK.
- **One scope per session**, and end each session with a summary block for the board.
- Since the cutover there is **no QA branch**: a merge to `main` publishes production. The QA
  that used to happen after the merge has to happen BEFORE it — on the PR's green gate, and on a
  dev-flavour build when the change needs a real device.

## Domain model
- `scheduled_parent` = planned responsible; `actual_parent` = the real one after a swap.
- Swap/revert requests are **two-party**: the approver is always the non-requester, and a day
  with a pending request is **frozen**. Scenario B (the requester proposes THEMSELVES on the
  target's day) makes message texts branch on `targetIsProposed`. Scenario C (a third caregiver
  proposing someone ELSE on another member's day) is **forbidden by design** (F-28) — that single
  rule is what keeps every two-party message text valid with N caregivers; relaxing it breaks
  them all.
- A member with `left_at` set is **frozen** (S-11): profile immutable, never assignable to a day,
  holds no seat — enforced by DB triggers; the UI only mirrors it.
- Every profile belongs to a **family** (RLS is family-scoped via `get_my_family_id()`);
  `is_admin` is per family, and the "≥1 admin" invariant is a DB trigger.
- **Urgency is never stored**: none/URGENTE/ATRASADO is computed from
  `schedule_date + (handoff ?? 00:00)` against now (pending) or `resolved_at` (history). The Edge
  Function mirrors the same rule in `America/Sao_Paulo`.

## Product invariants
- **The client MIRRORS, the database ENFORCES.** RLS, SECURITY DEFINER RPCs, sudo S-10
  (`ELEVATION_REQUIRED:` marker) and the T-33/T-35 concurrency guard (`revision` +
  `revision_token`/`submitted_token` echo) are the security. Never "protect" in the client.
- **Dates on the wire are ISO 8601** (`yyyy-MM-dd`); display formatting is client-side and per
  reader language (U-24). Translating a screen must never change the wire format.
- The client never writes to other profiles, to `families` or to `family_invitations` directly —
  **SECURITY DEFINER RPCs only** (`set_member_admin`, `rename_family`, `create_invitation`, …).
- Notification INSERTs use minimal return: RLS blocks selecting the other user's row back.
- **Day protections are database rules** (past days immutable, frozen days locked, actual-parent
  changes only through the workflow), with an explicit admin-mode bypass. Never add a UI shortcut
  around the workflow.
- **The T-27 transition rule is a DB rule too:** a `handoff_time` only survives on a day whose
  effective responsible differs from D-1's. Two triggers on `care_schedules` do it — a BEFORE one
  that parks a removed time in `handoff_time_backup` and gives it back when the day becomes a
  transition again, and an AFTER one that re-evaluates D+1. The client copy exists to WARN
  upfront, never to enforce — keep the two saying the same thing.
- The audit trail (`activity_logs`) is **append-only and written by trigger only**; its
  `old_data` snapshots are what power revert-restore (F-26).
- The role catalog is the single client-side source of role vocabulary. Seed data differs across
  environments (`Pai`/`Mãe` vs `father`/`mother`) — always match through the catalog.

## Legal pages (Privacy & Terms) — cross-repo sync (MUST)
The app links the **landing's** legal pages (`entrelares-site`); there is ONE copy of the legal
text and it opens in the browser (lote 4 decision). Any change to policy/terms **content** must be
mirrored on both sides **in the same delivery** — mirror the *substance*, not line for line.

**A material change BLOCKS the whole user base (S-15/B-4), so it is four things in ONE delivery:**
(1) `PolicyVersions.current`; (2) `enforceFrom` = *the date the text becomes VISIBLE to users* +
15 days — that is the PRODUCTION publish, not the merge, because the notice exists so people can
read the text before losing access; (3) the matching `policy.current_version` **and**
`policy.enforce_from` rows in `app_settings`, via migration; (4) an entry in the change summary
the screen renders. **Miss (3) and the RPC refuses every accept in production** — users are told
to update an app that is already current and nobody gets through. The integration tests that
compare each constant against its server setting are the red gate that replaces a live lockout;
never weaken them. **A non-material edit must NOT bump the version** — it would drag the whole
base through a blocking screen for nothing; only the "Última atualização" date moves.

**The S-15 lesson, which cost three rounds of legal opinion: check every sentence against the
CODE before publishing it.** One finding happened because the briefing quoted our own policy
("the only child datum is the first name") instead of the database, where no child field exists
at all. Applying that check to counsel's own approved wording then caught a promise with no
implementation and a disclosure that named less data than the system actually stores. Legal text
is a claim ABOUT the system, and an unverified claim is a liability no matter who drafted it.

## The board, and what effort means
The Notion board owns **status, roadmap order and effort**; the markdown in `backlog/` owns
**what each item IS**. Regenerate a page body with `python tool/notion_mirror.py` and push it with
`replace_content` — never hand-edit a body in Notion.

`Esforço gasto (h)` measures **elapsed time between merges** inside a working session, never time
at the keyboard: squash-merge collapses a whole PR into one timestamp. **Use it to compare items,
never as a timesheet.** It was long described as understating "systematically", and that stopped
being true on 24/08/2026 when the mirror learned to read every repo: an item that collects every
commit of its stage also collects the gaps between them, so a densely-delivered item now
OVERSHOOTS (T-53: 10,4 h → 28,0 h, against ~14 h of real work). The ranking is what improved and
what the number is for — U-28 went from 89th to 3rd. Retuning the three constants would move all
180 items to chase an absolute this line already says not to trust, so it was deliberately not
done (owner, 24/08/2026).

## Gotchas (hard-won) — database & platform
These survived the rewrite because none of them is about the client language.

- **An UPDATE the client is not allowed to make does NOT throw — it matches 0 rows.** With no
  UPDATE policy, PostgREST answers success and changes nothing, so "expect an exception" passes
  for the wrong reason and fails for the right one. **Assert the ROW IS UNTOUCHED** instead
  (re-read it with the service client). One suite carried this comment and a sibling walked into
  it anyway — read the neighbouring suite's assertions before writing new ones against the same
  table.
- **`anon` reads NOTHING, so a health ping needs `service_role` in BOTH headers.** The app is
  100% RLS-locked: `anon` has no SELECT even on reference tables, so an anonymous PostgREST read
  returns **401**, never `200 []`. And PostgREST derives the DB role from the JWT in
  `Authorization: Bearer` — `apikey` alone is only the Kong gate and still runs as `anon`. With a
  NEW-format key (`sb_secret_…`) it is the opposite: `apikey` ONLY, because it is not a JWT and
  the platform rejects it on `Authorization`. Handling both shapes is what lets a key be rotated
  without a red window.
- **`CREATE OR REPLACE` of a shared trigger function: start from the LATEST body, not the one you
  remember.** `enforce_day_protection` has been rewritten in full by eight migrations. Copying an
  old version to add one line silently deleted three later rules — no error, seven red tests.
  `grep -n 'FUNCTION public.<name>' supabase/migrations` first; the newest file wins.
- **A role check inside a `SECURITY DEFINER` function reads the OWNER, not the caller.**
  `current_user` there is always the function's owner, so a guard like `IF current_user =
  'authenticated'` never fires, silently. `auth.role()` is not the fix either — it reads the JWT
  claim, so a SECURITY DEFINER RPC called by an end user still reports `authenticated`. To tell a
  PostgREST end user apart from a server-side flow the function must be **SECURITY INVOKER** and
  test `current_user`.
- **API keys and the JWT signing key are two INDEPENDENT migrations (S-16)**, and conflating them
  is what made the July 2026 incident look unfixable. Legacy `anon`/`service_role` are JWTs signed
  with the project's JWT secret; `sb_publishable_…`/`sb_secret_…` are not JWTs and are validated
  by the gateway. Rotating the SIGNING key (HS256 → ES256) breaks the legacy keys *because* they
  are signed with the secret it replaces. So the key migration is the prerequisite, not a
  companion. **Emergency fix while any legacy key remains: roll the signing key back.** Edge
  Functions read the key sets by NAME and **fail without them**, so new keys must exist on a
  project BEFORE CI redeploys its functions.
- **`send-auth-email` is the one function with no fallback behind it.** With GoTrue's Send Email
  Hook enabled, GoTrue stops sending — a break there means nobody confirms a sign-up or recovers
  a password. It is also authorized differently: the hook calls it with no JWT and no key, signing
  the body with the Standard Webhooks scheme, so the signature IS the authorization and the
  project's own keys must NOT open it. GoTrue gives the hook a **fixed 5 s**, and a cold start
  after a redeploy has exceeded it — which is why the deploy pipeline warms the isolate with an
  empty POST.
- **An Edge Function must be redeployed whenever its templates or payload change** — an outdated
  copy silently sends zero e-mails.
- **A Resend API key can be BOUND to one domain and dies with that domain**, and the sending
  allowance is per ACCOUNT — the test suite once spent production's.
- **Integration seeds hit UNIQUE `(family_id, schedule_date)`**, and a CI run cancelled by a
  concurrency group dies before its teardown, leaving fixed-id seeds behind for the next run to
  collide with. The suite deletes those seeds before creating them, and the orphan sweep spares
  anything younger than 2 h so parallel runs do not eat each other.
- **A `cancelled` `db-gate` is usually an EVICTION, not a verdict.** The job holds a repo-wide
  serialized group (`concurrency: db-gate`, `cancel-in-progress: false`), and that `false`
  protects the job that is RUNNING — not the one waiting. GitHub keeps exactly ONE pending entry
  per group, so a third claimant drops the queued one. Read it off the shape: an evicted job
  reports `cancelled` and comes back with **no `steps` array at all**, because it never started.
  The response is to let the group drain and re-run THAT run — never to cancel somebody else's to
  get ahead. It does not need two people, either: pushing three times in quick succession to one
  branch is three claimants (25/08/2026 — seven pushes on one PR, and three evictions measured in
  an hour the same day). The serialization itself is load-bearing and must not be scoped per ref:
  the T-39 billing seeds use FIXED external ids, so two overlapping runs delete each other's rows
  — which is the gotcha directly above. Only the queue DEPTH is the flaw, and the real fix, if it
  is ever worth it, is to give those seeds a run scope like the `evt_e2e_*` events already have.
- **A ported mirror keeps its logic, not necessarily its INPUT format — and the test that
  encodes the old format passes while production never matches.** `translateSaveError` was
  ported from the Blazor helper, where the exception's text WAS the raw PostgREST JSON body, so
  it started by hunting for `{`. In Flutter the input is `PostgrestException.toString()`, a
  formatted Dart string with no JSON in it: `indexOf('{')` returned -1 for every real refusal,
  and every DB-raised rule — seat caps, admin-only, day protection, "this e-mail already has an
  account" — surfaced as the generic "check your connection", the product blaming the user's
  network for a rule the server had explained. Green suite throughout, because the tests fed
  hand-written JSON. **When porting a parser, assert against a string captured from the NEW
  platform, never one written from the old contract** (27/08/2026, found by sending one
  invitation on a real device).
- **A fake data source that REIMPLEMENTS the method under test is evidence about the fake, not
  about the code it replaces.** `fetchFrozenRequestsForMonth` gave up on a whole month, before
  touching the network, once that month's LAST day was past — so a request pending across the
  turn of the month vanished from the calendar overnight, taking the ⏳/🔔 badge, the frozen-day
  panel and the resolve sheet's count with it, while the row sat untouched in the database. The
  suite was green throughout: `FakeCustodyDataSource` writes its own version of that method,
  without the guard, so 524 passing tests described a calendar nobody had. **When the defect
  lives in a CONCRETE data source, the regression test has to drive THAT class** —
  `SupabaseClient(url, key, httpClient: MockClient(...))` costs nothing, and asserting the
  request actually went out is what the fake can never do. (01/09/2026, found in production by
  the owner on a request for 31/08; `frozen_month_window_test.dart`.) The sibling lesson is the
  bullet above: both are a test that agrees with the code it was written from instead of with
  the platform the code runs on.
- **An Android notification channel that does not exist swallows the notification, silently.**
  On Android 8+ a push whose payload names an unknown `channel_id` is dropped by the SYSTEM with
  no error: FCM reports delivery, the Edge Function logs success, and nothing appears on the
  phone. Every layer says it worked. The channel (`entrelares_swaps`) is created in
  `MainActivity.onCreate`, not from Dart, so it exists before a message can arrive at an app that
  is not running; creating a channel is idempotent, so doing it on every launch costs nothing and
  removes the ordering question (F-09, 29/08/2026).
- **Android draws a notification's small icon as a SILHOUETTE.** It keeps the alpha channel and
  throws the colours away, so an app that declares no notification icon gets its full-colour
  launcher icon flattened into a featureless blob. Declare
  `com.google.firebase.messaging.default_notification_icon` (white glyph on transparency, one
  file per density) and `default_notification_color`, or the brand arrives on the phone as a
  white circle (F-09, found on the first device round, 29/08/2026).
- **An upsert's conflict branch is an UPDATE, and RLS judges it by the row that is ALREADY
  there.** `INSERT … ON CONFLICT DO UPDATE` looks like one statement with one policy behind it;
  it is not. When the conflicting row belongs to someone else, the UPDATE policy's `USING` is
  evaluated against THAT row, fails, and Postgres answers `new row violates row-level security
  policy (USING expression)` — the `(USING expression)` suffix is how you tell this apart from a
  plain `WITH CHECK` refusal on an INSERT, and it is worth grepping for by name. It cost a day
  of production on F-09: the app upserted a device token on `onConflict: 'token'` to move a
  handset between accounts, which is a normal thing for one family sharing one telephone, and
  every attempt was refused. **If a write must legitimately displace another profile's row,
  neither the client nor the policy can do it** — clear the old row from a `SECURITY DEFINER`
  trigger or RPC, so the INSERT stands alone and its `WITH CHECK` still applies (29/08/2026).
- **A test that asserts the refusal of a statement the app never sends is green about nothing.**
  The db-gate pinned that a plain INSERT of a token held by someone else is rejected — correct,
  and beside the point: production sends an UPSERT, whose failure mode is the gotcha above and
  which no suite touched. This is the `translateSaveError` trap in a second language six days
  later, so it is the pattern and not the incident that matters: **write the gate against the
  CALL the product makes** — copy the statement out of the data source, don't paraphrase it into
  the shape that is easiest to assert (F-09, 29/08/2026).
- **"Does this profile have a device?" and "is THIS device registered?" differ on the second
  device, and only there.** F-09 asked the first and meant the second: a second handset found a
  row belonging to the first, concluded the work was done, never registered itself, and showed
  the control as `on` while the server had never heard of it. The same confusion made sign-out
  unregister nothing — the token was never read on a session that had nothing to repair, and the
  handset stayed pointed at the account that had just left. **Anything keyed to a device must be
  keyed to that device's token**, on the query and in the field the sign-out path reads.
- **A test that picks a date as `now + N days` breaks on the last N days of a month.** The
  calendar grid renders the CURRENT month only — blanks, then `1..daysInMonth`, with no tail of
  any neighbour — so a target that rolls into the next month resolves to the same day NUMBER in
  this one, which is a PAST day, which opens the sheet in read mode. The E2E lane went red on its
  own at 00:00 UTC on 29/08 with `Bad state: No element` on a chip finder: a symptom that names
  the widget and hides the cause entirely. It has now happened twice in this product (the Blazor
  `BulkUiTests` month-shape failure was the first). **Navigate to the target's month; never pass
  a bare day number.** And when a lane goes red on a change that cannot explain it, re-run the
  last GREEN sha before reading any code — it separates "my change" from "the calendar" in one
  command.
- **An SDK call named "get" can spend a one-shot resource.** The Firebase JS SDK's `getToken`
  calls `Notification.requestPermission()` itself whenever the permission is still `default` —
  it is a read on the native side and a WRITE on the web. `PushService.start` reads the token on
  every authenticated session precisely because that is supposed to be free, so the naive port
  of the web transport would have asked every returning visitor for notification permission at
  page load, with no gesture and no context, spending on a boot the one prompt the product means
  to spend on a press. The fix is one line — read `Notification.permission` and return null
  unless it is `granted` — and the point is the habit: **before reusing a cross-platform seam,
  read what the new platform's implementation DOES, not what the method is called.** Nothing
  about this is visible from Dart, and no suite would have caught it (T-62, 06/09/2026;
  `web_channel_test` now pins the guard's position in the source).
- **A vendored ESM bundle keeps its own dependency's ABSOLUTE url.** Copying
  `firebase-messaging.js` off gstatic to serve it from our own origin looks complete and is
  half a copy: its first bytes are
  `import{…}from"https://www.gstatic.com/firebasejs/<v>/firebase-app.js"`, so the vendored file
  still fetches the other 100 KB from the origin the whole exercise existed to avoid. The
  rewrite is one `replace`, and `tool/vendor_firebase_js.py` **exits non-zero** if any gstatic
  reference survives it, because the failure would otherwise appear only in a CSP refusal, in a
  browser console, at the moment a real person enabled push (T-62, 06/09/2026).
- **Supabase CLI on Windows:** `db dump -f` resolves against the CLI's own cwd — dump to a bare
  filename, then move.

## The eight paid-for lessons (pilot `entrelares-console` — each was a real defect)
1. Restored session ≠ live session: gate app open with `refreshSession()` BEFORE routing;
   failure → `signOut(scope: local)` + "sessão expirada". Add an `onAuthStateChange`
   listener that returns to login when the session dies mid-use.
2. Without a valid session the client is `anon` (zero privilege, 100% RLS) — map
   `42501` / `permission denied for function` to "Sessão expirada" centrally.
3. `signOut()` with a dead token THROWS → catch, fall back to `SignOutScope.local`,
   navigate ALWAYS.
4. `refreshSession()` best-effort before sensitive operations; propagate the server's own
   error text (`FunctionException.details['error']`), never collapse failures.
5. **`INTERNET` permission is missing from `src/main/AndroidManifest.xml`** in the
   `flutter create` template — release APK gets no network, looks like DNS. Already fixed
   here; first thing to re-check on any new Flutter module.
6. Debug keystore is per machine — create the real keystore early, outside the repo.
7. `--split-per-abi` for direct distribution (~18 MB arm64 vs ~52 MB universal); `.aab`
   for Play.
8. Supabase singleton initializes once per process → environments via flavors (see table).

## Build & test
```
cd packages/entrelares_core && fvm dart analyze --fatal-infos && fvm dart test
# Nesse lane moram os seis ESPELHOS (test/mirrors/, T-56 + F-09 + T-62): rótulos
# de papel em inglês, formato de data dos e-mails, a chave `lang` do redirect de reset,
# a cobertura de `params` de todo writer de notificação, o catálogo de push
# (F-09: o texto do push é montado no servidor, então `_shared/push.ts` duplica de
# propósito um subconjunto do catálogo Dart — o espelho compara string por string nas
# duas línguas e exige que o filtro do trigger e o `PUSH_TYPES` nomeiem os mesmos tipos),
# e o roteamento do toque na web (T-62: o clique numa notificação é tratado pelo SERVICE
# WORKER, que não chama Dart, então `firebase-messaging-sw.js` reespelha `PushRouting` —
# o espelho compara os dois lados para TODO tipo pushável, porque errar aqui abre a aba
# errada sem erro nenhum). Cinco leem
# supabase/functions/_shared/i18n.ts e supabase/migrations — as duplicações que
# existem de propósito porque Deno não chama Dart; o sexto lê um service worker, pela
# mesma razão em outra linguagem. Um espelho que ninguém confere
# apodrece calado, e é o lane mais barato do run.
cd packages/entrelares_db_contracts && fvm dart analyze --fatal-infos
cd apps/entrelares_app && fvm flutter analyze && fvm flutter test
# The two source gates live in that suite: no_literal_snack_test (catalog strings)
# and no_color_literal_test (U-27 — colours only in lib/theme/tokens.dart).
cd apps/entrelares_app && fvm flutter build apk --debug --flavor dev --split-per-abi
# Canal web: os dois flags NÃO são opcionais — sem o define o build aponta para o
# banco de QA, e sem o --no-web-resources-cdn o CanvasKit vem do gstatic.
cd apps/entrelares_app && fvm flutter build web --release --no-web-resources-cdn --dart-define=APP_ENV=prod
# Gate de banco (247 testes de RLS/RPC/trigger contra o projeto dev), Dart puro
# desde o PR 16 do T-56. Exige a service_role do DEV — nunca a de produção. Sem
# ela a suíte aborta com instruções em vez de rodar pela metade.
cd packages/entrelares_db_gate && fvm dart analyze --fatal-infos
cd packages/entrelares_db_gate && E2E_SUPABASE_SERVICE_ROLE_KEY=<chave dev> fvm dart test
# Gate de fluxo na web: os MESMOS arquivos integration_test/ num Chrome headless.
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
1. Secrets never enter the repo. `env.dart` carries only PUBLIC client config (same as the
   web app's `appsettings.json`); the anon key has zero privilege by construction (T-44).
2. Every pure rule lives in `packages/entrelares_core` with `dart test` coverage — the
   same mirror-test philosophy as the app's C# helper suites. The app package only
   orchestrates and presents.
3. Flutter version changes only by explicit owner decision recorded on the board.
4. One scope per session; end each session with a clear summary block for the board.
