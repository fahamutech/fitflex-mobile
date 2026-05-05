import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase configuration for all platforms.
///
/// Native platforms (Android/iOS) use values extracted from:
///   - android/app/google-services.json
///   - ios/Runner/GoogleService-Info.plist
///
/// Web uses dart-define overrides or hardcoded defaults (same as portal).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return ios;
      default:
        return web;
    }
  }

  // ── Android — from android/app/google-services.json ──
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC57ErqlO4j1_CAQWF_Uuc2FwsC4BdIo3E',
    appId: '1:318978253903:android:578eecbe0556347d45f63a',
    messagingSenderId: '318978253903',
    projectId: 'fitflex-af-pilot',
    storageBucket: 'fitflex-af-pilot.firebasestorage.app',
  );

  // ── iOS — from ios/Runner/GoogleService-Info.plist ──
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyC57ErqlO4j1_CAQWF_Uuc2FwsC4BdIo3E',
    appId: '1:318978253903:ios:578eecbe0556347d45f63a',
    messagingSenderId: '318978253903',
    projectId: 'fitflex-af-pilot',
    storageBucket: 'fitflex-af-pilot.firebasestorage.app',
    iosBundleId: 'com.example.fitflexmobile',
  );

  // ── Web — dart-define overridable, shared with portal Firebase config ──
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: String.fromEnvironment(
      'FIREBASE_WEB_API_KEY',
      defaultValue: 'AIzaSyCleDGLHf71NdmbFkXbJVzS9tOsmIMj7tA',
    ),
    authDomain: String.fromEnvironment(
      'FIREBASE_WEB_AUTH_DOMAIN',
      defaultValue: 'fitflex-af-pilot.firebaseapp.com',
    ),
    projectId: String.fromEnvironment(
      'FIREBASE_PROJECT_ID',
      defaultValue: 'fitflex-af-pilot',
    ),
    storageBucket: String.fromEnvironment(
      'FIREBASE_WEB_STORAGE_BUCKET',
      defaultValue: 'fitflex-af-pilot.firebasestorage.app',
    ),
    messagingSenderId: String.fromEnvironment(
      'FIREBASE_WEB_MESSAGING_SENDER_ID',
      defaultValue: '318978253903',
    ),
    appId: String.fromEnvironment(
      'FIREBASE_WEB_APP_ID',
      defaultValue: '1:318978253903:web:49b58d5fda05603645f63a',
    ),
  );
}
