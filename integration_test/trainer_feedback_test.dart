// Patrol E2E: Trainer feedback journeys.
// Covers: registration, per-session rate, specialties from list, currency.
// Run: patrol test integration_test/trainer_feedback_test.dart

import 'package:patrol/patrol.dart';

import 'journeys.dart';

void main() {
  patrolTest(
    'Issues 5-8, 30-41: trainer matrix',
    config: patrolConfig,
    trainerIssueMatrixJourney,
  );
}
