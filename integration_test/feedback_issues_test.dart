// Patrol blackbox E2E — All feedback journeys in one target.
// Run: patrol test integration_test/feedback_issues_test.dart
//
// For split execution use member_feedback_test / owner_feedback_test / trainer_feedback_test.

import 'package:patrol/patrol.dart';

import 'journeys.dart';

void main() {
  patrolTest(
    'Issue matrix: member flows',
    config: patrolConfig,
    memberIssueMatrixJourney,
  );
  patrolTest(
    'Issue matrix: owner flows',
    config: patrolConfig,
    ownerIssueMatrixJourney,
  );
  patrolTest(
    'Issue matrix: trainer flows',
    config: patrolConfig,
    trainerIssueMatrixJourney,
  );
}
