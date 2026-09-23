import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Registers this device's FCM token with the backend so FitFlex can push
/// booking, payment and renewal notifications (US139–147).
///
/// Android only for now: web push needs a VAPID key + service worker, and no
/// iOS app is registered in Firebase yet. Every call is best-effort — push
/// setup must never block or break sign-in.
class PushService {
  PushService(this.api, {FirebaseMessaging? messaging})
    : _messaging = messaging;

  final ApiClient api;
  final FirebaseMessaging? _messaging;
  StreamSubscription<String>? _refreshSub;
  String? _registeredToken;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  FirebaseMessaging get _fm => _messaging ?? FirebaseMessaging.instance;

  /// Call after a FitFlex session exists (the API needs the auth token).
  Future<void> register() async {
    if (!supported) return;
    try {
      await _fm.requestPermission();
      final token = await _fm.getToken();
      if (token != null) await _send(token);
      _refreshSub ??= _fm.onTokenRefresh.listen(_send);
    } catch (e) {
      debugPrint('[push] register failed: $e');
    }
  }

  /// Call before the session is cleared, so the backend stops pushing here.
  Future<void> unregister() async {
    if (!supported) return;
    await _refreshSub?.cancel();
    _refreshSub = null;
    final token = _registeredToken;
    _registeredToken = null;
    if (token == null) return;
    try {
      await api.unregisterDeviceToken(token);
    } catch (e) {
      debugPrint('[push] unregister failed: $e');
    }
  }

  Future<void> _send(String token) async {
    try {
      await api.registerDeviceToken(token, platform: 'android');
      _registeredToken = token;
    } catch (e) {
      debugPrint('[push] token upload failed: $e');
    }
  }
}
