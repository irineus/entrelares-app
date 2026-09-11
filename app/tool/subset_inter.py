"""U-27: turn the Inter variable font into four static, latin-subset weights.

Statics, not the variable file: Flutter maps `fontWeight` onto a pubspec
declaration deterministically, while an arbitrary `wght` axis needs explicit
FontVariation at every call site.
"""
import os
import subprocess
import sys

SRC = "Inter-var.ttf"
OUT = "out"
WEIGHTS = {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold"}

# Google Fonts' `latin` range: everything PT-BR and EN need,
# plus the currency/punctuation the reports print. latin-ext would triple the
# glyph count (438 -> 1118) and the weight with it, for scripts this product
# does not render.
UNICODES = (
    "U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,"
    "U+0304,U+0308,U+0329,U+2000-206F,U+2074,U+20AC,U+2122,U+2191,U+2193,"
    "U+2212,U+2215,U+FEFF,U+FFFD"
)

os.makedirs(OUT, exist_ok=True)
for weight, name in WEIGHTS.items():
    instance = os.path.join(OUT, f"_instance-{name}.ttf")
    final = os.path.join(OUT, f"Inter-{name}.ttf")
    # Pin both axes: opsz to the text optical size, wght to this weight.
    subprocess.run(
        [sys.executable, "-m", "fontTools.varLib.instancer", SRC,
         f"wght={weight}", "opsz=14", "-o", instance],
        check=True, capture_output=True)
    subprocess.run(
        [sys.executable, "-m", "fontTools.subset", instance,
         f"--unicodes={UNICODES}",
         "--layout-features=kern,liga,calt,ccmp,mark,mkmk,locl,frac,tnum",
         "--name-IDs=1,2,3,4,5,6",
         "--drop-tables+=DSIG",
         "--no-hinting",
         f"--output-file={final}"],
        check=True, capture_output=True)
    os.remove(instance)
    print(f"{final}: {os.path.getsize(final) // 1024} KB")
