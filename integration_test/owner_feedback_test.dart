// Patrol E2E: Owner feedback journeys.
// Covers: dashboard redesign, multi-scan, earnings, bank details, trainer creation, attendant.
// Run: patrol test integration_test/owner_feedback_test.dart

import 'package:patrol/patrol.dart';

import 'journeys.dart';

void main() {
  patrolTest(
    'Issues 3-4, 16-29, 42, 46-48: owner matrix',
    config: patrolConfig,
    ownerIssueMatrixJourney,
  );
}
