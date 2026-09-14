// Patrol E2E: Sign-in screen flow and role selection validation.
// Covers: sign-in screen has no role choices, create account navigates to role page,
// all 5 roles visible on role page.
// Run: patrol test integration_test/sign_in_flow_test.dart

import 'package:patrol/patrol.dart';

import 'journeys.dart';

void main() {
  patrolTest(
    'Sign-in screen flow and role selection',
    config: patrolConfig,
    signInExistingMemberJourney,
  );
}
