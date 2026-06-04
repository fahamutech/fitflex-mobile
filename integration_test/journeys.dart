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
  // Generous timeouts: dev-login seeds fixtures + loads data over the network.
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

/// GYM MEMBER: home pass, QR + marketplace (B5), gym photos (B2) + amenities (B3).
Future<void> memberJourney(PatrolIntegrationTester $) async {
  await bootToRole($);
  await $(const Key('devLoginMember')).tap();

  await $('Dev Member').waitUntilVisible();
  expect($('Premium'), findsWidgets);
  expect($('Show my QR'), findsOneWidget);

  await $('Show my QR').tap();
  await $('Show this code at the gym').waitUntilVisible();
  await $('Marketplace / Shop').scrollTo();
  expect($('Coming soon'), findsOneWidget);

  await $('Gyms').tap(); // bottom-nav label (exact match, not "Gyms near you")
  await $('Discover gyms').waitUntilVisible();
  await $('Iron Paradise (Dev)').scrollTo();
  await $('Iron Paradise (Dev)').tap();
  await $('Amenities').waitUntilVisible();
  expect($('Wellness & Recovery'), findsOneWidget);
  expect($('Member Facilities & Comfort'), findsOneWidget);
}

/// GYM OWNER: dashboard period/switch (A3/A8) + add trainer (A4).
Future<void> ownerJourney(PatrolIntegrationTester $) async {
  await bootToRole($);
  await $(const Key('devLoginOwner')).tap();

  await $('Gym Owner Dashboard').waitUntilVisible();
  expect($('Period settings'), findsOneWidget);
  expect($('Direct members'), findsOneWidget);
  expect($('FitFlex roaming members'), findsOneWidget);

  await $('Trainers').tap(); // owner bottom-nav
  await $('Add trainer').waitUntilVisible();
  await $('Add trainer').tap();

  // Add-trainer form — target fields by Key (robust, no coordinate taps).
  await $(const Key('trainerFormSave')).waitUntilVisible();
  final email = 'coach.${DateTime.now().millisecondsSinceEpoch}@example.com';
  await $(const Key('trainerFormName')).enterText('Coach Patrol');
  await $(const Key('trainerFormEmail')).enterText(email);
  await $(const Key('trainerFormRate')).enterText('20000'); // required
  await $(const Key('trainerFormSave')).tap();

  await $('Coach Patrol').waitUntilVisible(); // saved with no error 400
}

/// TRAINER: dashboard profile + linked gym.
Future<void> trainerJourney(PatrolIntegrationTester $) async {
  await bootToRole($);
  await $(const Key('devLoginTrainer')).tap();

  await $('Trainer Dashboard').waitUntilVisible();
  expect($('Dev Trainer'), findsOneWidget);
  expect($('Iron Paradise (Dev)'), findsWidgets);
}
