# store/ — Google Play presence: listing, brand assets and the release checklist

Everything the **Play package `com.entrelares.app`** shows to a human being, versioned instead
of drafted in the Console: the listing copy in both languages, the brand masters and the script
that derives every icon from them, the feature graphic and its generator, and the answers the
Console's policy forms expect.

Since the T-53 cutover (23/08/2026) that package carries **this repository's Flutter bundle**.
Build and upload mechanics therefore live where the build does — [§6](#6--publishing-a-new-android-build)
points at them; this directory is about the *presence*, not the pipeline.

> **Where this came from (T-56, 24/08/2026).** These files spent their whole life in
> `entrelares-app/store/`, next to the runbook of the **TWA** shell that used to be the Android
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
  with the Play character limits noted inline. **Edit the files, review in a PR, then paste into
  the Console** — never draft in the Console directly, where nothing is versioned.
- **Both files were re-verified sentence by sentence against the code on 28/08/2026 (T-57)**,
  and three claims moved. *"Funciona também offline"* / *"Works offline too"* was **deleted**:
  it was written for the Blazor PWA's service worker, the cutover falsified it, and **T-18 is
  still `pending`** — the whole app has exactly one mention of the word, in a comment. The
  real-time paragraph now says what the code does: live updates **with the app open**, and
  e-mail (`send-swap-email`) when it is closed, because **F-09, push, is `pending`**. And the
  PDF report is named as Premium, which is where `reports_pdf_tab.dart` gates it. In their
  place the bullet list gained the web channel, which does exist. **A listing is a claim about
  the system (the S-15 rule): re-read it against the code before every republish, and never
  paste a sentence a test could not defend.**
- **English translation** (the app is bilingual since U-13): at the top of the Main store
  listing page → **Manage translations** → **Add your own translation** → **English (United
  States) – en-US** → paste from `listing-en-US.txt`. The default language stays pt-BR.
- **Categories**: app category **Parenting** (fallback: Lifestyle). Tags: family, calendar.
- **Contact details**: e-mail `suporte@entrelares.app`; website `https://entrelares.app`.
- **Screenshots (phone)** — **current since 28/08/2026** ([T-57](../backlog/archive/phase-7.md)).
  The Console and the landing share one set, and it is now TWO sets: `pt-BR` from
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

## 2 · Brand assets

**Since U-29 (26/08/2026) the app's mark is drawn, not generated.** The owner's concept: a
calendar card whose **day cells draw the two interlocked houses** — the blue house and the amber
house wear the calendar's own day colours, the cells where they interlace are the rose
`#E11D48`, each house keeps a card-coloured "door" (an empty day), and the today ring sits on a
shared day. Launcher background: the brand indigo `#4F46E5`. Every colour is a token from
`apps/entrelares_app/lib/theme/tokens.dart` — the icon is the calendar screen, abstracted.

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
apps/entrelares_app/web/favicon.png                     (96, squircle)
apps/entrelares_app/web/icons/Icon-{192,512}.png        (full-bleed)
apps/entrelares_app/web/icons/Icon-maskable-{192,512}.png
apps/entrelares_app/assets/brand/emblema.png            (512, indigo squircle —
    legacy launchers AND the native splash bitmap)
apps/entrelares_app/assets/brand/emblema-maskable.png   (512, adaptive
    FOREGROUND: transparent, mark inside the 66% safe zone)
apps/entrelares_app/assets/brand/emblema-monochrome.png (512, the Android 13
    themed-icon glyph)
store/brand-calendario.svg
store/store_icon.png                                    (512, the Play LISTING
    icon — full-bleed indigo, mark at 60%)
```

The three `assets/brand/` files are what `flutter_launcher_icons` reads (config block in
`apps/entrelares_app/pubspec.yaml`: indigo adaptive background, zero foreground inset because
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

`apps/entrelares_app/assets/brand/google-g.png` (+ `2.0x/`, `3.0x/`) is Google's "G", used under
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
from PIL import Image                      # run from apps/entrelares_app/assets/brand/
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
(https://entrelares.app/privacidade.html) — **if the policy changes, re-answer.** Every
declaration on that page must be ✅ before a release rolls out, and the Console does not always
say which one is blocking: sweep the whole list.

- **Privacy policy URL**: `https://entrelares.app/privacidade.html`
- **App access** — the declaration that rejects apps whose reviewers cannot get in. The whole app
  sits behind login, so answer **"All or some functionality in my app is restricted"** and add an
  instruction set with a REAL test account (a dedicated reviewer account created through the
  normal sign-up, kept in the password manager as "Entrelares — Play reviewer account").
  Instructions: *"Log in with the credentials provided; the custody calendar is the home screen.
  All features are reachable from the bottom navigation."* Keep the account alive — Google
  re-reviews on later releases too.
- **Data Safety** — declare:
  | Data type | Collected? | Shared? | Notes |
  |---|---|---|---|
  | Personal info → Name | Yes — required, account | No | Profile name |
  | Personal info → Email address | Yes — required, account | No | Login + notifications |
  | App activity → App interactions | Yes — not linked to identity | No | Umami, cookieless product analytics; no device id, paths sanitized |
  | Financial info | **No** | — | See the caveat below |
  | Location, contacts, photos, device ids | No | — | Not requested |
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
    - `privacidade@entrelares.app` stays as the channel for whoever cannot sign in — including,
      today, anyone who signs in with Google: deletion is sudo-gated (S-10) and an OAuth session
      has no password to confirm (**S-21**).
  - The consent log stores the accepting IP (disclosed in the policy) — server-side
    security/audit data tied to the account; declare it under Personal info only if the form's
    current wording requires IP disclosure (re-read the help text at fill time).
  - ⚠️ **The "Financial info → No" line has an expiry date.** It was written when the Android
    app had no purchase flow at all and every payment happened on the website. The Play Billing
    rail (T-48) now ships **dormant** behind `billing.store_enabled = false`; the day that switch
    is flipped, the app does sell in-app — re-read the Financial info questions before, not
    after. The flip is the last step of [`supabase/README.md`](../supabase/README.md) §9-bis,
    which also records what Play does and does not ask about IAP (nothing on the App content
    page: Play derives it from the products that exist).
- **Content rating questionnaire**: category *Utility/Productivity*; no violence, no user-to-user
  public content (messages are private within a family), no gambling → expected rating L/3+.
- **Target audience**: 18+ (parents/guardians). The app is **not** child-directed — the child is
  the *subject* of the calendar; no child accounts exist and no child data is collected (the only
  child-related datum is the day assignment itself).
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

> **The closed test ended on 01/09/2026.** What follows it — production access, the listing
> going public, and the checkboxes that come with it — is tracked as **T-59** in
> the **T-59** card ([board](https://app.notion.com/3c82f3f4b9b2810aaff5e49014f748ef)), not here —
> `backlog/` stopped being the record on 07/09/2026 (T-63). The account-deletion URL of §4 is one
> of its checkboxes, tracked as **S-19**.

## 6 · Publishing a new Android build

```
cd apps/entrelares_app && fvm flutter build appbundle --flavor prod --release
```

- `--flavor prod` is not optional: it is what selects the production Supabase project **and** the
  `com.entrelares.app` application id. A flavour-less build resolves to dev by construction
  (`CLAUDE.md` → *Locked decisions*).
- **Release signing** comes from the git-ignored `apps/entrelares_app/android/key.properties`
  (T-55): `prod.*` must be the PRODUCT's upload keystore. Without the file a release build fails
  fast, on purpose.
- **Version**: `version:` in `pubspec.yaml` feeds both halves — the name (`2.0.0`) and the build
  number after `+`, which becomes Android's `versionCode`. **Every upload needs a higher
  `versionCode` than the last**, and a code is burned by the UPLOAD, not by the rollout.
  **Bump policy (owner decision, 27/08/2026):** `2.0.0` opened the Flutter generation (the
  Blazor client retired at `1.8.15`; the spike's `0.2.x` never graduated at the cutover).
  Per MERGED PR: MINOR when it delivers a backlog item, PATCH for fixes/polish, MAJOR only by
  owner decision, and `+N` rises on every merge to `main` — the full text lives as the
  comment above `version:` in the pubspec, next to the number it governs.
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
**web side**: `apps/entrelares_app/web/.well-known/assetlinks.json`, published with the web
channel at `web.entrelares.app`. It carries two statements — `com.entrelares.flutter` (the dev
flavour) and `com.entrelares.app` (upload + app-signing fingerprints). A third one named the
legacy `com.guardacompartilhada.app` and came out with **T-52** (09/09/2026), once that Play app
was deleted; `web_channel_test` now asserts its ABSENCE, so it cannot drift back in. If the
browser bar ever comes back on an installed app, that file in PRODUCTION is the first thing to
check.
