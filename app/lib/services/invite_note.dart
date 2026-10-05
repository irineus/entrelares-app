/// F-88 — the invitation a sign-up started from, kept across a reload, a
/// killed process and a sign-out until it is claimed (or found dead).
///
/// The Google path held the token in memory only: an F5 on `/onboarding`,
/// Android killing the process, or "Entrar com outra conta" after picking the
/// wrong Google account all landed on the FOUNDER form, and the invitee made a
/// second, disconnected family. It must NOT go to `shared_preferences`, which
/// Android's Auto Backup copies to the Google account (T-18): the web keeps it
/// in `sessionStorage` (this tab only), Android in the app's CACHE directory.
/// The choice is made at COMPILE time, as in `boot_handoff.dart`.
library;

export 'invite_note_io.dart' if (dart.library.js_interop) 'invite_note_web.dart';
