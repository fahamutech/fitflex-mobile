// Patrol E2E: Account registration and login flows for all roles.
// Covers: owner creates member/trainer → those accounts sign in successfully.
// Also covers role selection screen, sign-up screen rendering, and sign-in flow.
// Run: patrol test integration_test/register_login_test.dart

import 'package:patrol/patrol.dart';

import 'journeys.dart';

void main() {
  patrolTest(
    'Owner creates member, member signs in with email+PIN',
    config: patrolConfig,
    registerAndLoginMemberJourney,
  );
}
