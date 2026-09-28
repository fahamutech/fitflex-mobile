// One campaign: status, the message, who it was for, and delivery per
// channel. Drafts can be edited or deleted; scheduled campaigns can be
// taken back to draft or cancelled.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import 'data/communication_models.dart';
import 'data/communication_repository.dart';
import 'widgets/campaign_preview.dart';
import 'widgets/campaign_status.dart';
import 'widgets/comms_format.dart';
import 'widgets/delivery_stats.dart';
import 'widgets/history_widgets.dart';
import 'widgets/results_card.dart';

class CampaignDetailPage extends StatefulWidget {
  const CampaignDetailPage({
    super.key,
    required this.campaignId,
    this.repository,
  });

  final String campaignId;
  final CommunicationRepository? repository;

  @override
  State<CampaignDetailPage> createState() => _CampaignDetailPageState();
}

class _CampaignDetailPageState extends State<CampaignDetailPage> {
  late CommunicationRepository _repo;
  CampaignDetail? _detail;
  Object? _error;
  bool _busy = false;
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
      final d = await _repo.campaign(widget.campaignId);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _act(Future<void> Function() action, String doneKey) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(context.tr(doneKey))));
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(apiErrorMessage(FFLocaleScope.of(context), e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String titleKey, String bodyKey) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr(titleKey)),
          content: Text(ctx.tr(bodyKey)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tr('comms.keep')),
            ),
            FilledButton(
              key: const Key('dialog-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.tr('comms.yes')),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _edit(Campaign c) async {
    await context.push('/owner/communications/campaigns/${c.id}/edit');
    if (mounted) await _load();
  }

  Future<void> _delete(Campaign c) async {
    final ok = await _confirm('comms.delete.title', 'comms.delete.body');
    if (!ok || !mounted) return;
    await _act(() => _repo.delete(c.id), 'comms.done.deleted');
    if (mounted) context.pop(true);
  }

  Future<void> _cancel(Campaign c) async {
    final ok = await _confirm('comms.cancel.title', 'comms.cancel.body');
    if (!ok || !mounted) return;
    await _act(() async => await _repo.cancel(c.id), 'comms.done.cancelled');
    await _load();
  }

  Future<void> _unschedule(Campaign c) async {
    await _act(
      () async => await _repo.unschedule(c.id),
      'comms.done.unscheduled',
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('comms.detail.title'))),
      body: d == null
          ? (_error == null
                ? const Center(child: FFSpinner())
                : FFEmptyState(
                    title: context.tr('comms.loadFailed'),
                    body: errorMessage(FFLocaleScope.of(context), _error!),
                    action: FilledButton(
                      onPressed: _load,
                      child: Text(context.tr('comms.retry')),
                    ),
                  ))
          : RefreshIndicator(onRefresh: _load, child: _body(context, d)),
    );
  }

  Widget _body(BuildContext context, CampaignDetail d) {
    final c = d.campaign;
    final theme = Theme.of(context);
    final when = switch (c.status) {
      CampaignStatus.scheduled when c.scheduledAt != null =>
        context
            .tr('comms.scheduledFor')
            .replaceFirst('{when}', formatWhen(context, c.scheduledAt!)),
      _ when c.createdAt != null => formatWhen(context, c.createdAt!),
      _ => '',
    };
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                c.displayTitle.isEmpty
                    ? context.tr('comms.untitled')
                    : c.displayTitle,
                style: theme.textTheme.titleLarge,
              ),
            ),
            CampaignStatusPill(c.status),
          ],
        ),
        const SizedBox(height: FFTokens.spacingXs),
        Text(
          [
            if (c.purpose != null)
              context.tr('comms.purpose.${c.purpose!.name}'),
            if (when.isNotEmpty) when,
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        if (c.createdByName != null || c.templateName != null)
          Text(
            [
              if (c.createdByName != null)
                context
                    .tr('comms.history.createdBy')
                    .replaceFirst('{name}', c.createdByName!),
              if (c.templateName != null)
                context
                    .tr('comms.history.fromTemplate')
                    .replaceFirst(
                      '{name}',
                      c.templateSystem && c.templateKey != null
                          ? context.tr('comms.tpl.${c.templateKey}')
                          : c.templateName!,
                    ),
            ].join(' · '),
            key: const Key('detail-origin'),
            style: theme.textTheme.bodySmall,
          ),
        if (c.status == CampaignStatus.sending) ...[
          const SizedBox(height: FFTokens.spacingSm),
          FFAlert(
            tone: FFAlertTone.info,
            message: context.tr('comms.detail.sending'),
          ),
        ],
        FFSectionTitle(context.tr('comms.detail.audience')),
        FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('comms.preset.${c.audience.preset ?? 'all'}'),
                style: theme.textTheme.titleSmall,
              ),
              if (c.audience.filter != null)
                Text(
                  context.tr('comms.detail.withConditions'),
                  style: theme.textTheme.bodySmall,
                ),
              if (c.counts != null)
                Text(
                  context
                      .tr(
                        c.counts!.targeted == 1
                            ? 'comms.audience.matchOne'
                            : 'comms.audience.match',
                      )
                      .replaceFirst('{n}', '${c.counts!.targeted}'),
                  style: theme.textTheme.bodyMedium,
                ),
              Text(
                c.channels.map((ch) => channelLabel(context, ch)).join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        FFSectionTitle(context.tr('comms.detail.message')),
        InAppMessageCard(
          message: RenderedMessage(
            title: c.content.title,
            body: c.content.body,
            ctaLabel: c.content.ctaLabel,
            deepLink: c.content.deepLink,
          ),
        ),
        if (c.content.variables.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingXs),
            child: Text(
              context.tr('comms.detail.personalised'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (!c.status.editable &&
            c.status != CampaignStatus.scheduled &&
            c.status != CampaignStatus.cancelled) ...[
          FFSectionTitle(context.tr('comms.detail.delivery')),
          if (d.stats != null) ...[
            FFCard(
              key: const Key('detail-stats'),
              child: CampaignStatsGrid(stats: d.stats!),
            ),
            const SizedBox(height: FFTokens.spacingSm),
          ],
          FFCard(
            child: DeliveryStats(
              progress: d.progress,
              skipped: c.counts?.skipped ?? const {},
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          OutlinedButton.icon(
            key: const Key('detail-recipients'),
            onPressed: () => context.push(
              '/owner/communications/campaigns/${c.id}/recipients',
            ),
            icon: const Icon(Icons.people_outline),
            label: Text(context.tr('comms.history.seeRecipients')),
          ),
          FFSectionTitle(context.tr('comms.results.title')),
          ResultsCard(
            titleKey: 'comms.results.campaignTitle',
            repository: widget.repository,
            load: (repo) => repo.campaignResults(c.id),
          ),
        ],
        const SizedBox(height: FFTokens.spacingLg),
        if (c.status == CampaignStatus.draft) ...[
          FilledButton.icon(
            key: const Key('detail-edit'),
            onPressed: _busy ? null : () => _edit(c),
            icon: const Icon(Icons.edit_outlined),
            label: Text(context.tr('comms.detail.edit')),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          OutlinedButton(
            key: const Key('detail-delete'),
            onPressed: _busy ? null : () => _delete(c),
            child: Text(context.tr('comms.detail.delete')),
          ),
        ],
        if (c.status == CampaignStatus.scheduled) ...[
          OutlinedButton(
            key: const Key('detail-unschedule'),
            onPressed: _busy ? null : () => _unschedule(c),
            child: Text(context.tr('comms.detail.unschedule')),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          OutlinedButton(
            key: const Key('detail-cancel'),
            onPressed: _busy ? null : () => _cancel(c),
            child: Text(context.tr('comms.detail.cancel')),
          ),
        ],
      ],
    );
  }
}
