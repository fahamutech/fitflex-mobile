import 'package:flutter/material.dart';

import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/i18n.dart';
import '../data/communication_models.dart';
import 'comms_format.dart';

/// How the message looks to a member on each chosen channel, using one
/// real member's values.
class CampaignPreviewView extends StatelessWidget {
  const CampaignPreviewView({
    super.key,
    required this.message,
    required this.channels,
    this.gymName,
  });

  final RenderedMessage message;
  final Set<CommChannel> channels;
  final String? gymName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.memberName != null && message.memberName!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: Text(
              context
                  .tr('comms.preview.asSeenBy')
                  .replaceFirst('{name}', message.memberName!),
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (channels.contains(CommChannel.push)) ...[
          _Label(CommChannel.push),
          _PushBanner(message: message, sender: gymName),
          const SizedBox(height: FFTokens.spacingMd),
        ],
        if (channels.contains(CommChannel.inApp)) ...[
          _Label(CommChannel.inApp),
          InAppMessageCard(message: message, sender: gymName),
        ],
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.channel);
  final CommChannel channel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
    child: Text(
      channelLabel(context, channel),
      style: Theme.of(context).textTheme.labelLarge,
    ),
  );
}

/// The message as it appears in the member's inbox.
class InAppMessageCard extends StatelessWidget {
  const InAppMessageCard({super.key, required this.message, this.sender});

  final RenderedMessage message;
  final String? sender;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FFCard(
      key: const Key('preview-in-app'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sender != null)
            Text(
              sender!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          const SizedBox(height: FFTokens.spacing2xs),
          Text(message.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: FFTokens.spacingXs),
          Text(message.body, style: theme.textTheme.bodyMedium),
          if (message.ctaLabel != null && message.ctaLabel!.isNotEmpty) ...[
            const SizedBox(height: FFTokens.spacingSm),
            FilledButton(onPressed: null, child: Text(message.ctaLabel!)),
          ],
        ],
      ),
    );
  }
}

class _PushBanner extends StatelessWidget {
  const _PushBanner({required this.message, this.sender});

  final RenderedMessage message;
  final String? sender;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('preview-push'),
      padding: const EdgeInsets.all(FFTokens.spacingSm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.fitness_center,
            size: FFTokens.iconMd,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: FFTokens.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FitFlex${sender == null ? '' : ' · $sender'}',
                  style: theme.textTheme.labelSmall,
                ),
                Text(
                  message.title,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  message.body,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
