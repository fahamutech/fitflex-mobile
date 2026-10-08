import 'package:flutter/material.dart';

import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/i18n.dart';
import '../communication_controller.dart';
import '../data/communication_models.dart';
import 'comms_format.dart';

/// In-app, push and WhatsApp, with how many members each can reach.
class ChannelSelector extends StatelessWidget {
  const ChannelSelector({super.key, required this.controller});

  final CampaignComposerController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final reach = c.reach?.counts;
    return Column(
      children: [
        for (final ch in CommChannel.values)
          _ChannelTile(
            channel: ch,
            available: c.channelUsable(ch),
            needsTemplate:
                ch == CommChannel.whatsapp && c.channelsAvailable.of(ch),
            selected: c.channels.contains(ch),
            reached: reach?.byChannel[ch]?.queued,
            targeted: reach?.targeted,
            onChanged: (on) => c.toggleChannel(ch, on),
          ),
        if (reach != null && reach.skipped.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingSm),
            child: Text(
              [
                for (final e in reach.skipped.entries)
                  '${skipReasonLabel(context, e.key)}: ${e.value}',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.available,
    required this.selected,
    required this.onChanged,
    this.needsTemplate = false,
    this.reached,
    this.targeted,
  });

  final CommChannel channel;
  final bool available;
  final bool selected;

  /// Set up, but this message didn't start from an approved template.
  final bool needsTemplate;
  final int? reached;
  final int? targeted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String subtitle;
    if (!available) {
      subtitle = context.tr(
        channel == CommChannel.sms
            ? 'comms.channel.smsOff'
            : channel != CommChannel.whatsapp
            ? 'comms.channel.pushOff'
            : needsTemplate
            ? 'comms.channel.whatsappNeedsTemplate'
            : 'comms.channel.whatsappSoon',
      );
    } else if (reached != null && targeted != null) {
      subtitle = context
          .tr('comms.channel.reaches')
          .replaceFirst('{n}', '$reached')
          .replaceFirst('{total}', '$targeted');
    } else {
      subtitle = context.tr('comms.channel.${channel.wire}.body');
    }
    return FFCard(
      margin: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: CheckboxListTile(
        key: Key('channel-${channel.wire}'),
        contentPadding: EdgeInsets.zero,
        value: selected && available,
        onChanged: available ? (v) => onChanged(v ?? false) : null,
        secondary: Icon(
          channelIcon(channel),
          color: available ? theme.colorScheme.primary : theme.disabledColor,
        ),
        title: Text(channelLabel(context, channel)),
        subtitle: Text(subtitle),
      ),
    );
  }
}
