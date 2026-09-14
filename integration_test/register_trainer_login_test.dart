// Patrol E2E: Owner creates trainer with email/PIN → trainer signs in.
// Covers client feedback: trainer creation email login flow.
// Run: patrol test integration_test/register_trainer_login_test.dart

import 'package:patrol/patrol.dart';

import 'journeys.dart';

void main() {
  patrolTest(
    'Owner creates trainer, trainer signs in with email+PIN',
    config: patrolConfig,
    registerAndLoginTrainerJourney,
  );
}
