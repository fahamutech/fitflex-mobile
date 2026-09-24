import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../phone_step_counter.dart';

/// Android's hardware step counter (TYPE_STEP_COUNTER). iPhone isn't
/// supported yet.
class SensorPhoneStepCounter implements PhoneStepCounter {
  const SensorPhoneStepCounter();

  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> hasPermission() async =>
      isSupported && await Permission.activityRecognition.isGranted;

  @override
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    return (await Permission.activityRecognition.request()).isGranted;
  }

  @override
  Future<bool> isPermanentlyDenied() async =>
      isSupported && await Permission.activityRecognition.isPermanentlyDenied;

  @override
  Future<void> openSettings() => openAppSettings();

  @override
  Future<int?> readSinceBoot() async {
    if (!await hasPermission()) return null;
    try {
      // The sensor reports its current value as soon as it's listened to.
      final reading = await Pedometer.stepCountStream.first.timeout(
        const Duration(seconds: 10),
      );
      return reading.steps;
    } catch (e) {
      debugPrint('[PhoneStepCounter] no reading: $e');
      return null;
    }
  }
}
