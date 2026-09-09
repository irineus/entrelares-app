@Timeout(Duration(minutes: 5))
library;

import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

import 'suites/account_deletion.dart';
import 'suites/admin_override_tier.dart';
import 'suites/admin_rpc.dart';
import 'suites/adversarial.dart';
import 'suites/app_settings.dart';
import 'suites/auto_approval.dart';
import 'suites/billing_avulso.dart';
import 'suites/billing_checkout.dart';
import 'suites/billing_grace.dart';
import 'suites/billing_grace_warning.dart';
import 'suites/billing_history.dart';
import 'suites/billing_reactivate.dart';
import 'suites/billing_store.dart';
import 'suites/billing_webhook.dart';
import 'suites/caregiver_gate.dart';
import 'suites/claim_invitation.dart';
import 'suites/consent_and_retention.dart';
import 'suites/custom_role.dart';
import 'suites/day_protection.dart';
import 'suites/e2e_date_allocator.dart';
import 'suites/edge_function_auth.dart';
import 'suites/email_quota_gate.dart';
import 'suites/family_deletion.dart';
import 'suites/family_isolation.dart';
import 'suites/handoff_transition.dart';
import 'suites/invitation_lifecycle.dart';
import 'suites/invitation_purge.dart';
import 'suites/joined_via_invite.dart';
import 'suites/multi_caregiver.dart';
import 'suites/notification_params.dart';
import 'suites/oauth_onboarding.dart';
import 'suites/optimistic_concurrency.dart';
import 'suites/pending_member.dart';
import 'suites/planning_horizon_gate.dart';
import 'suites/platform_operator.dart';
import 'suites/premium_entitlement.dart';
import 'suites/profile_language.dart';
import 'suites/profile_self_service.dart';
import 'suites/push_subscriptions.dart';
import 'suites/reconsent_gate.dart';
import 'suites/register_invitee.dart';
import 'suites/resolution_log_link.dart';
import 'suites/revert_notes.dart';
import 'suites/rls_hardening.dart';
import 'suites/sudo_elevation.dart';
import 'suites/swap_message.dart';
import 'suites/test_recipient_suppression.dart';

/// **The single entrypoint of the database gate, and why it is single.**
///
/// In xUnit, 41 of the C# suite's 43 classes shared ONE family through
/// `[Collection("e2e-family")]` — a collection fixture is constructed once for
/// the whole collection, whatever the class count. `dart test` has no such
/// thing: it runs each *file* in its own isolate, so a `setUpAll` is per FILE.
/// A file-per-suite port would therefore create one throwaway family per file
/// — 40-odd sign-up flows, invitations and purges per run, hammering the shared
/// QA project and multiplying the GoTrue rate-limit surface T-32 already had to
/// back off from.
///
/// So the suites are libraries, not test files: each exposes a function that
/// REGISTERS its groups against a fixture it is handed. This file is the only
/// `_test.dart` in the package, it owns the one `setUpAll`/`tearDownAll` pair,
/// and every suite runs inside it against the same family.
///
/// Two consequences worth knowing before adding a suite:
///   · a suite registers groups at CALL time but must only TOUCH the fixture
///     inside a `test` body — the fields are populated in `setUpAll`, which runs
///     after registration;
///   · order matters as little as it did in xUnit, and for the same reason:
///     every day comes from the fixture's allocators, never from local date
///     arithmetic.
void main() {
  final fx = GateFixture();

  setUpAll(fx.initialize);
  tearDownAll(fx.dispose);

  familyIsolationTests(fx);
  rlsHardeningTests(fx);
  adversarialTests(fx);
  consentAndRetentionTests(fx);
  reconsentGateTests(fx);
  caregiverGateTests(fx);
  dayProtectionTests(fx);
  handoffTransitionTests(fx);
  planningHorizonGateTests(fx);
  optimisticConcurrencyTests(fx);
  autoApprovalTests(fx);
  swapMessageTests(fx);
  revertNotesTests(fx);
  resolutionLogLinkTests(fx);
  accountDeletionTests(fx);
  familyDeletionTests(fx);
  profileSelfServiceTests(fx);
  profileLanguageTests(fx);
  invitationLifecycleTests(fx);
  invitationPurgeTests(fx);
  joinedViaInviteTests(fx);
  multiCaregiverTests(fx);
  registerInviteeTests(fx);
  oauthOnboardingTests(fx);
  claimInvitationTests(fx);
  pendingMemberTests(fx);
  adminRpcTests(fx);
  adminOverrideTierTests(fx);
  platformOperatorTests(fx);
  sudoElevationTests(fx);
  customRoleTests(fx);
  appSettingsTests(fx);
  edgeFunctionAuthTests(fx);
  notificationParamsTests(fx);
  pushSubscriptionsTests(fx);
  emailQuotaGateTests(fx);
  testRecipientSuppressionTests(fx);
  e2eDateAllocatorTests(fx);
  premiumEntitlementTests(fx);
  billingCheckoutTests(fx);
  billingGraceTests(fx);
  billingGraceWarningTests(fx);
  billingHistoryTests(fx);
  billingReactivateTests(fx);
  billingAvulsoTests(fx);
  billingStoreTests(fx);
  billingWebhookTests(fx);
}
