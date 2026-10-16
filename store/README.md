# store/ — Google Play presence: listing, brand assets and the release checklist

Everything the **Play package `com.entrelares.app`** shows to a human being, versioned instead
of drafted in the Console: the listing copy in both languages, the brand masters and the script
that derives every icon from them, the feature graphic and its generator, and the answers the
Console's policy forms expect.

Since the T-53 cutover (23/08/2026) that package carries **this repository's Flutter bundle**.
Build and upload mechanics therefore live where the build does — [§6](#6--publishing-a-new-android-build)
points at them; this directory is about the *presence*, not the pipeline.

> **Where this came from (T-56, 24/08/2026).** These files spent their whole life in
> `entrelares-app-legacy/store/`, next to the runbook of the **TWA** shell that used to be the Android
> app: Bubblewrap, `twa-manifest.json`, the keystore ceremony, the version-code rule of a shell
> that wrapped a website. That half was the **dead package** — it did not travel, and retiring
> the legacy `com.guardacompartilhada.app` was its own item (**T-52**, closed 09/09/2026: the
> Play app was deleted and its `assetlinks.json` statement came out). What travelled is what is
> still true of a live store listing. Nothing here needs the old repository to be read.

---

## 1 · Store listing (PT-BR + en-US)

**Grow users → Store presence → Main store listing.**

- The copy is versioned here: [`listing-pt-BR.txt`](listing-pt-BR.txt) and
  [`listing-en-US.txt`](listing-en-US.txt) — app name, short description and full description,
  each under a `=== <label> (<= N …) ===` header that states Play's limit. **Since T-98
  (02/10/2026) nothing is pasted into the Console: edit the files → PR → after the merge,
  dispatch the `play-listing` workflow — dry run first, then for real — and approve it on the
  `play-production` Environment** ([§9](#9--publishing-the-listing--the-play-listing-workflow-t-98)).
  Never draft in the Console, and never edit the text there either: the next dispatch writes
  the files over whatever the Console holds.
- **Both files were re-verified sentence by sentence against the code on 28/08/2026 (T-57)**,
  and three claims moved. *"Funciona também offline"* / *"Works offline too"* was **deleted**:
  it was written for the Blazor PWA's service worker, the cutover falsified it, and **T-18 is
  still `pending`** — the whole app has exactly one mention of the word, in a comment. The
  real-time paragraph now says what the code does: live updates **with the app open**, and
  e-mail (`send-swap-email`) when it is closed, because **F-09, push, is `pending`**. And the
  PDF report is named as Premium, which is where `reports_pdf_tab.dart` gates it. In their
  place the bullet list gained the web channel, which does exist. **A listing is a claim about
  the system (the S-15 rule): re-read it against the code before every republish, and never
  publish a sentence a test could not defend.**
- **Re-verified again on 27/09/2026, after T-59 made the listing public** — a month of features
  had shipped past the 28/08 text. What moved, with the code that makes each sentence true:
  - **"aprovada automaticamente após 48 horas" was FALSE** since F-60: the window is anchored
    on the DAY's deadline (`schedule_date` + handoff time, `auto_approve_expired`), not on the
    request, and `auto_approval_copy_mirror_test` bans quoting the hours in any product
    sentence. The listing now says the reminder carries the exact day and time.
  - **"cada solicitação… chega por e-mail" was STALE**: push (F-09) is live on Android and the
    web (`_shared/push.ts` `PUSH_TYPES`); e-mail still carries the swaps, but a free family has
    a monthly e-mail cap and a Visualizador gets none — so no sentence says "every".
  - **"não pode ser editado nem apagado — por ninguém"** narrowed to *no family member*: a
    unanimous family deletion (S-11) erases the history.
  - **The caregivers paragraph** now says that caregivers beyond the free limit are Premium
    (`free_caregivers`), and names the **Visualizador** (F-50).
  - **Added, each live in production since S-22 (25/09/2026,
    `20260925100000_s22_phase6_live.sql`)**: the verifiable PDF (F-64), the child agenda
    (F-55 — notes free, the rest Premium), expenses and the Conversa (F-34/F-35, Premium);
    plus avisos (F-52), relatos do dia (F-67), Google sign-in (F-57/F-71), the dark theme
    (U-12), the Android offline month (T-18 — read-only, current month, Android only) and the
    Premium trial for new families. No number an operator can change is typed (U-57), no
    price (the store price is Play's), and the vocabulary is `vocabulary_test`'s.
  - en-US also stopped saying "after a divorce" (pt says *pais separados*) and "approved
    swaps" (read as if only approved swaps were free).
- **English translation** (the app is bilingual since U-13): the listing carries an **English
  (United States) – en-US** translation beside the default pt-BR, and `play-listing` writes
  both languages on every run — the file suffix is the Play locale code. The default language
  stays pt-BR, and it is chosen in the Console, not by the workflow.
- **Categories**: app category **Parenting** (fallback: Lifestyle). Tags: family, calendar.
- **Contact details**: e-mail `suporte@entrelares.app`; website `https://entrelares.app`.
- **Screenshots (phone)** — **generated from the app's own widgets since T-97 (02/10/2026)**:
  [`screenshots/pt-BR/`](screenshots/pt-BR/) and [`screenshots/en-US/`](screenshots/en-US/).
  See [§1.1](#11--phone-screenshots-generated-t-97). Play has carried the generated set since
  02/10/2026 (`play-listing` run 37088097075, 8 pt-BR + 8 en-US). The paragraph below is the
  T-57 set, which the Console carried until then and which the landing and
  `app/web/screenshots/` keep using.
- **The T-57 photographs** — current on the landing since 28/08/2026 ([T-57](../backlog/archive/phase-7.md)),
  and on the Console until T-97 replaced them there (02/10/2026). They are TWO sets: `pt-BR` from
  `entrelares-site/public/img/screenshots/`, `en-US` from `.../screenshots/en/`, eight frames
  each at 1080×1920 with a `webp`+`png` pair. They photograph the **Flutter** app in production
  configuration, under the U-27 visual system — the previous ones were the **Blazor** client,
  23/07/2026. The same item closed `entrelares-site`'s **L-21** (the English page had been
  serving the Portuguese captures).
  **Two things to know before re-shooting.** Never shoot the dev flavour: `environmentPrefix`
  puts `[Dev] ` at the head of every stored notification title, and no masking fixes a title.
  And the frames come off a phone at 20∶9, which Play does not take — the delivered set was
  cropped of its OS chrome and fitted to 9∶16 by replicating the edge column, which works only
  because the app's side edges are flat. The file names are a contract: the landing's
  `<picture>` elements and their `alt` text reference them.
  **A re-shoot has a THIRD copy to refresh (T-72, 14/09/2026):** six of the pt-BR `webp`
  (not `familia-membros`, not `assistente-rotacao-com-avo`) live in `app/web/screenshots/` too,
  because `web/manifest.json` names them and the web channel's `img-src` allows only its own
  origin — pointed at the landing, Chrome fetched them on every load and our CSP refused all
  six. Copy them over in the same delivery; `web_channel_test` fails a `src` that does not ship.

### 1.1 · Phone screenshots, generated (T-97)

**One command regenerates both sets:**

```
cd app && fvm flutter test store_screenshots/
```

It writes `store/screenshots/pt-BR/phone-<n>.png` and `store/screenshots/en-US/phone-<n>.png`,
1080×1920 (Play's 9∶16), numbered in **listing order**, and empties both folders of
`phone-*.png` first — a scene taken out of the list cannot leave an old image behind to be
uploaded by mistake. A run takes about 20 seconds.

**Nothing on the phone is drawn by hand.** The harness (`app/store_screenshots/`) pumps the
app's real shell and screens — `HomeShell` with the five branches `main.dart` builds, every
module flag at its production value (S-22, F-75, F-07) — against the same
`FakeCustodyDataSource` the widget suites use (`test/calendar_slice_test.dart`), filled with a
**fictional family**: Ana (mother, the signed-in admin) and Bruno (father), Lia and Theo, the
grandmother Rosa and the nanny Carla as a Visualizador. The phone is the 360×740 dp screen the
U-32 suite measures every page on, in the light theme, with the real Inter and Material icons
loaded from the test bundle's `FontManifest.json`; a finger opens sheets and switches tabs the
way the widget suites do. `store_frame.dart` only places that screen inside a phone outline
under a fixed caption band (same phone size and position on every image), every colour a
`tokens.dart` token. What the family typed — the swap message, the Conversa, the expenses, the
agenda — is written in each screenshot's language.

**Why it is not in CI.** The directory sits outside `test/`, and the CI's bare `flutter test`
discovers `test/` only, so the gate never renders PNGs. `flutter analyze` does read it — it has
to stay clean — and it imports the fakes from `test/`, so a change to the data source interface
that breaks it shows up there.

**The dates move with the run.** The calendar reads `DateTime.now()` and takes no clock, so
every date in the fixture is relative to the day the command runs: the month on screen is
always the current one, populated. The flip side is that two runs on different days produce
different images — **regenerate, then approve what was regenerated**.

| n | Screen | PT-BR caption | en-US caption | Plan |
|---|---|---|---|---|
| 1 | Calendar: the month, today's caregiver card, a swapped day, a pending request's bell | Quem fica com as crianças, dia a dia | Who has the kids, day by day | Free — two caregivers, no module |
| 2 | Day sheet: Bruno's pending swap request with his message, Aprovar/Recusar | Trocas de dia pedidas e respondidas no app | Day swaps, asked and answered in the app | Free — swaps have no gate |
| 3 | Relatórios → PDF: the year's report generated, the verifiable reports issued | Relatório em PDF verificável | A verifiable PDF report | **Premium** — `reports_pdf_tab.dart` shows the upsell when `!_isPremium`; the QR (F-64) is issued only for Premium |
| 4 | Família: two parents, the grandmother as a third caregiver, the nanny as Visualizador | Avó, babá e quem mais cuida | Grandma, the nanny and everyone who helps | **Premium** — a third caregiver is beyond `free_caregivers` |
| 5 | Day sheet: a day's agenda for both children | A agenda de cada criança | Each child's agenda | **Premium** — every kind but the note (`AgendaKind.isStructured`, `agenda.premium_only`) |
| 6 | Comunicação → Conversa: the permanent-record notice, two messages, a cited day | A conversa da família, registrada | The family chat, on record | **Premium** — `chat.premium_only` (`chat_view.dart`) |
| 7 | Despesas: the balance, the activity list | As despesas das crianças, divididas | The kids' expenses, shared | **Premium** — `expenses.premium_only` (`expenses_screen.dart`) |
| 8 | Relatórios → Resumo: the year in days per parent | Quantos dias com cada um | How many days with each parent | Free — the Resumo has no gate |

Each caption also has a one-line detail under the headline (in `store_screenshots_test.dart`,
next to the scene). The rules the captions follow are the listing's: **every sentence true of
the code (S-15)**; **a Premium scene carries the "Premium" pill**, so no image sells a Premium
feature as free; **no number an operator can change** — trial days, months of calendar,
caregiver counts (U-57); no emoji (U-31). The harness fails a caption that does not fit its
two lines, and an overflow anywhere on the phone fails the scene, as it does in the widget
suites.

**The owner approves the PNGs before `play-listing` uploads them** (§9; the first set was approved on 02/10/2026). Play serves its own copies: the
pt-BR set goes to the Main store listing's *Phone screenshots*, the en-US set to *Manage
translations → English (United States)*. A change to a screen, a caption or the scene list
means a new run, a new look, and a new approval.

## 2 · Brand assets

**Since U-29 (26/08/2026) the app's mark is drawn, not generated.** The owner's concept: a
calendar card whose **day cells draw the two interlocked houses** — the blue house and the amber
house wear the calendar's own day colours, the cells where they interlace are the rose
`#E11D48`, each house keeps a card-coloured "door" (an empty day), and the today ring sits on a
shared day. Launcher background: the brand indigo `#4F46E5`. Every colour is a token from
`app/lib/theme/tokens.dart` — the icon is the calendar screen, abstracted.

The **script is the source**: the geometry lives as data in
[`brand-icons.py`](brand-icons.py) (pure Pillow — `python3 store/brand-icons.py`), which also
writes [`brand-calendario.svg`](brand-calendario.svg) as the vector artifact. Changing the art
means editing the script and re-running it — never editing a PNG by hand.

| File | What it is |
|---|---|
| [`brand-icons.py`](brand-icons.py) | Draws the mark and derives every icon file below. THE source. |
| [`brand-calendario.svg`](brand-calendario.svg) | Vector rendition, written by the script — for print/large-format use, never edited by hand. |
| [`store_icon.png`](store_icon.png) | 512², the Play listing icon. **Written by the script since T-57** (28/08/2026), at its own framing — see below. |

**The clay masters are gone from this directory (T-57, 28/08/2026).** `brand-emblema.png` and
`brand-emblema-flat.png` were the AI-generated F-54 artwork, and they were kept here after U-29
retired the art — on the belief that the landing still needed them. It does not: the landing
carries its OWN copies in `entrelares-site/assets-src/`, and its generators read from there. So
this pair was read by nothing at all, which is the worst state for a 2.4 MB binary with no vector
source. Older records (`backlog/archive/phase-7.md`, `docs/changelog-blazor.md`) still name the
paths, correctly, as history — **the files are in git, and a live copy sits in the landing repo
until its own half of T-57 retires it.**

`brand-icons.py` writes, and these are the ONLY places the mark is vendored:

```
app/web/favicon.png                     (96, squircle)
app/web/icons/Icon-{192,512}.png        (full-bleed)
app/web/icons/Icon-maskable-{192,512}.png
app/assets/brand/emblema.png            (512, indigo squircle —
    legacy launchers AND the native splash bitmap)
app/assets/brand/emblema-maskable.png   (512, adaptive
    FOREGROUND: transparent, mark inside the 66% safe zone)
app/assets/brand/emblema-monochrome.png (512, the Android 13
    themed-icon glyph)
store/brand-calendario.svg
store/store_icon.png                                    (512, the Play LISTING
    icon — full-bleed indigo, mark at 60%)
```

The three `assets/brand/` files are what `flutter_launcher_icons` reads (config block in
`app/pubspec.yaml`: indigo adaptive background, zero foreground inset because
the script already composes the safe zone, plus the monochrome layer). After running the script:
`fvm dart run flutter_launcher_icons` refreshes the mipmaps and the adaptive XML.

**Why `store_icon.png` is written by the script again.** It was deliberately NOT an output
between 26/08 and 28/08/2026: the Play **listing** had to stay on the clay emblem until the
listing art moved as a WHOLE — screenshots, feature graphic and icon together — and a routine
re-run of the script could not be allowed to push a rebrand into the store behind that owner
decision. **T-57 is that whole**, so the hold is discharged and `store_listing()` writes the
512². It keeps its OWN framing — the mark at **60%**, against the PWA's 66% — because Play
applies its own rounding and masks the icon to a circle in some surfaces; that crop is exactly
why the old file used to be hand-supplied, and a separate function is what stops one framing
from drifting into the other. **The PNG is only half the delivery: Play serves its own copy,
so the file has to be re-uploaded in the Console.**

The landing repo's favicon and OG art are still on the clay masters, behind their own copy of
this script (`entrelares-site/assets-src/brand-icons.py`). Moving them is T-57's landing half,
and it happens in that repo.

### The one mark in this app that is NOT ours (U-45, 10/09/2026)

`app/assets/brand/google-g.png` (+ `2.0x/`, `3.0x/`) is Google's "G", used under
the *Sign in with Google* [branding guidelines](https://developers.google.com/identity/branding-guidelines).
It is **Google's trademark, not ours**: it may not be recoloured, redrawn, rotated or distorted,
which is exactly why it ships as an IMAGE and never as an icon font or a painter — and why its
colours are the one palette in the app that does not answer to `tokens.dart`. The rest of the
button's spec (surface, stroke, ink, 40 dp, 4 dp corners, 12/10/12 padding) lives in
`GoogleBrand`, inside `tokens.dart`, because that file is the only place a colour may be spelled
out and `no_color_literal_test` keeps it that way.

Provenance, so a future refresh of the mark is a re-run and not an archaeology dig:

```
master:  https://developers.google.com/identity/images/g-logo.png   (200×204, RGBA)
checked: against the official pack, https://developers.google.com/static/identity/images/signin-assets.zip
         → "Android + Web/PNG @4x/Light/…Show text=Yes, Shape=Square…" — the G there measures
           79×80 px at @4x (19.75×20 dp), 12 dp from the left edge, in a 40 dp button. That
           button is also where the height, the 4 dp corner and the paddings were MEASURED: the
           guidelines page states the colours and the paddings, not the geometry.
derived: scaled to fit a 20 dp square, centred, at 1×/2×/3× (20/40/60 px, ~9 KB total)
```

```python
from PIL import Image                      # run from app/assets/brand/
m = Image.open('g-logo.png').convert('RGBA')
for scale, out in ((1, 'google-g.png'), (2, '2.0x/google-g.png'), (3, '3.0x/google-g.png')):
    side = 20 * scale
    g = m.resize((round(m.width * side / m.height), side), Image.LANCZOS)
    box = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    box.paste(g, ((side - g.width) // 2, 0), g)   # fit by HEIGHT, never squashed
    box.save(out, optimize=True)
```

The pack's own pre-rendered buttons are deliberately NOT used: they carry the sentence baked in,
in English only, and this product writes it in the reader's language (`KApp.authGoogle`).

## 3 · Feature graphic (1024×500, required)

**Both languages have a generator since T-57 (28/08/2026), and both are on the new mark.**

| Render | Source |
|---|---|
| [`feature-graphic.png`](feature-graphic.png) | [`feature-graphic.html`](feature-graphic.html) |
| [`feature-graphic-english.png`](feature-graphic-english.png) | [`feature-graphic-english.html`](feature-graphic-english.html) |

Headless Chrome renders them — the exact command, and the crop workaround for builds that
subtract window chrome from `--window-size`, are in the PT-BR file's header comment. The two
files are the same layout in two languages, so **a layout change has to be made in both**.

The plaque is [`store_icon.png`](store_icon.png) shown 1∶1, so the graphic cannot drift from the
launcher: **re-run `brand-icons.py` first**, then re-render. The palette is the U-27 token set
(`surface`, `text`, `textMuted`, `accent`, `swapped`); the cream/navy of the clay era went with
the emblem.

Re-render whenever the tagline or the mark changes, and **re-upload both**: Play serves its own
copy and nothing updates it automatically (the en-US one at *Manage translations → English
(United States)*).

> **What the English file used to be.** Until T-57 it was a 2950×1440 clay render from
> 13/08/2026 with no source — exactly Play's 2.048∶1 ratio, but the form takes 1024×500, so the
> en-US listing could only show the Portuguese graphic or a stretched one. U-29 retired the art
> it drew; the generator above replaced the file.

## 4 · Policy forms (Data Safety, content rating, app access)

**Monitor and improve → Policy → App content.** The answers below map the shipped privacy policy
(https://entrelares.app/privacidade) — **if the policy changes, re-answer.** Every
declaration on that page must be ✅ before a release rolls out, and the Console does not always
say which one is blocking: sweep the whole list.

- **Privacy policy URL**: `https://entrelares.app/privacidade` — **no `.html`**: the Worker redirects the
  extension away, and a URL declared to a third party names the form that answers 200 (S-19, L-23).
  The field held the bouncing form until S-18; re-paste it in the same sitting as the table below.
- **App access** — the declaration that rejects apps whose reviewers cannot get in. The whole app
  sits behind login, so answer **"All or some functionality in my app is restricted"** and add an
  instruction set with a REAL test account (a dedicated reviewer account created through the
  normal sign-up, kept in the password manager as "Entrelares — Play reviewer account").
  Instructions: *"Log in with the credentials provided; the custody calendar is the home screen.
  All features are reachable from the bottom navigation."* Keep the account alive — Google
  re-reviews on later releases too.
- **Data Safety** — declare. **Re-verified against the CODE on 12/09/2026 (S-18) and again on
  24/09/2026 for phase 6 (S-22: F-55, F-50, F-64, F-34, F-35)** and on 03/10/2026 for the
  referral (F-82 — no new data type, see *Other actions*), the way the
  listing was in T-57: every row names the function or table that makes it true, so the next
  sweep compares the row with the code and not with the previous sweep. The Console form is
  answered by the owner from this table; **step 5 of the wizard (*Preview*) must match it line
  for line, in both directions** — nothing declared that the code does not do, nothing the code
  does left out.
  | Data type | Collected? | Shared? | Purpose | Notes — what in the code makes it true |
  |---|---|---|---|---|
  | Personal info → Name | Yes — required, linked | No | App functionality | `profiles.name`, shown to the family; since **F-55** also `children.first_name` — the child's first name, typed by the family's admin (`add_child`), the ONLY dedicated child field |
  | Personal info → Email address | Yes — required, linked | No | App functionality | GoTrue login + the transactional e-mails (`send-*-email`); since F-68 also the reply address of a support request (`support_requests.reply_email`, typed by a signed-out person) |
  | Personal info → User IDs | Yes — required, linked | No | App functionality | the account id (`auth.uid()` / `profiles.id`); Play's own example of a User ID is *"an account ID"* |
  | Financial info → Other financial info | Yes — optional, linked | No | App functionality | **F-34** `expenses` (amount in cents, category, description, date, who paid) + `expense_shares` + `expense_settlements` (payments between caregivers, confirmed by the receiver; since **F-93** an optional `reference` the payer types — e.g. the Pix transaction id — and an optional `answer_note` the receiver writes with the answer, both read by the family's caregivers in the app and the PDF) + the append-only `expense_history`. Typed by the caregivers; no payment instrument, no money moved; never shown to a viewer |
| Financial info → Purchase history | Yes — required, linked | No | App functionality | `billing-store-verify` writes `subscriptions.store_purchase_token` and the `billing_events` ledger; the RTDN webhook writes the lifecycle. **Marked 25/08/2026** — the store rail is LIVE since 23/08 |
  | Messages → Other in-app messages | Yes — optional, linked | No | App functionality | F-44 `request_message` / `approval_note` / `rejection_reason`: free text one caregiver writes, the server stores, the OTHER caregiver reads — inside the app, the e-mail and the push. Since **F-68** also the *Ajuda e contato* message (`send-support-request` → `support_requests.message`, 12-month retention), read by the team. Since **F-35** the family chat: `chat_messages.body` (`send_chat_message`), permanent, read by the whole family (viewers included); its first 140 characters reach the `chat_message` push ONLY for a reader who turned the preview on (S-27, 08/10/2026 — default: "Nova mensagem de <Nome> na Conversa"). The collected data and this answer do not change |
  | App info and performance → Other app performance data | Yes — optional, linked | No | App functionality | F-68: only when *Incluir informações técnicas* stays ticked — app version, channel, OS/browser family, language, the route with no query (`support_requests.diagnostics`, the function keeps five keys and drops the rest) |
  | App activity → Other user-generated content | Yes — optional, linked | No | App functionality | Since **F-55** the agenda: `child_events` (kind, times, `body`, child; the day notes are converted into agenda Notes at S-22) and `child_routines`; before it `care_schedules.notes` (the day note), `families.name` and, since **F-67** (21/09/2026), `day_accounts.body` — the *relato do dia*, free text a member appends to a past day, read by the family and printed in the F-33 PDF (same category, same operator, so the Console answer does not change); and, since **F-75** (28/09/2026, behind `feature.day_account_replies`), `day_account_replies.body` — another caregiver's reply appended under a relato, read by the family and printed with it (same category again, no Console change) — Play's own example of this row is *"notes"* |
  | App activity → Other actions | Yes — optional, linked | No | App functionality | **F-35** `chat_reads` — who read which chat text and when, shown to the family; `chat_prefs.push_muted`. **F-64** `report_attestations` — that a verifiable PDF was issued: period, a summary of counts with caregivers as INITIALS, the SHA-256 of the file (no document body), public by an unguessable id, purged after `report_attestation.valid_months`. Since **F-82** (03/10/2026, the referral of F-80 turned on): `family_referrals` — which family a NEW family came from (the referring family, the code, the sign-up channel `web`/`android`, the status and its dates: first payment, end of the refund window, reward or cancellation and why) and `family_referral_codes` (one random 10-symbol code per family); service role only, no family reads either table. On Android the code arrives through the **Play Install Referrer** (`install_referrer.dart` + `InstallReferrerChannel.kt`), read once at sign-up: only the `ref` value is kept (`ReferralRules.codeFromInstallReferrer`), the rest of the string is discarded and nothing is written on the device. Same category, same purpose and same operator as this row's other sources, so the Console answer does not change — policy 2.1 §3/§7/§11 name it |
| App activity → App interactions | Yes — required, **linked** (since T-78) | No | Analytics | Two sources, one row — Play asks per data TYPE, so the stricter answer wins. (1) Umami (`analytics_service.dart`): cookieless, no device id, paths sanitized by `sanitizeAnalyticsPath`; dev flavour sends nothing — not linked on its own. (2) **T-78 (23/09/2026)**: `member_activity_days` — one row per member × day (America/Sao_Paulo) × channel (`android`/`web`/`web-installed`) the app was used on, written by `touch_activity`; no hour, no IP, no user agent; service role only (no family member reads it); purged after 400 days and when the account is removed. That row IS linked to the account, so the whole type is. Policy §3/§11 name it. (3) **T-101 (04/10/2026)**: `families.acquisition_source` + `acquisition_campaign` — where a NEW family came from (a closed word: `google_app`, `google_search`, `meta`, `referral`, `organic`, `unknown`, and our own ad-campaign token), written ONCE at creation by a server trigger; on Android decided from the **Play Install Referrer** at sign-up (`AcquisitionRules.fromInstallReferrer`: only the verdict and the token leave the device, the string is never sent nor stored), on the web from `/register?src=…&cmp=…`. No pixel, no SDK, no new operator; the bulletin (T-99) reads it as counts per source. Same type, same purpose (Analytics), so the Console answer does not change — policy §3 names it |
  | App info and performance → Crash logs | Yes — not linked | No | Analytics | T-66 crash sink (Sentry): exception type, scrubbed message, stack, release/environment/channel — no user, no breadcrumbs, no route args (`crash_rules.dart`) |
  | Location → Approximate location | Yes — not linked | No | Analytics | NOT requested from the device: Sentry derives country + city from the IP of the crash report at ingest and KEEPS it after discarding the address (measured, T-66). The policy §7 says so since L-24, so the form has to |
  | Device or other IDs | Yes — optional, linked | No | App functionality | the FCM registration token (`push_subscriptions.token`), written only after the user turns push on (F-09); Play's own example of this row is *"Firebase installation ID"* |
  | Health and fitness → Health info | Yes — optional, linked | No | App functionality | **F-55** agenda items of kind `health` / `medicine` (`child_events.kind`): the family may record a child's appointment or medicine time, and whatever it types there. Nothing is requested beyond the kind; declared conservatively because the category exists in the product (owner's call at S-22) |
| Contacts, photos, files, calendar (device), precise location | No | — | — | never requested; the "calendar" is ours, not the device's |
  **"Shared" is No on every row on purpose.** Play's definition of sharing excludes transfers to a
  *service provider* processing on the developer's behalf, and that is what every operator in
  the policy's §7 is (Supabase, Resend, Cloudflare, Google — Fonts, FCM, Play, Gmail —, Umami, Sentry,
  Asaas). Nothing goes to a third party for its own purposes; §4 of the policy says the same.
  **The offline copy of the calendar adds NO row (T-18, 14/09/2026).** The Android app keeps the
  last-read current month, the 90-day upcoming window, that month's open requests and the family's
  profiles on the device (`offline_cache.dart`), so the plan can be read with no signal. Play
  counts data as *collected* only when it is transmitted off the device, and this copy never is:
  it lives in the app's cache directory (`offline_cache_store_io.dart`), which Android Auto Backup
  never copies — **not** `shared_preferences`, which it does — and it is wiped on every exit from
  the authenticated phase (`main.dart` `_setPhase`). Every item in it is already a row above,
  collected when the server sent it. If the copy ever moves to a backed-up location, that stops
  being true: re-read this paragraph in the same delivery. §9 of the policy names it.
  **Account creation** lists both `Username, password, and other authentication` **and** `OAuth`
  (F-57; ticked 10/09/2026 — see below). **Every row is deletable** by the user: leaving the family
  (S-19 page) removes the profile and its push tokens after the 30-day grace, and the family's own
  data — days, notes, messages, subscription — goes with the family when it is deleted.
  - Data is **encrypted in transit** (HTTPS only): Yes.
  - **Account creation** — the form asks HOW an account is created, and the answer lists
    **`Username, password, and other authentication`** *and* **`OAuth`**, ticked on 10/09/2026.
    The declaration of 25/08 had only the first, two days before Google sign-in (**F-57**)
    shipped: true when written, false the week after. This is the S-15 rule biting in the
    Console instead of in the policy — a declaration ages the moment the code moves.
  - **Deletion — TWO URL fields, both answered on 10/09/2026 with the public page (S-19).**
    They had held `https://web.entrelares.app/profile`, and that address is not a route this
    app serves: the real one is `/family/profile`, nested under `/family` (`main.dart`), so an unknown
    path lands on the T-64 `NotFoundScreen`; and without a session it lands on the login,
    which forgets where it was going — the T-64 gate keeps NO remembered destination, on
    purpose. Give both fields the public page **`https://entrelares.app/exclusao-de-conta`** —
    **no `.html`**, which is the address that answers 200: Cloudflare's static assets redirect
    the extension away (measured on the preview right after the deploy), which is also why the
    app links `/privacidade` without it. Declaring the bouncing form hands the reviewer a
    redirect for nothing. The page lives in `entrelares-site`, and it is what the three bullets
    beside the field actually ask for: name the app, **show the steps**, and **say what is
    deleted, what is kept and for how long**. A screen behind a login does none of the three.
    - *Delete account URL* — the page's first half: sign in at `web.entrelares.app` (the same
      client, with the same danger zone, so nobody needs the app installed) → **Perfil** →
      **Sair da família…** / **Excluir família…**.
    - *Delete data URL* (the optional "delete some data without deleting the account" — answered
      **Yes**) — the page's *"Apagar dados sem excluir a conta"* section: the LGPD art. 18
      rights exercised through `privacidade@entrelares.app`, including the by-annotation
      correction the immutable history requires.
    - `privacidade@entrelares.app` stays as the channel for whoever cannot sign in. It is no
      longer the only channel for a Google account: deletion is sudo-gated (S-10), and since
      **S-21** the gate takes a second proof — a one-time code mailed to the account — so a
      session with no password confirms and deletes like any other. The caveat this line carried
      on 10/09/2026 was true for exactly one day, and it is the reason the item existed: the
      declared URL promises a path a STRANGER can walk, and three of the four affected accounts
      were the sole admin of a one-seat family, i.e. people with no in-app way out at all.
  - The consent log stores the accepting IP (disclosed in the policy) — server-side
    security/audit data tied to the account; declare it under Personal info only if the form's
    current wording requires IP disclosure (re-read the help text at fill time).
  - **Why this table had to be rewritten (S-18, 12/09/2026).** The first version was answered on
    25/08/2026 with *Financial info → No* and a caveat written in the future tense — *"the day
    that switch is flipped"* — when `billing.store_enabled` had been `true` since **23/08**. Then
    F-09 (29/08) put a device token in the database, F-57 (27/08) added OAuth, T-66 (11/09) sent
    crash reports to a third party, and each of them moved the code without anyone re-reading
    this form. **A store declaration is a claim about the system, and it ages the moment the
    code moves** — the S-15 rule, which is also why the rows above cite the code that makes
    them true. Sweep this table in every item that adds an operator, a token, a sink or a
    free-text field, in the same delivery, together with the policy's §7. What Play does and
    does not ask about IAP is unchanged: nothing on the App content page, Play derives it from
    the products in *Monetize → Subscriptions* ([`supabase/README.md`](../supabase/README.md)
    §9-bis).
- **Content rating questionnaire**: category *Utility/Productivity*; no violence, no user-to-user
  public content (messages are private within a family), no gambling → expected rating L/3+.
  **Since F-35 (S-22) users DO communicate with each other** — the family chat, private to the
  family, with no moderation. Re-answer the questionnaire's user-interaction question **Yes**
  (private messaging between known users) in the same sitting as the Data safety table.
- **Target audience**: 18+ (parents/guardians). The app is **not** child-directed — the child is
  the *subject* of the calendar; no child accounts exist. Since **F-55** the family records the
  child's **first name** and an agenda about the child (including Saúde/Remédio items) — data
  ABOUT a child typed by the parents, declared above, never an account or an interface for a
  child.
- **Ads**: No ads.

## 5 · Closed test → production

A personal Play account must run a closed test before production: currently ~12 opted-in testers
for **14 uninterrupted days** (re-verify the rule at
https://support.google.com/googleplay/android-developer/answer/14151465 — it changes). That is
calendar time, so recruit testers early rather than when a build is ready.

1. **Testing → Closed testing → track**: watch the tester count; the Console shows progress
   toward production access.
2. When eligible, **Apply for production access** (the Console prompts), then **Test and release
   → Production → Create release**, upload the AAB and roll out.
3. Release notes in PT-BR. The Blazor client's release notes are frozen history in
   [`docs/changelog-blazor.md`](../docs/changelog-blazor.md); a Flutter release describes what
   this repo shipped since the previous upload.
4. **The closed test ends carrying a promise (F-53).** The recruitment message of 11/08/2026
   promised every tester **permanent Premium for their family**, and nothing grants it
   automatically — it is one operator action per family. The cutoff (accounts created
   11/08/2026 → 01/09/2026) and the exact procedure are in
   [`supabase/README.md`](../supabase/README.md) §12. Do it **before** the track goes public:
   these are the product's first users, and the promise is already public.

> **The closed test ended on 01/09/2026, and the listing is PUBLIC since 25/09/2026.** Production
> access (granted 21/09/2026), the launch checklist and the risks accepted for it are recorded on
> the **T-59** card ([board](https://app.notion.com/3c82f3f4b9b2810aaff5e49014f748ef)), not here —
> `backlog/` stopped being the record on 07/09/2026 (T-63). The Closed testing – Alpha track is
> retired (T-79): new builds climb Internal → Production only, as §6 describes.

## 6 · Publishing a new Android build — the pipeline (T-79, 22/09/2026)

No `.aab` is built on anyone's machine any more. Two steps, one of them the owner's:

1. **Merge → Internal testing, automatically.** The `play-internal` job of `verify.yml` runs
   after the three gates and `db-prod`. It compares the pubspec `versionCode` with every Play
   track: a NEW code is built (`flutter build appbundle --release --flavor prod`, upload key
   from the `play-internal` Environment) and sent to **Internal testing**, the ONE testing
   track (owner, 22/09/2026 — no Google review per release, up to 100 testers by e-mail list).
   An EQUAL code uploads nothing and says so; a LOWER one fails `main` and names both numbers.
   Closed testing – Alpha receives nothing any more.
2. **Owner → Production.** Actions → **play-promote** → *Run workflow* on `main`, then
   **Approve** the run on the `play-production` Environment. `promote` sends the build Internal
   holds (or a given `version_code`) to Production at a `fraction` — below 1 is a staged
   rollout — with no rebuild; `rollout` moves the fraction (1 completes it); `halt` pauses it
   (give the fraction that is live); a halted rollout resumes by promoting again. `dry_run`
   validates with Play and commits nothing.

**Release notes are required at promotion, and only there** (owner, 22/09/2026). Before the
dispatch, a small PR adds `store/release-notes/<versionCode>/pt-BR.txt` and `en-US.txt`, at most
**500 characters** each (Play's limit), describing what changed in the APP since the build
Production has now: leave out docs, CI, web-only and server-only changes. `play_release_test`
checks every folder on the way in, and the lane refuses a promotion without both files.

- `--flavor prod` is not optional: it is what selects the production Supabase project **and** the
  `com.entrelares.app` application id. A flavour-less build resolves to dev by construction.
- **Release signing** reads `prod.*` from `app/android/key.properties`, which the job writes for
  its own lifetime from the Environment secrets; each flavour signs by its OWN entries (T-79), so
  a local fallback build (the command above, with the owner's full file) still works unchanged.
- **Version**: `version:` in `pubspec.yaml` feeds both halves — the name (`2.0.0`) and the build
  number after `+`, which becomes Android's `versionCode`. **Every upload needs a higher
  `versionCode` than the last**, and a code is burned by the UPLOAD, not by the rollout.
  **Bump policy (owner decision, 27/08/2026):** `2.0.0` opened the Flutter generation (the
  Blazor client retired at `1.8.15`; the spike's `0.2.x` never graduated at the cutover).
  Per MERGED PR: MINOR when it delivers a backlog item, PATCH for fixes/polish, MAJOR only by
  owner decision, and `+N` rises on every merge to `main` — the full text lives as the
  comment above `version:` in the pubspec, next to the number it governs.
- The pipeline authenticates with its OWN service account (`PLAY_RELEASE_SERVICE_ACCOUNT`,
  release permissions on this package only), never with the billing one below.
- The Play Billing side of the account (products, RTDN, the service account the server uses to
  verify a purchase) is configured once, in [`supabase/README.md`](../supabase/README.md) §9-bis.

## 7 · Store-context rule (app behaviour)

Play's payments policy forbids steering a Play-distributed app's users to an external purchase
flow. The app therefore never shows the website checkout on the store build: the Android target
sells through **Play Billing** behind `billing.store_enabled`, and while that switch is `false` —
or the device has no store, or no product comes back — the store branch shows the **T-38 neutral
note** ("manage your subscription on the website": no price, no checkout link), which is also the
fail-closed default. The web target keeps the Asaas rail. Never add a store-visible link straight
into the web checkout.

## 8 · App Links (`assetlinks.json`)

The pairing that keeps the installed app full-screen and lets it own its own URLs lives on the
**web side**: `app/web/.well-known/assetlinks.json`, published with the web
channel at `web.entrelares.app`. It carries two statements — `com.entrelares.flutter` (the dev
flavour) and `com.entrelares.app` (upload + app-signing fingerprints). A third one named the
legacy `com.guardacompartilhada.app` and came out with **T-52** (09/09/2026), once that Play app
was deleted; `web_channel_test` now asserts its ABSENCE, so it cannot drift back in. If the
browser bar ever comes back on an installed app, that file in PRODUCTION is the first thing to
check.

## 9 · Publishing the listing — the `play-listing` workflow (T-98)

The Main store listing leaves `store/` the way a build does: through a workflow the owner
dispatches and approves, never through the Console's text boxes (owner, 02/10/2026).

1. **Edit `listing-pt-BR.txt` / `listing-en-US.txt` in a PR.** `app/test/play_listing_test.dart`
   parses both with the rules the lane uses and fails the PR on a broken file or a field over
   Play's limit — **30** (name), **80** (short), **4000** (full) characters. The format: three
   `=== <label> (<= N …) ===` headers, in the order name → short → full; the `N` must be Play's
   limit for that position, so a swapped section is refused; each text is everything up to the
   next header, trimmed; name and short are one line. The test reads the header pattern and the
   field order from the Fastfile, so the two cannot drift.
2. **After the merge — dry run.** [Actions → play-listing](https://github.com/irineus/entrelares-app/actions/workflows/play-listing.yml)
   → *Run workflow* on `main`, `dry_run` ticked (the default) → **Approve** on `play-production`.
   Play validates the whole edit and nothing is committed; the run summary lists the
   character count of every field.
3. **For real.** The same dispatch with `dry_run` unticked, approved again. **A green run means
   the change was SENT, not that it is live**: Google reviews a listing change like a release,
   and the Console's **Publishing overview** says when it is published.
4. **Screenshots** go up only with `upload_screenshots` ticked (default off), and only after the
   owner approved the PNGs. Each language's phone set is then **replaced** by
   `store/screenshots/<lang>/phone-<n>.png` — 2 to 8 files, numbered from 1 with no gap, shown in
   that order; an identical prefix already on Play is kept, the rest deleted and re-sent. A
   language with no folder keeps exactly what Play has.

What the lane never touches: binaries, tracks, release notes, the icon, the feature graphic
(both still re-uploaded by hand, §2/§3), the promo video, categories and contact details. supply
hangs a metadata edit on one release of a track, so the lane names the build **Internal testing**
holds — read, not changed; Internal must hold a build (it always has since T-79). The job shares
the `play-production` concurrency group with `play-promote`: one Play edit from the owner's
workflows at a time.

**The service account.** The workflow authenticates as `PLAY_RELEASE_SERVICE_ACCOUNT`, the
release account of T-79 (Environment secret), which needs, on this app, the Play Console
permission to edit the store listing — **Manage store presence** — besides the release ones.
There are **two** service accounts on this Play account, and they are easy to mix up: the
**billing** one (`PLAY_SERVICE_ACCOUNT`, read by the Edge Functions to verify purchases,
[`supabase/README.md`](../supabase/README.md) §9-bis) and the **release** one. A run that fails
with *"The caller does not have permission"* almost always means the permission was granted to
the OTHER account: compare the `client_email` inside the secret's JSON with the list in
**Users and permissions** before changing anything else.
