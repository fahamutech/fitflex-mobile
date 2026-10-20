import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device_data_stub.dart'
    if (dart.library.js_interop) 'device_data_web.dart'
    as platform;

/// What the phone says about saving data and storage, so app photos are not
/// downloaded when the person asked to save data or the phone is nearly
/// full.
abstract class DeviceDataProbe {
  /// True when downloads should be skipped: Android Data Saver, iOS Low
  /// Data Mode, or the browser's Save-Data / prefers-reduced-data. On a
  /// phone, an error or a missing answer also counts as true (no download).
  Future<bool> reducedData();

  /// Free bytes where app files are kept, or null when unknown.
  Future<int?> freeBytes();
}

/// The platform's probe: a method channel on Android and iOS (MainActivity /
/// AppDelegate), the Network Information API on the web.
class PlatformDeviceDataProbe implements DeviceDataProbe {
  const PlatformDeviceDataProbe();

  static const _channel = MethodChannel('fitflex/device_data');

  bool get _phone =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<bool> reducedData() async {
    if (kIsWeb) return platform.browserSavesData();
    if (!_phone) return false;
    try {
      return await _channel.invokeMethod<bool>('reducedData') ?? true;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<int?> freeBytes() async {
    if (!_phone) return null;
    try {
      return await _channel.invokeMethod<int>('freeBytes');
    } catch (_) {
      return null;
    }
  }
}
