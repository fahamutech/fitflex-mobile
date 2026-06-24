# Flutter Implementation Spec: `member_onboarding_page`

## Goal

Create `member_onboarding_page`, a multi-step onboarding screen used to collect member profile data before the user can continue using the app.

The page must be implemented in Flutter using reusable components, design tokens, clean state management, smooth motion, and separated service/business logic.

---

## File / Feature Name

`member_onboarding_page`

Suggested path:

```txt
lib/features/member_onboarding/
```

Suggested structure:

```txt
lib/features/member_onboarding/
  presentation/
    pages/
      member_onboarding_page.dart
    widgets/
      onboarding_step_scaffold.dart
      fitness_goal_step.dart
      personal_information_step.dart
      fitness_level_step.dart
      selectable_goal_card.dart
      selectable_level_tile.dart
      onboarding_bottom_bar.dart
  application/
    member_onboarding_controller.dart
    member_onboarding_state.dart
  data/
    member_onboarding_service.dart
    member_onboarding_repository.dart
  domain/
    member_onboarding_model.dart
```

---

# Screen Requirements

## General Behavior

`member_onboarding_page` is a 3-step onboarding flow.

Steps:

1. Fitness Goals
2. Personal Information
3. Fitness Level

The screen must have:

* Static bottom navigation area.
* Step indicator in the bottom area.
* Buttons change depending on the current step.
* Smooth motion when moving between steps.
* Validation before allowing the user to continue.
* API submission on final step.
* Loading progress during submission.
* API errors shown in a dialog.

All colors, spacing, typography, radius, shadows, icons, and animation durations must come from design tokens or theme extensions.

No hardcoded styles.

---

# Design Token Requirement

Use existing shared design tokens.

If tokens do not exist, create a theme/token layer first.

Required token categories:

```dart
AppColors
AppSpacing
AppRadius
AppTypography
AppMotion
AppShadows
```

Do not use raw values like:

```dart
Color(0xFF...)
EdgeInsets.all(16)
TextStyle(...)
Duration(milliseconds: 300)
```

Use tokens instead.

---

# Shared Components Requirement

Use shared components where available.

If missing, create reusable shared components first:

```txt
AppButton
AppTextField
AppRadioTile
AppSelectableCard
AppStepIndicator
AppDialog
AppDatePickerField
AppNumberInput
```

The onboarding step UI should be built from reusable components, not one-off widgets.

---

# Step 1: Fitness Goals

## Title

```txt
What are your fitness goals?
```

## Slogan

```txt
Select all that apply
```

## Options

User can select minimum 1 and maximum 5 goals.

Goals:

```txt
lose weight
gain muscle
stay fit
improve endurance
learn a new skill
```

## UI

Display choices in a responsive grid.

Each choice card should contain:

* Goal title
* Optional emoji/icon
* Selected visual state

Example icons:

```txt
lose weight: 🔥
gain muscle: 💪
stay fit: ❤️
improve endurance: 🏃
learn a new skill: 🎯
```

## Behavior

* Tapping a card selects it.
* Tapping selected card again unselects it.
* Next button is disabled when no goal is selected.
* Next button becomes active after at least one goal is selected.

---

# Step 2: Personal Information

## Title

```txt
Personal Information
```

## Slogan

```txt
Let us know about you
```

## Fields

```txt
name
gender
date of birth
height optional
weight optional
```

## Field Types

Name:

```txt
Text input
Required
Must not be empty
```

Gender:

```txt
Radio choice
Required
Options: male, female, other
```

Date of birth:

```txt
Date picker
Required
Must be valid
Must not be future date
```

Height:

```txt
Number input
Optional
Must be positive if filled
```

Weight:

```txt
Number input
Optional
Must be positive if filled
```

## Buttons

Bottom buttons:

```txt
Back
Next
```

## Behavior

* Back returns to Step 1.
* Next is disabled until required fields are valid.
* Validation logic must be outside UI widgets.
* Show inline field errors where needed.

---

# Step 3: Fitness Level

## Title

```txt
Fitness Level
```

## Slogan

```txt
Helusse recommend the suitable gym and trainers
```

## Options

Radio choices:

```txt
beginner
intermediate
advanced
```

Each radio item should have:

* Title
* Description
* Optional emoji/icon

Suggested descriptions:

```txt
beginner: I am just getting started or returning after a long break.
intermediate: I train sometimes and understand basic exercises.
advanced: I train regularly and need challenging programs.
```

Suggested icons:

```txt
beginner: 🌱
intermediate: ⚡
advanced: 🏆
```

## Buttons

Bottom buttons:

```txt
Back
Finish
```

## Behavior

* Finish is disabled until the user selects a fitness level.
* When Finish is tapped, submit onboarding data to the server.
* Show loading/progress state while submitting.
* Disable buttons during submission.
* Show API errors using dialog.
* On success, navigate to the next intended screen.

---

# Bottom Bar Requirement

The bottom bar must be static and visually connected across all steps.

It should contain:

* Step indicator
* Back button where applicable
* Next or Finish button depending on step
* Disabled/enabled button states
* Loading state on Finish

Step indicator must clearly show:

```txt
Step 1 of 3
Step 2 of 3
Step 3 of 3
```

Use shared `AppStepIndicator`.

---

# Motion Requirement

Use smooth natural motion when:

* Entering a step
* Leaving a step
* Selecting/unselecting goal card
* Selecting fitness level
* Button enabling/disabling
* Showing loading state

Recommended Flutter widgets:

```dart
AnimatedSwitcher
AnimatedContainer
AnimatedOpacity
AnimatedScale
PageTransitionSwitcher or PageView
```

Animation duration and curve must come from `AppMotion`.

Example token usage:

```dart
AppMotion.normalDuration
AppMotion.defaultCurve
```

---

# State Management Requirement

All application logic must be outside UI widgets.

Use a controller/service pattern.

The UI should only:

* Render state
* Call controller actions
* Show dialogs/navigation based on state changes

Suggested controller actions:

```dart
selectGoal(FitnessGoal goal)
unselectGoal(FitnessGoal goal)
toggleGoal(FitnessGoal goal)

updateName(String value)
updateGender(Gender value)
updateDateOfBirth(DateTime value)
updateHeight(String value)
updateWeight(String value)

selectFitnessLevel(FitnessLevel level)

goNext()
goBack()
submit()
```

Suggested state fields:

```dart
int currentStep
Set<FitnessGoal> selectedGoals
String name
Gender? gender
DateTime? dateOfBirth
String? height
String? weight
FitnessLevel? fitnessLevel
bool isSubmitting
String? apiError
bool canGoNext
bool canFinish
```

Validation must be exposed through state:

```dart
bool get isStepOneValid
bool get isStepTwoValid
bool get isStepThreeValid
```

---

# Domain Models

Create enums:

```dart
enum FitnessGoal {
  loseWeight,
  gainMuscle,
  stayFit,
  improveEndurance,
  learnNewSkill,
}

enum Gender {
  male,
  female,
  other,
}

enum FitnessLevel {
  beginner,
  intermediate,
  advanced,
}
```

Create request model:

```dart
class MemberOnboardingRequest {
  final List<FitnessGoal> goals;
  final String name;
  final Gender gender;
  final DateTime dateOfBirth;
  final double? height;
  final double? weight;
  final FitnessLevel fitnessLevel;
}
```

---

# API Service Requirement

Create service:

```dart
MemberOnboardingService
```

It should expose:

```dart
Future<void> submitOnboarding(MemberOnboardingRequest request);
```

The service must:

* Handle API request.
* Throw typed errors.
* Not contain UI code.
* Not show dialogs directly.

UI/controller handles:

* Loading state
* Error state
* Success navigation

---

# Error Handling

If API submission fails:

* Stop loading.
* Show error dialog.
* Keep user on Step 3.
* Preserve entered data.

Dialog title:

```txt
Could not finish onboarding
```

Dialog message:

Use API error message where available.

Fallback:

```txt
Something went wrong. Please try again.
```

---

# Acceptance Criteria

The implementation is complete when:

* User can move from Step 1 to Step 3.
* Step 1 requires at least one selected goal.
* Step 1 supports selecting and unselecting goals.
* Step 2 validates name, gender, and date of birth.
* Height and weight are optional but validated if filled.
* Step 3 requires fitness level selection.
* Finish submits data to API.
* Loading state appears during API call.
* API errors appear in dialog.
* Bottom bar stays fixed.
* Step indicator updates correctly.
* Components are reusable.
* Design tokens are used everywhere.
* No hardcoded colors, spacing, typography, radius, or durations.
* UI logic and business logic are separated.
* Step transitions and interactions are animated smoothly.

---

# Important Notes for Agent

Do not implement this as one large widget.

Break into clean components.

Do not hardcode design values.

Do not mix API logic inside UI widgets.

Prefer existing shared components. If missing, create them before implementing the screen.

The final screen must feel polished, connected, and production-ready.
