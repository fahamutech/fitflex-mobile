import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/activity/trainer_connection.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../member/widgets/trainer_sharing.dart' show sharedSummary;
import 'trainer_client_page.dart';
import 'trainer_plan_editor_page.dart';

/// Trainer's Clients tab: connection requests, connected clients (who
/// chose what to share), and the trainer's workout plan library.
class TrainerClientsTab extends StatefulWidget {
  const TrainerClientsTab({super.key});

  @override
  State<TrainerClientsTab> createState() => _TrainerClientsTabState();
}

class _TrainerClientsTabState extends State<TrainerClientsTab> {
  List<TrainerConnection> _clients = [];
  List<TrainerPlan> _plans = [];
  bool _loaded = false;
  bool _failed = false;
  String? _busyId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded && !_failed) _load();
  }

  Future<void> _load() async {
    final api = AppScope.of(context).api;
    try {
      final results = await Future.wait([
        api.trainerClients(),
        api.trainerPlans(),
      ]);
      if (!mounted) return;
      setState(() {
        _clients = [
          for (final r in results[0].whereType<Map>())
            TrainerConnection.fromJson(Map<String, dynamic>.from(r)),
        ];
        _plans = [
          for (final r in results[1].whereType<Map>())
            TrainerPlan.fromJson(Map<String, dynamic>.from(r)),
        ];
        _loaded = true;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _decide(TrainerConnection c, bool accept) async {
    final api = AppScope.of(context).api;
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr('owner.errorGeneric');
    setState(() => _busyId = c.id);
    try {
      await api.trainerDecideClient(c.id, accept: accept);
      await _load();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _openClient(TrainerConnection c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrainerClientPage(connection: c, plans: _plans),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _editPlan([TrainerPlan? plan]) async {
    final changed = await openTrainerPlanEditor(context, plan: plan);
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_failed) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          FFEmptyState(
            title: context.tr('owner.errorGeneric'),
            action: OutlinedButton(
              onPressed: () {
                setState(() => _failed = false);
                _load();
              },
              child: Text(context.tr('clients.retry')),
            ),
          ),
        ],
      );
    }
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final pending = _clients
        .where((c) => c.status == TrainerConnectionStatus.pending)
        .toList();
    final active = _clients
        .where((c) => c.status == TrainerConnectionStatus.active)
        .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const Key('trainer-clients'),
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          FFPageHeader(
            title: context.tr('clients.title'),
            description: context.tr('clients.body'),
          ),
          if (pending.isNotEmpty) ...[
            FFSectionTitle(context.tr('clients.requests')),
            for (final c in pending)
              FFCard(
                key: Key('client-request-${c.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        FFAvatar(
                          name: c.member?.displayName ?? '?',
                          src: c.member?.photoUrl,
                        ),
                        const SizedBox(width: FFTokens.spacingMd),
                        Expanded(
                          child: Text(
                            c.member?.displayName ?? '',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: FFTokens.spacingSm),
                    Text(
                      '${context.tr('clients.willShare')}: ${sharedSummary(context, c.permissions)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: FFTokens.spacingSm),
                    Row(
                      children: [
                        FilledButton(
                          key: Key('client-accept-${c.id}'),
                          onPressed: _busyId == c.id
                              ? null
                              : () => _decide(c, true),
                          child: Text(context.tr('clients.accept')),
                        ),
                        const SizedBox(width: FFTokens.spacingSm),
                        TextButton(
                          key: Key('client-decline-${c.id}'),
                          onPressed: _busyId == c.id
                              ? null
                              : () => _decide(c, false),
                          child: Text(context.tr('clients.decline')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
          FFSectionTitle(context.tr('clients.connected')),
          if (active.isEmpty)
            FFEmptyState(
              title: context.tr('clients.none'),
              body: context.tr('clients.noneBody'),
            )
          else
            for (final c in active)
              FFActionTile(
                key: Key('client-${c.id}'),
                icon: Icons.person_outline,
                title: c.member?.displayName ?? '',
                subtitle:
                    '${context.tr('share.canSee')}: ${sharedSummary(context, c.permissions)}',
                onTap: () => _openClient(c),
              ),
          Row(
            children: [
              Expanded(child: FFSectionTitle(context.tr('plans.title'))),
              TextButton.icon(
                key: const Key('plan-new'),
                onPressed: () => _editPlan(),
                icon: const Icon(Icons.add, size: 18),
                label: Text(context.tr('plans.new')),
              ),
            ],
          ),
          if (_plans.isEmpty)
            FFEmptyState(
              title: context.tr('plans.none'),
              body: context.tr('plans.noneBody'),
            )
          else
            for (final p in _plans)
              FFActionTile(
                key: Key('plan-${p.id}'),
                icon: Icons.assignment_outlined,
                title: p.name,
                subtitle: [
                  context
                      .tr('workout.exerciseCount')
                      .replaceAll('{n}', '${p.exercises.length}'),
                  if (p.estimatedDuration != null)
                    '${p.estimatedDuration} ${context.tr('activity.min')}',
                ].join(' · '),
                onTap: () => _editPlan(p),
              ),
        ],
      ),
    );
  }
}
