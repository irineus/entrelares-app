import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// The global the boot script reads before it reports anything. Spelled ONCE
/// here; `web_channel_test` reads this literal out of the source and fails the
/// build if `index.html` spells it differently — the two sides are in two
/// languages and nothing else would catch a rename, which would leave the boot
/// script armed forever and every Dart crash reported twice.
const _bootedFlag = 'entrelaresBooted';

/// Web half: tell the inline boot script that Dart is alive and it can stand
/// down. Set on `window`, which is what a script in the document reads.
void markAppBooted() {
  globalContext.setProperty(_bootedFlag.toJS, true.toJS);
}
