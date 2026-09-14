// Patrol E2E: member bookings populate the trainer's sessions view.

import 'package:patrol/patrol.dart';

import 'journeys.dart';

void main() {
  patrolTest(
    'Issue 33: booking appears in today sessions',
    config: patrolConfig,
    trainerBookedSessionJourney,
  );
}
