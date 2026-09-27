// Automations (M9): the gym's messages that send themselves — welcome,
// reminders before a membership ends, when it has ended, a failed payment,
// and 14 days without a visit. The Automations tab lists them with an on/off
// switch; one automation's page sets its channels and template, previews
// the message and shows who it went to recently.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import 'data/automation_models.dart';
import 'data/communication_models.dart';
import 'data/communication_repository.dart';
import 'widgets/campaign_preview.dart';
import 'widgets/comms_format.dart';
import 'widgets/history_widgets.dart';
import 'widgets/template_selector.dart';

String _n(String s, int n) => s.replaceFirst('{n}', '$n');

/// "Membership ends in 7 days", in the app's language.
String automationTitle(BuildContext context, Automation a) {
  if (a.trigger == 'membership_expiring' && a.offsetDays == 1) {
    return context.tr('comms.auto.title.membership_expiring_1');
  }
  return _n(context.tr('comms.auto.title.${a.trigger}'), a.offsetDays);
}

/// When it sends, in a sentence.
String automationWhen(BuildContext context, Automation a) =>
    _n(context.tr('comms.auto.when.${a.trigger}'), a.offsetDays);

String _templateLabel(BuildContext context, Automation a) {
  if (a.templateSystem && a.templateKey != null) {
    return context.tr('comms.tpl.${a.templateKey}');
  }
  return a.templateName ?? '—';
}

String? _pausedText(BuildContext context, Automation a) {
  if (!a.paused) return null;
  final n = a.pausedFor;
  if (n != null) return _n(context.tr('comms.auto.pausedTooMany'), n);
  return context.tr('comms.auto.pausedTemplate');
}

/// The Automations tab of the Communication Center.
class AutomationsTab extends StatefulWidget {
  const AutomationsTab({super.key, this.gymId, this.repository});

  final String? gymId;
  final CommunicationRepository? repository;

  @override
  State<AutomationsTab> createState() => _AutomationsTabState();
}

class _AutomationsTabState extends State<AutomationsTab> {
  late CommunicationRepository _repo;
  List<Automation>? _list;
  Object? _error;
  final _busy = <String>{};
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _repo =
        widget.repository ?? CommunicationRepository(AppScope.of(context).api);
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.automations(gymId: widget.gymId);
      if (mounted) setState(() => (_list = list, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _toggle(Automation a, bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy.add(a.id));
    try {
      final updated = await _repo.updateAutomation(a.id, enabled: on);
      if (!mounted) return;
      setState(
        () => _list = [for (final x in _list!) x.id == a.id ? updated : x],
      );
    } on ApiException catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(apiErrorMessage(FFLocaleScope.of(context), e)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(a.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    if (list == null) {
      return _error == null
          ? const Padding(
              padding: EdgeInsets.all(FFTokens.spacingXl),
              child: Center(child: FFSpinner()),
            )
          : FFEmptyState(
              title: context.tr('comms.loadFailed'),
              body: errorMessage(FFLocaleScope.of(context), _error!),
              action: FilledButton(
                onPressed: _load,
                child: Text(context.tr('comms.retry')),
              ),
            );
    }
    final theme = Theme.of(context);
    return Column(
      key: const Key('automations'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('comms.auto.intro'), style: theme.textTheme.bodySmall),
        const SizedBox(height: FFTokens.spacingSm),
        for (final a in list)
          _AutomationTile(
            automation: a,
            busy: _busy.contains(a.id),
            onToggle: (on) => _toggle(a, on),
            onOpen: () async {
              final q = widget.gymId == null ? '' : '?gymId=${widget.gymId}';
              await context.push('/owner/communications/automations/${a.id}$q');
              if (mounted) await _load();
            },
          ),
      ],
    );
  }
}

class _AutomationTile extends StatelessWidget {
  const _AutomationTile({
    required this.automation,
    required this.busy,
    required this.onToggle,
    required this.onOpen,
  });

  final Automation automation;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = automation;
    final paused = _pausedText(context, a);
    final key = '${a.trigger}-${a.offsetDays}';
    return FFCard(
      margin: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: InkWell(
        key: Key('automation-$key'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    automationTitle(context, a),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Switch(
                  key: Key('automation-switch-$key'),
                  value: a.enabled,
                  onChanged: busy ? null : onToggle,
                ),
              ],
            ),
            Text(
              '${_templateLabel(context, a)} · ${a.channels.map((c) => channelLabel(context, c)).join(', ')}',
              style: theme.textTheme.bodySmall,
            ),
            if (a.stats.fired > 0 || a.stats.failed > 0)
              Text(
                [
                  _n(context.tr('comms.auto.sentTo'), a.stats.fired),
                  if (a.stats.failed > 0)
                    _n(context.tr('comms.history.failedN'), a.stats.failed),
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            if (paused != null)
              Padding(
                padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                child: FFAlert(
                  key: Key('automation-paused-$key'),
                  tone: FFAlertTone.warning,
                  message: paused,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One automation: when it sends, on/off, channels, template, preview and
/// recent firings.
class AutomationDetailPage extends StatefulWidget {
  const AutomationDetailPage({
    super.key,
    required this.automationId,
    this.gymId,
    this.repository,
  });

  final String automationId;
  final String? gymId;
  final CommunicationRepository? repository;

  @override
  State<AutomationDetailPage> createState() => _AutomationDetailPageState();
}

class _AutomationDetailPageState extends State<AutomationDetailPage> {
  late CommunicationRepository _repo;
  Automation? _a;
  TemplatePreview? _preview;
  List<AutomationFiring>? _runs;
  Object? _error;
  bool _busy = false;
  String? _lang;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _repo =
        widget.repository ?? CommunicationRepository(AppScope.of(context).api);
    _lang = FFLocaleScope.of(context).locale.languageCode;
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.automations(gymId: widget.gymId);
      final a = list.firstWhere((x) => x.id == widget.automationId);
      if (!mounted) return;
      setState(() => (_a = a, _error = null));
      final results = await Future.wait([
        _repo
            .automationPreview(a.id)
            .then<Object?>((p) => p, onError: (_) => null),
        _repo
            .automationRuns(a.id)
            .then<Object?>((r) => r, onError: (_) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _preview = results[0] as TemplatePreview?;
        _runs = (results[1] as List<AutomationFiring>?) ?? const [];
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _update({
    bool? enabled,
    List<CommChannel>? channels,
    String? templateId,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final a = await _repo.updateAutomation(
        widget.automationId,
        enabled: enabled,
        channels: channels,
        templateId: templateId,
      );
      if (!mounted) return;
      setState(() => _a = a);
      if (templateId != null) {
        final p = await _repo.automationPreview(a.id);
        if (mounted) setState(() => _preview = p);
      }
    } on ApiException catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              e.code == 'template_needs_values'
                  ? context.tr('comms.auto.templateNeedsValues')
                  : apiErrorMessage(FFLocaleScope.of(context), e),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeTemplate() async {
    final t = await pickTemplate(
      context,
      repository: _repo,
      gymId: widget.gymId ?? _a?.gymId,
    );
    if (t != null) await _update(templateId: t.id);
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          a == null
              ? context.tr('comms.auto.title')
              : automationTitle(context, a),
        ),
      ),
      body: a == null
          ? Center(
              child: _error == null
                  ? const FFSpinner()
                  : FFEmptyState(
                      title: context.tr('comms.loadFailed'),
                      body: errorMessage(FFLocaleScope.of(context), _error!),
                    ),
            )
          : _body(context, a),
    );
  }

  Widget _body(BuildContext context, Automation a) {
    final theme = Theme.of(context);
    final paused = _pausedText(context, a);
    final preview = _preview;
    final shown =
        preview?.byLocale[_lang] ?? preview?.byLocale.values.firstOrNull;
    return ListView(
      key: const Key('automation-detail'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Text(automationWhen(context, a), style: theme.textTheme.bodyMedium),
        const SizedBox(height: FFTokens.spacingSm),
        SwitchListTile(
          key: const Key('automation-enabled'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            context.tr(a.enabled ? 'comms.auto.on' : 'comms.auto.off'),
          ),
          value: a.enabled,
          onChanged: _busy ? null : (on) => _update(enabled: on),
        ),
        if (paused != null) FFAlert(tone: FFAlertTone.warning, message: paused),
        if (a.trigger == 'membership_expiring')
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingXs),
            child: Text(
              context.tr('comms.auto.replacesPlatform'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        FFSectionTitle(context.tr('comms.auto.channels')),
        for (final ch in CommChannel.values)
          CheckboxListTile(
            key: Key('automation-channel-${ch.wire}'),
            contentPadding: EdgeInsets.zero,
            secondary: Icon(channelIcon(ch)),
            title: Text(channelLabel(context, ch)),
            value: a.channels.contains(ch),
            onChanged: _busy
                ? null
                : (on) {
                    final next = {...a.channels};
                    on == true ? next.add(ch) : next.remove(ch);
                    if (next.isEmpty) return; // at least one
                    _update(
                      channels: CommChannel.values
                          .where(next.contains)
                          .toList(),
                    );
                  },
          ),
        Text(
          context.tr('comms.auto.channelsNote'),
          style: theme.textTheme.bodySmall,
        ),
        FFSectionTitle(context.tr('comms.auto.message')),
        Row(
          children: [
            Expanded(
              child: Text(
                _templateLabel(context, a),
                key: const Key('automation-template'),
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton(
              key: const Key('automation-change-template'),
              onPressed: _busy ? null : _changeTemplate,
              child: Text(context.tr('comms.tpl.change')),
            ),
          ],
        ),
        if (preview != null && preview.byLocale.length > 1)
          FFSegmented(
            key: const Key('automation-lang'),
            value: _lang ?? preview.byLocale.keys.first,
            options: [
              for (final l in preview.byLocale.keys)
                (l, context.tr('comms.lang.$l')),
            ],
            onChanged: (l) => setState(() => _lang = l),
          ),
        const SizedBox(height: FFTokens.spacingSm),
        if (shown != null)
          CampaignPreviewView(
            message: shown.inApp,
            channels: a.channels.toSet(),
            gymName: preview!.senderName,
          )
        else
          const Center(child: FFSpinner()),
        FFSectionTitle(context.tr('comms.auto.recent')),
        if (_runs == null)
          const Center(child: FFSpinner())
        else if (_runs!.isEmpty)
          Text(
            context.tr('comms.auto.noneYet'),
            style: theme.textTheme.bodySmall,
          )
        else
          for (final r in _runs!)
            FFCard(
              key: Key('firing-${r.id}'),
              margin: const EdgeInsets.only(bottom: FFTokens.spacingXs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      r.memberName ?? context.tr('comms.history.unknownMember'),
                      if (r.createdAt != null)
                        formatWhen(context, r.createdAt!),
                    ].join(' · '),
                    style: theme.textTheme.titleSmall,
                  ),
                  for (final c in r.channels)
                    Text(
                      [
                        if (c.channel != null)
                          channelLabel(context, c.channel!),
                        context.tr('comms.msgStatus.${c.status}'),
                        if (c.reason != null)
                          c.status == 'failed'
                              ? failureReasonLabel(context, c.reason!)
                              : skipReasonLabel(context, c.reason!),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
      ],
    );
  }
}
