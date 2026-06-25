import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'owner_shell.dart';
import 'widgets/add_member_sheet.dart';

/// Owner dashboard home tab — shows stats, quick actions, and gym summary.
class OwnerHomeTab extends StatefulWidget {
  const OwnerHomeTab({super.key});

  @override
  State<OwnerHomeTab> createState() => _OwnerHomeTabState();
}

class _OwnerHomeTabState extends State<OwnerHomeTab> {
  Future<void> _pickStatsRange() async {
    final data = OwnerDataScope.of(context);
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: (data.statsFrom != null && data.statsTo != null)
          ? DateTimeRange(start: data.statsFrom!, end: data.statsTo!)
          : null,
    );
    if (picked != null && mounted) {
      data.update((d) {
        d.statsFrom = DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        );
        d.statsTo = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
      });
      final shell = context.findAncestorStateOfType<OwnerShellState>();
      await shell?.refreshDashboard();
      if (mounted) setState(() {});
    }
  }

  Future<void> _showAddMemberDialog() async {
    final data = OwnerDataScope.of(context);
    final ownerGymIds = data.ownerGyms.map((g) => g['id'].toString()).toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AddMemberSheet(
        ownerGymIds: ownerGymIds,
        onSaved: (payload) async {
          if (!mounted) return;
          final api = AppScope.of(context).api;
          try {
            await api.ownerCreateMember(payload);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.tr('owner.memberAdded'))),
            );
            final shell = context.findAncestorStateOfType<OwnerShellState>();
            await shell?.refreshAll();
          } on ApiException catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Error ${e.status}')));
          }
        },
      ),
    );
  }

  String _dateOnly(DateTime value) => value.toIso8601String().split('T').first;

  @override
  Widget build(BuildContext context) {
    final data = OwnerDataScope.of(context);
    final dashboard = data.dashboard;
    final ownerGymList = data.ownerGyms;

    final todayCount = (dashboard?['todayCount'] as num?)?.toInt() ?? 0;
    final monthVisits = (dashboard?['monthVisits'] as num?)?.toInt() ?? 0;
    final periodVisits = (dashboard?['periodVisits'] as num?)?.toInt() ?? 0;
    final periodMembers = (dashboard?['periodMembers'] as num?)?.toInt() ?? 0;
    final directVisits = (dashboard?['directVisits'] as num?)?.toInt() ?? 0;
    final directMembers = (dashboard?['directMembers'] as num?)?.toInt() ?? 0;
    final fitflexVisits = (dashboard?['fitflexVisits'] as num?)?.toInt() ?? 0;
    final fitflexMembers = (dashboard?['fitflexMembers'] as num?)?.toInt() ?? 0;
    final overall = dashboard?['overall'] as Map<String, dynamic>?;
    final dashGym = dashboard?['gym'] as Map<String, dynamic>?;
    final primaryGym = ownerGymList.isNotEmpty ? ownerGymList.first : dashGym;

    final rangeLabel = (data.statsFrom != null && data.statsTo != null)
        ? '${_dateOnly(data.statsFrom!)} → ${_dateOnly(data.statsTo!)}'
        : context.tr('owner.thisMonth');

    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Text(
          context.tr('owner.dashboardBody'),
          style: TextStyle(
            color: Theme.of(context).textTheme.bodySmall?.color,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        // Primary gym card
        FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _section(context.tr('owner.gymProfile')),
              Text(
                primaryGym?['name']?.toString() ??
                    context.tr('owner.pendingApproval'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                primaryGym?['location']?.toString() ??
                    context.tr('owner.gymPending'),
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Period settings
        FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _section(context.tr('owner.periodSettings')),
              if (ownerGymList.length > 1) ...[
                DropdownButtonFormField<String>(
                  initialValue: data.dashboardGymId ?? '',
                  decoration: InputDecoration(
                    labelText: context.tr('owner.gymProfile'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(context.tr('owner.allGyms')),
                    ),
                    ...ownerGymList.map(
                      (g) => DropdownMenuItem(
                        value: g['id']?.toString() ?? '',
                        child: Text(g['name']?.toString() ?? ''),
                      ),
                    ),
                  ],
                  onChanged: (value) async {
                    data.update(
                      (d) => d.dashboardGymId = value == null || value.isEmpty
                          ? null
                          : value,
                    );
                    final shell = context
                        .findAncestorStateOfType<OwnerShellState>();
                    await shell?.refreshDashboard();
                    if (mounted) setState(() {});
                  },
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickStatsRange,
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text(rangeLabel, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  if (data.statsFrom != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: context.tr('owner.clearFilter'),
                      icon: const Icon(Icons.clear),
                      onPressed: () async {
                        data.update((d) {
                          d.statsFrom = null;
                          d.statsTo = null;
                        });
                        final shell = context
                            .findAncestorStateOfType<OwnerShellState>();
                        await shell?.refreshDashboard();
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _memberTypeChip(data, 'all', context.tr('owner.allMembers')),
                  _memberTypeChip(
                    data,
                    'direct',
                    context.tr('owner.directMembers'),
                  ),
                  _memberTypeChip(
                    data,
                    'fitflex',
                    context.tr('owner.fitflexMembers'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Stats rows
        Row(
          children: [
            Expanded(
              child: FFMetricCard(
                value: '$todayCount',
                label: context.tr('owner.todayCheckins'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FFMetricCard(
                value: '$monthVisits',
                label: context.tr('owner.monthCheckins'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FFMetricCard(
                value: primaryGym?['tier']?.toString() ?? '-',
                label: context.tr('owner.tier'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FFMetricCard(
                value: '$periodVisits',
                label: context.tr('owner.periodVisits'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FFMetricCard(
                value: '$periodMembers',
                label: context.tr('owner.periodMembers'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FFMetricCard(
                value: '${overall?['gymCount'] ?? ownerGymList.length}',
                label: context.tr('owner.gyms'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FFMetricCard(
                value: '$directMembers',
                label: '${context.tr('owner.directMembers')} ($directVisits)',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FFMetricCard(
                value: '$fitflexMembers',
                label: '${context.tr('owner.fitflexMembers')} ($fitflexVisits)',
              ),
            ),
          ],
        ),
        _section(context.tr('owner.actions')),
        FFActionTile(
          icon: Icons.qr_code_scanner,
          title: context.tr('owner.scan'),
          onTap: () => context.push('/owner/scan'),
        ),
        FFActionTile(
          icon: Icons.people,
          title: context.tr('owner.members'),
          subtitle: '${context.tr('owner.checkins')}: $periodVisits',
          onTap: () {
            final targetGym = primaryGym;
            if (targetGym != null) {
              context.push('/owner/gyms/${targetGym['id']}/checkins');
            }
          },
        ),
        FFActionTile(
          icon: Icons.person_add,
          title: context.tr('owner.addMember'),
          onTap: _showAddMemberDialog,
        ),
        FFActionTile(
          icon: Icons.sports_gymnastics,
          title: context.tr('owner.trainers'),
          subtitle: '${data.ownerTrainers.length}',
          onTap: () => context.go('/owner/trainers'),
        ),
        FFActionTile(
          icon: Icons.payments,
          title: context.tr('owner.earnings'),
          onTap: () => context.push('/owner/earnings'),
        ),
        // My Gyms section
        _section(context.tr('owner.myGyms')),
        if (ownerGymList.isEmpty)
          FFEmptyState(title: context.tr('member.noData'))
        else
          ...ownerGymList
              .take(2)
              .map(
                (gym) => FFActionTile(
                  icon: Icons.fitness_center,
                  title: gym['name']?.toString() ?? '',
                  subtitle: gym['location']?.toString(),
                  onTap: () =>
                      context.push('/owner/gyms/${gym['id']}/checkins'),
                ),
              ),
        if (ownerGymList.length > 2)
          OutlinedButton.icon(
            onPressed: () => context.go('/owner/gyms'),
            icon: const Icon(Icons.fitness_center),
            label: Text(context.tr('owner.manageGyms')),
          ),
      ],
    );
  }

  Widget _memberTypeChip(OwnerData data, String value, String label) {
    final selected = data.dashboardMemberType == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) async {
        data.update((d) => d.dashboardMemberType = value);
        final shell = context.findAncestorStateOfType<OwnerShellState>();
        await shell?.refreshDashboard();
        if (mounted) setState(() {});
      },
    );
  }

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    ),
  );
}
