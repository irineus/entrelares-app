"""T-102 (video v2) — measures, on the REAL screens in src/, the boxes the
video's pointers aim at, and prints them as JSON (source pixels, 1080×2220).

Run by build.mjs; never typed by hand. Each box is a colour match against the
app's own tokens, so a redesign that moves a card moves the pointer with it,
and a token that changes makes this script fail loudly (an empty match)
rather than point at the wrong place.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

SRC = Path(__file__).resolve().parent / 'src'

ROSE_CONTAINER = (255, 228, 230)   # tokens: member slot 2 container
BRAND_SOLID = (79, 70, 229)        # tokens: brand.solid
AMBER_CONTAINER = (254, 243, 199)  # tokens: warning.container (the swapped day)


def pixels(name):
    return np.array(Image.open(SRC / f'{name}.png').convert('RGB')).astype(int)


def mask(im, rgb, tol=6):
    return np.abs(im - np.array(rgb)).sum(axis=2) <= tol


def bbox(m):
    ys, xs = np.where(m)
    if len(xs) == 0:
        sys.exit('hotspots: no pixel matched — a token or a screen changed')
    return {'x': int(xs.min()), 'y': int(ys.min()),
            'w': int(xs.max() - xs.min() + 1), 'h': int(ys.max() - ys.min() + 1)}


def today_card():
    im = pixels('cal')
    m = mask(im, ROSE_CONTAINER)
    m[int(im.shape[0] * 0.3):] = False    # the card of today's carer sits above the legend
    return bbox(m)


def approve_button():
    im = pixels('sheet')
    m = mask(im, BRAND_SOLID)
    m[: im.shape[0] // 2] = False         # the buttons are in the lower half
    # Keep only the SOLID columns (the filled button), not the outlined
    # "Recusar" text drawn in the same colour.
    solid = m.sum(axis=0) > 60
    m[:, ~solid] = False
    return bbox(m)


def swapped_day():
    im = pixels('cal-after')
    m = mask(im, AMBER_CONTAINER)
    m[: int(im.shape[0] * 0.4)] = False    # the legend's own "Trocado" chip is amber too
    ys = np.where(m.any(axis=1))[0]
    # The FIRST amber cluster from the top is the approved Saturday; the
    # fixture's older swapped Thursday sits a row lower.
    top = ys[0]
    gap = np.where(np.diff(ys) > 1)[0]
    bottom = ys[gap[0]] if len(gap) else ys[-1]
    m[: top] = False
    m[bottom + 1:] = False
    return bbox(m)


def notice_row():
    # The first row of "Todas": the band between the filter chips and the
    # second row's title. Measured as the first run of non-background rows
    # below the chips.
    im = pixels('notif')
    bg = mask(im, (249, 250, 251), tol=2) | mask(im, (255, 255, 255), tol=2)
    ink = ~bg
    rows = ink.sum(axis=1) > 8
    h = im.shape[0]
    # Skip the header, the tab bar and the chips: the first ink row after the
    # chips' bottom edge.
    y = int(h * 0.19)
    while y < h and rows[y]:
        y += 1
    while y < h and not rows[y]:
        y += 1
    start = y
    # The row ends at the blank gap before the next title (≥ 18 px of nothing).
    blank = 0
    while y < h and blank < 18:
        blank = blank + 1 if not rows[y] else 0
        y += 1
    return {'x': 36, 'y': start - 14, 'w': im.shape[1] - 72, 'h': (y - blank) - start + 28}


def month_grid():
    im = pixels('cal')
    # From the weekday header to the last cell: every cell border is one of
    # the two member borders; the grid is their vertical extent.
    m = mask(im, (147, 197, 253), tol=10) | mask(im, (253, 164, 175), tol=10)
    m[: int(im.shape[0] * 0.36)] = False   # below the legend chips
    return bbox(m)


print(json.dumps({
    'today': today_card(),
    'approve': approve_button(),
    'swapped': swapped_day(),
    'notice': notice_row(),
    'grid': month_grid(),
}))
