import 'package:flutter/material.dart';
import '../../shared/api_client.dart';
import '../../shared/api_error_message.dart';
import '../../shared/auth_state.dart';
import '../../shared/i18n.dart';

class MemberOnboardingController extends ChangeNotifier {
  final ApiClient api;
  final AuthState auth;
  final FFLocale locale;

  int step = 0;
  bool busy = false;

  final List<String> fitnessGoals = [];

  final nameCtrl = TextEditingController();
  String? gender;
  final dobCtrl = TextEditingController();
  String? fitnessLevel;
  final heightCtrl = TextEditingController();
  final weightCtrl = TextEditingController();

  final PageController pageController = PageController();

  MemberOnboardingController({
    required this.api,
    required this.auth,
    required this.locale,
  }) {
    nameCtrl.addListener(notifyListeners);
    dobCtrl.addListener(notifyListeners);
    heightCtrl.addListener(notifyListeners);
    weightCtrl.addListener(notifyListeners);
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    dobCtrl.dispose();
    heightCtrl.dispose();
    weightCtrl.dispose();
    pageController.dispose();
    super.dispose();
  }

  bool get canProceed {
    if (step == 0) return fitnessGoals.isNotEmpty;
    if (step == 1) {
      return nameCtrl.text.trim().isNotEmpty &&
          gender != null &&
          dobCtrl.text.isNotEmpty;
    }
    if (step == 2) return fitnessLevel != null;
    return true;
  }

  void toggleGoal(String goal) {
    if (fitnessGoals.contains(goal)) {
      fitnessGoals.remove(goal);
    } else {
      if (fitnessGoals.length < 5) {
        fitnessGoals.add(goal);
      }
    }
    notifyListeners();
  }

  void setGender(String? val) {
    gender = val;
    notifyListeners();
  }

  void setFitnessLevel(String? val) {
    fitnessLevel = val;
    notifyListeners();
  }

  void setBusy(bool value) {
    busy = value;
    notifyListeners();
  }

  void next(VoidCallback onFinished) {
    if (step < 2) {
      step++;
      pageController.animateToPage(
        step,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      notifyListeners();
    } else {
      onFinished();
    }
  }

  void back() {
    if (step > 0) {
      step--;
      pageController.animateToPage(
        step,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      notifyListeners();
    }
  }

  void setStep(int newStep) {
    step = newStep;
    notifyListeners();
  }

  Future<void> submit({
    required VoidCallback onSuccess,
    required Function(String) onError,
  }) async {
    if (busy) return;
    setBusy(true);
    try {
      await api.updateProfile({
        'displayName': nameCtrl.text.trim(),
        'gender': gender,
        'dateOfBirth': dobCtrl.text.trim(),
        'fitnessGoals': fitnessGoals,
        'fitnessLevel': fitnessLevel,
        'heightCm': heightCtrl.text.isNotEmpty
            ? num.tryParse(heightCtrl.text)
            : null,
        'weightKg': weightCtrl.text.isNotEmpty
            ? num.tryParse(weightCtrl.text)
            : null,
        'preferredWorkoutTimes': <String>[],
        'onboardingCompleted': true,
      });

      // Re-hydrate auth user to reflect onboarding completion
      final meRes = await api.me();
      final user = Map<String, dynamic>.from(meRes['user'] as Map);
      await auth.signIn(auth.token!, user);
      onSuccess();
    } on ApiException catch (e) {
      onError(apiErrorMessage(locale, e));
    } catch (e) {
      onError(e.toString());
    } finally {
      setBusy(false);
    }
  }
}
