// Patrol E2E: configured trainer slots can be booked by a member.

import 'package:patrol/patrol.dart';

import 'journeys.dart';

void main() {
  patrolTest(
    'Issues 5, 30-31: member books an available trainer slot',
    config: patrolConfig,
    memberSlotBookingJourney,
  );
}
