import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../api_client.dart';
import 'phone_step_counter.dart';
import 'step_ledger.dart';

/// Counting steps with the member's own phone.
///
/// Off until the member turns it on (which asks for the "Physical activity"
/// permission). While on, FitFlex reads the phone's step counter when the
/// app opens, every minute while it's open, and about every 15 minutes in
/// the background, and sends each day's total to the server as a device
/// record (`source: device`, `devicePlatform: phone_sensor`,
/// `externalId: steps:yyyy-mm-dd`). Challenges, goals and trainer views then
/// see those steps like any other activity.
///
/// Counting starts when it's turned on: steps from before aren't included.
/// Turning it off stops reading and uploading; days already sent stay.
class PhoneSteps extends ChangeNotifier {
  PhoneSteps({
    required this.counter,
    StepStore? store,
    StepBackground? background,
    DateTime Function()? now,
  }) : store = store ?? PrefsStepStore(),
       background = background ?? const WorkmanagerStepBackground(),
       _now = now ?? DateTime.now;

  final PhoneStepCounter counter;
  final StepStore store;
  final StepBackground background;
  final DateTime Function() _now;

  static const enabledKey = 'phone_steps_enabled';
  static const _ledgerKey = 'phone_steps_ledger_v1';
  static const _dismissedKey = 'phone_steps_prompt_dismissed';
  static const platform = 'phone_sensor';

  bool _enabled = false;
  bool _loaded = false;
  bool _needsSettings = false;
  int _today = 0;
  bool _syncing = false;
  bool _promptDismissed = false;

  /// The member chose "Not now" on Home (the switch in Privacy stays).
  bool get promptDismissed => _promptDismissed;

  bool get supported => counter.isSupported;

  bool get enabled => _enabled;
  bool get loaded => _loaded;

  /// Permission was refused for good: only the phone's Settings can allow it.
  bool get needsSettings => _needsSettings;

  /// Steps this phone counted today (for the "counting" status line).
  int get countedToday => _today;

  Future<void> load() async {
    if (!supported) {
      _loaded = true;
      notifyListeners();
      return;
    }
    _enabled = await store.read(enabledKey) == 'true';
    _promptDismissed = await store.read(_dismissedKey) == 'true';
    if (_enabled && !await counter.hasPermission()) {
      // Permission was withdrawn in Settings.
      _enabled = false;
      await store.write(enabledKey, 'false');
      await background.cancel();
    }
    _today = (await _ledger()).stepsOn(_now());
    _loaded = true;
    notifyListeners();
  }

  /// Turns counting on. Returns whether it's now on. [known] is what the
  /// server already has from this phone per day (`yyyy-mm-dd` → steps), so
  /// turning it back on the same day carries on from there.
  Future<bool> enable({Map<String, int> known = const {}}) async {
    if (!supported) return false;
    final granted =
        await counter.hasPermission() || await counter.requestPermission();
    if (!granted) {
      _needsSettings = await counter.isPermanentlyDenied();
      notifyListeners();
      return false;
    }
    _needsSettings = false;
    _enabled = true;
    await store.write(enabledKey, 'true');
    // The first reading is the starting point.
    final ledger = await _ledger()
      ..seed(known);
    final reading = await counter.readSinceBoot();
    if (reading != null) ledger.record(reading, _now());
    await _save(ledger);
    await background.schedule();
    notifyListeners();
    return true;
  }

  Future<void> disable() async {
    _enabled = false;
    await store.write(enabledKey, 'false');
    final ledger = await _ledger()
      ..resetBaseline();
    await _save(ledger);
    await background.cancel();
    notifyListeners();
  }

  /// On sign-out: stop counting and forget this phone's days, so the next
  /// person to sign in on it doesn't inherit them.
  Future<void> forget() async {
    _enabled = false;
    _today = 0;
    await store.write(enabledKey, 'false');
    await store.write(_ledgerKey, jsonEncode(StepLedger().toJson()));
    await background.cancel();
    notifyListeners();
  }

  Future<void> dismissPrompt() async {
    _promptDismissed = true;
    await store.write(_dismissedKey, 'true');
    notifyListeners();
  }

  Future<void> openSettings() => counter.openSettings();

  /// Reads the counter and sends any new daily totals. Returns true when the
  /// server got new steps (so the caller can refresh activity).
  Future<bool> sync(ApiClient api) async {
    if (!supported || !_enabled || _syncing) return false;
    _syncing = true;
    try {
      final changed = await syncOnce(
        counter: counter,
        store: store,
        api: api,
        now: _now(),
      );
      _today = (await _ledger()).stepsOn(_now());
      notifyListeners();
      return changed;
    } finally {
      _syncing = false;
    }
  }

  Future<StepLedger> _ledger() => loadLedger(store);
  Future<void> _save(StepLedger l) =>
      store.write(_ledgerKey, jsonEncode(l.toJson()));

  static Future<StepLedger> loadLedger(StepStore store) async {
    final raw = await store.read(_ledgerKey);
    if (raw == null) return StepLedger();
    try {
      return StepLedger.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return StepLedger();
    }
  }

  /// One read-and-upload pass, shared by the app and the background task.
  static Future<bool> syncOnce({
    required PhoneStepCounter counter,
    required StepStore store,
    required ApiClient api,
    required DateTime now,
  }) async {
    if (await store.read(enabledKey) != 'true') return false;
    final ledger = await loadLedger(store);
    final reading = await counter.readSinceBoot();
    if (reading != null) ledger.record(reading, now);
    await store.write(_ledgerKey, jsonEncode(ledger.toJson()));

    final pending = ledger.pending();
    if (pending.isEmpty) return false;
    try {
      await api.syncDeviceActivities([
        for (final d in pending)
          {
            'devicePlatform': platform,
            'externalId': 'steps:${d.key}',
            'type': 'walking',
            // A day's total, dated at the start of that local day.
            'startedAt': d.day.toUtc().toIso8601String(),
            'steps': d.steps,
            'deviceName': 'This phone',
          },
      ]);
    } catch (e) {
      // Offline or signed out: the next pass sends it.
      debugPrint('[PhoneSteps] upload failed: $e');
      return false;
    }
    // Re-read so a reading taken meanwhile (the other isolate) isn't lost.
    final latest = await loadLedger(store)
      ..markUploaded({for (final d in pending) d.key: d.steps});
    await store.write(_ledgerKey, jsonEncode(latest.toJson()));
    return true;
  }
}

/// Key–value storage for the ledger. The default reads and writes straight
/// through (no cache), because the background task runs in another isolate.
abstract interface class StepStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class PrefsStepStore implements StepStore {
  SharedPreferencesAsync? _instance;
  SharedPreferencesAsync get _prefs => _instance ??= SharedPreferencesAsync();

  @override
  Future<String?> read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);
}

/// The periodic background reading.
abstract interface class StepBackground {
  Future<void> schedule();
  Future<void> cancel();
}

const _taskName = 'fitflex.phoneSteps';

class WorkmanagerStepBackground implements StepBackground {
  const WorkmanagerStepBackground();

  @override
  Future<void> schedule() async {
    try {
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (e) {
      debugPrint('[PhoneSteps] could not schedule background reading: $e');
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await Workmanager().cancelByUniqueName(_taskName);
    } catch (e) {
      debugPrint('[PhoneSteps] could not cancel background reading: $e');
    }
  }
}
