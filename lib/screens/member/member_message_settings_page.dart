// Messages from gyms and FitFlex: switch offers on or off per channel.
// Renewal, payment and announcement messages can't be switched off in the
// app or by push. WhatsApp offers need the member's agreement.

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/api_error_message.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';

class MemberMessageSettingsPage extends StatefulWidget {
  const MemberMessageSettingsPage({super.key});

  @override
  State<MemberMessageSettingsPage> createState() =>
      _MemberMessageSettingsPageState();
}

class _MemberMessageSettingsPageState extends State<MemberMessageSettingsPage> {
  Map<String, dynamic>? _prefs;
  Object? _error;
  String? _saving;
  bool _started = false;

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
      if (!mounted) return;
      setState(() {
        _prefs = (res['preferences'] as Map).cast();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _set(String key, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    final before = _prefs![key];
    setState(() {
      _prefs = {..._prefs!, key: value};
      _saving = key;
    });
    try {
      final res = await AppScope.of(
        context,
      ).api.updateCommunicationPreferences({key: value});
      if (mounted) setState(() => _prefs = (res['preferences'] as Map).cast());
    } catch (e) {
      if (!mounted) return;
      setState(() => _prefs = {..._prefs!, key: before});
      messenger.showSnackBar(
        SnackBar(content: Text(errorMessage(FFLocaleScope.of(context), e))),
      );
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  Future<void> _setWhatsappOffers(bool value) async {
    if (!value) return _set('whatsappMarketing', false);
    final agreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('msgPrefs.whatsappConsent.title')),
        content: Text(ctx.tr('msgPrefs.whatsappConsent.body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('comms.keep')),
          ),
          FilledButton(
            key: const Key('whatsapp-agree'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('msgPrefs.whatsappConsent.agree')),
          ),
        ],
      ),
    );
    if (agreed == true) await _set('whatsappMarketing', true);
  }

  @override
  Widget build(BuildContext context) {
    final p = _prefs;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('msgPrefs.title'))),
      body: p == null
          ? (_error == null
                ? const Center(child: FFSpinner())
                : FFEmptyState(
                    title: context.tr('inbox.loadFailed'),
                    body: errorMessage(FFLocaleScope.of(context), _error!),
                    action: FilledButton(
                      onPressed: _load,
                      child: Text(context.tr('comms.retry')),
                    ),
                  ))
          : ListView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                Text(
                  context.tr('msgPrefs.intro'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: FFTokens.spacingMd),
                FFCard(
                  child: Column(
                    children: [
                      _switch(
                        'prefs-inapp-offers',
                        'msgPrefs.inAppOffers',
                        'msgPrefs.inAppOffers.body',
                        p['inAppMarketing'] == true,
                        (v) => _set('inAppMarketing', v),
                      ),
                      const Divider(height: 1),
                      _switch(
                        'prefs-push-offers',
                        'msgPrefs.pushOffers',
                        'msgPrefs.pushOffers.body',
                        p['pushMarketing'] == true,
                        (v) => _set('pushMarketing', v),
                      ),
                      const Divider(height: 1),
                      _switch(
                        'prefs-whatsapp-offers',
                        'msgPrefs.whatsappOffers',
                        p['whatsappAvailable'] == true
                            ? 'msgPrefs.whatsappOffers.body'
                            : 'msgPrefs.whatsappOffers.soon',
                        p['whatsappMarketing'] == true,
                        _setWhatsappOffers,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: FFTokens.spacingMd),
                FFAlert(
                  tone: FFAlertTone.info,
                  message: context.tr('msgPrefs.alwaysOn'),
                ),
              ],
            ),
    );
  }

  Widget _switch(
    String key,
    String title,
    String body,
    bool value,
    ValueChanged<bool> onChanged,
  ) => SwitchListTile(
    key: Key(key),
    contentPadding: EdgeInsets.zero,
    title: Text(context.tr(title)),
    subtitle: Text(context.tr(body)),
    value: value,
    onChanged: _saving == null ? onChanged : null,
  );
}
