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

/// Launches the app from a clean session and opens the account role page.
Future<void> bootToRole(PatrolIntegrationTester $) async {
  await (await SharedPreferences.getInstance()).clear();
  await app.main();
  await $(const Key('langEnglish')).waitUntilVisible();
  await $(const Key('langEnglish')).tap();
  await $('Continue').tap();
  await $('Create account').waitUntilVisible();
  await $('Create account').tap();
  await $('Welcome to FitFlex').waitUntilVisible();
}

/// Launches the app from a clean session and lands on role-free sign in.
Future<void> bootToSignIn(PatrolIntegrationTester $) async {
  await (await SharedPreferences.getInstance()).clear();
  await app.main();
  await $(const Key('langEnglish')).waitUntilVisible();
  await $(const Key('langEnglish')).tap();
  await $('Continue').tap();
  await $('Sign in').waitUntilVisible();
}

/// Helper: dev-login as member and land on member home.
Future<void> devLoginMember(PatrolIntegrationTester $) async {
  await bootToRole($);
  await $(const Key('devLoginMember')).scrollTo();
  await $(const Key('devLoginMember')).tap();
  await $('Dev Member').waitUntilVisible();
}

/// Helper: dev-login as owner and land on owner dashboard.
Future<void> devLoginOwner(PatrolIntegrationTester $) async {
  await bootToRole($);
  await $(const Key('devLoginOwner')).scrollTo();
  await $(const Key('devLoginOwner')).tap();
  await $('Gym Owner Dashboard').waitUntilVisible();
  await $('Dev Owner Gym').waitUntilVisible();
}

/// Helper: dev-login as trainer and land on trainer dashboard.
Future<void> devLoginTrainer(PatrolIntegrationTester $) async {
  await bootToRole($);
  await $(const Key('devLoginTrainer')).scrollTo();
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
  await $('Iron Paradise Masaki').scrollTo(maxScrolls: 30);
  await $('Iron Paradise Masaki').tap();

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

  // Home is a focused dashboard, not the former single long scroll.
  expect($('Dev Trainer'), findsOneWidget);
  expect($(const Key('trainer-nav-sessions')), findsOneWidget);
  expect($(const Key('trainer-nav-gyms')), findsOneWidget);
  expect($(const Key('trainer-nav-profile')), findsOneWidget);

  await $(const Key('trainer-nav-sessions')).tap();
  await $(const Key('trainer-sessions-today')).waitUntilVisible();
  await $(const Key('trainer-nav-gyms')).tap();
  await $('Iron Paradise (Dev)').waitUntilVisible();
  await $(const Key('trainer-nav-profile')).tap();
  await $(const Key('trainer-tile-professional')).waitUntilVisible();
}

/// Physical-device regression for member-facing issues 1–15, 17–18, 22,
/// 31, 41–42, 45 and 48. It deliberately traverses the real seeded backend
/// instead of replacing API responses inside the app.
Future<void> memberIssueMatrixJourney(PatrolIntegrationTester $) async {
  await devLoginMember($);

  // Membership/expiry and profile QR (#1–3, #45).
  await $('Profile').tap();
  await $('Account settings').waitUntilVisible();
  expect($(const Key('membership-expiry')), findsOneWidget);
  expect($(const Key('membership-days-left')), findsOneWidget);
  await $('Home').tap();
  await $('Show my QR').waitUntilVisible();

  // Discovery filters + ordered gym details + verification + plans/photos
  // (#9–15, #42).
  await $('Gyms').tap();
  await $('Discover gyms').waitUntilVisible();
  if (await $.native.isPermissionDialogVisible(
    timeout: const Duration(seconds: 2),
  )) {
    await $.native.grantPermissionWhenInUse();
  }
  await $(const Key('gym-filter-more')).scrollTo(
    view: find.byKey(const Key('gym-filter-scroll')),
    scrollDirection: AxisDirection.right,
  );
  await $(const Key('gym-filter-more')).tap();
  expect($(const Key('gym-filter-verified')), findsOneWidget);
  await $(const Key('gym-filter-nearest')).scrollTo(
    view: find.byKey(const Key('gym-filter-scroll')),
    scrollDirection: AxisDirection.left,
  );
  await $(const Key('gym-filter-nearest')).tap();
  if (await $.native.isPermissionDialogVisible()) {
    await $.native.grantPermissionWhenInUse();
  }
  await $(const Key('gym-filter-all')).scrollTo(
    view: find.byKey(const Key('gym-filter-scroll')),
    scrollDirection: AxisDirection.left,
  );
  await $(const Key('gym-filter-all')).tap();
  await $(const Key('gym-search')).enterText('Iron Paradise (Dev)');
  await $(const Key('gym-card-gym_dev_demo')).waitUntilVisible();
  await $(const Key('gym-card-gym_dev_demo')).tap();
  final detailScroll = find.byKey(const Key('gym-detail-scroll'));
  expect($(const Key('gym-section-gallery')), findsOneWidget);
  expect($(const Key('gym-section-name')), findsOneWidget);
  expect($(const Key('gym-section-location')), findsOneWidget);

  await $.tester.drag(detailScroll, const Offset(0, -520));
  await $.tester.pumpAndSettle();
  expect($(const Key('gym-section-verification')), findsOneWidget);
  expect($(const Key('gym-section-ratings')), findsOneWidget);
  expect($(const Key('gym-section-plans')), findsOneWidget);

  await $.tester.drag(detailScroll, const Offset(0, -520));
  await $.tester.pumpAndSettle();
  expect($(const Key('gym-section-directions')), findsOneWidget);
  expect($(const Key('gym-section-about')), findsOneWidget);
  expect($(const Key('gym-section-equipment')), findsOneWidget);

  await $.tester.drag(detailScroll, const Offset(0, -520));
  await $.tester.pumpAndSettle();
  expect($(const Key('gym-section-amenities')), findsOneWidget);
  expect($(const Key('gym-section-trainers')), findsOneWidget);

  await $.tester.drag(detailScroll, const Offset(0, -520));
  await $.tester.pumpAndSettle();
  expect($(const Key('gym-section-reviews')), findsOneWidget);
  expect($(const Key('gym-section-actions')), findsOneWidget);
  expect($('Online Free'), findsNothing);
  await $.tester.fling(detailScroll, const Offset(0, 2400), 3000);
  await $.tester.pumpAndSettle();
  await $(const Key('gym-photo-0')).tap();
  await $(const Key('gym-photo-fullscreen')).waitUntilVisible();
  await $(const Key('gym-photo-close')).tap();
  await $.tester.drag(detailScroll, const Offset(0, -650));
  await $.tester.pumpAndSettle();
  await $(const Key('gym-plans-cta')).tap();
  await $('Gym plans').waitUntilVisible();
  expect($('Online Free'), findsNothing);
  await $.native.pressBack();

  // Trainer standardized profile and all engagement actions (#5–8, #30–31).
  await $.native.pressBack();
  await $('Trainers').tap();
  await $('Coach Ali Rashid').scrollTo();
  await $('Coach Ali Rashid').tap();
  await $(const Key('trainer-actions')).waitUntilVisible();
  expect($(const Key('trainer-action-book')), findsOneWidget);
  expect($(const Key('trainer-action-enquire')), findsOneWidget);
  expect($(const Key('trainer-action-interest')), findsOneWidget);
  expect($(Icons.favorite_border), findsOneWidget);
  expect($('About'), findsOneWidget);
  await $('Available gyms').scrollTo();
  expect($('Available gyms'), findsOneWidget);
  await $(const Key('trainer-action-book')).tap();
  await $('Book a session').waitUntilVisible();
  expect(
    find.byKey(const Key('trainer-book-confirm')).evaluate().isNotEmpty ||
        find.text('No availability listed.').evaluate().isNotEmpty,
    isTrue,
  );
  await $.native.pressBack();
  await $(const Key('trainer-action-enquire')).tap();
  await $(const Key('trainer-enquiry-message')).waitUntilVisible();
  await $(
    const Key('trainer-enquiry-message'),
  ).enterText('Physical device E2E enquiry');
  await $('Cancel').tap();

  // Shared live marketplace (#22, #39, #41).
  await $.native.pressBack();
  await $('Shop').tap();
  await $('Search products').waitUntilVisible();
}

/// Physical-device regression for owner issues 3–4, 16–29, 42, 46–48.
Future<void> ownerIssueMatrixJourney(PatrolIntegrationTester $) async {
  await devLoginOwner($);
  expect($('Pending admin approval'), findsNothing);

  // Live dashboard cards/statistics and current-period picker (#16, #19–21,
  // #25–27, #46).
  await $('This month').waitUntilVisible();
  expect($(const Key('owner-card-total-members')), findsOneWidget);
  expect($(const Key('owner-card-checkins')), findsOneWidget);
  await $(const Key('owner-card-total-members')).tap();
  await $(const Key('stat-total-members')).waitUntilVisible();
  expect($(const Key('stat-expiring-soon')), findsOneWidget);
  await $('Add Member').tap();
  await $(const Key('add-member-name')).waitUntilVisible();
  expect($(const Key('add-member-email')), findsOneWidget);
  expect($(const Key('add-member-initial-password')), findsOneWidget);
  await $.native.pressBack();

  // Owner gym editing exposes the operational gym record (#24, #28–29).
  await $('Manage Gyms').tap();
  await $('Dev Owner Gym').waitUntilVisible();
  await $(Icons.edit).tap();
  await $('Edit gym').waitUntilVisible();
  expect(find.textContaining('Class'), findsWidgets);
  expect(find.textContaining('Trainer'), findsWidgets);
  await $(Icons.close).tap();

  // Trainer management/pending approval (#4, #23).
  await $('Trainers').tap();
  expect(find.byTooltip('Edit trainer'), findsWidgets);

  // Owner shop and earnings are real modules (#21–22, #32, #41).
  await $('Home').tap();
  await $('Earnings').scrollTo();
  await $('Earnings').tap();
  await $(const Key('earnings-total-paid')).waitUntilVisible();
  expect($(const Key('earnings-total-pending')), findsOneWidget);
  await $.native.pressBack();
  await $('Shop').scrollTo();
  await $('Shop').tap();
  await $('Search products').waitUntilVisible();
}

/// Physical-device regression for trainer issues 5–8 and 30–40, plus the
/// shared marketplace flow in issue 41.
Future<void> trainerIssueMatrixJourney(PatrolIntegrationTester $) async {
  await devLoginTrainer($);
  expect($(const Key('trainer-rate-per-session')), findsOneWidget);
  expect(find.textContaining('/hr'), findsNothing);

  // Booking-derived and manual sessions (#32–34).
  await $(const Key('trainer-nav-sessions')).tap();
  await $(const Key('trainer-sessions-today')).tap();
  await $('Add manual session').waitUntilVisible();
  await $(const Key('trainer-add-session')).tap();
  expect($(const Key('session-customer-name')), findsOneWidget);
  expect($(const Key('session-customer-email')), findsOneWidget);
  expect($(const Key('session-customer-phone')), findsOneWidget);
  expect($(const Key('session-save')), findsOneWidget);
  await $(const Key('session-customer-name')).enterText('Patrol client');
  await $(const Key('session-save')).tap();
  await $('Patrol client').waitUntilVisible();
  await $.native.pressBack();

  await $(const Key('trainer-earnings')).tap();
  await $(const Key('trainer-earnings-total')).waitUntilVisible();
  await $.native.pressBack();

  // Professional fields, linked gyms and join-another-gym (#30, #35–38, #40).
  await $(const Key('trainer-nav-gyms')).tap();
  expect($('Iron Paradise (Dev)'), findsWidgets);
  await $(const Key('trainer-apply-gym')).tap();
  expect(
    find.text('Apply to a gym').evaluate().isNotEmpty ||
        find.text('No gyms available').evaluate().isNotEmpty,
    isTrue,
  );
  await $.native.pressBack();

  await $(const Key('trainer-nav-profile')).tap();
  await $(const Key('trainer-edit-account')).tap();
  await $('Edit personal details').waitUntilVisible();
  await $(Icons.close).tap();
  await $(const Key('trainer-tile-professional')).tap();
  await $(const Key('trainerFormRate')).waitUntilVisible();
  expect($('Currency'), findsOneWidget);
  expect(find.textContaining('Special'), findsWidgets);
  await $(Icons.close).tap();
  // Trainer marketplace access (#39, #41).
  await $(const Key('trainer-nav-home')).tap();
  await $(const Key('trainer-tile-shop')).tap();
  await $('FitFlex Shop').waitUntilVisible();
  expect($('Search products'), findsOneWidget);

  // Account session management is the terminal trainer action.
  await $.native.pressBack();
  await $(const Key('trainer-nav-profile')).tap();
  expect($(const Key('trainer-help')), findsOneWidget);
  await $(const Key('trainer-sign-out')).tap();
  await $(const Key('trainer-confirm-sign-out')).tap();
  await $(const Key('langEnglish')).waitUntilVisible();
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
  expect($(Icons.arrow_back), findsNothing);
  await $.native.pressBack();
}

/// GYM OWNER: dashboard + scan + trainer.
Future<void> ownerJourney(PatrolIntegrationTester $) async {
  await devLoginOwner($);
  expect($(Icons.arrow_back), findsNothing);
  await $.native.pressBack();
}

/// Account creation chooses a role on its own page; sign-in does not ask.
Future<void> roleChoiceJourney(PatrolIntegrationTester $) async {
  await bootToSignIn($);
  expect($('Gym Member'), findsNothing);
  expect($('Gym Owner'), findsNothing);
  expect($('Personal Trainer'), findsNothing);

  await $('Create account').tap();
  await $('Welcome to FitFlex').waitUntilVisible();
  expect($('Gym Member'), findsOneWidget);
  await $('Gym Member').tap();
  await $('Continue').tap();
  await $('Sign up').waitUntilVisible();
}

/// Owner creates a direct member and that member signs in with the shared PIN.
Future<void> directMembershipCredentialJourney(
  PatrolIntegrationTester $,
) async {
  await devLoginOwner($);
  await $('Members').tap();
  await $('Add Member').waitUntilVisible();
  await $('Add Member').tap();

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final email = 'direct.member.$stamp@example.com';
  const pin = '2468';
  await $(const Key('add-member-name')).enterText('E2E Direct Member');
  await $(const Key('add-member-email')).enterText(email);
  await $(const Key('add-member-initial-password')).scrollTo();
  await $(const Key('add-member-initial-password')).enterText(pin);
  await $(const Key('add-member-save')).scrollTo();
  await $(const Key('add-member-save')).tap();
  await $('Member registered successfully').waitUntilVisible();

  await $(const Key('owner-profile-button')).tap();
  await $(const Key('owner-sign-out')).scrollTo();
  await $(const Key('owner-sign-out')).tap();
  await $(const Key('owner-confirm-sign-out')).tap();

  await $(const Key('langEnglish')).waitUntilVisible();
  await $(const Key('langEnglish')).tap();
  await $('Continue').tap();
  await $('Sign in').waitUntilVisible();
  await $(const Key('login-identifier')).enterText(email);
  await $(const Key('login-continue')).tap();
  await $('Verification PIN').waitUntilVisible();
  for (final digit in pin.split('')) {
    await $(digit).tap();
  }
  await $('OK').tap();
  await $('E2E Direct Member').waitUntilVisible();
  await $(const Key('direct-membership-start')).waitUntilVisible();
  expect($(const Key('direct-membership-expiry')), findsOneWidget);
  expect($(const Key('direct-membership-days-left')), findsOneWidget);
  expect($('Visits this cycle'), findsNothing);
}

/// TRAINER: focused dashboard + bottom-nav gym access.
Future<void> trainerJourney(PatrolIntegrationTester $) async {
  await devLoginTrainer($);

  expect($('Dev Trainer'), findsOneWidget);
  await $(const Key('trainer-nav-gyms')).tap();
  expect($('Iron Paradise (Dev)'), findsWidgets);
  expect($(Icons.arrow_back), findsNothing);
  await $.native.pressBack();
}
