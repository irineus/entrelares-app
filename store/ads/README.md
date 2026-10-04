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
cd app && fvm flutter test store_ads/      # the 18 images + the 2 closing cards (~20 s)
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
| Videos | the two YouTube links of `video/entrelares-9x16.mp4` and `video/entrelares-1x1.mp4` — an app campaign takes video only as a YouTube URL, so the owner uploads them (unlisted) first |

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
| Video | `video/entrelares-9x16.mp4` (Stories/Reels), `video/entrelares-1x1.mp4` (feed) |
| Website URL | `https://entrelares.app/comecar/meta?utm_campaign=primeira-turma` |

The video: ~24 s, the three angles of 7 s and a closing card of 5 s with 0.6 s crossfades, H.264
30 fps, **no audio track** (no licensed music).

The exact settings of each campaign (country, language, budget, end date) are in the handoff
blocks of **L-31**, not here — this folder is the material, the card is the launch.
