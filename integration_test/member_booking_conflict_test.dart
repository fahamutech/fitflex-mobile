// Patrol E2E: booking declines show a specific user-facing reason.

import 'package:patrol/patrol.dart';

import 'journeys.dart';

void main() {
  patrolTest(
    'Issue 48: booked trainer slot explains the decline',
    config: patrolConfig,
    memberBookedSlotDeclineJourney,
  );
}
