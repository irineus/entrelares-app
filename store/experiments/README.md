# store/experiments/ — Google Play store-listing experiments

A Play *store listing experiment* shows a variant of the listing to a share of its visitors and
counts installs against the current listing. The variants live here, **outside** the two paths the
`play-listing` workflow reads (`store/listing-*.txt` and `store/screenshots/<lang>/`), so no
dispatch can publish a variant as the listing by mistake. A variant reaches Play only through the
Console's experiment form, by the owner's hand — experiments have no API that `supply` drives.

The rules every variant follows are the listing's own (store/README.md §1 and §1.1): every
sentence true of the code (S-15), no number an operator can change (U-57), no emoji (U-31), and
a screenshot rendered from the real widgets by `app/store_screenshots/`, never drawn by hand.

**One variable per experiment.** A variant that differs in two things cannot say which one moved
the installs. For screenshots that has a consequence: the variant and the control must come from
the **same** run of the harness, because the dates on screen move with the day it runs and the UI
moves with every release. A variant rendered today against a control published a month ago differs
in the month, the data and every screen that changed in between.

---

## T-108 — the first screenshot's headline (pt-BR)

| | |
|---|---|
| Type | *Graphics experiment on default listing* — the pt-BR listing (the default language). en-US carries its own graphics, so its readers are not in it |
| Why pt-BR | 15 of the 17 real-cohort families (since 05/10/2026) use the app in pt-BR; 2 in English (production read, 19/11/2026) |
| Variable | the headline of screenshot 1 — nothing else |
| Control | `store/screenshots/pt-BR/phone-1.png` — **"Quem fica com as crianças, dia a dia"** (names the feature) |
| Variant | `store/experiments/T-108/pt-BR/phone-1.png` — **"Duas casas, um só calendário"** (names the reader's situation; echoes the full description's opening, *"Duas casas, uma mesma infância"*) |
| Same in both | the screen (the month, Hoje card, a swapped day, a pending request's bell), the detail line *"O mês num olhar, e com quem elas estão hoje"*, and screenshots 2–8 (`store/screenshots/pt-BR/phone-2.png` … `phone-8.png`) |
| Hypothesis | a visitor who lands from a search for *guarda compartilhada* recognizes their own situation faster than a feature description, and installs more often |
| Rendered | 19/11/2026, one run of `fvm flutter test store_screenshots/`, control and variant together |
| Target metric | *Unique user install clicks* |
| Audience | 50 % of the listing's visitors see the variant (one variant) |

**What the volume allows.** In the 28 days to 19/11/2026 the listing had 17 acquisitions at a
12.6 % conversion (90 days) — on the order of 135 listing visitors a month, ~67 of them on the
variant. Telling 12.6 % from even 18 % takes several hundred visitors per arm, so expect Play to
say *More data needed* for months; Play stops every experiment at 6 months by itself. The reading
rule is therefore fixed before the start: **only Play's own verdict counts** — a *winning variant*
is applied; a *Draw*, a *More data needed* at the 6-month stop, or *current listing performed best*
keeps the current listing. No early call on a lead in the first weeks.

**While it runs.** No `play-listing` dispatch with `upload_screenshots` ticked: it would replace
the control's screenshots under a running experiment. A text-only dispatch (en-US) does not touch
the pt-BR graphics and is fine.

**If the variant wins.** Its headline moves into scene 1 of
`app/store_screenshots/store_screenshots_test.dart`, the T-108 entry leaves
`experimentVariants`, both sets are regenerated and approved, and `play-listing` publishes them
— the Console's *Apply* button would write the listing outside `store/` (T-98).
