import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/pin_credentials.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MemberProfile preserves multiple fitness goals and workout times', () {
    final profile = MemberProfile.fromJson({
      'fitnessGoals': ['lose_weight', 'build_muscle'],
      'fitnessLevel': 'beginner',
      'preferredWorkoutTimes': ['morning', 'evening'],
    });

    expect(profile.fitnessGoals, ['lose_weight', 'build_muscle']);
    expect(profile.fitnessLevel, 'beginner');
    expect(profile.preferredWorkoutTimes, ['morning', 'evening']);
  });

  test('Firebase password uses a string credential derived from the PIN', () {
    final password = firebasePasswordForPin('1234');

    expect(password, isNot('1234'));
    expect(password.length, greaterThanOrEqualTo(6));
    expect(password.endsWith('1234'), isTrue);
  });
}
