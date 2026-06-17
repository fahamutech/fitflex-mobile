// Patrol blackbox E2E — All feedback journeys in one target.
// Run: patrol test integration_test/feedback_issues_test.dart
//
// For split execution use member_feedback_test / owner_feedback_test / trainer_feedback_test.

import 'package:patrol/patrol.dart';

import 'journeys.dart';

void main() {
  // ─── Member ───
  patrolTest(
    'Member: Onboarding PIN + tour + location',
    config: patrolConfig,
    memberOnboardingPinTourLocationJourney,
  );
  patrolTest(
    'Member: Gym discovery, subscription, Shop',
    config: patrolConfig,
    memberGymDiscoverySubscriptionAndShopJourney,
  );
  patrolTest(
    'Member: Profile, gym review, visits',
    config: patrolConfig,
    memberProfileGymReviewAndVisitsJourney,
  );
  patrolTest(
    'Member: Auth terms and profile QR',
    config: patrolConfig,
    memberAuthTermsAndProfileQrJourney,
  );
  patrolTest(
    'Member: Gym filters and subscription',
    config: patrolConfig,
    memberGymFiltersAndSubscriptionJourney,
  );

  // ─── Owner ───
  patrolTest(
    'Owner: Dashboard, scan, earnings',
    config: patrolConfig,
    ownerProfileDashboardScanAndEarningsJourney,
  );
  patrolTest(
    'Owner: Trainer credential and attendant',
    config: patrolConfig,
    ownerTrainerCredentialAndAttendantJourney,
  );
  patrolTest(
    'Owner: QR failure and scan flow',
    config: patrolConfig,
    ownerQrFailureAndTrainerCreationJourney,
  );
  patrolTest(
    'Owner: Create gym member',
    config: patrolConfig,
    ownerCreateGymMemberJourney,
  );

  // ─── Trainer ───
  patrolTest(
    'Trainer: Registration, rate, specialty',
    config: patrolConfig,
    trainerRegistrationRateAndSpecialtyJourney,
  );
}
