"""T-62: vendor the Firebase JS SDK into `web/`, so no third party executes
code on this app's origin.

**Why this script exists at all.** `firebase_core_web` does not bundle the
Firebase JS SDK — it INJECTS it at runtime, with a dynamic
`import("https://www.gstatic.com/firebasejs/<v>/firebase-app.js")`. The web
channel's CSP is `script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' blob:`
and `web_channel_test` asserts, in writing, that no gstatic host may appear
there: CanvasKit is served from this origin precisely so that executable code
never comes from somebody else's. So the SDK is vendored here instead, and the
plugin is told to inject nothing (see `services/push_messaging_web.dart`,
which sets `window.firebase_core` before `Firebase.initializeApp`).

**Four files, two pairs, two different loaders.**
  * the ESM pair (`firebase-app.js`, `firebase-messaging.js`) is what the PAGE
    imports;
  * the compat pair (`…-compat.js`) is what the SERVICE WORKER imports, because
    `importScripts` is a classic-script loader and cannot take an ES module —
    and the FlutterFire Dart layer registers the worker without `{type}`.

**The one rewrite.** The gstatic ESM bundles hard-code the absolute URL of
their own dependency: `firebase-messaging.js` starts with
`import{…}from"https://www.gstatic.com/firebasejs/<v>/firebase-app.js"`. Copying
the file verbatim would therefore still fetch half the SDK from gstatic — and
fail the CSP at exactly the moment someone enables push. The rewrite below
points it at its sibling. It is asserted from the other side too:
`web_channel_test` fails if any vendored file still names gstatic.

Usage (from `app`):

    python tool/vendor_firebase_js.py

Re-run it when `firebase_core_web`'s `supportedFirebaseJsSdkVersion` moves —
that constant, not this file, is the source of truth for VERSION below, and
`web_channel_test` pins the two together so an upgrade cannot land with a
stale copy.
"""
import os
import re
import sys
import urllib.request

# Must equal `supportedFirebaseJsSdkVersion` in
# `firebase_core_web/lib/src/firebase_sdk_version.dart`. The plugin warns at
# runtime when the loaded SDK differs from the version it was tested against,
# and a browser console warning nobody reads is not a gate — so the pin is a
# test instead.
VERSION = "12.18.0"

BASE = f"https://www.gstatic.com/firebasejs/{VERSION}"
OUT = os.path.join("web", "firebasejs", VERSION)

# ESM: imported by the page. Compat: `importScripts`-ed by the worker.
FILES = (
    "firebase-app.js",
    "firebase-messaging.js",
    "firebase-app-compat.js",
    "firebase-messaging-compat.js",
)

os.makedirs(OUT, exist_ok=True)

for name in FILES:
    with urllib.request.urlopen(f"{BASE}/{name}") as response:
        body = response.read().decode("utf-8")

    # The dependency URL the ESM bundles hard-code, pointed at the sibling copy.
    # `./` and not a bare path: the import is resolved against the importing
    # module's own URL, so this survives the app being served from a sub-path.
    body = body.replace(f"{BASE}/", "./")

    if "gstatic.com/firebasejs" in body:
        # A shape this script does not know about. Failing loudly beats
        # shipping a file that silently reaches for a blocked origin.
        leftover = re.findall(r"https://www\.gstatic\.com/firebasejs/\S{0,60}", body)
        sys.exit(f"{name}: gstatic reference survived the rewrite: {leftover[:3]}")

    with open(os.path.join(OUT, name), "w", encoding="utf-8") as out:
        out.write(body)

    print(f"{name}: {len(body) // 1024} KB -> {OUT}")
