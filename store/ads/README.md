# store/ads/ — the ad kit of the first real-cohort campaign (T-102)

Made for **L-31** (owner, 04/10/2026): R$ 600 over 4 weeks — Google app campaign (Android
installs → the Play listing), Google Search (→ `entrelares.app/comecar/busca`) and Meta /
Instagram (→ `entrelares.app/comecar/meta`). No pixel: each family's source is recorded on our
side at creation (T-101) from the link the ad opened (L-46).

Everything here is generated, and **nothing on a phone is drawn by hand**: the images pump the
app's REAL screens with T-97's fictional demo family (Ana, Bruno, Lia and Theo —
`app/store_screenshots/demo_family.dart`), the same way the Play screenshots are made.

## Regenerate

```
cd app && fvm flutter test store_ads/      # the 18 images, the 2 closing cards and the 4 video screens
bash store/ads/render_video.sh             # the 2 videos (ffmpeg from PATH, else Docker)
```

The calendar reads the real clock, so the month on screen and the dates in the swap sheet move
with the day of the run: **regenerate, then approve what was regenerated.** The images live
outside the CI (`app/store_ads/` is not under `test/`); `flutter analyze` still reads the
harness. The copy's limits are a CI test: `packages/entrelares_core/test/store_ads_copy_test.dart`.

## The three angles

| Angle | Headline on the image | Screen | Plan |
|---|---|---|---|
| `hoje` | Quem está com as crianças hoje? | the month, today's carer on top | Free |
| `troca` | Troca de dia pedida e respondida no app | a pending swap request, Aprovar / Recusar | Free |
| `festas` | Natal e Ano-Novo em duas casas | December, the 24th/25th and 31st/1st alternating | Free |

**Why angle 2 does not say "only when both agree".** The owner's angle was *"a swap changes only
when both agree, and it is recorded"*. Two things in the code make "only" false: a request nobody
answers is approved by the deadline rule (F-24/F-60 — the sheet itself shows *Aprovação
automática*), and an admin with the admin mode on changes a day directly (F-81 tells the people
it touched). So the words say what always holds — *one asks, the other approves or refuses, and
the change is recorded* (S-15).

Every image and line: neutral (never "ex", never a side), no price, no competitor, no number an
operator can change (U-57), no emoji (U-31), and no Premium module — the three screens are free.

## Which file goes where

### Google Ads — app campaign (Android installs)

| Asset | File |
|---|---|
| Headlines (5, ≤ 30) | [`copy/google-app-headlines.txt`](copy/google-app-headlines.txt) |
| Descriptions (5, ≤ 90) | [`copy/google-app-descriptions.txt`](copy/google-app-descriptions.txt) |
| Images 1.91:1 | `img/hoje-google-1200x628.png`, `img/troca-google-1200x628.png`, `img/festas-google-1200x628.png` |
| Images 1:1 | `img/<angle>-google-1200x1200.png` |
| Images 4:5 | `img/<angle>-google-1200x1500.png` |
| Videos | the YouTube links of `video/entrelares-v2-16x9.mp4` and `video/entrelares-v2-9x16.mp4` (v2, below) — an app campaign takes video only as a YouTube URL, so the owner uploads them (unlisted) first |

### Google Ads — Search (responsive search ad)

| Asset | File |
|---|---|
| Headlines (15, ≤ 30) | [`copy/search-headlines.txt`](copy/search-headlines.txt) |
| Descriptions (4, ≤ 90) | [`copy/search-descriptions.txt`](copy/search-descriptions.txt) |
| Keywords (phrase `"…"` and exact `[…]`) | [`copy/search-keywords.txt`](copy/search-keywords.txt) |
| Negative keywords | [`copy/search-negatives.txt`](copy/search-negatives.txt) |
| Final URL | `https://entrelares.app/comecar/busca?utm_campaign=primeira-turma` |

### Meta — Instagram feed, Stories and Reels

| Asset | File |
|---|---|
| Primary text, 3 angles × 2 variants (≤ 125, `angle-n\|text`) | [`copy/meta-primary.txt`](copy/meta-primary.txt) |
| Headlines, one per angle (≤ 40, `angle\|text`) | [`copy/meta-headlines.txt`](copy/meta-headlines.txt) |
| Feed 1:1 / 4:5 | `img/<angle>-meta-1080x1080.png` / `img/<angle>-meta-1080x1350.png` |
| Stories / Reels 9:16 | `img/<angle>-meta-1080x1920.png` (the words keep out of the top 13% and bottom 12%, where Instagram draws its bars) |
| Video | `video/entrelares-v2-9x16.mp4` (Stories/Reels), `video/entrelares-v2-4x5.mp4` (feed) — and the `-15s-` cuts (v2, below) |
| Website URL | `https://entrelares.app/comecar/meta?utm_campaign=primeira-turma` |

The video: ~24 s, the three angles of 7 s and a closing card of 5 s with 0.6 s crossfades, H.264
30 fps, **no audio track** (no licensed music). **Superseded by v2 below** (07/10/2026); the two
files stay until the campaigns swap them.

## The video, v2 (07/10/2026)

A motion piece instead of a slideshow: the question, the month, a swap asked and approved with
the finger on *Aprovar*, the notifications, the card. One cut, six files — the 25 s master and a
15 s version (Meta recommends ≤ 15 s), each in 9:16 (Stories/Reels/Shorts), 4:5 (Instagram feed)
and 16:9 (YouTube, for the Google app campaign):

| File | Canvas | Where |
|---|---|---|
| `video/entrelares-v2-9x16.mp4` · `-15s-9x16` | 1080×1920 | Instagram Stories and Reels; YouTube Shorts |
| `video/entrelares-v2-4x5.mp4` · `-15s-4x5` | 1080×1350 | Instagram feed |
| `video/entrelares-v2-16x9.mp4` · `-15s-16x9` | 1920×1080 | YouTube (unlisted) → Google app campaign |
| `video/frames/<same name>-first.png`, `-end.png` | | the first frame and the closing card, as stills |

H.264, yuv420p, 30 fps, faststart, **no audio track** (owner, 04/10/2026). In 9:16 every word
and the logo stay between y = 250 and y = 1250 with 60 px side margins (Reels draws its UI over
the top 250 px and the bottom ~670 px); the phone may run into the bottom band. Words: the
approved lines of `copy/` plus *"Imprevisto no dia? Mande um aviso."* and *"O essencial é
gratuito."*, under the same rules as the images (neutral, no price, no promise of outcome,
no operator-editable number, no emoji, no Premium module, no store badge on the card).

The phone shows the app's REAL screens: `app/store_ads/video_frames_test.dart` pumps four
states with the demo family (the month, Bruno's request open in the day sheet, the month after
Ana approves it, the notifications on *Todas*) and writes them bare to `video/src/`. Everything
else — captions, outline, the ring and the finger — is `video/scene.html`, one deterministic page
(`window.seek(t)`), screenshotted frame by frame by `video/build.mjs` (Playwright on the
installed Chrome) and encoded by ffmpeg (from the PATH, else the pinned Docker image). The
pointers aim at boxes `video/hotspots.py` measures on the real pixels by token colour, so a
screen that moves moves the pointer with it.

```
cd app && fvm flutter test store_ads/video_frames_test.dart   # the 4 screens (dates = today)
cd store/ads/video && npm i --no-save playwright-core@1.56.1 && node build.mjs   # ~8 min
```

`ONLY=9x16 CUTS=25 node build.mjs` renders one file while iterating. The calendar reads the real
clock, so **regenerate the screens, then approve what was regenerated.**

The exact settings of each campaign (country, language, budget, end date) are in the handoff
blocks of **L-31**, not here — this folder is the material, the card is the launch.
