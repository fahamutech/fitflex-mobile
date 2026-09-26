// New message / edit draft: purpose → audience → message → channels →
// schedule → preview → confirm. UI only — state and the send live in
// [CampaignComposerController].

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import 'communication_controller.dart';
import 'data/communication_models.dart';
import 'data/communication_repository.dart';
import 'widgets/audience_selector.dart';
import 'widgets/campaign_preview.dart';
import 'widgets/channel_selector.dart';
import 'widgets/comms_format.dart';
import 'widgets/message_composer.dart';
import 'widgets/template_selector.dart';

class CampaignComposerPage extends StatefulWidget {
  const CampaignComposerPage({
    super.key,
    this.gymId,
    this.campaignId,
    this.templateId,
    this.repository,
  });

  final String? gymId;

  /// Set when editing an existing draft.
  final String? campaignId;

  /// Start a new message from this template.
  final String? templateId;

  final CommunicationRepository? repository;

  @override
  State<CampaignComposerPage> createState() => _CampaignComposerPageState();
}

class _CampaignComposerPageState extends State<CampaignComposerPage> {
  CampaignComposerController? _controller;
  CommunicationRepository? _repo;
  Object? _loadError;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _start();
  }

  Future<void> _start() async {
    final repo =
        widget.repository ?? CommunicationRepository(AppScope.of(context).api);
    // New messages and templates start in the owner's app language.
    final lang = FFLocaleScope.of(context).locale.languageCode;
    _repo = repo;
    try {
      final template = widget.templateId == null
          ? null
          : await repo.template(widget.templateId!);
      final existing = widget.campaignId == null
          ? null
          : (await repo.campaign(widget.campaignId!)).campaign;
      final overview = await repo.overview(
        gymId: widget.gymId ?? existing?.gymId,
      );
      if (!mounted) return;
      setState(() {
        _controller = CampaignComposerController(
          repo,
          gymId: widget.gymId ?? existing?.gymId,
          channelsAvailable: overview.channels,
          existing: existing,
          template: template,
          writingLocale: lang,
        );
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickTemplate(CampaignComposerController c) async {
    final t = await pickTemplate(
      context,
      repository: _repo!,
      gymId: c.gymId,
      purpose: c.purpose,
    );
    if (t != null) c.applyTemplate(t);
  }

  Future<void> _submit() async {
    final c = _controller!;
    final messenger = ScaffoldMessenger.of(context);
    final result = await c.submit();
    if (!mounted || result == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.status == CampaignStatus.scheduled
              ? context
                    .tr('comms.done.scheduled')
                    .replaceFirst(
                      '{when}',
                      formatWhen(context, result.scheduledAt!),
                    )
              : context.tr('comms.done.sending'),
        ),
      ),
    );
    context.pushReplacement('/owner/communications/campaigns/${result.id}');
  }

  Future<void> _saveDraft() async {
    final c = _controller!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await c.saveDraft();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(context.tr('comms.done.draft'))),
      );
      context.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(apiErrorMessage(FFLocaleScope.of(context), e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('comms.new'))),
        body: _loadError == null
            ? const Center(child: FFSpinner())
            : FFEmptyState(
                title: context.tr('comms.loadFailed'),
                body: errorMessage(FFLocaleScope.of(context), _loadError!),
              ),
      );
    }
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final steps = ComposerStep.values;
        return Scaffold(
          appBar: AppBar(
            title: Text(context.tr('comms.step.${c.step.name}')),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(4),
              child: LinearProgressIndicator(
                value: (c.step.index + 1) / steps.length,
              ),
            ),
          ),
          body: ListView(
            key: Key('step-${c.step.name}'),
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            children: [
              Text(
                context
                    .tr('comms.stepOf')
                    .replaceFirst('{n}', '${c.step.index + 1}')
                    .replaceFirst('{total}', '${steps.length}'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              _stepBody(context, c),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(FFTokens.spacingMd),
              child: Row(
                children: [
                  if (c.step.index > 0)
                    OutlinedButton(
                      key: const Key('comms-back'),
                      onPressed: c.submitting ? null : c.back,
                      child: Text(context.tr('comms.back')),
                    ),
                  const Spacer(),
                  if (c.step == ComposerStep.confirm) ...[
                    TextButton(
                      key: const Key('comms-save-draft'),
                      onPressed: c.submitting ? null : _saveDraft,
                      child: Text(context.tr('comms.saveDraft')),
                    ),
                    const SizedBox(width: FFTokens.spacingXs),
                    FilledButton(
                      key: const Key('comms-submit'),
                      onPressed: c.canContinue(ComposerStep.confirm)
                          ? _submit
                          : null,
                      child: c.submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              context.tr(
                                c.scheduleLater
                                    ? 'comms.scheduleCampaign'
                                    : 'comms.sendCampaign',
                              ),
                            ),
                    ),
                  ] else
                    FilledButton(
                      key: const Key('comms-next'),
                      onPressed: c.canContinue(c.step) ? c.next : null,
                      child: Text(context.tr('comms.next')),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _stepBody(BuildContext context, CampaignComposerController c) =>
      switch (c.step) {
        ComposerStep.purpose => _PurposeStep(controller: c),
        ComposerStep.audience => AudienceSelector(controller: c),
        ComposerStep.message => MessageComposer(
          key: ValueKey(c.contentRevision),
          controller: c,
          onPickTemplate: () => _pickTemplate(c),
        ),
        ComposerStep.channels => ChannelSelector(controller: c),
        ComposerStep.schedule => _ScheduleStep(controller: c),
        ComposerStep.preview => _PreviewStep(controller: c),
        ComposerStep.confirm => _ConfirmStep(controller: c),
      };
}

class _PurposeStep extends StatelessWidget {
  const _PurposeStep({required this.controller});
  final CampaignComposerController controller;

  static const _icons = {
    CampaignPurpose.promotion: Icons.local_offer_outlined,
    CampaignPurpose.renewal: Icons.autorenew,
    CampaignPurpose.payment: Icons.payments_outlined,
    CampaignPurpose.announcement: Icons.campaign_outlined,
    CampaignPurpose.engagement: Icons.favorite_outline,
    CampaignPurpose.general: Icons.chat_bubble_outline,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final p in CampaignPurpose.values)
          FFActionTile(
            key: Key('purpose-${p.name}'),
            icon: _icons[p]!,
            title: context.tr('comms.purpose.${p.name}'),
            subtitle: context.tr('comms.purpose.${p.name}.body'),
            trailing: Icon(
              controller.purpose == p
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: controller.purpose == p
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            onTap: () => controller.setPurpose(p),
          ),
      ],
    );
  }
}

class _ScheduleStep extends StatelessWidget {
  const _ScheduleStep({required this.controller});
  final CampaignComposerController controller;

  Future<void> _pick(BuildContext context) async {
    final c = controller;
    final now = DateTime.now();
    final initial = c.scheduledAt ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 90)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    c.setScheduledAt(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final tooSoon = c.scheduleLater && !c.canContinue(ComposerStep.schedule);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RadioGroup<bool>(
          groupValue: c.scheduleLater,
          onChanged: (v) => c.setScheduleLater(v ?? false),
          child: Column(
            children: [
              RadioListTile<bool>(
                key: const Key('send-now'),
                value: false,
                title: Text(context.tr('comms.schedule.now')),
              ),
              RadioListTile<bool>(
                key: const Key('send-later'),
                value: true,
                title: Text(context.tr('comms.schedule.later')),
              ),
            ],
          ),
        ),
        if (c.scheduleLater) ...[
          const SizedBox(height: FFTokens.spacingSm),
          OutlinedButton.icon(
            key: const Key('pick-time'),
            onPressed: () => _pick(context),
            icon: const Icon(Icons.event_outlined),
            label: Text(
              c.scheduledAt == null
                  ? context.tr('comms.schedule.pick')
                  : formatWhen(context, c.scheduledAt!),
            ),
          ),
          if (tooSoon)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingSm),
              child: FFAlert(
                tone: FFAlertTone.warning,
                message: context.tr('comms.schedule.tooSoon'),
              ),
            ),
        ],
      ],
    );
  }
}

class _Warnings extends StatelessWidget {
  const _Warnings(this.warnings);
  final List<CampaignWarning> warnings;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final w in warnings)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFAlert(
            key: Key('warning-${w.code}'),
            tone: w.code == 'nobody_reachable'
                ? FFAlertTone.error
                : FFAlertTone.warning,
            message: context
                .tr('comms.warn.${w.code}')
                .replaceFirst('{n}', '${w.count ?? ''}')
                .replaceFirst(
                  '{channel}',
                  w.channel == null ? '' : channelLabel(context, w.channel!),
                ),
          ),
        ),
    ],
  );
}

class _PreviewStep extends StatelessWidget {
  const _PreviewStep({required this.controller});
  final CampaignComposerController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.previewLoading || (c.preview == null && c.previewError == null)) {
      return const Padding(
        padding: EdgeInsets.all(FFTokens.spacingXl),
        child: Center(child: FFSpinner()),
      );
    }
    if (c.previewError != null) {
      return FFEmptyState(
        title: context.tr('comms.loadFailed'),
        body: errorMessage(FFLocaleScope.of(context), c.previewError!),
        action: FilledButton(
          onPressed: c.loadPreview,
          child: Text(context.tr('comms.retry')),
        ),
      );
    }
    final p = c.preview!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Warnings(p.warnings),
        if (p.example != null)
          CampaignPreviewView(message: p.example!, channels: c.channels)
        else
          Text(context.tr('comms.preview.none')),
      ],
    );
  }
}

class _ConfirmStep extends StatelessWidget {
  const _ConfirmStep({required this.controller});
  final CampaignComposerController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final counts = c.preview?.counts;
    final targeted = counts?.targeted ?? c.audienceCount?.count ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Row(
                icon: Icons.groups_outlined,
                label: context.tr('comms.confirm.audience'),
                value:
                    '${context.tr('comms.preset.${c.preset ?? 'all'}')} · '
                    '${context.tr(targeted == 1 ? 'comms.audience.matchOne' : 'comms.audience.match').replaceFirst('{n}', '$targeted')}',
              ),
              for (final ch in c.channels)
                _Row(
                  icon: channelIcon(ch),
                  label: channelLabel(context, ch),
                  value: context
                      .tr('comms.channel.reaches')
                      .replaceFirst(
                        '{n}',
                        '${counts?.byChannel[ch]?.queued ?? '–'}',
                      )
                      .replaceFirst('{total}', '$targeted'),
                ),
              _Row(
                icon: Icons.title,
                label: context.tr('comms.msg.title'),
                value: c.content.title,
              ),
              _Row(
                icon: Icons.schedule_outlined,
                label: context.tr('comms.confirm.when'),
                value: c.scheduleLater && c.scheduledAt != null
                    ? formatWhen(context, c.scheduledAt!)
                    : context.tr('comms.schedule.now'),
              ),
              _Row(
                icon: Icons.label_outline,
                label: context.tr('comms.confirm.type'),
                value: context.tr(
                  c.purpose?.isTransactional ?? false
                      ? 'comms.category.transactional'
                      : 'comms.category.marketing',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        if (c.preview != null)
          _Warnings(
            c.preview!.warnings.where((w) => w.code != 'large_send').toList(),
          ),
        if (c.needsLargeSendConfirm)
          CheckboxListTile(
            key: const Key('confirm-large'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: c.confirmLargeSend,
            onChanged: (v) => c.setConfirmLargeSend(v ?? false),
            title: Text(
              context
                  .tr('comms.confirm.large')
                  .replaceFirst('{n}', '$targeted'),
            ),
          ),
        if (c.submitError != null)
          FFAlert(
            tone: FFAlertTone.error,
            message: errorMessage(FFLocaleScope.of(context), c.submitError!),
          ),
        const SizedBox(height: FFTokens.spacingSm),
        Text(
          context.tr('comms.confirm.note'),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: FFTokens.iconMd, color: theme.colorScheme.primary),
          const SizedBox(width: FFTokens.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
