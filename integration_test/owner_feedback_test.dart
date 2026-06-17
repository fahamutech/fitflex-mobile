// Patrol E2E: Owner feedback journeys.
// Covers: dashboard redesign, multi-scan, earnings, bank details, trainer creation, attendant.
// Run: patrol test integration_test/owner_feedback_test.dart

import 'package:patrol/patrol.dart';

import 'journeys.dart';

void main() {
  patrolTest(
    'Owner: Dashboard, scan, and earnings',
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
}
