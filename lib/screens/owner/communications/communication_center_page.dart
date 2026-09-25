// Communication Center (Gym Owner → Messages): an overview of who can be
// reached and recent messages, and the list of campaigns. UI only — data
// and logic live in [CommunicationCenterController].

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import 'communication_controller.dart';
import 'data/communication_models.dart';
import 'data/communication_repository.dart';
import 'widgets/campaign_status.dart';
import 'widgets/comms_format.dart';

class CommunicationCenterPage extends StatefulWidget {
  const CommunicationCenterPage({super.key, this.gymId, this.repository});

  final String? gymId;

  /// Injectable for tests; defaults to the app's API.
  final CommunicationRepository? repository;

  @override
  State<CommunicationCenterPage> createState() =>
      _CommunicationCenterPageState();
}

class _CommunicationCenterPageState extends State<CommunicationCenterPage> {
  CommunicationCenterController? _controller;
  String _tab = 'overview';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= CommunicationCenterController(
      widget.repository ?? CommunicationRepository(AppScope.of(context).api),
      gymId: widget.gymId,
    )..load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _gymQuery() => widget.gymId == null ? '' : '?gymId=${widget.gymId}';

  Future<void> _newMessage() async {
    await context.push('/owner/communications/new${_gymQuery()}');
    if (mounted) await _controller!.load();
  }

  Future<void> _open(Campaign c) async {
    await context.push('/owner/communications/campaigns/${c.id}');
    if (mounted) await _controller!.load();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller!;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('comms.title'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('comms-new'),
        onPressed: _newMessage,
        icon: const Icon(Icons.edit_outlined),
        label: Text(context.tr('comms.new')),
      ),
      body: AnimatedBuilder(
        animation: c,
        builder: (context, _) => RefreshIndicator(
          onRefresh: c.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              FFTokens.spacingLg,
              FFTokens.spacingSm,
              FFTokens.spacingLg,
              96,
            ),
            children: [
              Text(
                context.tr('comms.subtitle'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: FFTokens.spacingMd),
              FFSegmented(
                value: _tab,
                options: [
                  ('overview', context.tr('comms.tab.overview')),
                  ('campaigns', context.tr('comms.tab.campaigns')),
                ],
                onChanged: (v) => setState(() => _tab = v),
              ),
              const SizedBox(height: FFTokens.spacingMd),
              if (c.loading && c.overview == null)
                const Padding(
                  padding: EdgeInsets.all(FFTokens.spacingXl),
                  child: Center(child: FFSpinner()),
                )
              else if (c.error != null && c.overview == null)
                FFEmptyState(
                  title: context.tr('comms.loadFailed'),
                  body: errorMessage(FFLocaleScope.of(context), c.error!),
                  action: FilledButton(
                    onPressed: c.load,
                    child: Text(context.tr('comms.retry')),
                  ),
                )
              else if (_tab == 'overview')
                ..._overview(context, c)
              else
                ..._campaigns(context, c),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _overview(
    BuildContext context,
    CommunicationCenterController c,
  ) {
    final o = c.overview!;
    return [
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FFMetricCard(
                key: const Key('comms-members'),
                label: context.tr('comms.overview.members'),
                value: o.members?.toString() ?? '–',
                sub: context.tr('comms.overview.membersSub'),
              ),
            ),
            const SizedBox(width: FFTokens.spacingSm),
            Expanded(
              child: FFMetricCard(
                label: context.tr('comms.overview.sent'),
                value:
                    '${o.count(CampaignStatus.sent) + o.count(CampaignStatus.sending) + o.count(CampaignStatus.partiallyFailed)}',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: FFTokens.spacingSm),
      Row(
        children: [
          Expanded(
            child: FFMetricCard(
              label: context.tr('comms.overview.scheduled'),
              value: '${o.count(CampaignStatus.scheduled)}',
            ),
          ),
          const SizedBox(width: FFTokens.spacingSm),
          Expanded(
            child: FFMetricCard(
              label: context.tr('comms.overview.drafts'),
              value: '${o.count(CampaignStatus.draft)}',
            ),
          ),
        ],
      ),
      FFSectionTitle(context.tr('comms.overview.channels')),
      FFCard(
        child: Column(
          children: [
            for (final ch in CommChannel.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(channelIcon(ch)),
                title: Text(channelLabel(context, ch)),
                trailing: FFBadge(
                  key: Key('channel-status-${ch.wire}'),
                  label: context.tr(
                    o.channels.of(ch)
                        ? 'comms.channel.on'
                        : ch == CommChannel.whatsapp
                        ? 'comms.channel.soon'
                        : 'comms.channel.off',
                  ),
                  tone: o.channels.of(ch)
                      ? FFBadgeTone.success
                      : FFBadgeTone.gray,
                ),
              ),
          ],
        ),
      ),
      FFSectionTitle(context.tr('comms.overview.recent')),
      if (o.recent.isEmpty)
        FFEmptyState(
          title: context.tr('comms.empty.title'),
          body: context.tr('comms.empty.body'),
        )
      else
        for (final campaign in o.recent)
          CampaignTile(campaign: campaign, onTap: () => _open(campaign)),
    ];
  }

  List<Widget> _campaigns(
    BuildContext context,
    CommunicationCenterController c,
  ) {
    const filters = <CampaignStatus?>[
      null,
      CampaignStatus.draft,
      CampaignStatus.scheduled,
      CampaignStatus.sending,
      CampaignStatus.sent,
      CampaignStatus.cancelled,
    ];
    return [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final f in filters)
              Padding(
                padding: const EdgeInsets.only(right: FFTokens.spacingXs),
                child: FFPill(
                  key: Key('filter-${f?.wire ?? 'all'}'),
                  label: f == null
                      ? context.tr('comms.filter.all')
                      : context.tr('comms.status.${f.wire}'),
                  filled: c.statusFilter == f,
                  onTap: () => c.setStatusFilter(f),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: FFTokens.spacingMd),
      if (c.campaigns.isEmpty)
        FFEmptyState(
          title: context.tr('comms.empty.title'),
          body: context.tr('comms.empty.body'),
        )
      else
        for (final campaign in c.campaigns)
          CampaignTile(campaign: campaign, onTap: () => _open(campaign)),
    ];
  }
}
