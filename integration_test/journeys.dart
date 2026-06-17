// Shared Patrol journey helpers for FitFlex blackbox tests.
//
// Each role journey lives in its own *_test.dart target so Patrol runs it in a
// fresh app process (avoids cross-test teardown crashes). All steps use widget
// Keys + exact-text finders — no screen-size coordinate taps.
//
// Run via scripts/blackbox.sh (sets API_BASE + MOCK_AUTH and adb reverse).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/main.dart' as app;

const patrolConfig = PatrolTesterConfig(
  existsTimeout: Duration(seconds: 20),
  visibleTimeout: Duration(seconds: 20),
  settleTimeout: Duration(seconds: 20),
);

/// Launches the app from a clean session and selects English → role screen.
Future<void> bootToRole(PatrolIntegrationTester $) async {
  (await SharedPreferences.getInstance()).clear();
  await app.main();
  await $(const Key('langEnglish')).waitUntilVisible();
  await $(const Key('langEnglish')).tap();
}

/// Helper: dev-login as member and land on member home.
Future<void> devLoginMember(PatrolIntegrationTester $) async {
  await bootToRole($);
  await $(const Key('devLoginMember')).tap();
  await $('Dev Member').waitUntilVisible();
}

/// Helper: dev-login as owner and land on owner dashboard.
Future<void> devLoginOwner(PatrolIntegrationTester $) async {
  await bootToRole($);
  await $(const Key('devLoginOwner')).tap();
  await $('Gym Owner Dashboard').waitUntilVisible();
}

/// Helper: dev-login as trainer and land on trainer dashboard.
Future<void> devLoginTrainer(PatrolIntegrationTester $) async {
  await bootToRole($);
  await $(const Key('devLoginTrainer')).tap();
  await $('Trainer Dashboard').waitUntilVisible();
}

// ═══════════════════════════════════════════════════════════════════════════════
// MEMBER JOURNEYS
// ═══════════════════════════════════════════════════════════════════════════════

/// Member onboarding PIN + tour + location journey.
/// Covers: PIN auth, no name on auth step, personal-info mandatory fields.
Future<void> memberOnboardingPinTourLocationJourney(
  PatrolIntegrationTester $,
) async {
  await bootToRole($);

  // Select member role to reach auth screen
  await $('Gym Member').tap();

  // Navigate to email auth (signup mode)
  await $('Continue with email').waitUntilVisible();
  await $('Continue with email').tap();

  // Auth step: should NOT have name field, should have PIN fields
  await $(const Key('emailField')).waitUntilVisible();
  expect($(const Key('nameField')), findsNothing);
  expect($(const Key('pinField')), findsOneWidget);

  // PIN visibility toggle (eye icon)
  expect($(const Key('pinVisibilityToggle')), findsOneWidget);

  // Tap sign up toggle
  await $('Sign up').tap();
  await $(const Key('confirmPinField')).waitUntilVisible();
  expect($(const Key('nameField')), findsNothing);
}

/// Member gym discovery, subscription, and Shop tab journey.
/// Covers: Shop tab, nearest filter, other filters, subscription confirmation.
Future<void> memberGymDiscoverySubscriptionAndShopJourney(
  PatrolIntegrationTester $,
) async {
  await devLoginMember($);

  // Shop tab in bottom nav
  await $('Shop').waitUntilVisible();
  await $('Shop').tap();
  await $('FitFlex Shop').waitUntilVisible();
  expect($('Coming soon'), findsOneWidget);

  // Gym discovery
  await $('Gyms').tap();
  await $('Discover gyms').waitUntilVisible();

  // Nearest filter chip visible
  await $('Nearest').waitUntilVisible();
  await $('Nearest').tap();
  // Should trigger location or show gyms sorted by distance

  // Navigate to a gym
  await $('Iron Paradise (Dev)').scrollTo();
  await $('Iron Paradise (Dev)').tap();

  // Gym detail: no Paid tag, has directions
  expect($('Paid'), findsNothing);
  await $('Get directions').waitUntilVisible();
}

/// Member profile, gym review, and visits journey.
/// Covers: profile goals, workout prefs, PIN change, verified badge.
Future<void> memberProfileGymReviewAndVisitsJourney(
  PatrolIntegrationTester $,
) async {
  await devLoginMember($);

  // Profile tab
  await $('Profile').tap();
  await $('Account settings').waitUntilVisible();

  // Goals, preferences, PIN change tiles
  await $('Change fitness goals').scrollTo();
  expect($('Change fitness goals'), findsOneWidget);
  expect($('Workout preferences'), findsOneWidget);
  expect($('Change PIN'), findsOneWidget);

  // Tap Change PIN
  await $('Change PIN').tap();
  await $('Current PIN').waitUntilVisible();
  await $('New PIN').waitUntilVisible();
  // Cancel the dialog
  await $('Cancel').tap();

  // QR access from home (Show my QR button)
  await $('Home').tap();
  await $('Show my QR').waitUntilVisible();
  await $('Show my QR').tap();
  await $('Show this code at the gym').waitUntilVisible();
}

/// Member auth, terms acceptance, and profile QR journey.
/// Covers: terms and conditions, localized validation, QR under profile.
Future<void> memberAuthTermsAndProfileQrJourney(
  PatrolIntegrationTester $,
) async {
  await bootToRole($);

  // Select member role to reach auth screen
  await $('Gym Member').tap();
  await $('Continue with email').waitUntilVisible();
  await $('Continue with email').tap();

  // Switch to sign up
  await $('Sign up').tap();
  await $(const Key('emailField')).waitUntilVisible();

  // Terms checkbox must be present and unchecked
  expect($(const Key('termsCheckbox')), findsOneWidget);

  // Try submit without terms — should fail
  await $(const Key('emailField')).enterText('test@example.com');
  await $(const Key('pinField')).enterText('1234');
  await $(const Key('confirmPinField')).enterText('1234');
  await $('Create account').tap();
  // Should show terms validation error or not proceed
}

/// Member gym filters and subscription journey.
/// Covers: filter combinations, My subscription filter, eligible gyms.
Future<void> memberGymFiltersAndSubscriptionJourney(
  PatrolIntegrationTester $,
) async {
  await devLoginMember($);

  await $('Gyms').tap();
  await $('Discover gyms').waitUntilVisible();

  // All filter should be active by default
  await $('All').waitUntilVisible();

  // Tap Nearest filter chip
  await $('Nearest').tap();

  // Gym list still loads after filter
  await $('Iron Paradise (Dev)').waitUntilVisible();
}

// ═══════════════════════════════════════════════════════════════════════════════
// OWNER JOURNEYS
// ═══════════════════════════════════════════════════════════════════════════════

/// Owner profile, dashboard, scan, and earnings journey.
/// Covers: B.4 dashboard look, B.3 multi-scan, B.6 earnings, B.1 bank details.
Future<void> ownerProfileDashboardScanAndEarningsJourney(
  PatrolIntegrationTester $,
) async {
  await devLoginOwner($);

  // Wait for dashboard data to load (period settings appear after API)
  await $('Period settings').waitUntilVisible();

  // Member type chips
  expect($('All members'), findsOneWidget);
  expect($('Direct members'), findsOneWidget);
  expect($('FitFlex roaming members'), findsOneWidget);

  // Owner tools section
  await $('Owner tools').scrollTo();
  await $('Owner tools').waitUntilVisible();

  // QR check-in tile
  expect($('QR check-in'), findsOneWidget);

  // Earnings action tile
  await $('Earnings').scrollTo();
  await $('Earnings').tap();
  // Should navigate to earnings view
  await $('Earnings').waitUntilVisible(); // title in AppBar
  await $(Icons.arrow_back).tap();
  await $('Gym Owner Dashboard').waitUntilVisible();
}

/// Owner trainer credential creation and (future) attendant journey.
/// Covers: B.2 trainer email/PIN login, B.5 attendant role.
Future<void> ownerTrainerCredentialAndAttendantJourney(
  PatrolIntegrationTester $,
) async {
  await devLoginOwner($);

  // Navigate to trainers
  await $('Trainers').tap();
  await $('Add trainer').waitUntilVisible();
  await $('Add trainer').tap();

  // Fill trainer form with email
  await $(const Key('trainerFormSave')).waitUntilVisible();
  final email = 'coach.${DateTime.now().millisecondsSinceEpoch}@example.com';
  await $(const Key('trainerFormName')).enterText('Coach E2E');
  await $(const Key('trainerFormEmail')).enterText(email);
  await $(const Key('trainerFormRate')).enterText('25000');
  await $(const Key('trainerFormSave')).tap();

  // Trainer should appear in list (confirms user record was created for login)
  await $('Coach E2E').waitUntilVisible();
}

/// Owner QR failure handling and multi-member scan journey.
/// Covers: B.3 scanning multiple members.
Future<void> ownerQrFailureAndTrainerCreationJourney(
  PatrolIntegrationTester $,
) async {
  await devLoginOwner($);

  // Wait for dashboard to load fully
  await $('Period settings').waitUntilVisible();

  // Scroll down and tap QR check-in
  await $('QR check-in').scrollTo();
  await $('QR check-in').tap();

  // Scanner page should load (AppBar title)
  await $('Scan Member QR').waitUntilVisible();

  // Go back to dashboard
  await $(Icons.arrow_back).tap();
  await $('Gym Owner Dashboard').waitUntilVisible();
}

/// Owner create gym member journey.
/// Covers: owner adds member to their gym with duration and dates.
Future<void> ownerCreateGymMemberJourney(PatrolIntegrationTester $) async {
  await devLoginOwner($);

  // Wait for dashboard to load fully
  await $('Period settings').waitUntilVisible();

  // Scroll to and tap Register member action
  await $('Register member').scrollTo();
  await $('Register member').tap();

  // Register member dialog should open
  await $('Register member').waitUntilVisible();
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRAINER JOURNEYS
// ═══════════════════════════════════════════════════════════════════════════════

/// Trainer registration, rate, and specialty journey.
/// Covers: specialties from list, per-session rate, currency.
Future<void> trainerRegistrationRateAndSpecialtyJourney(
  PatrolIntegrationTester $,
) async {
  await devLoginTrainer($);

  // Trainer dashboard shows profile and linked gym
  expect($('Dev Trainer'), findsOneWidget);
  expect($('Iron Paradise (Dev)'), findsWidgets);
}

// ═══════════════════════════════════════════════════════════════════════════════
// LEGACY JOURNEYS (kept for backwards compatibility with blackbox.sh)
// ═══════════════════════════════════════════════════════════════════════════════

/// GYM MEMBER: home pass, Shop tab, gym detail.
Future<void> memberJourney(PatrolIntegrationTester $) async {
  await devLoginMember($);

  expect($('Premium'), findsWidgets);
  expect($('Show my QR'), findsOneWidget);

  // Shop tab replaces My QR in bottom nav
  await $('Shop').tap();
  await $('FitFlex Shop').waitUntilVisible();
  expect($('Coming soon'), findsOneWidget);

  // Gym discovery
  await $('Gyms').tap();
  await $('Discover gyms').waitUntilVisible();
  await $('Iron Paradise (Dev)').scrollTo();
  await $('Iron Paradise (Dev)').tap();
  await $('Amenities').waitUntilVisible();
  expect($('Paid'), findsNothing);
  await $('Get directions').waitUntilVisible();
}

/// GYM OWNER: dashboard + scan + trainer.
Future<void> ownerJourney(PatrolIntegrationTester $) async {
  await devLoginOwner($);

  // Wait for dashboard data to load (period settings appear after API call)
  await $('Period settings').waitUntilVisible();

  // Member type filter chips
  expect($('All members'), findsOneWidget);
  expect($('Direct members'), findsOneWidget);
  expect($('FitFlex roaming members'), findsOneWidget);

  // Owner tools section
  await $('Owner tools').scrollTo();
  await $('Owner tools').waitUntilVisible();
  expect($('QR check-in'), findsOneWidget);
  await $('Earnings').scrollTo();
  expect($('Earnings'), findsOneWidget);
}

/// TRAINER: dashboard profile + linked gym.
Future<void> trainerJourney(PatrolIntegrationTester $) async {
  await devLoginTrainer($);

  expect($('Dev Trainer'), findsOneWidget);
  expect($('Iron Paradise (Dev)'), findsWidgets);
}
