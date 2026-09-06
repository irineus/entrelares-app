# Archive — Phase 7 (Public Availability & Product Depth)

Implementation records of items completed in Phase 7, opened **03/08/2026** with the `v1.7.0`
promotion — the release that closed Phase 6 and emptied roadmap group 1 ("Ligar o lançamento
pago"), leaving the paid launch complete in code AND configuration (billing has been charging
in production since 29/07/2026).

The phase covers what the execution queue holds next:

- **Group 2 — public-availability gate: closed out.** **S-16** (`1.7.1`, the first item of the
  phase: the stack left the legacy static keys, so promoting ES256 became a scheduled runbook
  step instead of a recurring incident) and **T-35** (`1.7.2`, the concurrency token stops being
  guessable) shipped here; the two items left — T-36 (Supabase Pro upgrade) and the S-17 key
  cleanup — are owner ops waiting on revenue and on the HS256 grace window, and were moved to the
  new **group 8 · Início da monetização** (owner, Aug 2026), which makes explicit that additional
  platform spend waits for income.
- **Group 3 — swap-workflow & reports depth:** **F-44 (requester message + approval note,
  delivered `1.7.3`/`1.7.4`)**, **T-45 (next-day handoff consistency, delivered `1.7.5`)**,
  **F-45 (notifications ↔ swap requests ↔ audit log + PDF enrichment, delivered
  `1.7.6`/`1.7.7`)**, **U-20 + U-07 (projected balance with accepted future swaps +
  per-caregiver swap split, delivered together in `1.7.9` — same cards, same PDF section)** and
  **F-47 (the reversion asks whether to restore the day observation, `1.7.10`)** — the group is
  now **empty**, and execution continues at group 4.
- **Group 4 — distribution:** opened with **F-48 (checkout trust signals, promotional launch
  pricing, paywall funnel, Pix avulso — `1.7.11`/`1.7.12`, same delivery as the landing's
  L-14)**; its CNPJ/company-identity half was carved out to the new pair **F-49/L-15**
  (group 8 — waits for the company to exist). **T-38 (Android TWA wrapper + Google Play
  listing, `1.7.14`/`1.7.15`)** delivered the repo half of the store presence — maskable
  icons, store manifest, Digital Asset Links, the Bubblewrap runbook and the store-shell
  detection that swaps the paywall for a neutral state (Play payments policy) — with the
  listing itself continuing as owner ops per `store/README.md`. **F-58** (`1.8.8`–`1.8.12`)
  then gave the product its first PLATFORM role — the operator — with the console living in a
  separate Flutter app (`entrelares-console`) so no operator code ships in the public bundle;
  it unblocks F-53, whose promise of permanent Premium for the closed-alpha testers now has a
  mechanism to fulfil it.

Conventions and the forward plan's rationale: [`../README.md`](../README.md). The authoritative
status and execution order of pending items is the [Notion board](https://app.notion.com/p/3ae2f3f4b9b28169acd9e642ad4760aa)
(`Grupo roadmap` + `Ordem`); this file receives the record when an item CLOSES.

---

### T-45 — Next-day handoff consistency on swap approval/revert (T-27 invariant)

| Field | Value |
|---|---|
| **Status** | `done` (`1.7.5`) |
| **Priority** | `medium` |
| **Complexity** | `medium` |
| **Impact** | `medium` |

**Description**
The T-27 rule ("a handoff time belongs only on a transition day") was enforced **only looking
backwards and only on manual saves** (day editor, bulk, wizard — all compare against D-1). No
resolution path ever touched day **D+1**: `SwapRequestService.ApproveAsync`, the
`auto_approve_expired` RPC and the revert restore all update the single row of day D. So an
approved swap that made D+1's responsible equal to D's new effective responsible left D+1 with
a **handoff time on a day where nobody hands the child over** — and reverting could not put it
back, because nothing recorded that it had been removed.

**Design decisions (locked with the owner before implementation)**
- **The rule lives in the DATABASE**, as the project's precedent (V008) says it should. What
  settled it was not symmetry but a blocker: a client-side clearing of D+1 is REJECTED by
  `enforce_day_protection` exactly in the interesting cases — D+1 frozen by its own pending
  request, or a past day under an admin correction — because the approver is not that day's
  `is_target`. One DB rule covers the client approval, `auto_approve_expired`, the revert
  restore, admin corrections and the F-25 bulk in one place.
- **The removed time is PARKED, not destroyed** (`care_schedules.handoff_time_backup`), instead
  of reading it back from the audit log as the item originally proposed. The log route means
  guessing WHICH entry was the cascade's own clearing and risks resurrecting a time the family
  deleted on purpose; a parking slot is the value itself, deterministic, and correct for paths
  that never had a swap request to hang a reference on (bulk, admin, wizard).
- **The cascade re-evaluates the day itself as well as D+1.** Bulk approvals (F-25) resolve
  several days in one batch, and with a next-day-only rule the order of resolution decides
  whether a day in the middle of the batch keeps a stale time. Evaluating the written row
  against D-1 in a BEFORE trigger costs one indexed lookup and removes the ordering question.
- **Inverse case: nothing** (owner). A swap that CREATES a transition at D+1 leaves its
  handoff time NULL — there is no time to invent, and a day without one is an ordinary state.
- The client keeps its own copy of the rule (`CalendarHelpers.IsTransitionDay`, extracted here
  and used by the editor's live hint and its save): the user must be told upfront, not have
  the server silently rewrite what they just saved.

**How it works**
- `trigger_d_apply_handoff_transition_rule` (BEFORE INSERT/UPDATE) compares the row against
  D-1. Non-transition + a time → park it and clear; transition + no time + something parked →
  give it back. An explicit write of `handoff_time` is the writer's INTENT and drops the
  parked value, so a time cleared by hand is never resurrected. The column is server-owned
  (the trigger overwrites whatever a payload sends — same stance as T-35's `submitted_token`).
- `trigger_d_sync_next_day_handoff` (AFTER INSERT/UPDATE/DELETE) touches D+1 when a day's
  effective responsible changes, letting the BEFORE trigger decide — and touches nothing when
  D+1 would not change, so the audit trail gains no no-op rows. The recursion stops by
  construction: the cascade writes `handoff_time`, never the responsible.
- The cascade announces itself with the transaction-local GUC `app.handoff_cascade`, which
  `enforce_day_protection` waves through (same shape as the S-11 deletion context). Both
  functions are `SECURITY DEFINER` owned by `postgres`, which is also what carries the
  internal UPDATE past T-35 — that guard exempts by ROLE, and inside a definer function
  `current_user` is the owner.
- The migration ends with a one-off backfill of days that were already inconsistent.

**Trap this delivery hit (worth the next reader's time)**
`enforce_day_protection` has been rewritten in full by **eight** migrations (S-09, S-11 ×2, the
QA clear rule, F-39, T-41, F-40). Copying "the" body to add one line took the S-09 version, and
`CREATE OR REPLACE` silently deleted the departed-member block, the planning horizon and the
tier-aware past-day override — seven integration tests caught it. Always start from the LATEST
definition, not the one the item's own history points at.

**A latent test landmine surfaced (fixed here).** `OptimisticConcurrencyTests` seeded family A's
days at fixed offsets (today+31…+34) while every other test draws from the fixture allocator,
which starts at +11 and marches upward. The eight extra dates this item allocates pushed the
allocator into those four, and `AdversarialTests.CrossFamilyCareSchedule_IsNotReadable` — which
asserts family A sees ZERO rows on "a date it never used" — failed in the full run while passing
alone. The suite had been one delivery away from this for months; the seeds now use
`fx.NextFutureDate()`.

**Tests**
- Integration (`HandoffTransitionTests`, 5 cases, all through the real write paths): approval
  applied by the request's target clears D+1; the revert gives the time back; the
  `auto_approve_expired` RPC does the same server-side; a D+1 that stays a transition is
  untouched; an explicit new time outranks the parked one.
- Unit (`CalendarHelpersTests.IsTransitionDay_…`): the extracted client mirror of the rule.
- No new E2E: the effect is data, not a visible flow, and the existing `PlanningUiTests`
  T-27 cases (hint clears the time / a real transition persists it) already assert the
  behaviour the DB rule now also guarantees.

**Files**
- `supabase/migrations/20260804160000_t45_next_day_handoff.sql`
- `SharedParentalCustody/Helpers/CalendarHelpers.cs`, `Pages/Home.razor`
- `SharedParentalCustody.Tests/CalendarHelpersTests.cs`
- `SharedParentalCustody.IntegrationTests/HandoffTransitionTests.cs`,
  `E2EFamilyFixture.cs` (`NextFutureDates`), `OptimisticConcurrencyTests.cs`

---

### F-44 — Requester message on swap/revert requests (+ optional approval note)

| Field | Value |
|---|---|
| **Status** | `done` (`1.7.3` backend + `1.7.4` UI — two incremental PRs + the migration-order fix #176) |
| **Priority** | `medium` |
| **Complexity** | `medium` |
| **Impact** | `high` |

**Description**
The swap workflow carried no requester-supplied text anywhere: `CreateSwapRequestAsync` and
`RequestRevertAsync` took no message, and the only free text in the whole flow was the
approver's optional `rejection_reason` (200 chars, written only on rejection). The approver
decided with nothing but requester / proposed parent / handoff / date. Delivered: an
**optional free-text message from the requester at creation** (swap AND revert), stored on
`swap_requests.request_message`, shown to the approver everywhere the request appears (the
frozen-day panel, the Notifications "Para você" cards, the request e-mails **and the 24h
auto-approval reminder**), plus an **optional note on approval**
(`swap_requests.approval_note`, symmetric to the rejection reason), shown to the requester
in the resolution notification, the approval e-mails and the "Enviadas" tab.

**Design decisions (locked Aug 2026 with the owner + implementation round)**
- Scope: requester message on swap and revert **creation**; optional approver note on
  **approval**. Rejection reason already existed; **cancellation stays without a message**.
- Separation from the day observation: the message lives on the **request**
  (`swap_requests`), never persisted onto the day — `care_schedules.notes` remains the
  day-scoped observation. A rejected/reverted request's message dies with the request, so an
  obsolete swap motive can never masquerade as a day note.
- Notification texts append the message the same way rejection does (`" Mensagem: …"` /
  `" Observação: …"` via the pure helpers `MessageSuffix`/`NoteSuffix`/`NormalizeFreeText`),
  branching untouched on `targetIsProposed` (scenario B rule). Whitespace-only input
  collapses to NULL — no dangling labels anywhere.
- **One dual-purpose approver field** (owner's pick): the panel/card input "Observação
  (opcional)" is sent as `approval_note` on approve and `rejection_reason` on reject — no
  second input at the 344px minimum width.
- **The editor message field is conditional** (owner's pick): it appears only when the
  current selection will actually open a request (`EditorWillOpenWorkflow` mirrors
  `ShouldTriggerWorkflow`/`ShouldRequestRevert`), with a hint that the change requires the
  other caregiver's approval. The bulk sheet shows it when the batch can create requests
  (actual-parent change or clearing an approved swap); one message rides every request the
  batch creates.
- **The 24h reminder e-mail carries the message too** (owner's pick): it is the approver's
  last informed-decision moment before auto-approval.
- Columns follow `rejection_reason`'s discipline: nullable `text`, no DB CHECK, 200-char
  `maxlength` in the UI. Auto-approval (`auto_approve_expired`) writes no note — nothing
  changed there.
- **Ops lesson (cost one red gate):** migration timestamps are allocated per-session — the
  F-44 migration was authored as `…120000` while T-35's `…140000` was already applied on
  DEV, and `supabase db push` refuses out-of-order files without `--include-all`. Fixed
  forward by renaming to `20260804150000` (#176; safe: never applied anywhere). When
  authoring a migration, check the LAST APPLIED remote version, not just the local files.

**Tests**
- Unit (12 cases, `SwapRequestServiceLogicTests`): `NormalizeFreeText` trim/NULL collapse;
  `MessageSuffix`/`NoteSuffix` labelled output and empty-input silence.
- Integration (`SwapMessageTests`): the message persists at creation and is readable by the
  TARGET through family RLS; the approval note persists on the `pending→approved` flip
  (full-row update like `ApproveAsync`) and is readable by the REQUESTER; the creation
  message survives resolution untouched.
- E2E (smoke `SwapRequest_IsApproved_EndToEnd`, pack p0 — runs on every `dev` push):
  message typed in the day editor → visible in the approver's frozen-day panel
  (`.frozen-message-value`) → approval note attached (`.approver-note-input`) → both texts
  asserted on the resolved DB row. Dedicated marker classes per the Playwright
  first-match gotcha.

**Files**
- `supabase/migrations/20260804150000_f44_request_message.sql`
- `SharedParentalCustody/Models/SwapRequest.cs`, `Services/SwapRequestService.cs`
- `SharedParentalCustody/Pages/Home.razor`, `Pages/Components/FrozenDayPanel.razor`,
  `Pages/Notifications.razor`
- `supabase/functions/send-swap-email/index.ts` (redeployed by CI)
- `SharedParentalCustody.Tests/SwapRequestServiceLogicTests.cs`,
  `SharedParentalCustody.IntegrationTests/SwapMessageTests.cs`,
  `SharedParentalCustody.E2ETests/SmokeTests.cs`

---

### T-35 — Harden the concurrency token against fabrication

| Field | Value |
|---|---|
| **Status** | `done` (`1.7.2`) |
| **Priority** | `low` |
| **Complexity** | `low` |
| **Impact** | `low` |

**Description**
Found by the T-32 exploration (finding T32-A1, [`../t32-findings.md`](../t32-findings.md)).
The T-33 optimistic-concurrency guard compared `care_schedules.revision`, a counter
that increments **monotonically (+1)** and is therefore **guessable**: a hand-crafted
PostgREST call sending `revision = read + 1` **without re-reading** matched
`OLD.revision` and its stale write was accepted, defeating the optimistic lock.
Never a security hole — the worst outcome was a last-writer-wins overwrite of
`notes`/`actual_parent` (exactly the pre-T-33 behaviour), by a co-parent who is
allowed to change those fields anyway, with every real invariant (S-09 planned
parent, the swap workflow, day protection) still enforced by its own trigger and
every change recorded in the immutable `activity_logs`. Closed as defence-in-depth
before wide public availability.

**The analysis that changed the fix (the item's own proposal did not work).**
The record proposed replacing the counter with a non-guessable per-write uuid.
That does **not** close the finding: inside a `BEFORE UPDATE` trigger an **omitted**
column is indistinguishable from a correctly echoed one — PostgREST sends a partial
body and `NEW.<col>` simply carries `OLD.<col>` — so the same forger who could send
`revision + 1` would just leave `revision_token` out of the PATCH and pass again.
The second proposal (guard `updated_at` via an `If-Unmodified-Since`-style filter)
fails for the same reason, plus it is client-supplied. Shipping either would have
closed the item on paper while leaving the hole open, which is worse than the
documented limitation it replaced.

**Design decisions**
- **Read and echo live in DIFFERENT columns** — that asymmetry is the whole fix.
  `revision_token` is re-rolled by the trigger on every write (what a client READS);
  `submitted_token` is the echo and is reset to `NULL` after every write (what a
  client WRITES). A valid write carries `submitted_token = ` the row's current
  `revision_token`. Omitting inherits `NULL` ≠ token → rejected; forging means
  guessing a uuid → rejected; and the only way to produce a valid echo is to
  actually re-read the row, which is exactly what the optimistic lock asks for.
  A single column can never distinguish "echoed correctly" from "not sent".
- **Server-side exemption is by ROLE, not by payload shape.** T-33 exempted
  column-list UPDATEs implicitly (they never mentioned `revision`) — the same
  loophole the forger used. Now the trigger enforces unless
  `current_user IN ('postgres','service_role','supabase_admin')`: `SECURITY DEFINER`
  RPCs (S-11 erasure, `auto_approve_expired`, the E2E purge) run as their owner
  `postgres`, and the crons/integration harness as `service_role`. Fail-closed by
  construction — the exemption is an allowlist, so an unforeseen role is guarded
  rather than waved through.
- **Deliberate consequence:** an end-user column-list UPDATE (`.Set(...)`) on
  `care_schedules` is now rejected. Every client path already sends the full row.
- **`SubmittedToken` is COMPUTED from `RevisionToken` in the model**, not assigned
  at each call site. Five update paths (`CustodyService.UpsertScheduleAsync`,
  three in `SwapRequestService`, plus every integration test that updates a day)
  carry the echo without touching a line of their code — and, more importantly, a
  path added later cannot forget it. Assigning it by hand would have created a
  class of bug where a new flow silently gets the "someone got there first" error.
- **A missing echo gets its OWN message.** A cached PWA older than T-35 sends no
  echo, so it would otherwise be told "someone got there first" — which sends the
  user into a reload-the-month-and-retry loop that can never succeed. It now says
  "Recarregue o aplicativo…". Pre-T-35 clients surface it unchanged, because
  `CalendarHelpers.TranslateSaveError` passes accented trigger messages through —
  the message only ever reaches a client that predates this delivery, which is why
  the DB text (not the new client code) is what had to carry it.
- **The `revision` counter and its guard STAY.** Zero cost, keeps the
  human-readable "how many times was this day edited" signal, keeps rejecting a
  client that stamps a revision it never read (T-32's `StampingUnreadRevision`
  case), and keeps the T-33 integration assertions meaningful.
- **The trigger functions drop `SECURITY DEFINER`** (T-33 had made the guard a
  definer gratuitously — it touches no table). Inside a `SECURITY DEFINER`
  function `current_user` is the function's OWNER, so the role test would read
  `postgres` for every caller and the guard would **silently never fire**. As
  invoker it reads the caller's effective role, which is the whole distinction
  this design rests on. `auth.role()` is not an alternative: it reads the JWT
  claim, so a `SECURITY DEFINER` RPC called by an end user would still report
  `authenticated` and get blocked — the opposite of what the exemption is for.
- **INSERT stamps the token server-side.** The C# model serializes every `[Column]`
  property, so an INSERT arrives with the all-zeros uuid, which would override the
  `DEFAULT` and make every new row's first token perfectly guessable. A
  `BEFORE INSERT` trigger settles it regardless of payload.

**Tests**
- `OptimisticConcurrencyTests.ForgedToken_IsRejected` — everything legitimate
  except an invented token (the attack the counter could not stop).
- `OptimisticConcurrencyTests.EndUserUpdateWithoutEcho_IsRejected_AsAStaleClientBuild`
  — the omission half, asserting the *distinct* message.
- The existing T-33 cases keep passing untouched, which is itself the check that
  the computed echo reaches the wire on every full-row update.
- `CalendarHelpersTests.IsStaleClientBuild_IsDistinctFromADayConflict` — the stale
  build must never enter the day-conflict recovery flow.

**Files**
- `supabase/migrations/20260804140000_t35_nonguessable_revision_token.sql`
- `SharedParentalCustody/Models/CareSchedule.cs`, `Pages/Home.razor`,
  `Helpers/CalendarHelpers.cs`
- `SharedParentalCustody.Tests/CalendarHelpersTests.cs`,
  `SharedParentalCustody.IntegrationTests/OptimisticConcurrencyTests.cs`

---

### S-16 — Coordinated JWT signing-key migration (legacy HS256 → ES256)

| Field | Value |
|---|---|
| **Status** | `done` (`1.7.1`) |
| **Priority** | `medium` |
| **Complexity** | `medium` |
| **Impact** | `high` |

**Background — the July 2026 incident (why this item exists).**
Supabase began auto-provisioning projects with an **ES256 (ECC P-256) asymmetric
JWT signing key** as *Current*, demoting the legacy **HS256 shared secret** to
*Previous*. Our stack still authenticates with the **legacy static keys** — the
`anon` key in `appsettings` and the `service_role` key injected into Edge
Functions — both **HS256-signed with `kid` = `<nil>`**. Once ES256 became the
active signing key, GoTrue stopped recognising those static tokens and rejected
them: `unrecognized JWT kid <nil> for algorithm ES256`. The concrete symptom was
`register-invitee`'s `supabase.auth.admin.createUser()` failing (invite-link
sign-ups broken), which surfaced as a red CI gate on the DEV project and the same
latent breakage in prod. **Immediate mitigation applied (both environments): roll
the signing key back so HS256 is *Current* again** (Dashboard → JWT Keys → *Move
to Standby* the HS256 *Previous* key → *Rotate keys*). That restores the
known-good state but is a **band-aid** — Supabase will keep pushing ES256, so this
item does the migration *properly, on our schedule*.

**Description**
Adopt the new asymmetric signing keys end-to-end so we can leave ES256 as the
active key without breaking auth:
1. **App client**: replace the legacy `anon` key in `appsettings*.json` with the
   new **publishable key** (`sb_publishable_…`); confirm the Supabase C# client
   sends it as the `apikey`/`Authorization` anon token and that GoTrue/PostgREST
   accept it under ES256.
2. **Edge Functions**: they read `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY`
   from the injected env — verify Supabase injects the **new** keys once ES256 is
   current (the `service_role` equivalent is the new **secret key**
   `sb_secret_…`); redeploy `register-invitee`, `send-swap-email` and any other
   function and confirm `admin.createUser` / privileged calls succeed.
3. **CI secrets**: rotate the values behind `E2E_SUPABASE_SERVICE_ROLE_KEY` (and
   any anon key used by the integration/E2E suites) to the new keys for **both**
   the DEV and prod GitHub environments.
4. **Verification gate**: run the full suite against a DEV project that has ES256
   as *Current* (not rolled back) — invite sign-up (E2E), family isolation and
   adversarial RLS (integration) must all pass **before** touching prod.
5. **Prod promotion**: only after DEV is green on ES256, promote — leave HS256 as
   *Previous/standby* during a grace window (existing sessions signed under it),
   then revoke once no legacy tokens remain.

**Justification**
Auth-layer breakage is total-outage class (sign-up, and potentially any
static-key path). The rollback bought time but the platform default is moving to
ES256; migrating deliberately — with the app, Edge Functions and CI all cut over
together and verified on DEV first — removes a standing production fragility and
the recurring manual rollback. Asymmetric keys are also the more secure posture
(no shared secret to leak). **Do this before public availability** (alongside the
other launch-gate security items).

**Files affected**
- `SharedParentalCustody/wwwroot/appsettings*.json` — anon → publishable key
- `supabase/functions/*/index.ts` — verify against injected new keys; redeploy
- GitHub environment secrets (DEV + prod): `E2E_SUPABASE_SERVICE_ROLE_KEY`, anon
- `supabase/README.md` — runbook step for the key cutover + grace/revoke window
- Verification: existing E2E (invite sign-up) + integration (RLS isolation) suites

**Delivered (03/08/2026, `1.7.1`) — what the investigation changed about the item.**
The item as written mixed two migrations that Supabase treats as **independent**, and getting
that wrong is what made it look scarier than it is:

1. **API keys** — `anon`/`service_role` → `sb_publishable_…`/`sb_secret_…`. The legacy pair are
   JWTs signed with the project's *JWT secret*; the new pair are not JWTs at all and are
   validated by the platform gateway.
2. **JWT signing keys** — HS256 → ES256, which is what the July incident was about.

The causal link is one-way: (2) breaks the legacy keys *because* they are signed with the
secret it replaces. So (1) is not a nicety to do "alongside" — it is the thing that makes (2)
a scheduled step instead of an outage. Legacy keys keep working until the end of 2026, which is
the grace this item spends deliberately rather than by luck.

**The item's premise was also stale.** It claimed the stack "still ships the legacy static
keys" — false for DEV since July: `SUPABASE_ANON_KEY_DEV` and `TestEnv.AnonKey` were already the
publishable key (PR #124, the 1.8 h recorded), and the integration suite has been authenticating
with it on every push. What remained was the `service_role` half, prod, and the functions.

**Design decisions**
- **New keys only, no legacy fallback** (owner's call). The functions read
  `SUPABASE_SECRET_KEYS`/`SUPABASE_PUBLISHABLE_KEYS` through `_shared/keys.ts` and fail loudly
  without them. Cost: a hard ordering requirement — the keys must exist on a project BEFORE the
  CI redeploys its functions (every `dev` push, every promotion). That is the first thing the
  runbook's section 10 says, and the reason the prod-promotion checklist item 3 was rewritten.
- **Key NAME resolution.** The dictionary is keyed by name and the Dashboard creates `default`,
  but DEV's publishable key is named `github_key`. The helper prefers `default`, accepts a
  single candidate, and **refuses to choose among several** — a wrong pick is an auth failure
  that only appears at runtime, so guessing is worse than failing at deploy.
- **`verify_jwt` off + in-code authorization on five functions.** The platform gate only
  understands legacy JWT keys, so a caller holding a new key (the crons, and our
  function-to-function calls, both now sending it on `apikey`) gets 401 *before* the function
  runs. Turning the gate off without replacing it would have left an e-mail relay, the account
  purge and the auto-approval worker as anonymous endpoints — so `_shared/auth.ts` checks the
  secret key (comparison without early exit) or a valid user session, per caller class:
  `auto-approve-expired` (secret only), `purge-deleted` / `send-swap-email` /
  `send-account-email` (secret **or** user session — the app invokes all three).
- **`register-invitee` deliberately gets NO key check.** Its caller has not signed up yet and
  holds only the publishable key, which is public by definition — the gate never authenticated
  anybody there. The invitation token is, and always was, the authorization. Writing this down
  matters because "one function without the check" looks like an oversight otherwise.
- **Header shape follows the key FORMAT, not the environment** (`TestEnv.ApplyKeyHeaders`, the
  same `case` in `keepalive-dev.yml`, the same guard in `AuthService`): legacy needs
  `Authorization: Bearer` for PostgREST to derive the role (the T-44 lesson), new needs `apikey`
  alone. Supporting both is what allows rotating one secret at a time instead of a single
  flip-everything step — the difference between a staged migration and an outage window.

**The known unknown, RESOLVED the same day by two probes (and the reason it was worth
recording instead of guessing).** The `Supabase` C# SDK 1.4.0 builds
`Authorization: Bearer <session ?? apiKey>` and `SupabaseOptions.Headers` only *overrides* — an
unauthenticated client cannot omit it. Supabase's docs say a new-model key is rejected there;
in practice DEV has run on the publishable key since July with the suite green. The decisive
experiment is two PowerShell probes against the DEV project (runbook **10.2**), which the owner
runs BEFORE rotating `SUPABASE_SERVICE_ROLE_DEV` — `apikey` alone vs. `apikey` + `Authorization`,
the second being what the SDK-based `E2EFamilyFixture.Service` will send. If the second fails,
the documented fallback would be to keep the service side legacy — and **not** promote ES256,
since ES256 is precisely what invalidates legacy keys.

**Both probes came back green** (03/08/2026, DEV): the platform **accepts the secret key on
`Authorization`**, contradicting its own *Known limitations* section. Same discrepancy the
publishable key has been demonstrating since July. So the SDK path survives and the CI rotation
is unblocked — but the code still sends only `apikey` where we control the header, because
following the documented contract is what protects us if the platform ever starts enforcing what
it documents. A third probe covered the one path PostgREST does not — GoTrue's
`/auth/v1/admin/users`, which `AdminApi` calls to create the throwaway test users — and came back
green with the key on `apikey` alone. Three probes, ten seconds each, replaced a guess that would
otherwise have been answered by a red CI gate on the shared `dev` project.

**Two corrections the Supabase docs forced during the handover** (the owner asked for
click-by-click steps, which is what surfaced them): (a) the runbook's rotation table listed a
`SUPABASE_SERVICE_ROLE_PROD` secret that **does not exist** — the suites always run against DEV,
even on `master`, so prod's privileged key never enters CI; (b) the ES256 step is not "promote
the key" but **Migrate JWT secret → Rotate keys** on the JWT Keys page, and the docs warn that
functions still carrying *Verify JWT* may break on rotation. That leaves `elevate` and
`billing-checkout` as the known contingency — both already validate the user's JWT in their own
code, so the fix is to add them to the same `verify_jwt = false` list (runbook 10.6).

**Tests.** New `EdgeFunctionAuthTests` (13 cases): anonymous call, wrong secret, the public
publishable key and a garbage session must each get 401 from the four gate-less functions. The
happy paths were already covered (`RegisterInviteeTests`, the billing and deletion suites) — what
had no coverage was the posture this item changed, which is exactly the kind of regression that
stays invisible while every feature keeps working.

**Outcome (03/08/2026, same day): the whole cutover ran green on DEV, and the July incident is
closed at the root.** Sequence: keys created → three probes → CI secret rotated → both crons moved
to the `apikey` header (verified live: `{processed:0, emailsFailed:0}` with the key, **401**
without it — both branches of the new authorization, in production conditions) → full-pack green
→ **ES256 promoted to *Current*** → full-pack green again (run #261). Two things worth keeping:
the dashboard had **no "Migrate JWT secret" button** — the July auto-migration had already created
the ECC (P-256) key, which our rollback had demoted to *Previous*, so the step was to move that
existing key back to standby and rotate; and the documented contingency **did not materialize** —
`elevate` and `billing-checkout` kept `verify_jwt` on and validated ES256 user tokens fine (the
docs' warning applies to code verifying JWTs against the *legacy secret*, which we never did).
Zero code changes were needed after the merge.

**Files:** `supabase/functions/_shared/{keys,auth}.ts` (new), the 8 `supabase/functions/*/index.ts`,
`supabase/config.toml` (four new `verify_jwt = false` blocks), `.github/workflows/deploy.yml`
(`--no-verify-jwt` on five deploys, both branches), `.github/workflows/keepalive-dev.yml`,
`SharedParentalCustody/Services/AuthService.cs`,
`SharedParentalCustody.IntegrationTests/{TestEnv,AdminApi,BillingHistoryTests,RegisterInviteeTests,EdgeFunctionAuthTests}.cs`,
`supabase/README.md` (new section 10 + sections 2.1/4.3/4.4 and promotion checklist item 3).


---

### F-45 — Link notifications ↔ swap requests ↔ audit log (and enrich the PDF)

| Field | Value |
|---|---|
| **Status** | `done` (`1.7.6` part 1, `1.7.7` part 2) |
| **Priority** | `medium` |
| **Complexity** | `medium` |
| **Impact** | `high` |

**Description**
`notifications.swap_request_id` already existed, but nothing linked a swap request to the
`activity_logs` row its **resolution** produced — the only request→log pointer was
`pre_edit_log_id`, which points *backwards* at the pre-edit snapshot. So the Histórico could not
say *why* a day changed, Notifications could not show the change they announce, and the F-33 PDF
(which reads `activity_logs` only) showed the mutation with no motivation — auto-approvals even
rendered as "Sistema" with no trace of the underlying request. The triangle is now closed:
`swap_requests.resolution_log_id` (FK to `activity_logs`, `ON DELETE SET NULL`), symmetric to
`pre_edit_log_id`, stamped in **both** resolution paths, then consumed by the three surfaces.

**Delivered (part 1, `1.7.6`)**
- Migration `20260804200000_f45_swap_resolution_log`: column + partial reverse-lookup index +
  trigger `trigger_z_stamp_swap_resolution_log` (BEFORE UPDATE on `swap_requests`): on the
  `pending`/`revert_pending` → `approved`/`revert_approved` transition, stamps
  `max(activity_logs.id)` for the same family+date with `created_at >= the request's` and
  `id > pre_edit_log_id`. One implementation covers the client approval AND the
  `auto_approve_expired` RPC (both update `care_schedules` before flipping the status, so the
  resolution's audit row already exists when the trigger fires).
- **Conservative backfill** (creation→resolution window, same family/date; no match = stays
  NULL — an unlinked entry is honest, a wrongly linked one is not): 62 of 68 resolved requests
  linked on dev.
- **Histórico de Ajustes**: workflow-originated entries show the origin line + the F-44
  request message / approval note (`AuditService.GetResolutionOriginsAsync` batch reverse
  lookup + `ResolutionOriginText`).

**Delivered (part 2, `1.7.7`)**
- **Notifications history tab**: change-announcing notifications (`swap_approved`/`_self`,
  `revert_approved`/`_self`, `auto_approved`, `swap_family_info`) render the field diff of the
  change they announce inline (notification → request → resolution log → `ComputeDiff`, two
  batch reads, best-effort).
- **PDF (F-33)**: timeline entries gain `OriginText`/`OriginMessage`/`OriginNote` —
  requester/approver or the auto-approval wording, plus the F-44 texts. `ReportPdfService.Build`
  takes an optional `resolutionOrigins` lookup; `BuildForPeriodAsync` feeds it from
  `GetResolutionOriginsAsync`.

**Design decisions**
- **DB trigger, not an RPC and not a client stamp**: converting approval into a SECURITY
  DEFINER RPC would bypass the day-protection triggers for the whole write; a client stamp
  would repeat the race-prone "newest log for the date" heuristic and miss the auto path. The
  trigger runs after `enforce_swap_status_transition` (alphabetical BEFORE-trigger order,
  `trigger_z_…`), so only validated transitions reach it.
- **Trigger-owned column**: on every non-resolution UPDATE the trigger restores
  `OLD.resolution_log_id`, so a forged/cleared client write is inert (pinned by
  `ResolutionLogLinkTests.ClientWrite_CannotClearOrForgeTheStamp`). Consequence: the backfill
  MUST run before the trigger is created in the migration — the trigger would null it.
- **The frozen-day invariant is what makes the stamp race-free**: while a request is pending
  the day only changes through the workflow (admin override logs land with older ids than the
  resolution's own write, taken by `max(id)` at the resolution instant).
- **One phrasing source** (`AuditService.ResolutionOriginText`) shared by Histórico and PDF so
  the texts cannot drift; branches on revert vs. swap and manual vs. `resolved_by = 'system'`.
- **Notifications got the inline summary, not a deep link**: the app has no per-date deep-link
  infrastructure; building it just for this card would be its own item. The card shows the
  change directly instead.

**Files touched**
Migration `20260804200000_f45_swap_resolution_log.sql`; `Models/SwapRequest.cs`
(`ResolutionLogId`), `Models/CustodyReport.cs` (`OriginText`/`OriginMessage`/`OriginNote`);
`Services/AuditService.cs` (`GetResolutionOriginsAsync`, `GetLogsByIdsAsync`,
`ResolutionOriginText`), `Services/SwapRequestService.cs` (`GetByIdsAsync`),
`Services/ReportPdfService.cs`; `Pages/ReportsAudit.razor(.css)`, `Pages/Notifications.razor(.css)`,
`Pages/ReportsPdf.razor(.css)`. Tests: `ResolutionLogLinkTests` (integration, 4),
`AuditServiceTests` (unit, 5), `ReportPdfServiceTests` (+3).

---

### U-20 — Reports Summary: projected balance including accepted future swaps

| Field | Value |
|---|---|
| **Status** | `done` (`1.7.9`, delivered together with U-07 — same cards, same PDF section) |
| **Priority** | `medium` |
| **Complexity** | `low` |
| **Impact** | `high` |

**Description**
Approval writes `actual_parent_id` **immediately, even for future days** (no date guard in
`ApproveAsync` nor in the day-protection triggers), but the Resumo discarded that information:
"Realizado" is gated to `ScheduleDate < today`, so an accepted future swap was invisible until
the day passed. Parents who agreed on a rebalancing could not see the resulting balance ahead of
time. Delivered as a **toggle** ("Considerar trocas futuras já aceitas") that, when on, adds a
**"Previsto"** metric per caregiver — realized past + future days with `actual ?? scheduled`
applied — and makes every swap count include accepted future swaps. Pure client-side
computation/presentation; no migration.

**Design decisions**
- **Toggle, not an always-on third column** (locked Aug 2026 with the owner): the default view
  stays Programado/Realizado exactly as before.
- **Same option on the PDF** (locked Aug 2026): the "PDF numbers must match the screen" rule
  stands — `ReportPdfService.Build` gained `includeAcceptedFutureSwaps` and mirrors the counting
  expressions; the generator exposes the same checkbox, the report header gains a "Critério"
  line ("Inclui trocas futuras já aceitas no período") and the caregiver table a "Dias
  previstos" column, so a printed report is explicit about which rule produced its numbers.
- **Toggle ON = the WHOLE view is projected** (locked at delivery): the per-caregiver swap
  split (U-07) and the total-swaps banner also include accepted future swaps, instead of mixing
  a projected "Previsto" with realized-only swap counts. Toggle OFF = everything realized-only,
  as today.
- **Projection expression**: `Previsto = count((actual ?? scheduled) == caregiver)` over the
  whole period, no date gate — correct because approval already stamps `actual_parent_id` for
  any date; the projection just stops discarding it.
- **Visibility rule**: a caregiver whose only involvement in the period is a *received future
  swap* (planned = realized = 0) appears in the PDF caregiver table only when the projection is
  on (`SwapsReceived`/`ProjectedDays` joined the `Where` filter).
- The Resumo caches the period's rows (`loadedSchedules`) so toggling recomputes client-side
  without a new fetch.

**Files touched**
`Pages/ReportsSummary.razor(.css)` (toggle `.future-swaps-toggle`, "Previsto" row, banner
variant, `ComputeStats`/`IsVisibleSwap`), `Services/ReportPdfService.cs`
(`includeAcceptedFutureSwaps` on `Build`/`BuildForPeriodAsync`), `Models/CustodyReport.cs`
(`IncludesFutureSwaps`, `CaregiverStat.ProjectedDays`), `Pages/ReportsPdf.razor(.css)` (option +
"Critério" meta line + "Dias previstos" column). Tests: `ReportPdfServiceTests` (+5 with U-07),
E2E `ReportsUiTests.Reports_TotalsMatchSeed` (seeded accepted future swap + toggle assertions).

---

### U-07 — Show swap count in Reports Summary cards

| Field | Value |
|---|---|
| **Status** | `done` (`1.7.9`, delivered together with U-20 — same cards, same PDF section) |
| **Priority** | `low` |
| **Complexity** | `low` |
| **Impact** | `medium` |

**Description**
Each parent's summary card showed "Programado" and "Realizado" counts but no per-parent swap
breakdown — the total banner did not distinguish who gave days away and who received them. Each
card gains a third row, **"Trocas: cedeu X · recebeu Y"**: *cedeu* = days scheduled to that
caregiver where someone else was the actual responsible; *recebeu* = days where they were the
actual responsible on someone else's scheduled day. The total swaps banner at the bottom
remains as-is.

**Design decisions**
- **"cedeu X · recebeu Y", not a single number** (decision at delivery): the item's
  justification — distinguishing who gave and who received — is only met with both sides on the
  card, and the split stays informative with 3+ caregivers (where a single per-card count
  would leave "received" unattributable).
- **Realized swaps only by default**; with the U-20 projection toggle ON, both sides include
  accepted future swaps (one consistent view — see U-20's record).
- **PDF mirrors the split** (decision at delivery): the caregiver table gains a single
  "Trocas (cedeu · recebeu)" column (value "X · Y") rather than two columns, keeping the
  table inside the printable width; the summary section scrolls horizontally on narrow screens
  (`overflow-x` on `.rp-section`, screen only).

**Files touched**
`Pages/ReportsSummary.razor(.css)` (`.stat-row-swaps` row), `Services/ReportPdfService.cs` +
`Models/CustodyReport.cs` (`CaregiverStat.SwapsGiven`/`SwapsReceived`),
`Pages/ReportsPdf.razor(.css)` (table column). Tests: `ReportPdfServiceTests` (+5 with U-20),
E2E `ReportsUiTests.Reports_TotalsMatchSeed` (per-card swap-row assertions).

---

### F-47 — User decides whether a reversion also restores the day observation

| Field | Value |
|---|---|
| **Status** | `done` (`1.7.10`) |
| **Priority** | `low` |
| **Complexity** | `medium` |
| **Impact** | `medium` |

**Description**
The revert restore (F-26) puts the day back to its **full** pre-edit snapshot — including
`care_schedules.notes`, the "Observação do dia". That is sometimes right (the observation
described the swap that is being undone) and sometimes wrong (the family updated the day's
observation AFTER the swap was approved, and the revert silently rolls it back). There is no
universal rule — so the USER decides, at the moment a reversion is requested: when the current
observation ("Texto B") differs from the pre-swap snapshot's ("Texto A"), the day editor asks
whether the reversion should also restore the observation. **Default — including when the user
dismisses or does not answer: the observation is NOT reverted** (Texto B stays). Equal texts (or
both empty) ask nothing.

**Design decisions (owner, Aug 2026 — QA follow-up of the F-44 terminology round)**
- The question appears **only when the texts differ**, at revert-request time, in the single-day
  editor. It reuses the S-09 confirmation-block pattern inside the day panel (not a new sheet):
  the save that would open the revert stops, shows both texts labelled *Observação atual* /
  *Antes da troca*, and offers **Manter a atual** (safe) / **Restaurar a anterior** / *Cancelar*.
  Neutral styling, not the red of the destructive blocks — both answers are legitimate.
- **Fail-safe default is "keep the current observation"** everywhere: no answer, a dismissed
  question, an old cached build and every **bulk** revert path all send `false`. Restoring is an
  explicit opt-in. The bulk decision (owner): a batch **never** restores — one answer applied to
  N different texts is not a decision, and asking per day turns a bulk action into a form.
- **The choice is persisted on the request** (`swap_requests.revert_notes boolean not null
  default false`) because the restore runs later and on the OTHER side: the approver's client
  (`ApproveRevertAsync` → `RestorePreEditStateAsync`) and the 48h `auto_approve_expired` both
  read it. `restore_pre_edit_state` gained a third argument rather than an overload (a DEFAULT
  twin would make every existing 2-arg call ambiguous).
- **The flag is frozen after the INSERT** (`freeze_revert_notes_choice`, BEFORE UPDATE): the
  approver rewrites the whole row when they resolve the request, so without the trigger a
  full-row PostgREST update from the other party could flip the requester's answer on its way
  to the restore. Same discipline as `resolution_log_id` (F-45).
- Nothing else in the snapshot restore changed — parents, handoff time and the
  delete-if-the-edit-created-the-day rule are untouched. A day whose `old_data` is NULL is still
  deleted by the revert, and asks nothing: there is no observation to decide about.
- **Security fix carried along (found while rewriting the function, verified on DEV):** the
  V007-era "worker-only" lockdown on `restore_pre_edit_state` and `auto_approve_expired` —
  `REVOKE ALL … FROM PUBLIC` + `GRANT … TO service_role` — **never worked**. Supabase's DEFAULT
  PRIVILEGES grant EXECUTE to `anon`/`authenticated` on every new function in `public`, and a
  revoke from PUBLIC does not touch role grants, so both were callable by any logged-in user
  (and by anon). `restore_pre_edit_state` is `SECURITY DEFINER` over a bare schedule id with no
  family filter, i.e. a cross-family rewrite/DELETE primitive; `auto_approve_expired` would let
  anyone force-resolve every expired request in the project and fire its notifications. Both are
  now revoked from the two roles BY NAME. Every legitimate caller (the Edge Function cron, the
  integration suites) runs as `service_role`, so nothing else changes.
  `RevertNotesTests.WorkerFunctions_AreNotCallableByAnEndUser` keeps it closed.

**Files touched**
Migration `20260804220000_f47_revert_notes.sql` (column + `freeze_revert_notes_choice` trigger +
3-arg `restore_pre_edit_state` with tightened grants + `auto_approve_expired` passing
`rec.revert_notes`), `Models/SwapRequest.cs` (`RevertNotes`),
`Services/SwapRequestService.cs` (`RequestRevertAsync(restoreNotes)`, `RestorePreEditStateAsync`
honouring it, `GetPreEditNotesAsync` + `NotesDifferForRevert`, extracted
`GetApprovedRequestForDateAsync`), `Pages/Home.razor(.css)` (the question block, the two bulk
call sites documented as deliberate `false`). Tests: `SwapRequestServiceLogicTests` (+9 cases on
`NotesDifferForRevert`), `RevertNotesTests` (integration, 4 cases: auto-approval keeping,
auto-approval restoring, approver unable to flip the choice, and the two worker functions
refusing an end-user call).

---

### F-48 — Checkout trust signals, paywall funnel instrumentation & Pix avulso

| Field | Value |
|---|---|
| **Status** | `done` (`1.7.11` blocks 1+2 + promotional pricing; `1.7.12` Pix avulso; `1.7.13` QA price fix — gateway minimum) |
| **Priority** | `high` |
| **Complexity** | `medium` |
| **Impact** | `high` |
| **Cross-repo** | **Same delivery as landing L-14** (guarantee + Pix + new price + Play-badge slot on the pricing section; record in the landing `ROADMAP.md`) |

**Description**
Born from the Aug 2026 architecture/monetization review: the owner's core doubt — "does anyone
pay outside the stores?" — settled as trust + measurement on the web funnel, not a platform
migration. Three blocks, all shipped:

1. **Trust signals on the payment surface** (`1.7.11`): the premium offer gained the Pix
   emphasis ("QR pelo app do seu banco, sem informar dados de cartão") and the **7-day
   guarantee box** (full refund via `suporte@guardacompartilhada.com`, art. 49 CDC) — a
   visible mirror of Terms §10, so **non-material** (no `PolicyVersions` bump); the guarantee
   reminder repeats on `/premium/retorno`. **CNPJ/razão social carved out to F-49/L-15**
   (group 8): the owner has no CNPJ yet and will not expose his personal identity instead.
2. **Paywall funnel** (`1.7.11`): `premium-paywall-view` (1×/visit) → `premium-checkout-start`
   (pre-existing event, kept for data continuity) → `premium-checkout-return` →
   `premium-checkout-outcome` (confirmed/timeout), all through the pure
   `AnalyticsService.FunnelProps` helper — closed prop set (`channel`/`cycle`/`outcome`/`mode`,
   no PII can ride along), `channel` fixed at "web" until T-38 ships the store-shell flag.
   This is the data that arbitrates **T-48**.
3. **Pix avulso** (`1.7.12`): a single non-recurring Pix charge for 1 month (R$ 5,49) or
   12 months (R$ 54,90) — `billing-checkout` action `avulso` (DETACHED payment link, Pix only);
   the webhook now matches subscription-less payments by `externalReference family:<id>` and
   settles the `single_charge` row (migration `20260805010000`) as **canceled-with-paid-time**
   — the state the whole F-42/grace/U-22 machinery already understands: additive renewals,
   grace-cron lapse, expiry notice. `PAYMENT_OVERDUE` is inert on avulso rows; F-42
   reactivation refused on both sides (no gateway subscription ever existed). UI: avulso
   buttons under the subscribe pair, avulso-specific paid-until copy, and the near-lapse
   warning (`ExpiringDaysLeft`, ≤7 days).

**Promotional launch pricing (owner decision): R$ 5,49/month · R$ 54,90/year** — replaces
R$ 14,90/149 for every NEW checkout (migrations `20260805003000_f48_promo_pricing` +
`20260805020000_f48_price_gateway_minimum` + client/function defaults + the landing).
**QA round (`1.7.13`): the price first chosen, R$ 4,90, sat under the Asaas Pix/boleto
minimum of R$ 5,00** — the gateway 400'd every monthly payment-link creation and every
reactivation ("O valor mínimo para cobranças via Boleto e Pix é R$ 5,00", surfaced as 502s;
the annual R$ 49 passed), so the owner repriced to 5,49/54,90. **The monthly price must stay
≥ R$ 5,00.** "2 meses grátis" stays exact (5490 = 10 × 549); existing subscriptions keep
their acquired price (Terms guarantee — panels/webhook read `subscriptions.price_cents`,
never the setting). **The promotion that carries the new price to production must ride
together with the landing `main` deploy (L-14)** — both surfaces must announce the same
price.

**Files affected**
`Pages/FamilyPage.razor(.css)` (trust copy, avulso buttons, expiry warning, funnel events),
`Pages/PremiumReturn.razor(.css)` (guarantee reminder + return/outcome events),
`Services/AnalyticsService.cs` (`Channel`, `FunnelProps`), `Services/BillingService.cs`
(`StartAvulsoAsync`, avulso-aware `CanReactivate`, `ExpiringDaysLeft`),
`Services/SettingsService.cs` + `supabase/functions/billing-checkout` (promo defaults, avulso
action, reactivate guard), `supabase/functions/billing-webhook` (subscription-less match +
single-charge settlement + overdue guard), `Models/Subscription.cs` (`single_charge`),
migrations `20260805003000` + `20260805010000`. Tests: `AnalyticsServiceTests` (funnel props),
`BillingServiceTests` (avulso reactivation refusal, expiry threshold), `BillingWebhookTests`
(new price assert) and `BillingAvulsoTests` (integration, 3 cases: settlement without a
subscription id, additive second charge, overdue inert).

---

### T-38 — Android TWA wrapper + Google Play listing

| Field | Value |
|---|---|
| **Status** | `done` (`1.7.14` manifest/icons/assetlinks/runbook; `1.7.15` store-shell detection + neutral paywall, closes the item; `1.8.1` the real fingerprints + bilingual listing — the follow-up the closure predicted) |
| **Priority** | `high` |
| **Complexity** | `medium` |
| **Impact** | `high` |
| **Phase** | 7 |

**Description**
Wrap the existing PWA as a **Trusted Web Activity** for the Google Play Store. The PWA was
already TWA-ready (standalone manifest, service worker, HTTPS); the item delivered everything
the repo side needs, plus the runbook that guides the owner-ops half:

- **`1.7.14` (part 1)** — `wwwroot/manifest.webmanifest` gains dedicated **maskable icons**
  (`icon-maskable-192/512.png`, motif inside the 80% safe zone over a radial background rebuilt
  from the art's own palette — the `purpose: any` originals get cropped by Android launchers),
  `screenshots` (the landing L-03 set, 1080×1920, PT-BR labels), `categories`, `description`,
  `lang`/`dir` and `related_applications` with the package id; new
  **`wwwroot/.well-known/assetlinks.json`** (Digital Asset Links — placeholder fingerprints
  until the Play Console emits the real ones; verified that `dotnet publish` INCLUDES the
  dot-directory and the service worker precaches it); new **`store/README.md`** runbook
  (Bubblewrap on Windows with the full `init` answer table, keystore handling, Play Console
  click-by-click, Data Safety mapped to the shipped privacy policy, PT-BR listing texts, the
  closed-testing gate and the version-code rule) + `store/.gitignore`.
- **`1.7.15` (part 2)** — **store-shell detection**: every TWA cold start loads the first
  document with the `android-app://com.guardacompartilhada.app` referrer; an early inline
  script in `index.html` captures it into **sessionStorage** (`store-context`) and `Program.cs`
  reads it once, before the first render, into the new static helper `Helpers/StoreContext` —
  no component races the detection. With the flag on, FamilyPage swaps the whole Premium offer
  (prices, subscribe, Pix avulso, reactivate) for the neutral `.premium-store-note` ("managed
  on the website" — no price, no checkout link; Play payments policy), keeping the
  informational status lines; `AnalyticsService.Channel` reads the flag, so the F-48 funnel
  events carry `channel=store` inside the shell — the data that arbitrates **T-48**.
- **`1.8.1` (follow-up, 10/08/2026)** — the PR the closure below predicted, delivered once the
  first upload made the fingerprints exist: `assetlinks.json` gets the **real** SHA-256 pair
  (Play app-signing key + upload key — both, so a locally-signed APK also validates), which is
  what stops the installed app from opening in custom-tab mode with the Chrome address bar over
  it. Also `store/twa-manifest.json` **versioned at last** (§1 always required it; it had sat
  untracked since the first packaging) with `appVersionCode` 2 — **a version code is burned by
  the UPLOAD, not by the rollout**, and code 1 was spent on a release that never went live —,
  the store listing versioned and bilingual (`store/listing-pt-BR.txt` + `listing-en-US.txt`;
  the PT-BR copy claimed "em português" about an app that speaks English since U-13), and four
  runbook corrections the first publication attempt paid for in wasted clicks: the Console moved
  App signing (**App integrity → Protected with Play**; `…/keymanagement` still works as the
  direct route), the **App access** form is mandatory and rejects apps whose reviewer cannot log
  in (this whole app is behind login), the en-US translation procedure, and that **saving a
  release does not publish it** — the `Start rollout` button is the actual publish, and missing
  it is what left the first upload a draft for days with no warning anywhere.

**Design decisions (owner, 05/08/2026):**
- **Bubblewrap CLI over PWABuilder**: local, reproducible build; `store/twa-manifest.json`
  versioned; keystore generated and kept only on the owner's machine. PWABuilder remains the
  fallback (it imports the same `twa-manifest.json`).
- **Package id `com.guardacompartilhada.app`**.
- **sessionStorage, NOT localStorage, for the shell flag**: the TWA shares its storage with the
  device's Chrome profile — a persistent flag written inside the shell would leak into plain
  browser tabs (hiding the checkout from a legitimate web session and mis-tagging its funnel).
  `getInstalledRelatedApps()` was rejected for the same reason: it answers "is the app
  installed", not "am I running inside it".
- **T-36 (Supabase Pro) WAIVED deliberately** at the item's start: the group-8 rule stands
  (platform spend waits for actual revenue) and the accepted risk is unchanged (weekly
  encrypted dump is the only backup net; payment truth lives in Asaas). Revisit when revenue
  starts.
- **Play listing starts with the current (masked DEV/QA) L-03 screenshot set**; recapture from
  production at the next promotion (reminder below).
- **Item closed at code-complete** (S-16 precedent): the listing itself is owner ops guided by
  `store/README.md` — Play account, Bubblewrap build, fingerprints into `assetlinks.json` (a
  small future PR that cites T-38 as context), Data Safety, closed test (~12 opted-in testers
  for 14 days — calendar time; recruiting starts with the runbook, not with the build).

> **📸 Reminder — recapture screenshots from PRODUCTION once the app is fully updated in prod.**
> The current `L-03` screenshots (store + landing) were captured from the **DEV/QA** build with
> the `[Dev]` badge masked in-place. At the next promotion, recapture the full set from prod
> (DPR 3, 1080×1920), including **Notifications** and **per-parent Summary**, and replace both
> the Play-listing assets **and** the landing `L-03` images (`store/README.md` §6 repeats this).

**Justification**
Store presence is both a discovery channel and a trust signal, at low cost (~US$25 one-time).
iOS stays a separate item (T-40, group 4 next-but-one) — Capacitor shell, APNs, App Review;
**T-47** (publishability spike) sits between the two and its verdict shapes T-40's scope.

**Files affected**
`wwwroot/manifest.webmanifest`, `wwwroot/.well-known/assetlinks.json` (new),
`wwwroot/icon-maskable-192/512.png` (new), `wwwroot/index.html` (capture script),
`Helpers/StoreContext.cs` (new), `Program.cs` (boot read), `Services/AnalyticsService.cs`
(`Channel` reads the flag), `Pages/FamilyPage.razor(.css)` (neutral offer state),
`store/README.md` + `store/.gitignore` (new). Tests: `AnalyticsServiceTests` (+4: pure
`ChannelFor` mapping, persisted-value parsing, store-channel funnel props — the facts that flip
the static flag live in the same class on purpose, so they never race the default-web asserts)
and the new E2E `StoreShellUiTests` (p1, 2 cases: the persisted store flag — seeded via
`AddInitScript`, since Chromium refuses to surface a non-http `Referer`, probed 05/08/2026 —
→ neutral note with zero checkout buttons; web session still sees the full offer; the
referrer→sessionStorage capture line itself is validated on-device, `store/README.md` §3e).

---

### T-49 — Stop the test suite from spending the Resend allowance

| Field | Value |
|---|---|
| **Status** | `done` |
| **Delivered** | `1.7.23` (06/08/2026) |
| **Priority** | `high` |
| **Complexity** | `low` |
| **Impact** | `high` |

**Description**
`send-swap-email` and `send-account-email` now skip the outbound Resend call when the
recipient sits on the `@resend.dev` test domain — the addresses the E2E/integration fixture
builds (`delivered+e2e-<run>-<who>@resend.dev`, `TestEnv.E2eEmailDomain`). The rule lives in
one place, `supabase/functions/_shared/mail.ts`, so both functions cannot drift apart.

**Justification**
The suites drive the REAL flows against the DEV project, so every CI run made the app call the
e-mail functions for real. Measured on 06/08/2026 from the Resend API: **86 e-mails in a single
day, 100% of them from CI** (~7 per `dev` push × ~12 pipelines), against an account **shared
with production** — one team, one verified domain, six API keys, including `supabase-smtp-prod`,
the GoTrue SMTP that sends sign-up confirmations and password resets. The free plan caps at
**100/day**, and the owner was getting the 80%-quota warning almost daily with the app still in
private testing. So a busy CI day could return 429 to production and leave a real invitation, a
real swap notice — or a sign-up confirmation, which is the severe case, since the user simply
cannot get in — undelivered, with no error surfaced to anyone.

**Design decisions**
- **Unconditional, not an environment flag.** `resend.dev` is Resend's own reserved test
  domain: no real user can hold a mailbox there. A flag would be one more thing to set
  correctly on a new project, and getting it wrong in prod would suppress real e-mail.
- **The guard sits at the HTTP call only.** Recipient resolution, the templates, the F-38
  quota accounting (`consume_email_quota` runs BEFORE the dispatch) and the function's response
  all behave exactly as in production, so no suite loses coverage.
- **Verified, not assumed, that nothing was testing delivery**: no test asserts an e-mail was
  sent (`EmailQuotaGateTests` calls the RPC directly; `EdgeFunctionAuthTests` asserts 401s),
  and every `Functions.Invoke` call site in the app ignores the response inside a `try/catch`.
  A send REJECTED by Resend has never failed a test — before or after this change. That was
  the owner's explicit condition for approving the work.
- **`suppressed` is reported apart from `failed`.** Skipping on purpose and failing must not
  read the same in the logs or in the response body — that distinction is what the new test
  asserts, and what a future reader needs to trust the counter.

**What this does NOT cover**
The ~12 remaining e-mails/day are GoTrue's own auth messages on the DEV project
(`[DEV] Confirme seu cadastro`), sent over custom SMTP — they never pass through this code.
Removing them is a configuration step (point DEV's SMTP at a sandbox), recorded in
`supabase/README.md` §5.5. The Supabase built-in SMTP is not an option there: ~2–4/hour would
break the pack.

**Files affected**
`supabase/functions/_shared/mail.ts` (new — the rule + the whole rationale),
`supabase/functions/send-swap-email/index.ts` and `supabase/functions/send-account-email/index.ts`
(`sendEmail` returns whether it dispatched; the three response paths count `suppressed`),
`supabase/README.md` §5.5 (the quota note + the DEV SMTP follow-up). Tests: the new integration
`TestRecipientSuppressionTests` (p0, 1 case) — it drives the app's own path (signed-in user →
`send-swap-email`) and requires `suppressed ≥ 1` with `failed = 0`. It was verified to be a real
gate by running it against the still-unguarded deployed function: it failed on exactly that
assertion, with the response `{"sent":1,"failed":0,"quota":"allowed"}` printed.

---

### U-13 — Internationalization (PT-BR / EN) across every surface the user reads

| Field | Value |
|---|---|
| **Status** | `done` — delivered across ten PRs, `1.7.16` → `1.7.28` (06/08/2026) |
| **Priority** | `high` |
| **Complexity** | `high` |
| **Impact** | `high` |

**What it turned out to be.** The item was promoted because PT-BR-only was one of the two
reasons the tester recruitment stalled — most of the developer community reachable for a closed
test does not read Portuguese. The scope decision was **complete coverage, not UI-only**: a
tester who reads the app in English and then receives a PT-BR invitation e-mail or exports a
PT-BR PDF has still hit the wall the item exists to remove. It shipped that way.

**The one genuinely hard part, and the shape that solved it.** Notifications and e-mails are
**written by one person and read by another**. `notifications.title`/`.message` were rendered
PT-BR sentences composed at INSERT time by SQL triggers and by `SwapRequestService`; the e-mails
are composed by a cron with no browser to ask. There is no language the WRITER could pick that
is right. The answer, in both places, was to stop storing sentences and start storing **data**:
a `params` JSONB column rendered on the reader's device (`NotificationRenderer`), and
`profiles.language` read per recipient by the Edge Functions. The stored PT-BR text survives
untouched as the fallback for every row written before the item — nothing in history was
rewritten, and no backfill fabricated a translation that never existed.

**Discriminators are the load-bearing detail.** Wherever one `type` carried more than one
wording, the payload gained a discriminator: `family_deletion` has seven, `account_deletion`
three, `email_cap_reached` two, and `swap_cancelled` two — that last one a real collision
between `SwapRequestService` and `request_account_deletion`. Without them each reader would get
the OTHER party's sentence, which is worse than not translating, because it is false.

**Decisions that bind future work**
- **Compiled C# dictionaries**, not `.resx`/`IStringLocalizer`: a typo in a `K.` constant fails
  to compile, where `IStringLocalizer["key"]` fails silently in front of a user; and `.resx`
  would have forced `DefaultThreadCurrentUICulture` to move, coupling the UI language to the
  `InvariantCulture` pin that keeps ISO 8601 on the wire.
- **Language fixed at boot; a switch does a `forceLoad`.** No component subscribes to a change
  event, so no screen can render half-translated.
- **`profiles.language` is not redundant with localStorage.** localStorage is the client's truth
  (it must work on the login screen, before a session exists); the column is the SERVER's copy,
  for senders with no browser. NULL is never backfilled — "never chose" and "asked for
  Portuguese" are different facts.
- **User data is never translated**: names, family names, day observations, swap messages, and
  F-41 custom roles pass through in both languages.
- **Legal pages stay PT-BR** (they are the binding instrument for a Brazilian service); English
  gets a courtesy rendering of the consent declarations and of the policy-change summary, each
  with an on-screen notice naming the Portuguese text as the one that binds.
- **Dates and numbers were split out as U-24** — they render `dd/MM` in every language, and
  changing that touches the whole calendar plus the `InvariantCulture` pin. The billing prices
  deliberately stay in Brazilian format (`R$ 5,49`) in both languages: the charge is in reais.
- **GoTrue auth e-mails remain out of scope** — one template set per project, no per-user
  language. Recorded in the runbook.

**The lesson that cost the most.** Three separate slices were declared clean by a verification
method that could not see the text: PR 3c grepped for **accented** literals, and "Resumo",
"Total", "Dias", "Nome", "Papel" and "PDF" carry no accent (fixed in `1.7.25`); PR 5 then found
seven more strings that sat **after an `@`-expression** rather than after a tag, which the
replacement "scan visible text" method still missed. Each time the code was fine and the PROXY
was wrong. The sweep that finally held looks for text in every position it can occupy —
between tags, after an expression, in `placeholder`/`aria-label`/`title`, and in capitalised
string assignments.

**A FOURTH instance of the same lesson, found from outside the item (U-23, 06/08/2026).** Every
sweep above asks the same question — "is there Portuguese text left in this file?" — and all
four blind spots were about *where* the text sits. There is a second shape none of them can see:
the string WAS extracted, WAS translated in both catalogues, and the `.razor` was **never
switched over to read it**. Nothing is missing and nothing is unbalanced; the key simply has no
caller, and an English reader gets the original Portuguese. Six survived the item —
`ProfExportHint` (the whole LGPD paragraph), `ProfForgotCurrent`, `ProfPasswordLinkSentTo`,
`ProfResetByEmail`, `FamSending` (two call sites) and `RolesIntro` — plus two entries produced by
nothing (`SumNotSavedOne`/`Many`, duplicates of `BulkConflictSuffix*` created by the same
extraction). The existing gates were structurally incapable of it: both orphan tests compare the
catalogue against `K`, never `K` against a call site. Fixed here, with
`EveryDeclaredKey_HasACallSite` (a source scan of the app project, plus a companion test proving
the scanner matches known references so it cannot pass by matching nothing). The generalizable
form: *a translation is not delivered when the string is translated — it is delivered when
something reads it*, and only a gate that looks at the call site can tell the two apart.

**Gates left behind** (each exists because key parity cannot catch what it checks):
`LocalizationTests` (catalogue parity both ways, orphan keys and entries, matching placeholder
SETS, the `LanguageResolver` precedence rule, and — since PR 3a-Premium — that **numbers stated
in one language appear in the other**, that inline emphasis survives translation, and that the
markup is balanced, and — since the U-23 finding above — that **every declared key has a call
site**); `NotificationRendererTests` (every `type` + discriminator pair asserted
byte-for-byte against the sentence the writer stores); `NotificationParamsCoverageTests` (reads
`supabase/migrations` with `CREATE OR REPLACE` semantics and fails any live notification INSERT
that omits `params`); `RoleCatalogMirrorTests` (reads the Edge Functions' TypeScript and fails
when the role labels drift from `RoleCatalog`); and `LocalizationUiTests` (an `en-US` browser
gets an English screen).

**The delivery, PR by PR**

| PR | Version | What it carried |
|---|---|---|
| 1 | `1.7.16` | Infrastructure, language resolution, `profiles.language`, the picker, auth screens + app chrome |
| — | `1.7.17` | Built-in role labels (`RoleDefinition.LabelEn`, `RoleCatalog.Translate`) |
| 2a | `1.7.18` | Calendar surface + `DisplayCulture` for month/weekday names |
| 2b | `1.7.19` | Calendar sheets; `Pluralize` takes catalogue KEYS |
| 3a | `1.7.20` | `FamilyPage` minus Premium, `CustomRolesPage`, `SudoPrompt` |
| 3b | `1.7.21` | `ProfilePage`, `Leaving`, `PolicyUpdate`, `PremiumReturn`; `ChangeSummaryEn` |
| 3c | `1.7.22` | Notifications screen, Period Summary, Adjustment History |
| — | `1.7.25` | QA fix: the accent-grep blind spot |
| 4a | `1.7.24` | `notifications.params`, one trigger, `NotificationRenderer` |
| 4b | `1.7.26` | The other 9 functions / 13 INSERTs, 14 client sites, renderer wired to the screen |
| 3a-Premium | `1.7.27` | The billing block, reviewed sentence by sentence ([table](../../docs/reviews/u13-premium-ptbr-en.md)) |
| 5 | `1.7.28` | Both e-mail functions, the PDF page + document, `ExportService`, `AuditService` |
| 5 (corr.) | `1.7.28` | The six keys nobody was reading + `EveryDeclaredKey_HasACallSite`. No bump: `1.7.28` had not reached `dev` yet, so this is the same build being corrected before it ships, not a second one sharing a revision |

**Cross-repo.** The landing's English half is **L-16**, planned next in the landing repo.

<details>
<summary>Full working record (scope, split rationale, per-PR notes)</summary>

| Field | Value |
|---|---|
| **Status** | `pending` |
| **Priority** | `high` |
| **Complexity** | `high` |
| **Impact** | `high` |

> **Rewritten and promoted on 05/08/2026** (owner). The item used to read `low`/`low` —
> "a long-term improvement rather than an immediate fix", written when the app was a
> single-family PT-BR product. Two facts moved it to the head of the queue: the app is now
> **open to the international community**, and PT-BR-only is one of the **two reasons the
> tester recruitment stalled** (the other is U-23). Most of the developer community the owner
> can reach for a closed test does not read Portuguese, so the language barrier is not a
> comfort feature — it is what blocks the Play closed test from filling its ~12 seats.

**Description**
Every user-facing string in the product is hardcoded in PT-BR. Introduce a localization layer
and translate **all** of it to English, keeping PT-BR as the default for `pt-*` browsers. The
scope decision (owner, 05/08/2026) is **complete coverage, not UI-only**: a tester who reads the
app in English and then receives a PT-BR invitation e-mail or exports a PT-BR PDF has still hit
the wall the item exists to remove.

**Language selection (decided 05/08/2026): auto-detect + persisted manual override.**
On first load, resolve from `navigator.language` — `pt-*` → PT-BR, anything else → EN. The user
can override it in the profile/menu; the choice persists in `localStorage` **and** on the
profile row, so the server-side senders (e-mails, cron notifications) can address each recipient
in their own language instead of guessing. The override wins over detection on every later load.

**The four surfaces, in dependency order**

1. **App UI** — the 27 `.razor` pages/components plus the services that build user-visible
   strings. This is where the infrastructure lands and where most of the volume is.
2. **Transactional e-mails** — `send-swap-email` and `send-account-email` render their templates
   inside the Edge Function. They must take the recipient's language (from the profile column
   above) and pick the template set. **Remember the redeploy gotcha**: a template change with no
   redeploy silently sends zero e-mails.
3. **The PDF report** (`ReportPdfService` + `print.js`, F-33) — headings, the F-45 origin
   sentence and the U-20/U-07 summary labels. The report is the premium wedge; shipping it
   PT-BR-only to an English-speaking payer is worse than not shipping the gate.
4. **Notifications** — see the design decision below.

**Design decision — notification texts are written by the DATABASE, in PT-BR, at insert time.**
This is the one genuinely hard part and it must be settled before coding. `notifications.title`
/ `.message` are composed inside SQL triggers (the baseline swap fan-out, the auto-approval
fan-out, the S-11 departure notices, the F-38 quota, the T-39/S-15 billing warnings), so the
stored row is a *rendered PT-BR sentence*, and rows already in production cannot be retranslated.
The table already carries a `type` column plus `swap_request_id`, which is most of what a
client-side renderer needs. Recommended approach: **render on the client from `type` + a new
`params` JSONB column**, keeping the stored `title`/`message` as the fallback for legacy rows and
for anything the client cannot rebuild — so nothing in history changes and new rows become
localizable. Reject the alternative of a second set of PT/EN columns per row: it doubles the
trigger bodies for every future notification type.

**Out of scope (explicitly)**
- **Role labels — CUSTOM ones only.** The F-41 custom per-family roles are *user data*, not UI
  copy: a family that named a role "Vovó Zezé" keeps reading it in English mode.
  > **Clarified 06/08/2026 (owner).** This bullet's original last sentence — "only the
  > catalog's own built-in suggestions get English aliases" — was read during the PR 1
  > analysis as if ALL role labels were out of scope, and the gap surfaced in QA as an
  > English session showing "👨 Pai / 👩 Mãe / 👴 Avô". The owner ruled that roles are far too
  > central to the app to leave untranslated, which is what the sentence had always said.
  > **Delivered in `1.7.17`**: `RoleDefinition.LabelEn`/`LabelFor(AppLanguage)` +
  > `RoleCatalog.Translate(role, language)`, reaching all 12 consumers through the single
  > `ProfileService.TranslateRole` funnel (which now takes `LocalizationService` by
  > injection). The built-in/custom boundary needed no new code — `Find()` already returns
  > null outside the catalogue. Three labels carry `(m)`/`(f)` because Portuguese genders
  > what English collapses (`cousin_*`, `friend_*`, `guardian_*`) and those are distinct rows
  > profiles already point at; the emoji cannot disambiguate them in the calendar legend, the
  > PDF or the CSV, which print the label alone. **Still pending in PR 4**:
  > `send-swap-email/index.ts:281` keeps its own PT-BR mirror of the mapping for the
  > invitation e-mail.
- **GoTrue auth e-mails** (confirm / reset — runbook §5.4). GoTrue holds **one template set per
  project**, with no per-user language, so an EN version means either a bilingual template or a
  platform-level choice. Record the limitation in the runbook; do not let it block the item.
- **Legal pages.** `Pages/Privacy.razor` / `Terms.razor` are the *legal instrument* for a Brazilian
  service. Translating them creates a second normative text and a sync burden across two repos
  (the cross-repo MUST in `CLAUDE.md`). Ship an English **courtesy notice** pointing to the
  binding PT-BR text; a real translation is a legal-review item, not this one.
- **Free text written by users** (day observations, swap messages, family/role names) — never
  translated.

**Split (decided in the analysis step, 06/08/2026 — 4 PRs, not the 3 sketched below)**
`Home.razor` alone is 2,281 lines and `FamilyPage.razor` 1,407, so "infra + first-run
surfaces" in one PR would have been the infrastructure plus 40% of the app's markup.
- **PR 1 — DELIVERED (`1.7.16`)**: infrastructure, language resolution, the profile column,
  the picker, and the auth screens + app chrome translated (login, sign-up/invite,
  password recovery, `MainLayout` banners, `NavMenu`, 404, `AuthService` error messages).
- **PR 2 — split in two on 06/08/2026** (`Home.razor` alone holds ~160 strings; one diff that
  size is unreviewable and impossible to isolate if QA finds something):
  - **2a — DELIVERED (`1.7.18`)**: the calendar SURFACE — month header, legend, weekday
    initials, day cells + their accessible names, empty state, `TodayCard`, selection bar,
    navigation guard. Adds `LocalizationService.DisplayCulture` for month/weekday NAMES,
    passed explicitly per call site — never assigned to the thread culture, which stays
    invariant so ISO 8601 keeps reaching Supabase. Numeric date layout deliberately
    unchanged (that is U-24), pinned by a test: `FormatHandoffDate` in English returns
    `Fri, 17/07`, not `Fri, 07/17`.
  - **2b — DELIVERED (`1.7.19`)**: the SHEETS — day editor, bulk edit, resolve-requests,
    rotation wizard, frozen-day panel, and `BulkSummary`. `Pluralize` now takes catalogue
    KEYS: PT-BR agrees the participle in gender AND number, so a plural is not a stem plus
    "s"; the count moved INSIDE the catalogue text so a language that places it differently
    stays expressible.

> **Scope correction found while implementing 2b (06/08/2026).** This record said the
> notification texts are composed inside SQL triggers. They are — but **the CLIENT writes them
> too**: `SwapRequestService.CreateNotificationAsync` INSERTS `title`/`message` into
> `notifications`, including the row addressed to the OTHER caregiver. So translating them in
> 2b would make an English requester write English notifications into a Portuguese reader's
> inbox. The boundary is not per-file, it is **per reader**: what the ACTING user sees on their
> own screen was translated in 2b; everything read by someone else — the 12 trigger bodies AND
> the client-composed ones — goes to **PR 3** together, rendered from `type` + `params` in the
> READER's language. Owner decision, 06/08/2026.
- **PR 3 — split again on 06/08/2026** (the remaining screens hold ~388 accented lines, twice
  all of PR 2; `FamilyPage.razor` alone carries 152 of them):
  - **3a — DELIVERED (`1.7.20`)**: `FamilyPage` **minus its Premium block**, `CustomRolesPage`
    (F-41) and `SudoPrompt` (S-10).
  - **3a-Premium — DELIVERED (`1.7.27`)**: the billing block of `FamilyPage`, on its own and
    reviewed line by line, plus the `PremiumReturn` re-read. The PT-BR × EN table the record
    asked for is versioned at [`docs/reviews/u13-premium-ptbr-en.md`](../../docs/reviews/u13-premium-ptbr-en.md)
    — in the repo rather than in a PR comment, so the reasoning survives the merge.
    **Shape: one paragraph = one catalogue entry**, rendered through the new
    `LocalizationService.Rich` so the inline `<strong>` survives. That emphasis is not
    decoration here — "**nenhum dado é apagado**", "**sem renovação automática**" and
    "**você paga agora**" are the reassurances that stop a misreading, and fragmenting a
    sentence to preserve them would reintroduce exactly the risk this slice was split out to
    avoid. `Rich` HTML-encodes the ARGUMENTS and not the catalogue text: today the arguments
    are dates and prices, but encoding them now means a future key interpolating a NAME
    cannot inject markup — a failure that would otherwise surface far from its cause.
    Where the copy had an optional clause it became **whole alternative sentences**: the
    cancel warning has a with-date and a without-date version, and the reactivation hint has
    **four** (with/without payment method × with/without first-charge date), because that is
    the sentence stating WHEN the charge is issued.
    **Verified, not assumed**: "2 meses grátis" holds by construction — `app_settings` has
    `billing.price_annual_cents` 5490 ÷ `billing.price_monthly_cents` 549 = 10 exactly, so the
    annual plan costs ten monthly payments. If that ratio ever changes, the copy must change
    with it, in both languages.
    **`BillingService.DescribeHistoryCategory`/`DescribeBillingType` now return catalogue KEYS**
    (`HistoryCategoryKey`/`BillingTypeKey`): the ledger is read by whoever opens it, so the
    label follows the READER.
    **Two decisions flagged for the owner in the table**: "Pix" stays untranslated (proper
    noun, and what the bank app itself calls it), and the price keeps Brazilian formatting
    (`R$ 5,49`) in both languages — the charge is in reais, and swapping the decimal separator
    on a price is how someone misreads what they owe; number formatting per language is U-24
    by design. A test pins the second one, so reversing it is a deliberate act.
    **Three gates the key-parity test could never provide**, all catalogue-wide rather than
    billing-specific: `NumbersInsideAText_AreTheSameInBothLanguages` (a "7-day guarantee" that
    became "14 days" is a divergence of FACT and passes every other check — it found a real
    difference on its first run, the example placeholder reading `18h` against `6pm`, exempted
    because a clock convention states nothing about the product),
    `EmphasisSurvivesTranslation`, and `MarkupInsideCatalogueEntries_IsBalanced` (these
    strings render as markup, so an unclosed tag does not appear as stray text — it swallows
    the rest of the page).
  - **3b — DELIVERED (`1.7.21`)**: `ProfilePage`, `Leaving`, `PolicyUpdate`, `PremiumReturn`.
    `PolicyVersions.ChangeSummary` gained a COURTESY English rendering (`ChangeSummaryEn`) —
    that summary exists for LGPD art. 9, so leaving it PT-BR on an English screen would ask
    someone to accept a diff they cannot read. It lives beside the original (not in the string
    catalogue) so both versions of one legal statement fit in a single diff, and 3 tests pin
    that the two lists stay the same length with no empty entry — key parity cannot catch that,
    because they are not keys. **`PremiumReturn` is ON THE REVIEW LIST** with the Premium block:
    it states the F-48 7-day refund guarantee, which is a commercial promise.
  - **3c — DELIVERED (`1.7.22`), with a QA fix in `1.7.25`**: Notifications + the Period Summary
    + the Adjustment History. The fix caught what 3c missed and, more usefully, WHY: every
    slice had been verified with `grep` for **accented** literals, and "Dias", "Total", "Nome",
    "Papel", "Resumo" and "PDF" carry no accent — the proxy returned zero and the screen was
    declared clean. `ReportsTabs.razor` (the Resumo · Histórico · PDF sub-nav on all three
    report screens) and two `CultureInfo.CreateSpecificCulture("pt-BR")` month-name calls
    survived that way. **Verify by scanning VISIBLE TEXT** — content between tags,
    `placeholder`, `aria-label`, `title`, capitalised string assignments — not by accent.
    Still PT-BR by COUPLING: `AuditService.ResolutionOriginText` and `ComputeDiff` are shared
    with `ReportPdfService`, so they move with the PDF slice; `AccountActionLabel` is the
    History's alone and fits there too.
    **`ReportsPdf.razor` deliberately excluded**: the PDF DOCUMENT is generated from that page's
    own `rp-*` markup by `print.js`, so the page and `ReportPdfService` are ONE deliverable —
    translating half would leave an English form producing a Portuguese document. It ships with
    the PDF slice (PR 5), together with `ExportService`.
- **PR 4** — the notification RENDERER. Split in two by the owner (06/08/2026): prove the
  pattern on ONE trigger, then replicate.
  - **4a — DELIVERED (`1.7.24`)**: the `notifications.params` column, `auto_approve_expired`
    rewritten to fill it, `NotificationRenderer` + its catalogue entries, and the tests for
    both halves. The pilot found two defects that would have been copied twelve times:
    `AppNotification.Params` typed as `string` (the column is JSONB, so Newtonsoft threw on
    the WHOLE response — every client read of the table would have broken the moment a row
    carried params), and a third instance of the backdated-seed landmine (60h collided with
    `AutoApprovalTests`; now 30h/108h/156h).
  - **4b — DELIVERED (`1.7.26`)**: the rest of the writers, plus the wiring the pilot left
    undone. Measured against the DEV `pg_proc` rather than trusted from this record, the
    remainder was **9 functions / 13 INSERTs**, not the 11/~33 estimated above — the estimate
    had counted superseded bodies of the same function. Client side: **14 INSERT sites** in
    `SwapRequestService`.
    **The most important defect it fixed was not in the plan.** PR 4a shipped
    `NotificationRenderer` with 18 unit tests and *no caller*: `Notifications.razor` still
    printed `@notif.Title`/`@notif.Message`, so even a row WITH params rendered PT-BR for an
    English reader. The renderer was dead code, and the suite could not notice because it
    tested the function rather than the screen. **The generalisable lesson: a pure helper with
    green tests proves nothing about the product until something calls it** — the pilot's
    "prove the pattern" step should have included the read path, not only the write path.
    **New discriminators** (one `type`, several wordings): `family_deletion` has SEVEN
    (`requested_self`/`requested_other`/`agreed`/`agreement_undone`/`refused`/`withdrawn`/
    `reminder`), `account_deletion` three, `email_cap_reached` two (premium × free), and
    `swap_cancelled` two — that last one a REAL collision, since `SwapRequestService` and
    `request_account_deletion` write the same type with unrelated copy.
    **Owner decisions taken in the analysis step (06/08/2026)**: (a) the urgency prefix
    (⚠️ URGENTE / ⏰ ATRASADO) travels in `params` and IS translated — it is content, unlike the
    `[Dev]` environment prefix the renderer drops; (b) the PT-BR catalogue entries are
    **byte-identical** to the stored sentences, so wiring the renderer cannot make a Portuguese
    reader's history appear to change retroactively; (c) the destructive RPCs
    (`request_account_deletion`, the family-deletion trio) are covered by a static gate rather
    than executed, since driving them in the shared family would dismantle it.
    **Structural change**: `notify_family_email_cap` takes its title/message from the caller,
    so it needed a new argument — and `CREATE OR REPLACE` cannot change an argument list (it
    would leave an overload), hence `DROP` + `CREATE` with `consume_email_quota` rewritten in
    the same migration. In passing it lost `EXECUTE` for `PUBLIC`, which it had only by
    default for never having carried an explicit GRANT.
    **Two shapes worth reusing.** The free-text suffix (F-44) became the LAST placeholder of
    every text that accepts a message instead of something the code concatenates — same
    reasoning as the 2b `Pluralize` decision, and it is what turns "recusou reverter … A troca
    permanece ativa", where the suffix lands MID-sentence, from a special case into an
    ordinary entry. Name fallbacks got one key per SURFACE FORM ("Outro responsável", "O outro
    responsável", "o outro responsável", "o responsável planejado"); collapsing them into one
    rendered a capital mid-sentence whenever a profile lookup came back empty.
    **The coverage gate is `NotificationParamsCoverageTests`**, and it is the durable answer to
    "did we remember all of them": it reads `supabase/migrations` applying `CREATE OR REPLACE`
    semantics (last definition wins, superseded bodies ignored) and fails any still-live INSERT
    into `notifications` that omits `params`. It needs no database and fires the second a
    migration is written — the file it checks is the one CI applies to production. A companion
    test asserts the scanner actually matches the known writers, so it cannot pass by matching
    nothing.
    Coverage: **+93 unit** (the `PtBr_Rendering_MatchesTheStoredSentence` table walks all 33
    type/discriminator pairs asserting byte equality with the stored sentence, doubling as the
    coverage gate — a missing branch falls through to a sentinel; plus the English mirror, the
    discriminators that must not collapse, unknown-discriminator fallback and the blank-message
    rule) and **+1 integration** (`MemberJoining_WritesTheNameAsRenderData`, end to end in a
    throwaway family). Local green: 456 unit, 195 integration (full suite).

> **Recipe for 4b**, distilled from the pilot — follow it literally, the hazards are real:
> 1. Per function, `grep -n 'FUNCTION public.<name>' supabase/migrations` and start from the
>    **most recent file**, never from memory (the `CREATE OR REPLACE` gotcha).
> 2. Copy the body verbatim; the ONLY edit is adding `params` to the INSERTs.
> 3. `params` carries VALUES, never sentences — plus a discriminator whenever one `type` has
>    more than one wording (`role` in `auto_approved` is the worked example).
> 4. After applying on DEV, inspect `pg_proc.prosrc` to confirm that function's own rules
>    survived. That is how the F-47 restore was proved still present.
> 5. Backdated seeds in the shared family must differ by ≥24h AND avoid the offsets the
>    neighbouring suites already use.
- **PR 5 — DELIVERED (`1.7.28`)**: the two e-mail Edge Functions, the PDF page + the document
  it generates, `ExportService` and the three `AuditService` helpers. The e-mails are the only
  surface where the language cannot be resolved on the client — they run on a cron with no
  browser — so `profiles.language` is read **per recipient, not per message**: `auto_approved`
  writes to both parties in one call, and the family-deletion fan-out writes to everyone.
  New `supabase/functions/_shared/i18n.ts` keeps the template markup written ONCE with only the
  text varying, in typed `Record<Lang, …>` tables, so a missing key is a compile error rather
  than an `undefined` in an e-mail already sent.
  **The invitation goes out in the INVITER's language** — the invitee has no profile yet, so
  that is the best signal available and at worst as wrong as the hardcoded Portuguese it
  replaces. Documented as a limitation, not as a result.
  **The role label in the invitation** stopped being the raw `label_pt`: `roles` has no
  `label_en`, so the module carries a `RoleCatalog` mirror, and `RoleCatalogMirrorTests` reads
  the TypeScript file and fails on drift in BOTH directions. A mirror nobody checks rots
  silently — someone adds a role, the e-mail keeps sending the Portuguese label, nothing fails.
  **The origin sentence became four WHOLE entries** instead of a "kind" + "resolution" pair:
  Portuguese agrees the participle with the noun it follows, so the fragments are not
  independent. The LGPD export's notifications now render through the same renderer as the
  screen — the export and the Histórico must not disagree about what a notification says.
  **Found during the sweep**: seven PT-BR strings had survived in `Notifications.razor` since
  PR 3c, all in a position the earlier scan could not see — **after an `@`-expression** rather
  than after a tag. Third instance of the same blind spot; the app's last
  `CultureInfo.CreateSpecificCulture("pt-BR")` fell here too.
  Validation: `deno check` clean on both functions (and the other six). There is no Deno in the
  repo environment, so a temporary one was installed for it — it is what catches type and
  reference errors, the real risk of writing TypeScript blind. Local green: 469 unit, 195
  integration (full suite), 56 E2E (FULL pack).

**Decisions taken in PR 1 (they bind the rest of the item)**
- **Mechanism: compiled C# dictionaries**, not `.resx`/`IStringLocalizer` and not JSON.
  `Program.cs` pins `InvariantCulture` for FORMATTING (ISO 8601 to Supabase) and `.resx`
  would have required moving `DefaultThreadCurrentUICulture`, coupling the two; a typo in a
  `K.` constant fails to compile, while `IStringLocalizer["key"]` fails silently in front of
  a user; and satellite assemblies cost a per-culture download plus a boot-time reload.
- **The language is fixed at boot and a switch does a `forceLoad`** — the same idiom
  login/logout use to recreate the DI scope. No component subscribes to a change event, so
  no screen can render half-translated. Cost: one reload on an action taken about once.
- **`profiles.language` is NOT redundant with localStorage.** localStorage is the client's
  truth (it must work on the login screen, before a session exists); the column is the
  SERVER's copy, for senders that have no browser to ask. NULL is never backfilled —
  "never chose" and "asked for Portuguese" are different facts.
- **Consent declarations get an English COURTESY translation** (`ConsentDeclarations.*En`)
  plus an on-screen notice naming the Portuguese text as the binding one. This follows the
  "English courtesy notice" decision above without creating a second normative text.
- **Role labels: RESOLVED, in scope** — see the Out-of-scope note above. Built-in catalogue
  roles are translated (`1.7.17`); only F-41 custom roles pass through.
- **Dates: split out as [U-24](#u-24--date-and-number-formatting-per-language).** They render
  as `dd/MM` in every language, so an English reader may parse `05/08` as May 8th. Changing it
  touches the whole calendar AND the `InvariantCulture` pin that keeps ISO 8601 on the wire, so
  it is not a decision to take in passing inside a translation PR (owner, 06/08/2026).

**Files affected**
- New localization infrastructure — `.resx` satellite assemblies (`IStringLocalizer`, the
  framework-native path) or JSON locale files loaded at startup; decide in the analysis step.
  Note `Program.cs` currently pins `CultureInfo.InvariantCulture` for *formatting* — the
  UI culture must move without dragging number/date parsing with it.
- All `.razor` pages/components + `Layout/` — inline strings become resource keys
- `SharedParentalCustody/Models/Profile.cs` + a migration — persisted language preference
- `SharedParentalCustody/Services/ReportPdfService.cs`, `wwwroot/js/print.js` — PDF strings
- `supabase/functions/send-swap-email/index.ts`, `send-account-email/index.ts` — template sets
- A migration adding `notifications.params` (JSONB) + the trigger bodies that fill it — start
  from the **latest** body of each function, per the `CREATE OR REPLACE` gotcha in `CLAUDE.md`
- `SharedParentalCustody.Tests` — resource-key parity (no key present in one locale and missing
  in the other) and the language-resolution rule; an E2E that loads the app with an `en-US`
  browser locale and asserts an English screen

**Cross-repo**
The landing (`guardacompartilhada.com`) is the page a recruited tester reads **before** the app.
Its English half is **L-16** in the landing repo, planned right after this item.

</details>

---

### U-23 — First-run onboarding: activation checklist + short guided tour

| Field | Value |
|---|---|
| **Status** | `completed` — `1.7.29` (PR 1) + `1.7.30` (PR 2) |
| **Priority** | `high` · **Complexity** `medium` · **Impact** `high` |

**Why it existed.** Recruitment blocker #2, created 05/08/2026 alongside U-13 out of the failure
to fill the Play closed test. A new user landed on an empty calendar and was told what to *tap*,
never what the product *is*: nothing explained that the app models a **planned** responsible
against the **real** one, that a change needs the **other parent's approval**, or that none of it
works until the co-caregiver is invited. A tester who never reaches the second parent never sees
the product at all — the swap workflow, which is the entire wedge, requires two people.

**What shipped.** Three pieces, in two PRs.

1. **"Primeiros passos"**, an activation card on Home between the today card and the calendar —
   the first thing read after "who has the child today", and before a grid a first-timer cannot
   yet interpret.
2. **"Como funciona a troca"**, a bottom sheet carrying the concept: planned × actual, why the
   other person must accept, what a frozen day is, that the history is immutable.
3. **A four-stop guided tour** over the real elements, on the first entry.

**The rule the checklist is built on.** *Every step ticks itself off from REAL state, never from
a "seen" flag.* Convidar is done because an invitation is open or a second member exists;
planejar because a `care_schedules` row exists — any row, any date, deliberately not "this
month", or the card would reset itself on the 1st and be measuring the calendar instead of the
person. A stored "done" that disagreed with the family would be **worse than no card**, because
the only thing the card asserts is that it describes *that* family.

The single exception is understanding, and it is deliberate: comprehension is not a row in any
table. So the step closes by opening the explanation — or, better, by **having taken part in a
swap**, which is real state and is why the second signal exists. That second path is also what
keeps the step honest for an invitee who arrives into an active family and never needed the
screen.

**The fourth step was dropped, not implemented.** The item's own record proposed "Completar o
perfil — only if something is actually missing". Checked against the code *before* building it:
sign-up **requires** the full name (`Register.razor`, `required` plus the `Validate()` guard) and
the role is either chosen there (creator) or carried by the invitation (invitee). No profile
field can be missing, so the step would have been one of two useless things — permanently green,
dead weight on a card whose whole value is that every line is actionable, or permanently red,
nagging about something with nothing to fix. `OnboardingSteps` documents where it would go if a
genuinely optional field ever appears. **This is the S-15 lesson applied to a backlog record
instead of a legal text**: a written claim about the system is worth exactly as much as the last
time somebody checked it against the code, no matter who wrote it — including us.

**Where the state lives.** Three `timestamptz` columns on `profiles`
(`onboarding_swap_explained_at`, `onboarding_tour_seen_at`, `onboarding_dismissed_at`), not
`localStorage`. The onboarding is about a **person**: someone signing in on a second phone must
not meet the first-run experience again, and a dismissal is a real decision — losing it by
changing devices is losing the decision, not a cache. Timestamps rather than booleans, matching
`consent_accepted_at` / `left_at`: they answer "did it happen" **and** "when", which is the only
way a later question ("do people dismiss the card before or after inviting?") can be answered
from data that already exists. The columns stay **out of `enforce_profile_protection`** — that
trigger is a blacklist of system-managed / privilege-bearing fields, and "I read the explanation"
is neither; `profiles_own_update` is the whole authorization story. Same reading as U-13's
`language` column.

**Cost on Home was measured, not assumed** — it is the most-loaded screen in the app. Both
existence checks ask for `Limit(1)` and a single column; the swap-participation check only runs
when the explanation was never opened; and a member who dismissed the card **pays for no query at
all**. Reading the facts (`OnboardingService`) is separated from deciding what they mean
(`OnboardingSteps`) precisely so the rules stay testable without a connection.

**Why the tour is a spotlight and not anchored balloons.** An anchored balloon needs runtime
positioning, and at 344 px — the width this app is held to — there is frequently no side of the
target with room for one: it lands on top of the thing it points at, or off-screen. A card pinned
above the bottom nav always fits, always reads in the same place, and has no measurement to get
wrong.

Two implementation facts that are easy to get wrong and were:
- **The highlight is applied from OUTSIDE the component** (`wwwroot/js/tour.js`), because the
  elements belong to other components — the notifications tab lives in the nav. It walks the
  ancestors: a `z-index` only competes inside its own stacking context, so lifting the target
  without lifting the `position: fixed` nav would leave the tab highlighted in a layer nobody can
  see.
- **It picks the first VISIBLE match, not the first in the DOM.** The layout ships both navs — a
  top bar for wide screens, a bottom tab row for narrow ones — and hides one with a media query,
  so a shared marker class has a 50% chance of resolving to the invisible copy. Highlighting
  something nobody can see is a dead stop: the screen dims and nothing lights up.

**A rule from PR 1 that PR 2 had to correct.** `ShouldShowChecklist` hid the card when it was
dismissed *or* finished — and those are exactly the two states somebody pressing "Rever os
primeiros passos" is most likely to be in, so the button silently did nothing for its whole
audience. It now takes an explicit `reopened` override. The generalizable form: a rule that hides
something needs a way to say "the user asked for it anyway", or the escape hatch is decorative.

**Gates left behind**
- `OnboardingStepsTests` — the step rules, the invitee's nearly-done arrival, dismissal, and the
  reopen override.
- `TourStepsTests` — the stop list, and the one that matters: **every selector must still match a
  class some `.razor` renders**. A tour step whose element was renamed away fails silently, because
  `querySelector` returning null is an ordinary thing for it to do — the screen dims and highlights
  nothing at the exact moment the app is making a first impression. A companion test asserts the
  scanner really reads files, so it cannot pass by matching nothing.
- `FirstRunUiTests` (E2E) — the four stops with the class landing on the REAL element, the tour
  not running twice, the checklist ticking from family state, and dismiss → reopen from the
  profile. Each test uses a throwaway family and resets the three stamps first: watching a tour is
  a persistent change to a person, so sharing the fixture's founder would let whichever test ran
  first decide what the others saw.

**The delivery, PR by PR**

| PR | Version | What it carried |
|---|---|---|
| 1 | `1.7.29` | Migration + the three columns, `OnboardingSteps`, `OnboardingService`, the checklist, "Como funciona a troca", the profile door |
| 2 | `1.7.30` | `TourSteps`, `GuidedTour`, `js/tour.js` + the global spotlight CSS, the replay flags, the `reopened` override, `FirstRunUiTests` |

**Validation note, unusual and worth recording.** Both PRs were built during the 06/08/2026
GitHub Actions incident, in a session that started with **no .NET SDK**. The SDK turned out to be
installable from `packages.microsoft.com` (the official CDNs are refused by the environment's
network policy), which bought the compiler and the whole unit suite — but `*.supabase.co` is
refused by that same policy, so **integration and E2E never ran**: they were written, and their
first execution is whatever green CI run follows. The migration was dry-run on DEV through the
Supabase MCP, which does not go through that proxy. Both facts are now in `CLAUDE.md` so the next
session does not rediscover them.

**Relationship to U-04 (Phase 2).** U-04's empty-state hint inside the grid stays: it answers
"this month is empty", a state that recurs long after onboarding. U-23 answers "what am I supposed
to do with this product", and does not repeat its wording.

**Cross-repo.** **L-16** (the landing's English half) is the other end of the same recruitment
problem — the tester reads the site before the app.

---

### U-24 — Date and number formatting per language

| Field | Value |
|---|---|
| **Status** | `completed` (`1.7.31` + `1.7.32`) |
| **Priority** | `medium` |
| **Complexity** | `medium` |
| **Impact** | `medium` |

> **Created 06/08/2026** (owner), split out of U-13 during the PR 1 review. U-13 translates
> *strings*; this is *formatting*, and the two failed differently enough to deserve separate
> items — a wrong word is read as a missing translation, a wrong date is read as the wrong day.

**Description**
Every date in the app renders as `dd/MM` (or `dd/MM/yyyy`) in **every** language, because
`Program.cs` pins `CultureInfo.InvariantCulture` for both formatting and parsing. For a
PT-BR reader that is correct. For an English reader it is actively misleading: `05/08` is
5 August here and reads as May 8th to most of the anglophone world — and unlike an
untranslated label, nothing on screen signals that something is off. The reader simply
believes the wrong day.

Decide and apply a per-language date/number format for **display**, without touching what
goes on the wire.

**Why it was not folded into U-13**
Three reasons, all of which surfaced in the PR 1 analysis:
1. **The invariant pin is load-bearing.** It exists so every date sent to Supabase is ISO 8601
   (`2026-06-30`). Any change here must keep the *transport* format frozen and move only
   *display* — the two are currently the same call, which is exactly the trap.
2. **It touches the whole calendar**, the biggest surface in the app (`Home.razor`, 2,281
   lines), plus the PDF report, the CSV export and the audit history.
3. It is a **product decision** (does an EN session get `MM/dd/yyyy`, or the unambiguous
   `dd MMM yyyy`?), not a translation task.

**Design questions to settle before coding**
- **Which English format**: `MM/dd/yyyy` (US expectation, still ambiguous to a UK reader) vs.
  `dd MMM yyyy` / `MMM d, yyyy` (unambiguous in every locale because the month is a word).
  The second is the safer default for an app whose whole job is "who has the child on which
  day", and it sidesteps having to model regional English variants.
- **Month and weekday names** in the calendar header/legend — these are strings, and belong
  in the U-13 catalogue rather than in `CultureInfo`, for the same reason the UI language does
  not ride the culture.
- **Parsing**: any `DateTime.Parse`/`TryParse` on user input must stay invariant or become
  explicitly format-aware. A display change that silently alters parsing is how a swap lands
  on the wrong day.
- **Numbers**: currency already renders as `R$ x,yz` in the billing/paywall copy. Decide
  whether an EN session keeps BRL formatting (it is a Brazilian service charging in BRL, so
  probably yes — the *price* is not localized, only the surrounding words).

**Files affected**
- `SharedParentalCustody/Program.cs` — the culture pin, and the comment explaining which half moved
- A formatting helper (e.g. `Helpers/DateFormats.cs`) so no page calls `ToString("dd/MM")` directly
- `Pages/Home.razor`, `Layout/MainLayout.razor`, `Pages/Reports*.razor`, `Services/ReportPdfService.cs`,
  `Services/ExportService.cs` — every current `dd/MM` call site
- `SharedParentalCustody.Tests` — the formatting rule per language, and a regression pinning that
  what reaches Supabase is still ISO 8601 in an EN session

**Depends on**
U-13 (the language layer). Executable as soon as the language is resolvable, i.e. now.

**Decisions settled (owner, 06/08/2026)**
- **English gets the month by NAME** — `05 Aug 2026` / `05 Aug`, not `MM/dd/yyyy`. The numeric
  US form only *moves* the ambiguity from an American reader to a British one, and the session
  has one English, not five.
- **English gets a 12-hour clock** (`2:30 PM`); PT-BR keeps `14:30`.
- **Prices stay `R$ 5,49` in both languages.** The charge happens in BRL, and a price is not
  a translatable string — swapping the comma for a dot states a different amount to anyone who
  reads it as their own convention.
- **Notification dates move to ISO in `params`**, so the reader's device decides the format.

**What PR 1 delivered (`1.7.31`)**
- `Localization/DateFormats.cs` — the ONLY place that decides a display format, as extension
  methods on `LocalizationService` (it already holds the language, and every page injects it
  as `L`). Placed here rather than in `Helpers/` for that reason.
- 37 display call sites migrated across `MainLayout`, `FamilyPage`, `Notifications`,
  `ReportsAudit`, `ReportsPdf`, `FrozenDayPanel`, `Home` and `Leaving`.
- **The transport half never moved.** The `Program.cs` pin stays exactly as it was — the
  comment there was already right, and the fix was to stop *display* riding on it, not to
  loosen it. `ReportsPdf.Fmt` stopped being `static` for the same reason.
- **Migration `20260807000000`** — the five notification writers store `params.date` in ISO.
  Bodies extracted VERBATIM from their latest definitions with the date expression as the only
  edit (14-line diff), then verified by comparing `md5(prosrc)` on DEV against the source files
  — the deployed bodies were byte-identical, so nothing had drifted via the Dashboard.
- **No backfill, by design.** `FormatIsoDate` returns anything that is not ISO unchanged, so a
  row written before this item renders exactly as its reader first received it. A pleasant
  consequence: the pre-existing `NotificationRendererTests`, which all feed `"04/08"`, became
  the legacy-passthrough regression without a line changing.
- **Deliberate widening**: `auto_approve_expired` wrote `DD/MM` while `SwapRequestService`
  wrote `DD/MM/YYYY` for the *same* notification type. Rendering now normalizes both to the
  full date, so a PT-BR reader sees `05/08/2026` where the cron used to say `05/08`. That
  removes an existing inconsistency rather than adding one.
- **Fixed in passing**: a U-13 residue in `ReportsAudit.razor`, where the wrapper around an
  already-translated action label was still PT-BR — an English reader read
  "created a new schedule **para este dia**" and "**Dia:** 05/08/2026". Same lines this item
  had to touch anyway.
- New gate `DateFormatsTests`, plus three renderer tests for the ISO path.

**What PR 2 delivered (`1.7.32`) — the e-mails**
- **The structural defect was not the format — it was WHERE the date was computed.**
  `send-swap-email` computed `dateFormatted` ONCE, outside `buildEmails`, and
  `send-account-email` computed `deadline` once for the requester *and* every other member —
  while each branch already had the recipient's `lang` in scope. For the types that notify
  both parties in a single call (`auto_approved`, the family-deletion fan-out) that means
  **one of the two was receiving the other's format**. Formatting moved inside the branches.
- **`formatDateIn` / `formatTimeIn` in `functions/_shared/i18n.ts`** — the server-side mirror
  of `DateFormats.cs`. The invitation keeps using the INVITER's language, as U-13 decided:
  an invitee has no profile yet, so there is no language of their own to read.
- **No `Intl`/`toLocaleDateString`, deliberately.** It would bind the output to whatever ICU
  data the Deno runtime ships, so a platform upgrade could restyle every e-mail we send with
  no commit to point at. The price of hardcoding is drift, and `EmailDateFormatMirrorTests`
  is what makes drift red: it reads the TypeScript, compares all twelve month abbreviations
  against what the app actually renders, and also pins the SHAPE of the assembly — an e-mail
  saying `Aug 05, 2026` while the screen says `05 Aug 2026` would pass a token-only check and
  still be two spellings of one day. A companion test proves the scanner matches something,
  so a renamed constant cannot make it pass over an empty list.
- **The `"30 dias"` fallback** in `send-account-email` was hardcoded PT-BR in every language;
  it moved to the catalogue as `fallbackThirtyDays`. The timezone shift was split from the
  formatting (`isoDayInSaoPaulo` + `deadlineFor`) because they answer different questions:
  which day it is, versus how that day is written. Only the second depends on the reader.

**Why the split into two PRs**
E-mail carries its own failure mode — an outdated function silently sends **zero** e-mails,
with nothing surfacing it — so it earned its own redeploy and QA pass rather than riding along
with a 37-call-site client refactor.

---

### F-54 — Rebranding to "Entrelares" (name, brand assets, possibly domain)

| Field | Value |
|---|---|
| **Status** | `done` — delivered 12–13/08/2026 across **six versions**: `1.8.2` (everything the user sees + the domain, with the landing pair L-22), `1.8.3` (internal code rename), `1.8.4` (the Emblema identity — promotion A, which also carried the sender cutover of runbook 5.8), `1.8.5` (the fallback sender), `1.8.6` and `1.8.7` (the Android shell correct at its first upload + the app-signing fingerprint in `assetlinks.json` — promotion B, 13/08). The Play app `com.entrelares.app` is live in closed testing with 12 testers opted in, and the store-installed app opens full-screen. **What deliberately did NOT close with it:** retiring the legacy package — its `assetlinks.json` statement and the old referrer prefix are a bridge for whoever still has the previous app installed, and they come out when that app is unpublished. Tracked as **T-52**. |
| **Priority** | `high` — every day before the new track's rollout was a day the 14-day clock was not running |
| **Complexity** | `high` — full rename: name, Play package AND domain, all three layers in the item |
| **Impact** | `high` (identity of the product for everyone arriving from outside) |
| **Roadmap** | Group 4 (distribution) — executed first in the group, 12–13/08/2026 |
| **Cross-repo** | **L-22** (opened 12/08/2026, delivered with PR 1): landing content, domain, hreflang/canonical/sitemap, legal sync. Screenshots re-shoot stays L-21 |

> **Created 12/08/2026 from closed-alpha feedback.** Two testers independently criticized the
> name: *"É só o nome do teu aplicativo que está confuso pra mim. […] por exemplo não tenho
> guarda compartilhada […] acho que tinha que mudar um nome […] que ser um nome mais atrativo"*
> and *"o objetivo é a guarda […] mas o nome não precisa ser isso. […] essa ideia entre lares
> […] tu está trazendo um olhar mais afetivo do negócio […] quanto mais humanizado […] fica
> mais fácil"*. Candidate settled in the WhatsApp thread: **Entrelares** (invented word, almost
> certainly registrable — only small unrelated CNPJs found, e.g. a clinic in Recife), tagline
> **"Duas casas, uma mesma infância."** The second quote also carries a positioning insight worth
> keeping: users want to cite the app **in court/audiências as evidence** — the humanized name
> lowers the barrier to adopting it, while the immutable record is what makes it citable.

**Description — three independent layers with very different costs**

**Layer 1 — name & brand (cheap, no Play-test restart).** Display name everywhere the user
reads it: `Localization/StringsPtBr.cs` + `StringsEn.cs`, `wwwroot/manifest.webmanifest`
(`name`/`short_name`), `wwwroot/index.html` (title), the e-mail senders' display name and
templates (`supabase/functions/_shared/i18n.ts` + the send-* functions), PDF report header,
`Pages/Privacy.razor`/`Pages/Terms.razor` product name, `store/listing-pt-BR.txt` +
`listing-en-US.txt`, `twa-manifest.json` `name`/`launcherName` (+ `bubblewrap build`, version
code +1, normal upload to the SAME track), Play Console listing (name, icon if redesigned,
feature graphic), and the landing content. **The legal-page rename is NON-material: only the
"Última atualização" date moves — do NOT bump `PolicyVersions.Current`** (a bump would drag the
whole base through the re-consent hard lock for a name change).

**Layer 2 — Play package id (a decision, not a task — and it expires).** The package
`com.guardacompartilhada.app` can NEVER be changed on an existing Play app. Either it stays
forever under the new brand (harmless: visible only in the Play URL), or a NEW app is created
as `com.entrelares.app` — which restarts the closed test from zero (new track, 14 uninterrupted
days, the ≥12 testers must re-opt-in via a NEW link, Data Safety/content rating/app access
forms re-filled, assetlinks re-paired). Restarting is only cheap while the current test is days
old; after production access it means abandoning installs/reviews. **Decide during the alpha or
accept the legacy package forever.**

**Layer 3 — domain (IN scope — owner decision 12/08/2026).** The client is domain-agnostic
(`BaseUri`), so the app itself barely cares — the cost is around it: new domain purchase +
Cloudflare Pages custom domains (app + landing), TWA `host` change (rebuild + assetlinks.json
served on the NEW host with the same fingerprints), GoTrue Site URL/Redirect URLs, **Resend:
verify the new sending domain (SPF/DKIM/DMARC from scratch)**, mailbox moves (`privacidade@`,
`suporte@`, `noreply@` — old addresses stay as receiving aliases; `privacidade@` is named in
the privacy policy), `send-swap-email`'s `APP_URL` fallback, and permanent 301s from the old
domain (links live in already-sent e-mails). Originally phaseable; the owner folded it into this
item — a brand pointing at another brand's domain undercuts the rebrand.

**Decisions locked (12/08/2026, owner)**
- **Package id swaps now**: new Play app `com.entrelares.app`; the current closed test is
  abandoned and the 14-day / ≥12-tester clock restarts on the new track. Rationale: the test
  was days old — this is the only cheap window the swap will ever have.
- **Full domain migration is IN scope**: *"tudo que aponta para guardacompartilhada"* moves to
  the new brand — site, app host, e-mail senders and mailboxes, GoTrue, Play listing URLs.
- **Domain acquired 12/08/2026: `entrelares.app`** (`entrelares.com.br` was taken). The `.app`
  TLD is HSTS-preloaded — browsers refuse plain HTTP on every subdomain; the stack is already
  100% HTTPS, so this is a free hardening, but it rules out any future non-HTTPS use. The
  **PWA host is `web.entrelares.app`** (`app.entrelares.app` would stutter; `web` is neutral
  in both languages and names what it is — the web app versus the store app). Landing +
  mailboxes on the apex (`noreply@`/`privacidade@`/`suporte@entrelares.app`).
  `entrelares.app.br` was NOT bought now — deferred until the app has revenue, tracked as
  **T-51** (group 8) so it is not forgotten.
- Remaining defaults (revisit only if the owner objects): **upload keystore is REUSED**
  (`store/android.keystore` — one key may sign any number of package ids, and it only signs
  uploads; Play generates a fresh app-signing key for the new app regardless); **launcher
  name** `Entrelares` (fits — current is `Guarda`); **icon/visual identity unchanged** for
  now (an icon change later needs no new app, just a shell update).

**Execution plan** — ready to start: the domain is bought and named (`entrelares.app`).

*Phase 0 — owner:*
1. ~~Choose + buy the domain~~ **DONE 12/08/2026 — `entrelares.app`** (`.app.br` deferred to
   T-51).
2. **INPI search** for "Entrelares" (https://busca.inpi.gov.br/pePI/ → Marca → busca por
   radical) in classes 9 (software) and 45 (legal/social services). The WhatsApp research
   found only small unrelated CNPJs; verify before spending on assets. Filing can follow later.
3. **Re-confirm the tester list** (the same ≥12 people) and warn them a new opt-in link is
   coming — re-opt-in is the long pole of the restart, so prime it on day one.

*Ops A — domain plumbing (owner + assistant). **EXECUTED 12/08/2026** — status per step
below; do NOT re-ask the owner for these. Two facts learned doing it: the landing is a
**Worker** (`guardacompartilhada-site`), not a Pages project — its custom domains live under
Workers & Pages → the worker → **Domains** tab, which is also where the promotion-A 301s get
configured; and Cloudflare's Email Routing moved to a new UI (Email Service → Email Routing),
where custom addresses are created under the **Routing rules** tab.*

| Ops A step | Status 12/08/2026 |
|---|---|
| Cloudflare zone `entrelares.app` | ✅ Active (Registrar purchase, same account) |
| `web.entrelares.app` on the app Pages project | ✅ serving the prod app (v1.8.1 verified in-browser) |
| `entrelares.app` apex on the landing worker | ✅ serving the landing |
| `www.entrelares.app` on the landing worker | ✅ (12/08, dashboard print) |
| Email Routing: destination `irineus@gmail.com` verified | ✅ |
| Routing rules `privacidade@` + `suporte@` → Gmail | ✅ (12/08) — owner also added `contato@` AND an active **catch-all** → Gmail, so every `@entrelares.app` address delivers |
| GoTrue Redirect URLs `https://web.entrelares.app/**` (dev + prod) | ✅ (Site URL untouched, as planned) |
| Resend / senders / 301s / DMARC | ✅ executed at the promotion-A cutover, 12/08 (runbook 5.8) |

*(original step list, kept for context:)*
- **Cloudflare**: DNS zone for `entrelares.app`; `web.entrelares.app` as custom domain on the app Pages
  project, apex on the landing project; **301 redirects** old apex + `app.` → new equivalents.
  The old domain stays as a redirect indefinitely — already-sent e-mails carry its links.
- **Resend — CANNOT be prepared up front (found 12/08/2026)**: the Free plan allows ONE
  domain per account, and `guardacompartilhada.com` is production's live sender — the API
  refused `create-domain` with `403 "Your plan includes 1 domain"`. The DKIM key only exists
  once the domain is created in Resend, so the DNS records cannot be pre-staged either. The
  sender migration therefore becomes a **coordinated cutover at promotion A** (see below).
  Zero-downtime alternative if the owner accepts one-off spend: Resend Pro for ONE month
  (US$ 20) verifies both domains in parallel, flip senders calmly, delete the old domain,
  downgrade back to Free. Default: the free cutover — the alpha has ~12 users; a
  minutes-long e-mail window at a quiet hour is acceptable. The account/keys stay the same
  either way (T-49 suppression unaffected).
- **Mailboxes**: `privacidade@`, `suporte@`, `noreply@` on `entrelares.app`; the old addresses stay
  as receiving aliases (`privacidade@guardacompartilhada.com` is named in the published
  policy and in the Play Data Safety answers).
- **GoTrue** (dev first; prod at promotion A, runbook-style): Site URL + Redirect URLs →
  `https://web.entrelares.app`; SMTP sender → `noreply@entrelares.app` (dev AND prod configs).

*PR 1 — rename + domain swap in the repo, one delivery on
`feature/f-54-rebranding-entrelares` (from current `dev`), version bump 1.8.1 → 1.8.2:*
- **UI strings**: every "Guarda Compartilhada" in `Localization/StringsPtBr.cs` (17) and
  `StringsEn.cs` (15) → "Entrelares" (the tagline "Duas casas, uma mesma infância." may join
  the login/landing surfaces where a subtitle already exists — no new layout).
- **`wwwroot/manifest.webmanifest`**: `name`/`short_name` → Entrelares; `related_applications`
  id → `com.entrelares.app`.
- **`wwwroot/index.html`**: `<title>`; the store-context referrer check (line ~83) accepts
  **BOTH** `android-app://com.entrelares.app` and the old package while testers migrate — the
  old prefix is removed in the cleanup step, after the old app is retired.
- **`Helpers/StoreContext.cs`**: doc comment.
- **E-mails**: product name in `supabase/functions/_shared/i18n.ts` and the `send-*`
  templates/subjects; `send-swap-email`'s `APP_URL` fallback → `https://web.entrelares.app`.
  **Sender ADDRESSES do not flip in this PR** — the Resend free plan means the new domain
  only becomes verifiable at the promotion-A cutover, and a sender on an unverified domain
  bounces everything. Move the from-address to a per-project **env var** (`MAIL_FROM`,
  read in `functions/_shared/mail.ts`, falling back to the current address), so the cutover
  is a config flip + GoTrue SMTP edit, with no redeploy in the critical window. Display
  name → "Entrelares" already (safe on the old domain).
- **Legal pages**: product name + contact addresses in `Pages/Privacy.razor` +
  `Pages/Terms.razor` (old `privacidade@` kept listed as alias or swapped — both readable
  paths must work), "Última atualização" date only — **explicitly NO `PolicyVersions.Current`
  bump** (name and contact-address updates are non-material). Cross-repo: the landing's
  `privacidade.html`/`termos.html` in the same delivery (L- item: brand + content + domain).
- **PDF report** header/footer product name (F-33 path).
- **`store/listing-pt-BR.txt` / `listing-en-US.txt`**: app name → Entrelares, short/full
  descriptions reworded around the new name + tagline (respect the char limits noted inline);
  contact e-mail `suporte@entrelares.app`, website `https://entrelares.app`.
- **`store/twa-manifest.json`**: `packageId` → `com.entrelares.app`, `name`/`launcherName` →
  `Entrelares`, **`host` → `web.entrelares.app`** (+ `iconUrl`/`maskableIconUrl`/`webManifestUrl`/
  `fullScopeUrl` on the new host), **`appVersionCode` back to 1** (the counter is
  per-package), `appVersionName`/`appVersion` → the app version being wrapped.
- **`wwwroot/.well-known/assetlinks.json`**: ADD a second statement for `com.entrelares.app`
  with the **upload-key fingerprint** (known now — same keystore: `keytool -list -v -keystore
  .\android.keystore -alias android`). The **app-signing** fingerprint only exists after the
  first upload (PR 2). The old package's statement STAYS until the old app is retired; the
  file is one Pages deployment, so old and new hosts serve the same content during transition.
- **Version bump** (csproj ×3, webmanifest, README changelog + §Versioning lines) — the U-13
  parity/orphan gates in `LocalizationTests` cover the string edits; sweep the test suites for
  literal "Guarda Compartilhada" asserts.
- **Docs sweep**: `store/README.md` (package id, host, init prompts, opt-in link), README
  title/branding, `supabase/README.md` domain references. CLAUDE.md/README **Overview**
  paragraphs move only at promotion, as always.

*Promotion A (after PR 1 QA):* `dev`→`master` **v1.8.2** + release notes
(`docs/releases/v1.8.2.md`), then the **Resend + sender cutover in the same sitting, at a
quiet hour** (e-mails are LOST during the window — the app sends fire-and-forget, so nothing
errors, nothing retries):
1. Resend: delete `guardacompartilhada.com` → create `entrelares.app` (region `sa-east-1`,
   sending only, tracking off — mirror the old config) → paste the returned DKIM/SPF/MX
   records into the Cloudflare zone (+ `_dmarc` TXT, same policy the old domain earned its
   DMARC PASS with) → Verify. Cloudflare is authoritative, so minutes, not hours.
2. Flip `MAIL_FROM` on BOTH Supabase projects to `noreply@entrelares.app`.
3. GoTrue (both projects): SMTP sender → `noreply@entrelares.app`; PROD Site URL →
   `https://web.entrelares.app` (runbook steps 4–5).
4. Old-domain 301 redirects go live in Cloudflare now (apex + `app.` → new equivalents).
The TWA wraps the PRODUCTION site, so `https://web.entrelares.app` must serve the app saying
"Entrelares" before any tester installs. **Human verification round on the new domain**:
sign-up confirmation AND password reset end to end — auth-link round trips are exactly the
class no suite reaches (the 07/08 lesson), and the Site URL + sender just changed.

*Owner — Play Console (delta over `store/README.md`, which PR 1 updates):*
1. `bubblewrap build` in `store/` (manifest already carries the new identity + host; verify
   `appVersionCode: 1` before building).
2. **Create app**: https://play.google.com/console → Create app → name `Entrelares`,
   default language `Portuguese (Brazil) – pt-BR`, App, Free.
3. **Closed testing** → create track `closed-alpha` → upload the new AAB → paste the tester
   e-mail list → **Save → Review release → Start rollout to Closed testing** (the last button
   is the publish — it stalled the first app, Aug 2026).
4. **Forms** (all re-filled; same answers as `store/README.md` §7 except the URLs): privacy
   policy `https://entrelares.app/privacidade.html`, App access (same reviewer account), Data
   Safety (deletion contact `privacidade@entrelares.app`), content rating, target audience, ads.
5. Copy the **App signing key + Upload key SHA-256 fingerprints** from the new app's
   keymanagement page → hand to PR 2.
6. **Send every tester the NEW opt-in link** `https://play.google.com/apps/testing/com.entrelares.app`
   — adding them notifies nobody; each must open it and accept. The 14-day clock runs from
   rollout with ≥12 opted-in.

*PR 2 — the internal rename (owner directive 12/08/2026, "no trace"):* project/namespace
`SharedParentalCustody` → **`Entrelares`** (csproj, folders, every `.cs`/`.razor`, the three
test projects → `Entrelares.Tests`/`.IntegrationTests`/`.E2ETests`, workflows, docs) — kept
OUT of PR 1 because it touches every file and would drown the visible rebrand's diff.
**Rename half DELIVERED 12/08/2026 (`1.8.3`)** — `git mv` preserves blame; the scoped-CSS
bundle follows the assembly name (`Entrelares.styles.css`, referenced in `index.html`);
historical records/releases keep the old name as history. **Fingerprint half DELIVERED
13/08/2026 (`1.8.7`, promotion B)**: the app-signing fingerprint
`21:EC:98:2F:…:B3:5C` went into `assetlinks.json` right after the first upload — Play App
Signing is enabled at UPLOAD, not at approval, so there was no reason to wait for the review —
and the Console's upload-key row matched the value already in the file, confirming the reused
keystore. Production serves both statements since that promotion.

*Cleanup — DONE 12–13/08/2026, except the one piece that is gated on an external state:*
the three `send-*` functions' `RESEND_FROM_EMAIL` **fallbacks** flipped to
`noreply@entrelares.app` in `1.8.5` (they stayed on the old domain through PR 1 on purpose —
until the 5.8 cutover that domain was the verified sender; **after** the cutover the same
fallback became the opposite of harmless, since a project without the secret would send from a
domain Resend no longer knows and fail in silence, which is exactly the state DEV was found
in). Infrastructure: old Cloudflare workers and the old Pages project deleted, old hosts
serving permanent 301s, Resend keys recreated (a key bound to the deleted domain refuses
everything), dead Brevo secrets removed, Supabase project/org names updated, and the
Dashboard's auth-e-mail templates swept — they are the hook's back-out path and had kept the
old brand because they live only in the Dashboard, invisible to any `grep`. **Still gated:**
retiring the legacy package — its `assetlinks.json` statement and the old referrer prefix are
what keep the PREVIOUS app full-screen for whoever still has it installed, so they come out
when that app is unpublished, tracked as **T-52**. The old DOMAIN is not cleaned up at all: it
keeps 301-redirecting and receiving e-mail aliases indefinitely (renewal is an owner call
later — never let it lapse while sent e-mails still point there).

*Dev/QA environment sweep (owner request 12/08/2026 — "garanta que tudo vire Entrelares,
inclusive em ambiente de desenvolvimento"):*
- The app-code rename reaches QA **by construction** — the `dev` branch carries PR 1, so the
  QA screens, notifications and dev-project e-mails all say Entrelares the moment it merges.
  Nothing extra to do for the CONTENT.
- The QA **host** is `dev.sharedparentalcustody.pages.dev` (`deploy.yml` publishes with
  `--project-name=sharedparentalcustody`, one alias per branch) and the dev GoTrue Site URL
  points at it. Note the name is the REPO's, not the old brand's. Decide at execution:
  **DECIDED at execution (12/08/2026): `qa.entrelares.app`**, via a CNAME to the `dev`
  branch alias — combined with the Pages-project move below, the target is
  `dev.entrelares-app.pages.dev`. Dev GoTrue Site URL + docs follow in the same sitting
  (owner steps in the PR-1 handover).
- **Internal-identifier inventory — decisions taken 12/08/2026 (owner: leave no trace):**
  · **GitHub repos → `entrelares-app` + `entrelares-site`** (owner renames in the UI;
    GitHub redirects old URLs; docs/`notion-mirror.py`/workflow refs updated in PR 1).
  · **Pages project**: names are IMMUTABLE on Cloudflare, so the "rename" is create
    **`entrelares-app`** + point `deploy.yml --project-name` at it (done in PR 1 — the
    project must exist BEFORE the merge or the CI deploy fails). Custom domains move to
    the new project's production deployment at promotion A (until then the old project
    keeps serving them); old project deleted in the cleanup.
  · **Cloudflare worker `guardacompartilhada-site` → `entrelares-site`**: worker names are
    also create-new (a renamed `wrangler.jsonc` deploys a fresh worker with no domains, no
    secret, no KV binding wired) — executed with the landing's next delivery: change
    `wrangler.jsonc` `name`, re-set `RESEND_API_KEY`, move the custom domains, keep the
    SAME KV namespace ids (the opt-in log must not fork).
  · **Supabase project display names** (cosmetic, refs immutable) and **Resend key labels**:
    owner renames in the dashboards at leisure; nothing references them.
  · **R2 bucket `guarda-backups`** (T-19): left as-is for now — rename = create+migrate
    with zero user-facing value; revisit if T-50 moves traces there.
- **The rule that keeps this sane**: anything a USER can ever see ships in PR 1,
  unconditionally; internal-only renames are batched here, each one taken only when its
  blast-radius updates ship in the SAME delivery — never breaking CI mid-item for a label.

*Explicitly OUT of this item:* icon redesign, INPI filing mechanics, Play production access
(that is the normal end of the closed test, not part of the rename).

**Justification**
Two independent alpha testers hit the same wall: "Guarda Compartilhada" names the legal
instrument, not the product — it excludes parents without formal shared custody (a real
segment: one of the two testers is exactly that) and reads institutional where the purchase
decision is emotional. "Entrelares" is an invented, ownable word that names the child's reality
(two homes) instead of the parents' legal status, widening the addressable audience at the
exact moment the product prepares to go public — which is also the only moment the rename is
still cheap.

---

### F-58 — Platform-operator console (app settings + entitlement management)

| Field | Value |
|---|---|
| **Status** | `completed` — **18/08/2026**, in builds `1.8.8`–`1.8.12` (app) and `v0.1.0`–`v0.3.2` (console), across PR 1 + entrega 2 + four QA rounds driven by the owner testing on his own Android |
| **Priority** | `high` — prerequisite of F-53 (the tester-reward comp is granted THROUGH this console's RPC) |
| **Complexity** | `medium` — the security model is the item; the v1 scope is deliberately small |
| **Impact** | `medium` (operator-only surface, but it unblocks F-53's public promise) |
| **Roadmap** | Group 4 (Distribuição), Ordem 0.8 — before F-53, which depends on it |
| **Cross-repo** | The console app lives in the NEW repo **`entrelares-console`** (see decision below). The privacy-policy disclosure synced to `entrelares-site/public/privacidade.html` in PR 1 |
| **Delivered in** | `1.8.8` (PR 1 — database foundation), `1.8.9` (QA 1 — full family listing + login-e-mail change), `1.8.10` (QA 2 — plan history + operator trail), `1.8.11` (QA 3 — the comp reason reaches the family), `1.8.12` (QA 4 — the revoke has a reason of its own) |

> **Created 12/08/2026, owner request**: *"uma tela de administrador do aplicativo, onde eu
> consiga ajustar os parâmetros da aplicação e também possa gerenciar algumas funcionalidades,
> como dar o Premium permanente para as famílias do Closed-Test, como prometido."*

**What it is**: the product's first PLATFORM-level role — the operator, who runs the service
(everything else is family-scoped: `is_admin` is FAMILY admin, RLS fences every table by
family). Deliberately small v1: (1) an `app_settings` editor with `value_type` validation;
(2) per-family entitlement management — the whole family base listed and filtered, plan state,
grant/revoke the **permanent courtesy Premium (comp)**; (3) participant support — changing the
login e-mail of somebody who lost their mailbox; (4) the operator's own audit trail, readable
in the console. Every access logged.

**Decisions locked (18/08/2026, owner)**
- **Comp = dedicated column** (`families.comp_premium_at` + `comp_premium_note`), read by
  `is_premium()` itself — never a parallel check — and orthogonal to `plan`, so a billing
  webhook downgrade can never silently clobber a courtesy grant. Comp SEMANTICS (who gets it)
  stay in F-53; this item ships the mechanism. Client mirror: `EntitlementService` gained the
  optional `compPremiumAtUtc` parameter (default keeps every pre-F-58 call site exact).
- **Transparency**: granting/revoking a comp writes the family's own `account_logs`
  (`comp_premium_granted`/`comp_premium_revoked`, rendered with the system actor — the
  operator is not a family member), besides the operator's own trail.
- **`policy.current_version` / `policy.enforce_from` are READ-ONLY in the console**: the RPC
  refuses `policy.%`. A lone DB edit would desync `PolicyVersions.cs` and the S-15 four-piece
  delivery rule — risking the production-wide lockout that rule exists to prevent.
- **The console is a SEPARATE Flutter app (`entrelares-console`), not a page in the PWA.**
  Owner's call, two reasons: (a) not one line of operator UI/code ships in the public bundle
  (in Blazor WASM every user downloads the whole app); (b) it is the deliberate FIRST PIECE of
  the future Flutter/Dart migration of the product, using **`irineus/desmalha`** as the
  benchmark (FVM-pinned Flutter 3.44.7, `supabase_flutter`, JDK 17, minSdk 26,
  `tool/setup_env.sh` + environment verifier). Dedicated repo (not a monorepo); **no CI in
  v1** — verification happens in-session (analyze + tests + APK build) before each push;
  distribution = APK sideloaded on the owner's Android only, no store.
- **Security model (all enforced in THIS repo's database — the console is only a caller):**
  `platform_operators` seeded by migration from the owner's auth e-mail (never assignable via
  UI or client RPC; zero client privilege on the table); `is_platform_operator()` for the
  UI-gating question only; every capability is a SECURITY DEFINER RPC checking `auth.uid()`
  against the seeded table (T-35 lesson: never `current_user` inside DEFINER) + **S-10 sudo on
  every write** (`ELEVATION_REQUIRED:` contract, same as `set_member_admin`); zero broad RLS
  bypass. `operator_audit_logs` is append-only, has NO client access and NO foreign keys on
  purpose — it is evidence and must outlive what it names (same reasoning as the C-6 opt-in
  log). `admin_lookup_family` logs EVERY call, including misses — looking up personal data is
  the audited act, found or not.
- **LGPD**: the operator's audited cross-family access to cadastral data (name, e-mail, role,
  plan state) is disclosed in §10 of the privacy policy (both repos). Non-material — the
  controller already had unrestricted infrastructure access (Dashboard/service_role, policy
  §7); the console creates a NARROWER, password-reconfirmed, audited path — so only the
  "Última atualização" date moved (no `PolicyVersions.Current` bump).

**RPCs**: `admin_list_settings` (whole table, read), `admin_update_setting` (validates against
`value_type`, refuses `policy.*`, refuses unknown keys — the console edits, never creates;
audits before/after), `admin_lookup_family(email)` (family + members + plan + subscription as
jsonb; every call audited), `admin_set_comp(family_id, granted, note)` (idempotent — a
repeated grant keeps the original timestamp), `admin_list_families()` (QA 1 — the whole base
with members and subscription inline, ONE audited bulk-access row, so the console filters
locally instead of demanding an exact e-mail), `admin_list_audit(limit)` (QA 2 — the operator
trail, newest first, family name inline).

**The Edge Function `admin-update-member-email` (QA 1)**: the operator as the recovery path
when a member loses the mailbox that IS their only way in. Session token → operator check →
elevation check → GoTrue Admin API `updateUserById` (JWT gate ON, like `elevate`), keeping
`auth.users` and identities consistent; the existing `sync_profile_email` trigger carries it
into `profiles` and the family's `account_logs`. Refuses a departed member (S-11 immutability)
and an address already in use (409).

**Plan history (QA 2) — the design that mattered.** The owner asked why the family's history
said the plan changed but never WHY. The reasons live in the billing path (webhook, grace
cron), which is production-critical code carrying real money since 29/07 — so nothing there
was touched: a trigger on `families`, firing only when `plan` actually changes, INFERS the
reason from the subscription state at that instant (`active` → payment, `single_charge` →
avulso, `overdue` → grace ended, `canceled` → cancellation, else generic). It therefore covers
the webhook, the cron's direct UPDATE and every writer that does not exist yet. The end of the
TRIAL writes no row at all — `is_premium()` computes it — so it renders as a SYNTHETIC timeline
entry derived from `trial_ends_at`, interleaved chronologically; no backfill, nothing stored.

**QA 3 and 4 — the reason had to be visible, and unambiguous.** QA 3: the comp note was
reaching only the operator's trail, so the family's own entry said "cortesia concedida" with no
motive; `admin_set_comp` now writes it as the entry's value. QA 4: a revoke echoed the GRANT's
note in the green "new value" pill, which reads as if that were the new state. Fixed on both
ends — the revoke got a reason parameter of its own (the family entry now reads *motivo da
cortesia → motivo da revogação*), and the Histórico renderer stopped rendering a lone OLD value
as a new one: it comes out in the undone-value style. Old entries were left exactly as they
were — history is a record, not a document to rewrite.

**Tests**: `PlatformOperatorTests` (integration) — non-operator refused on every RPC even
elevated; operator without sudo refused on writes; type validation + `policy.*` + unknown-key
refusals; a THROWAWAY settings row proves persist + audit (the shared dev config is never
mutated); comp flows through `is_premium()`, survives a billing-style downgrade and is
idempotent; both audit trails recorded WITH the grant/revoke note pair; lookup crosses families
and logs hits AND misses; the operator trail comes back newest-first; a plan flip written the
way the grace cron writes it produces the family history row with the inferred reason; neither
operator table readable by any authenticated client. `EntitlementServiceTests` (unit) — the
comp clause of the client mirror, including "comp during trial hides the countdown" and "the
comp timestamp is a grant record, not an expiry". In the console: `rules_test.dart` (16) over
the pure rules — value validation, `policy.*`, the elevation marker contract, e-mail validation,
the filters, the date formats and the friendly-error mapping.

**Files affected (app)**
- `supabase/migrations/20260818150000_f58_platform_operator_console.sql`,
  `…210000_f58_admin_list_families.sql`, `…230000_f58_plan_history_and_operator_audit.sql`,
  `20260819000000_f58_comp_note_in_family_history.sql`,
  `20260819010000_f58_comp_revoke_reason.sql`
- `supabase/functions/admin-update-member-email/index.ts` (+ both `deploy.yml` pipelines)
- `Entrelares/Services/EntitlementService.cs`, `Models/Family.cs`, `Services/AuditService.cs`,
  `Pages/FamilyPage.razor`, `Pages/CustomRolesPage.razor`, `Pages/ReportsAudit.razor`,
  `Localization/{K,StringsPtBr,StringsEn}.cs`
- `Entrelares/Pages/Privacy.razor` §10 (+ landing `public/privacidade.html`)
- `Entrelares.IntegrationTests/{PlatformOperatorTests,PlatformOperator,OperatorAuditLog,AppSettingSeed}.cs`
- `Entrelares.Tests/EntitlementServiceTests.cs`

**The console repo (`entrelares-console`, entrega 2)**: `apps/console_app` (Flutter), four
tabs — Parâmetros, Famílias, Participantes, Auditoria —, environment switch dev/prod chosen at
login, S-10 sudo handled by a shared `runWithSudo` helper, launcher icon built from the
Entrelares emblem with a gear badge (`tool/gerar_icone.py`). Distribution is the `--split-per-abi`
arm64 APK, sideloaded.

**What the Flutter pilot taught, and where it is written down.** The device-only failures were
worth more than the feature: a release APK with no network because `flutter create` puts the
INTERNET permission only in the debug/profile manifests; "senha incorreta" on a correct password
because a dead access token and a wrong password look identical to a dialog that treats every
`FunctionException` the same; and a restored-but-dead session that let the app in, ran every
request as `anon` (→ `42501 permission denied for function`) and then threw on the way out of
`signOut`. All of it — symptom, cause, fix — is recorded for the eventual migration of the app
itself in **[`entrelares-console/docs/migracao-flutter.md`](https://github.com/irineus/entrelares-console/blob/main/docs/migracao-flutter.md)**,
which is the second deliverable of this item and the reason the pilot was worth doing on a
single-user surface first.

**Justification**
The owner needed to fulfil F-53's public promise (permanent Premium for closed-alpha testers)
and tune operational parameters without hand-run SQL against production. Hand-run SQL has no
type validation, no sudo gate and no audit trail — exactly the class of risk the item removes.
The separate-app decision additionally started the Flutter migration path with a low-stakes,
single-user surface, and paid for itself immediately in lessons.

---

---

### T-54 — CI gate for the `entrelares-flutter` repo

| Field | Value |
|---|---|
| **Status** | `completed` — **19/08/2026**, PR 3 of `entrelares-flutter` (`verify.yml`), self-validated: the workflow's first run happened on its own PR |
| **Priority** | `high` — the repo was born WITHOUT a gate; every merge so far was verified only on the dev machine |
| **Complexity** | `low` |
| **Impact** | `medium` (it is what makes T-53's stages 2–3 safe to build at pace) |
| **Roadmap** | Group 4, Ordem 0.1 — right behind T-53; worth doing before any next Flutter PR |
| **Relates** | **T-53** (its repo), the desmalha benchmark's Codemagic lane (iOS, later) |

> Delivered the same day it was created (19/08/2026, at the T-53 stage-1 close), before any
> further Flutter PR — the point of the card. Original motivation: the spike repo `irineus/entrelares-flutter`
> merged its first two PRs with all checks run locally (analyze clean, 50 core + 10 widget
> tests green) and NO CI — flagged as a candidate card in the session summary, per the
> one-scope-per-session rule.

**Scope.** A single GitHub Actions workflow on push/PR: FVM-pinned Flutter 3.44.7 (the
`.fvmrc` is the source of truth — `subosito/flutter-action` reads the version from it),
then `dart analyze` + `dart test` in `packages/entrelares_core` and `flutter analyze` +
`flutter test` in `apps/entrelares_app`. No APK build in the gate (that is minutes-expensive
and the account's 2000 min/mo are shared with the product repos — same constraint that
shaped T-50); a manual/`workflow_dispatch` APK job is enough. The iOS lane, when it exists,
follows the desmalha benchmark (Codemagic free macOS runner), not GitHub Actions.

**Files affected** (repo `entrelares-flutter`)
- `.github/workflows/verify.yml` (new)
- `README.md` (Build & test section gains the CI note)

**Follow-up delivered 19/08/2026 (T-53 lote 3, PR #19): the E2E lane opened.**
The card's own scope stayed as written; what the parity map deferred — "the E2E
lane enters when the first two-user flow ports" — arrived with the swap
workflow. `verify.yml` gained an `e2e` job driving the REAL app on an Android
emulator (API 34, KVM) against the dev project, with the throwaway-family
pattern the web suite already pays for (`E2E-<runId>`, `@resend.dev`,
`purge_e2e_family` whose double-signature guard lives in the DATABASE). Two
deltas from the plan, both deliberate: **`integration_test` instead of Patrol**
(the official package covers the flow with no extra dependency) and **scheduled
06:10 UTC + `workflow_dispatch` instead of per-push** — an emulator run costs
~10-15 min of the account-wide 2000 min/mo, the same arithmetic that keeps the
APK build out of the gate. Operational prerequisite: the
`SUPABASE_SERVICE_ROLE_DEV` secret must exist in `entrelares-flutter` (it
already does here); the fixture fails with an explicit message without it.

### T-55 — Own signing keystore for the Flutter app

| Field | Value |
|---|---|
| **Status** | `completed` — **19/08/2026**, PR 5 of `entrelares-flutter` (`0.2.0+2` → `0.2.1+3`), same day the card was created |
| **Priority** | `medium` — became `high` with the T-53 stage-1 GO verdict, delivered immediately after it |
| **Complexity** | `low` (owner ops + gradle wiring; the product already has this discipline from F-54) |
| **Impact** | `high` if ignored: a device that installed a debug-signed build must UNINSTALL (losing local data) to accept any build from another machine |
| **Roadmap** | Group 4, Ordem 0.2 — gated on the T-53 stage-1 verdict |
| **Relates** | **T-53** (pilot lesson 2.2), **F-54** (the upload-keystore discipline this copies) |

> Created 19/08/2026 at the T-53 stage-1 close: the spike APK handed to the owner is signed
> with THIS dev machine's debug keystore (pilot lesson 2.2 — debug keystores are
> per-machine). Fine for the measurement run; not fine for anything after it.

**Scope (as written).** Generate a dedicated upload keystore OUTSIDE the repo (same regime
as the app's `store/android.keystore`, F-54); wire `signingConfigs` in
`apps/entrelares_app/android/app/build.gradle.kts` reading path/passwords from
`key.properties` (git-ignored); document the handling in the repo README. Secrets never
enter the repo nor a cloud session (permanent rule 1). The keystore is for direct/sideload
builds only — Play distribution of `com.entrelares.app` uses the PRODUCT's existing upload
keystore (stage-0 finding); no second Play identity.

**Delivered.** Release signing is **per flavor** via the git-ignored `android/key.properties`:
`dev.*` → the dedicated sideload keystore, `prod.*` → the product's upload keystore
(`store/android.keystore`) — separated by construction so a Play upload can never come out
signed with the sideload key by mistake. Without the file, any release task **fails fast**
with a message pointing at the README (no silent fallback to debug keys — that fallback IS
the lesson-2.2 trap); debug builds are untouched. Verified end-to-end with a throwaway test
keystore (deleted after the check): release APK carries the test cert per `apksigner`,
release without `key.properties` fails in 3 s, debug with the file present still carries
the `Android Debug` cert. The CI dispatch APK became a **debug** build — the runner never
has the keystores, so release is local-by-construction. **The owner op closed the same day
(19/08/2026):** the real sideload keystore was generated on the dev machine (RSA 2048,
valid to 2054) and `key.properties` put in place — a release build then came out signed
with the owner's own certificate (`apksigner` fingerprint match), completing the chain.
Bonus lesson: the README's `keytool` command was in `cmd` syntax (`%USERPROFILE%`) and
failed on the owner's PowerShell — fixed to `$env:USERPROFILE` + directory creation first.

**Files affected** (repo `entrelares-flutter`)
- `apps/entrelares_app/android/app/build.gradle.kts` (per-flavor `signingConfigs` + fail-fast)
- `.github/workflows/verify.yml` (dispatch APK: release → debug)
- `README.md` ("Assinatura (release)" section: `keytool` command + `key.properties` template)
- `CLAUDE.md` + version bump (`pubspec.yaml`, README §Versionamento)


---

### T-48 — Google Play Billing (REDESIGNED and delivered inside T-53 lote 5)

| Field | Value |
|---|---|
| **Status** | `completed` (20/08/2026) — delivered in REDESIGNED form inside T-53 lote 5 (`entrelares-flutter` #34/#35 + `entrelares-app` #285, app `1.8.13`). The deliverable is the code, which is deployed and dormant; **go-live is configuration**, tracked in `supabase/README.md` §9-bis exactly as T-39's was. Do not re-open this row to track the console steps. |
| **Priority** | `low` |
| **Complexity** | `high` |
| **Impact** | `medium` |
| **Roadmap** | Roadmap group 5 — it WAS parked behind data, and stopped being so on 19/08/2026: the owner's tension-2 decision put Play Billing on stage 3's critical path, because a native app may not sell a digital subscription through an external checkout at all. The data gate became moot the moment the store shell stopped being a TWA. |
| **Prerequisites** | Delivered as part of T-53 lote 5 |

**Delivered shape (20/08/2026) — the Digital Goods API design is DEAD.** It was a
Chrome/TWA mechanism; the Flutter app is native, so the rail is Play Billing proper:

- **Client** (`entrelares-flutter` #34): `in_app_purchase` behind a `StoreBilling`
  interface, product ids `premium_monthly`/`premium_annual` pinned by test, the price
  shown is PLAY's (the `app_settings` prices rule the web rail only), restore-purchase,
  and the Play "manage subscription" deep link — because the store owns that
  subscription and cancelling there is the honest answer.
- **Server** (this repo): `subscriptions` gains the `play` gateway plus the purchase
  token (UNIQUE — one purchase funds ONE family, so a replayed receipt cannot buy
  Premium twice) and the product id; `billing-store-verify` turns a token into Premium
  only after asking the Play Developer API whether it is real and until when it pays;
  `billing-store-webhook` receives the RTDN (Pub/Sub push, shared token on the query
  string) and applies renewal, cancellation, expiry, revocation and dunning. **Both go
  through the SAME `set_family_plan` and the SAME `billing_events` ledger** as the Asaas
  webhook, with the same idempotency contract.
- **Master switch** `billing.store_enabled` (public, `false`): while it is off the store
  build shows the neutral T-38 note — which is also the fail-closed default when the
  device has no store or no product comes back. An offer the store cannot honor is worse
  than no offer.
- **The client never grants.** The acknowledge to Play happens only after the server
  accepted: Play refunds an unacknowledged purchase after three days, and acknowledging
  one the server refused would leave a family paid and without the entitlement.

**Description as ORIGINALLY written (kept for the record — this design was NOT built)**
If (and only if) the store cohort's paywall→checkout conversion is materially below the web
cohort's, add **Google Play Billing inside the existing TWA** via the Chrome **Digital Goods
API** + Payment Request API — store billing **without a native rewrite**; the app stays the
Blazor PWA:

- Digital Goods API purchase flow in the TWA (replaces T-38's neutral CTA for the store cohort)
- New `billing-store-webhook` Edge Function: Play **Real-Time Developer Notifications** (Pub/Sub)
  + purchase-token validation against the Play Developer API
- `subscriptions` provider column (`asaas` | `play`) and reconciliation into the **per-family**
  entitlement — the family model vs per-Google-account purchase mismatch is the real complexity:
  payer leaves the family, admin transfer, cross-platform "manage subscription" deep link,
  cancellation discovered only via RTDN
- Play's ~15% fee is treated as CAC for that cohort; **web/Pix (Asaas) stays the primary rail**
  — the T-39 web-first principle is unchanged

**Justification**
Records the decision of the Aug 2026 architecture review (a full MAUI + store-billing migration
was evaluated and declined) so the option is never re-litigated from scratch: the cheap path to
store billing exists, is incremental, and has a written go/no-go criterion instead of a feeling.
The iOS mirror (StoreKit plugin in the T-40 shell) is noted in T-40 and would be a separate item.

**Files affected (as delivered)**
- `entrelares-flutter`: `packages/entrelares_core/lib/src/store_billing_rules.dart`,
  `apps/entrelares_app/lib/services/store_billing.dart`, the store branch of the Premium
  section, `Env.androidPackage`, plus the two suites
- New `supabase/functions/billing-store-verify/` and `supabase/functions/billing-store-webhook/`,
  sharing `supabase/functions/_shared/play.ts`
- `supabase/migrations/20260820020000_t48_play_billing.sql` — the `play` gateway, the UNIQUE
  purchase token, the product id, and the `billing.store_enabled` switch
- `Entrelares.IntegrationTests/BillingStoreTests.cs`; `supabase/README.md` §9-bis (go-live)

**Why the original design died**: the Digital Goods API is a Chrome/TWA mechanism. T-53's
tension 2 (owner, 19/08/2026) replaced the TWA with a native Flutter app, and Play requires
Play Billing for a digital subscription sold inside one — so the data gate ("only if the funnel
says so") became moot: without this rail the store channel cannot sell at all.

---

### U-27 — Visual foundation: design tokens and the shared component set

| Field | Value |
|---|---|
| **Status** | `completed` |
| **Priority** | `high` — the last moment this is cheap. Zero users are on the Flutter app; after the T-53 cutover every visual change is a change to a live product |
| **Complexity** | `medium` — no new data, no rule changes, no flow redesign. It touches 20+ screens through the theme, not one by one |
| **Impact** | `high` — every screen inherits it at once |
| **Roadmap** | Group 4 · **before the stage-4 cutover of T-53** |
| **Prerequisites** | None left. The palette and identity decisions closed 20/08/2026 (below) |
| **Delivered** | 20/08/2026 — `entrelares-flutter` `0.2.29+31`…`0.2.31+33`, PRs #37/#38/#39 |

> **Origin (20/08/2026).** Closing T-53's lote 5 left stage 3 functionally complete, and the
> owner's own reading of the dev previews was that the app looked unfinished. A code audit
> confirmed it and measured it: **the port carried 100% of the rules and ~0% of the visual
> layer.**

**The measured gap**

| | Blazor (production) | Flutter (`0.2.28+30`) |
|---|---|---|
| Visual layer | **5,317 lines of CSS** (12 page sheets + `shared.css`) | **4 lines of theme** — one `ColorScheme.fromSeed` + `useMaterial3` |
| Depth and motion | **115** gradient / shadow / keyframe / transition declarations | **2** occurrences of `BoxShadow`/`LinearGradient`/`elevation` |
| Colour | derived from `:root` variables | **81 literals across 13 files** — the same `0xFF991B1B` decided 15 times |
| Loading | a whole `.skel-*` family with shimmer | **0 skeletons**; 26 places that render the word "Carregando" |

**Decisions locked 20/08/2026** (owner + external UI/UX review; the review's first draft was
revised after a code check — it had assumed a .NET backend that does not exist)

1. **Identity is neutral/institutional, not warm.** The product is a family calendar *and* a
   near-evidentiary record used by people in conflict; a playful surface reads as
   condescending exactly when the stakes are highest. Greys carry the surfaces, colour is
   reserved for **data** (calendar, charts) and the primary action.
2. **Two role colours, not five.** The web's pair returns — father `#1D4ED8`, mother `#E11D48`
   — because it was chosen to survive deuteranopia and protanopia, and the five-slot palette
   the spike introduced never was. **Roles beyond the two do not get a new solid colour**:
   they get the alternative surface with a border and a hatch pattern, so colour stops being
   the only vector of information.
3. **Dark mode ships with the tokens, not later.** Deferring it is the expensive order: it is
   nearly free while the tokens are being written and nearly impossible against 81 literals.
   The use context argues for it too — this calendar gets checked late at night, in bed.
4. **Brand hue survives, in one place.** The accent stays the product's indigo `#4F46E5`
   (`colorScheme.primary`) so the app shares a colour with its own landing and store listing;
   surfaces stay strictly grey.
5. **`ColorScheme` is written by hand**, not `fromSeed` — seeding bleeds the indigo into the
   greys and destroys the neutrality the first decision buys.
6. **State management is NOT rewritten.** Bloc was proposed and withdrawn: its strongest
   argument was a front-end audit trail, and this product's audit trail is entirely in the
   database (27 migrations touching triggers and log tables, 45 inserts into
   `activity_logs`/`account_logs`, `resolution_log_id` stamped by trigger). A Bloc event log
   lives in RAM on one device and has no evidentiary value. The current injected data source
   plus 367 widget tests against a fake already buy the testability. Dependency injection may
   be modernised later on its own merits, never as part of this item.

**Tokens**

| Token | Light | Dark |
|---|---|---|
| Surface | `#F9FAFB` | `#111827` |
| Surface alt (cards, sheets, inputs) | `#FFFFFF` | `#1F2937` |
| Text | `#111827` | `#F9FAFB` |
| Text muted | `#6B7280` | `#9CA3AF` |
| Outline | `#E5E7EB` | `#374151` |
| Accent (brand) | `#4F46E5` | `#4F46E5` |
| Success · Warning · Error | `#16A34A` · `#D97706` · `#DC2626` | `#22C55E` · `#F59E0B` · `#EF4444` |
| Role — parent 1 · parent 2 | `#1D4ED8` · `#E11D48` | `#3B82F6` · `#FB7185` |

- **Type**: Inter, embedded as a **local variable font, subset to weights 400/500/600/700, no
  italics** — the web target's first-load weight is an open acceptance criterion and CI prints
  the gzip figure on every push. Scale: 32/700, 20/600, 16/500, 16/400 (1.5), 14/400 (1.4),
  12/500 uppercase +0.5 tracking.
- **Spacing** 4 · 8 · 16 · 24 · 32. **Radius** 0 (calendar dividers) · 4 · 8 · 16 (sheets).
- **Elevation** 0 (bordered surfaces) · 1 (app bar on scroll) · 2 (bottom nav) · 3 (sheets).
- **Motion** 150 ms `easeOut` (micro) · 300 ms `easeInOut` (sheets, segmented) · 400 ms
  `fastOutSlowIn` (page transitions, admin banner).
- **Skeleton** base `#E5E7EB`/`#374151`, highlight `#F3F4F6`/`#4B5563`, pure horizontal
  translation, 1500 ms, `Curves.easeInOutSine`.

**Scope**

1. The token file and a hand-written `ColorScheme` for both themes.
2. The eight components every screen repeats — section header, card, badge/pill, empty state,
   list row, sheet handle, primary+secondary action pair, banner — plus the three the review
   added from the form side: text field, segmented button, avatar.
3. Skeleton loaders replacing the 26 "Carregando" points.
4. Migrating the 81 colour literals onto tokens.
5. **The gate**: a test that fails when `Color(0x` appears outside the token file — the same
   shape as the existing `no_literal_snack_test`, which already enforces "no literal strings
   in snackbars". Without it the literals grow back.

**Open spec points** — none blocks the start; each needs a decision while building

- **The input border does not meet the rule it was written for.** `#E5E7EB` on a `#FFFFFF`
  field over a `#F9FAFB` page measures ≈1.2:1 against both neighbours; WCAG 1.4.11 asks 3:1.
  Two honest closures: a real grey (`#6B7280` gives 4.9:1 on white) at the cost of a heavier
  look, or keep the light border as decoration and satisfy 1.4.11 the other way the norm
  allows — **a persistent visible label on every field**, never a bare placeholder.
- **The admin banner fails as specified.** White on `#D97706` is 3.18:1 — large-text only, and
  a banner is body text. Amber takes **dark** text: `#111827` gives 5.5:1 in light and 8.2:1
  on `#F59E0B` in dark.
- **The badge has no dark value.** "10% of the accent" disappears over `#1F2937`, and the
  badge's text colour is unspecified in both themes.
- Minor: a list-row press state of `Surface` over a white card is ≈1.05:1 in light — the
  Material ink ripple carries it in practice, but the token should not be the only signal.

**Out of scope, deliberately**

Screen-by-screen polish; `U-12` (dark mode as a feature — this item makes it nearly free);
`U-21`; `fl_chart` in the summary; biometrics; the `MaterialBanner` rollout for admin mode.
None of them blocks the cutover, and all get cheaper once tokens exist.

**Justification**

The cutover is when production users meet the Flutter app, and first impressions are not
re-issued. Today they would meet a stock Material surface after using a styled PWA — better
underneath, worse to look at. Foundation before the cutover is bounded work that lifts every
screen; polish after it is open-ended work that would delay the whole point of the migration,
which is to stop investing in a frozen stack.


---

**As delivered (20/08/2026, three PRs on `entrelares-flutter`)**

| PR | Version | What |
|---|---|---|
| [#37](https://github.com/irineus/entrelares-flutter/pull/37) | `0.2.29+31` | The token file, both hand-written `ColorScheme`s, the type scale, the migration of every colour literal, and the gate |
| [#38](https://github.com/irineus/entrelares-flutter/pull/38) | `0.2.30+32` | The eleven shared components and their adoption across the screens |
| [#39](https://github.com/irineus/entrelares-flutter/pull/39) | `0.2.31+33` | Skeletons at the content loads, and the admin banner's motion |

**What the numbers turned out to be.** The audit said 81 literals across 13 files; the count
at implementation time was **79** across the same 13 files, all of them gone — the gate
`no_color_literal_test` now fails the build on a `Color(0x` anywhere outside
`lib/theme/tokens.dart`. The "26 places rendering Carregando" were **25 progress indicators
across 18 files plus 3 catalog strings**; the ones that became skeletons are the content
loads, and the rest stayed spinners on purpose (below). Coverage went from 367 widget tests
to **402**.

**Decisions taken while building that the record above did not settle**

1. **Four calendar slots keep a colour, not two.** The record's "two role colours, further
   roles get patterns" would have removed chromatic distinction from slots 3 and 4 — and a
   family with four active carers is exactly the family whose grid is hardest to read. The
   web's four active themes stay (blue · rose · teal · orange), and the non-chromatic vector
   the decision was protecting is delivered as a **texture per slot** (`SlotPattern`), which
   is strictly stronger: with the patterns on, the grid is readable with no colour vision at
   all. Slot 1 keeps "no texture", itself one of the distinguishable states.
2. **The swapped day returns to the web's convention** — amber with a dashed border. It had
   to move: it was using `#E11D48` in Flutter, which is the rose the role pair reclaims.
3. **In dark, the brand indigo lightens to `#818CF8`.** The token table said `#4F46E5` in
   both themes; on `#111827` that measures **2.3:1**, so every accented label would be
   unreadable. Same hue, readable tone — the identity the decision protected survives, and
   this is the same class of measured correction the record itself made for the amber banner.
4. **The input border stays a hairline and the label is always visible**
   (`floatingLabelBehavior: always`) — the second of the two closures the record offered for
   WCAG 1.4.11, chosen because a real grey border makes every form look like a spreadsheet.
   Three fields had **only** a placeholder (the batch note, the frozen-day note, the reply in
   Notifications): a placeholder has no accessible name once the field has text.
5. **The amber banner takes dark text** and **the badge gained explicit values in both
   themes** — the two spec points the record left open, closed as it suggested.
6. **The action pair puts the confirmation FIRST.** Not Material's order, and deliberate: it
   is the order the Blazor app has always used, and the people who meet the Flutter app at
   the cutover arrive with that muscle memory.
7. **Inter is embedded**, instanced into the four static weights of the scale and subset to
   Google Fonts' `latin` range — 438 glyphs, ~57 KB each, **110 KB gzip** for the set against
   a first load of 1,429 KB (`main.dart.js`) + 2,841 KB (`canvaskit.wasm`). `latin-ext` would
   have tripled the glyph count for scripts this product does not render. The PDF keeps
   Roboto (F-33): a report is near-evidentiary and a full font cannot print tofu for an
   unusual name. Regenerable with `apps/entrelares_app/tool/subset_inter.py`.
8. **What did NOT become a skeleton**, documented in the file itself: a button mid-press (the
   spinner is about that press), a determinate bar (the batch and the wizard know their
   progress — a shimmer would throw that away), and a wait with no known shape (the splash,
   and the premium-return screen polling the processor).

**A real defect the work surfaced.** `RenderCustomPaint.hitTestSelf` is
`painter.hitTest(position) ?? true` — a `CustomPainter` that does not override `hitTest`
**absorbs** the tap. The dashed border is drawn over the whole cell, so every swapped day
would have been untappable. Fixed in both painters and pinned by `slot_pattern_test`.

**Files affected (as delivered, all in `entrelares-flutter`)**
- `apps/entrelares_app/lib/theme/`: `tokens.dart` (the only place a colour may be written),
  `app_theme.dart` (both `ThemeData`s, hand-written `ColorScheme`s), `slot_pattern.dart`
- `apps/entrelares_app/lib/widgets/ui/`: `surfaces.dart`, `signals.dart`, `controls.dart`,
  `skeleton.dart`, barrel `ui.dart`
- `apps/entrelares_app/assets/fonts/Inter-*.ttf` + `OFL.txt`;
  `apps/entrelares_app/tool/subset_inter.py`
- Every screen and shared widget, for the literal migration and the component adoption
- Tests: `no_color_literal_test.dart` (the gate), `slot_pattern_test.dart`,
  `ui_components_test.dart`, `skeleton_test.dart`

**Still open, and deliberately outside this item**: `U-12`'s user-facing dark-mode switch
(both themes now exist and the app follows the system), `U-21`, `fl_chart` in the summary,
biometrics, and the `MaterialBanner` rollout for admin mode.

---

### U-28 — Screen-by-screen visual harmonization (the U-27 adoption pass)

| Field | Value |
|---|---|
| **Status** | `completed` |
| **Priority** | `high` — same window as U-27: zero users are on the Flutter app, and after the T-53 stage-4 cutover every visual change is a change to a live product |
| **Complexity** | `medium-high` — no new data and no rule changes, but it touches every screen and carries three real layout defects |
| **Impact** | `high` — this is the app production users will meet at the cutover |
| **Roadmap** | Group 4, alongside `T-53` — **before the stage-4 cutover** |
| **Prerequisites** | `U-27` (delivered 20/08/2026). This item spends what that one built |
| **Delivered** | 20/08/2026 — `entrelares-flutter` `0.2.32+34`…`0.2.42+44`, PRs [#41](https://github.com/irineus/entrelares-flutter/pull/41) (the five lotes) and [#42](https://github.com/irineus/entrelares-flutter/pull/42)–[#47](https://github.com/irineus/entrelares-flutter/pull/47) (six QA rounds on the owner's device) |

> **Origin (20/08/2026).** The owner reviewed the Flutter app screen by screen against the
> frozen Blazor app in production, with paired screenshots, and produced ten written findings
> (icon/splash, login, skeleton transition, calendar, family, profile, notifications, and the
> three reports tabs). U-27 had just closed. The review's verdict was not that the tokens were
> wrong — it was that the screens do not look like they use them.

**The measured root cause**

A code audit of the ten findings collapsed them into six causes, of which one dominates: the
eleven shared components exist and are almost never used. Occurrences in `lib/screens/`:

| Screen | `AppCard` | `AppSectionHeader` | `AppBadge` | `AppSegmented` |
|---|---|---|---|---|
| `family_screen.dart` (1,866 lines) | **0** | 1 | 0 | 0 |
| `profile_screen.dart` (753) | **0** | 0 | 0 | 0 |
| `calendar_screen.dart` (1,141) | **0** | 0 | 0 | 0 |
| `login_screen.dart` (245) | **0** | 0 | 0 | 0 |
| `reports_*.dart` (3 tabs) | **0** | 0 | 0 | 2 |
| `notifications_screen.dart` (587) | 1 | 0 | 1 | 1 |

`AppCard` is used **once in the whole app**. That single fact is what the owner read as
"sections came loose", "the danger zone became plain text" and "the Premium block is
disorganized". The other five causes:

2. **No constraint discipline on rows and grids.** Three visible overflow defects share it:
   `GridView.count` with no `childAspectRatio` gives a ~43 dp square cell for ~50 dp of
   content (`BOTTOM OVERFLOWED`, calendar); the notification card's header `Row` has no
   `Flexible`/`Wrap`, so the date renders one character per line beside its badges
   (`RIGHT OVERFLOWED BY 85 PIXELS`); five `AppBar` actions truncate the month title to
   "agosto de…" for admins.
3. **The calendar `AppBar` became a junk drawer** — five global icon buttons where the month
   name should be. `onSignOut` is a `CalendarScreen` parameter, so **logout is unreachable
   from the other three tabs**: a real defect, not a preference.
4. **Colour was demoted from surface to hairline.** The web tinted the whole member surface;
   the port uses a 4 px left border and leaves the rest neutral. The tokens already carry
   `tone.container`/`onContainer` for exactly this.
5. **Skeletons cover only part of the screen they stand in for.** `AppSkeletonCalendar` lives
   inside `_MonthGrid`, while the today card and the legend simply do not exist until data
   arrives — so half the screen has no skeleton and the layout jumps.
6. **Brand identity is missing at the edges.** The launcher icon is still the stock Flutter
   logo (only `mipmap-xxxhdpi/ic_launcher.png`, no adaptive icon, no `flutter_launcher_icons`)
   and the splash is a bare `CircularProgressIndicator` (`main.dart`), where the web shows the
   U-10 animated calendar. Both masters already exist: `store/brand-emblema.png` and
   `store/brand-emblema-flat.png` with `store/brand-icons.py`, and the U-10 splash is fully
   specified in `Entrelares/wwwroot/index.html`.

**Decisions locked 20/08/2026 (owner)**

1. **Texture stops meaning "which member".** The owner's rule — hatching marks only a member
   who left — is adopted, and it does not cost the U-27 principle that colour is never the
   only vector: **the cell already prints the member's initial**, which is a non-chromatic
   identity vector present in every slot. Active members carry colour plus initial; the
   `SlotPattern` hatch is reserved for slot 0 (inactive/departed), and the swapped day keeps
   its amber dashed border. This *supersedes* U-27's "a texture per slot" decision.
2. **The bottom nav gets colour back, in one place only**: the selected destination's icon
   **and** label take the brand indigo, keeping the Material icon set. Not per-destination
   hues (those colours are reserved for data) and not the old app's emoji.
3. **Account lives in the app bar of every tab.** An avatar button on the right opens Perfil,
   Idioma and Sair (and U-12's theme switch later). It fixes the logout defect, empties the
   calendar app bar, and scales — chosen over a fifth "Sair" nav destination (the old app's
   shape) because logout is an action, not a destination.
4. **Five incremental PRs**, each green on both gates, each demo-able on its own.

**Scope — five PRs**

| PR | Scope | Findings closed |
|---|---|---|
| **1 — foundation and entry** | Three components the set is missing (`AppDangerZone`, `AppBulletList`, `AppTimelineEntry`), the three overflow fixes, the segmented control's selected state, the launcher icon (`flutter_launcher_icons` from the vendored emblem), the U-10 splash ported to Flutter with tokens, and the login screen (calendar mark, divider, legal links on one line, language as a real segmented control, version footer) | 1, 2, part of 3 |
| **2 — shell and navigation** | Account/avatar entry point on all four tabs (logout defect), a month bar above the grid (arrows, month name, calendar actions), bottom nav colour | part of 4 |
| **3 — calendar** | Today card rebuilt on the member's tinted surface with role and handoff time; legend with roles, no texture for active members and no wrap that squeezes the grid; day cell with a real aspect ratio, the handoff time back and a stronger "today"; a skeleton mirroring the whole screen | 3, 4 |
| **4 — família and perfil** | One `AppCard` per section, member rows that do not wrap, the Premium block reorganized (it is where a Free family decides to pay), `AppDangerZone` for "Excluir família" and "Sair da família", icons on "Salvar dados" and "Alterar e-mail", bordered secondary buttons, the language selector back on the profile, the lost copy, the version footer, and the `{0}` placeholder defect in "E-mail atual" | 5, 6 |
| **5 — avisos and relatórios** | A notification card header that cannot overflow, one badge vocabulary, history entries with the inset origin block and the highlighted changed values back, the audit tab as a real timeline at usable density, the summary as tinted per-member cards with the period total, and the PDF tab's header scrolling under the sticky tabs | 7, 8, 9, 10 |

**Defects this item fixes (not preferences)**

- Logout unreachable outside the calendar tab.
- `BOTTOM OVERFLOWED` on every calendar cell that carries a handoff badge.
- `RIGHT OVERFLOWED BY 85 PIXELS` on notification cards whose date meets its badges.
- `E-mail atual: {0} …` — an unsubstituted placeholder on the profile screen.
- The PDF tab's description clipped mid-sentence under the sticky tab bar.

**Content lost in the port, restored here**: the handoff time on calendar cells; the
"Responsável real / Horário da troca" block and "Mensagem do solicitante" in the history; the
period's total swaps in the summary; the "Exportar meus dados" hint in the family-deletion
notice; the app version footer.

**Out of scope, deliberately**: `U-12`'s user-facing theme switch; `U-21` (profile read-only
groups); `U-25` (day sheet); `fl_chart` in the summary; any rule or flow change. Parity is the
floor — where the Flutter platform offers a better answer than the Blazor screen it is taken
(owner directive, 18/08/2026), but never as a rule change.

**Justification**
U-27 bought the vocabulary; without this pass the screens keep speaking the old one, and the
cutover is the single moment production users form their first impression of the rewrite.
Every finding here was written by the owner against a real screenshot pair, and five of them
are defects the app would otherwise ship.

**Files affected**
- `apps/entrelares_app/lib/widgets/ui/` — three new components plus the barrel
- `apps/entrelares_app/lib/screens/` — all ten screens, for component adoption
- `apps/entrelares_app/lib/widgets/today_card.dart`, `lib/screens/home_shell.dart`
- `apps/entrelares_app/lib/theme/app_theme.dart` — segmented and nav bar themes (no new tokens)
- `apps/entrelares_app/android/app/src/main/res/` plus a `flutter_launcher_icons` config; the
  emblem vendored from `store/brand-emblema.png`
- Widget tests per PR; both source gates stay green

---

**As delivered (20/08/2026, one PR carrying the five lotes as five commits on
`entrelares-flutter`)**

| Commit | Version | What |
|---|---|---|
| [`7bfc2eb`](https://github.com/irineus/entrelares-flutter/commit/7bfc2eb) | `0.2.32+34` | The three missing components, the two content overflows, the launcher icon, the U-10 splash ported, the login screen |
| [`6cd20a7`](https://github.com/irineus/entrelares-flutter/commit/6cd20a7) | `0.2.33+35` | Account entry point on all four tabs (the logout defect), the month bar, colour on the active nav destination |
| [`cf96a95`](https://github.com/irineus/entrelares-flutter/commit/cf96a95) | `0.2.34+36` | Today card tinted with role and handoff time, one-line legend with roles, handoff time on the cell, a stronger "today", a skeleton that mirrors the whole screen |
| [`5883048`](https://github.com/irineus/entrelares-flutter/commit/5883048) | `0.2.35+37` | Sections back in cards, both danger zones, the Premium block, the `{0}` defect, the language section and the version footer |
| [`68635e4`](https://github.com/irineus/entrelares-flutter/commit/68635e4) | `0.2.36+38` | The rail on both event logs, changed values as chips, the summary tinted in two columns, each report tab naming itself |

**Five commits, one PR** — [#41](https://github.com/irineus/entrelares-flutter/pull/41).
The record above planned five PRs; a squash merge orphans a branch's history, so five PRs in
series would have cost four rebases to reach exactly the same five commits on `main`. Each
commit is still one closed, reviewable lote.

**Decisions taken while building that the record above did not settle**

1. **A texture means one thing: this member left.** The owner's rule was adopted as written,
   and the U-27 principle it appeared to contradict survives intact — the non-chromatic
   vector was never really the hatch, it was the **initial the cell already prints**. That is
   now pinned by `calendar_slice_test` ("every assigned cell prints the carer initial"), which
   is where the guarantee actually lives; `no_color_literal_test` was rewritten to encode the
   new rule rather than the old one. This **supersedes** U-27's decision 1.
2. **The account button is an avatar, and it needed a service.** The shell owns no data
   source, so `AccountIdentity` (a `ChangeNotifier`, the same shape as `NotificationBadge`)
   lets whichever screen loaded the signed-in member publish it, and the button in all four
   app bars wears their calendar colour. `CalendarScreen.onSignOut` was removed: sign-out is
   the shell's now, which is what makes it reachable everywhere.
3. **The greeting uses the first name.** The web prints the full legal name; on a phone that
   was three lines of card spent on something the reader already knows.
4. **`AppBulletList` asserts in `build`, not in its constructor.** `List.length` is not a
   constant expression, so the constructor assert made every `const AppBulletList` with icons
   fail to COMPILE — found by the first test that used one.
5. **The report tabs dropped their emoji for Material icons.** Emoji stays where the catalog
   owns it — inside sentences the app writes — and leaves the structural chrome, which has to
   follow the selected colour and sit at the same optical weight as every other icon.
6. **The month bar keeps the calendar's own actions** (bulk selection, wizard, admin shield)
   and hands language and sign-out to the account menu. The admin shield stays with the
   calendar because what it unlocks is a day on *this* grid.

**Not delivered, deliberately.** The "Responsável real / Horário da troca" block the web shows
in the notifications history. Those values are not in the `params` of the notification rows
this client receives; composing them in the client is precisely what "the client MIRRORS, the
database ENFORCES" forbids. The audit tab's own origin block (F-45) already existed and stays.
If the block is wanted, it is a server-side item: the params have to carry it.

**What the numbers turned out to be.** The audit predicted the component set was unused; the
count was `AppCard` **once in the whole app**, `AppSectionHeader` once, `AppBadge` once,
`AppSegmented` three times — all in `notifications_screen.dart` and the reports tabs. Coverage
went from **402 widget tests to 439**. Two source gates earned their keep during the work:
`catalog_call_sites_test` caught four keys that stopped being orphans (`calPrevMonth`,
`calNextMonth`, `languageLabel`, `languageHint` — the last two being copy the port had lost),
and `no_color_literal_test` forced the texture decision to be written down instead of just
applied.

**Files affected (as delivered, all in `entrelares-flutter` unless noted)**
- `apps/entrelares_app/lib/widgets/ui/`: `surfaces.dart` (`AppBulletList`, `AppTimelineEntry`),
  `signals.dart` (`AppDangerZone`), `skeleton.dart`, barrel `ui.dart`
- `apps/entrelares_app/lib/widgets/`: `app_splash.dart` (new, with `AppBrandMark`),
  `account_button.dart` (new, `AccountScope` + `AppAccountButton`), `today_card.dart`,
  `app_l10n.dart`
- `apps/entrelares_app/lib/services/account_identity.dart` (new)
- `apps/entrelares_app/lib/screens/`: `home_shell.dart`, `calendar_screen.dart`,
  `login_screen.dart`, `family_screen.dart`, `profile_screen.dart`,
  `notifications_screen.dart`, `reports_screen.dart`, `reports_summary_tab.dart`,
  `reports_audit_tab.dart`, `reports_pdf_tab.dart`
- `apps/entrelares_app/lib/theme/`: `tokens.dart` (the texture rule), `app_theme.dart`
  (segmented and nav bar)
- `apps/entrelares_app/assets/brand/` (the emblem, vendored from `store/brand-emblema.png`),
  `android/app/src/main/res/` (adaptive icon, launch window), `web/icons/` + `web/manifest.json`
- `packages/entrelares_core/lib/src/localization/`: `k.dart`, `strings_pt_br.dart`,
  `strings_en.dart` — `splashTagline`, `navAccount`, `navProfile`, `sumHeading`, `auditHeading`
- Tests: `ui_components_u28_test.dart`, `splash_test.dart`, `account_button_u28_test.dart`,
  `family_profile_u28_test.dart`, `reports_notifications_u28_test.dart`, plus updates to
  `no_color_literal_test`, `skeleton_test`, `calendar_slice_test`, `today_card_test`,
  `family_page_test`, `reports_summary_test`, `catalog_call_sites_test`, `shell_and_auth_test`,
  `lifecycle_test`, `onboarding_test`

**The six QA rounds (20/08/2026)**

The item shipped its five lotes and then met the owner's device, which is where
most of what follows was found. Recording them as one block because they share a
lesson, not because they are afterthoughts: **the first delivery was measured
against the code and this half was measured against a phone**, and the phone won
every disagreement.

| PR | Version | What the round found |
|---|---|---|
| [#42](https://github.com/irineus/entrelares-flutter/pull/42) | `0.2.33+35` | The grid scrolled; the month truncated again; the legend ran off the right edge; the swap key showed on months with no swap (**U-18**, delivered on the web and never ported); **and the owner could not find sign-out at all** |
| [#43](https://github.com/irineus/entrelares-flutter/pull/43) | `0.2.38+40` | Five sheets, the same three faults in each: they filled the screen, the action row scrolled away, and "Cancelar" was gone |
| [#44](https://github.com/irineus/entrelares-flutter/pull/44) | `0.2.39+41` | The fit test did not model the **admin strip**, so it passed while the device scrolled; the third carer's colour measured 1.03:1 against the swapped amber |
| [#45](https://github.com/irineus/entrelares-flutter/pull/45) | `0.2.40+42` | The owner asked whether the cell could size itself. It could — the fixed number was the FLOOR, and a five-week month was leaving a band of dead space |
| [#46](https://github.com/irineus/entrelares-flutter/pull/46) | `0.2.41+43` | A `Container` with an `alignment` expands to fill: every legend key took a full row |
| [#47](https://github.com/irineus/entrelares-flutter/pull/47) | `0.2.42+44` | A `Flexible` under-uses its flex allotment and the `Row` gives the leftover to the END of the line, so the date never reached the right edge |

**What the rounds settled, beyond the fixes**

1. **The sheet is a component, not a convention.** Five sheets with identical
   faults is a missing abstraction. `showAppSheet` caps every sheet at 90% of the
   screen so a strip stays tappable, and `AppSheetFrame` scrolls the body while
   pinning the actions. A source-level test now fails on any
   `showModalBottomSheet` outside the helper: `isScrollControlled: true` with no
   constraints is one line to write by accident and it is what produced all five.
2. **Parenthetical explanations became an ⓘ that opens on TAP.** The owner asked
   for tooltips; a plain `Tooltip` on Android opens on a LONG PRESS, which would
   have hidden the text rather than moved it. Optional fields are marked and
   required ones are not — almost every field in this product is required.
3. **The day cell's height is a RANGE (50–76 dp), not a number.** The grid spends
   what the screen gives it, divided by the weeks the month really has. The floor
   is the content plus the "today" ring; the ceiling stops a short month on a
   tall phone from turning each day into a letterbox.
4. **The way back to today is directional.** Looking at the future the chip sits
   left of the month with a back arrow; looking at the past it crosses to the
   right and the arrow turns. Both sides are always built and collapse when they
   do not apply, so the month name never jumps as the chip swaps ends — and it
   stays clear of the month arrows, which do the opposite thing.

**The lesson worth keeping: presence is not position.** Two of these rounds
existed because a widget test asserted that something was *there* while the
layout put it in the wrong place — the stacked legend keys and the date that
never reached the right edge both passed a green suite. Both now assert
geometry, and so do the calendar's fit tests. When the requirement is about
ARRANGEMENT, a finder is not evidence.

**The gates this item leaves behind**, each one encoding a decision rather than
a preference: the calendar fit test (floor, ceiling, and that a taller screen is
actually spent), the sheet-helper source scan, `no_color_literal_test` rewritten
around "a texture marks the departed member and nothing else",
`catalog_call_sites_test` (which caught six keys going in or out of use during
this item), the legend keys sharing a row, and the date reaching the card's edge.

**Verified on the owner's device 20/08/2026**, including dark mode — which is
the first real confirmation that the U-27 dark palette holds outside a test,
and that the deepened third-carer orange separates there too.

**Still open, and deliberately outside this item**: `U-12`'s user-facing theme switch (the
account menu is where it will go), `U-21`, `U-25`, `fl_chart` in the summary, and the
notifications-history detail block above. None of them blocks the cutover.

---

### T-53 — Flutter/Dart rewrite (the platform bet)

| Field | Value |
|---|---|
| **Status** | `done` (23/08/2026) — stage 1 closed with a **GO verdict** (owner, 19/08/2026; verdict table in [`docs/flutter-migracao.md`](../../docs/flutter-migracao.md)) and **stage 2 DONE the same day**: the parity map lives in [`docs/flutter-paridade.md`](../../docs/flutter-paridade.md) — 51 lines then, **52 since the lote-4 correction** (the Profile page was missing), **41 port · 4 redesign · 2 drop · 5 untouched**, in 6 dependency-ordered build batches, with the T-48 Play Billing redesign and the test-strategy verdicts (unit mirrors port to `entrelares_core`, the C# integration suite STAYS as the DB gate, Playwright → Patrol). **The three product tensions are DECIDED (owner, 19/08/2026, reaffirmed over the map's more conservative recommendations): Flutter Web replaces the PWA; Play Billing enters stage 3's critical path; the Blazor freeze is IMMEDIATE** — policy written in the map; the queue triage below stopped applying 19/08/2026. **Stage 3 OPENED 19/08/2026**: cutover plan (per-screen acceptance checklist + rollback) in [`docs/flutter-cutover.md`](../../docs/flutter-cutover.md); flavors dev/prod delivered in `entrelares-flutter` (dev keeps `com.entrelares.flutter`, prod IS `com.entrelares.app`; `--flavor` mandatory, `[Dev]` tag, app `0.2.0+2`). Batches in order 1→2→3→4→6→5 (billing last). **Lote 1 (foundation) DELIVERED 19/08/2026** in three PRs on `entrelares-flutter` — #6 bilingual i18n U-13/U-24 (`0.2.2+4`), #9 go_router hull + App Links recovery + S-01/S-04 (`0.2.3+5`, paired assetlinks #279 here), #10 Today-at-a-Glance card + T-41/F-32 mirrors + SnackBar/amber banner (`0.2.4+6`) — the two things the pilot never validated (bilingual i18n, App Links in a Flutter shell) are now proven in this stack; App Links QA on the owner's device still pending (needs the dev RELEASE build + the assetlinks dev→master promotion). **Lote 2 (full calendar) DELIVERED 19/08/2026** in four PRs — #11 core rules (FreemiumGates/BulkSummary/day-protection with tier-aware F-40/wizard) + F-39 paging clamp (`0.2.5+7`), #12 full day editor + admin mode F-14 with the proactive F-40 gate (`0.2.6+8`), #13 multi-selection U-11 + Bulk Edit + navigation guard (`0.2.7+9`), #14 Rotation Wizard with the insert-only write preserving existing days (`0.2.8+10`) — deliberately WITHOUT the workflow slice (frozen days, general actual-parent, F-44 ride with lote 3); coverage core + widget (403 + 67 tests), Patrol accrues for the lote-3 lane. **Lote 3 (swap workflow + notifications) DELIVERED 19/08/2026** in five PRs — #15 core mirror of `SwapRequestService` (the two predicates, the F-20/F-22 urgency formula, F-44 plumbing, F-47, the resolve subsets) + the workflow data source (`0.2.9+11`), #16 frozen days 🔔/⏳ + the frozen-day panel (`0.2.10+12`), #17 workflow routing in the day editor and Bulk Edit + "🔔 Resolver" (`0.2.11+13`), #18 the 3-tab Notifications page + bell badge + the F-23 safety poll (`0.2.12+14`), #19 **the E2E lane on the first two-user flow** (`0.2.13+15`) — which is what opens **T-54's E2E lane** (`integration_test` on an emulator against dev, throwaway family, scheduled + on demand). Batch decisions: the F-23 poll SURVIVES as a safety net (25 s socket-down / 120 s healthy) until the socket proves itself under real load; F-45 history enrichment deferred to lote 6 with the audit mirror. Coverage 484 core + 95 widget + the E2E lane. **Lote 4 (account, family and legal) DELIVERED 19/08/2026** in six PRs — #20 core mirrors (RoleCatalog, CustomRoleRules, ConsentDeclarations, PolicyVersions, SudoRules, OnboardingSteps/TourSteps, Register/InviteFormRules) + the S-10 sudo client with the 🔐 sheet and BOTH layers of `runWithSudo` (`0.2.14+16`), #21 native `/register` with the founder × invitee branches, the per-path S-15 consent, the invitation App Link and the cross-family migration question (`0.2.15+17`), #22 the Família page (roster, rename, invitations with the system share sheet, F-37 seat arithmetic) + `/custom-roles` F-41 (`0.2.16+18`), #23 `/profile` and `/profile/{id}` — role change, sudo-gated admin toggle, e-mail/password, and the LGPD export delivered through the share sheet (`0.2.17+19`), #24 S-11 leaving + `/leaving` + the family-deletion panel with unanimity + the persistent banner + the S-15 re-consent gate (`0.2.18+20`), #25 U-23 onboarding (real-state checklist, swap explanation, 4-stop tour with a native spotlight) + **the account E2E pack** (`0.2.19+21`). Batch decisions: **legal pages open in the BROWSER** (one copy of the legal text; an external link is accepted by the stores), **member editing follows the PRODUCT rather than the map** — F-16 moved promote/demote and the role change to `/profile/{id}`, and the `/profile` page was MISSING from the parity map — and the premium/billing block stays out (lote 5, T-38 neutral-paywall rule). Coverage: 678 core + 255 widget + two E2E packs. **Lote 6 (reports, analytics and platform) DELIVERED 19/08/2026** in five PRs — #26 core mirrors of the reports and of the audit trail (the U-20/U-07 counting as ONE function the screen AND the F-33 document call, the field-level diff, the four F-45 origin sentences, the S-10 labels and the synthetic trial-end entry) (`0.2.20+22`), #27 the Relatórios hub with three tabs + "Resumo do Período" (`0.2.21+23`), #28 "Histórico de Ajustes" with its four tabs, incremental "Carregar mais" and **F-45** — the enrichment lote 3 deferred to arrive with the audit mirror (`0.2.22+24`), #29 the **F-33 report as a native PDF** delivered through the system share sheet or the native print dialog, gated by the F-32 mirror with a NEUTRAL upsell (T-38) (`0.2.23+25`), #30 **T-37 analytics** + **the web target** + the batch close-out (`0.2.24+26`). Batch decisions: tabs instead of routes in the hub; **no embedded PDF viewer** (the useful native step is handing the file to the system); **Roboto embedded** in the document because dart_pdf's Helvetica has no Unicode and was DROPPING the Portuguese accents; `premium-gate-click` deferred with the CTAs it measures. **Tension 1 executed**: the web target is enabled and `flutter build web` is in `verify.yml`, printing the gzip first-load weight each run (`main.dart.js` ≈ 1.4 MB, `canvaskit.wasm` ≈ 2.9 MB) — the CHANNEL acceptance (a real first load on a mid-range Android over 4G) is still the owner's measurement. Coverage: 738 core + 312 widget + two E2E packs, plus the U-23 gate the README promised for this moment (`catalog_call_sites_test`: every catalog key has a call site or a written reason for not having one).  **Lote 5 (premium e billing) DELIVERED 20/08/2026 — the LAST functional batch of stage 3** in five PRs: core billing mirrors + the subscription model and reads (`0.2.25+27`), the Premium section on the Família page with its six states, the F-32 waitlist, cancellation and the F-42 way back (`0.2.26+28`), the web rail (T-39 checkout + F-48 Pix avulso) + `/premium/retorno` + the F-43 ledger + the complete T-37 funnel including the `premium-gate-click` lote 6 deferred (`0.2.27+29`), **Play Billing in the client** behind `billing.store_enabled` (`0.2.28+30`), and the SERVER half of the redesigned T-48 in this repo (`play` gateway + UNIQUE purchase token, `billing-store-verify` and the RTDN `billing-store-webhook`, both through the SAME `set_family_plan` and `billing_events`; app `1.8.13`). Batch decisions: **the whole T-48 behind a master switch** (the code exists and sleeps until the Play Console side does), **the store price is Play's** (the product carries it; `app_settings` rules the web rail only), and the **T-38 neutral note is the FAIL-CLOSED default** of the store branch, not merely its off state. The U-23 gate closed its billing list: all 82 keys have a call site, and the list was REMOVED. Coverage: 782 core + 367 widget + two E2E packs, plus `BillingStoreTests` in the C# integration suite (gateway, one-token-one-family, RLS of the new columns, the public switch at `false`, the verify function's own auth). **What is left is not code**: the Play Console configuration in `supabase/README.md` §9-bis, and then the stage-4 cutover. **Stage 3 is functionally COMPLETE.** **U-27 (visual foundation) was delivered on 20/08/2026, between the last batch and the cutover** — the app now has a token layer, both themes, the shared component set and skeletons (`0.2.29+31`…`0.2.31+33`), done while zero users were on it, and **U-28** harmonised it against the owner's screen-by-screen review (`0.2.42+44`). **STAGE 4 OPENED 23/08/2026** — decisions, runbook and rollback in [`docs/flutter-cutover.md`](../../docs/flutter-cutover.md): the Flutter app takes over `web.entrelares.app` (the Blazor moves to `legado.entrelares.app` as the way back), **the store channel cuts first** (its bundle is already in internal test and has already sold), the announcement is a dated banner in the Blazor client, and the code half is DELIVERED: the web channel's pipeline in `entrelares-flutter` (#48/#49 — `deploy-web`, `_redirects`, the CanvasKit CSP, `assetlinks.json`, the service-worker TOMBSTONE that is the only thing that reaches an installed PWA, and the `APP_ENV=prod` fix without which every web build resolved to the QA project, since `flutter build web` accepts no `--flavor`), plus the dated notice here (#298, app `1.8.14`). **The STORE channel was CUT on 23/08/2026**: release `44 (0.2.42)` promoted from internal testing to **Closed testing – Alpha** (177 countries), which turned the TWA bundle (`versionCode 1`) `Inactive` in the same action — inside a track the higher `versionCode` wins, so the promotion WAS the removal. It was a cheap step by luck of timing: install base was **0.00%** on both bundles (every family is on the web channel), managed publishing was off, and the only tester is the licensed one, so `billing.store_enabled` being live risked no real charge. From here the Play package `com.entrelares.app` **is** the Flutter app. **The web channel's QA and its CHANNEL ACCEPTANCE both landed on 23/08/2026**: the owner ran the QA at `entrelares-web.pages.dev` (production config, no domain yet) and it paid for itself — SIX defects, every one invisible on Android because none is about logic: the CSP blocking CanvasKit's font fallback, hash routing (whose real damage would have been an invitation link losing its token AFTER the cutover), the LGPD export dying in the generic snack (its delivery needed `dart:io`), an error sentence printing its own `{0}`, "session expired" on a deliberate sign-out, and an edge-to-edge calendar on the desktop — a parity break, since the Blazor PWA always lived in a centred column. All fixed (`entrelares-flutter` #51…#54, app `0.2.47+49`). And the **first-load measurement on a mid-range Android over 4G — tension 1's acceptance, open since 19/08 — was ACCEPTED**, which closes the last of the three tensions. **THE WEB SWITCH WAS THROWN ON 23/08/2026, AND THE ITEM IS DONE**: `legado.entrelares.app` was attached to the Blazor project and added to the Auth redirect URLs, and `web.entrelares.app` moved to the `entrelares-web` Pages project. Verified from outside the account: the production hostname serves Flutter `0.2.48+50`, a deep route answers 200 (the SPA fallback), `/privacy` 301s to the landing, `.well-known/assetlinks.json` is served — so the installed Android app keeps verifying its App Links — and the service-worker TOMBSTONE answers at the production origin, which is the only thing that reaches a phone with the old PWA installed. **Both channels are now Flutter**, which is what this item set out to decide and then to do: the bet was declared on 12/08/2026 and shipped in eleven days. **What remains is NOT this item**: the Blazor client stays published at `legado.entrelares.app` as the documented way back, and its shutdown — the day the rollback dies — is ops with no date, tracked in [`docs/flutter-cutover.md`](../../docs/flutter-cutover.md). Two loose ends are recorded there too: the `dev`→`master` promotion is held by a RED `BulkUiTests` E2E (deterministic, only when the allocated days land in the last row of the month — a Blazor-only path, untouched by the diff), and with it the `1.8.15` privacy-policy copy inside the old client; the LEGAL requirement is already met, because the Flutter app links the LANDING, published at Versão 1.7 with Google declared as an operator. |
| **Priority** | `critical` as a DECISION — every UI item built in Blazor from now on is potentially throwaway work, which is the owner's stated reason for putting it at the head of the queue |
| **Complexity** | `very high` |
| **Impact** | `very high` (platform, distribution, billing policy, testing strategy) |
| **Roadmap** | Group 4, **Ordem 0 — head of the whole queue** |
| **Benchmark sources** | `irineus/entrelares-console` (the **pilot**, already in production use by the operator) and `irineus/desmalha` (structure, FVM, tooling) |
| **Relates** | **T-47/T-40** (gated — see Sequencing), **T-48** (obsoleted in its current form), **F-09** (push), **T-18** (offline), **F-29/F-23** (the Realtime bridge this retires) |

> **Created 12/08/2026, owner request:** *"vamos refatorar a aplicação para usar flutter + dart,
> assim como as aplicações desmalha e o entrelares-console estão fazendo… caso dê sucesso,
> podemos deixar de lado o blazor e C#"*. **Promoted to next item on 19/08/2026:** *"para não
> perdermos mais tempo adicionando novas funcionalidades em uma linguagem que não será mais
> utilizada"*.

**Why this is not the declined MAUI decision**
MAUI was declined in Aug 2026 for ONE reason: a MAUI Blazor Hybrid renders in a **WKWebView**,
so it would face the same App Review "thin wrapper" scrutiny as the Capacitor shell — it did not
buy the guarantee being paid for. **Flutter renders natively** (Impeller/Skia), so the iOS build
is a genuine native app. The decline is not being ignored; it is being revisited on new grounds.

---

## Stage 0 — benchmark harvest (DONE, 19/08/2026)

Harvested from `entrelares-console/docs/migracao-flutter.md` (written from real QA defects
during the F-58 build) plus the two repos' structure. **This is the item's biggest asset: the
pilot is not a toy — it is a Flutter client of THIS product's own backend, used by the operator
against production.**

### Already PROVEN by the pilot
| Fact | Consequence for the migration |
|---|---|
| `supabase_flutter` works against the Entrelares backend with the **S-16 publishable keys** — SDK puts the key in `apikey` and the user token in `Authorization`, the correct shape | The whole key/header discipline ports for free |
| **Realtime works natively** | The F-29 JS interop bridge + vendored `supabase.js` are RETIRED (keep F-23's poll as a safety net until the socket proves itself under real load) |
| The **S-10 sudo contract** (`ELEVATION_REQUIRED:` marker) survives both transports — PostgREST exception message and Edge Function `FunctionException.details` | `runWithSudo` ported cleanly from the web concept |
| **Pure rules in Dart + `dart test`**, no emulator | Same philosophy as the C# helpers and mirror tests — the ~511 unit tests have a natural home |
| Edge Functions with `verify_jwt` ON work with the normal user session | No gate loosening needed for user-called functions |
| A **cloud session can develop, test AND build the APK** (`storage.googleapis.com`, `dl.google.com`, `pub.dev` reachable; coexists with the `dotnet` install) | Assistant sessions are not blocked — unlike today's integration/E2E |
| **The Play package `com.entrelares.app` can receive a Flutter build** — same `applicationId`, same upload signature | ⭐ **No new Play app, no restarted closed test, no re-filled forms.** F-54 just paid that cost once; the migration does not pay it again |

### Costly lessons already paid for (each from a real defect)
1. **A restored session is not a live session.** `supabase_flutter` restores a persisted session
   whose refresh token may be dead → every call fails `42501`. Gate the app opening with
   `refreshSession()` BEFORE routing. Blazor gets this for free via the `forceLoad` DI-scope
   recreation; **Flutter has no equivalent — the gate must exist from day one.**
2. **Without a valid session the client is `anon`**, which in this 100%-RLS product has no
   privilege at all (T-44) — the `42501` reads like a GRANT bug and is not. Map that signature
   to "sessão expirada" centrally.
3. **`signOut()` with a dead token throws** → the Sair button silently does nothing.
   `try/catch` → `signOut(scope: local)`, and navigate always.
4. **Refresh before sensitive operations** (sudo/elevate failed as "senha incorreta" after hours
   backgrounded); never collapse heterogeneous failures into one message — propagate the
   server's own text (already reader-language since U-13).
5. **`INTERNET` permission is missing from the release manifest** in the `flutter create`
   template — the release APK has NO network and it looks like a DNS bug. First thing to check.
6. **Debug keystore is per machine** — create the real keystore early (the product already has
   this discipline from F-54).
7. **`--split-per-abi`**: 52 MB universal → 18 MB arm64 for direct distribution; `.aab` for Play.
8. **The `Supabase` singleton initializes once per process** → environments via
   flavors/build variants, never a runtime switcher.

### Structure benchmark (from `desmalha`, 37.5k lines of Dart, 36 test files)
Monorepo **`apps/` + `packages/`**, with a **pure-Dart core** testable without an emulator; FVM
pin (**Flutter 3.44.7**) + JDK 17; idempotent `tool/setup_env.sh`; a `tool/verificar_ambiente.dart`
that fails loudly when the toolchain drifts from what the repo declares; **Codemagic** for the
iOS lane (free macOS runner, 500 min/month — the owner's machine is Windows without Xcode);
Sentry anonymous by construction. The Entrelares equivalent: `packages/entrelares_core` (pure
Dart — the priority tags, `CalendarHelpers`, `FreemiumGates`, `PolicyVersions`, `RoleCatalog`,
the U-13 catalogues and U-24 formats, the notification renderer: exactly what today's unit suite
covers) + `apps/entrelares_app`.

### What the pilot did NOT validate (the migration must prove it)
Bilingual i18n by reader (U-13/U-24 — the console is PT-only), push/APNs (F-09), deep links +
`assetlinks` in a Flutter shell, offline persistence (`desmalha` uses Drift+SQLCipher — the
benchmark for T-18), Realtime under real load, and iOS (T-47/T-40's verdict still stands).

---

## Stages 1–4 (reversible until stage 3)

- **Stage 1 — vertical-slice spike. EXECUTED 19/08/2026** in the new repo
  **`irineus/entrelares-flutter`** (desmalha mold: `apps/entrelares_app` +
  `packages/entrelares_core`, FVM 3.44.7, JDK 17, minSdk 26; spike applicationId
  `com.entrelares.flutter` so the APK coexists with the Play app on the owner's device).
  The slice: session gate (refreshSession before routing), month calendar under RLS
  (slots F-27/S-11, initials F-28, swapped, legend), native day sheet, the write path
  with the full-row T-33/T-35 echo and translated conflicts, NATIVE Realtime reloading
  the month — plus the owner-directed native improvements (month swipe, pull-to-refresh,
  haptics). 50 pure `dart test` mirrors (same cases as CalendarHelpersTests) + 10 widget
  tests. Emulator floor: cold start ~1.5 s median, release APK arm64 17.3 MB. The
  go/no-go number is the OWNER's device run — script in
  `entrelares-flutter/docs/medicao-estagio-1.md`, verdict table in
  [`docs/flutter-migracao.md`](../../docs/flutter-migracao.md).
- **Stage 2 — parity map. EXECUTED 19/08/2026** in
  [`docs/flutter-paridade.md`](../../docs/flutter-paridade.md): feature-by-feature inventory
  (the README feature table plus U-13/U-24 and T-38 from the testing section — 51 lines; 52 after the lote-4 correction),
  each marked port/redesign/drop/untouched with its test strategy, grouped into 6
  dependency-ordered build batches. 40 port · 4 redesign (Realtime already done in stage 1,
  T-39/T-48 billing, F-33 PDF, PWA/offline) · 2 drop · 5 untouched. Carries the T-48
  Play Billing redesign, the test-suite verdicts, and the three product tensions —
  **decided by the owner the same day** (recorded there, with the written freeze policy
  in force since 19/08/2026). The "rewrite" is now a finite, schedulable list.
- **Stage 3 — parallel build behind a cutover plan. OPENED 19/08/2026.** Point of no
  return. Its three prerequisites exist in writing: the freeze policy (in
  [`docs/flutter-paridade.md`](../../docs/flutter-paridade.md)), the per-screen acceptance
  checklist and the rollback plan valid until the last user migrates (both in
  [`docs/flutter-cutover.md`](../../docs/flutter-cutover.md)). The opening delivery also
  shipped the environment model in `entrelares-flutter`: build flavors dev/prod
  (dev = `com.entrelares.flutter` against the dev project, prod = `com.entrelares.app`
  against production; `--flavor` mandatory, flavor-less targets fall back to dev), the
  lote-1 `[Dev]` environment tag, and the CI dispatch building the dev flavor. **T-55
  (per-flavor release signing) DELIVERED 19/08/2026** — prod distribution unlocked.
  Batches proceed 1→2→3→4→6→5, each as PR(s) with the acceptance checklist per screen.
- **Stage 4 — cutover + decommission. OPENED 23/08/2026**, in one dated, announced
  step PER CHANNEL (owner: the store cuts first, the web after — its bundle is already
  in internal test and has already sold, so promoting it is Play Console ops with no
  code). Decisions, runbook and rollback in
  [`docs/flutter-cutover.md`](../../docs/flutter-cutover.md); the code half is delivered
  (the web pipeline in `entrelares-flutter`, the dated notice here). The **Blazor
  shutdown is the LAST action**, and the day the rollback dies: until it, the old client
  stays published at `legado.entrelares.app`, and the Playwright suite stays the flow
  gate of the promotion to production — the Flutter `integration_test` lane is
  scheduled, not per-push, so retiring Playwright first would leave the promotion with
  no flow gate at all. The repo `entrelares-app` is NOT retired with the client: it
  remains the repo of the database, the Edge Functions, the backlog and the integration
  gate.

## The three product tensions to answer before stage 3 — ANSWERED 19/08/2026
> Decisions recorded in [`docs/flutter-paridade.md`](../../docs/flutter-paridade.md): Flutter Web
> replaces the PWA; Play Billing enters stage 3's critical path; the Blazor freeze is
> immediate (written policy there). The paragraphs below keep the original framing.
1. **The web IS the current distribution** — the landing sells *"Sem loja de apps"* and every
   alpha user arrived through the PWA. Flutter Web exists but is a different animal: (a) Flutter
   for stores + keep the Blazor PWA (two codebases), (b) Flutter Web replaces the PWA (measure
   first-load on a mid-range Android over 4G first), or (c) stores-only, web becomes marketing.
2. **Store billing gets harder, not easier.** A genuinely native app increases IAP pressure, and
   **T-48 is obsoleted in its current form** — the Digital Goods API is a Chrome/TWA mechanism;
   a Flutter app needs real Play Billing. The T-39 web-first rail cannot be assumed to survive
   untouched.
3. **Two live stacks during the transition**, maintained by a solo developer while production
   carries real subscriptions. This is the dominant risk; the triage below is what bounds it.

## Queue triage — what is safe to build in Blazor meanwhile
> **SUPERSEDED 19/08/2026** by the owner's immediate-freeze decision (tension 3, recorded in
> [`docs/flutter-paridade.md`](../../docs/flutter-paridade.md)): new client features are Flutter-only
> from that date; only the freeze policy's exceptions still enter Blazor. The table below stays
> for history — its server-half column remains true (DB/Edge halves serve both stacks).

The owner's concern ("stop adding features in a language we are dropping") has a sharper answer
than a blanket freeze: **the database/Edge-Function half of every item survives the rewrite
untouched; only Blazor UI is throwaway.** So, while stages 0–2 run:

| Verdict | Items | Why |
|---|---|---|
| **Fully survives** — build freely | T-51, T-52, T-36, S-17 (ops); U-26 (e-mail templates live in `functions/_shared`); every `L-*` (the landing is a separate stack) | No Blazor code at all |
| **Mostly survives** — build the server half now, defer the screens | F-56 (solo mode: member states + RPCs), F-55's child entity (schema + RPCs), F-52 (aviso: table + notifications), F-51's RPC | The rules live in the DB, which is the whole point of "the client mirrors, the database enforces" |
| **Throwaway if the bet lands** — hold | U-25 (day sheet), U-12 (dark mode), U-21 (profile), F-55's timeline UI, F-57's screens (its GoTrue/provider config survives) | Pure Blazor UI |

## Sequencing — the thing that must not be missed
**T-47's spike (US$99 + weeks) and T-40 exist ONLY to get a WebView wrapper past Apple.** If
Flutter is chosen, both become moot — the Flutter iOS build is native. The **stage-1 verdict must
land before T-47 is executed**. If Flutter is declined, T-47/T-40 proceed unchanged.
**GO declared 19/08/2026** → T-47/T-40 do NOT execute (they stay on the board as conditional
discards until stage 3, the point of no return, removes them for good) and T-48's redesign
(real Play Billing instead of the Digital Goods API) entered the stage-2 parity map —
its dual-rail design (Play Billing for the store channel, Asaas kept on the web rail,
both webhooks converging on `set_family_plan`) is in
[`docs/flutter-paridade.md`](../../docs/flutter-paridade.md).

## Success criterion (written before starting, per the owner's own framing)
The slice reaches parity with the current calendar + day sheet, with (a) cold start and first
interaction no worse than the PWA on a mid-range Android, (b) an E2E suite a solo developer can
keep green, and (c) development velocity at least comparable for equivalent work. Fail any of
the three and the answer is "keep Blazor" without regret — stages 0–2 exist to make that outcome
cheap.

**Files affected**
- [`docs/flutter-migracao.md`](../../docs/flutter-migracao.md) — stage-0 harvest + stage-1 record
  and verdict table (the pilot's `docs/migracao-flutter.md` stays its own living record)
- [`docs/flutter-cutover.md`](../../docs/flutter-cutover.md) — stage-3 cutover plan: acceptance
  checklist per screen, rollback plan, environment/flavor decisions, channel acceptance gates
- Spike location DECIDED at stage 1: the separate repo **`irineus/entrelares-flutter`**, so the
  production CI never sees the experiment and the bet stays reversible by construction
- Nothing in the current app until stage 3

---

### T-56 — Archive the `entrelares-app` repository

| Field | Value |
|---|---|
| **Status** | `completed` (24/08/2026) |
| **Priority** | `high` — every extra day was a day the product's written memory lived in a repository nobody opened |
| **Complexity** | `high` (70 migrations, 12 Edge Functions, a 225-test database gate, the whole backlog and three ops pipelines) |
| **Impact** | `high` — it decided where the product's written memory lives |
| **Roadmap** | Outside the groups: structural debt opened by the cutover, not forward plan |

> **This item REVOKED a written decision.** The cutover plan
> ([`../../docs/flutter-cutover.md`](../../docs/flutter-cutover.md), § *"Onde o rollback morre"*,
> 23/08/2026) said: *"o repo `entrelares-app` NÃO é aposentado: ele continua sendo o repo do
> banco, das Edge Functions, do backlog e do gate de integração"*. That held while this repo
> was the T-53 spike and the Blazor client was the product. The cutover inverted both roles
> the next day, and keeping the database, the gate and the written memory in a repository
> nobody opens is the shortest path to losing them. New owner decision, 24/08/2026.

**Description**
Make `entrelares-app` **archived**: no longer needing to be updated and, above all, no longer
needing to be consulted. Everything about the application moves to `entrelares-flutter`;
`entrelares-site` keeps answering for the site.

The **eight decisions**, the **three measurements** behind them and the **PR-by-PR plan** live
in [`../../docs/arquivamento-app.md`](../../docs/arquivamento-app.md), which is this item's
operational record. What the three measurements settled, because they overturned assumptions:
the database gate was tied to the Blazor client by only 1.010 lines of PostgREST contracts (not
by the suite itself); the Playwright suite was 62 tests against the 5 of this repo's
`integration_test` lane, so replacing the FLOW gate — not the database one — was the hard
problem; and this repo has no staging stage, since a merge to `main` publishes production.

**How it closed**
Seventeen PRs here plus two in the old repo, all on 24/08/2026. The session tooling and the
memory moved first (1, 4a, 4b, 4c), then the database and its ops (2, 3), then the flow gate
that had to exist before the Playwright suite could die (5), then the port of the database gate
to Dart suite by suite (6…16), then the emptying of the old repo (F), and finally the shutdown
(this record's last two bullets). The arithmetic that watched the port held: **225 assertions at
the start, 225 at the end**, printed in every run's summary and repeated in every PR body.

- ~~The **flow gate** replacing the Playwright suite.~~ **Delivered 24/08/2026**: the same
  `integration_test` files run in a headless browser (`flutter drive` + chromedriver), 144 s for
  both packs against the 10-15 min of the emulator lane. It does not replace the emulator for
  what needs a device. Wired into `deploy-web`'s `needs:` on 24/08/2026 — the role Playwright
  played for the old repo's promotion.

  > **CORRECTED 25/08/2026 — this bullet claimed a gate that was not gating.** What it said was
  > that the lane "was MEASURED before being trusted, because `flutter drive` on web prints
  > 'All tests passed.' whether or not anything ran: a probe with a deliberately failing test
  > turned the job red", and that it therefore "blocks the web publish… what makes it a gate
  > rather than a report". The first half is true and the conclusion does not follow.
  >
  > The probe failed a **test body**. The suite was failing in **`setUpAll`** — and a blown
  > fixture does NOT turn the job red: `flutter drive` still printed "All tests passed." two
  > seconds after the debug service connected, a window in which no real call to Supabase fits.
  > So the lane approved **without executing a single assertion**, on every merge that published
  > production from 24/08/2026 onward, including this item's own PRs #78, #79 and #80.
  >
  > The fixture bug is older than T-56: `integration_test/e2e_family.dart` reads
  > `roles.role_name`, and that column has never existed — it is `role` since the baseline
  > (`20260713000000_baseline_v1_4_0.sql`), and the only `role_name` around is an OUTPUT field
  > of the `get_invite_info` RPC. It arrived with the lane itself, in T-53 lote 3 (19/08/2026,
  > #19). What belongs to T-56 is not the bug — it is **promoting that suite to a
  > publish-blocking gate on a verification that missed the failure class actually occurring**,
  > and then writing the claim down as settled.
  >
  > Found on 25/08/2026 by the session investigating the E2E lane, and verified here
  > independently: on its run `32839960732`, once the `role_name` defect was out of the way,
  > `web-e2e` went **red** at the drive step. Red-capable at last, which is the proof that it
  > was not before.
  >
  > **Still open as this is written:** the fix lives in PR #81, which is not merged, so `main`
  > still carries the vacuous lane. Turning it into a gate that can actually stop a publish is
  > a change of regime, not a test fix, and it is the owner's call — deliberately NOT made from
  > inside this correction.
  >
  > **The method lesson, which is the reusable part:** a probe proves what it exercises and
  > nothing more. This one proved the lane can report a failing assertion; it never asked
  > whether the lane can report a suite that never got to assert. When a check exists precisely
  > because a tool lies about success, the probe has to cover **every** way the run can end —
  > and the record of it must say which ways were covered. This one said "measured" and meant
  > "measured once, one way".
- ~~The **port of the database gate to Dart**, suite by suite.~~ **Done 24/08/2026**, in the
  eleven PRs (6…16) whose slicing, merge authorization and verification arithmetic are in
  [`../../docs/arquivamento-app.md`](../../docs/arquivamento-app.md). The 225 tests are 43 suite
  libraries under `packages/entrelares_db_gate/test/suites/`, and `db-gate/` is gone with PR 16.
  Its foundation (PR 6) settled three things the ten that followed inherited: the row contracts
  left the app into `packages/entrelares_db_contracts`, so the gate asserts against the SAME
  shape the app reads; the gate is one aggregating entrypoint rather than a file per suite,
  because `dart test` gives a `setUpAll` per FILE and the naive port would create 41 throwaway
  families per run against the shared QA project; and the identity clients come from the
  PURE-Dart `supabase` package, never `supabase_flutter`, whose per-process singleton (the
  pilot's lesson 8) could hold exactly one of the four the gate needs.

  **What the crossing found, which is the argument for having done it as eleven PRs against the
  real database rather than as one rewrite.** PR 7 turned red on
  `type 'Null' is not a subtype of type 'String'` — `FamilyDeletionRequest.fromJson` read
  `created_at` and the table has no such column, it is `requested_at`. That factory is the one
  the app parses through, and the Família screen renders `requestedAt`, so **the screen crashed
  for every family with a pending deletion request**, in production, since the cutover. No
  widget test could have caught it: they build the object in memory, and the column name is only
  a claim about a table nobody was asking. The gate asked on its first run.
- ~~The **emptying** of the old repo, in a single PR.~~ **Done 24/08/2026** (`entrelares-app`
  #309, squash-merged to `dev`): 242 files, −46.941 lines. What was left there is the frozen
  client, its unit suite and a `deploy.yml` reduced to the half that publishes — the QA deploy
  that followed the merge went green in **1 min 39 s**, against the ~15 min of the old gate.
  Three things that were NOT in the plan are recorded in **What stayed behind, and why** below.
- ~~The **gap the emptying opened**: four C#↔Deno mirrors with no Dart equivalent.~~
  **Closed 24/08/2026**, and it is the one open end that turned out to be hiding a live defect —
  see **The four mirrors** below.
- ~~The **Blazor shutdown**, which is when the rollback dies — triggered by a measured condition
  (N days without a hit on `legado.entrelares.app`), never by a date.~~ **Done 24/08/2026, and
  not by the measurement.** The owner declared the rollback no longer needed, which is the
  decision the measurement existed to provoke rather than to replace: decision 7 bought a
  verifiable trigger so the last step could not drift indefinitely, and the trigger was overtaken
  before it ever fired. `entrelares-app` #310 removed the last workflow, the QA alias
  `qa.entrelares.app` and the PR template that still instructed a flow with no deploy behind it,
  and rewrote both docs to describe an archive rather than a published client.

  **What that closed, and it is more than a domain.** The old `master` still carried the
  PRE-emptying `deploy.yml` — including its *"Aplicar migrations e functions em PRODUÇÃO"*
  steps, pointed at a `supabase/` copy that had been standing still since PR 3. Any push there
  would have written production schema from the stale copy, in competition with this repo. That
  is the two-writer hazard decision 5 exists to prevent, and it lived on for one day inside the
  branch nobody was pushing to.

  **The promotion needed a second pass, and the reason is worth keeping.** `dev`→`master` was
  refused by a repository ruleset requiring the status check **`deploy`** — the check produced by
  the workflow the same delivery removes. The lock outlived the door: the ruleset protected a
  production the shutdown had just retired, and satisfying it would have meant re-adding a
  pipeline to an archive. **The generalizable half:** a required status check is a dependency on
  a workflow's continued existence, so any delivery that removes a pipeline must ask what is
  still requiring its checks.

  **Unblocked by the owner on 25/08/2026, and reading the rule changed the action.** The first
  instruction written for it was "delete the ruleset" — written before anyone had read it.
  `protect-master` has THREE rules: `deletion`, `non_fast_forward` and the required check. Only
  the last one blocked a fast-forward promotion, so unchecking *Require status checks* cleared
  the way while keeping the branch protected against deletion and history rewrite, which is what
  that ruleset existed to do. **A rule that gets in the way is not automatically a rule to
  delete**, and the difference between the two actions cost one read-only API call.
  `origin/master` now sits on the shutdown commit with no `.github/` at all.

  **The console work finished on 25/08/2026 and was verified from outside the account**: the
  `legado.` and `qa.` hosts no longer resolve, the Pages project is gone, the zone carries no
  dangling record, both Auth projects are clean, and `irineus/entrelares-app` is **archived** —
  read-only, kept for its history. `web.entrelares.app` and the landing answered 200 throughout.
  **T-56 ends there.**

**The four mirrors, and the defect the port found (24/08/2026)**
Four unit tests left with the `supabase/` they read: `RoleCatalogMirrorTests`,
`EmailDateFormatMirrorTests`, `AuthMailMirrorTests` and `NotificationParamsCoverageTests`. They
were the C#↔Deno mirrors — the Edge Functions cannot call into the client, so the role labels,
the e-mail date format, the `redirect_to` language marker and the `params` coverage over every
notification writer are duplicated ON PURPOSE, and those tests were what made the duplication's
drift RED. They are Dart now, in `packages/entrelares_core/test/mirrors/`, reading the same
`_shared/i18n.ts` and the same `supabase/migrations`. They live in the CORE package, not in the
app: they need no Flutter, and the core lane runs first, so a drift goes red in the cheapest job
of the run.

**Porting one of them found a missing half.** `AuthMailMirrorTests` asserted that the client
writes `?lang=` into the reset `redirect_to`; the Flutter app never did — `DeepLinkUrls.updatePassword`
was a bare constant. Nothing was broken, and that is exactly why it survived the cutover
unnoticed: `send-auth-email` ranks `profiles.language_detected` third and the app writes that
column, so anyone who had signed in once still got their language. But signal 2 is the only one
that serves a person who CANNOT sign in — which is the definition of someone asking for a
password reset — and it was always absent. Restored with `DeepLinkUrls.updatePasswordFor(language)`
and the shared key in `AuthMail.languageQueryParam`.

The worst case was checked against the CODE rather than inherited from the Blazor record: if a
project's Redirect URLs allow-list does not match a query string, GoTrue falls back to the Site
URL, and `AuthChangeEvent.passwordRecovery` routes to `/update-password` from wherever the app
is — the same mitigation `MainLayout` used to give.

The reset mirror is the one translation that STRENGTHENS its original instead of copying it: the
C# pinned a single named method, and this app has two reset entry points, so the Dart version
reads every `resetPasswordForEmail` call site under `lib/` and requires each to carry the
language. All four were then measured before being trusted — a divergent label, a divergent
month, the Deno constant renamed, a call site stripped of its language and a live `INSERT` with
no `params` each turned the matching suite red.

**What stayed behind in the old repo, and why (the emptying, 24/08/2026)**
- **`Entrelares/` and `Entrelares.Tests`** — the client that served the rollback route, and the
  only suite that could still validate a change to it. Everything else went. They stay in the
  archived repository as history: with the shutdown there is no route left to fix.
- **The Playwright suite and the C# integration suite went, both of them** (owner decision,
  24/08/2026). The plan had kept them on one sentence — *"until then it is still the flow gate
  of the promotion to production"* — and that sentence expired the same day: this repo's own
  flow gate (PR 5) now blocks the web publish, the database gate had lived in `db-gate/` since
  PR 2, and the Blazor client was frozen. They left together because `Entrelares.E2ETests`
  referenced `Entrelares.IntegrationTests` by `ProjectReference`.
- **The test steps left `deploy.yml`, which was the point rather than a side effect.** Both
  suites ran against the SAME dev Supabase project that `db-gate` now uses on every PR here,
  and the T-39 billing seeds use FIXED external ids (`sub_e2e_*`): two overlapping runs delete
  each other's rows. The migrations/functions steps went with them (schema and app travel in
  the same push, in the repo where the app lives), and so did the unit-test step — without the
  other two it protected nothing that repository still decided.
- **`dependabot.yml` went too** (owner decision): a weekly NuGet/Actions PR aimed at `dev` is,
  with no gate left, an unvalidated change to a rollback route. Security ALERTS do not come
  from that file and are unaffected.
- **Three defects the sweep found, none of them on the list.** The `.gitignore` still named the
  PRE-REBRAND folder for the app settings, so since F-54 the real file — which carries the
  environment's URL and anon key — was ignored by nobody; `SharedParentalCustody.slnx` pointed
  at two projects that stopped existing with the same rebrand; and `tsconfig.json` +
  `Directory.Build.props` existed only to keep `supabase/**/*.ts` out of the MSBuild TypeScript
  compiler. The lesson is about method: a list of "what comes" written before execution is not
  a check — what checks is reading the source repository whole, at the end.

**The adversarial finding, and the CI consequence it left (24/08/2026)**
`AdversarialTests.CrossFamilyAuditLog_IsNotReadable` went red with
`57014 — canceling statement due to statement timeout` after five suite runs in two hours
against the dev project. It was NOT an RLS breach: the assertion never ran. The test read
`activity_logs` **with no filter** and let RLS do the work, so its cost grew with everything the
QA project had accumulated — not with the size of its own throwaway family — and it hit the
8 s `statement_timeout` of the `authenticated` role. **Applied in PR 7**, and it is the one line
of the whole port that is not a translation: the Dart `adversarial.dart` filters by the foreign
log's own id and asserts the result is empty, which is the same claim at constant cost. The
suite header says so, so the divergence from the C# original cannot read as a slip.

**The process half of that episode is fixed too.** `verify.yml` cancelled in-progress runs of
the same ref at WORKFLOW level, which is right for minutes and wrong for `db-gate`: a job cannot
opt out of a workflow-level cancellation, so the serialized group that existed precisely to keep
two suites from overlapping was still being killed mid-suite, and a killed run dies before its
teardown and leaves a throwaway family for the orphan sweep to collect two hours later.
Cancellation moved down to the jobs that can afford it (`verify`, `apk`, `e2e`, `web-e2e`);
`db-gate` keeps its repo-wide serialized group, and **`db-prod` and `deploy-web` now QUEUE
instead of cancelling** — killing a migration or a publish half-way is a worse outcome than
waiting for the one in front. That last part is wider than the finding and was taken
deliberately: it was the workflow-level group that had been protecting them, and removing it
without replacing it would have silently made a concurrent push able to interrupt a production
deploy.

**What the shutdown's own cleanup list was missing (25/08/2026)**
Writing the owner's runbook in detail found two things the plan had never written down, and both
are about the same blind spot: **a runbook records what it ADDS and rarely what undoes it.**
- **The Auth allow-list.** Step 4b of the cutover added `legado.entrelares.app` to the Supabase
  Redirect URLs so recovery and invitations still worked through the rollback route. Nothing
  anywhere said to remove it. Alone it is a dead entry; combined with a DANGLING CNAME — which is
  exactly what remains if the Pages project is deleted before its custom domain — it becomes a
  path for whoever claims that subdomain to receive password-recovery links. The runbook now
  orders the steps so the CNAME dies with the domain, before the project is deleted.
- **The Site URL is a second field, and nobody looked at it.** Removing `legado.` from the
  Redirect URLs is the obvious half; the **Site URL** on the same screen is what GoTrue falls
  back to when a `redirect_to` does not match the allow-list — silently, per runbook §5.3. The
  DEV project's Site URL was `https://qa.entrelares.app`, and that host died with the Pages
  project, so the dev fallback started pointing at nothing. **This lands on this item's own
  change:** the `?lang=` restored above is precisely the case where an allow-list entry written
  without a query string may fail to match, and this record's claim that the worst case is MILD
  rests on `passwordRecovery` routing from wherever the app is — which is only true while the
  Site URL is a LIVE host. A mitigation that depends on configuration has to be re-checked every
  time the configuration moves. Found by reading the console screenshots of the cleanup, not by
  any test.
- **`cutover.web_date` looks like cutover litter and is pinned by the gate.**
  `packages/entrelares_db_gate/test/suites/app_settings.dart` asserts the row exists with
  `value_type = 'string'`, so tidying it away turns `db-gate` red and blocks the web publish. The
  suite header already says the key is spelled out by hand there precisely because the helper
  that owned it died with the Blazor client — the warning is now in the owner's runbook too.

**Related**
T-53 (the cutover that inverted the two repos' roles), T-52 (the legacy Play package, whose
Blazor arms died with this shutdown), T-29 (schema and app travel in the same push — the
invariant decision 5 preserves).

---

### T-47 — iOS publishability spike (real App Review verdict before T-40) — SKIPPED

| Field | Value |
|---|---|
| **Status** | `skipped` (26/08/2026 — post-cutover board sweep, owner decision) |
| **Priority** | `high` (as scoped) |
| **Complexity** | `medium` |
| **Impact** | `high` (as scoped) |

**Why it was skipped.** The item existed to buy **Apple's own verdict** on the risk that a
Capacitor shell around the Blazor WASM app would be rejected as a "thin wrapper" (Guideline
4.2) — a fear born in the Aug 2026 architecture review that evaluated and declined a .NET
MAUI rewrite, since a MAUI Blazor Hybrid faced the same WKWebView review. The T-53 cutover
(23/08/2026) dissolved the premise instead of answering it: the product is a Flutter app, the
iOS channel is a **native build** (`flutter build ipa`), and there is no wrapper for Apple to
judge. Paying US$99 + days of spike effort to test a shell that will never ship stopped
making sense.

**What survived.** The spike's useful mechanics — validate the platform work cheaply, with
zero users affected, before the listing budget is spent — became **step 1 of the rewritten
T-40**: a TestFlight validation pass (build, signing, upload, one internal round) that
surfaces icons, launch screen, permission strings and plugin platform code early. The
build-lane consideration (macOS runner's 10× minutes multiplier vs a local Mac; click-by-click
steps for a Windows owner) moved into T-40's scope verbatim.

---

### T-50 — Move the Playwright traces off the GitHub artifact quota (to R2) — SKIPPED

| Field | Value |
|---|---|
| **Status** | `skipped` (26/08/2026 — post-cutover board sweep, owner decision) |
| **Priority** | `medium` (as scoped) |
| **Complexity** | `low` |
| **Impact** | `medium` (as scoped) |

**Why it was skipped.** Created 07/08/2026 from a real incident: a red E2E run could not
upload its `e2e-traces` because the account-wide 500 MB artifact quota was full, so the
diagnostic vanished exactly when a test was failing. The producer of those traces was the
Blazor repo's Playwright suite — and it died whole with the archiving of `entrelares-app`
(T-56, 24/08/2026). The flow-gate role passed to `web-e2e` (the same `integration_test`
files in a headless browser), which uploads nothing, and this repo's only CI artifact is the
debug APK at **1-day retention**. The quota pressure the item existed to relieve no longer
has a source.

**What survived.** The lesson, not the work: a diagnostic step must never be able to change a
verdict (`continue-on-error: true` on any future upload step), and if the `web-e2e`/emulator
lanes ever start recording heavy diagnostics, a **new item with real scope** replaces this
one — the R2 bucket + credential pattern from T-19 remains the named lever.

---

### F-57 — Social login (Google now, Apple with the iOS wrapper) — DELIVERED (the Google half; Apple rides T-40)

| Field | Value |
|---|---|
| **Status** | `done` (27/08/2026, `2.1.2+57`, PRs #92 + #93 + #99) — **phase 1 (Google) only, by the item's own design**: the Apple half was always coupled to T-40 (the App Store requires Sign in with Apple once ANY third-party login exists) and moves with it. **LIVE on both projects since 27/08/2026**, when the owner ran `supabase/README.md` §9-ter; Android shows the button only after a Play promotion of a bundle ≥ `2.1.2+57` |
| **Priority** | `high` — owner 12/08/2026: *"creio que possa ser implementado o quanto antes"* |
| **Complexity** | `medium` — accurate, but not where the record guessed: GoTrue did the heavy lifting, and the real work was a trigger invariant nobody had listed |
| **Impact** | `high` (kills the confirmation-e-mail failure mode — the whole 07/08 QA round — for Google sign-ups) |
| **Depends on / relates** | S-13/S-15 (consent moved into the deferred onboarding), U-21 (the profile shows the sign-in method for password-less sessions), T-40 (Apple half), F-15/F-28 (invite claim via OAuth, delivered), **T-61** and **U-30** (both found while testing this item on a real device) |

> **Created 12/08/2026 from closed-alpha feedback; delivered AND switched on 27/08/2026.**

> **Follow-up finding, 28/08/2026 — the go-live was one console step short, and it is the step
> with no signal.** Preparing T-61, the Google Auth Platform console showed the app still in
> **Testing**: §9-ter.0 step 2 (Audience → publish) was never executed. Since 27/08 that means
> Google sign-in worked **only for accounts on the test-user list** — the owner's device test
> passed for exactly that reason — while every other alpha tester met a closed door, and anyone
> who did get in is signed out after 7 days.
>
> Nothing in the delivered code is wrong and nothing here changes it; the switch is still the
> provider config. What failed is the *verification* of a config step: `/auth/v1/settings`
> reports whether the provider is enabled and **nothing about publishing status**, so the one
> command the runbook recommended came back green over a half-configured app. There is no
> endpoint for the missing half — only the console — and a check that cannot see a failure mode
> reads as proof that the failure mode is absent. Runbook corrected in the same delivery
> (§9-ter banner and 9-ter.0 step 2).

**What shipped (decisions locked with the owner, 27/08/2026)**

- **The central finding, absent from the record's edge list:** `handle_new_user` RAISES for a
  sign-up without founder metadata, and as an `AFTER INSERT ON auth.users` trigger that abort
  kills the auth user itself — a Google account simply never came into existence. The fix is
  the **deferred profile**: a sign-up carrying neither `invite_token` nor `role` creates the
  auth user with NO profile, and the app confines that session to a new `/onboarding` screen
  (`AuthPhase.onboarding` in the route rules — the S-11 leaving confinement's shape at the
  other end of the account's life).
- **Deliberately NOT keyed on the OAuth provider:** the first gate run proved the Admin API
  cannot forge `provider: google`, so a provider-based branch would be a production rule the
  db gate can never exercise. The absence of OUR metadata is the true discriminator (both
  legitimate flows always send it); a bare password sign-up straight at the GoTrue API now
  defers to the same onboarding — documented behaviour, pinned by the suite.
- **Two doors create the profile:** `complete_oauth_onboarding` (RPC, founder: role + family
  name + S-13 consent validated against `policy.current_version` — the S-15 posture) and
  `claim-invitation` (JWT-verified Edge Function + service_role SQL twin, invitee), with the
  S-11 cross-family migration adapted to **automatic account linking**: a departed member
  signing in with Google lands on their EXISTING auth user, so the old frozen profile is
  DETACHED (`user_id → NULL`, tombstone kept) and the caller's session survives the
  migration — the register-invitee flow deletes and recreates instead, because there the user
  is new.
- **The fail-closed switch is GoTrue's own settings endpoint** (`/auth/v1/settings`): the
  button renders only where the project says the provider exists, so config and UI cannot
  disagree, each environment arms itself, and the owner's flip is the provider toggle in the
  console (runbook `supabase/README.md` §9-ter). No `app_settings` flag — the login screen is
  anonymous and reads no table anyway.
- **Android returns by per-flavor custom scheme** (`<applicationId>://login-callback`, the
  manifest's `${applicationId}` placeholder): an https App Link on a custom-tab redirect is
  the flaky half of Android deep linking, and one shared scheme would open a chooser on the
  owner's two-flavor device. Web round-trips to its own origin.
- **U-21 slice:** a session whose providers exclude `email` sees its sign-in method in place
  of the password card — offering "alterar senha" to a password-less account would submit
  against nothing.
- **The device round (#99), after the owner tested the delivered flow.** Two moves, one
  rule: *an affordance placed after the cost it avoids does not avoid any cost.* The Google
  button went ABOVE the password fields — it exists so nobody invents a password, and at the
  bottom it arrived once that price was already paid; everything below it is now explicitly
  the secondary path. And the account identity ("Conectado como <address>") plus its escape
  hatch went above the form, because the wrong-account realisation happens at the prefilled
  name — and the ADDRESS is what carries it, since two accounts of one person routinely share
  a display name. Both positions are pinned by coordinate-ordering tests: here the order IS
  the feature, and nothing else in the tree would notice it drifting back down.
- Coverage: `oauth_onboarding` + `claim_invitation` gate suites (deferred trigger, founder
  RPC, claim, thief token, stale policy, S-11 migration with surviving session); 13 widget
  tests (fail-closed button, both onboarding branches, migration dialog, profile swap,
  the two orderings); route-rules and onboarding-validation cases in core.

**Verified on a device, not only in CI (27/08/2026).** All three paths were walked on real
hardware: a new Google account reaching `/onboarding` and founding a family; an invited
address claiming through Google; and an existing password account **linking** and landing
straight on its own calendar, never seeing onboarding. That last one is the account-linking
posture this item chose, and the OAuth round trip is precisely what CI cannot exercise —
there is no Google to redirect to inside a runner.

**Two findings it produced, both recorded as their own items.** **T-61**: the Google consent
screen *and* the summary e-mail Google sends afterwards both name `<ref>.supabase.co`, never
Entrelares — a blocker for the public rollout, on the one screen where the product asks for
someone's identity. **U-30**: an account that linked Google to an existing password login now
has two doors and the profile screen shows one, so "I changed my password" reads as a lock
that is not there.

**What the next reader should know.** The `_isRestoring`/`_isSigningUp` guards the record
pointed at were the BLAZOR AuthService's — dead with the archiving; the Flutter equivalents
(`_userSignOut`, `SessionGate`) needed no change. What DID need change was
`_syncProfileLanguage`'s fetch-and-swallow, which silently let a profile-less session into
the shell: phase resolution now happens before the shell renders (`_resolveAuthedPhase`).

---

### T-57 — Bring the whole product listing to the current app (icon, art, screenshots, copy — PT-BR + en-US) — DELIVERED

| Field | Value |
|---|---|
| **Status** | `done` (28/08/2026) — repo halves in [#105](https://github.com/irineus/entrelares-flutter/pull/105) and [entrelares-site#62](https://github.com/irineus/entrelares-site/pull/62), promoted to the landing's production in [#63](https://github.com/irineus/entrelares-site/pull/63); the Play half published as **Console submission 9**, 11 changes, 28/08/2026 11:32. **Absorbs and closes L-21.** Nothing left over except two follow-ups recorded below, neither of which belongs to this item |
| **Priority** | `high` — raised from `medium` on 26/08/2026. It opened as "nothing is broken, the pictures are merely old"; the sweep below found the listing **claiming a feature the product does not have** (offline) and the Console apparently serving a pre-masking screenshot upload. A listing is a claim about the system, so a stale one is not merely unflattering |
| **Complexity** | `medium` — the capture is one sitting; the cost is the seeded family, the two languages, the three publishing surfaces, and the fact that the mark, the art, the frames and the copy have to land TOGETHER |
| **Impact** | `high` — it is the store listing's and the landing's whole visual argument, and it is also where the product makes its public promises |
| **Roadmap** | Group 5 (polish), taking the slot L-21 vacates |
| **Repo** | `flutter` (the app being photographed, `store/`, and the mark's generator) **and** `entrelares-site` (the landing's own art and frames). Plus the Play Console uploads, which live in no repo at all |

> **Absorbs [L-21](https://github.com/irineus/entrelares-site/blob/preview/ROADMAP.md)
> ("English screenshots for `/en/`"), 24/08/2026, owner decision.** L-21 was written on
> 10/08/2026 with a premise that has since died: that the PT-BR captures were current and only
> the English set was missing. The cutover (T-53) replaced the client they photograph and
> U-27/U-28 replaced its visual system, so **both** sets are now stale — and one capture session
> produces both. Splitting "shoot the EN frames" from "publish the EN frames" would create a
> hand-off inside a single sitting.

**Description**
Re-capture the eight product frames from the **Flutter** app and republish them to both
consumers. The current set was captured on **23/07/2026** from the QA environment of the
**Blazor** client, with the `[Dev]` badge masked in place afterwards.

The eight frames (the names are the contract — the landing's `<picture>` elements and their
`alt` text reference them, so keep them):

| File | What it shows |
|---|---|
| `today-calendar-meu-dia` | Home: the day card when the day is the viewer's, plus the month |
| `today-calendar-dia-do-outro` | The same card in its two-colour state |
| `calendario-tres-cuidadores` | The month with three caregivers, one colour each |
| `editor-dia` | The day sheet: responsible, handoff time, observation |
| `troca-aguardando-aprovacao` | A pending swap with Aprovar / Recusar |
| `assistente-rotacao-com-avo` | The rotation wizard building a cycle with a grandmother |
| `historico-auditoria` | The immutable history with date and time |
| `familia-membros` | The family screen with members and the e-mail invitation |

Each one ships as a **`.png` + `.webp` pair, 1080×1920**. The PT-BR set keeps its place at
`entrelares-site/public/img/screenshots/`; the English set goes to a **parallel directory**,
`public/img/screenshots/en/` — L-21's call, and it is the right one: `public/index.html` and
`public/en/index.html` point at the same files today, so overwriting them in English would
hand the PT-BR page an English UI and merely move the defect. The **Play listing** takes the
PT-BR set for `pt-BR` and the English one for `en-US`, uploaded in the Console.

**Two constraints inherited from L-21/L-03, and they are not stylistic**

- **No invented data and no mocked screens** — the frames are a claim about the system, so
  this is the S-15 rule applied to marketing assets. Fictional family, real running UI.
- **Keep the `webp` + `png` pair and the existing `loading`/`width`/`height` attributes**, or
  the hero's LCP regresses. The `alt` text on `/en/` has to describe the English screen it
  will then actually show.

If **L-17** (the landing's animated demo of the immutable history) is scheduled anywhere near
this, do them in the same sitting: the recording and the stills come from the same running
app, and standing that app up is the expensive part.

**The item grew to the WHOLE listing (26/08/2026, owner decision)**

It opened as "re-shoot the eight frames". Two things happened after it was written: **U-29
replaced the mark** (26/08 — the calendar card whose day cells draw the two interlocked houses)
and a sweep of the live listing found that the frames were the least of it. The owner's call:
the item now covers **every surface a stranger sees, in both languages**, and they publish
**together**.

**Why together, and not one fix at a time.** U-29 deliberately did NOT move the store icon —
[`store/README.md`](../../store/README.md) §2 records the reason: *"the Play listing stays on the
clay emblem until the listing art is updated as a whole — screenshots, feature graphic and icon
together (coordinate with T-57)"*. Shipping the icon alone gives the store one mark and eight
photographs of another; shipping the frames alone does the mirror image. **This item is the
release condition of that decision**, and it is not met surface by surface.

**A · The mark — three places, none of them the bundle**

The launcher icon travels in the `.aab` and U-29 already regenerated it, which is why the
INSTALLED app shows the new mark while the store shows the old one. The listing icon is a
different artifact with a different delivery path, and nothing in any build touches it.

| Where | What |
|---|---|
| [`store/store_icon.png`](../../store/store_icon.png) | **Done (PR 1, 28/08/2026).** The decision was to teach the script: `store_listing()` writes the 512² at its OWN framing — mark at **60%**, against the PWA's 66% — because Play rounds it and masks it to a circle in some surfaces, which is the crop the hand-supplied file used to survive. A separate function is what stops one framing from drifting into the other. **Uploaded 28/08/2026** (Console submission 9) |
| Play Console → *Grow users → Store presence → Main store listing → **App icon*** | The upload itself |
| `entrelares-site/public/` | `favicon.png`, `icon-192.png`, `icon-512.png`, `og-cover.png`, `og-cover-en.png` — **five** files, all moved to the U-29 mark on 28/08/2026 and live on `entrelares.app` since the `preview`→`main` promotion ([site#63](https://github.com/irineus/entrelares-site/pull/63)). The landing keeps one rendered master (`assets-src/brand-marca.png`) plus a resize script, so the geometry has a single home in the app repo |

**B · Feature graphic (1024×500, required by Play)**

[`store/feature-graphic.png`](../../store/feature-graphic.png) is still the clay art, rendered from
`feature-graphic.html` with headless Chrome. Re-render against the new mark and **re-upload** —
§3's warning applies: *Play serves its own copy and nothing updates it automatically*.

The English side is a known hole, not an oversight: `feature-graphic-english.png` is
**2950×1440** — Play's 2.048∶1 ratio, but the form takes 1024×500 — and there is no
`feature-graphic-english.html` that reproduces it. An en-US listing either downscales that file
or gains a generator. Decide which; do not leave the EN listing showing the PT graphic.

> **Done (PR 1, 28/08/2026): the EN gained a generator.** Both files are re-rendered on the new
> mark, from `feature-graphic.html` and the new `feature-graphic-english.html`, at 1024×500. The
> plaque in both is `store_icon.png` shown 1∶1, so the graphic cannot drift from the launcher —
> re-run `brand-icons.py` before re-rendering. The 2950×1440 clay file was replaced by the render
> (it drew an emblem U-29 had already retired, and it had no source to re-render from). **Both
> were uploaded on 28/08/2026** (Console submission 9).

**C · The eight frames — with a finding attached**

The frames and their file names are as described above, unchanged. What is new is this:

> **The Console's screenshots look like an upload OLDER than the repo's files (26/08/2026).** On
> the live Play page, both calendar frames carry an orange **DEV** pill at the bottom right. The
> versioned files — `entrelares-site/public/img/screenshots/today-calendar-meu-dia.png` and
> `calendario-tres-cuidadores.png` — were opened and **do not have it**: the `[Dev]` masking was
> done, in the repo. So the two consumers that `store/README.md` §1 calls "one set" have drifted,
> and the store is the one that drifted. **Confirm at full size in the Console before acting on
> it**; if it holds, the listing has been telling every visitor since 13/08 that they are looking
> at a development build. It also kills the assumption that a re-upload is optional whenever the
> files already exist in the repo.
>
> **The repo half is confirmed (28/08/2026): the Flutter app has no DEV pill at all.** The only
> environment marker in the client is `environmentPrefix`, and it goes into stored notification
> TITLES (`main.dart`), not into any widget — `grep` finds no badge, banner or pill. So a DEV pill
> on the live listing can only come from the **Blazor** client, i.e. from an upload older than the
> 13/08 masking. Confirm at full size in the Console; the repo side needs nothing.
>
> **Closed by the re-upload (28/08/2026).** Submission 9 replaced every screenshot in both
> languages, so whatever the Console was serving is gone regardless of how it got there. The
> lesson it leaves is the durable part: **a file being correct in the repo says nothing about
> what the store serves**, because Play keeps its own copy and no build touches it.

**D · The copy — where this stops being cosmetic**

[`store/listing-pt-BR.txt`](../../store/listing-pt-BR.txt) and
[`listing-en-US.txt`](../../store/listing-en-US.txt) were last touched when they MOVED repositories
(#70, 24/08); their content predates the cutover. **Re-verify every sentence against the code
before re-publishing — the S-15 rule, applied to marketing.** The sweep already found one:

> **"Funciona também offline (os dados sincronizam ao reconectar)" is not true of this product.**
> **T-18** — *"Offline-first data strategy (read cache + offline indicator)"* — is `pending` in
> this very file. If offline worked, that item would not exist. The sentence was written for the
> **Blazor PWA**, whose service worker cached the shell; what answers at that URL today is the
> **tombstone** worker, which deletes caches by design (T-53 stage 4). The claim did not rot
> through neglect — the cutover falsified it, and nobody re-read the listing.

> **Confirmed and removed (PR 1, 28/08/2026).** `grep -rn offline apps/entrelares_app/lib`
> returns exactly **one** hit, and it is a comment in `supabase_custody_data_source.dart` — no
> cache, no indicator, no worker. The bullet is deleted from both files rather than softened:
> there is nothing true to say in its place while T-18 is `pending`. Its slot went to the **web
> channel**, which does exist. Worth recording: **the landing never repeated the claim** — the
> defect was the Play listing's alone.

Two more to check, stated as questions rather than verdicts:

- **"Notificações em tempo real […] chegam na hora para todos os responsáveis."** In-app Realtime
  exists (plus the F-23 poll), but **F-09, push notifications, is `pending`** — with the app
  closed, nothing arrives. Decide whether the sentence survives as written.
  **Decided (PR 1): it does not.** The paragraph now splits the promise the way the code does —
  live updates *with the app open*, and e-mail (`send-swap-email`, which fires on
  `swap_requested`, on every resolution and on the F-24 reminder) when it is closed. A third
  sentence moved in the same pass, unprompted: the PDF report is gated by `_isPremium` in
  `reports_pdf_tab.dart`, so the copy now names it as Premium.
- The store shows the app as **"Entrelares (acesso antecipado)"**. That is Play's own
  early-access tag from the closed test, not our copy — recorded so the next reader does not go
  hunting for it in `listing-pt-BR.txt`.

The **en-US listing** gets the same treatment, and it is not a translation exercise: it is the
same verification performed in the other language, against the same code. Console path —
*Main store listing → Manage translations → English (United States)*; the default language stays
pt-BR.

**E · The publish, in one sitting**

Nothing here is delivered by a merge. The repo half is `store/` plus `entrelares-site`; the store
half is **manual uploads in the Console** — icon, feature graphic, eight screenshots per
language, and both listing texts. Do them as one pass, in both languages, and only then is the
U-29 decision discharged.

**Where the item ended (28/08/2026)**

All five parts closed on the same day. The repo halves went in
[#105](https://github.com/irineus/entrelares-flutter/pull/105) (copy, listing icon, both feature
graphics) and [site#62](https://github.com/irineus/entrelares-site/pull/62) (the sixteen frames
and the mark), the landing reached production through
[site#63](https://github.com/irineus/entrelares-site/pull/63), and the Play half published as
**Console submission 9** — 11 changes, both languages, 28/08/2026 11:32.

| Part | State |
|---|---|
| **A · the mark** | **done in both repos.** `store/store_icon.png` is back under the script; the landing's five brand files moved to the U-29 mark; the four clay masters (two per repo) deleted — no vector source, and the geometry now has one home, with the landing holding a rendered master instead of a second drawing |
| **B · feature graphic** | **done, both languages**, with a generator each |
| **C · the eight frames** | **done, both languages** (28/08/2026) — see below |
| **D · the copy** | **done, both languages** |
| **E · the publish** | **done.** Console submission 9 published 28/08/2026 11:32 — app icon, both feature graphics, phone + 7" + 10" screenshots and the full description, in `pt-BR` and `en-US`. The tablet sets were not in the item's plan and were replaced too: they carried the same Blazor material |

**The frames were shot from PRODUCTION, across TWO families — and only one of them was
disposable.** The decision behind it: **the PRODUCTION project, with a disposable family created
for the shoot** — a `--flavor prod` / `APP_ENV=prod` build against
real production, as the first gotcha below prescribes. The alternative considered and rejected
was seeding the family in **dev** through `service_role` (server-written notification titles
carry no `[Dev] ` prefix, since the prefix is applied by the CLIENT on write, so the frames
would have come out clean); it was rejected for fidelity. Two consequences were planned for — the families are real
production data and have to be **removed by hand afterwards**, and they must not be named
`E2E-…`, which the purge sweep would eat mid-session — and the first of those turned out to hold
for only one of the two.

> **The cleanup, and why half of it did not happen (28/08/2026).** The frames came from
> **`Família Andrade` (id 18)**, created the morning of the shoot, and **`Familia Neves` (id 2)**,
> which was **not** created for it — it dates from 02/08/2026. Andrade was purged in full: 2
> profiles, 90 `care_schedules`, 103 `activity_logs`, 1 notification, 1 invitation, the family
> row and **both `auth.users`**, verified afterwards by a sweep that found zero orphan
> notifications and **zero `auth.users` without a profile anywhere in the project**.
>
> **Neves was kept, deliberately, and the reason is worth writing down: it holds the ledger of
> real money.** Ten `billing_events` — `PAYMENT_CREATED`×2, `PAYMENT_RECEIVED` and
> `PAYMENT_PARTIALLY_REFUNDED` on the Asaas rail (02–03/08), then `PAYMENT_DELETED` +
> `SUBSCRIPTION_DELETED`, and the **`PLAY_PURCHASE_VERIFIED` plus three RTDN of 23/08 — the real
> purchase that proved the T-48 store go-live**. `purge_e2e_family`'s own comment says that table
> is denormalized on purpose so the *audit survives the subscription*; deleting the family would
> have deleted the audit it was built to preserve. The owner keeps Neves as the production test
> family (28/08/2026).
>
> **Two traps met on the way, both worth repeating.** `purge_e2e_family` **refuses** either
> family by design — the double signature wants `E2E-` in the name and `@resend.dev` on every
> e-mail, exactly so a fixture bug cannot delete a real family — so the teardown had to be
> hand-written. And its body has been rewritten five times: the **T-39 version**
> (`20260728150000`) is the one to copy, because it deletes `notifications` by
> `recipient_profile_id` (that table has no `family_id`), adds `billing_events`, and moves
> `activity_logs` to **after** `care_schedules`, since deleting days fires the audit triggers that
> write fresh log rows. The July body gets all three wrong — the `CREATE OR REPLACE` gotcha in
> `CLAUDE.md`, met in the wild.

**How the capture actually went, and what it cost (28/08/2026)**

Shot on an Android device rather than in the browser, so the frames arrived **1440×3088 JPEG** —
20∶9, which is neither the 1080×1920 of the existing set nor a ratio Play takes. The fix, applied
uniformly: crop the OS chrome (**94 px** of status bar, **35 px** of gesture pill — measured, not
guessed), fit to height, then pad the width by **replicating the edge column**, which is seamless
because the app's left and right edges are flat (white AppBar, `surface` middle, white nav). A
20∶9 screen cannot become 9∶16 without either losing content or letterboxing, and losing content
was the worse trade. The hero's `webp` came out at 76 KB against the previous 80 KB, so the L-03
LCP constraint held.

**Two measurement bugs are worth knowing before anyone repeats this**, because they had the same
shape: a search window that ended exactly where the boundary was, so the code reported the window
edge as the answer. The first cropped 185 px off the top (the status bar *plus* the app's
safe-area inset); the second cropped 186 px off the bottom and **silently ate the navigation
bar's labels** — and the frames looked fine until they were compared against the source. Size the
window to contain the *gap after* the boundary, never to the expected answer.

Three rounds of review were needed on the family itself, and every one was the same class of
defect — **the data looked like test data**. First a third caregiver named "Tio (Tio)": name equal
to role, and an uncle where the file name `assistente-rotacao-com-avo` and both pages' `alt` text
promise a grandmother. Then an `EN-today-calendar-meu-dia` that was really a second
`dia-do-outro`, because the card is unified only when the viewer IS the day's responsible
(`isUnified = userSlot == responsibleSlot`, `today_rules.dart`) — a state that needs the right
ACCOUNT logged in, not the right screen. **Neither was visible by looking; both came from reading
the frames against the rules.**

Left as-is by owner decision, and recorded so the next session starts from a list instead of
re-deriving one: the family renders "Familia Neves" without the accent; the swap message reads
*"combinado, busco as 18h"*; the day note names a different child in each language; and
`historico-auditoria` shows four instances of the same action, where an approval would have told
the product's actual story.

**Two findings for other items, both from running this item's own acceptance — *open the Play
page and the landing as a stranger would*.**

1. **The landing's install instructions point at a host that does not exist.** `public/index.html`
   and `public/en/index.html` both tell the reader to open **`app.entrelares.app`** — twice each,
   under *Android (Chrome)* and *iPhone e iPad (Safari)*. That name does not resolve (`curl` gets
   no connection); the web channel is **`web.entrelares.app`**, which answers 200. Four
   occurrences, on the section whose only job is to get a stranger into the product, live in
   production. `app.entrelares.app` survives elsewhere only as `Env.analyticsHostname`, an Umami
   label that was never a host. **Fixed the same day**, in
   [site#64](https://github.com/irineus/entrelares-site/pull/64), on the owner's instruction —
   as a landing defect rather than as part of this item, and it is worth more than everything
   this item shipped.
2. **"Android e iPhone" and "Sem loja de apps" — checked, and NOT defects.** Read in context
   both hold: the PWA does run on both platforms, the install section gives the steps for each,
   and the Play listing is still a CLOSED test, invisible to a visitor — so a page that says it
   installs "sem loja" is describing the path it actually offers. They were left alone on
   purpose: correct copy should not be edited early to look thorough. **They flip at T-59**
   (closed test → public availability), where a checklist line now says so, together with the
   Google Play badge block that already sits commented out in both pages waiting for exactly
   that event.

**Acceptance:** open the Play page and the landing as a stranger would, in each language, and
find nothing left of the previous product — no clay mark, no Blazor screenshot, no DEV pill, and
no sentence the code cannot back.

**Four things that will bite, all knowable in advance**

1. **Do not shoot the dev flavour.** `SupabaseCustodyDataSource.environmentPrefix` puts
   `"[Dev] "` at the head of every stored notification title on non-production flavours. It is
   a deploy marker, deliberately outside `params` — so it is baked into the text a
   notification frame would photograph, and no amount of masking fixes a title. Shoot a
   **production-configured** build (`--dart-define=APP_ENV=prod` on web, `--flavor prod` on
   Android) against a family created for the purpose.
2. **The language is resolved, not toggled.** `LanguageResolver` reads localStorage override →
   `profiles.language` → `navigator.language`. The English set therefore needs the override or
   a profile stamped `en` — not a device-language guess, which is what makes an English frame
   silently render Portuguese.
3. **The seeded family has to be plausible AND disposable.** Three caregivers (the
   `calendario-tres-cuidadores` and `assistente-rotacao-com-avo` frames need the grandmother),
   real-looking names, a swap mid-flight for the approval frame, and history for the audit
   frame. It must not be a real family's data, and it must not be an `E2E-` family the purge
   sweep will eat mid-session.
4. **A closed test survives a listing update**, so this does not have to wait for a release —
   but it should PRECEDE the next production rollout, which is the argument the
   `store/README.md` note has been carrying.

**Justification**
The listing and the landing are the only two places where somebody who has never opened the
app decides whether to. Both currently show the Blazor client under the pre-U-27 visual
system: the product is misrepresented *cosmetically*, not in what it claims — which is why
this is polish and not a defect, and also why it never becomes urgent on its own and has to be
written down to happen at all.

**Files affected**
- `entrelares-site/public/img/screenshots/*.{png,webp}` — the eight PT-BR frames, re-shot
- `entrelares-site/public/img/screenshots/en/*.{png,webp}` — the English set (new directory)
- `entrelares-site/public/index.html` + `public/en/index.html` — `alt` text review; `/en/`
  finally points at the English captures (the L-21 half)
- `entrelares-site/ROADMAP.md` — L-21's record, closed as absorbed
- `store/README.md` §1 — the "out of date" note comes down when the frames are current
- Play Console (owner ops, no code): the `pt-BR` and `en-US` screenshot sets

---

### F-09 — Push notifications for swap requests — DELIVERED

| Field | Value |
|---|---|
| **Status** | `done` (29/08/2026) — PR 1 (the rail) in [#109](https://github.com/irineus/entrelares-flutter/pull/109), PR 2 (the Android client) in [#110](https://github.com/irineus/entrelares-flutter/pull/110), PR 3 (the U-23 step, the two device-round fixes and the close-out) in [#111](https://github.com/irineus/entrelares-flutter/pull/111). Shipped in `2.3.0+59`. **Android is live; iOS inherits the rail inside T-40; web push is explicitly NOT in scope** |
| **Priority** | `low` — kept, and it is the honest label. The Realtime bridge already covers everything that happens while the app is open, so this only reaches the person who is not looking |
| **Complexity** | `high` — confirmed, but not where the record expected. The transport was the easy half |
| **Impact** | `medium` |
| **Roadmap** | Group 5 (polish) |
| **Repo** | `flutter` |

> **Re-analysed 29/08/2026 before any code, at the owner's request** ("this requirement is a bit
> old — re-read it against the current app and against push on Android *and* iOS"). The
> 26/08 rewrite had already replaced the Web Push/VAPID scope with FCM and that direction held.
> What the re-read changed was the COST, in three places the record had not seen.

**What the re-analysis found**

1. **There is no `apps/entrelares_app/ios/` at all** — the scaffold was never generated (the
   owner is on Windows). So iOS here is not "harder", it is untestable: no Mac, no Apple
   Developer Program, no device. iOS became T-40's, and the rail was written iOS-ready instead.
2. **`_shared/i18n.ts` does not carry the notification catalog.** It exports `swap`, `account`
   and `authMail`; the ~25-type `NotificationRenderer` catalog lives only in Dart. The record
   said "assemble the payload with the server-side mirror" as though that mirror existed.
3. **Wanting iOS *at all* forces the server-side render immediately.** A data-only payload could
   have reused the Dart renderer with no duplication, but on iOS a silent push is throttled and
   not guaranteed to arrive — so the only payload that displays with the app dead is one whose
   text the server already wrote. There is no "start data-only and add iOS later" path that does
   not rebuild the rail.

**The four decisions locked with the owner (29/08/2026)**

| Question | Decision |
|---|---|
| Platforms in this item | **Android now; iOS inside T-40.** The rail is iOS-ready — T-40 adds the APNs key and the token registration, and rewrites nothing |
| How the text is built | **Server-side, for a SUBSET of types.** A new TS mirror, deliberately small |
| Push vs e-mail | **Push ADDS; the e-mail is untouched.** The F-38 quota is unchanged. "A live token" is a common lie — uninstalled app, revoked permission, an OEM killing the process — and trading a delivered e-mail for it would lose the notice silently |
| Firebase boundary | **Two projects (`entrelares-dev` / `entrelares-prod`)**, mirroring the two Supabase projects, so a QA service account cannot reach a production device |

**What shipped**

- **The dispatcher hangs off the single writer.** Every push-worthy moment already writes a
  `notifications` row — some from SQL triggers, some from the client's own insert — so an
  `AFTER INSERT` trigger on that table (pg_net → `send-push-notification`) is the one choke point
  that covers both writers. Push, in-app and e-mail become three renderings of ONE event, and a
  future writer gets push with nothing to remember.
- **Ten types push, and the rule is "only what the recipient did NOT just do."** That excludes
  the self-receipts (`swap_sent`, `revert_sent`, `swap_approved_self`, `revert_approved_self`),
  which reach a person holding the phone that produced them, and the F-28 family fan-out, which
  is information rather than a call to act. A mirror test pins those five OUT.
- **`push_subscriptions` is the only table in the schema that is NOT family-scoped.** A
  registration token is the capability to interrupt someone's phone, and sharing a family is not
  consent to hold it — own rows only, with the gate suite proving the UPDATE path (which does not
  throw; it matches zero rows and answers success, so the assertion is on the ROW).
- **The permission is spent by a gesture, never by opening the app.** Android 13+ shows the
  dialog once per install and a refusal is only undone in Settings. `start` runs on every
  authenticated session and only REPAIRS a registration for someone who already said yes;
  `enable`, on the Notificações screen, is the only caller that prompts.
- **Four states, not two.** Collapsing `blocked` into `off` produces a button that does nothing
  when pressed, because the dialog will not appear — the app looks broken while behaving exactly
  as designed. `blocked` has no button; it has the sentence that points at Settings.
- **The U-23 step is platform-conditional, and that is not cosmetic.** The checklist hides itself
  when everything is done, so a step the web can never finish would pin the card at "3 de 4"
  forever. `OnboardingSteps.visibleIn` drops it where there is no transport; marking it "done"
  instead would tell someone they had finished something they never did.

**Two traps that would each have cost a device session**

- **A notification channel that does not exist is dropped silently.** On Android 8+ a payload
  naming an unknown `channel_id` is discarded by the system with no error: FCM reports delivery,
  the server logs success, and nothing appears. `entrelares_swaps` is created in `MainActivity`.
- **`start` awaits its own initialization.** The auth gate is a network round trip and the
  transport start-up is local, so the ordering "usually" works — and "usually" is how a feature
  ends up silently off for whoever's transport took a moment longer.

**The web bundle does not carry a transport it cannot use.** Firebase sits behind
`PushMessaging`, chosen at COMPILE time (the `file_delivery.dart` idiom). Two payoffs: zero
occurrences of `firebase` in the web `main.dart.js`, and a service that a suite can finally
drive — `firebase_messaging` is a platform channel with no Android under `flutter test`, so
before the seam the permission path, the token rotation and the notification tap were
unreachable by any test.

**Files**
- `supabase/migrations/20260828120000_f09_push_subscriptions.sql` — table + RLS + dispatcher
- `supabase/functions/send-push-notification/`, `_shared/push.ts`, `_shared/fcm.ts` (FCM HTTP v1
  by hand: the v1 API wants a service-account JWT, and `firebase-admin` is a Node tree that does
  not belong in an Edge Function)
- `packages/entrelares_core/lib/src/push_enrollment.dart` + suite; `test/mirrors/push_notification_mirror_test.dart`
- `packages/entrelares_db_gate/test/suites/push_subscriptions.dart`
- `apps/entrelares_app/lib/services/push_service.dart`, `push_messaging{,_io,_web}.dart` + suite
- Android: `google-services.json` per flavor, `POST_NOTIFICATIONS`, the channel in `MainActivity`
- `supabase/README.md` §11 — arming a project, per environment

**The device round found two things no gate could (29/08/2026, owner, dev flavour on a real
handset + an emulator as the second caregiver).** Push itself worked first try, in both
directions, with the app killed. Both findings were about what happens AFTER it arrives:

1. **The notification wore a featureless white blob instead of the mark.** Not an emulator
   artifact — Android renders a notification's small icon as a **silhouette**, keeping the alpha
   channel and discarding the colours, so an app that declares none gets its full-colour launcher
   icon flattened. Fixed with a white-on-transparent glyph at five densities, generated from the
   same geometry as every other icon (`store/brand-icons.py`), plus
   `default_notification_color` so the silhouette carries the brand indigo instead of the
   system's grey. It reads from xhdpi up; at mdpi the day cells merge, which is accepted —
   `minSdk` is 26 and that density is not in this product's field.
2. **A receipt landed on an empty screen.** Tapping "Troca aprovada" opened Notificações on
   "Para você", which lists OPEN requests — and the request it was about had just been closed.
   The person taps a notice and arrives at *"nada pendente para você"*, which reads as the app
   having lost what it just told them. The tab is now chosen from the notice's TYPE
   (`PushRouting`): a receipt lands on **Histórico**, which is the notification list itself and
   therefore always holds the row that was tapped, while a request awaiting this person — and
   `auto_reminder`, the most deadline-bound notice the product sends — stays on "Para você".
   Enviadas was considered and rejected: it holds only requests this person OPENED, so it is
   empty for a notice about somebody else's request or about a day resolved automatically.

Both were invisible to every suite by construction: one is how the OS draws a payload, the other
is which tab a running app selects after a tap that no test can perform. **This is the argument
for the device round being part of the item and not a follow-up.**

**Left deliberately open**

- **Web push** — needs its own service worker, and `web/service-worker.js` is the PWA's tombstone
  that must keep unregistering itself. A design decision, not a flag. **Now T-62** (29/08/2026).
- **iOS** — T-40. The payload already carries its `apns` block.
- **Whether push should ever REPLACE the e-mail** — revisit with adoption data, not before.
  **Now F-59** (29/08/2026), whose first half is the measurement that data requires: the
  dispatcher currently returns its outcome to a trigger that discards it.

The three run in sequence in roadmap group 4: **T-40** (iOS) → **T-62** (web) → **F-59** (the
e-mail rebalance, which would be decided on a third of the evidence if it came first).
- **A second device round after the two fixes above** — the icon and the landing tab were found
  by looking, and only looking can confirm them. *(Done the same day: the icon reads as the mark
  and the receipt lands on Histórico; the revert flow was exercised end to end in both
  directions.)*

**Post-delivery defect — one telephone, two accounts (fixed 29/08/2026, same day)**

The owner could not enable push on the product's FIRST account while a second account on the
same handset had just enabled it fine. Production log, eight refusals in ninety seconds:

```
new row violates row-level security policy (USING expression) for table "push_subscriptions"
```

`registerPushToken` upserts on the token, because the row holding it may belong to another
profile — the same phone, a different sign-in. But the conflict branch of an upsert is a real
UPDATE, and `push_subscriptions_update_own`'s `USING` requires the row to be **yours already**.
It was not. The re-point the code's own comment promised was never possible, and the account's
age had nothing to do with it: it was simply the SECOND to ask for that handset's token. In the
opposite order the test account would have been the broken one.

**Three defects, one path.** The refusal above was only the visible one.

1. The upsert had no way to claim a token held by another profile. Fixed in the DATABASE —
   `push_subscriptions_claim_token`, a `BEFORE INSERT` that clears the previous holder so the
   INSERT never reaches the UPDATE branch. It had to be the database: `2.3.0+59` was already on
   handsets and cannot call an RPC that did not exist when it was compiled.
2. **`stop()` was a no-op after any restart.** `_token` was only set by `_register`, which
   `start()` skips when a row already exists — so signing out dropped nothing and left the
   handset pointed at the account that had just left. That stale row is what the next account
   collided with. `start()` now reads the token first, always.
3. **`hasPushSubscription` asked about the PROFILE, not the device.** A second handset saw
   "this profile has a device", never registered itself, and displayed `on` while the server had
   never heard of it. It is `isDeviceRegistered(profileId, token)` now.

**Why the gate was green through all of it.** `push_subscriptions.dart` asserted that a plain
INSERT of a held token is refused — true, and a statement the app never sends. The shape
production actually uses, the upsert, was never exercised. Exactly the `translateSaveError`
trap, six days later and in a different language: *a test that encodes a call the product does
not make is green about nothing.* The suite now drives the upsert, pins the trigger's blast
radius to the single row it may delete, and pins that re-registering your OWN device still takes
the UPDATE branch and keeps its `created_at`.

**The capability this grants, said out loud:** whoever presents a token claims that handset. One
family sharing one telephone is the ordinary case in this product, not the attack — and holding
the token IS being the device. It is strictly narrower than the alternative of loosening the
UPDATE policy, which a single WHERE-less statement could have used to sweep the whole registry.

---

### F-53 — Closed-alpha tester reward: permanent Premium for tester families — DELIVERED

| Field | Value |
|---|---|
| **Status** | `completed` — **01/09/2026**, the day the closed test ended. The grant itself is operator ops and the owner ran it in the console the same day |
| **Priority** | `high` |
| **Complexity** | `low` — and lower than recorded: by the time it came up for execution, F-58 had already reduced it to a decision |
| **Impact** | `medium` |
| **Roadmap** | Group 4 (Distribuição), first — it was coupled to the closed-alpha campaign, and closed with it |
| **Depends on** | **F-58** (delivered 18/08/2026) — the whole mechanism |
| **Delivered in** | **no build.** Nothing under `apps/` or `packages/` changed, so no version bump; a markdown-only change also runs no CI, by the design recorded in `CLAUDE.md` |

> **The promise** (WhatsApp, 11/08/2026, closed-alpha recruitment): *whoever joins the test gets
> Premium free, permanently, for their family — current and future paid features.* The item was
> recorded the same day the promise was published, before anything implemented it — the S-15
> lesson applied to a claim that lived in WhatsApp instead of a policy page.

**What the item turned out to be.** The record written on 11/08 planned an implementation:
`set_family_plan` plus a marker column so a grant could be told apart from a paying family, and
a check inside the billing webhook so the T-39 dunning path could not silently revoke the
reward. **None of that was built, because F-58 answered it better on 18/08** — the comp is its
own column (`families.comp_premium_at` + `comp_premium_note`) read by `is_premium()` ITSELF, so
it is orthogonal to `plan` and no billing writer can reach it. The webhook was never touched and
never needs to be. By 01/09 the item had shrunk to what F-58 had explicitly left to it: the
**semantics** — who the promise covers, and the procedure that keeps the answer auditable.

**The four questions the record asked, answered (owner, 01/09/2026):**

1. **Marking** — one note, character for character across the whole batch. The string the owner
   granted with is **`Closed Alpha Gift`**. A per-family free text would answer *"why is THIS
   family premium?"* and lose *"who else got this?"*; the shared string makes the cohort
   re-findable in both trails (the family's own `account_logs` and `operator_audit_logs`), and
   it is the join key between a family row and §12 of the runbook. It went out in English, which
   the language rule would not have chosen — the note renders in the family's own visible
   history — and it was left alone on purpose: `admin_set_comp` is idempotent in the strict
   sense (a repeated grant does *nothing*, note included), so rewording it would mean revoking
   and re-granting 17 families, writing 34 history entries to improve none of them. The lesson
   for the next batch is in §12: **the note is chosen once, at grant time.**
2. **Protection against billing downgrades** — answered **by construction**, not by a marker
   check. Pinned by the db-gate, which drives a billing-style downgrade against a comped family
   and asserts the entitlement holds.
3. **Matching testers to families, and who executes** — the console (`entrelares-console` →
   Famílias), **never SQL**. `admin_set_comp` sits behind the operator check *and* the S-10 sudo
   gate and writes both trails; a hand-run `UPDATE` has none of that, which is the exact risk
   F-58 exists to remove. The grant is idempotent, so re-running the batch is safe.
4. **Scope of "tester"** — the cutoff is **accounts created inside the window 11/08/2026 →
   01/09/2026 inclusive**. Not the Play tester list: someone who accepted the Console invitation
   and never signed up has no family to reward, and someone who signed up inside the window is
   exactly who *"quem entrar no teste"* addresses. The window is also checkable against
   `families.created_at`, so the cohort can be **re-derived instead of remembered**. Anyone
   arriving after 01/09/2026 is a normal user on the normal 30-day trial — written down so a
   late arrival is *answered* rather than argued.

**Executed 01/09/2026:** every family with `id` up to **17**, granted one by one in the console
under the note above. `families.id` is sequential, so the id boundary and the date cutoff name
the same set — the id is just the form the operator could act on, family by family, and it is
what §12 records as the re-derivation query.

**Nothing had to be built on the client either.** The T-53 rewrite had already ported the comp
into the Dart mirror (`computeIsPremium` / `describePlan` in `entrelares_core`, `compPremiumAt`
on the `Family` contract), and the copy a comped family sees is the promise almost verbatim:
**✨ Premium permanente — sem expiração** over **💙 Sua família tem Premium permanente — sem
expiração e sem cobrança. Aproveite!**, in PT and EN. The trial countdown disappears even mid-
trial, which is right: the family is premium for a reason that does not expire.

**What was found and deliberately NOT fixed (owner, 01/09/2026).** `computeBillingUi` reaches
the permanent-Premium block only when there is **no subscription row at all**. A comped family
that once subscribed and cancelled therefore still sees the OFFER — the product selling a
subscription to someone who already holds Premium forever, and on the Android build that is a
live Play purchase button. It is the record's own second bullet, arriving from the other side:
the *entitlement* is safe (the comp holds; the DB never wavers), only the copy is wrong. No
tester ever subscribed, so the state is unreachable for this cohort and the fix was declined as
speculative. The shape of it is written down in the runbook so the next person does not have to
re-derive it: pass the comp fact into `computeBillingUi` and return `premiumForever` **after**
the `active`/`overdue`/`scheduled` branches — a family that is actually paying must keep its
cancel button.

**Why this is a runbook section and not code.** The deliverable of an item whose mechanism
already exists is the *decision*, and a decision that is not written down is not a decision. §12
of [`supabase/README.md`](../../supabase/README.md) carries the cutoff, the canonical note, the
console-only rule, what the family sees, the accepted gap and the revoke semantics — so the
question "why is this family premium?" has an answer that outlives the session that granted it.

**Files affected**
- `supabase/README.md` — new **§12** (the cutoff, the grant procedure, the accepted UI gap,
  revoke semantics)
- `store/README.md` §5 — the closed test ends carrying this promise, and the closed test's own
  end date (01/09/2026), with the follow-on rollout pointed at T-59
- `backlog/technical.md` — T-59's `F-53 executed` checkbox ticked
- `backlog/features.md` → this record; `backlog/README.md` group 4 table

**Justification**
The reward is what made recruiting ~12 testers for 14 uninterrupted days realistic on a personal
network, and Play's production-access gate depended on those testers. The cost at this scale is
near zero; the liability of *not* honouring it would have been a broken public promise to the
app's first and most engaged users — the exact people the launch's word of mouth depends on.

---

### T-62 — Web push channel (Flutter Web, and the tombstone it must not touch) — DELIVERED (dark)

| Field | Value |
|---|---|
| **Status** | `completed` — **06/09/2026**. The code, the worker, the gates and the runbook ship together; the channel is **armed by console work**, not by a merge (see *What "dark" means* below) |
| **Priority** | `low` |
| **Complexity** | `medium` |
| **Impact** | `low` — unchanged, and for the reason recorded: on iOS web push needs the site on the Home Screen, so the audience is desktop and Android browsers |
| **Roadmap** | Group 4 (Distribuição). Taken **before T-40** rather than after it: the sequencing argument was about the AUDIENCE this buys, never about a dependency, and nothing in it waits on an iOS build |
| **Depends on** | **F-09** (29/08/2026) — and the prediction held: the dispatcher, the ten types, the per-recipient render, the token registry, `PushEnrollment`'s four states and the Notificações control needed **no change at all** |
| **Delivered in** | `2.4.0+61` |

**What the record predicted, and what was actually there**

The record said the client work was "one file". It is one file plus a service worker, a vendored
SDK and two rewrites of things nobody had looked at — and the difference is worth writing down,
because every one of the four was invisible from the Dart side.

1. **`firebase_core_web` does not bundle the Firebase JS SDK — it INJECTS it**, at runtime, with
   a dynamic `import("https://www.gstatic.com/firebasejs/12.18.0/firebase-app.js")`. This
   channel's CSP is `script-src 'self' …` and `web_channel_test` says in writing that no gstatic
   host may appear there: CanvasKit is served from our own origin (`--no-web-resources-cdn`)
   precisely so that executable code never comes from somebody else's. So web push, done the
   standard way, **collides with a documented decision of the channel**. The way out is the
   plugin's own: it injects nothing when `window.firebase_core` is already set. The four bundles
   are vendored under `web/firebasejs/12.18.0/` by `tool/vendor_firebase_js.py`, and the
   transport sets both globals before `Firebase.initializeApp`. **The CSP gained two
   `connect-src` hosts and nothing in `script-src`** — which is the whole shape of this item.
2. **`getToken` opens the permission prompt by itself.** The JS SDK runs
   `if (Notification.permission === 'default') await Notification.requestPermission()`, and
   `PushService.start` reads the token on EVERY authenticated session because on the native side
   that is free. Ported naively, the web channel would have asked every returning visitor for
   notification permission at page load, with no gesture and no context — spending on a boot the
   one prompt the product means to spend on a press, and breaking `PushService`'s own documented
   contract. `token()` reads the permission first; `web_channel_test` pins the guard's position.
3. **Passing `serviceWorkerScriptPath` would have replaced the app shell.** The FlutterFire layer
   calls `serviceWorker.register(path)` with no `{scope}`, which takes scope `/` — where
   Flutter's own worker lives. Passing `null` leaves the JS SDK to register the worker under its
   own scope, `/firebase-cloud-messaging-push-scope`. That is the answer to the record's "which
   worker, at which scope": **three workers, three scopes, no contention.** The tombstone is not
   a participant — nothing registers it but the browser's update check on a device that still
   carries the Blazor install, and its `activate` unregisters *itself* and touches no other
   registration. It was never in the way; it only made the standard recipe unusable.
4. **On the web the tap never reaches Dart.** `onMessageOpenedApp` has no web implementation at
   all and `getInitialMessage` is hard-coded to `null`: a notification shown by a service worker
   is clicked against the WORKER. So `firebase-messaging-sw.js` re-states `PushRouting` in
   JavaScript and opens `/notifications?tab=…&n=…` itself — the same URL `main.dart` builds, read
   by the same route. It is the **sixth** mirror this product keeps on purpose and the first that
   is not Dart↔Deno, with a suite of its own; the first run of that suite caught its own
   leniency, reporting the handler-order rule broken because it had counted a mention in a
   comment. Order there is load bearing and invisible: the SDK installs its own
   `notificationclick` listener that calls `stopImmediatePropagation()`, so ours has to be first
   or the tap closes the notification and goes nowhere.

**The weight, measured rather than argued** (the record asked for exactly this)

| | gzip |
|---|---|
| `main.dart.js` before | 1433 KB |
| `main.dart.js` after | **1443 KB** (+10 KB, +0,7 %) |
| the SDK the PAGE loads | 32 KB — **only for someone who enables push** |
| the SDK the WORKER loads | 22 KB — only on that person's first push |

The +10 KB is the Dart interop of `firebase_core`/`firebase_messaging`, which F-09 kept out of
the web bundle entirely (it was zero occurrences of `firebase` in `main.dart.js`; it is 25 now).
The 32 KB is not first-load weight at all: `initialize()` answers from `Notification.permission`
and three global lookups, and the SDK is imported lazily, the first time a token is actually
needed. **A visitor who never turns push on fetches none of it** — which is what keeps the
channel acceptance of 23/08/2026 intact rather than re-opened.

**What "dark" means, and why it is the honest shipping state**

The go-live needs a Firebase **Web app** and a VAPID key pair per project — console work, and
five public values rather than the one the record anticipated (the web has no
`google-services.json`, so `Firebase.initializeApp` takes explicit options). Until they exist
`Env.webPush.isConfigured` is false, `PushMessaging.supported` is false, and the control resolves
to `unsupported` **and says so in words**. Same fail-closed shape as `FCM_SERVICE_ACCOUNT`
server-side and `billing.store_enabled` client-side, and the same reason: a switch that does
nothing when pressed is worse than a sentence explaining why there is no switch.

The config lands in **two places** — `Env.prod.webPush` for the page, `FIREBASE_CONFIG` in the
worker, because a worker is started by the browser with no page to ask — and `web_channel_test`
compares them string by string, checks that all five values are present (a HALF-filled config
passes a "not empty" check and then fails at `getToken` complaining about an unrelated field) and
asserts the worker stays inert while `apiKey` is blank.

**Acceptance is still a human round**, as the record said: `web-e2e` drives a headless Chrome with
no notification permission and no service-worker lifetime, so it cannot prove a notification. The
procedure is `supabase/README.md` §11-bis.3, and its one non-obvious step is **close the tab** —
FCM does not show a notification while a client is visible, it forwards the message to the page.

**The one server-side change**, against a record that said "almost nothing": a `webpush` block in
`_shared/fcm.ts` carrying `notification.icon`. It is the browser's version of the F-09 Android
silhouette gotcha — with no icon the notification arrives as a generic bell instead of this
product. The path is **relative**, because `showNotification` resolves it against the service
worker's own URL, so one payload names the right origin on every environment and the sender never
learns a hostname it would then have to keep in sync. No `fcm_options.link`: the destination is a
product rule and it lives beside the rule it mirrors, and naming a link would hand the tap to the
SDK's own handler, which stops propagation.

**Files affected**
- `apps/entrelares_app/lib/services/push_messaging_web.dart` — the stub becomes real
- `apps/entrelares_app/web/firebase-messaging-sw.js` — new; the worker, its scope reasoning and
  the `PushRouting` mirror
- `apps/entrelares_app/web/firebasejs/12.18.0/` — new; the vendored SDK (four bundles)
- `apps/entrelares_app/tool/vendor_firebase_js.py` — new; the generator, which exits non-zero if
  any gstatic reference survives its rewrite
- `apps/entrelares_app/web/_headers` — two `connect-src` hosts, the worker's no-store rule, the
  pinned SDK's immutable rule
- `apps/entrelares_app/lib/env.dart` — `WebPushConfig`, per environment
- `apps/entrelares_app/test/web_channel_test.dart` — seven gates (vendoring, the version pin read
  out of the plugin itself, the CSP trade, the worker scope, the permission guard, the two-sided
  config, the cache rules)
- `packages/entrelares_core/test/mirrors/push_routing_worker_mirror_test.dart` — new; the sixth
  mirror
- `supabase/functions/_shared/fcm.ts` — the `webpush` block
- `supabase/README.md` — new **§11-bis**; `CLAUDE.md` — the Push row, the web-channel row, the
  mirror inventory and two gotchas

**Justification**
The web channel is a first-class channel of this product and was the only one that could not tell
a caregiver something happened while they were not looking. What the item was really blocked on
was never effort: it was a design decision about service workers on an origin that already had
two, and — as it turned out — three more traps that a green suite would have shipped without
noticing. Writing them down is most of the value here; the code is small.
