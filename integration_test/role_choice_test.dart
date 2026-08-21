import 'package:patrol/patrol.dart';

import 'journeys.dart';

void main() {
  patrolTest(
    'Create account role page and automatic sign-in role',
    config: patrolConfig,
    roleChoiceJourney,
  );
}
