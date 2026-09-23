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
        onPressed: () => context.go(AppRoutes.memberTrainerConnections),
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

/// Trainers & sharing: every connection, what it can see, and controls to
/// change sharing, cancel a request or disconnect.
class MemberTrainerConnectionsPage extends StatefulWidget {
  const MemberTrainerConnectionsPage({super.key});

  @override
  State<MemberTrainerConnectionsPage> createState() =>
      _MemberTrainerConnectionsPageState();
}

class _MemberTrainerConnectionsPageState
    extends State<MemberTrainerConnectionsPage> {
  String? _busyId;

  MemberShellState? get _shell =>
      context.findAncestorStateOfType<MemberShellState>();

  Future<void> _run(String id, Future<void> Function() op) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr('connect.failed');
    setState(() => _busyId = id);
    try {
      await op();
      await _shell?.refreshConnections();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _edit(TrainerConnection c) async {
    final perms = await showTrainerSharingSheet(
      context,
      trainerName: c.trainer?.displayName ?? context.tr('connect.yourTrainer'),
      initial: c.permissions,
      isRequest: false,
    );
    if (perms == null || !mounted) return;
    final api = AppScope.of(context).api;
    await _run(c.id, () => api.updateTrainerConnection(c.id, perms.toJson()));
  }

  Future<void> _end(TrainerConnection c) async {
    final pending = c.status == TrainerConnectionStatus.pending;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          ctx.tr(pending ? 'connect.cancelTitle' : 'connect.endTitle'),
        ),
        content: Text(
          ctx
              .tr(pending ? 'connect.cancelBody' : 'connect.endBody')
              .replaceAll('{name}', c.trainer?.displayName ?? ''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('workout.keepGoing')),
          ),
          FilledButton(
            key: const Key('connect-end-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr(pending ? 'connect.cancel' : 'connect.end')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final api = AppScope.of(context).api;
    await _run(c.id, () => api.endTrainerConnection(c.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connections = MemberDataScope.of(context).trainerConnections;
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.go(AppRoutes.memberProfile),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(context.tr('member.profile')),
          ),
        ),
        FFPageHeader(
          title: context.tr('connect.pageTitle'),
          description: context.tr('connect.pageBody'),
        ),
        if (connections.isEmpty)
          FFEmptyState(
            title: context.tr('connect.none'),
            body: context.tr('connect.noneBody'),
            action: OutlinedButton(
              onPressed: () => context.go(AppRoutes.memberTrainers),
              child: Text(context.tr('member.findTrainer')),
            ),
          )
        else
          for (final c in connections)
            FFCard(
              key: Key('connection-${c.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      FFAvatar(
                        name: c.trainer?.displayName ?? '?',
                        src: c.trainer?.photoUrl,
                      ),
                      const SizedBox(width: FFTokens.spacingMd),
                      Expanded(
                        child: Text(
                          c.trainer?.displayName ?? '',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      FFPill(
                        label: context.tr('connect.status.${c.status.wire}'),
                        filled: c.status == TrainerConnectionStatus.active,
                      ),
                    ],
                  ),
                  const SizedBox(height: FFTokens.spacingSm),
                  Text(
                    '${context.tr('share.canSee')}: ${sharedSummary(context, c.permissions)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (c.status.isOpen) ...[
                    const SizedBox(height: FFTokens.spacingSm),
                    Wrap(
                      spacing: FFTokens.spacingSm,
                      children: [
                        OutlinedButton(
                          key: Key('connection-edit-${c.id}'),
                          onPressed: _busyId == c.id ? null : () => _edit(c),
                          child: Text(context.tr('connect.manage')),
                        ),
                        TextButton(
                          key: Key('connection-end-${c.id}'),
                          onPressed: _busyId == c.id ? null : () => _end(c),
                          child: Text(
                            context.tr(
                              c.status == TrainerConnectionStatus.pending
                                  ? 'connect.cancel'
                                  : 'connect.end',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
      ],
    );
  }
}
