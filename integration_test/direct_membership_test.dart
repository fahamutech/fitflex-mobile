import 'package:patrol/patrol.dart';

import 'journeys.dart';

void main() {
  patrolTest(
    'Owner-created direct member can sign in with shared credentials',
    config: patrolConfig,
    directMembershipCredentialJourney,
  );
}
