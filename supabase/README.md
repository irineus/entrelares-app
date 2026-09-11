# Supabase — QA & Production Deploy Runbook

**This is the source-of-truth checklist for deploying the backend** (database
migrations, Edge Functions, cron and Dashboard configuration) plus the app-publish
step that is coupled to it. Follow it top to bottom; nothing should be done from memory.

Everything is **per Supabase project**: run the whole runbook on **QA** first
(the CLI baseline + migrations are already applied on the existing environments),
validate with step 6, then repeat on **prod**.

---

## Deploy order & couplings — read this first

The six steps below are ordered because they depend on each other:

```
1. DB migrations  →  2. Edge Functions  →  3. Publish the app  →  4. Cron  →  5. Auth settings  →  6. Verify
```

> **Since T-29 (Phase 4), steps 1–3 are AUTOMATED by CI/CD**: pushing `dev` or
> `master` runs `supabase db push` (pending migrations), deploys both Edge
> Functions and publishes the app — in that exact order, aborting the app
> publish if the schema push fails. Steps 4–5 remain per-project Dashboard
> work, and step 6 remains the human verification. The manual procedures below
> are kept as **fallback** and for one-off environments.

> **Historical note:** the V007–V010 couplings below are from the Phase-4 CLI
> cutover and are long past on **both** environments (prod is at v1.6.1, well
> beyond V010). They are kept as a worked example of *why* migrations, functions
> and the app publish are ordered — not as live steps for the current promotion.

- **Migrations ↔ app are coupled (V010):** the OLD app build still sends the
  `is_urgent` field when creating swap requests; once V010 drops the column,
  creating a swap in the old app **fails**. The reverse also breaks (the new
  app needs V008 RLS / V009 RPCs). So: apply the migrations and **publish the
  new app immediately after** (steps 1 → 3, same maintenance window).
- **Migrations ↔ `send-swap-email` are coupled (V009/V010):** the deployed
  function copy must know the F-15 `invitation` type and must NOT expect the
  client's `isUrgent` — always redeploy it in the same window (step 2).
- **The cron needs the function** (step 4 after step 2), and the function's
  RPC comes from V007 (step 2 after step 1).

> **Account architecture (consolidated July 2026 — supersedes the old two-account
> split):** dev/QA and prod live under **ONE Supabase login** (`irineus@gmail.com`)
> in **two separate organizations** — dev/QA in a **Free** org, prod in a **Pro**
> org — so both are reachable from one Dashboard session with no extra per-project
> fee. CI-token isolation never depended on separate accounts: it comes from
> per-project service_role keys plus the two **named** account-level access tokens
> (`SUPABASE_ACCESS_TOKEN_DEV`/`_PROD`, see `deploy.yml`) — named tokens buy
> per-pipeline revocation and audit, not scoping. Dashboard steps below: same
> login, pick the right org/project. Watch two Free-org effects: dev
> **auto-pauses after 7 days idle** (`.github/workflows/keepalive-dev.yml` pings
> it twice weekly) and the MCP/OAuth connector is **scoped to one org per
> connection** (keep it on dev day-to-day; reconnect to the prod org for prod work).

**Per-environment values** used throughout the steps:

| Value | QA | Production |
|---|---|---|
| App URL (`APP_URL` secret, Site URL, Redirect URLs) | **`https://web.entrelares.app` — the same value as production, since 27/08/2026.** Dev has had NO web deployment since T-56 killed the Blazor QA site, so there is no dev-specific host left to name. It used to say `qa.entrelares.app`, which did not stop resolving when that deployment died — it became a ghost serving a stale build, which is worse than a dead host because it answers. Cost of the alignment, worth knowing before it confuses someone: a DEV invitation e-mail now points at the PRODUCTION web app, whose database has no such token, so it says "convite inválido" — dev invite testing happens inside the app, never from the inbox (§9-ter) | `https://web.entrelares.app` (F-54, Aug 2026 — the apex `entrelares.app` hosts the product **landing page**; e-mail/DNS records stay on the apex; the pre-rebrand `app.guardacompartilhada.com` 301-redirects here indefinitely) |
| `APP_ENVIRONMENT` secret | anything ≠ `Production` (e.g. `QA`) → notifications/e-mails prefixed `[Dev]` | `Production` (no prefix) |
| App publish trigger (step 3) | push/merge to the `dev` branch | push/merge to `master` |

---

## 0. Prerequisites — values to gather first

From the Supabase Dashboard of the **target** project:

| Value | Where |
|---|---|
| **`<project-ref>`** | Project Settings → General → **Reference ID** (also the subdomain of your API URL, `https://<project-ref>.supabase.co`) |
| **`<SERVICE_ROLE_KEY>`** | Project Settings → **API** → Project API keys → **`service_role`** (`secret`). ⚠️ Full-access key — never put it in client code or commit it |

Tools: **Supabase CLI** (`npx supabase …`, run from the repo root) and access to the
project's **SQL Editor**.

**CI secrets (one-time, GitHub → Settings → Secrets and variables → Actions).**
The T-29 pipeline steps need, besides the existing app/Cloudflare secrets:

| Secret | Value |
|---|---|
| `SUPABASE_ACCESS_TOKEN_DEV` / `_PROD` | two personal access tokens — supabase.com/dashboard/account/tokens, named e.g. `ci-qa` and `ci-prod`. ⚠️ Tokens are **account-scoped** (either can manage any project); two named tokens buy per-pipeline **revocation and audit**, not isolation |
| `SUPABASE_PROJECT_REF_DEV` / `_PROD` | each project's Reference ID (same as `<project-ref>` above) |
| `SUPABASE_DB_PASSWORD_DEV` / `_PROD` | each project's **database** password (Project Settings → Database) |

---

## 1. Database migrations — automated (T-29)

The pipeline runs `supabase db push` on every push to `dev`/`master`, applying
**only the pending** `supabase/migrations/*` files (tracked per environment in
`supabase_migrations.schema_migrations`) — nothing to do manually. Authoring
flow and conventions: [`database/README.md`](../database/README.md).

Check an environment's state:

```
npx supabase link --project-ref <ref>
npx supabase migration list
```

**Manual fallback** (CI unavailable / one-off environment): `npx supabase db push`
with the same link — it is idempotent, so running it locally and letting CI
re-run later is safe.

> ⚠️ **Before ANY local `db push`, check the link**: `cat supabase/.temp/project-ref`
> must show the DEV ref (`buroanotfjcgvbfmacuh`). The CLI link is sticky, invisible
> state that survives across sessions — on 2026-07-15 a stale PROD link (left by an
> old backup dump) sent a migration straight to production. Since the July-2026
> account consolidation one login reaches BOTH projects, which makes a stale
> link even easier to follow by accident — always check before pushing. CI is
> immune (explicit link + per-pipeline token every run).

> **History note:** the pre-CLI era (V001–V010, `database/migrations/VNNN__*`,
> tracked in `public.schema_migrations`) is frozen. Its CLI-era equivalent is
> the baseline migration `20260713000000_baseline_v1_4_0.sql`, marked as already
> applied on the existing environments during the T-29 cutover
> (`supabase migration repair --status applied 20260713000000`).

After each **production** deploy, refresh `database/snapshots/` with a **schema** dump:

```powershell
npx supabase link --project-ref <prod-ref>
npx supabase db dump --linked -f snapshot_YYYY-MM.sql   # asks for the DATABASE password
Move-Item snapshot_YYYY-MM.sql database\snapshots\
```

> ⚠️ **Windows path gotcha:** the CLI resolves `-f` against its own working
> directory, not necessarily your shell's — a relative path like
> `database/snapshots/…` fails ("cannot find the path") and a bare filename may
> land in `%USERPROFILE%`. Dump to a bare filename, then find it (repo root or
> home) and `Move-Item` it into place.

> **Privacy rule:** only the **schema** snapshot is committed. A **data** backup
> is worth taking too (the Free plan has no automatic backups) but must never
> enter git — `npx supabase db dump --linked --data-only -f data_YYYY-MM.dump.sql`;
> the `*.dump.sql` name is already gitignored. Verify the committed snapshot has
> no `COPY`/`INSERT` lines before pushing.

> **Full backup & disaster-recovery reference (T-19):** the cadence, the
> encryption/retention rules for PII dumps (row data **and** `auth.users`), and
> the step-by-step **restore procedure** live in the README's
> [Backup & Recovery](../README.md#backup--recovery) section. An optional
> ready-to-enable weekly encrypted backup workflow sits at
> [`.github/workflows/backup.yml`](../.github/workflows/backup.yml) (disabled by
> default). The Free plan has no PITR — upgrading to Pro is the recommended
> durability step before public availability.

---

## 2. Edge Functions — secrets, then deploy

**2.1 Secrets** (Dashboard → Edge Functions → Secrets). `SUPABASE_URL`,
`SUPABASE_PUBLISHABLE_KEYS` and `SUPABASE_SECRET_KEYS` are injected automatically
**once the new API keys exist on the project** (S-16, section 10.1) — the
functions read those and fail without them, so confirm they are listed here
before deploying. The legacy `SUPABASE_ANON_KEY`/`SUPABASE_SERVICE_ROLE_KEY` are
still injected but no longer read by any function. Set the rest:

| Secret | Value |
|---|---|
| `RESEND_API_KEY` | your Resend API key |
| `RESEND_FROM_EMAIL` | sender on the **verified** Resend domain — `noreply@entrelares.app` after the F-54 promotion-A cutover; until that cutover the verified domain (and thus the sender) is still `guardacompartilhada.com` (see 5.6 and 5.8) |
| `RESEND_FROM_NAME` | `Entrelares` |
| `APP_URL` | the environment's app URL (per-environment table above; **no trailing slash, must be public** — a `localhost` link in an e-mail is a spam signal) |
| `APP_ENVIRONMENT` | `QA` on QA, `Production` on prod (per-environment table above) |
| `ASAAS_API_KEY` | T-39: Asaas API key of **that** environment's account (sandbox on QA, the real account on prod) |
| `ASAAS_WEBHOOK_TOKEN` | T-39: shared token the `billing-webhook` demands in `asaas-access-token`; must match the value registered in the Asaas dashboard webhook. **Use a fresh value in prod** — never the sandbox one |
| `ASAAS_API_URL` | T-39: **sandbox is the code default, so production MUST opt in** with `https://api.asaas.com/v3`. Leaving it unset in prod silently keeps real families billing against the sandbox |

**2.2 Deploy — automated (T-29):** the pipeline deploys **all eight** functions on
every push, right after the migrations (see `deploy.yml`). Manual fallback:

```
npx supabase login
npx supabase link --project-ref <project-ref>
npx supabase functions deploy send-swap-email      --project-ref <project-ref>
npx supabase functions deploy auto-approve-expired --project-ref <project-ref>
npx supabase functions deploy register-invitee     --project-ref <project-ref>
npx supabase functions deploy elevate              --project-ref <project-ref>
npx supabase functions deploy purge-deleted        --project-ref <project-ref>
npx supabase functions deploy send-account-email   --project-ref <project-ref>
npx supabase functions deploy billing-webhook      --no-verify-jwt --project-ref <project-ref>
npx supabase functions deploy billing-checkout     --project-ref <project-ref>
```

> `billing-webhook` **must** carry `--no-verify-jwt`: Asaas calls it server-to-server
> with no Supabase JWT, and its own auth is the `asaas-access-token` shared secret.
> Deploying it without the flag makes every webhook 401 — payments confirm at the
> provider and the family never turns premium.

| Function | Purpose |
|---|---|
| `send-swap-email` | Transactional e-mails (Resend) for every workflow event, the F-24 `reminder`/`auto_approved` types, the F-15 `invitation` type; computes the F-20 priority tag at send time |
| `auto-approve-expired` | Cron worker (F-24): calls the `auto_approve_expired()` RPC (24 h reminders + 48 h auto-approval) and dispatches e-mails via `send-swap-email` |
| `register-invitee` | F-15 invite sign-up: `admin.createUser` + profile/family wiring for a user joining via an invitation link (first casualty if the JWT key is on ES256 — see S-16) |
| `elevate` | S-10 sudo elevation: opens the short-lived window the guarded destructive actions require. Two proofs since S-21 — the current password, or a one-time code mailed through `send-account-email`, which is the only door a Google session has |
| `purge-deleted` | S-11 cron worker: hard-deletes accounts (and families) past their 30-day grace. Also carries the retention/notice duties added since: `purge_old_notifications` (S-13, read notices > 6 months), **`purge_stale_invitations`** (S-15/A-4, never-accepted invitations > 30 days — what makes the invite e-mail's purge promise true) and **`billing_grace_warnings_due`** (S-15/B-3, warns admins by e-mail before the Premium grace expires; the RPC writes the in-app notice, the e-mail here is the best-effort twin) |
| `send-push-notification` | F-09: the push dispatcher. Fired by an AFTER INSERT trigger on `notifications` (pg_net, hence `--no-verify-jwt` and the secret key on `apikey`), so push, in-app and e-mail are three renderings of ONE event. Pushes ten types only — the rule is "push only what the recipient did not just do" — renders the copy per recipient from `_shared/push.ts` in that reader's language, and deletes the tokens FCM retires. **Fails closed and quiet on every branch**: no `FCM_SERVICE_ACCOUNT`, no device, or an unrenderable payload each answer 200 with a reason (arming: section 11) |
| `send-account-email` | S-11 account-lifecycle e-mails (deletion scheduled/cancelled, family-deletion consent); mirrors the F-20 priority tag in `America/Sao_Paulo`. S-15/B-3 added `premium_grace_ending` — the only type that e-mails ONLY the subject (a family admin), since billing is admin-only. S-21 added `elevation_code`, the odd one out: keyed by `userId` (the subject may have no profile yet), secret-key callers only (`elevate`), and the destination address is read from `auth.users` instead of trusted from the payload |

| `billing-webhook` | T-39: receives Asaas events (auth = the `ASAAS_WEBHOOK_TOKEN` shared secret in `asaas-access-token`, hence `--no-verify-jwt`). **Idempotent by the provider's event id** — a redelivery is recorded and ignored — and applies every effect through `set_family_plan`, adopting the subscription created by the payment link (`externalReference family:<id>`, link-id fallback) |
| `billing-checkout` | T-39: called with the **user's** JWT and admin-only (guard chain 401→403→409→503); creates the Asaas Payment Link (`RECURRENT`, `dueDateLimitDays` — the API rejects it without one) so payer data is typed only on the provider's PCI page, and handles `cancel` honouring the period already paid. Refuses everything while `billing.enabled` is false; gateway failures are audited as `CHECKOUT_ERROR` in the ledger |

> An outdated `send-swap-email` used to silently build **0 e-mails** for unknown
> types — the historical gotcha the automated redeploy-on-every-push eliminates.

---

## 3. Publish the app — automated

The same pipeline publishes the app to Cloudflare Pages **after** migrations and
functions succeed (per-environment table above: `dev` = QA, `master` = prod), so
schema and app always ship together. Clients pick the new version up on the next
visit (the service worker auto-activates new deployments). Details: root
[`README.md`](../README.md) → Deployment.

---

## 4. Schedule the `auto-approve-expired` cron (F-24)

Per project, after step 2 (the function must exist).

**4.1** Dashboard → **Database → Extensions** → enable **`pg_net`**.

**4.2** Dashboard → **Integrations → Cron** → enable the **`pg_cron`** extension.

> **S-16 — a new environment skips straight to the new-key form.** The commands
> in 4.3/4.4/4.5 below are the LEGACY shape (`Authorization: Bearer` + the
> `service_role` JWT), kept because that is what the existing projects still run.
> A project set up from scratch — or one already migrated — stores the **secret
> key** in Vault and sends it on the **`apikey`** header instead: see
> [section 10.3](#103-migrar-os-crons-para-o-header-apikey). The new keys are not
> JWTs and are rejected on `Authorization`.

**4.3 Store the service-role key in Vault** (so the key is not sitting in
plaintext inside the cron command). In the SQL Editor, paste your
`<SERVICE_ROLE_KEY>` from step 0:
```sql
select vault.create_secret('<SERVICE_ROLE_KEY>', 'service_role_key');
```
Confirm it exists (does not print the secret):
```sql
select name from vault.secrets where name = 'service_role_key';
```

**4.4 Create the job** — Cron → **Jobs → Create Job**:
- **Name:** `auto-approve-expired-hourly`
- **Schedule:** `0 * * * *` (top of every hour)
- **Command:** use exactly this (⚠️ **not** the Dashboard's default — see the gotcha):
  ```sql
  select net.http_post(
    url := 'https://<project-ref>.supabase.co/functions/v1/auto-approve-expired',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  ```

> **⚠️ Gotcha (this cost us a debugging session).** If you accept the Dashboard's
> generated command it comes as `headers := '{}'` and `timeout_milliseconds := 1000`,
> and it **fails silently**: an empty-`headers` call carries no credential at all,
> so it is refused — the cron shows a "Last Run" but nothing happens. **Always**
> include the key header (via the Vault secret above) and a real timeout
> (≥ 30 000 ms).
>
> *S-16 changed where the refusal comes from, not the lesson.* It used to be the
> platform's `verify_jwt` gate answering **401 before the function ran**, which is
> why no function logs appeared. These functions now run with the gate off and
> check the key themselves, so an unauthorized cron call **does** show up in the
> function logs (`refused — caller did not present the secret key`) — a much
> faster diagnosis than the silent version. What still breaks it silently is
> sending the key on the wrong header for its format.

### 4.5 Schedule the `purge-deleted` cron (S-11)

Same mechanics as 4.4 — a daily job that hard-deletes accounts past their
30-day grace (and, from PR2, families). The function has `verify_jwt` on, so
the `Authorization: Bearer <service_role_key>` header (Vault secret from 4.3)
is mandatory, exactly like the gotcha above.

- **Name:** `purge-deleted-daily`
- **Schedule:** `0 4 * * *` (daily, 04:00 UTC — off-peak; grace is measured in
  days, so hourly is unnecessary)
- **Command:** as in 4.4 but with
  `url := 'https://<project-ref>.supabase.co/functions/v1/purge-deleted'`.

---

## 5. Authentication settings & e-mail templates (F-15 sign-up)

Once per project, in the Dashboard → **Authentication**. Without these the
self-service sign-up flow does not work as designed.

**5.1 Turn on e-mail confirmation.**
Authentication → **Sign In / Providers** (older UI: "Providers") → click the **Email**
provider → toggle **"Confirm email" = ON** → Save.
*Why:* with this ON, `SignUp` does not create a logged-in session; the user receives a
confirmation link and **cannot sign in before clicking it** (login returns "Email not
confirmed", which the app translates). E-mail is the workflow notification channel
(F-10/F-24), so it must be verified at the door. The register page already assumes this
mode — after sign-up it shows "📧 Confirme seu e-mail" instead of logging in.

**5.2 Minimum password length = 8.**
Same **Email** provider panel → **"Minimum password length"** → change from `6` (default)
to `8`.
*Why:* the register form validates 8+ client-side, but client validation is UX only — if
the server still accepts 6, a direct API call bypasses the rule. Server and client must
agree.

**5.3 Site URL and Redirect URLs.**
Authentication → **URL Configuration**:
- **Site URL** = the environment's app URL (per-environment table above).
- **Redirect URLs**: add `<app URL>/login` (wildcards work: `<app URL>/**` covers all).

*Why:* `SignUpAsync` **and** `SendPasswordResetAsync` send `RedirectTo = <BaseUri>/login`
— where the browser lands after the confirmation / recovery click. GoTrue **only honours
RedirectTo if it is on this allow-list** (open-redirect protection); otherwise it silently
falls back to the Site URL.

That fallback is not theoretical: found in the pre-production round of Aug 2026, the reset
call passed **no** `RedirectTo` at all, so every environment used its Site URL — and DEV's
was still a `https://localhost:7072` from the pre-deploy days. A reset asked for on the QA
app mailed a link back to a machine the reader does not have. The code now states the
redirect (from `BaseUri`, so local, QA and production each point at themselves), but the
allow-list is the other half: **a project whose Redirect URLs do not include its own app
URL silently reverts to the same bug**, with no error anywhere. Check both projects after
any URL change:
- dev/QA → https://supabase.com/dashboard/project/buroanotfjcgvbfmacuh/auth/url-configuration
- prod → https://supabase.com/dashboard/project/jptqbwfziyzlhlmoekzu/auth/url-configuration

**5.4 PT-BR templates for the auth e-mails.**

> **Superseded by 5.7 once the Send Email Hook is enabled** (U-13, Aug 2026). While
> the hook is off, GoTrue sends these templates and this section applies as written —
> that is why it is kept. Once 5.7 is done, GoTrue stops sending and these templates
> become dead configuration: the bodies below live in `send-auth-email` instead, in
> **both** languages. Do not edit both places; edit the function.
>
> **"Dead" is not "harmless" — swept 12/08/2026 (F-54).** These templates are the BACK-OUT
> path of a critical flow, and they live ONLY in the Dashboard: unversioned, in two projects,
> invisible to every `grep`. The rebrand went through the whole codebase, both repos and the
> whole infrastructure, and left them saying *"Redefinição de senha — Guarda Compartilhada"* —
> so the one scenario where they get used (the hook is down, someone is locked out and asks
> for a password reset) is exactly the scenario where the brand would be wrong. Settled:
> **PROD keeps hand-maintained PT-BR templates** (a real person receives that e-mail, so it is
> worth the upkeep) and **DEV is reset to the Supabase default** (nobody real receives it; one
> less thing to rot). **Any brand, domain or sender change must sweep the prod templates in the
> same delivery** — all six of them (Confirm signup, Invite user, Magic Link, Change Email
> Address, Reset Password, Reauthentication), subject line included.

Authentication → **Emails** (older UI: "Email Templates") — the defaults are in
English; replace **both** tabs below so they match the app's PT-BR e-mails. In both,
keep `{{ .ConfirmationURL }}` exactly as is (double braces) — it becomes the action
link.

**Tab "Confirm signup":**

- **Subject heading:** `Confirme seu cadastro — Entrelares`
- **Message body** (the link honours the app's `RedirectTo=/login`):

```html
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Confirme seu cadastro</title>
</head>
<body style="margin:0;padding:0;background:#f4f4f5;font-family:system-ui,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0">
    <tr><td align="center" style="padding:32px 16px;">
      <table width="100%" style="max-width:480px;background:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08);">
        <tr><td style="background:#212529;padding:20px 24px;">
          <p style="margin:0;color:#ffffff;font-size:18px;font-weight:700;">👨‍👩‍👧 Entrelares</p>
        </td></tr>
        <tr><td style="padding:28px 24px;">
          <h2 style="margin:0 0 16px;font-size:20px;color:#212529;">Falta só um passo! ✅</h2>
          <p style="margin:0 0 12px;color:#374151;line-height:1.6;">Sua conta foi criada. Para ativá-la, confirme que este e-mail é seu tocando no botão abaixo:</p>
          <p style="margin:20px 0;">
            <a href="{{ .ConfirmationURL }}" style="display:inline-block;background:#212529;color:#ffffff;padding:12px 24px;border-radius:8px;text-decoration:none;font-weight:600;">Confirmar meu e-mail</a>
          </p>
          <p style="margin:0 0 12px;color:#374151;line-height:1.6;">Depois de confirmar, é só fazer o login no aplicativo.</p>
          <p style="margin:16px 0 0;font-size:12px;color:#9ca3af;">Se o botão não funcionar, copie e cole este link no navegador:<br/><span style="word-break:break-all;color:#6b7280;">{{ .ConfirmationURL }}</span></p>
          <p style="margin:16px 0 0;font-size:12px;color:#9ca3af;">Se você não criou esta conta, ignore este e-mail — nada será ativado sem a confirmação.</p>
          <p style="margin:24px 0 0;font-size:12px;color:#9ca3af;">Esta é uma mensagem automática. Não responda a este e-mail.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>
```

**Tab "Reset Password":**

- **Subject heading:** `Redefinição de senha — Entrelares`
- **Message body** (the link carries `type=recovery`, which the app intercepts and
  routes to `/update-password`):

```html
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Redefinição de senha</title>
</head>
<body style="margin:0;padding:0;background:#f4f4f5;font-family:system-ui,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0">
    <tr><td align="center" style="padding:32px 16px;">
      <table width="100%" style="max-width:480px;background:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08);">
        <tr><td style="background:#212529;padding:20px 24px;">
          <p style="margin:0;color:#ffffff;font-size:18px;font-weight:700;">👨‍👩‍👧 Entrelares</p>
        </td></tr>
        <tr><td style="padding:28px 24px;">
          <h2 style="margin:0 0 16px;font-size:20px;color:#212529;">Vamos redefinir sua senha 🔑</h2>
          <p style="margin:0 0 12px;color:#374151;line-height:1.6;">Recebemos um pedido para redefinir a senha da sua conta. Toque no botão abaixo para criar uma nova senha:</p>
          <p style="margin:20px 0;">
            <a href="{{ .ConfirmationURL }}" style="display:inline-block;background:#212529;color:#ffffff;padding:12px 24px;border-radius:8px;text-decoration:none;font-weight:600;">Redefinir minha senha</a>
          </p>
          <p style="margin:16px 0 0;font-size:12px;color:#9ca3af;">Se o botão não funcionar, copie e cole este link no navegador:<br/><span style="word-break:break-all;color:#6b7280;">{{ .ConfirmationURL }}</span></p>
          <p style="margin:16px 0 0;font-size:12px;color:#9ca3af;">Se você não pediu a redefinição, ignore este e-mail — sua senha continuará a mesma.</p>
          <p style="margin:24px 0 0;font-size:12px;color:#9ca3af;">Esta é uma mensagem automática. Não responda a este e-mail.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>
```

**5.5 SMTP — know the built-in limit; use Resend in production.**
The confirmation e-mail is sent by **GoTrue itself, NOT by `send-swap-email`/Resend**.
Two consequences:

- **⚠️ Built-in SMTP rate limit:** Supabase's default SMTP allows only a handful of
  auth e-mails per hour (~2–4). Several sign-ups in a row and e-mails silently stop
  arriving — that is the limit, not a bug.
- **Custom SMTP via Resend** (**recommended for prod**, optional on QA):
  Authentication → **SMTP Settings** (older UI: Project Settings → Auth → SMTP) →
  enable Custom SMTP with: host `smtp.resend.com`, port `465`, username `resend`,
  password = the `RESEND_API_KEY`, sender = the same `RESEND_FROM_EMAIL`/`RESEND_FROM_NAME`
  used by the Edge Function. Auth e-mails then leave through your Resend account —
  no built-in limit, consistent sender across all app e-mails.
  **Status (July 2026): DONE on the DEV project and verified working (DMARC PASS,
  inbox delivery).** The F-54 promotion-A cutover REPLACES the Resend domain with
  `entrelares.app` (one domain on the Free plan — see 5.8); the record below describes
  the original setup and stays the template for the new zone. DNS on
  `guardacompartilhada.com` (Cloudflare) is live: SPF on the
  root and `send.` subdomain, DKIM (`resend._domainkey`), DMARC (`_dmarc`, `p=none`,
  `rua=mailto:irineus@gmail.com`). PROD is a separate project (own org) — nothing
  propagates: repeat this setup there at promotion (section 7), with a separate
  Resend API key. After a few weeks of clean DMARC reports, harden `_dmarc` from
  `p=none` to `p=quarantine` (edit the existing TXT in Cloudflare). Also raise the
  auth e-mail rate limit (Authentication → Rate Limits) — ~30/h is comfortable with
  custom SMTP.
- **⚠️ The Resend allowance is per ACCOUNT, and dev shares it with prod.** One team,
  one verified domain, six API keys (`guardacompartilhada-dev/-prod`,
  `supabase-smtp-dev/-prod`, plus the landing worker) — all drawing on the same
  **100 e-mails/day** of the free plan. So DEV traffic can return 429 to PRODUCTION,
  and because `supabase-smtp-prod` is the GoTrue sender, the casualty is a sign-up
  confirmation or a password reset: the user simply cannot get in, and nothing
  surfaces the failure. **T-49** removed the largest source — the test suites, which
  were ~86 e-mails/day, 100% of the consumption — by suppressing the Resend call for
  `@resend.dev` recipients inside the Edge Functions (`functions/_shared/mail.ts`).
  **Still open, as a configuration step:** the ~12/day of GoTrue auth e-mails on the
  DEV project go out over the custom SMTP above and never touch that code. To take
  DEV to zero, point its SMTP at a capture sandbox (Mailtrap/Ethereal) instead of
  `smtp.resend.com` — the messages stay readable for QA and prod keeps the whole
  allowance. Do NOT fall back to Supabase's built-in SMTP: ~2–4/hour breaks the pack.
  After that, an 80%-quota warning from Resend means real traffic (or a runaway
  send loop) and is worth investigating instead of ignoring.

**5.6 Deliverability — keep e-mails out of spam.**
During F-15 testing the invitation e-mail landed in the recipient's spam folder. The
levers, in order of impact:

- **Verified sending domain in Resend** (resend.com → Domains): add the domain and
  create the DNS records Resend provides — **SPF** and **DKIM** both green. Add a
  **DMARC** record too (`_dmarc` TXT → `v=DMARC1; p=none; rua=mailto:<your-email>`).
  `RESEND_FROM_EMAIL` must be an address **on that verified domain** (never
  `onboarding@resend.dev` in prod).
- **`APP_URL` must be a public URL** — e-mails embed links built from it.
- **Custom SMTP (5.5)** routes the auth e-mails through the same verified domain —
  one consistent sender reputation for everything the app sends.
- A **new domain with low volume** starts with neutral reputation: first e-mails to a
  given provider may still be flagged; asking the recipient to mark "Not spam" trains
  that inbox for all subsequent workflow e-mails.

**5.7 Send Email Hook — the auth e-mails in the READER's language.** *(U-13, Aug 2026)*

*Why:* GoTrue's templates are **one per project** — one body, one language, every
reader. An English tester who asked for a password reset got a Portuguese e-mail while
every screen around them was in English. There is no way to branch inside GoTrue, so
the message has to leave through us: the hook makes GoTrue hand us the user, the action
type and the token, and `send-auth-email` renders it in the recipient's language and
sends it through the same Resend account as every other e-mail here.

> **⚠️ There is no fallback.** With the hook enabled, GoTrue does not send these
> e-mails itself. If the URL is wrong, the function is broken or the secret is wrong,
> **nobody can confirm a sign-up and nobody can recover a password.** That is why the
> probe (step 4) comes BEFORE the toggle (step 5). To back out at any time: turn the
> toggle off — GoTrue immediately resumes using the 5.4 templates.
>
> **This went wrong on the first attempt (Aug 2026), and the symptom named nothing.**
> The hook was pointed at the APP's URL instead of the function's. A static site
> answers `405` to a POST, so GoTrue reported
> `500: Unexpected status code returned from hook: 405` and every sign-up and password
> reset on QA failed — while the Edge Function logs stayed **empty**, because a 405
> from the gateway means the function never ran. If auth e-mails stop and the function
> shows no invocations at all, the URL is wrong; that is the first thing to check, and
> the probe below is what would have caught it.

Per project (dev first, prod at promotion). The URLs below are **literal — copy them,
do not retype a placeholder**; the whole failure above was one wrong URL.

1. **The function must exist first.** CI deploys it on every push (`deploy.yml`
   deploys `send-auth-email --no-verify-jwt`). Confirm the row **send-auth-email** is
   listed:
   - dev → https://supabase.com/dashboard/project/buroanotfjcgvbfmacuh/functions
   - prod → https://supabase.com/dashboard/project/jptqbwfziyzlhlmoekzu/functions

   If it is missing, the hook has nothing to call — stop here and let a deploy run.

2. **Set the function's secret FIRST, before the hook exists.** The order is
   deliberate: a hook that is live before its secret refuses every e-mail.

   Open *Settings → Edge Functions → Secrets*:
   - dev → https://supabase.com/dashboard/project/buroanotfjcgvbfmacuh/settings/functions
   - prod → https://supabase.com/dashboard/project/jptqbwfziyzlhlmoekzu/settings/functions

   You cannot fill the value yet — it is created with the hook in step 3 — so this step
   is just to know where the screen is. Come back here right after step 3.

   Optional, and only on **dev**: add `MAIL_ENV_PREFIX` = `[Dev] ` (with the trailing
   space) so a QA e-mail is recognisable in the inbox. Leave it unset in production.

3. **Create the hook — but leave it OFF.**
   - dev → https://supabase.com/dashboard/project/buroanotfjcgvbfmacuh/auth/hooks
   - prod → https://supabase.com/dashboard/project/jptqbwfziyzlhlmoekzu/auth/hooks

   **Add hook** → type **Send Email** → **HTTPS**.

   > **⚠️ The URL to paste is NOT the address of the page you are standing on.** The
   > line above is where you NAVIGATE; the value below is what you TYPE INTO the URL
   > field. In Aug 2026 the hook was saved with
   > `https://supabase.com/dashboard/project/<ref>/auth/hooks` — the Dashboard's own
   > address, copied from the browser bar — and `supabase.com` answers `405` to a POST,
   > so every sign-up and password reset on QA failed for two hours. Two `https://…`
   > lines next to each other in a runbook is all it takes.

   The value for the **URL** field, copied exactly:

   - dev → `https://buroanotfjcgvbfmacuh.supabase.co/functions/v1/send-auth-email`
   - prod → `https://jptqbwfziyzlhlmoekzu.supabase.co/functions/v1/send-auth-email`

   It must contain `.supabase.co/functions/v1/send-auth-email`. If what you pasted
   contains `supabase.com/dashboard`, `pages.dev` or `web.entrelares.app`, it
   is not the function.

   Save. The Dashboard shows a **secret** shaped `v1,whsec_…`. **Copy it now** — it is
   the only authorization the function has, and the screen may not show it again.

   Now go back to step 2's screen and add the secret:
   - Name: `SEND_EMAIL_HOOK_SECRET`
   - Value: the whole `v1,whsec_…` string, pasted unchanged.

   The function reads it at request time, so it takes effect immediately — no redeploy.

4. **Read the URI back from the hook screen.** This is the check that matters, and it
   is the one that is easy to skip: reopen the hook you just saved and confirm the URI
   field shows what you typed. A Dashboard edit that was never saved looks exactly like
   a saved one until you reload the panel.

   **A `curl` against the function does NOT verify this** — it proves the function is
   up, which is a different fact. In Aug 2026 the hook was left pointing at the app,
   the operator probed the correct function URL, got the expected `401`, and re-enabled
   a hook that was still misrouted; QA stayed broken for two more hours. The only
   things that see the hook's own configuration are this screen and a real e-mail.

   With that confirmed, probe the function itself from PowerShell (substitute the
   dev/prod ref):

   ```powershell
   curl.exe -s -o NUL -w "%{http_code}`n" -X POST "https://buroanotfjcgvbfmacuh.supabase.co/functions/v1/send-auth-email" -H "Content-Type: application/json" -d "{}"
   ```

   Expected: **`401`**. What the other answers mean:
   - **`405`** — the URL is the app, not the function. Fix step 3 before going on.
   - **`404`** — wrong path, or the function was never deployed (step 1).
   - **`200`** — stop. The function would mail an account-recovery link to whatever
     address a caller names; this is exactly what `EdgeFunctionAuthTests` fails on.

   Then check the function's logs are reachable, because they are your only diagnosis
   once the hook is live:
   https://supabase.com/dashboard/project/buroanotfjcgvbfmacuh/functions/send-auth-email/logs

5. **Enable the hook** (step 3's page): toggle it **on**. If anything goes wrong from
   here, this toggle is the undo — turning it off restores the 5.4 templates instantly,
   and there is no reason to debug with sign-up broken.

6. **Confirm with a real e-mail.** Ask for a password reset for an account you own,
   from the app:
   - the subject is `Redefina sua senha` (or `Reset your password` if that account
     reads the app in English). If it is still the old
     `Redefinição de senha — Entrelares` (the 5.4 template subject), the hook is not firing and GoTrue
     is using the 5.4 templates;
   - the button's link points at `…supabase.co/auth/v1/verify?…` and its `redirect_to=`
     is the app URL from 5.3, never `localhost`.

   **If no e-mail arrives**, in this order: the function's logs (link in step 4) — an
   empty log means GoTrue never reached it, i.e. the URL (step 3); a
   `SEND_EMAIL_HOOK_SECRET is not configured` line means the secret (step 3); an
   `Auth Logs` entry reading `Unexpected status code returned from hook` names the
   status the URL returned.

7. **After it works, leave 5.4 alone — but do not forget it exists.** The templates stay in
   the Dashboard as the back-out path for the toggle; they are no longer what anybody
   receives, which is precisely why a brand change sails past them (see the sweep note in
   5.4). On PROD they are hand-maintained in PT-BR; on DEV they are the Supabase default.

**5.8 F-54 sender cutover — `guardacompartilhada.com` → `entrelares.app`** — **EXECUTED
12/08/2026** at the promotion-A sitting; kept here as the record of what was done and as
the pattern for any future sender migration. The Resend Free plan holds ONE domain and the old
one is production's live sender, so the migration cannot be pre-staged: e-mails sent
inside the window are silently lost (the app sends fire-and-forget). Sequence, all in one
sitting: (1) Resend → Domains → delete `guardacompartilhada.com` → add `entrelares.app`
(region `sa-east-1`, sending only, tracking off) → paste the DKIM/SPF/MX records it
returns into the `entrelares.app` Cloudflare zone, plus the `_dmarc` TXT with the same
policy the old domain used → Verify (Cloudflare is authoritative — minutes). **(1b)
Recreate EVERY API key that predates the new domain** — a Resend key can be bound to a
single domain, is not editable, and the binding is invisible in the key list; a bound key
starts refusing everything the moment its domain is deleted (see the (6) note below).
Create one key per consumer, named after what it serves and not after the domain
(`entrelares-prod`, `entrelares-dev`, `entrelares-smtp-prod`, `entrelares-smtp-dev`, the
landing worker's), each with *Sending access* on `entrelares.app`, and paste each into its
place BEFORE step (6). (2) Flip
`RESEND_FROM_EMAIL` to `noreply@entrelares.app` on BOTH Supabase projects (no redeploy
needed). (3) GoTrue on both projects: SMTP sender → `noreply@entrelares.app`; on PROD also
Site URL → `https://web.entrelares.app` (5.3). (4) Asaas: add `web.entrelares.app` to the
registered site/callback domains (section 9 prerequisite — without it the hosted checkout
refuses the new callback URLs). (5) Cloudflare: turn on the old domain's 301s (apex and
`app.` → the new equivalents; the old domain keeps redirecting and receiving e-mail
aliases indefinitely). (6) Human verification on the new domain: sign-up confirmation AND
password reset end to end — the auth-link round trip is the class of defect no suite
reaches. Zero-downtime alternative if ever needed again: Resend Pro for one month
(US$ 20) verifies both domains in parallel.

*What step (1b) costs when it is missed — measured, 12/08/2026.* Step (6) failed on the
first try: the password reset came back with the app's generic "Não foi possível enviar o
e-mail de recuperação", and the function log said
`Resend rejected the message (400): "The associated domain with your API key is not
verified. Please, create a new API key with full access or with a verified domain."` The
domain was verified — the KEY (`guardacompartilhada-prod`, issued in June against the old
domain) was the thing that was not. Note the blast radius: GoTrue answered **500 on
`/auth/v1/recover`**, so it was not one e-mail missing, it was password recovery and sign-up
confirmation both down for every user until the key was replaced. Recreating the key and
saving it as `RESEND_API_KEY` fixed it with no redeploy — the function reads the secret per
invocation. **The diagnosis lives in the Edge Function logs, not in Auth**, which is where
the hook moved it (see the auth-e-mail note in `CLAUDE.md`'s gotchas).

*What the cutover left behind, and what step (2) is really protecting you from:* the three
sending functions read `RESEND_FROM_EMAIL` with a literal fallback in the code, and until
`1.8.5` that fallback was `noreply@guardacompartilhada.com` — an address on a domain that
step (1) had just DELETED. A project missing the secret would therefore send from a domain
Resend no longer knows, and the send fails with nothing on screen: the app dispatches
fire-and-forget, so the casualty is a sign-up confirmation or a password reset that simply
never arrives. The fallback is now `noreply@entrelares.app`, which makes step (2) a
configuration detail again instead of a single point of silent failure. The lesson
generalizes to any provider migration: **a literal default is only harmless while the thing
it names still exists** — flip it in the same delivery that retires what it points at.

---

## 6. Verify the deploy

**6.1 Database & cron:**
```sql
-- CLI migrations landed (this is the CLI's tracking table — the legacy
-- public.schema_migrations is frozen at the V001–V010 baseline, do NOT use it here)
select version, name from supabase_migrations.schema_migrations order by version;
-- cron's HTTP calls should be 200, not 401
select id, status_code, error_msg, created from net._http_response order by id desc limit 5;
-- job run history
select jobid, status, return_message, start_time from cron.job_run_details order by start_time desc limit 5;
```
**Edge Functions → `auto-approve-expired` → Logs** should show a new entry each hour
(`rpc processed N …`).

**6.2 Workflow smoke test** (validates the V008 RLS + V010 + the new app build):
signed in as a normal parent, the calendar loads, a swap request can be created
(would fail against a stale app/function after V010) and approved by the other
side, and the priority tag appears on the Notifications card. The app version in
the Login footer must read the deployed version.

**6.3 F-15 sign-up smoke test** (validates V009 + step 5 end to end): open
`/register`, create a throwaway account → the "Confirme seu e-mail" screen appears
and the PT-BR confirmation e-mail arrives → click the link → sign in → the Família
page shows the new one-member family → send an invite to a second throwaway e-mail
→ the invitation e-mail (Resend) arrives with a working `/register?invite=…` link.
Clean up the test family afterwards (delete the two auth users in Authentication →
Users; their profiles/family cascade is manual — remove via SQL).

**6.4 Security advisors (S-12, periodic):** Dashboard → **Advisors → Security** —
review after any migration that touches tables, policies or functions (and at
least at every prod promotion). Expected steady state: no errors about RLS
disabled or anon-exposed tables; new warnings become backlog items. The
"anon reads nothing" invariant is also locked in CI by
`RlsHardeningTests.AnonKey_WithoutSession_ReadsNothingFromAnyTable`.

---

## 7. Prod-promotion checklist (dev → master)

Everything CI does NOT do — one pass through this list at every promotion,
besides the sections above. Consolidated July 2026 (desktop-session handoff):

1. **S-15: move `policy.enforce_from` to *promotion date + 15 days*** — a one-line
   corrective migration, PLUS the same value in `Helpers/PolicyVersions.EnforceFrom`,
   **in the same delivery**. It currently ships as a deliberately loose `2026-09-30`:
   the 15-day notice the legal review requires exists so the subject can READ the new
   text before losing access, and they can only do that once it is in PRODUCTION —
   counting from the QA merge would burn the whole window while the text is invisible
   to the people it binds. Until the promotion the gate only warns, which is correct.
   `ReconsentGateTests.EnforceFromConstant_MatchesServerSetting` turns the half-done
   version of this into a red gate instead of a live lockout, so moving only one of
   the two fails CI.
2. **Check prod's migration state** against `supabase/migrations/`, BEFORE merging to
   `master`. The drift left by the old stale-CLI-link incident was **verified gone on
   01/08/2026**: prod's applied set was an exact PREFIX of the repo's — no prod-only rows,
   no gaps — so the delta is just the unapplied tail and the CI `db push` runs clean.
   Keep checking anyway (`list_migrations` via the Supabase MCP on the PROD org, or the
   Dashboard): what makes this step cheap is that a mismatch here fails the prod `db push`
   AFTER the gate has gone green, i.e. with the deploy already in motion.
3. **Confirm prod's API keys (S-16)** — BEFORE merging to `master`. The Edge
   Functions read `SUPABASE_SECRET_KEYS`/`SUPABASE_PUBLISHABLE_KEYS` and **fail
   without them**, so the publishable/secret pair must EXIST on the prod project
   before the promotion redeploys the functions there — **section 10.1**, plus the
   matching GitHub secrets (10.2) and the cron header migration (10.3). While prod
   still holds a legacy key anywhere, also check Dashboard → **JWT Keys** that
   **HS256 is *Current*** (roll back if Supabase auto-promoted ES256 — Standby the
   ES256 key → Rotate), because ES256 is exactly what invalidates the legacy keys:
   GoTrue answers `unrecognized JWT kid <nil> for algorithm ES256` and invite
   sign-ups break first (`register-invitee`'s `admin.createUser`). Once nothing
   legacy remains, that rollback stops being needed and ES256 becomes step 10.5.
4. **Custom SMTP via Resend on the prod project** (section 5.5 — separate
   account, nothing propagates; use a separate Resend API key).
5. **Auth e-mail templates in PT-BR on prod** (sections 5.4/5.6 — the generic
   link-only defaults score badly with spam filters). **And then the Send Email
   Hook (section 5.7)**, which is what makes those e-mails follow the reader's
   language; it is per-project and its secret does not propagate, so prod needs
   its own. Do the templates anyway: they are the back-out path if the hook has
   to be switched off.
6. **Verify "Secure email change" is ON** (double confirmation on the old AND
   new address) — the S-10 design leans on it for the e-mail change path.
   Check the auth rate limits while there (section 5.5).
7. **Crons on prod** (section 4): `auto-approve-expired-hourly` and
   `purge-deleted-daily` are per-project — create them on prod with the prod
   ref URL (pg_cron + pg_net + Vault secret first, sections 4.1–4.3).
8. **Backup (T-19) goes live only on `master`**: create the private R2 bucket
   `guarda-backups` + a bucket-scoped token, add the 4 secrets
   (`BACKUP_PASSPHRASE` — keep an offline copy, it is the GPG decryption
   key —, `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`), then
   smoke-test via Actions → "Weekly encrypted backup" → Run workflow and
   confirm the object lands in R2. Scheduled workflows only fire from the
   default branch.
9. Standard runbook pass: sections 0–6 (CI covers 1–3; Dashboard steps are
   manual) + human verification (section 6).
10. **Update the documented production version — in the same pass.** Nothing
    derives it automatically, so it drifts silently: `CLAUDE.md` (the Overview
    line **and** the prod-project line under *Environments*), the
    `backlog/README.md` roadmap paragraph, and any README statement about what
    is live. It already bit us — the 30/07 promotion took prod to `1.6.33` while
    every one of those still said `1.6.23`, which made the backlog claim billing
    was awaiting promotion when it had in fact shipped. Also re-read what the
    stale number implied elsewhere, not just the number itself.
11. **Tag and PUBLISH THE RELEASE — the promotion is not done without it**
    (owner, Aug 2026). Annotated tag `vX.Y.Z` on the promoted `master` commit,
    then a published GitHub release on that tag. **This is the only artefact a
    USER can read to learn what changed in the version they just received** —
    the README changelog is developer documentation and the in-app number says
    nothing by itself. Title `vX.Y.Z — <what it delivers>`, body in PT-BR:
    one-paragraph summary, `### Destaques` written for whoever uses the app
    (backlog IDs in parentheses, never as the explanation), `### Banco de dados`
    when migrations shipped, and the `compare/<previous>...<this>` link. Draft
    it from the README changelog rows this promotion carries.
    **How — the full convention (format, wording, publishing, current state) is
    [`docs/releases/README.md`](../docs/releases/README.md); read that one, not
    this paragraph, when actually writing a release.** In short: the notes live
    at **`docs/releases/<tag>.md`** (first line = the release title, rest = the
    body), written in the same PR as the promotion; then run **Actions →
    `Publicar release no GitHub` → Run workflow**, filling `tag` with `vX.Y.Z`
    and leaving `target` empty when the tag already exists (or `master` to have
    the workflow create the tag on the current `master` head). Success looks
    like the version showing up at
    `https://github.com/irineus/entrelares-app/releases` as *Latest*.
    **State (05/08/2026): `v1.7.15` was published WITH that promotion** — the
    first release through the workflow, which the same promotion carried to
    `master` (so "Run workflow" exists from now on). No pre-written file is
    pending; the first delivery after the promotion creates
    `docs/releases/v1.7.16.md` and the rename-per-delivery cadence restarts (the
    workflow fails with "notas não encontradas" when the name does not match the
    tag — on purpose).
    **The "Run workflow" button only appears once `publish-release.yml` is on
    `master`** — `workflow_dispatch` is registered from the DEFAULT branch only
    (same restriction as `schedule`; from `dev` the API answers a bare 404).
    Until then — and as a fallback any time — publish by hand at
    `https://github.com/irineus/entrelares-app/releases/new?tag=vX.Y.Z`:
    *Choose a tag* resolves to the existing tag, the **Release title** is the
    first line of the notes file (without the `# `) and the **body** is
    everything after it; leave *Set as a pre-release* unchecked and click
    **Publish release**.
    The workflow refuses to overwrite an existing release — correct a published
    one by hand in the UI. This indirection exists because the releases REST API
    is blocked in the browser-based Claude Code sessions (the GitHub MCP
    connector only READS releases), so without it the assistant cannot publish.
    **Patch promotions get a release too**, even a three-line one.

---

## 8. Incident response — data breach (LGPD art. 48)

Pairs with the disaster-recovery plan (T-19). A "security incident" here is any
event with possible unauthorized access to personal data: leaked key
(`service_role`, R2 token, Resend key), RLS bypass, compromised admin account,
exposed backup, or a Supabase/Cloudflare/Resend upstream breach affecting us.

**1. Contain (immediately).**
- Rotate the compromised credential first: Supabase Dashboard → Settings → API
  (service_role/anon), R2 token in Cloudflare, Resend key, GitHub secrets that
  mirror them (`deploy.yml` / `backup.yml`).
- If an account is compromised: Authentication → Users → sign-out/ban the user;
  if the app itself is the vector, pause the Cloudflare Pages deployment.
- Preserve evidence: export the relevant Dashboard logs (Auth, Edge Functions,
  Postgres) BEFORE any cleanup — they age out.

**2. Assess (same day).**
- What data, whose, how many subjects, for how long, was it a CHILD-related
  record (notes/schedule)? Custody data leaking to the wrong party is the
  worst-case scenario — treat any cross-family exposure as high risk.
- Record a timeline (detection, window of exposure, vector) in a private
  incident note; it becomes the art. 48 report's core.

**3. Notify (if risk or relevant damage to data subjects).**
- **ANPD**: within the regulated deadline (Resolução CD/ANPD nº 15/2024 —
  **3 business days** from awareness) via the ANPD's incident form; include
  nature of data, subjects affected, technical measures, risks, mitigation.
- **Affected users**: plain-PT-BR e-mail from the privacy address
  (privacidade@entrelares.app) — what leaked, when, what we did,
  what THEY should do (e.g. change password), contact for questions.
- Under-notification is the fined behavior; when in doubt at the risk
  threshold, notify.

**4. Recover & post-mortem.**
- Restore integrity if data was altered (T-19 backups; document any restore).
- Post-mortem within a week: root cause, what detection lacked, corrective
  backlog items (S- prefix), and whether policies/runbook need updating.

---

## 9. Billing go-live (T-39) — activating real charges in production

> **DONE — production has been charging since 29/07/2026.** The product owner
> ran this checklist and flipped `billing.enabled=true` in prod `app_settings`
> that day; prod carries real subscriptions and webhook events since. This
> section is kept as (a) the RECORD of what was configured and (b) the
> procedure for any future environment. **Do not re-run the flag step as if it
> were pending** — and treat the billing path as production-critical from here
> on: a change to `billing-checkout`/`billing-webhook`, `set_family_plan` or the
> grace cron can now cost a real family money or access.
>
> *(Discovered 03/08/2026 while verifying the 1.7.0 promotion against the
> database: the docs had claimed "dormant behind `billing.enabled=false`" for
> five days after the flip. Same lesson as S-15 — check the claim against the
> system, not against our own notes.)*

The billing code has been live in production since `1.6.33`: functions,
tables, RPCs and the grace cron are all deployed by CI. **Go-live was pure
configuration — no deploy, no promotion.** It is the product owner's explicit
decision; the steps below are in the order they must happen (webhook
authentication BEFORE the flag flip, so no payment can ever arrive
unprocessed). Everything was validated end-to-end in the sandbox on
28/07 (checkout → Pix → webhook → premium; refund → free; cancel honors the
paid period; re-subscribe adds time).

**9.1 Real Asaas account** — at https://www.asaas.com (NOT `sandbox.asaas.com`).
Complete the commercial registration (CPF or CNPJ) and wait for the account
approval; register the receiving bank account (*Configurações → Conta
bancária*) and check the current per-transaction fees (*Configurações →
Taxas*). Two prerequisites discovered in the sandbox run: register the site
**the app host** (callback-domain validation; `app.guardacompartilhada.com` at the time —
since F-54 the host is **`web.entrelares.app`**, which must be ADDED there at the
promotion-A cutover or the hosted checkout refuses the new callback URLs) and create a
**Pix key** — without one the hosted checkout silently doesn't offer Pix.

**9.2 Production API key** — Asaas dashboard → avatar menu → *Integrações →
Chave de API*. Shown **once** (`$aact_prod_…`); copy it straight into the
password manager. It must exist nowhere in the repo — only as the function
secret below.

**9.3 Prod function secrets** — Dashboard of the **prod** project
(`jptqbwfziyzlhlmoekzu`) → Edge Functions → Secrets (the section 2.1 table):
- `ASAAS_API_KEY` — the key from 9.2.
- `ASAAS_API_URL` = `https://api.asaas.com/v3` — **mandatory**: the sandbox is
  the code default precisely so a misconfigured environment can never charge
  real money by accident, which means prod must opt in explicitly.
- `ASAAS_WEBHOOK_TOKEN` — a fresh random value (e.g. `openssl rand -hex 32`),
  never the sandbox one. Keep a copy: the same value is typed again in 9.4.
- `APP_URL` — should already be `https://web.entrelares.app` (F-54); confirm.

Secret changes need **no redeploy** — they apply to subsequent invocations.

**9.4 Register the webhook in the Asaas dashboard** (*Integrações → Webhooks* →
new webhook):
- **URL**: `https://jptqbwfziyzlhlmoekzu.supabase.co/functions/v1/billing-webhook`
- **Auth token**: the exact `ASAAS_WEBHOOK_TOKEN` value — Asaas sends it in the
  `asaas-access-token` header, the only authentication the function accepts.
- API version **v3**, sequential queue, alert e-mail = the owner's (Asaas
  e-mails when the queue pauses).
- **Events**: payments `PAYMENT_CONFIRMED`, `PAYMENT_RECEIVED`,
  `PAYMENT_OVERDUE`, `PAYMENT_REFUNDED` + subscriptions
  `SUBSCRIPTION_DELETED`, `SUBSCRIPTION_INACTIVATED`. Selecting "all" is safe —
  unknown events are ledgered and acked with 200.
- Queue semantics: repeated non-2xx responses make Asaas **pause the whole
  queue** (silencing every family's events) — that is why the function returns
  200 even for events it ignores. If the queue ever pauses, fix the cause and
  re-enable it on this same screen.

**9.5 Auth smoke test** (30 seconds, before the flip):
```bash
# no token → must print 401
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  https://jptqbwfziyzlhlmoekzu.supabase.co/functions/v1/billing-webhook \
  -H "Content-Type: application/json" -d '{}'

# with the token → {"error":"Malformed event."}
# (400 = authenticated and parsed, rejected as empty — both sides of the token match)
curl -s -X POST \
  https://jptqbwfziyzlhlmoekzu.supabase.co/functions/v1/billing-webhook \
  -H "Content-Type: application/json" \
  -H "asaas-access-token: <the token>" -d '{}'
```

**9.6 Flip the switch.** This is per-environment runtime configuration, not
schema — a direct UPDATE in the prod SQL Editor is the correct mechanism (a
migration would wrongly drag dev/QA to the same value):
```sql
-- review the prices first if needed: billing.price_monthly_cents,
-- billing.price_annual_cents, billing.grace_days, billing.grace_warning_days
UPDATE public.app_settings SET value = 'true' WHERE key = 'billing.enabled';
```
The moment it commits, the Família page swaps the F-32 waitlist for the real
offer and `billing-checkout` starts creating payment links. The grace/dunning
cron is already scheduled by migration (pg_cron, hourly at :23) — nothing to arm.

**9.7 End-to-end verification with a real payment** — use the owner's own
family in prod: monthly checkout (R$ 5,49, the cheapest — promotional launch price, F-48) → Asaas hosted page →
pay via Pix → redirected back to `/premium/retorno` → verify
`subscriptions.status = 'active'` with `current_period_end` ≈ +1 month, the
`PAYMENT_RECEIVED` row in `billing_events`, `families.plan = 'premium'` and the
premium features unlocked in the app. Optionally close the loop: **refund** the
payment in the Asaas dashboard — `PAYMENT_REFUNDED` must drop the subscription
to `canceled` and the plan to `free` (and the Pix comes back). Troubleshooting
lives in **Edge Functions → `billing-checkout` / `billing-webhook` → Logs** and
in the ledger (`billing_events` rows with `event_type = 'CHECKOUT_ERROR'`
record the gateway's exact refusal).

---
## 9-bis. Store billing go-live (T-48) — the Google Play rail

> **DONE — the store rail is LIVE in production since 23/08/2026.** The code
> shipped with T-53 lote 5 (20/08/2026), reached the prod project with the
> `v1.8.13` promotion (22/08), and `billing.store_enabled` was flipped to `true`
> on 23/08 after the whole console side below was executed and verified on a
> real device.
>
> **What a real purchase proved, end to end** (23/08/2026, licensed tester,
> internal-test track):
>
> | Time (UTC) | Event | Effect |
> |---|---|---|
> | 01:43:40 | `PLAY_RTDN_4` (PURCHASED), via Pub/Sub push | recorded; `subscription_id`/`family_id` NULL — nothing to attach to yet |
> | 01:44:17 | `PLAY_PURCHASE_VERIFIED`, the app calling `billing-store-verify` | subscription row created, plan → `premium` |
> | 01:45:48 | `PLAY_RTDN_3` (CANCELED), via Pub/Sub push | found the row, status → `canceled` |
>
> **The RTDN for the purchase arrived 37 seconds BEFORE the client could
> verify.** That race is real and the design absorbs it: the webhook cannot
> attach a purchase token that no family owns yet, so it records and no-ops, and
> the client's verification is what creates the row. Do not "fix" this by making
> the webhook create subscriptions — it would be granting Premium from a message
> body, which is exactly what the design refuses.
>
> Final state after cancelling: `status = canceled`, `current_period_end` intact
> a month out, `families.plan` still `premium`. The paid period survived, and
> the grace cron owns the eventual downgrade — same shape as an Asaas
> cancellation.
>
> **Rolling back** is still one statement (9-bis.5). Purchases already made keep
> applying, because the RTDN webhook is not gated by the flag.

Why this rail exists at all: a native app may NOT sell a digital subscription
through an external checkout. The Asaas rail (recurring + Pix avulso) keeps
serving the WEB channel; Play Billing serves the store one. Both converge in
the database — same `set_family_plan`, same `billing_events` ledger, same
grace window, same additive renewal.

**9-bis.0 Upload a build that declares BILLING — this comes FIRST.** Play only
unlocks the Subscriptions page once an uploaded build declares
`com.android.vending.BILLING`; until then the page says *"Your app doesn't have
any subscriptions yet"* and offers only *"Upload a new APK"*. The bundle sitting
in the account today is the **TWA**, which carries no billing permission (the
original T-48 was the Digital Goods API and never shipped), so 9-bis.1 below is
unreachable until this step is done — found the hard way on 22/08/2026.

The Flutter build carries the permission with no manifest edit of ours:
`in_app_purchase` pulls `com.android.billingclient:billing`, whose AAR manifest
declares it, and the merge does the rest.

```
cd apps/entrelares_app && fvm flutter build appbundle --flavor prod --release
```

Upload it to the **internal-test** track (see the warning under 9-bis.6 — never
the closed one), with a tester list holding the owner's account only, and add
that same account under *Setup → License testing* so the test purchase does not
charge.

> There is **nothing to declare** about in-app purchases. Checked on the real
> console (22/08/2026): *Policy → App content* holds ten declarations — health
> apps, advertising ID, financial features, government apps, data safety, target
> audience, content ratings, ads, sign-in details, privacy policy — and none of
> them is about IAP. Play derives "contains in-app purchases" from the products
> that exist. Do not confuse it with **Financial features**, which is about
> financial SERVICES (lending, crypto) and is correctly answered "no". The
> uploaded build is the only gate.

**9-bis.1 Create the two subscription products** in Play Console → *Monetize →
Subscriptions*. The product ids are pinned in the client
(`packages/entrelares_core/lib/src/store_billing_rules.dart`, with a test that
fails if they drift) and in `billing-store-verify`:

| Product id | Base plan | Notes |
|---|---|---|
| `premium_monthly` | monthly, auto-renewing | |
| `premium_annual` | annual, auto-renewing | |

Set the prices HERE, per country — the app displays whatever Play answers and
never a number from `app_settings` (which rules the web rail only). Google's
fee (~15% in the subscriptions tier) is yours to absorb or price in; the R$ 5,00
Asaas floor does not apply to Play.

**9-bis.1-bis The Google Cloud project — there was none.** Both 9-bis.2 and
9-bis.3 assume a Cloud project exists; on 22/08/2026 the account had none, and
neither this section nor anything else said to create one.

> **Do NOT look for "API access" in the Play Console.** That page is gone from
> this account (checked 22/08/2026: not under Settings, not under Developer
> account, and `/developers/<id>/api-access` redirects to the app list). It used
> to create and link the Cloud project — and enable the Play API — in one click.
> Without it, both are manual, and **enabling the Play API is no longer
> optional**: skip it and verification answers 403 with the purchase already
> made.

Create everything in Google Cloud, then grant access from the Play Console:

1. Project — <https://console.cloud.google.com/projectcreate>
2. Enable **Google Play Android Developer API** —
   <https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com>
3. Enable **Cloud Pub/Sub API** (for 9-bis.3) —
   <https://console.cloud.google.com/apis/library/pubsub.googleapis.com>

Check that 2 and 3 landed inside the project from 1: each API screen carries
`?project=…` in its URL, and that is where it is verified. Enabling an API on
the wrong project is silent.

Done on 22/08/2026: project `entrelares-506400`, both APIs enabled, service
account `entrelares@entrelares-506400.iam.gserviceaccount.com` with no IAM role
(correct — the Play Console is what authorizes it).

> Pub/Sub usually wants an active **billing account** on the project even when
> usage sits entirely inside the free tier — and RTDN volume for one app is far
> from that limit. Expect near-zero cost, but the decision to attach a card is
> the owner's: it touches the group-8 rule that new platform spend waits for
> revenue (T-36).

**9-bis.2 Service account for the Play Developer API.** In Google Cloud, create
a service account and a JSON key; in Play Console → *Users and permissions*,
invite that account and grant **View financial data** + **Manage orders and
subscriptions** for this app. Paste the whole JSON as the function secret
`PLAY_SERVICE_ACCOUNT`. Without it, `billing-store-verify` fails loudly (by
design — a silent fallback would grant Premium on the client's word).

**9-bis.3 Real-Time Developer Notifications.** Create a Pub/Sub topic, allow
`google-play-developer-notifications@system.gserviceaccount.com` to publish to
it, and point Play Console → *Monetize → Monetization setup → RTDN* at it. Then
create a **push subscription** whose endpoint is:

```
https://<PROJECT_REF>.supabase.co/functions/v1/billing-store-webhook?token=<PLAY_RTDN_TOKEN>
```

Pub/Sub allows no custom headers, so the shared token travels on the query
string — set the same value as the function secret `PLAY_RTDN_TOKEN` (long and
random; it is the ONLY authentication that endpoint has). Set the SECRET FIRST:
until it exists the endpoint answers 401 to everything, including a perfect
configuration. Also leave the subscription's **payload unwrapping OFF** — the
function reads `push.message.data` and `push.message.messageId`, and an
unwrapped delivery would be silently ignored with a 200, which is the worst
kind of failure. Set **Expiration period = never**: the default is 31 days of
inactivity, and a rail with no subscribers yet produces exactly that. Use Play
Console's "Send test notification" button and check the function logs: a test
notification is acknowledged and applies nothing.

> **Known limitation — the token is in the request logs.** The platform logs the
> full URL, so `?token=…` sits in plaintext in the Edge Function logs (seen
> 23/08/2026). That is inherent to the design: Pub/Sub sends no custom headers,
> so the secret must travel in the URL.
>
> The blast radius is small on purpose — the webhook **never trusts the message
> body** for entitlement. It takes the purchase token to the Play Developer API
> and applies what Google says, so a forged message with an invented token is a
> no-op. Damage would require an already-real purchase.
>
> **Rotating it** has no zero-downtime path (the function compares against one
> value), but nothing is lost: a mismatch answers 401, Pub/Sub retries, and the
> retry lands once both sides agree. Order: change the function secret, then the
> push subscription's endpoint URL.

**9-bis.4 Package name.** Set `PLAY_PACKAGE_NAME` to the flavor's
`applicationId` — `com.entrelares.app` in production. The default matches, so
this is only needed if it ever changes.

**9-bis.5 Flip the switch — BEFORE the test purchase, not after.**

```sql
UPDATE public.app_settings SET value = 'true' WHERE key = 'billing.store_enabled';
```

> **This step used to be numbered LAST, and in that order it is impossible**
> (found 22/08/2026, preparing the go-live). While the flag is `false` the
> client returns `StoreOffer.neutralNote` before anything else
> (`store_billing_rules.dart`) and never offers a purchase, and
> `billing-store-verify` refuses with 409. There is no button to press: you
> cannot buy your way to the state the old 9-bis.6 waited for.
>
> Turning it on first is safe **while the store build reaches nobody but the
> tester**. The store rail exists only in the Flutter ANDROID build
> (`isStoreChannel = !kIsWeb`), so with the app on the internal-test track and
> the licensed tester list holding one account, the flag reaches exactly that
> device. The TWA in production and the Flutter web target stay on the Asaas
> rail, untouched. Re-check that assumption before flipping it in any other
> situation: once the stage-4 cutover puts the Flutter build in front of real
> users, this flag is a PRODUCT decision, not a test setup.

The client reads it on the next load; no deploy needed. To roll back, set it to
`false` — the store build returns to the neutral note, and purchases already
made keep working (the RTDN webhook is not gated by the flag: money that Google
already took must keep applying). That rollback is the safety net for
everything below.

**9-bis.6 A real purchase, on a real device.** Add a licensed tester account in
Play Console, install a build from the **internal-test** track, and buy. What
to check: the Premium section flips to active, `subscriptions` holds a row with
`gateway='play'` and the purchase token, and cancelling on Play arrives as an
RTDN that leaves the paid period intact. **An emulator cannot do this** — Play
Billing needs the store, and the test purchase needs the licensed account.

The ledger keys, which this section used to state wrongly as
`play:<token>:<expiry>` (it cost a wrong `LIKE` filter while verifying the real
purchase on 23/08/2026):

| Written by | `event_id` | `event_type` |
|---|---|---|
| `billing-store-verify` | `play:<purchaseToken>` | `PLAY_PURCHASE_VERIFIED` |
| `billing-store-webhook` | `play-rtdn:<messageId>` | `PLAY_RTDN_<type>` |

So `event_id LIKE 'play%'` catches both; `'play:%'` catches only the direct
verification.

> **Internal test, NOT closed alpha** (owner, 22/08/2026). `com.entrelares.app`
> is the same package the current TWA ships under, so a build on the closed
> track would hand the Flutter app to the alpha testers before the stage-4
> cutover — a different app, with no notice. The internal track with a
> single-account tester list is what keeps this a test.


## 9-ter. Google login go-live (F-57) — enabling the provider, per project

> **PARTIALLY DONE, and the gap was invisible for a month — read 9-ter.0 step 2 first.** The
> code merged on 27/08/2026 (PRs #92/#93, `2.1.0+55`) and both projects answer
> `external.google: true`, but on 28/08/2026 the console showed the Google Auth Platform app
> still in **Testing**: step 2 of 9-ter.0 was never executed. **FIXED 10/09/2026 — the app is now
> `In production`.** It stayed broken for two weeks, and the shape of the break is worth keeping:
> the *Test users* table was **empty**, which is worse than "capped to a list". An empty list does
> not mean everyone — it means **only principals holding an IAM role on the Cloud project could
> complete Google sign-in at all**. The owner could, because the account owns the project; every
> alpha tester who pressed the button since the go-live hit a wall, and no signal on our side
> could show it. Those who did get in were also **silently signed out after 7 days**, when Testing
> expires the refresh token — so expect one last such sign-out from sessions created before the
> fix.
>
> **Which project's Audience is the one that matters.** Both Supabase projects hand the browser
> the SAME OAuth client — `97600663120-8jnqm3cq…apps.googleusercontent.com`, so `97600663120` is
> the Cloud project whose consent screen users actually see. It is neither Firebase project
> (`entrelares-dev` is `51960618124`, `entrelares-prod` is `575356979434`; §11.1). **Confirmed
> 10/09/2026:** *Google Auth Platform → Clients* in `entrelares-506400` lists exactly one client,
> *"Entrelares — Supabase GoTrue"*, Web application, created 27/08/2026 — so that project's
> Branding, Audience and Verification are the ones that reach a user. Re-confirm it before
> publishing or submitting if anything about the client changes: every Cloud project has its own
> consent screen, and configuring the wrong one changes nothing on the device. Read it without
> the console:
>
> ```
> curl -s -o /dev/null -w "%{redirect_url}
" >   https://<ref>.supabase.co/auth/v1/authorize?provider=google
> ```
>
> The `client_id` in that redirect is public — it is in the URL every user's browser follows.
>
> **Why nobody caught it, which is the lesson worth more than the fix.** This banner told you to
> verify in one command and to prefer that over reading the console. That advice is right about
> what it covers and dangerously wrong as a stand-in for the section: `/auth/v1/settings`
> answers **only** "is the provider enabled". It says nothing about publishing status, so
> `external.google: true` was read as "9-ter is done" when it only ever meant "step 9-ter.1
> happened". **There is no endpoint for publishing status** — the Audience page is the only
> source, and that asymmetry is exactly where a config gap can hide behind a green check.
>
> So: verify the provider with the command below, and verify the AUDIENCE by opening
> `https://console.cloud.google.com/auth/audience`. Two checks, because there is no one check.
>
> ```
> curl -s -H "apikey: <publishable key>" https://<ref>.supabase.co/auth/v1/settings
> ```
>
> **What is live where, because the two channels are NOT in the same state:**
>
> | Channel | State |
> |---|---|
> | Web (`web.entrelares.app`) | Button live from the merge — the web build follows `main` |
> | Android | **No button until a Play promotion of a bundle ≥ `2.1.2+57`.** What is on the store predates F-57 and has no such code — this is not a config problem and no console change fixes it |
>
> **Enabling prod before T-61 was deliberate, not an oversight.** T-61 (the consent screen and
> Google's summary e-mail both naming `<ref>.supabase.co` instead of Entrelares) is a blocker
> for the PUBLIC rollout (T-59), and the product is still in closed alpha — so this puts the
> flow in front of exactly the testers whose feedback created F-57, while the branding fix
> lands before it reaches strangers. **Closed 10/09/2026, and the host never moved** — path A
> brands the consent screen in place, so the migration this paragraph used to warn about did not
> happen and its warning survives only under §9-quater.C/D, for the day a host change is chosen.
> **§9-quater is the procedure** — and read it before assuming the host has to move at all: the
> (A, Google brand verification) changes no host and no code, and only its failure sends us to
> a path that does.

The code shipped dormant on purpose: **the switch IS the provider config.**
The app asks GoTrue's public settings endpoint (`/auth/v1/settings`) whether
`google` is enabled and only then renders the button — so there is no
`app_settings` flag to flip, nothing that can disagree with the real config,
and each project (dev / prod) arms itself independently. Until you finish this
section on a project, that project's builds simply have no Google button.

**9-ter.0 GCP — one OAuth client, once.** In a Google Cloud project owned by
the product account (ours is `entrelares-506400`). Google reorganised this
console in 2026: what used to be *APIs & Services → OAuth consent screen* is
now its own product, **Google Auth Platform** (`console.cloud.google.com/auth`),
split into Branding / Audience / Clients / Data Access. The old
*APIs & Services → Credentials* page still exists and still LISTS the client
afterwards — it just no longer creates it.

1. *Google Auth Platform → **Branding***: app name **Entrelares**, support
   e-mail, the `entrelares.app` authorized domain.
2. *Google Auth Platform → **Audience***: **External**, and **publish it** —
   the "Testing" state caps sign-ins to a listed set of accounts and expires
   refresh tokens after 7 days. Left in Testing, this surfaces as users being
   silently signed out a week later, which reads like an app bug and is not.

   > **This step was MISSED at the go-live and the miss survived a month
   > (found 28/08/2026, preparing T-61).** It is the one step in this section
   > with no observable signal on our side: the button appears, a listed
   > tester signs in, the settings endpoint says `true` — everything a
   > developer would check comes back green while the app is closed to
   > everyone not on the list. **Confirm it by eye, on the Audience page,
   > every time this section is run**, and confirm it the only way that
   > actually proves it: sign in with an account that is NOT a test user.
   > Publishing is also the prerequisite for T-61 path A — verification cannot
   > be submitted while the app is in Testing (§9-quater.A).
3. *Google Auth Platform → **Clients** → Create OAuth client → Application
   type: **Web application*** (WEB, even for Android: the device never talks to
   Google directly — GoTrue does the code exchange server-side). Name it for
   the console's own benefit (`Entrelares — Supabase GoTrue`). Leave
   *Authorized JavaScript origins* EMPTY — this is a redirect flow, not a
   browser-implicit one. Under **Authorized redirect URIs**, BOTH projects'
   GoTrue callbacks:
   - `https://buroanotfjcgvbfmacuh.supabase.co/auth/v1/callback` (dev)
   - `https://jptqbwfziyzlhlmoekzu.supabase.co/auth/v1/callback` (prod)

   The create screen warns that settings take **5 minutes to a few hours** to
   take effect. Believe it: a `redirect_uri_mismatch` in the first minutes
   after saving is propagation, not a typo — re-check the URI once, then wait
   rather than "fixing" a correct value.
4. Keep the **Client ID** and **Client secret** — the next step wants them.
   One client for both projects is fine; the secret lives only in the Supabase
   consoles (never in this repo — Rule 1).

**9-ter.1 Supabase — per project, DEV first.** *Authentication → **Sign In /
Providers*** (the entry called plain "Providers" until 2026) → **Google**:
enable, paste Client ID + secret, save.

> Do NOT confuse it with its two neighbours, which read like the right thing
> and are its mirror image: **OAuth Apps** (under MANAGE) and **OAuth Server
> (BETA)** are Supabase acting AS an OAuth provider for third parties. What
> this section configures is Supabase CONSUMING Google.

Then *Authentication → URL Configuration → Redirect URLs*, add the app's
return addresses:

| Project | Add to Redirect URLs |
|---|---|
| dev | `com.entrelares.flutter://login-callback` (Android dev flavor) — plus `http://localhost:*` patterns if web QA runs locally |
| prod | `com.entrelares.app://login-callback` (Android prod) and `https://web.entrelares.app` (web channel return) |

The custom schemes match the manifest's `${applicationId}` intent filter and
`DeepLinkUrls.oauthCallback` — per flavor so a device carrying both apps never
opens a chooser. Nothing here requires a redeploy: the S-16 ordering trap does
not apply because no Edge Function reads this config.

> **Do NOT test the invitation half from the e-mail on dev — it cannot work,
> and the way it fails is a trap.** `send-swap-email` builds the invite link
> from the `APP_URL` secret, and **dev has had no web target since T-56**: the
> Blazor QA deployment died with the cutover. The secret still said
> `qa.entrelares.app`, a host that did not stop resolving — it became a GHOST,
> answering with a stale build, so the link opened a real-looking page with no
> Google button and nothing about it said "wrong app" (measured 27/08/2026).
> **Already fixed the same day:** dev's `APP_URL` now carries
> `https://web.entrelares.app`, the same value prod does — the ghost is strictly
> worse than pointing at a live host, because a stale build that answers is the
> failure mode that lies quietly.
>
> Know what that costs, though: a DEV invite e-mail then points at the
> PRODUCTION web app, whose database has no such token, so it answers
> "convite inválido". That is honest and harmless — a dev token can do nothing
> in prod — but it means **dev invite testing happens inside the app**, never
> from the inbox: use "Copiar link" on the Família screen, or push the link
> straight in with
> `adb shell am start -a android.intent.action.VIEW -d "https://web.entrelares.app/register?invite=<token>" com.entrelares.flutter`.
> A debug build never verifies App Links (per-machine certificate), so the
> e-mail link would land in the browser regardless of the secret's value.
> Giving dev a web deployment again is the only real fix, and it is its own
> scope.

**9-ter.2 Verify on DEV before touching prod.** A dev-flavor build
(`workflow_dispatch → build-apk`) on a real device: the button appears on
`/login` (it was absent before — that is the fail-closed switch working), a
NEW Google account lands on `/onboarding`, completes the form and reaches the
calendar; an invited e-mail tapping "continuar com Google" from the register
screen lands on the claim variant. On the dev project, confirm the profile
row carries `consent_policy_version` = current and `joined_via_invite`
matching the path taken.

**9-ter.3 Prod.** Repeat 9-ter.1 on the prod project. The button reaches real
users on the WEB immediately; on Android it waits for the next Play promotion
(the manifest's scheme filter ships with `2.1.0+55`+).

> **Correction (27/08/2026, during the go-live).** This step used to warn that
> enabling prod before the store carried the F-57 build would strand an
> Android user in the browser. Checked against the code, that scenario cannot
> happen: the build currently on Play predates F-57 and has no button to tap,
> and an Android user browsing `web.entrelares.app` returns through the web
> origin (`Uri.base.origin`), never the scheme. The real constraint is the
> other one, and 9-ter.1 already satisfies it: **prod's Redirect URLs must
> already list `com.entrelares.app://login-callback` when a build ≥`2.1.0+55`
> reaches the store** — provider and redirect URL are configured together, so
> they cannot drift apart. Enabling prod is therefore safe for the web channel
> at any time; what gates it is 9-ter.2, not the store.

**Do not skip 9-ter.2 to get here faster.** Every automated layer (237 gate
tests, the widget suites, `web-e2e`) exercises the RULES; none of them
executes an actual OAuth round trip, because there is no Google to redirect to
in CI. Until the dev APK run happens, the redirect, the scheme return and a
profile created from a real Google identity have never run once — and dev has
no web deployment (T-56), so that APK is the only place they can run before
real users meet them.

**Account linking posture (decided 27/08/2026):** GoTrue's automatic linking
stays ON — Google e-mails arrive verified, so a Google sign-in with an
existing password account's e-mail lands on the SAME user (one profile, one
family). The gate pins the consequences: `oauth_onboarding` /
`claim_invitation` suites.

**Rolling back:** disable the provider on the project — the button vanishes on
the next app boot, password sign-in never depended on any of this. Sessions
already created by Google keep working (they are ordinary GoTrue sessions);
disabling only closes the door for NEW sign-ins.


## 9-quater. T-61 — making the Google screens say Entrelares

> **DONE 10/09/2026, by path A, at zero cost and with no application code changed.** Both
> measurements passed: the consent flow names **Entrelares** on four surfaces (account chooser,
> consent title, permission sentence, policy links) with the U-29 logo, and Google's summary
> e-mail arrived titled *"You shared some Google Account data with Entrelares"*. Kept in full
> because two of its premises were **false**, and the corrections below are the part worth
> reading: there is **no verification submission** for non-sensitive scopes (step 3), and the
> documented reason path A could fail **could never have fired**. C and D stay for a rollback or
> a change of mind; **B has no live trigger left**.

**The problem.** Google identifies the relying party by the HOST of the redirect URI, and today
that host is the project ref. Measured on a real device during the F-57 go-live: the consent
screen reads *"Fazer login no serviço `jptqbwfziyzlhlmoekzu.supabase.co`"*, and Google's summary
e-mail arrives titled *"You shared some Google Account data with
jptqbwfziyzlhlmoekzu.supabase.co"*. Full reasoning in the T-61 card, which is the record of the
item since T-63 retired the markdown backlog (07/09/2026).

**The decision (owner, 28/08/2026): A now, B if A fails.** Both are free. The two host changes
stay documented below because they are what a rollback or a change of mind returns to — they are
NOT the plan.

| | Path | Cost | Fixes Android | Fixes web |
|---|---|---|---|---|
| **A** | **Google brand verification** — **DONE 10/09/2026** | zero | yes | yes |
| **B** | **Native sign-in** (`signInWithIdToken`) — fallback, **no live trigger** | zero | yes | **no** |
| C | Vanity subdomain (`entrelares.supabase.co`) | zero | partial | partial |
| D | Custom domain (`auth.entrelares.app`) | ~US$10/mo | yes | yes |

> **What falling back to B accepts, in writing.** B replaces the browser redirect with the
> platform's own account picker, and on Flutter WEB there is no such picker:
> `google_sign_in_web` reports `supportsAuthentication: false` and **throws on
> `authenticate()`** — the only web path is Google's own rendered button (GIS), which would put
> a third-party SCRIPT source in the CSP (`accounts.google.com`) and replace the U-27 button
> with an iframe. `_headers` refuses exactly that, by an owner decision of 23/08/2026: fonts may
> come from a third party, executable code may not. So **if we land on B, the web channel keeps
> showing `<ref>.supabase.co`** — and that is accepted, not a defect to reopen.
>
> **The positioning it rests on (owner, 28/08/2026), because it is not obvious from the code:**
> Entrelares is an **Android/iOS product**. `web.entrelares.app` and the Asaas rail it sells
> through are the **alternative channel, deliberately not the main focus** — which is why an
> unbranded consent screen there is a price worth paying for a free fix on the channels that
> matter. Read that before "fixing" the web gap: the repo shows two channels built to the same
> standard and says nothing about their rank, so the rank has to be written down.

**9-quater.A — Brand verification. Free, no code, and — measured 10/09/2026 — no wait either.**

Supabase's own Google guide is explicit that Branding **and Verification** *"show a logo and name
instead of the Supabase project ID in the consent screen"*. That is the lever the first analysis
missed: §9-ter.0 configured Branding, but Branding alone changes nothing on screen — **verified**
is a separate submission with human review, and publishing the Audience (step 0 below) is only
its prerequisite. "Branding set, screen still showing the ref" is the expected state of an
unverified app, so the device measurement and this path do not contradict each other.

> **The exact values to submit** — app name, logo path, the three landing URLs, the scopes, and
> the two-place re-measurement protocol — are in the card's sub-page **"T-61 — Brand verification
> submission dossier"**, each one verified against this repository and the live hosts on
> 10/09/2026. This section stays the procedure and the ordering; that page is what to paste, and
> afterwards the record of what was submitted.

0. **Publish the app first.** *Google Auth Platform → **Audience*** must read **In
   production**, not Testing — Google neither requires nor accepts verification for an app in
   Testing, so everything below is inert until this is done. It is also §9-ter.0 step 2, which
   was missed at the F-57 go-live; see the banner at the top of §9-ter.
1. *Google Auth Platform → **Branding***: app name **Entrelares**, logo, support e-mail,
   authorized domain `entrelares.app`, and the home page / privacy policy / terms links — the
   landing already serves `entrelares.app/privacidade` and `/termos` (lote 4). **Use
   `apps/entrelares_app/assets/brand/emblema.png`** (the indigo squircle, U-29) — or
   `store/store_icon.png`, which since **T-57** (28/08/2026) is the same U-29 mark rather than
   the retired F-54 clay emblem; the two differ only in framing (the store icon is full-bleed at
   60 %, cut for Play's own rounding).

   > **Measured on 28/08/2026:** the *Authorized domains* list already carries both Supabase
   > project hosts, added by the console because the OAuth client's redirect URIs live there.
   > **Do not remove them** — that breaks the client.
   >
   > This was also, from 28/08 to 10/09/2026, the documented way path A could fail: Google wants
   > proven ownership of authorized domains and `supabase.co` is not ours. **It never came up.**
   > There is no submission for non-sensitive scopes (step 3), so nothing ever asked us to prove
   > a domain. The risk was real on paper and moot in practice.
   >
   > The support e-mail is a **dropdown**, not a free field: it offers the signed-in account and
   > Google Groups you administer. `suporte@entrelares.app` is not among them, so the configured
   > value is the owner's own address.
2. *Google Auth Platform → **Data Access (Scopes)***: confirm only `openid`,
   `.../auth/userinfo.email` and `.../auth/userinfo.profile`. The app passes **no** `scopes` to
   `signInWithOAuth` (`main.dart`), so these are the defaults — all non-sensitive, which is the
   light review path, with no security assessment.
3. *Google Auth Platform → **Verification Center***. **There is nothing to submit, and no wait
   — measured 10/09/2026.** The page answers *"Verification is not required since your app is not
   requesting any sensitive or restricted scopes"*, and Branding status reads *"Your branding has
   been verified and is being shown to users"*. **Publishing (step 0) is what makes Branding take
   effect**; the human review this section spent two weeks planning around applies to sensitive
   and restricted scopes, which we do not request. If this page ever DOES ask for a submission,
   something added a scope — go read step 2 before answering it.
4. **Re-measure both places on a real device**, the way the finding was made: the consent screen
   line AND the subject of Google's summary e-mail. Only both together close T-61.
   **The console is not the measurement.** "Being shown to users" is Google's claim about its own
   state, and the whole of T-61 exists because Branding was configured on 28/08 and the device
   still read the project ref — configured never meant displayed. Trust the handset.

   > **Revoke the grant first, or you measure nothing.** Google shows the consent screen — and
   > sends the summary e-mail — only on an account's FIRST authorization. A returning account
   > skips both, and "I did not see the ref" is then evidence of nothing. `myaccount.google.com/
   > connections` → the entry → *Remove access*. It does not touch the Supabase account: GoTrue
   > keys the identity on the Google `sub`, which survives the revoke.

   **Measured 10/09/2026, both PASSED.** The flow names Entrelares on four surfaces with the
   logo — including the **account chooser**, which the original finding never checked and which
   carried the ref too. The e-mail arrived **one minute** later, not hours, titled *"You shared
   some Google Account data with Entrelares"*. Both screens render in GOOGLE's UI language, not
   the product's, so English there is not a U-13/U-24 regression.

> **The open risk that could never fire — kept because reasoning this well and still being wrong
> is the lesson.** Google requires authorized domains to be domains
> you can prove you own, and it infers domains from the redirect URIs. If `supabase.co` is pulled
> into that list, the submission may be refused over a domain we cannot verify. **It never came
> up: there is no submission on this path**, so nothing ever asked us to prove a domain. The risk
> was about a mechanism that does not run here — and it was the ONLY trigger for path B, which
> therefore sat armed for two weeks against something that could not happen. That refusal — or
> a review that comes back with the screen still naming the ref — is the trigger for B. Nothing
> else is.

**9-quater.B — Native sign-in. Free, ~1 session, Android (and iOS with T-40).**

> **NOT pending work since 10/09/2026.** A closed and its only trigger turned out to be
> unreachable, so this stays as the answer to a future regression — Google un-verifying the app,
> or a scope change dragging us into real review. Its console half is already paid: the Fulcrum
> tenant's six OAuth clients (§11.1 item 4) are exactly what it orders.

Google issues an ID token to the app and `signInWithIdToken` exchanges it for a Supabase session.
GoTrue's redirect never happens, so **no host is displayed at all** — it is the native account
picker, showing the app's own name and icon, which is also better UX than today's Custom Tab.

*What survives untouched, which is most of F-57:* `AuthProviders.googleEnabled()` and the
`/auth/v1/settings` fail-closed switch (the provider still has to be enabled), the
`OauthOnboardingScreen`, `completeOauthOnboarding`, migration `20260827140000`, and the gate
suites `oauth_onboarding` / `claim_invitation` / `joined_via_invite` — all of them live
downstream of "a Google session exists". The screens' button wiring (`googleEnabled` +
`onSignInWithGoogle`) is unchanged; only the callback body is.

*What changes:* `google_sign_in ^7.x` in `pubspec.yaml`; the ~25 lines of `_signInWithGoogle`
(`main.dart`, v7 API: `GoogleSignIn.instance`, `serverClientId`, `authorizeScopes`); **one
Android OAuth client per flavor** in GCP (the package differs); the Web client ID registered in
Supabase's *Client IDs*; and the manifest's scheme `intent-filter` plus
`DeepLinkUrls.oauthCallback` become dead code. For iOS (T-40) add the iOS client and enable
*Skip nonce check*.

> **The friction to plan for, because it hits the §9-ter.2 loop.** Native sign-in binds to
> package name **+ signing certificate**, so every certificate needs its SHA-1 registered:
> Play's app-signing key (prod), the T-55 sideload keystore (dev flavor), and the **debug
> keystore, which is per machine**. Today's redirect flow works on any build; after B, a debug
> build cannot sign in with Google until that machine's SHA-1 is registered. Budget console time
> for every new development machine.

**9-quater.C / D — changing the auth host. Documented, NOT the plan.**

Kept because a rollback, a failed A *and* B, or a later change of mind returns here — and because
the client-side facts below are true of any host change. **C** is Supabase's free **vanity
subdomain** (`entrelares.supabase.co`, CLI only, experimental): it deletes the random string but
keeps `supabase.co` on the screen where the user hands over their identity. **D** is the paid
**Custom Domain** add-on (`auth.entrelares.app`), whose procedure follows. The two are **mutually
exclusive**, so taking C would buy a second host migration later, with real accounts already
created.

Whichever is chosen, **three client files name the host** — the "no application code" reading was
wrong: `lib/env.dart` (`Env.prod.supabaseUrl`), `web/_headers` (whose `connect-src` wildcard
`*.supabase.co` does NOT cover `auth.entrelares.app`) and `pubspec.yaml` (the version bump).
`web_channel_test` asserts that `connect-src` covers the host `Env.prod.supabaseUrl` names, so
the flip is a red gate until `_headers` follows it.

**9-quater.D0 — Buy the add-on.** *Dashboard → the PROD project → Settings → Add-ons → Custom
Domain*. Per project, per month. Owner-only step: it is a spend.

**9-quater.D1 — DNS, on the `entrelares.app` zone (Cloudflare).**

| Type | Name | Value | Proxy |
|---|---|---|---|
| CNAME | `auth` | `jptqbwfziyzlhlmoekzu.supabase.co.` | **DNS only (grey cloud)** |

**The grey cloud is not a preference.** Supabase terminates TLS for this hostname itself and
issues the certificate through an ACME challenge against these records; with Cloudflare's proxy
orange, our edge answers for the name and the issuance never completes. Use a low TTL until the
domain is verified — a mistake then costs minutes instead of a day.

**9-quater.D2 — Register and verify ownership.**

```
supabase domains create --project-ref jptqbwfziyzlhlmoekzu --custom-hostname auth.entrelares.app
```

It prints one outstanding TXT record, `_acme-challenge.auth.entrelares.app`. **Cloudflare appends
the zone to the name**, so create it as `_acme-challenge.auth`, never as the full name — the
classic way to end up with `_acme-challenge.auth.entrelares.app.entrelares.app`. Trim the
surrounding whitespace off the value. Then:

```
supabase domains reverify --project-ref jptqbwfziyzlhlmoekzu
```

Expect to run it more than once: DNS has to propagate and the certificate can take up to 30
minutes.

**9-quater.D3 — GCP BEFORE activating.** *Google Auth Platform → Clients →* the
`Entrelares — Supabase GoTrue` client → **Authorized redirect URIs**: ADD

- `https://auth.entrelares.app/auth/v1/callback`

**in addition to** the two already there (§9-ter.0). Do not remove the prod project-ref URI —
it is what a rollback returns to. Google's own warning applies here as much as it did then:
the change takes **5 minutes to a few hours** to propagate, so a `redirect_uri_mismatch` right
after saving is propagation, not a typo.

**9-quater.D4 — Activate. This is the hard cutover.**

```
supabase domains activate --project-ref jptqbwfziyzlhlmoekzu
```

What activation actually does, and the asymmetry that matters:

| Surface | On `<ref>.supabase.co` after activation |
|---|---|
| REST, Realtime, Storage, Edge Functions | **keep working** — both hosts serve them |
| **Third-party auth (Google)** | **stops working.** GoTrue advertises the custom domain only |

So the client flip below is not optional and cannot be deferred to "next release": from
activation onward, the ONLY host where Google sign-in exists is the new one. Do it in a quiet
window — sign-ins in flight at that instant fail (the user retries and succeeds; existing
sessions and `auth.identities` rows are untouched).

**What does NOT change, so nobody "fixes" it:** the Redirect URLs / Site URL allowlist (those
are the app's RETURN addresses — `com.entrelares.app://login-callback`,
`https://web.entrelares.app`), the `APP_URL` secret, and the Edge Function warm-up in
`.github/functions.sh`, which addresses functions on the project host that keeps answering.

**9-quater.D5 — The client flip, in the same window.** One PR, three lines and a version bump:

1. `apps/entrelares_app/lib/env.dart` — `Env.prod.supabaseUrl` → `https://auth.entrelares.app`.
2. `apps/entrelares_app/web/_headers` — `connect-src` gains
   `https://auth.entrelares.app wss://auth.entrelares.app`. **Keep the `*.supabase.co` pair**:
   dev still lives there. Miss this and the web channel does not degrade — it reaches NO API at
   all, REST and Realtime included, with only the browser console to say why.
3. `apps/entrelares_app/pubspec.yaml` — `version:`, both halves.

Step 2 cannot be forgotten: `web_channel_test` asserts that `connect-src` covers the host
`Env.prod.supabaseUrl` names, so step 1 without step 2 is a red gate (T-61). Merging to `main`
publishes the web channel; Android picks the new host up at the next Play promotion, and until
then the store build still points at the project ref — where **Google sign-in no longer works**.
Sequence the promotion with this, or accept a window where the store app's Google button fails.

**9-quater.D6 — Verify, in this order.**

```
curl -s -H "apikey: sb_publishable_uKr0ES-10F3gpcd0j0osYw_HxqP_RMZ" \
  https://auth.entrelares.app/auth/v1/settings
```

`external.google` must be `true` on the NEW host. Then re-run §9-ter.2 against **production**
on a real device, and read the two lines the item exists for: the consent screen must say
*"Fazer login no serviço auth.entrelares.app"*, and Google's summary e-mail must name the same
host. Only both together close T-61.

**Rolling back.** `supabase domains delete --project-ref jptqbwfziyzlhlmoekzu`, then revert the
client flip (§9-quater.D5) and promote/publish it. This only works because §9-quater.D3 kept the
old redirect URI listed in GCP — removing it is what would make the rollback a second outage.

## 10. S-16 — migração das chaves de API e da assinatura JWT

Duas migrações **independentes**, nesta ordem: primeiro as chaves de API
(`anon`/`service_role` → `sb_publishable_…`/`sb_secret_…`), depois a assinatura
JWT (HS256 → ES256). A segunda é o que quebrou o cadastro por convite em julho;
ela só é segura **depois** que nada mais depende de chave legada, porque as
legadas são JWTs assinados com o *JWT secret* do projeto — as novas não são.

Links diretos por projeto (o Dashboard usa o *ref*, não o nome):

| | DEV (`Entrelares-Dev`) | PROD |
|---|---|---|
| API Keys | [`/project/buroanotfjcgvbfmacuh/settings/api-keys`](https://supabase.com/dashboard/project/buroanotfjcgvbfmacuh/settings/api-keys) | [`/project/jptqbwfziyzlhlmoekzu/settings/api-keys`](https://supabase.com/dashboard/project/jptqbwfziyzlhlmoekzu/settings/api-keys) |
| Segredos das Functions | [`/functions/secrets`](https://supabase.com/dashboard/project/buroanotfjcgvbfmacuh/functions/secrets) | [`/functions/secrets`](https://supabase.com/dashboard/project/jptqbwfziyzlhlmoekzu/functions/secrets) |
| JWT Keys | [`/settings/jwt`](https://supabase.com/dashboard/project/buroanotfjcgvbfmacuh/settings/jwt) | [`/settings/jwt`](https://supabase.com/dashboard/project/jptqbwfziyzlhlmoekzu/settings/jwt) |
| Cron | [`/integrations/cron/jobs`](https://supabase.com/dashboard/project/buroanotfjcgvbfmacuh/integrations/cron/jobs) | [`/integrations/cron/jobs`](https://supabase.com/dashboard/project/jptqbwfziyzlhlmoekzu/integrations/cron/jobs) |

> **Ordem obrigatória.** As Edge Functions leem `SUPABASE_SECRET_KEYS`/
> `SUPABASE_PUBLISHABLE_KEYS` e **falham sem elas**. O CI redeploya as 8 funções
> a cada push em `dev` e a cada promoção em `master`, então **10.1 tem de estar
> feito no projeto ANTES do deploy chegar nele** — em DEV antes do merge, em PROD
> antes da promoção.

### 10.1 Criar as chaves novas (uma vez por projeto)

1. Abra a página **API Keys** do projeto (links acima). O menu é
   **Project Settings → API Keys** (ícone de engrenagem na barra lateral).
2. Selecione a aba **"Publishable and secret API keys"** (a outra aba,
   *"Legacy API keys"*, é onde vivem `anon` e `service_role` — não mexa nela agora).
3. Se aparecer o botão **"Create new API keys"**, clique. Ele cria **duas** chaves
   de uma vez, ambas com o nome **`default`**:
   - **`sb_publishable_…`** — substitui a `anon` (pública, vai no app).
   - **`sb_secret_…`** — substitui a `service_role` (bypassa RLS; **nunca** no cliente).
4. **Nomes importam.** O helper `_shared/keys.ts` procura a chave chamada
   `default`; se não houver `default`, aceita quando existe **uma só**; e **recusa
   escolher** se houver várias sem `default`. O DEV já tem uma publishable chamada
   **`github_key`** (criada em julho) — deixe-a lá: com a `default` nova convivendo,
   o helper usa a `default`. Não renomeie nada.
5. Copie os dois valores agora (a secret só é exibida por inteiro na criação;
   depois fica mascarada). Guarde-os fora do repositório.

**Verificação (obrigatória antes de seguir):** abra a página **Edge Functions →
Secrets** (link acima) e confirme que a lista mostra `SUPABASE_PUBLISHABLE_KEYS`
e `SUPABASE_SECRET_KEYS`. São injetadas pela plataforma — você **não** as cria à
mão. Se não aparecerem, o passo 3 não completou; sem elas todas as funções
respondem 500 no primeiro deploy.

### 10.2 Provar, antes de rotacionar nada, que a chave nova funciona

O gateway do Supabase resolve o papel a partir do header **`apikey`** e recusa a
chave nova em `Authorization` (ela não é JWT). Dois comandos no **PowerShell**
respondem se a nossa suíte sobrevive à troca — rode-os **antes** de tocar nos
secrets do GitHub. Substitua o valor entre aspas pela secret key do DEV.

```powershell
$key = "sb_secret_COLE_AQUI"
$url = "https://buroanotfjcgvbfmacuh.supabase.co/rest/v1/roles?select=id&limit=1"
$ua  = "guarda-compartilhada-probe/1.0"
```

> **⚠️ O `-UserAgent` não é enfeite (custou uma rodada, ago/2026).** A secret key
> tem uma proteção a mais que a `service_role` legada nunca teve: o gateway
> **recusa** a chave quando o `User-Agent` parece navegador — *"Forbidden use of
> secret API key in browser"*. O `Invoke-RestMethod` do PowerShell 5.1 manda
> `Mozilla/5.0 (Windows NT…) WindowsPowerShell/5.1`, que casa com a regra, então
> a sonda falha mesmo com a chave correta. Ironicamente a mensagem **prova** que a
> chave é válida (o gateway a reconheceu para poder recusá-la). Nenhum chamador
> real nosso cai nisso — `HttpClient` do .NET não manda UA, o `curl` do keepalive
> manda `curl/8.x`, o `pg_net` e o Deno das functions mandam o próprio —, é uma
> armadilha exclusiva de quem testa à mão.

**Teste A — só `apikey` (é assim que os crons e as chamadas função→função ficam):**
```powershell
Invoke-RestMethod -Uri $url -Headers @{ apikey = $key } -UserAgent $ua
```
Esperado: **uma linha de `roles`**. Se vier 401, confira se copiou a *secret* (não
a publishable); se vier a mensagem de *browser*, faltou o `-UserAgent`.

**Teste B — `apikey` + `Authorization` (é o que o SDK C# faz sozinho, e o que eu
não consegui verificar daqui):**
```powershell
Invoke-RestMethod -Uri $url -Headers @{ apikey = $key; Authorization = "Bearer $key" } -UserAgent $ua
```

O PowerShell 5.1 esconde o corpo da resposta em erro; para ver status + mensagem:
```powershell
try { Invoke-RestMethod -Uri $url -Headers @{ apikey = $key; Authorization = "Bearer $key" } -UserAgent $ua }
catch { $_.Exception.Response.StatusCode.value__; (New-Object IO.StreamReader $_.Exception.Response.GetResponseStream()).ReadToEnd() }
```
- **Se retornar a linha:** a plataforma tolera o Bearer e a rotação do secret de
  CI é segura — siga para 10.3.
- **Se retornar 401:** o fixture dos testes (`E2EFamilyFixture.Service`, que usa o
  SDK e não permite omitir o `Authorization`) vai quebrar. Nesse caso **não
  rotacione** `SUPABASE_SERVICE_ROLE_DEV`: mantenha a `service_role` legada (válida
  até o fim de 2026), pule para 10.4 e **não faça o 10.5** — o ES256 é justamente o
  que invalida chave legada.

> **Resultado no DEV (03/08/2026): A e B verdes**, ambos devolvendo a linha de
> `roles`. Ou seja, **a plataforma ACEITA a secret key no `Authorization`**, ao
> contrário do que a doc oficial afirma em *Known limitations* ("You can't send a
> publishable or secret key in the `Authorization: Bearer` header"). É o mesmo
> descompasso já observado com a publishable, que roda no DEV desde julho com a
> suíte verde. Consequência prática: o SDK C# — que monta o `Authorization`
> sozinho e não deixa omitir — continua funcionando, então a rotação do secret de
> CI está liberada. **O código continua mandando só `apikey` onde controlamos o
> header**: seguir o contrato documentado é o que nos protege se a plataforma um
> dia passar a aplicar o que ela própria documenta.

**Teste C — a Admin API do GoTrue, com `apikey` sozinho.** Os testes A e B cobrem
o PostgREST; este cobre o outro caminho privilegiado que a suíte usa: o
`AdminApi` cria e apaga os usuários descartáveis da família E2E em
`/auth/v1/admin/users`, e desde o S-16 manda a chave nova **só** no `apikey`.
```powershell
Invoke-RestMethod -Uri "https://buroanotfjcgvbfmacuh.supabase.co/auth/v1/admin/users?page=1&per_page=1" -Headers @{ apikey = $key } -UserAgent $ua
```
Esperado: um objeto com a lista `users` (pode vir vazia — o que importa é **não**
ser 401). Um 401 aqui significaria que o GoTrue não aceita a chave nova sem um JWT
no `Authorization`, e aí o `AdminApi` precisaria mandá-la nos dois headers (o Teste
B já provou que a plataforma tolera) antes de rotacionar o secret.

> **Resultado no DEV (03/08/2026): C verde** — a Admin API devolveu a lista de
> usuários com a chave **só** no `apikey`. Com A, B e C verdes, os três caminhos
> privilegiados que a suíte usa estão cobertos (PostgREST nos dois formatos de
> header e a Admin API do GoTrue), e a rotação do `SUPABASE_SERVICE_ROLE_DEV`
> está liberada sem mudança de código.

### 10.3 Rotacionar os secrets do GitHub

Repositório `irineus/Entrelares` → **Settings** → **Secrets and
variables** → **Actions** → aba *Secrets* → no secret existente, botão de lápis
(*Update*) → cole o novo valor → **Update secret**. Os nomes exatos:

| Secret | Novo valor | Situação |
|---|---|---|
| `SUPABASE_ANON_KEY_DEV` | publishable do DEV | **já rotacionado** em jul/2026 |
| `SUPABASE_SERVICE_ROLE_DEV` | secret key do DEV | só se o Teste B passou |
| `SUPABASE_ANON_KEY_PROD` | publishable do PROD | fazer antes da promoção |

Não existe secret `SUPABASE_SERVICE_ROLE_PROD` — a suíte roda **sempre** contra o
DEV, inclusive em `master`, então a chave privilegiada de prod nunca entra no CI.
Em prod a secret key só é usada pelas Edge Functions (injetada pela plataforma) e
pelos crons (via Vault, passo 10.4).

No seu ambiente local, o arquivo git-ignored `e2e.local.env` na raiz do repo
recebe a **secret key do DEV** em `E2E_SUPABASE_SERVICE_ROLE_KEY` (nunca a de prod).

### 10.4 Migrar os crons para o header `apikey`

Os dois jobs criados nas seções 4.4/4.5 mandam a chave em `Authorization: Bearer`
— **chave nova é recusada ali**. Por projeto:

1. **SQL Editor** → guarde a secret key no Vault (nome exato `secret_key`):
   ```sql
   select vault.create_secret('sb_secret_COLE_AQUI', 'secret_key');
   ```
   Confirme (não imprime o valor):
   ```sql
   select name from vault.secrets where name = 'secret_key';
   ```
2. **Integrations → Cron → Jobs**: edite o job **`auto-approve-expired-hourly`** e
   depois **`purge-deleted-daily`**. Em cada um, no campo do comando SQL, troque o
   bloco `headers` por:
   ```sql
   headers := jsonb_build_object(
     'Content-Type', 'application/json',
     'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'secret_key')),
   ```
   O resto do comando (`url`, `body`, `timeout_milliseconds := 30000`) fica igual.
3. **Verificação:** espere a próxima hora cheia e abra **Edge Functions →
   `auto-approve-expired` → Logs**. Sucesso = uma execução registrada. Se o job
   ainda estiver com o header antigo, o log mostra
   `refused — caller did not present the secret key` (a função agora recusa no
   próprio código, então o erro **aparece** — antes o gate da plataforma barrava
   antes da função e não sobrava log nenhum).

### 10.5 Validar em DEV antes de tocar em prod

GitHub → aba **Actions** → workflow **"Deploy to Cloudflare Pages"** → botão
**Run workflow** → escolha a branch **`dev`** → *Run workflow*. O `workflow_dispatch`
roda o pacote E2E **completo** (o push normal em `dev` roda só o `pack=p0`), que é
onde o cadastro por convite e a `EdgeFunctionAuthTests` de fato exercitam as chaves.
Verde aqui é o pré-requisito de qualquer passo em prod.

### 10.6 Promover o ES256 (a segunda migração)

Só depois de 10.1–10.5 verdes. Página **JWT Keys** → aba **"JWT Signing Keys"**
(links no topo).

> **Os nossos projetos NÃO começam do zero aqui** (constatado no DEV, 03/08/2026).
> A doc do Supabase descreve um botão **"Migrate JWT secret"** para quem ainda está
> só no segredo legado — ele **não aparece** nos nossos, porque o incidente de julho
> já passou por essa etapa: a plataforma criou a chave **ECC (P-256)** e a promoveu
> sozinha, e o nosso rollback a rebaixou. Então a tela mostra **HS256 como
> *CURRENT KEY*** e a **ECC (P-256) em *Previously used keys*** ("last rotated"
> ≈ a data do incidente). O caminho é *reaproveitar* essa chave, não criar outra:

1. Na tabela **"Previously used keys"**, na linha da chave **ECC (P-256)**, abra o
   menu **⋮** da coluna *ACTIONS* → **"Move to standby"**. A chave sobe para o
   painel de standby. **Nada muda em runtime neste passo.**
   *Não* clique em **"Create Standby Key"** — isso geraria uma chave nova e
   desnecessária; a ECC que já está lá serve.
2. Aguarde ~5 minutos (a plataforma limita mudanças de estado) e clique em
   **"Rotate keys"**. A ECC/ES256 vira *CURRENT KEY* e a HS256 desce para
   *Previously used*. **Ninguém é deslogado**: os tokens já emitidos continuam
   aceitos até expirar.
3. Deixe a HS256 em *Previously used* — a revogação dela é o 10.7, e só depois de
   desativar as chaves de API legadas.
4. Faça no **DEV primeiro** e repita o dispatch full-pack (10.5). O ES256 antes da
   promoção é deliberado: se a contingência abaixo se confirmar, ela é uma mudança
   de CÓDIGO, e código só chega em produção pela promoção — fazendo o DEV primeiro,
   a correção pega carona na mesma; na ordem inversa, exigiria uma segunda.
5. **Contingência conhecida:** a doc do Supabase avisa que funções com *Verify JWT*
   ligado podem quebrar na rotação. Cinco das nossas já rodam sem o gate (S-16);
   sobram **`elevate`** e **`billing-checkout`**. Se elas passarem a responder 401
   depois da rotação, a correção é barata e já está meio pronta: ambas **já
   validam o JWT do usuário no próprio código** (`admin.auth.getUser(jwt)` /
   `userClient.auth.getUser()`), então basta acrescentá-las ao `config.toml` com
   `verify_jwt = false` e ao `deploy.yml` com `--no-verify-jwt`, como as outras.

> **Resultado no DEV (03/08/2026): rotação feita, full-pack VERDE** (run #261,
> 18min26s, com a ECC/ES256 como *Current*). O que ele prova, item a item:
> `register-invitee`/`admin.createUser` — **a primeira vítima de julho** — passou;
> `SudoElevationTests` e `BillingCheckoutTests` passaram, ou seja **a contingência
> acima NÃO se materializou**: o gate `verify_jwt` da plataforma valida tokens de
> usuário ES256 normalmente (o aviso da doc vale para quem verifica JWT contra o
> *segredo legado* no próprio código, que não é o nosso caso); e o `service_role`
> da CI, já no formato `sb_secret_`, operou contra um projeto em ES256. O JWKS
> passou a publicar `alg=ES256` com o `kid` da chave promovida — e lista **só** ela,
> porque a HS256 é segredo compartilhado e não tem contraparte pública (continua
> aceita na verificação até ser revogada no 10.7).
>
> **PROD seguiu no mesmo dia, logo após a promoção da `1.7.1`** e com o mesmo
> desenho de tela (HS256 *Current*, ECC `E2CB7F04…` em *Previous* há 11 dias): sonda
> das functions verde (`{processed:0, emailsFailed:0}` com a chave, **401** sem),
> crons migrados, verificação humana no app real, e então *Move to standby* +
> *Rotate keys*. O JWKS de prod passou a publicar `alg=ES256`. **Os dois ambientes
> estão migrados** — o que falta é só o 10.7, agora rastreado como **S-17**.

### 10.7 Desativar as chaves legadas — item de backlog **S-17**

> Este passo **não** é um resto de tarefa: ele espera por construção (tokens
> assinados com HS256 valem por 1 h, e a plataforma recusa revogar o segredo
> enquanto as chaves que derivam dele estiverem ativas), então virou item próprio.
> Registro e critérios de verificação no card **S-17**
> ([board](https://app.notion.com/3b12f3f4b9b28111a8d7e7d4bce53122)) — o card é o registro desde
> 07/09/2026 (T-63), e `backlog/` é história congelada.

Página **API Keys** → aba **"Legacy API keys"** → use os indicadores de *last used*
para confirmar que `anon` e `service_role` não são mais chamadas → **Disable**.
É reversível (dá para reativar se aparecer um cliente esquecido). Só depois disso
o segredo HS256 pode ser revogado na página JWT Keys — e a própria plataforma
**exige** essa ordem, porque `anon`/`service_role` são JWTs assinados por ele.
Espere ao menos **1h15** após a rotação antes de revogar (o access token dura 1h;
revogar antes desloga quem estiver com sessão ativa).

---

## 11. Push notifications go-live (F-09) — arming a project to push

> **The rail ships DARK, on purpose.** The trigger, the table and the Edge Function are
> deployed by CI to both projects, and on a project without the secrets below every one of
> them returns without doing anything. Nothing here is a prerequisite for merging F-09 —
> it is what turns the rail on, per environment, and dev should be armed first because
> that is where a real device can be pointed at it without a user noticing.

**Order matters in one place only:** `FCM_SERVICE_ACCOUNT` must exist on a project **before**
its `google-services.json` reaches a build that real people run. The reverse — an app that
registers tokens against a project whose function cannot send — is harmless (rows accumulate,
nothing is delivered); the same shape as the S-16 ordering rule, for the same reason.

### 11.1 One Firebase project per environment

Two projects, mirroring the two Supabase projects — **not** one project with two Android
apps. The boundary is the point: a single project means a single service account, so a bug
in a QA run can push to production devices, which is exactly what the build flavors exist to
prevent.

1. [console.firebase.google.com](https://console.firebase.google.com) → **Add project**.
   Suggested names: `entrelares-dev` and `entrelares-prod`. Google Analytics is not needed
   (T-37 already owns analytics, and it is Umami).
2. In each project → **Add app → Android**, with the flavor's `applicationId`:
   - dev project → `com.entrelares.flutter`
   - prod project → `com.entrelares.app`
3. Download each `google-services.json`. They are **public client config** (rule 1: the file
   carries no secret) and are committed in the app PR under
   `apps/entrelares_app/android/app/src/dev/` and `.../src/prod/`.
4. **SHA-1 fingerprints are not needed for messaging** — they are a Google-sign-in concern,
   and F-57 handles sign-in through Supabase, not Firebase. Both files nonetheless CARRY
   fingerprints since 10/09/2026: the Fulcrum tenant registered six OAuth clients in these very
   projects (one Web + one Android per signing certificate, per project), so `oauth_client` is no
   longer empty. **Nothing in `lib/` reads them** — the app still signs in by redirect. They are
   inert here and are the standing prerequisite of T-61 path B (§9-quater.B), which is why they
   are committed rather than stripped.

### 11.2 The service account, per project

FCM's HTTP v1 API authenticates with a service account, not a server key (the legacy key API
was retired in 2024).

1. Firebase Console → ⚙️ **Project settings → Service accounts → Generate new private key**.
   A JSON file downloads. **It is a real secret** — never commit it.
2. Supabase Dashboard (the MATCHING project) → **Edge Functions → Secrets** → add
   `FCM_SERVICE_ACCOUNT` with the **entire JSON file contents** as the value, on one line.
3. Redeploy is not required — Edge Function secrets are read at invocation.

Check it landed, from either project (the empty POST is the same warm-up the deploy pipeline
sends, and it answers with the arming state instead of doing work):

```
curl -s -X POST -H "apikey: <secret key>" \
  https://<ref>.supabase.co/functions/v1/send-push-notification
```

`{"skipped":"no notification_id","configured":true}` — `configured:false` means the secret is
missing or is not valid JSON with `client_email`, `private_key` and `project_id`.

### 11.3 The two Vault secrets the trigger reads

The dispatcher trigger runs inside Postgres, which knows neither the project's own URL nor
any API key. Both come from Vault, and **either one missing disarms the trigger silently** —
which is what makes this migration safe to apply to an unarmed project.

`secret_key` already exists on both projects (section 10.4, for the crons). Only the base URL
is new. In the **SQL Editor**:

```sql
select vault.create_secret(
  'https://<ref>.supabase.co/functions/v1', 'functions_base_url');
```

No trailing slash — the trigger appends `/send-push-notification`. Confirm both are present:

```sql
select name from vault.secrets where name in ('secret_key', 'functions_base_url');
```

### 11.4 Verify end to end

With a device registered (the app writes its own `push_subscriptions` row after the user
grants the permission), have the other caregiver open a swap request on the dev project. The
push should arrive within a couple of seconds. When it does not, read in this order:

```sql
-- 1. Did the trigger fire and get a 2xx back? (pg_net keeps its own log)
select id, status_code, error_msg, created
from net._http_response order by created desc limit 5;

-- 2. Is there a device at all?
select profile_id, platform, created_at from public.push_subscriptions;
```

Then the function's own logs (Dashboard → Edge Functions → `send-push-notification`), which
name every refusal explicitly: `FCM_SERVICE_ACCOUNT not set`, `no registered device`,
`payload could not be rendered`, `type … is not pushable`.

> **A token that stops working is not a bug to chase.** FCM retires tokens on uninstall and
> on its own rotation schedule, and answers `UNREGISTERED`; the function deletes those rows,
> and the app registers a fresh token on its next start. An empty `push_subscriptions` for a
> profile means that person has not granted the permission on any device — the notification
> and its e-mail still reached them.

---

## 11-bis. The WEB half of the same rail (T-62)

> **Everything in section 11 already covers the web.** The trigger, the function, the service
> account, the two Vault secrets and the ten types are platform-agnostic, and
> `push_subscriptions.platform` has accepted `'web'` since the F-09 migration. What is missing
> on a project armed by §11 is only the CLIENT half: a Firebase **Web app** and a VAPID key
> pair. Until they exist the web channel reports `unsupported` and says so on the Notificações
> screen — it never offers a switch that cannot work.

**This is client config, not a secret**, so unlike §11.2 it is COMMITTED. It also lands in two
places at once, and `web_channel_test` fails the build if only one of them moves.

### 11-bis.1 One Web app per Firebase project

In the SAME project §11.1 created for the environment — not a new one, or the token would be
minted against a service account that cannot send to it.

1. Firebase Console → the project → ⚙️ **Project settings → General → Your apps → Add app →
   Web** (`</>`). Nickname is free; **do not** tick "Also set up Firebase Hosting".
2. The console shows a `firebaseConfig` object. Four of its fields are the ones needed here:
   `apiKey`, `appId`, `messagingSenderId`, `projectId`. (`authDomain` and `storageBucket` are
   for products this app does not use.)
3. Same settings page → **Cloud Messaging** tab → **Web Push certificates** → **Generate key
   pair**. The string in the "Key pair" column is the VAPID **public** key. The private half
   never leaves the console.

### 11-bis.2 Writing them down, on both sides

The page and the service worker each need the config, and they get it separately: a worker is
started by the browser with no page to ask.

1. `apps/entrelares_app/lib/env.dart` → the `webPush:` slot of `Env.prod` (and of `Env.dev`
   only while a session is watching a push arrive locally — see the comment there).
2. `apps/entrelares_app/web/firebase-messaging-sw.js` → `FIREBASE_CONFIG`, the same four
   values minus the VAPID key.

```
cd apps/entrelares_app && fvm flutter test test/web_channel_test.dart
```

That suite compares the two objects string by string, checks that all five values are present
(a HALF-filled config passes a "not empty" check and then fails at `getToken` complaining about
an unrelated field) and asserts the worker stays inert while `apiKey` is blank.

### 11-bis.3 Verify end to end

`web-e2e` cannot prove this: it drives a headless Chrome with no notification permission and no
service-worker lifetime. The acceptance is one human round, the same shape F-09's was.

1. Open the channel in a desktop Chrome or an Android browser, sign in, and turn the control on
   in **Notificações**. Granting the browser prompt is what mints the token.
2. `select profile_id, platform from public.push_subscriptions;` — a `web` row must be there.
3. **Make the tab invisible — SWITCH to another tab; do NOT close it.** Hiding it is the point of
   the test (with a visible client FCM forwards the message to the page and shows nothing), but
   CLOSING it is a different act, and locally it is fatal: see the box below. Then have the other
   caregiver open a swap request.
4. The notification appears with the product's title, body and icon; clicking it opens
   `/notifications?tab=…&n=…` on the right tab.

> **Testing this LOCALLY has two traps, and both cost a full round on 08/09/2026.**
>
> **Fix the port.** `flutter run` picks a random one, and an origin is scheme + host + **port** —
> so every run is a NEW origin, with its own service worker, its own notification permission and
> its own token. The control then reads "off" on the new origin and looks like it disarmed itself,
> while the token in `push_subscriptions` still points at the previous origin. Always
> `fvm flutter run -d chrome --web-port=8099`.
>
> **Never close the tab locally.** The tab and `flutter run` die together, and a service worker
> whose server is gone cannot start: its `importScripts('/firebasejs/…')` gets connection refused,
> so the push is dropped **silently**. Every layer upstream still reports success — the dispatcher
> logs `sent`, because FCM's job ended when it handed the message to the push service. Switch tabs
> instead. None of this exists on `web.entrelares.app`, where the origin is stable; it is an
> artefact of the dev server only.

When nothing arrives, read in this order: the browser's DevTools → Application → Service
Workers (`firebase-messaging-sw.js` must be *activated and running* at scope
`/firebase-cloud-messaging-push-scope`, alongside the app shell's worker at `/`); then the
console for a CSP refusal (`connect-src` must cover `firebaseinstallations` and
`fcmregistrations`, and NOTHING may be blocked in `script-src` — the SDK is vendored under
`/firebasejs/<version>/` precisely so it is not); then the function's logs as in §11.4.

> **iOS Safari buys almost nothing here, and that is expected.** Web push on iPhone requires
> the site added to the Home Screen — the installed-PWA scope that died with the cutover. The
> audience this section serves is desktop and Android browsers.

> **Upgrading the SDK is a re-vendoring, not a `pub upgrade`.** `firebase_core_web` fetches the
> Firebase JS SDK from `www.gstatic.com` at runtime, which this channel's CSP forbids for
> executable code. The four bundles under `apps/entrelares_app/web/firebasejs/<version>/` are
> served from our own origin instead. When the plugin's `supportedFirebaseJsSdkVersion` moves,
> `web_channel_test` goes red; the fix is `python tool/vendor_firebase_js.py` after bumping its
> `VERSION`, plus the paths in the worker and in `push_messaging_web.dart`.

---

## 12. F-53 — the closed-alpha courtesy Premium (who it covers, and how it is granted)

> **Nothing here is new mechanism.** F-58 shipped all of it: `admin_set_comp` writes
> `families.comp_premium_at` + `comp_premium_note`, and `is_premium()` reads that column
> ITSELF — never a parallel check. This section is the **semantics** F-58 deliberately left to
> F-53: who the public promise covers, and the exact procedure that leaves "why is this family
> premium?" answerable a year from now.

**The promise** (WhatsApp, 11/08/2026, closed-alpha recruitment message): *whoever joins the
test gets Premium free, permanently, for their family — current and future paid features.* It
was published before anything implemented it, which is why F-53 was recorded the same day (the
S-15 lesson: a published claim with no implementation is a liability, and this one lived in
WhatsApp instead of a policy page).

### 12.1 The cutoff (owner decision, 01/09/2026)

A **tester family** is one whose account was **created inside the closed-alpha window,
11/08/2026 → 01/09/2026 inclusive** — the day the closed test ended.

Not the Play tester list, which was the other candidate: somebody who accepted the Console
invitation and never signed up has no family to reward, and somebody who signed up inside the
window is exactly who the sentence *"quem entrar no teste"* addresses. The window is also
checkable against the database (`families.created_at`), so the cohort can be re-derived instead
of remembered.

**Anyone who arrives after 01/09/2026 is a normal user on the normal 30-day trial.**
That is a decision, not an oversight, and it is written here so a late arrival is *answered*
rather than argued.

**What was actually granted (01/09/2026):** every family with **`id` up to 17**. `families.id`
is sequential, so the id boundary and the date cutoff describe the same set — the id is simply
the form the operator could act on family by family in the console. It is also the cheapest way
to re-derive the cohort later:

```sql
select id, name, created_at, comp_premium_at, comp_premium_note
from public.families where id <= 17 order by id;
```

### 12.2 Granting — console only, never SQL

`admin_set_comp` is SECURITY DEFINER behind the operator check **and** the S-10 sudo gate, and
it writes two trails (the family's own `account_logs`, plus the append-only
`operator_audit_logs`). A hand-run `UPDATE` has none of that — it is the exact class of risk
F-58 exists to remove, so the grant never happens in the SQL Editor.

1. Console (`entrelares-console`) → pick environment **prod** at login → tab **Famílias**.
2. Find the family by a member's e-mail (the console filters the whole base locally, so one
   audited bulk read covers the batch).
3. **Conceder cortesia**, with the batch's note, character for character. The F-53 batch used:

   ```
   Closed Alpha Gift
   ```

   The note is **identical across the whole batch on purpose**: it is what makes the cohort
   recognizable later, both in the family's own history and in the operator trail. A per-family
   free text would answer "why is THIS family premium?" and lose "who else got this?" — so
   **grep for that exact string** when you need the list; it is the join key between a family
   row and this section.
4. Confirm the sudo prompt. The grant is **idempotent** — repeating it keeps the ORIGINAL
   timestamp, so re-running the batch is safe. Note that idempotent means *nothing happens*:
   a repeated grant does not rewrite the note either, so **the note is chosen once, at grant
   time**. Changing it afterwards costs a revoke + re-grant, which writes two more entries into
   the family's visible history — not worth it for wording.

> **The note is user-visible, so a future batch should be written in PT-BR.** It renders as the
> value of the family's own `account_logs` entry, which is a UI surface and therefore falls under
> the language rule in `CLAUDE.md`. The F-53 batch went out in English (`Closed Alpha Gift`) and
> was left alone: correcting it would mean revoking and re-granting 17 families to fix a caption,
> writing 34 history entries to improve none of them.

### 12.3 What the family sees — nothing to deploy

`is_premium()` returns true from that moment, and the Premium section switches to its
permanent-Premium block: the badge **✨ Premium permanente — sem expiração** over
**💙 Sua família tem Premium permanente — sem expiração e sem cobrança. Aproveite!** (PT and
EN). The trial countdown disappears even if the 30 days are still running — correct, because
the family is now premium for a reason that does not expire.

### 12.4 What a comp survives, and the one case the UI does not cover

- **Billing downgrades cannot touch it.** `comp_premium_at` is orthogonal to `plan`: the T-39
  dunning cron and the billing webhook write `plan`, `is_premium()` reads both, and the db-gate
  pins a comp surviving a billing-style downgrade. This is the "protection against billing
  downgrades" F-53 asked for, and it was answered by construction rather than by a marker check
  inside the webhook.
- **Known UI gap, accepted 01/09/2026 (not a defect in the entitlement).** The Premium
  section's state machine (`computeBillingUi`, `packages/entrelares_core/lib/src/billing_rules.dart`)
  reaches the permanent-Premium block only when there is **no subscription row at all**. A
  comped family that once subscribed and cancelled therefore still sees the OFFER — the product
  selling a subscription to someone who already holds Premium forever, and on the Android build
  that is a live Play purchase button. The entitlement itself is never at risk; only the copy is
  wrong. No tester ever subscribed (owner, 01/09/2026), so the state is unreachable for this
  cohort today and it was left alone deliberately instead of fixed speculatively. **If one ever
  lands there** — a tester who subscribes and then cancels — the fix is to pass the comp fact into
  `computeBillingUi` and return `premiumForever` *after* the `active`/`overdue`/`scheduled`
  branches — a family that is actually paying must keep its cancel button.

### 12.5 Revoking

`admin_set_comp(granted: false)` takes a reason of its own, and the family's history renders the
pair as *motivo da cortesia → motivo da revogação* (F-58 QA 4). **There is no legitimate reason
to revoke an F-53 comp** — the promise was permanent — so a revoke on this cohort should be
treated as a mistake until proven otherwise.
## 13. T-66 — crash reporting (Sentry), per project

> **Why this is in the runbook and not only in the code.** The client half ships with the app
> and needs no deploy step; what needs a human is the *other* end — the projects, the alert
> rule and the quota. Until 11/09/2026 a crash on a real device reached nobody on either
> channel, and every defect the product ever heard about came from a person who happened to say
> something.

### 13.1 The two projects

| Environment | Sentry project | Written by |
|---|---|---|
| Production | `irineu-pinheiro/entrelares-app` | the Play build and `web.entrelares.app` |
| Dev/QA | `irineu-pinheiro/entrelares-app-dev` | a `dev`-flavour build and a local `flutter run` |

**One project per environment, not one project with an `environment` tag.** The reasoning is the
one the two Firebase projects already follow (§11.1): a QA run must never be able to write into
the stream someone reads to decide whether production is on fire. The DSNs live in
`apps/entrelares_app/lib/env.dart`, one per `Env`, as PUBLIC config — a Sentry DSN is shipped to
every browser that loads an instrumented page and can only WRITE events, so rule 1 of
`CLAUDE.md` holds unchanged. **An empty DSN is a state**: `CrashReporter.isEnabled` goes false
and the app is silent, never half-configured.

Unlike analytics (T-37), **dev is NOT dark**. Umami is silent in dev so QA cannot pollute
product statistics; a crash path, by contrast, proves nothing until an event of ours has
actually landed somewhere, and the place to prove it is the environment no family lives in.

### 13.2 What leaves the device, and what deliberately does not

There is **no SDK**. The event is a hand-written envelope POST (`lib/services/crash_reporter.dart`),
and the payload itself is built and scrubbed in `packages/entrelares_core/lib/src/crash_rules.dart`,
under `dart test`. That is the whole reason for the shape: an SDK's defaults collect breadcrumbs,
user context and request data, and the S-13 invariant would then depend on switching each of them
off — where a new default in a future version reopens the leak in silence. Here nothing enters the
payload that we did not write.

**Sent:** exception type, scrubbed message, parsed stack frames (with `in_app` for our own),
release, environment, channel (`web`/`store`), platform.
**Never sent:** user id, e-mail or session; breadcrumbs; device or server name; request and
response bodies; route arguments; screenshots.

The scrubber masks the known shapes before anything is encoded — e-mail addresses, JWTs, both
S-16 key shapes, `Bearer`/`apikey` pairs, **the entire query and fragment of any URL** (that is
where an invitation token and a recovery hash live), UUIDs, and runs of six digits or more (the
S-21 elevation code is exactly six). A five-digit SQLSTATE survives on purpose: it is a
diagnosis, not a credential.

**What it cannot promise, stated plainly:** a first name has no shape a regular expression can
catch. A server message that interpolates one would carry it. That is why the message is capped
at 1 000 characters and why the app never attaches a response body — the unknown-shaped data is
kept out by not sending the places it lives, not by matching it.

### 13.2-bis The one field the client cannot scrub: the IP

**Sentry derives the reporter's IP from the request itself**, server-side, and a coarse
geolocation from it — measured 11/09/2026 on a probe event, which came back tagged
`user: ip:201.37.167.23` and `user.geo: BR, Porto Alegre` although the payload carried no user
object at all. No client-side scrubber can prevent this: the address is on the packet, not in the
body.

An IP is personal data under LGPD, so this is not a detail. Two consequences, both outside the
client code:

1. **"Prevent Storing of IP Addresses"**, per project (Sentry → Settings → Security & Privacy).
   It is the only control that stops it, it applies at ingest, and it is **not exposed by the
   API** — a human has to click it. **Enabled on both projects 11/09/2026.**
2. **Sentry processes data for us now**, exactly as allowing `fonts.gstatic.com` made Google an
   operator for the web client (see the `_headers` commentary). The privacy policy on the landing
   names who does that, and a processor the policy does not name is the S-15 failure mode in its
   purest form: a claim about the system that the system contradicts. Tracked as **L-24**.

**What the switch does NOT remove, measured after turning it on:** the event came back with no
`user` and `Users Impacted: 0`, but still carrying **`user.geo: BR, Porto Alegre`**. Sentry derives
the coarse location at ingest and keeps it even when the address it derived it from is discarded.
City-level geography is not an identifier on its own, and it is the honest thing to disclose rather
than to claim the sink receives nothing about the reader — which is the claim that would be
checked, under the S-15 method, against exactly this measurement.

### 13.3 Rate limiting, on both ends

The client sends **one event per distinct fingerprint per process**, with a ceiling of **20 per
process**. A failure inside `build()` throws on every frame, and without the ceiling one bad
release spends the month's quota — and the reader's battery — in seconds.

The free plan covers 5 000 errors/month, which is far above this product's volume. If a release
ever floods anyway, cap it at the DSN: Sentry → project → **Client Keys (DSN)** → rate limit.

### 13.4 Verifying a project by hand

One `curl` proves the whole chain — auth in the query, `text/plain` body, envelope shape:

```bash
# The key is the part of the DSN before the @; the project id is its last path segment.
DSN_KEY=745aa4d38b3b07ac90ce48a267ea4181
PROJECT=4512066983559168

cat > probe.envelope <<'ENVELOPE'
{"event_id":"aa11bb22cc33dd44ee55ff6677889901","sent_at":"2026-09-11T12:00:00.000Z"}
{"type":"event","content_type":"application/json"}
{"event_id":"aa11bb22cc33dd44ee55ff6677889901","timestamp":"2026-09-11T12:00:00.000Z","platform":"other","level":"error","release":"probe","environment":"dev","exception":{"values":[{"type":"ProbeError","value":"runbook probe"}]}}
ENVELOPE

curl -sS -X POST -H 'Content-Type: text/plain;charset=UTF-8' --data-binary @probe.envelope "https://o4511910022217728.ingest.us.sentry.io/api/$PROJECT/envelope/?sentry_key=$DSN_KEY&sentry_version=7"
# 200 + {"id":"…"} = accepted. The issue appears within seconds.
```

**The auth is in the QUERY and the body is `text/plain` on purpose** — that keeps the web
channel's POST a CORS-simple request with no preflight, the same trap the Umami transport
avoids (T-37). Moving either one into a custom header is how the web channel would go quiet
without failing.

### 13.5 Alerting — what Sentry already does, and the one thing to turn OFF

**Creating a project creates an enabled alert rule with it**, measured 11/09/2026: *"Send a
notification for high priority issues"*, e-mailing the issue owners with fallthrough to active
members. So production alerts correctly **without anyone configuring anything** — which is the
good half of the surprise.

The bad half is that **dev got the same rule**, and it fired on the very first probe event. A QA
crash must not put a message in the same inbox that says production is on fire; that is the whole
reason the environments are two projects. **Disable (or delete) the dev project's rule**, and
leave production's alone:

| Project | Rule | What it should be |
|---|---|---|
| `entrelares-app` | https://irineu-pinheiro.sentry.io/monitors/alerts/3978315/ | **enabled** — this is the signal |
| `entrelares-app-dev` | https://irineu-pinheiro.sentry.io/monitors/alerts/3978316/ | **disabled** — dev proves the path, it does not wake anyone |

> **Where the UI keeps alerts.** Not under a top-level "Alerts" item — in this layout they live
> under **Monitors**. The direct rule URLs above come from the API and are the reliable way in;
> hunting for the word "Alerts" in the sidebar is how this was nearly declared impossible.

**T-68 shares this destination.** A failed publish is the same defect one floor up, and three
channels of ops signal is the same as none.
### 13.6 Source maps — making a web stack readable

Android release builds carry no obfuscation (`--obfuscate` is in no workflow), so their frames are
readable as they land. The web is the opposite: dart2js minifies, and a frame names a
`main.dart.js` offset. The issue still groups and counts correctly — it just says nothing about
where it happened. The first real proof of this was an accident: a local browser run reported
`Unable to load asset: "AssetManifest.bin.json"` as `minified:wB` in `Object.h`.

`deploy-web` closes that gap, in four steps that only make sense together:

1. the build gains **`--source-maps`**;
2. the release is named off the pubspec as **`entrelares-app@<version>`** — the exact string
   `CrashReporter.release` puts in every event. A release that does not match is an upload nobody
   ever asks for: the maps are there, the events are there, and they never meet;
3. `sentry-cli sourcemaps upload … --url-prefix '~/'` sends the maps (the frames carry absolute
   URLs, and `~/` is what makes an artifact match one);
4. **every `.map` is deleted before the publish** — always, token or not. Sentry has its copy; a
   map served from our own origin hands the whole Dart source to anyone who asks. The
   `//# sourceMappingURL=` line goes with it, so a devtools session does not fetch a 404 and read
   the deploy as broken.

`web_channel_test` pins all four, including the ORDER of (4) against the publish.

**No `sourcemaps inject`.** It stamps debug ids into the bundle and expects the events to carry
them back, which a hand-written client does not send. Matching here is by release + URL, which is
exactly why step 2 is worth a test.

**The secret this needs — armed 11/09/2026.** The upload step disarms itself while
`SENTRY_AUTH_TOKEN` is absent (the same shape as the Cloudflare publish beside it): the deploy
still publishes and the run summary says the stacks will read minified.

To arm it (or to rotate it): Sentry → Settings → **Organization Tokens** → Create New
Organization Token (https://irineu-pinheiro.sentry.io/settings/auth-tokens/new-token/), then add
the value as the repository secret `SENTRY_AUTH_TOKEN`
(https://github.com/irineus/entrelares-flutter/settings/secrets/actions).

**An organization token's scope is not chosen — it is fixed at `org:ci`**, which the screen spells
out as *Source Map Upload, Release Creation, Code Mappings*. That is exactly what the three
`sentry-cli` calls above use and nothing more, so there is no narrower option to pick and no
broader one to avoid. (A per-user token with `project:releases` would work too and is what most
docs describe; it is the worse choice here, because it dies with the person rather than with the
project.)

Verify on the next merge to `main`: the run summary stops carrying the "upload PULADO" line, and
the release appears under Sentry → Releases with its artifacts.
