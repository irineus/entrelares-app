import 'dart:io';

/// Where the gate points and how it authorizes — the Dart twin of the C#
/// suite's `TestEnv` (T-30).
///
/// Since Fulcrum 04.3.1 / T-94 (28/09/2026) the suite runs against an
/// EPHEMERAL LOCAL stack built from the checkout — `bash tool/db_gate_local.sh`,
/// in CI and on a workstation alike — and never against a hosted project. It
/// used to run against the dev project on the grounds that a local stack proves
/// the rules "about a database no user talks to"; what that cost was ~344 real
/// auth users per run, which the Free plan counts as MAU whether or not the
/// teardown deletes them, and 375 runs put the dev org at 91,988 / 50,000. The
/// migrations are the same files `db push` applies to both hosted projects, so
/// the local database IS the schema users talk to, applied from zero.
///
/// So all three values are REQUIRED and have no default: a missing URL can no
/// longer fall back to a hosted project and spend its MAU in silence. The
/// fixture aborts with instructions rather than running half a suite and
/// reporting green.
///
/// Sources, in order: environment variable (what the script exports from
/// `supabase status`) → the git-ignored `e2e.local.env` file, searched upward
/// from the working directory.
abstract final class TestEnv {
  /// The signature the DB-side purge guard recognises. `purge_e2e_family`
  /// re-validates it server-side, which is what makes a fixture bug unable to
  /// delete a real family.
  static const String e2eFamilyPrefix = 'E2E-';

  /// Resend's test domain: accepted, delivered nowhere, never bounces.
  static const String e2eEmailDomain = '@resend.dev';

  static String get supabaseUrl => _required('E2E_SUPABASE_URL');

  static String get anonKey => _required('E2E_SUPABASE_ANON_KEY');

  static String get serviceRoleKey =>
      _required('E2E_SUPABASE_SERVICE_ROLE_KEY');

  static String _required(String name) {
    final value = _get(name);
    if (value == null || value.trim().isEmpty) {
      throw StateError(
        '$name is not set. The gate runs against a LOCAL Supabase stack: from '
        'the repository root, `bash tool/db_gate_local.sh` starts one from the '
        'migrations, exports E2E_SUPABASE_URL, E2E_SUPABASE_ANON_KEY and '
        'E2E_SUPABASE_SERVICE_ROLE_KEY from `supabase status`, and runs the '
        'suite. Never point it at a hosted project — every run creates ~344 '
        'auth users, and the Free plan counts each one as a MAU (T-94).',
      );
    }
    return value.trim();
  }

  /// S-16: a key is either LEGACY (a JWT signed with the project's JWT secret)
  /// or NEW-MODEL (`sb_publishable_…` / `sb_secret_…`). They need OPPOSITE
  /// headers, so every HAND-BUILT request goes through [keyHeaders] instead of
  /// hardcoding one shape:
  ///   · legacy → `apikey` AND `Authorization: Bearer`. PostgREST derives the
  ///     DB role from the Bearer JWT; `apikey` alone runs as `anon`, which in
  ///     this 100%-RLS app reads nothing (the T-44 keep-alive lesson).
  ///   · new    → `apikey` ONLY. They are not JWTs: the gateway resolves the
  ///     role from the key itself.
  /// Keeping both shapes alive is what lets the CI secrets be rotated one at a
  /// time instead of in a single flip-everything-at-once step.
  static bool isNewKeyFormat(String key) => key.startsWith('sb_');

  static Map<String, String> keyHeaders(String key) => {
        'apikey': key,
        if (!isNewKeyFormat(key)) 'Authorization': 'Bearer $key',
      };

  /// OPTIONAL secrets (e.g. the billing-webhook shared token). Absent is a
  /// valid state — the dependent tests arm themselves only when the value
  /// exists, mirroring how the function secret itself is provisioned
  /// out-of-band. CI passes a missing GitHub secret as an EMPTY string, which
  /// is the same thing as absent.
  static String? optional(String key) {
    final value = _get(key);
    return (value == null || value.trim().isEmpty) ? null : value.trim();
  }

  static String? _get(String key) =>
      Platform.environment[key] ?? _localEnvFile[key];

  static Map<String, String>? _localEnvFileCache;

  /// Minimal `.env` reader: `KEY=VALUE` lines, `#` comments; searched upward
  /// from the working directory so it works from any package directory.
  static Map<String, String> get _localEnvFile {
    final cached = _localEnvFileCache;
    if (cached != null) return cached;

    final values = <String, String>{};
    for (var dir = Directory.current;; dir = dir.parent) {
      final file = File('${dir.path}${Platform.pathSeparator}e2e.local.env');
      if (file.existsSync()) {
        for (final line in file.readAsLinesSync()) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
          final separator = trimmed.indexOf('=');
          if (separator <= 0) continue;
          values[trimmed.substring(0, separator).trim()] =
              trimmed.substring(separator + 1).trim();
        }
        break;
      }
      if (dir.parent.path == dir.path) break; // filesystem root
    }
    return _localEnvFileCache = values;
  }
}
