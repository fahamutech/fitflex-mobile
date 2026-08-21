// Patrol E2E: Member feedback journeys.
// Covers: PIN auth, Shop tab, gym discovery filters, profile edit, verified badge, QR.
// Run: patrol test integration_test/member_feedback_test.dart

import 'package:patrol/patrol.dart';

import 'journeys.dart';

void main() {
  patrolTest(
    'Issues 1-15, 17-18, 22, 31, 41-42, 45, 48: member matrix',
    config: patrolConfig,
    memberIssueMatrixJourney,
  );
}
