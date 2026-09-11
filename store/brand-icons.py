#!/usr/bin/env python3
"""U-29 (R6/F24) — draw the Entrelares brand mark and derive every app icon.

THE MARK (owner's concept, 26/08/2026): a calendar card whose DAY CELLS draw
the product's founding image — two interlocked houses. The blue house and the
amber house wear the calendar's own day colours (slot 1 and the swapped
amber), the cells where they interlace are rose `#E11D48` (slot 2), each house
keeps a card-coloured "door" (an empty day), and the today ring sits on one of
the SHARED days. Launcher background: brand indigo `#4F46E5` (option A, then
concept V1 of the U-29 icon review).

This file replaced the previous clay-emblem derivation (F-54) on 26/08/2026.
The AI-generated masters it used to read (`brand-emblema.png`,
`brand-emblema-flat.png`) had no vector source, and T-57 deleted them from
`store/` once nothing here read them any more (a live copy survives in
`entrelares-site/assets-src/` until the landing migrates). The mark below is
pure geometry, so THIS SCRIPT is the source — it also writes
`store/brand-calendario.svg` as the vector artifact.

Usage (needs Pillow):  python3 store/brand-icons.py
Then:                  cd app && fvm dart run flutter_launcher_icons

Outputs:  app/web/favicon.png                    (96, squircle)
          app/web/icons/Icon-{192,512}.png       (full-bleed)
          app/web/icons/Icon-maskable-{192,512}.png
          app/assets/brand/emblema.png           (512, squircle
              on transparency — legacy launcher AND the native splash bitmap)
          app/assets/brand/emblema-maskable.png  (512, adaptive
              FOREGROUND: transparent, mark inside the 66% safe zone)
          app/assets/brand/emblema-monochrome.png (512, the
              Android 13 themed-icon glyph: white alpha shape)
          app/android/.../res/drawable-*/ic_stat_entrelares.png
              (F-09: the Android status-bar icon, 5 densities — white glyph on
              transparency, because Android silhouettes the small icon)
          store/brand-calendario.svg                             (vector source)
          store/store_icon.png                                   (512, the Play
              LISTING icon — full-bleed indigo, mark at 60% so Play's own
              rounding and circular masks never bite into the card)

`store_icon.png` was deliberately NOT written here between 26/08 and 28/08/2026:
the Play listing had to stay on the clay emblem until the listing art moved as a
WHOLE, and a routine re-run of this script could not be allowed to push a rebrand
into the store behind that decision. **T-57 is that whole**, so the hold is over
and the file is an output again — the framing that used to justify hand-supplying
it now lives in `store_listing()`, separate from the PWA's, so tuning one can
never drift the other.

STILL not an output, and still deliberate: the landing repo keeps its own copy of
this script (`entrelares-site/assets-src/brand-icons.py`) and its own masters.
Moving the landing to the new mark is T-57's landing half, in that repo.
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app"
WEB = APP / "web"
BRAND = APP / "assets" / "brand"

INDIGO = (0x4F, 0x46, 0xE5)   # tokens: accent.solid (light) — the background
BLUE = (0x1D, 0x4E, 0xD8)     # tokens: slot 1 solid — the first house
AMBER = (0xD9, 0x77, 0x06)    # tokens: swapped solid — the second house
ROSE = (0xE1, 0x1D, 0x48)     # tokens: slot 2 solid — the interlace
OUTLINE = (0xE5, 0xE7, 0xEB)  # tokens: outline — the card header chrome
EMPTY = (0xEE, 0xF1, 0xF5)    # a step under outline — the vacant days
RING = (0x11, 0x18, 0x27)     # tokens: text — the today ring
WHITE = (255, 255, 255)

SS = 4  # supersample factor: draw big, LANCZOS down — crisp rounded corners

# Card geometry, normalized to a card width of 168 (AppBrandMark's scale).
_PAD, _GAP, _HDR_H, _DOT, _CELL_R, _CARD_R = 12, 3, 4, 5, 4, 16
_COLS, _ROWS = 8, 6

def _house(c0: int, r0: int) -> set:
    """A filled 5x5 pixel pentagon: apex, roof row, three wall rows."""
    s = {(r0, c0 + 2)}
    s.update((r0 + 1, c) for c in range(c0 + 1, c0 + 4))
    for r in range(r0 + 2, r0 + 5):
        s.update((r, c) for c in range(c0, c0 + 5))
    return s

_L = _house(0, 1)              # blue house, grounded
_R = _house(3, 0)              # amber house, raised one row — the interlace
_BOTH = _L & _R                # the five shared days
_DOORS = {(5, 2), (4, 5)}      # a vacant day at each house's threshold
_TODAY = sorted(_BOTH)[len(_BOTH) // 2]   # today is a SHARED day

def _cell_colour(p):
    if p in _DOORS:
        return None            # the card shows through
    if p in _BOTH:
        return ROSE
    if p in _L:
        return BLUE
    if p in _R:
        return AMBER
    return EMPTY

def _card_height(w: float) -> float:
    s = w / 168.0
    cell = (w - 2 * _PAD * s - (_COLS - 1) * _GAP * s) / _COLS
    return (2 * _PAD + _HDR_H + 8) * s + _ROWS * cell + (_ROWS - 1) * _GAP * s

def draw_mark(d: ImageDraw.ImageDraw, x: float, y: float, w: float,
              monochrome: bool = False) -> None:
    """The card at (x, y), width w, onto an SS-supersampled canvas."""
    s = w / 168.0
    h = _card_height(w)
    pad, gap = _PAD * s, _GAP * s
    if monochrome:
        # A themed icon is an alpha GLYPH: the card outline plus the two
        # houses, all white — the launcher supplies the colour.
        d.rounded_rectangle([x, y, x + w, y + h], radius=_CARD_R * s,
                            outline=WHITE, width=max(1, round(3 * s)))
    else:
        d.rounded_rectangle([x, y, x + w, y + h], radius=_CARD_R * s, fill=WHITE)
    hdr = WHITE if monochrome else OUTLINE
    bar_w = w - 2 * pad - (8 + 2 * _DOT + _GAP) * s
    d.rounded_rectangle([x + pad, y + pad, x + pad + bar_w, y + pad + _HDR_H * s],
                        radius=2 * s, fill=hdr)
    dx = x + pad + bar_w + 8 * s
    for _ in range(2):
        d.ellipse([dx, y + pad, dx + _DOT * s, y + pad + _DOT * s], fill=hdr)
        dx += (_DOT + _GAP) * s
    grid_top = y + pad + (_HDR_H + 8) * s
    cell = (w - 2 * pad - (_COLS - 1) * gap) / _COLS
    for r in range(_ROWS):
        for c in range(_COLS):
            p = (r, c)
            colour = _cell_colour(p)
            if monochrome:
                # Glyph keeps only the houses — the vacant days would blur
                # the silhouette the launcher tints.
                colour = WHITE if (p in _L or p in _R) and p not in _DOORS \
                    else None
            if colour is None:
                continue
            cx = x + pad + c * (cell + gap)
            cy = grid_top + r * (cell + gap)
            d.rounded_rectangle([cx, cy, cx + cell, cy + cell],
                                radius=_CELL_R * s, fill=colour)
            if p == _TODAY and not monochrome:
                d.rounded_rectangle([cx, cy, cx + cell, cy + cell],
                                    radius=_CELL_R * s, outline=RING,
                                    width=max(1, round(2.2 * s)))

def _canvas(size: int):
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)

def _finish(img: Image.Image, size: int, opaque_on=None) -> Image.Image:
    out = img.resize((size, size), Image.LANCZOS)
    if opaque_on is not None:
        base = Image.new("RGB", (size, size), opaque_on)
        base.paste(out, (0, 0), out)
        return base
    return out

def _centred_mark(d, size_ss: int, frac: float, monochrome=False):
    w = size_ss * frac
    h = _card_height(w)
    draw_mark(d, (size_ss - w) / 2, (size_ss - h) / 2, w, monochrome=monochrome)

def full_bleed(size: int) -> Image.Image:
    """PWA 'any' icon: indigo square, mark at 66%."""
    img, d = _canvas(size)
    d.rectangle([0, 0, size * SS, size * SS], fill=INDIGO)
    _centred_mark(d, size * SS, 0.66)
    return _finish(img, size, opaque_on=INDIGO)

def store_listing(size: int) -> Image.Image:
    """Play LISTING icon: full-bleed indigo, mark at 60%.

    Play does not serve this file as uploaded — it applies its own rounding,
    and some surfaces mask it to a circle. 0.60 (against the PWA's 0.66) is
    what keeps the card clear of the circular mask's chord at the corners; the
    old clay file was hand-framed for exactly this reason.
    """
    img, d = _canvas(size)
    d.rectangle([0, 0, size * SS, size * SS], fill=INDIGO)
    _centred_mark(d, size * SS, 0.60)
    return _finish(img, size, opaque_on=INDIGO)

def maskable_bleed(size: int) -> Image.Image:
    """PWA maskable: full-bleed indigo, mark inside the safe zone."""
    img, d = _canvas(size)
    d.rectangle([0, 0, size * SS, size * SS], fill=INDIGO)
    _centred_mark(d, size * SS, 0.46)
    return _finish(img, size, opaque_on=INDIGO)

def squircle(size: int) -> Image.Image:
    """Legacy launcher + splash bitmap: indigo squircle on transparency."""
    img, d = _canvas(size)
    d.rounded_rectangle([0, 0, size * SS - 1, size * SS - 1],
                        radius=int(size * SS * 0.24), fill=INDIGO)
    _centred_mark(d, size * SS, 0.66)
    return _finish(img, size)

def adaptive_foreground(size: int) -> Image.Image:
    """Adaptive FOREGROUND layer: transparent, mark within the 66% circle."""
    img, d = _canvas(size)
    _centred_mark(d, size * SS, 0.46)
    return _finish(img, size)

def monochrome(size: int) -> Image.Image:
    """Android 13 themed-icon glyph (launcher tints the alpha)."""
    img, d = _canvas(size)
    _centred_mark(d, size * SS, 0.46, monochrome=True)
    return _finish(img, size)

def notification(size: int) -> Image.Image:
    """F-09 — the Android status-bar icon: white glyph on transparency.

    This one is NOT a nicety. Android renders a notification's small icon as a
    SILHOUETTE — it keeps the alpha channel and throws the colours away — so an
    app that ships none gets its launcher icon flattened into a featureless
    blob. That is what a real device showed on the first push (29/08/2026): a
    white circle where the mark should be.

    The mark fills the box (0.92, against `monochrome`'s 0.46) because a status
    bar icon has no safe zone to respect — the system gives it its own padding.
    It reads from xhdpi up; at mdpi the day cells merge, which is accepted:
    `minSdk` is 26 and a device that low-density is not in this product's field.
    """
    img, d = _canvas(size)
    _centred_mark(d, size * SS, 0.92, monochrome=True)
    return _finish(img, size)


def write_svg(path: Path, size: int = 1024) -> None:
    """The vector source: same geometry, same tokens, hand-editable."""
    w = size * 0.66
    h = _card_height(w)
    x, y = (size - w) / 2, (size - h) / 2
    s = w / 168.0
    pad, gap = _PAD * s, _GAP * s
    cell = (w - 2 * pad - (_COLS - 1) * gap) / _COLS
    hexc = lambda c: "#%02X%02X%02X" % c
    e = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
         f'viewBox="0 0 {size} {size}">',
         f'<rect width="{size}" height="{size}" rx="{size*0.24:.0f}" fill="{hexc(INDIGO)}"/>',
         f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" '
         f'rx="{_CARD_R*s:.1f}" fill="#FFFFFF"/>']
    bar_w = w - 2 * pad - (8 + 2 * _DOT + _GAP) * s
    e.append(f'<rect x="{x+pad:.1f}" y="{y+pad:.1f}" width="{bar_w:.1f}" '
             f'height="{_HDR_H*s:.1f}" rx="{2*s:.1f}" fill="{hexc(OUTLINE)}"/>')
    dx = x + pad + bar_w + 8 * s
    for _ in range(2):
        e.append(f'<circle cx="{dx+_DOT*s/2:.1f}" cy="{y+pad+_DOT*s/2:.1f}" '
                 f'r="{_DOT*s/2:.1f}" fill="{hexc(OUTLINE)}"/>')
        dx += (_DOT + _GAP) * s
    grid_top = y + pad + (_HDR_H + 8) * s
    for r in range(_ROWS):
        for c in range(_COLS):
            colour = _cell_colour((r, c))
            if colour is None:
                continue
            cx = x + pad + c * (cell + gap)
            cy = grid_top + r * (cell + gap)
            e.append(f'<rect x="{cx:.1f}" y="{cy:.1f}" width="{cell:.1f}" '
                     f'height="{cell:.1f}" rx="{_CELL_R*s:.1f}" '
                     f'fill="{hexc(colour)}"/>')
            if (r, c) == _TODAY:
                e.append(f'<rect x="{cx:.1f}" y="{cy:.1f}" width="{cell:.1f}" '
                         f'height="{cell:.1f}" rx="{_CELL_R*s:.1f}" fill="none" '
                         f'stroke="{hexc(RING)}" stroke-width="{2.2*s:.1f}"/>')
    e.append('</svg>')
    path.write_text('\n'.join(e), encoding='utf-8')

if __name__ == "__main__":
    for size in (192, 512):
        full_bleed(size).save(WEB / "icons" / f"Icon-{size}.png", optimize=True)
        print("ok", f"Icon-{size}.png")
        maskable_bleed(size).save(WEB / "icons" / f"Icon-maskable-{size}.png",
                                  optimize=True)
        print("ok", f"Icon-maskable-{size}.png")
    squircle(96).save(WEB / "favicon.png", optimize=True)
    print("ok favicon.png")
    squircle(512).save(BRAND / "emblema.png", optimize=True)
    print("ok emblema.png")
    adaptive_foreground(512).save(BRAND / "emblema-maskable.png", optimize=True)
    print("ok emblema-maskable.png")
    monochrome(512).save(BRAND / "emblema-monochrome.png", optimize=True)
    print("ok emblema-monochrome.png")
    store_listing(512).save(ROOT / "store" / "store_icon.png", optimize=True)
    print("ok store_icon.png")
    # F-09: the status-bar icon, one file per density. Android picks by density
    # and silhouettes whatever it finds, so shipping all five is what keeps the
    # mark from being resampled into mush on the phone that matters.
    res = APP / "android" / "app" / "src" / "main" / "res"
    for bucket, px in (("mdpi", 24), ("hdpi", 36), ("xhdpi", 48),
                       ("xxhdpi", 72), ("xxxhdpi", 96)):
        out = res / f"drawable-{bucket}" / "ic_stat_entrelares.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        notification(px).save(out, optimize=True)
    print("ok ic_stat_entrelares.png (5 densities)")
    write_svg(ROOT / "store" / "brand-calendario.svg")
    print("ok brand-calendario.svg")
