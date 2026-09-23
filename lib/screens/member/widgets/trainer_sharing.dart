import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/activity/trainer_connection.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../member_shell.dart';

String permissionLabel(BuildContext context, TrainerPermission p) =>
    context.tr('share.${p.wire}');

String permissionHint(BuildContext context, TrainerPermission p) =>
    context.tr('share.${p.wire}.hint');

/// "Steps, Workout history" or "Nothing shared".
String sharedSummary(BuildContext context, TrainerPermissions perms) {
  if (perms.isEmpty) return context.tr('share.nothing');
  return [
    for (final p in TrainerPermission.values)
      if (perms.has(p)) permissionLabel(context, p),
  ].join(', ');
}

/// Lets the member pick exactly what [trainerName] may see. Returns the
/// chosen permissions, or null if dismissed.
Future<TrainerPermissions?> showTrainerSharingSheet(
  BuildContext context, {
  required String trainerName,
  required TrainerPermissions initial,
  required bool isRequest,
}) => showModalBottomSheet<TrainerPermissions>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _SharingSheet(
    trainerName: trainerName,
    initial: initial,
    isRequest: isRequest,
  ),
);

class _SharingSheet extends StatefulWidget {
  const _SharingSheet({
    required this.trainerName,
    required this.initial,
    required this.isRequest,
  });

  final String trainerName;
  final TrainerPermissions initial;
  final bool isRequest;

  @override
  State<_SharingSheet> createState() => _SharingSheetState();
}

class _SharingSheetState extends State<_SharingSheet> {
  late TrainerPermissions _perms = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          FFTokens.spacingLg,
          FFTokens.spacingLg,
          FFTokens.spacingLg,
          FFTokens.spacingMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context
                  .tr(widget.isRequest ? 'share.requestTitle' : 'share.title')
                  .replaceAll('{name}', widget.trainerName),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: FFTokens.spacingXs),
            Text(
              context.tr('share.body').replaceAll('{name}', widget.trainerName),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in TrainerPermission.values)
                    SwitchListTile(
                      key: Key('share-${p.wire}'),
                      contentPadding: EdgeInsets.zero,
                      value: _perms.has(p),
                      onChanged: (on) =>
                          setState(() => _perms = _perms.toggle(p, on)),
                      title: Text(permissionLabel(context, p)),
                      subtitle: Text(permissionHint(context, p)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('share-save'),
                onPressed: () => Navigator.pop(context, _perms),
                child: Text(
                  context.tr(
                    widget.isRequest ? 'share.sendRequest' : 'share.save',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Train with …" on a trainer's profile: connect, or see where things are.
class TrainerConnectCard extends StatefulWidget {
  const TrainerConnectCard({
    super.key,
    required this.trainerId,
    required this.trainerName,
  });

  final String trainerId;
  final String trainerName;

  @override
  State<TrainerConnectCard> createState() => _TrainerConnectCardState();
}

class _TrainerConnectCardState extends State<TrainerConnectCard> {
  bool _busy = false;

  Future<void> _connect() async {
    final perms = await showTrainerSharingSheet(
      context,
      trainerName: widget.trainerName,
      initial: const TrainerPermissions(),
      isRequest: true,
    );
    if (perms == null || !mounted) return;
    final api = AppScope.of(context).api;
    final shell = context.findAncestorStateOfType<MemberShellState>();
    final messenger = ScaffoldMessenger.of(context);
    final sent = context.tr('connect.sent');
    final failed = context.tr('connect.failed');
    setState(() => _busy = true);
    try {
      await api.requestTrainerConnection(widget.trainerId, perms.toJson());
      await shell?.refreshConnections();
      messenger.showSnackBar(SnackBar(content: Text(sent)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = MemberDataScope.of(context).connectionWith(widget.trainerId);
    final String title;
    final String body;
    final Widget action;
    if (c == null) {
      title = context
          .tr('connect.title')
          .replaceAll('{name}', widget.trainerName);
      body = context.tr('connect.body');
      action = FilledButton.tonalIcon(
        key: const Key('trainer-connect'),
        onPressed: _busy ? null : _connect,
        icon: const Icon(Icons.link, size: 18),
        label: Text(context.tr('connect.action')),
      );
    } else {
      title = context.tr(
        c.status == TrainerConnectionStatus.active
            ? 'connect.connected'
            : 'connect.pending',
      );
      body =
          '${context.tr('share.canSee')}: ${sharedSummary(context, c.permissions)}';
      action = OutlinedButton(
        key: const Key('trainer-manage-sharing'),
        onPressed: () => context.go(AppRoutes.memberActivitySharing),
        child: Text(context.tr('connect.manage')),
      );
    }
    return FFCard(
      key: const Key('trainer-connect-card'),
      margin: const EdgeInsets.only(top: FFTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Text(body, style: theme.textTheme.bodySmall),
          const SizedBox(height: FFTokens.spacingSm),
          action,
        ],
      ),
    );
  }
}
