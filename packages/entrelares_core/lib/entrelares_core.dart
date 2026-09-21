/// Pure-Dart core of Entrelares — the client-side MIRROR of rules the server
/// enforces. The server is the authority (RLS, triggers, RPCs); these exist so
/// the UI can present state and refuse bad input upfront, and so every contract
/// is unit-tested without a device — the same philosophy as the C# mirror
/// suites in `entrelares-app` (CalendarHelpersTests, EntitlementService).
library;

export 'src/account_rules.dart';
export 'src/analytics_rules.dart';
export 'src/appearance_rules.dart';
export 'src/audit_rules.dart';
export 'src/billing_rules.dart';
export 'src/auth_rules.dart';
export 'src/bulk_rules.dart';
export 'src/calendar_rules.dart';
export 'src/channel_handoff_rules.dart';
export 'src/connectivity_rules.dart';
export 'src/consent_declarations.dart';
export 'src/crash_rules.dart';
export 'src/custom_role_rules.dart';
export 'src/date_math.dart';
export 'src/day_protection_rules.dart';
export 'src/editor_rules.dart';
export 'src/entitlement_rules.dart';
export 'src/family_lifecycle_rules.dart';
export 'src/empty_month_rules.dart';
export 'src/freemium_rules.dart';
export 'src/install_hint_rules.dart';
export 'src/environment_rules.dart';
export 'src/feedback_rules.dart';
export 'src/notice_rules.dart';
export 'src/onboarding_steps.dart';
export 'src/localization/app_language.dart';
export 'src/localization/date_formats.dart';
export 'src/localization/k.dart';
export 'src/localization/k_app.dart';
export 'src/localization/language_resolver.dart';
export 'src/localization/localization.dart';
export 'src/localization/notification_renderer.dart';
export 'src/localization/rich_text.dart';
export 'src/localization/strings_en.dart';
export 'src/localization/strings_pt_br.dart';
export 'src/policy_versions.dart';
export 'src/push_enrollment.dart';
export 'src/push_routing.dart';
export 'src/quick_swap_rules.dart';
export 'src/report_rules.dart';
export 'src/role_catalog.dart';
export 'src/document_title.dart';
export 'src/route_rules.dart';
export 'src/save_errors.dart';
export 'src/schedule_range_rules.dart';
export 'src/settings_rules.dart';
export 'src/sign_in_methods.dart';
export 'src/store_billing_rules.dart';
export 'src/sudo_rules.dart';
export 'src/support_rules.dart';
export 'src/swap_notifications.dart';
export 'src/swap_rules.dart';
export 'src/swap_snapshot.dart';
export 'src/today_rules.dart';
export 'src/tour_steps.dart';
export 'src/wizard_rules.dart';
