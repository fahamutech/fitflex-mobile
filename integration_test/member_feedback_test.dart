// Patrol E2E: Member feedback journeys.
// Covers: PIN auth, Shop tab, gym discovery filters, profile edit, verified badge, QR.
// Run: patrol test integration_test/member_feedback_test.dart

import 'package:patrol/patrol.dart';

import 'journeys.dart';

void main() {
  patrolTest(
    'Member: Onboarding PIN + tour + location',
    config: patrolConfig,
    memberOnboardingPinTourLocationJourney,
  );

  patrolTest(
    'Member: Gym discovery, subscription, and Shop tab',
    config: patrolConfig,
    memberGymDiscoverySubscriptionAndShopJourney,
  );

  patrolTest(
    'Member: Profile, gym review, and visits',
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
}
