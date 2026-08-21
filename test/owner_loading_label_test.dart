import 'package:fitflexmobile/screens/owner/owner_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('owner header never shows a temporary pending-approval label', () {
    final data = OwnerData();

    expect(data.activeGymName('Gym'), 'Gym');

    data.ownerGyms = [
      {'id': 'gym-1', 'name': 'Mikocheni Fitness'},
    ];
    expect(data.activeGymName('Gym'), 'Mikocheni Fitness');
  });
}
