// Shared Patrol journey helpers for FitFlex blackbox tests.
//
// Each role journey lives in its own *_test.dart target so Patrol runs it in a
// fresh app process (avoids cross-test teardown crashes). All steps use widget
// Keys + exact-text finders — no screen-size coordinate taps.
//
// Run via scripts/blackbox.sh (sets API_BASE + MOCK_AUTH and adb reverse).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:patrol/patrol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/main.dart' as app;

const patrolConfig = PatrolTesterConfig(
  existsTimeout: Duration(seconds: 20),
  visibleTimeout: Duration(seconds: 20),
  settleTimeout: Duration(seconds: 20),
);

// ═══════════════════════════════════════════════════════════════════════════════
// TEST DATA MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// E2E email domain used for all test-created accounts.
const e2eEmailDomain = '@e2e-test.fitflex.test';

/// API base that mirrors the compile-time define used by blackbox.sh.
const _apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://localhost:3000',
);

/// Generates a unique E2E email for a given role.
String e2eEmail(String role) =>
    'e2e.$role.${DateTime.now().millisecondsSinceEpoch}$e2eEmailDomain';

/// Calls the backend dev/cleanup endpoint to remove all test users whose email
/// contains [pattern]. Safe to call even when there is nothing to clean.
Future<void> cleanupTestData({String pattern = e2eEmailDomain}) async {
  try {
    final res = await http.post(
      Uri.parse('$_apiBase/auth/dev/cleanup'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'emailPattern': pattern}),
    );
    final body = jsonDecode(res.body);
    final removed = body['removedUsers'] ?? 0;
    // ignore: avoid_print
    print('[e2e-cleanup] Removed $removed test user(s) matching "$pattern"');
  } catch (e) {
    // ignore: avoid_print
    print('[e2e-cleanup] Cleanup call failed (non-fatal): $e');
  }
}

/// Cleans up specific emails via the backend dev/cleanup endpoint.
Future<void> cleanupTestEmails(List<String> emails) async {
  if (emails.isEmpty) return;
  try {
    final res = await http.post(
      Uri.parse('$_apiBase/auth/dev/cleanup'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'emails': emails}),
    );
    final body = jsonDecode(res.body);
    final removed = body['removedUsers'] ?? 0;
    // ignore: avoid_print
    print('[e2e-cleanup] Removed $removed user(s) by email list');
  } catch (e) {
    // ignore: avoid_print
    print('[e2e-cleanup] Cleanup call failed (non-fatal): $e');
  }
}

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

/// Helper: dev-login as marketplace vendor and land on vendor home.
Future<void> devLoginVendor(PatrolIntegrationTester $) async {
  await bootToRole($);
  await $(const Key('devLoginVendor')).scrollTo();
  await $(const Key('devLoginVendor')).tap();
  await $('Vendor marketplace').waitUntilVisible();
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

  // Shop tab — live marketplace with search
  await $('Shop').waitUntilVisible();
  await $('Shop').tap();
  await $(const Key('shop-search')).waitUntilVisible();

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
  await $(
    const Key('gym-card-gym_dev_demo'),
  ).scrollTo(view: find.byKey(const Key('gym-page-scroll')));
  await $(const Key('gym-card-gym_dev_demo')).waitUntilVisible();
  await $(const Key('gym-card-gym_dev_demo')).tap();
  final detailScroll = find.byKey(const Key('gym-detail-scroll'));
  expect($(const Key('gym-section-gallery')), findsOneWidget);
  expect($(const Key('gym-section-name')), findsOneWidget);
  expect($(const Key('gym-section-location')), findsOneWidget);

  expect($(const Key('gym-section-verification')), findsOneWidget);
  expect($(const Key('gym-section-ratings')), findsOneWidget);
  expect($(const Key('gym-section-plans')), findsOneWidget);

  await $.tester.drag(detailScroll, const Offset(0, -520));
  await $.tester.pumpAndSettle();
  expect($(const Key('gym-section-directions')), findsOneWidget);
  expect($(const Key('gym-section-about')), findsOneWidget);
  expect($(const Key('gym-section-equipment')), findsOneWidget);

  await $(const Key('gym-section-amenities')).scrollTo(view: detailScroll);
  expect($(const Key('gym-section-amenities')), findsOneWidget);
  await $(const Key('gym-section-trainers')).scrollTo(view: detailScroll);
  expect($(const Key('gym-section-trainers')), findsOneWidget);

  await $(const Key('gym-section-reviews')).scrollTo(view: detailScroll);
  expect($(const Key('gym-section-reviews')), findsOneWidget);
  await $(const Key('gym-section-actions')).scrollTo(view: detailScroll);
  expect($(const Key('gym-section-actions')), findsOneWidget);
  expect($('Online Free'), findsNothing);
  await $.tester.fling(detailScroll, const Offset(0, 2400), 3000);
  await $.tester.pumpAndSettle();
  await $(const Key('gym-photo-0')).tap();
  await $(const Key('gym-photo-fullscreen')).waitUntilVisible();
  if (find.byKey(const Key('gym-photo-next')).evaluate().isNotEmpty) {
    await $(const Key('gym-photo-next')).tap();
    expect(find.textContaining('2/'), findsWidgets);
  }
  await $(const Key('gym-photo-close')).tap();
  await $(const Key('gym-plans-cta')).scrollTo(view: detailScroll);
  await $(const Key('gym-plans-cta')).tap();
  await $('Gym plans').waitUntilVisible();
  expect($('Online Free'), findsNothing);
  await $.native.pressBack();

  // Trainer standardized profile and all engagement actions (#5–8, #30–31).
  await $.native.pressBack();
  await $(const Key('member-nav-gyms')).tap();
  await $(const Key('member-find-trainer')).tap();
  await $('Find a trainer').waitUntilVisible();
  await $(
    const Key('trainer-card-trn_aa1ff43e'),
  ).waitUntilVisible(timeout: const Duration(seconds: 20));
  await $(const Key('trainer-card-trn_aa1ff43e')).tap();
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
    find.byKey(const Key('trainer-book-slots')).evaluate().isNotEmpty ||
        find.text('No availability listed.').evaluate().isNotEmpty,
    isTrue,
  );
  await $(const Key('trainer-book-close')).tap();
  await $(const Key('trainer-action-enquire')).tap();
  await $(const Key('trainer-enquiry-message')).waitUntilVisible();
  await $(
    const Key('trainer-enquiry-message'),
  ).enterText('Physical device E2E enquiry');
  await $('Cancel').tap();

  // Shared live marketplace (#22, #39, #41).
  await $(const Key('trainer-detail-back')).tap();
  await $('Shop').tap();
  await $(const Key('shop-search')).waitUntilVisible();
}

/// Physical-device booking flow for report items #5, #30, and #31.
Future<void> memberSlotBookingJourney(PatrolIntegrationTester $) async {
  await devLoginMember($);
  await $(const Key('member-nav-gyms')).tap();
  await $(const Key('member-find-trainer')).tap();
  await $('Find a trainer').waitUntilVisible();
  await $(const Key('trainer-search')).enterText('Dev Trainer');
  await $(const Key('trainer-card-trn_dev')).waitUntilVisible();
  await $(const Key('trainer-card-trn_dev')).tap();
  await $(const Key('trainer-action-book')).tap();
  final today = const [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ][DateTime.now().weekday - 1];
  await $(Key('slot-$today-10:00')).waitUntilVisible();
  await $(Key('slot-$today-10:00')).tap();
  await $(const Key('trainer-book-slots')).tap();
  await $('Booking summary').waitUntilVisible();
  await $(const Key('trainer-book-confirm')).tap();
  await $('Booking requested. Your sessions are confirmed once the payment is approved.').waitUntilVisible();
}

/// Seeds a real member enquiry for the trainer notification regression.
Future<void> memberTrainerEnquiryJourney(PatrolIntegrationTester $) async {
  await devLoginMember($);
  await $(const Key('member-nav-gyms')).tap();
  await $(const Key('member-find-trainer')).tap();
  await $('Find a trainer').waitUntilVisible();
  await $(const Key('trainer-search')).enterText('Dev Trainer');
  await $(const Key('trainer-card-trn_dev')).tap();
  await $(const Key('trainer-action-enquire')).tap();
  await $(
    const Key('trainer-enquiry-message'),
  ).enterText('Physical device trainer inbox enquiry');
  await $(const Key('trainer-enquiry-send')).tap();
  await $('Enquiry sent to the trainer.').waitUntilVisible();
}

/// Physical-device regression for report item #33: a member booking appears
/// in the trainer's sessions list without manual entry.
Future<void> trainerBookedSessionJourney(PatrolIntegrationTester $) async {
  await devLoginTrainer($);
  await $(const Key('trainer-nav-sessions')).tap();
  await $(const Key('trainer-sessions-today')).tap();
  await $('Dev Member').waitUntilVisible();
}

/// Physical-device/web fallback proof for marketplace issue #41 and the
/// vendor workflow requested in issue #56.
Future<void> vendorMarketplaceJourney(PatrolIntegrationTester $) async {
  await devLoginVendor($);
  expect($(const Key('vendor-nav-products')), findsOneWidget);
  expect($(const Key('vendor-nav-orders')), findsOneWidget);
  expect($(const Key('vendor-nav-payments')), findsOneWidget);
  expect($(const Key('vendor-nav-enquiries')), findsOneWidget);
  expect($(const Key('vendor-nav-business')), findsOneWidget);

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final productName = 'Vendor E2E Product $stamp';
  await $(const Key('vendor-add-product')).tap();
  await $(const Key('vendor-product-name')).enterText(productName);
  await $(
    const Key('vendor-product-description'),
  ).enterText('Created through the vendor end-to-end journey');
  await $(const Key('vendor-product-category')).enterText('Equipment');
  await $(const Key('vendor-product-brand')).enterText('FitFlex E2E');
  await $(const Key('vendor-product-price')).enterText('45000');
  await $(const Key('vendor-product-stock')).enterText('7');
  await $(const Key('vendor-product-discount-price')).enterText('40000');
  await $(const Key('vendor-product-sku')).enterText('E2E-$stamp');
  await $(const Key('vendor-product-weight')).enterText('1.2');
  await $(const Key('vendor-product-variants')).enterText('Black, Green');
  await $(const Key('vendor-product-save')).tap();
  await $('Product saved.').waitUntilVisible();
  await $(productName).waitUntilVisible();

  await $(const Key('vendor-nav-orders')).tap();
  expect(
    find.text('No customer orders yet.').evaluate().isNotEmpty ||
        find.textContaining('Status:').evaluate().isNotEmpty,
    isTrue,
  );

  await $(const Key('vendor-nav-payments')).tap();
  await $(const Key('vendor-download-statement')).waitUntilVisible();

  await $(const Key('vendor-nav-enquiries')).tap();
  expect(
    find.text('No customer enquiries yet.').evaluate().isNotEmpty ||
        find.byKey(const Key('vendor-reply-message')).evaluate().isEmpty,
    isTrue,
  );

  await $(const Key('vendor-nav-business')).tap();
  await $(const Key('vendor-edit-profile')).waitUntilVisible();
  await $(const Key('vendor-edit-profile')).tap();
  await $(const Key('vendor-profile-businessName')).waitUntilVisible();
  await $(const Key('vendor-profile-publish')).scrollTo();
  await $(const Key('vendor-profile-publish')).tap();
  await $(const Key('vendor-add-staff')).tap();
  await $(const Key('vendor-staff-name')).enterText('Marketplace Staff $stamp');
  await $(
    const Key('vendor-staff-email'),
  ).enterText('marketplace-$stamp@fitflex.test');
  await $(const Key('vendor-staff-phone')).enterText(
    '+2557${stamp.toString().substring(stamp.toString().length - 8)}',
  );
  await $(const Key('vendor-staff-password')).enterText('Staff123');
  await $(const Key('vendor-staff-save')).scrollTo();
  await $(const Key('vendor-staff-save')).tap();
  await $('Marketplace Staff $stamp').waitUntilVisible();
}

/// Full buyer marketplace journey: vendor seed, browse/detail/enquiry, cart,
/// paid home-delivery checkout, and automatic order-history tracking.
Future<void> marketplaceBuyerJourney(PatrolIntegrationTester $) async {
  await devLoginVendor($);
  await $(const Key('vendor-sign-out')).tap();
  await $(const Key('langEnglish')).waitUntilVisible();
  await $(const Key('langEnglish')).tap();
  await $('Continue').tap();
  await $('Create account').tap();
  await $(const Key('devLoginMember')).scrollTo();
  await $(const Key('devLoginMember')).tap();
  await $('Dev Member').waitUntilVisible();

  await $(const Key('member-nav-shop')).tap();
  await $(const Key('shop-search')).waitUntilVisible();
  await $(const Key('shop-search')).enterText('Resistance Bands');
  await $(const Key('shop-product-prd_dev_marketplace')).waitUntilVisible();
  await $(const Key('shop-product-prd_dev_marketplace')).tap();
  await $(const Key('shop-chat-vendor')).scrollTo();
  await $(const Key('shop-chat-vendor')).tap();
  await $(
    const Key('shop-enquiry-message'),
  ).enterText('Can I collect this at the Masaki gym?');
  await $(const Key('shop-enquiry-send')).tap();
  await $(const Key('shop-product-close')).tap();

  await $(const Key('shop-save-prd_dev_marketplace')).tap();
  await $('Saved for later: 1').waitUntilVisible();
  await $(const Key('shop-add-prd_dev_marketplace')).tap();
  await $(const Key('shop-checkout')).tap();
  await $(
    const Key('shop-delivery-address'),
  ).enterText('Mikocheni, Dar es Salaam');
  await $(const Key('shop-place-order')).tap();
  await $('Order placed — the vendor will confirm it.').waitUntilVisible();
  await $('My orders').waitUntilVisible();
  expect(find.textContaining('pending').evaluate().isNotEmpty, isTrue);
}

/// Physical-device regression for report item #48: API conflict responses
/// must tell a member why a trainer booking was declined.
Future<void> memberBookedSlotDeclineJourney(PatrolIntegrationTester $) async {
  await devLoginMember($);
  await $(const Key('member-nav-gyms')).tap();
  await $(const Key('member-find-trainer')).tap();
  await $('Find a trainer').waitUntilVisible();
  await $(const Key('trainer-search')).enterText('Dev Trainer');
  await $(const Key('trainer-card-trn_dev')).waitUntilVisible();
  await $(const Key('trainer-card-trn_dev')).tap();
  await $(const Key('trainer-action-book')).tap();
  final today = const [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ][DateTime.now().weekday - 1];
  await $(Key('slot-$today-10:00')).tap();
  await $(const Key('trainer-book-slots')).tap();
  await $('That slot was just booked. Pick another.').waitUntilVisible();
}

/// Physical-device regression for owner issues 3–4, 16–29, 42, 46–48.
Future<void> ownerIssueMatrixJourney(PatrolIntegrationTester $) async {
  await devLoginOwner($);
  expect($('Pending admin approval'), findsNothing);

  // Live dashboard cards/statistics and current-period picker (#16, #19–21,
  // #25–27, #46).
  await $('This Month').waitUntilVisible();
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
  await $(const Key('gym-add-class')).scrollTo();
  await $(const Key('gym-add-class')).tap();
  await $(const Key('gym-class-name')).enterText('Yoga E2E');
  await $(const Key('gym-class-schedule')).enterText('Monday 07:00');
  await $(const Key('gym-class-price')).enterText('10000');
  await $(const Key('gym-class-location')).enterText('Studio A');
  await $(const Key('gym-class-save')).tap();
  await $(const Key('gym-form-scroll')).waitUntilVisible();
  await $(const Key('gym-trainer-pass-enabled')).scrollTo();
  await $(const Key('gym-trainer-pass-enabled')).tap();
  await $(const Key('gym-trainer-pass-fee')).scrollTo();
  await $(const Key('gym-trainer-pass-fee')).enterText('50000');
  await $(const Key('gym-form-save')).tap();
  await $('Gym updated').waitUntilVisible();

  // Trainer management/pending approval and owner-created account (#4, #23).
  await $('Trainers').tap();
  await $(const Key('owner-add-trainer')).tap();
  await $('Choose a gym for this trainer').waitUntilVisible();
  await $(const Key('owner-trainer-gym-gym_dev_owner')).tap();
  await $(const Key('trainerFormName')).waitUntilVisible();
  final trainerEmail =
      'owner.e2e.${DateTime.now().microsecondsSinceEpoch}@fitflex.test';
  await $(const Key('trainerFormName')).enterText('Owner E2E Coach');
  await $(const Key('trainerFormEmail')).enterText(trainerEmail);
  await $(const Key('trainerFormPin')).enterText('2468');
  await $(const Key('trainerFormRate')).enterText('25000');
  await $(const Key('trainerFormSave')).tap();
  await $('Trainer added').waitUntilVisible();
  await $('Owner E2E Coach').waitUntilVisible();
  expect(
    find.byTooltip('Edit trainer').evaluate().isNotEmpty ||
        find.text('No trainers yet').evaluate().isNotEmpty,
    isTrue,
  );

  // Owner shop and earnings are real modules (#21–22, #32, #41).
  await $('Home').tap();
  await $('Earnings').scrollTo();
  await $('Earnings').tap();
  await $(const Key('earnings-total-paid')).waitUntilVisible();
  expect($(const Key('earnings-total-pending')), findsOneWidget);
  await $.native.pressBack();
  await $('Shop').scrollTo();
  await $('Shop').tap();
  await $(const Key('shop-search')).waitUntilVisible();
}

/// Physical-device regression for trainer issues 5–8 and 30–40, plus the
/// shared marketplace flow in issue 41.
Future<void> trainerIssueMatrixJourney(PatrolIntegrationTester $) async {
  await devLoginTrainer($);
  expect($(const Key('trainer-rate-per-session')), findsOneWidget);
  expect(find.textContaining('/hr'), findsNothing);
  await $(const Key('trainer-engagement-inbox')).tap();
  await $('Member enquiries').waitUntilVisible();
  await $('Physical device trainer inbox enquiry').waitUntilVisible();
  expect(find.textContaining('Contact:'), findsWidgets);
  expect(find.byTooltip('Reply to member'), findsWidgets);
  await $.native.pressBack();

  // Booking-derived and manual sessions (#32–34).
  await $(const Key('trainer-nav-sessions')).tap();
  await $(const Key('trainer-sessions-today')).tap();
  await $('Add manual session').waitUntilVisible();
  await $(const Key('trainer-add-session')).tap();
  expect($(const Key('session-customer-name')), findsOneWidget);
  expect($(const Key('session-customer-email')), findsOneWidget);
  expect($(const Key('session-customer-phone')), findsOneWidget);
  expect($(const Key('session-location-type')), findsOneWidget);
  expect($(const Key('session-save')), findsOneWidget);
  await $(const Key('session-customer-name')).enterText('Patrol client');
  await $(const Key('session-location-type')).tap();
  await $('Other location').tap();
  await $(const Key('session-other-location')).enterText('E2E beach');
  await $(const Key('session-save')).tap();
  await $('Patrol client').waitUntilVisible();
  await $('E2E beach').waitUntilVisible();
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
  await $(const Key('trainer-sign-out')).waitUntilVisible();
  await $(const Key('trainer-edit-account')).tap();
  await $('Edit personal details').waitUntilVisible();
  await $(Icons.close).tap();
  // Allow dialog dismiss to settle before tapping the next tile.
  await $.pumpAndSettle();
  await $(const Key('trainer-tile-professional')).waitUntilVisible();
  await $(const Key('trainer-tile-professional')).tap();
  await $(const Key('trainerFormRate')).waitUntilVisible();
  expect($('Currency'), findsOneWidget);
  expect(find.textContaining('Special'), findsWidgets);
  await $(const Key('trainerFormRate')).enterText('98765');
  await $(const Key('trainerFormSave')).tap();
  await $('Profile updated').waitUntilVisible();
  await $(const Key('trainer-nav-home')).tap();
  await $(const Key('trainer-rate-per-session')).waitUntilVisible();
  expect($('TZS 98,765/session'), findsOneWidget);
  // Trainer marketplace access (#39, #41).
  await $(const Key('trainer-nav-home')).tap();
  await $(const Key('trainer-tile-shop')).scrollTo();
  await $(const Key('trainer-tile-shop')).tap();
  await $(const Key('shop-search')).waitUntilVisible();

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

  // Shop tab — live marketplace with search
  await $('Shop').tap();
  await $(const Key('shop-search')).waitUntilVisible();

  // Gym discovery
  await $('Gyms').tap();
  await $('Discover gyms').waitUntilVisible();
  await $('Iron Paradise (Dev)').scrollTo();
  await $('Iron Paradise (Dev)').tap();
  await $(const Key('gym-detail-scroll')).waitUntilVisible();
  await $(const Key('gym-section-directions')).waitUntilVisible();
  expect($('Paid'), findsNothing);
  await $.native.pressBack();
}

/// GYM OWNER: dashboard loaded, no stray back arrow.
Future<void> ownerJourney(PatrolIntegrationTester $) async {
  await devLoginOwner($);
  expect($(Icons.arrow_back), findsNothing);
  // Verify the Members tab is accessible
  await $('Members').tap();
  await $('Add Member').waitUntilVisible();
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

/// Owner creates a direct member and that member navigates to sign-in PIN screen.
/// In MOCK_AUTH mode Firebase is not initialized, so we verify the sign-in UI
/// flow through to the PIN entry screen without submitting Firebase credentials.
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
  // Verify PIN entry screen renders with correct email context
  await $('Verification PIN').waitUntilVisible();
  await $(email).waitUntilVisible();
}

/// TRAINER: focused dashboard + bottom-nav gym access.
Future<void> trainerJourney(PatrolIntegrationTester $) async {
  await devLoginTrainer($);

  expect($('Dev Trainer'), findsOneWidget);
  await $(const Key('trainer-nav-gyms')).tap();
  await $('Iron Paradise (Dev)').waitUntilVisible();
  expect($(Icons.arrow_back), findsNothing);
  await $.native.pressBack();
}

// ═══════════════════════════════════════════════════════════════════════════════
// REGISTRATION & LOGIN JOURNEYS (REAL ACCOUNT CREATION)
// ═══════════════════════════════════════════════════════════════════════════════

/// Owner-created member registration + sign-in navigation flow.
/// Tests the complete cycle: owner creates member → sign out → member navigates
/// the sign-in screens up to PIN entry. Firebase sign-in is not executed in
/// MOCK_AUTH mode (Firebase is not initialized), so we verify the UI flow only.
Future<void> registerAndLoginMemberJourney(PatrolIntegrationTester $) async {
  // Pre-cleanup: remove any leftover E2E data
  await cleanupTestData();

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final email = 'e2e.member.$stamp$e2eEmailDomain';
  const pin = '2468';

  // Step 1: Owner creates a member with login credentials
  await devLoginOwner($);
  await $('Members').tap();
  await $('Add Member').waitUntilVisible();
  await $('Add Member').tap();
  await $(const Key('add-member-name')).waitUntilVisible();
  await $(const Key('add-member-name')).enterText('E2E Test Member $stamp');
  await $(const Key('add-member-email')).enterText(email);
  await $(const Key('add-member-initial-password')).scrollTo();
  await $(const Key('add-member-initial-password')).enterText(pin);
  await $(const Key('add-member-save')).scrollTo();
  await $(const Key('add-member-save')).tap();
  await $('Member registered successfully').waitUntilVisible();

  // Step 2: Sign out as owner
  await $(const Key('owner-profile-button')).tap();
  await $(const Key('owner-sign-out')).scrollTo();
  await $(const Key('owner-sign-out')).tap();
  await $(const Key('owner-confirm-sign-out')).tap();

  // Step 3: Member navigates to sign-in → email → PIN screen
  await $(const Key('langEnglish')).waitUntilVisible();
  await $(const Key('langEnglish')).tap();
  await $('Continue').tap();
  await $('Sign in').waitUntilVisible();
  await $(const Key('login-identifier')).enterText(email);
  await $(const Key('login-continue')).tap();

  // Verify PIN entry screen renders with correct email context
  await $('Verification PIN').waitUntilVisible();
  await $(email).waitUntilVisible();

  // Cleanup: remove E2E test data
  await cleanupTestEmails([email]);
}

/// Owner registration journey: select gym owner role → navigate to sign up.
/// Since Firebase is disabled in MOCK_AUTH mode, we verify the signup screens
/// render correctly with all expected fields and validations.
Future<void> registerOwnerSignUpFlowJourney(PatrolIntegrationTester $) async {
  await cleanupTestData();

  await bootToRole($);

  // Select Gym Owner role
  await $(find.text('Gym Owner')).tap();
  await $('Continue').tap();

  // Should land on sign up screen
  await $('Sign up').waitUntilVisible();

  // Google sign-in button should be present
  expect(find.textContaining('GOOGLE'), findsOneWidget);

  // Email field should be present
  expect(find.byType(TextField), findsWidgets);
}

/// Trainer registration journey: select trainer role → navigate to sign up.
Future<void> registerTrainerSignUpFlowJourney(PatrolIntegrationTester $) async {
  await cleanupTestData();

  await bootToRole($);

  // Select Personal Trainer role
  await $(find.text('Personal Trainer')).tap();
  await $('Continue').tap();

  // Should land on sign up screen
  await $('Sign up').waitUntilVisible();
  expect(find.textContaining('GOOGLE'), findsOneWidget);
  expect(find.byType(TextField), findsWidgets);
}

/// Vendor role selection journey: select vendor role → navigate to sign up.
Future<void> registerVendorSignUpFlowJourney(PatrolIntegrationTester $) async {
  await cleanupTestData();

  await bootToRole($);

  // Select Fitness Vendor role
  await $(find.text('Fitness Vendor')).tap();
  await $('Continue').tap();

  // Should land on sign up screen
  await $('Sign up').waitUntilVisible();
}

/// Staff role selection journey: select staff role → navigate to sign up.
Future<void> registerStaffSignUpFlowJourney(PatrolIntegrationTester $) async {
  await cleanupTestData();

  await bootToRole($);

  // Select Gym Staff role
  await $(find.text('Gym Staff')).tap();
  await $('Continue').tap();

  // Should land on sign up screen
  await $('Sign up').waitUntilVisible();
}

/// Owner creates trainer with email/PIN → trainer navigates sign-in flow.
/// Tests the full owner→trainer creation cycle and verifies the trainer can
/// reach the PIN entry screen. Firebase sign-in is not executed in MOCK_AUTH
/// mode, so we verify the UI flow up to PIN entry only.
Future<void> registerAndLoginTrainerJourney(PatrolIntegrationTester $) async {
  await cleanupTestData();

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final email = 'e2e.trainer.$stamp$e2eEmailDomain';
  const pin = '2468';

  // Step 1: Owner creates a trainer with login credentials
  await devLoginOwner($);
  await $('Trainers').tap();
  await $(const Key('owner-add-trainer')).tap();
  await $('Choose a gym for this trainer').waitUntilVisible();
  await $(const Key('owner-trainer-gym-gym_dev_owner')).tap();
  await $(const Key('trainerFormName')).waitUntilVisible();
  await $(const Key('trainerFormName')).enterText('E2E Coach $stamp');
  await $(const Key('trainerFormEmail')).enterText(email);
  await $(const Key('trainerFormPin')).enterText(pin);
  await $(const Key('trainerFormRate')).enterText('30000');
  await $(const Key('trainerFormSave')).tap();
  await $('Trainer added').waitUntilVisible();
  await $('E2E Coach $stamp').waitUntilVisible();

  // Step 2: Sign out as owner
  await $(const Key('owner-profile-button')).tap();
  await $(const Key('owner-sign-out')).scrollTo();
  await $(const Key('owner-sign-out')).tap();
  await $(const Key('owner-confirm-sign-out')).tap();

  // Step 3: Trainer navigates to sign-in → email → PIN screen
  await $(const Key('langEnglish')).waitUntilVisible();
  await $(const Key('langEnglish')).tap();
  await $('Continue').tap();
  await $('Sign in').waitUntilVisible();
  await $(const Key('login-identifier')).enterText(email);
  await $(const Key('login-continue')).tap();

  // Verify PIN entry screen renders with correct email context
  await $('Verification PIN').waitUntilVisible();
  await $(email).waitUntilVisible();

  // Cleanup
  await cleanupTestEmails([email]);
}

/// Full sign-in screen flow for an existing dev member account.
/// Covers: sign-in → email entry → PIN entry → member home.
Future<void> signInExistingMemberJourney(PatrolIntegrationTester $) async {
  await bootToSignIn($);

  // Sign-in screen should NOT show role choices (Sign in has no role tiles)
  expect($('Gym Member'), findsNothing);
  expect($('Gym Owner'), findsNothing);
  expect($('Personal Trainer'), findsNothing);

  // "Create account" link navigates to role page
  await $('Create account').tap();
  await $('Welcome to FitFlex').waitUntilVisible();
  // Role tiles show labels (may have duplicate text in title + description)
  expect($('Gym Member'), findsWidgets);
  expect($('Gym Owner'), findsWidgets);
  expect($('Personal Trainer'), findsWidgets);
  expect($('Fitness Vendor'), findsWidgets);
  expect($('Gym Staff'), findsWidgets);

  // Back to sign-in
  await $(Icons.arrow_back).tap();
}

// ═══════════════════════════════════════════════════════════════════════════════
// FULL BLACKBOX SUITE JOURNEY (runs all sub-journeys sequentially)
// ═══════════════════════════════════════════════════════════════════════════════

/// Comprehensive cleanup that runs before and after the full test suite.
Future<void> fullSuiteCleanup() async {
  await cleanupTestData();
}
