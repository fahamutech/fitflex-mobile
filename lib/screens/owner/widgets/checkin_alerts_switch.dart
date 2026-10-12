import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../shared/i18n.dart';

/// "Check-in notifications" on the gym owner's (and staff's) profile: a
/// notification each time a member checks in. On unless switched off, and
/// each person chooses for themselves.
///
/// Hidden until the choice has loaded, and if it can't be loaded — a
/// switch that might show the wrong state is worse than none.
class CheckinAlertsSwitch extends StatefulWidget {
  const CheckinAlertsSwitch({super.key});

  @override
  State<CheckinAlertsSwitch> createState() => _CheckinAlertsSwitchState();
}

class _CheckinAlertsSwitchState extends State<CheckinAlertsSwitch> {
  bool? _on;
  bool _started = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await AppScope.of(context).api.communicationPreferences();
      final prefs = res['preferences'];
      if (!mounted || prefs is! Map) return;
      // Servers from before the switch existed send nothing: it is on.
      setState(() => _on = prefs['gymCheckinAlerts'] != false);
    } catch (_) {
      // Stays hidden.
    }
  }

  Future<void> _set(bool value) async {
    final before = _on;
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr('checkinAlerts.failed');
    setState(() {
      _on = value;
      _saving = true;
    });
    try {
      await AppScope.of(
        context,
      ).api.updateCommunicationPreferences({'gymCheckinAlerts': value});
    } catch (_) {
      if (!mounted) return;
      // Put it back: what the screen shows must be what is saved.
      setState(() => _on = before);
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = _on;
    if (on == null) return const SizedBox.shrink();
    return SwitchListTile(
      key: const Key('checkin-alerts-switch'),
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.notifications_active_outlined),
      title: Text(context.tr('checkinAlerts.title')),
      subtitle: Text(context.tr(on ? 'checkinAlerts.on' : 'checkinAlerts.off')),
      value: on,
      onChanged: _saving ? null : _set,
    );
  }
}
