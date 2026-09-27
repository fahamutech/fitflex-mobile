// Communication history building blocks: a campaign's numbers, a message's
// status on each channel, one communication in a member's timeline, one
// campaign recipient, a message in full (bottom sheet), and the Messages
// card on the owner's member detail page.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../app_scope.dart';
import '../../../../shared/api_client.dart';
import '../../../../shared/api_error_message.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/i18n.dart';
import '../data/communication_repository.dart';
import '../data/history_models.dart';
import 'comms_format.dart';

const _knownFailures = {
  'invalid_recipient',
  'recipient_opted_out',
  'template_not_approved',
  'provider_unavailable',
  'provider_failed',
  'rate_limited',
  'push_failed',
  'push_disabled',
  'push_unavailable',
  'no_device',
  'whatsapp_template_missing',
  'channel_not_supported',
};

/// Localised reason a message failed; unknown codes are shown as they are.
String failureReasonLabel(BuildContext context, String code) =>
    _knownFailures.contains(code) ? context.tr('comms.failure.$code') : code;

FFBadgeTone _statusTone(String status) => switch (status) {
  'failed' => FFBadgeTone.danger,
  'skipped' => FFBadgeTone.gray,
  'queued' || 'sending' => FFBadgeTone.warning,
  'sent' => FFBadgeTone.brand,
  _ => FFBadgeTone.success,
};

FFBadgeTone _outcomeTone(String outcome) => switch (outcome) {
  'reached' => FFBadgeTone.success,
  'pending' => FFBadgeTone.warning,
  'failed' => FFBadgeTone.danger,
  _ => FFBadgeTone.gray,
};

/// "Reached", "Waiting", "Failed", "Skipped" for a whole communication.
class OutcomeBadge extends StatelessWidget {
  const OutcomeBadge(this.outcome, {super.key});
  final String outcome;

  @override
  Widget build(BuildContext context) => FFBadge(
    label: context.tr('comms.outcome.$outcome'),
    tone: _outcomeTone(outcome),
  );
}

/// A campaign's numbers from the ledger.
class CampaignStatsGrid extends StatelessWidget {
  const CampaignStatsGrid({super.key, required this.stats});

  final CampaignStats stats;

  @override
  Widget build(BuildContext context) {
    final t = stats.totals;
    final cells = [
      ('targeted', stats.targeted),
      ('sent', t.sent),
      ('delivered', t.delivered),
      ('opened', t.opened),
      ('clicked', t.clicked),
      ('failed', t.failed),
      if (t.skipped > 0) ('skipped', t.skipped),
      if (t.pending > 0) ('pending', t.pending),
    ];
    final theme = Theme.of(context);
    return Wrap(
      spacing: FFTokens.spacingMd,
      runSpacing: FFTokens.spacingSm,
      children: [
        for (final (key, n) in cells)
          SizedBox(
            width: 88,
            child: Column(
              key: Key('stat-$key'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$n',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: key == 'failed' && n > 0
                        ? theme.colorScheme.error
                        : null,
                  ),
                ),
                Text(
                  context.tr('comms.stat.$key'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One channel of a message: icon, channel and status; tap for details.
class ChannelStatusChip extends StatelessWidget {
  const ChannelStatusChip({super.key, required this.message, this.onTap});

  final CommMessage message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ch = message.channel;
    return InkWell(
      key: Key('msg-${message.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(FFTokens.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ch != null) ...[
              Icon(channelIcon(ch), size: FFTokens.iconSm),
              const SizedBox(width: FFTokens.spacing2xs),
              Text(
                channelLabel(context, ch),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: FFTokens.spacingXs),
            ],
            FFBadge(
              label: context.tr('comms.msgStatus.${message.status}'),
              tone: _statusTone(message.status),
            ),
          ],
        ),
      ),
    );
  }
}

String _whyNot(BuildContext context, CommMessage m) {
  if (m.failureReason != null) {
    return failureReasonLabel(context, m.failureReason!);
  }
  if (m.skipReason != null) return skipReasonLabel(context, m.skipReason!);
  return '';
}

/// The channel chips of a communication, with why any didn't go out.
class _Channels extends StatelessWidget {
  const _Channels({required this.channels, required this.onOpen});

  final List<CommMessage> channels;
  final ValueChanged<CommMessage> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final m in channels)
          Row(
            children: [
              ChannelStatusChip(message: m, onTap: () => onOpen(m)),
              if (_whyNot(context, m).isNotEmpty) ...[
                const SizedBox(width: FFTokens.spacingXs),
                Flexible(
                  child: Text(
                    _whyNot(context, m),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: m.isFailed ? theme.colorScheme.error : null,
                    ),
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

/// One communication in a member's timeline.
class CommunicationTile extends StatelessWidget {
  const CommunicationTile({
    super.key,
    required this.item,
    required this.onOpen,
  });

  final CommunicationItem item;
  final ValueChanged<CommMessage> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = item.createdAt;
    return FFCard(
      key: Key('comm-${item.key}'),
      margin: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title.isEmpty
                      ? context.tr('comms.untitled')
                      : item.title,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              OutcomeBadge(item.outcome),
            ],
          ),
          const SizedBox(height: FFTokens.spacing2xs),
          Text(
            [
              if (when != null) formatWhen(context, when),
              if (item.messageType != null)
                context.tr('comms.purpose.${item.messageType!.name}'),
              if (item.category != null)
                context.tr('comms.category.${item.category}'),
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          if (item.body.isNotEmpty) ...[
            const SizedBox(height: FFTokens.spacingXs),
            Text(
              item.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: FFTokens.spacingXs),
          _Channels(channels: item.channels, onOpen: onOpen),
        ],
      ),
    );
  }
}

/// One member a campaign went to.
class RecipientTile extends StatelessWidget {
  const RecipientTile({
    super.key,
    required this.recipient,
    required this.onOpen,
    this.onOpenMember,
  });

  final Recipient recipient;
  final ValueChanged<CommMessage> onOpen;
  final VoidCallback? onOpenMember;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FFCard(
      key: Key('recipient-${recipient.memberId}'),
      margin: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onOpenMember,
                  child: Text(
                    recipient.memberName ??
                        context.tr('comms.history.unknownMember'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ),
              OutcomeBadge(recipient.outcome),
            ],
          ),
          const SizedBox(height: FFTokens.spacingXs),
          _Channels(channels: recipient.channels, onOpen: onOpen),
        ],
      ),
    );
  }
}

/// Opens one message in full.
Future<void> showMessageDetail(
  BuildContext context, {
  required CommunicationRepository repository,
  required String messageId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => FractionallySizedBox(
    heightFactor: 0.85,
    child: _MessageDetail(repository: repository, messageId: messageId),
  ),
);

class _MessageDetail extends StatefulWidget {
  const _MessageDetail({required this.repository, required this.messageId});

  final CommunicationRepository repository;
  final String messageId;

  @override
  State<_MessageDetail> createState() => _MessageDetailState();
}

class _MessageDetailState extends State<_MessageDetail> {
  CommMessage? _m;
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.repository
        .message(widget.messageId)
        .then((m) => mounted ? setState(() => _m = m) : null)
        .catchError((Object e) => mounted ? setState(() => _error = e) : null);
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    if (m == null) {
      return Center(
        child: _error == null
            ? const FFSpinner()
            : FFEmptyState(
                title: context.tr('comms.loadFailed'),
                body: errorMessage(FFLocaleScope.of(context), _error!),
              ),
      );
    }
    final theme = Theme.of(context);
    String? day(DateTime? d) => d == null ? null : formatWhen(context, d);
    final times = [
      ('created', m.createdAt),
      ('sent', m.sentAt),
      ('delivered', m.deliveredAt),
      ('opened', m.openedAt),
      ('clicked', m.clickedAt),
      ('failed', m.failedAt),
      ('nextAttempt', m.nextAttemptAt),
    ].where((e) => e.$2 != null);
    return ListView(
      key: const Key('message-detail'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                m.memberName ?? context.tr('comms.history.unknownMember'),
                style: theme.textTheme.titleMedium,
              ),
            ),
            ChannelStatusChip(message: m),
          ],
        ),
        if (m.campaignName != null)
          Text(m.campaignName!, style: theme.textTheme.bodySmall),
        const SizedBox(height: FFTokens.spacingMd),
        if (m.isFailed || m.isSkipped)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
            child: FFAlert(
              key: const Key('message-why'),
              tone: m.isFailed ? FFAlertTone.error : FFAlertTone.info,
              message: [
                _whyNot(context, m),
                if (m.isFailed)
                  context.tr(
                    m.failurePermanent
                        ? 'comms.history.notRetried'
                        : 'comms.history.retried',
                  ),
              ].where((s) => s.isNotEmpty).join(' — '),
            ),
          ),
        FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.title, style: theme.textTheme.titleSmall),
              const SizedBox(height: FFTokens.spacingXs),
              Text(m.body, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        for (final (key, at) in times)
          _Row(label: context.tr('comms.history.at.$key'), value: day(at)!),
        if (m.messageType != null)
          _Row(
            label: context.tr('comms.history.type'),
            value: [
              context.tr('comms.purpose.${m.messageType!.name}'),
              if (m.category != null)
                context.tr('comms.category.${m.category}'),
            ].join(' · '),
          ),
        if (m.templateName != null)
          _Row(
            label: context.tr('comms.history.template'),
            value: m.templateSystem && m.templateKey != null
                ? context.tr('comms.tpl.${m.templateKey}')
                : m.templateName!,
          ),
        if (m.locale != null)
          _Row(
            label: context.tr('comms.history.language'),
            value: context.tr('comms.lang.${m.locale}'),
          ),
        if (m.attempts > 1)
          _Row(
            label: context.tr('comms.history.attempts'),
            value: '${m.attempts}',
          ),
        const SizedBox(height: FFTokens.spacingSm),
        Text(
          context.tr('comms.history.provider'),
          style: theme.textTheme.titleSmall,
        ),
        _Row(
          label: context.tr('comms.history.via'),
          value: context.tr('comms.provider.${m.provider.name}'),
        ),
        if (m.provider.templateName != null)
          _Row(
            label: context.tr('comms.history.providerTemplate'),
            value: '${m.provider.templateName} (${m.provider.language ?? '–'})',
          ),
        if (m.provider.devices != null)
          _Row(
            label: context.tr('comms.history.devices'),
            value: '${m.provider.devices}',
          ),
        if (m.provider.messageId != null)
          _Row(
            key: const Key('provider-ref'),
            label: context.tr('comms.history.reference'),
            value: m.provider.messageId!,
            copyable: true,
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FFTokens.spacing2xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: copyable
                ? SelectableText(value, style: theme.textTheme.bodyMedium)
                : Text(value, style: theme.textTheme.bodyMedium),
          ),
          if (copyable)
            IconButton(
              tooltip: context.tr('comms.history.copy'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy, size: FFTokens.iconSm),
              onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            ),
        ],
      ),
    );
  }
}

/// The Messages section of the owner's member detail page: the latest few
/// communications from this gym. Hidden for staff who can't see messages.
class MemberMessagesCard extends StatefulWidget {
  const MemberMessagesCard({
    super.key,
    required this.memberId,
    this.repository,
  });

  final String memberId;
  final CommunicationRepository? repository;

  @override
  State<MemberMessagesCard> createState() => _MemberMessagesCardState();
}

class _MemberMessagesCardState extends State<MemberMessagesCard> {
  late CommunicationRepository _repo;
  HistoryPage<CommunicationItem>? _page;
  bool _hidden = false;
  bool _failed = false;
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
      final page = await _repo.memberCommunications(widget.memberId, limit: 3);
      if (mounted) setState(() => _page = page);
    } on ApiException catch (e) {
      // No permission to see messages (staff without the communications
      // scope) or not this gym's member: the section just isn't shown.
      if (!mounted) return;
      setState(() => e.status == 403 ? _hidden = true : _failed = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final page = _page;
    return Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingMd),
      child: FFCard(
        key: const Key('member-messages'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.forum_outlined,
                  size: FFTokens.iconSm,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: FFTokens.spacingSm),
                Expanded(
                  child: Text(
                    context.tr('comms.history.memberSection'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (page != null && page.items.isNotEmpty)
                  TextButton(
                    key: const Key('member-messages-all'),
                    onPressed: () => context.push(
                      '/owner/members/${widget.memberId}/messages',
                    ),
                    child: Text(context.tr('members.viewAll')),
                  ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingSm),
            if (_failed)
              Text(
                context.tr('comms.loadFailed'),
                style: theme.textTheme.bodySmall,
              )
            else if (page == null)
              const Center(child: FFSpinner())
            else if (page.items.isEmpty)
              Text(
                context.tr('comms.history.noneYet'),
                style: theme.textTheme.bodySmall,
              )
            else
              for (final item in page.items)
                CommunicationTile(
                  item: item,
                  onOpen: (m) => showMessageDetail(
                    context,
                    repository: _repo,
                    messageId: m.id,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
