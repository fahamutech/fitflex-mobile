import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';

/// Trainers are approved at once, so a new trainer (for example a member who
/// added the trainer role) is "approved" before registering. Where they land
/// follows onboardingCompleted, which the server sets once they have a profile.
Future<AuthState> _signedInTrainer({required bool onboarded}) async {
  final auth = AuthState(ApiClient(baseUrl: 'http://localhost:0'));
  await auth.signIn('jwt', {
    'id': 'usr_trainer',
    'userType': 'trainer',
    'approvalStatus': 'approved',
    'onboardingCompleted': onboarded,
  });
  return auth;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('an approved trainer with no profile yet registers first', () async {
    final auth = await _signedInTrainer(onboarded: false);
    expect(routeForSignedInUser(auth), AppRoutes.trainerRegistration);
  });

  test('a trainer who has registered goes to the trainer home', () async {
    final auth = await _signedInTrainer(onboarded: true);
    expect(routeForSignedInUser(auth), AppRoutes.trainerHome);
  });
}
