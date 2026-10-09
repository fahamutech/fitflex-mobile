import 'package:flutter/material.dart';
import '../../shared/api_error_message.dart';

import '../../app_scope.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';

class OwnerDashboardPage extends StatefulWidget {
  const OwnerDashboardPage({super.key});

  @override
  State<OwnerDashboardPage> createState() => _OwnerDashboardPageState();
}

class _OwnerDashboardPageState extends State<OwnerDashboardPage> {
  Map<String, dynamic>? _dashboard;
  bool _loading = true;
  String? _error;
  String? _selectedGymId;
  String _memberType = 'all';

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = AppScope.of(context).api;
      final result = await api.operatorDashboard(
        gymId: _selectedGymId,
        memberType: _memberType,
      );
      if (!mounted) return;
      setState(() {
        _dashboard = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(FFLocaleScope.of(context), e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('owner.dashboard')),
        actions: [
          IconButton(
            tooltip: context.tr('a11y.refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboard,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: FFSpinner())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _loadDashboard,
                    child: Text(context.tr('home.retry')),
                  ),
                ],
              ),
            )
          : _dashboard != null
          ? _buildDashboard()
          : const Center(child: Text('No data available')),
    );
  }

  Widget _buildDashboard() {
    final data = _dashboard!;
    final gym = data['gym'] as Map<String, dynamic>?;
    final gyms = data['gyms'] as List<dynamic>? ?? [];
    final overall = data['overall'] as Map<String, dynamic>? ?? {};

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          // Welcome header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(FFTokens.radiusXl),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gym?['name']?.toString() ?? context.tr('owner.dashboard'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr('owner.dashboardBody'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Gym selector
          if (gyms.length > 1) ...[
            FFDropdownField<String>(
              value: _selectedGymId ?? gym?['id']?.toString(),
              label: context.tr('ownerScan.gym'),
              items: gyms.map((g) {
                final gymData = g as Map<String, dynamic>;
                return DropdownMenuItem(
                  value: gymData['id']?.toString(),
                  child: Text(gymData['name']?.toString() ?? ''),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedGymId = value);
                _loadDashboard();
              },
            ),
            const SizedBox(height: 16),
          ],

          // Member type filter
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'all',
                label: Text(context.tr('owner.memberTypeAll')),
              ),
              ButtonSegment(
                value: 'direct',
                label: Text(context.tr('owner.memberTypeDirect')),
              ),
              ButtonSegment(
                value: 'fitflex',
                label: Text(context.tr('owner.memberTypeFitflex')),
              ),
            ],
            selected: {_memberType},
            onSelectionChanged: (Set<String> selected) {
              setState(() => _memberType = selected.first);
              _loadDashboard();
            },
          ),
          const SizedBox(height: 20),

          // Today / This Month cards
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: context.tr('owner.todayVisits'),
                  value: (data['todayCount'] as num?)?.toInt() ?? 0,
                  icon: Icons.today,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  label: context.tr('owner.monthVisits'),
                  value: (data['monthVisits'] as num?)?.toInt() ?? 0,
                  icon: Icons.calendar_month,
                  color: FFTokens.success600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: context.tr('owner.periodVisits'),
                  value: (data['periodVisits'] as num?)?.toInt() ?? 0,
                  icon: Icons.date_range,
                  color: FFTokens.warning500,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  label: context.tr('owner.periodMembers'),
                  value: (data['periodMembers'] as num?)?.toInt() ?? 0,
                  icon: Icons.people,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Overall performance section
          FFSectionTitle(context.tr('owner.overallPerformance')),
          FFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OverallStat(
                  label: context.tr('owner.totalGyms'),
                  value: (overall['gymCount'] as num?)?.toInt() ?? 0,
                  icon: Icons.business,
                ),
                const Divider(height: 1),
                _OverallStat(
                  label: context.tr('owner.totalVisits'),
                  value: (overall['totalVisits'] as num?)?.toInt() ?? 0,
                  icon: Icons.bar_chart,
                ),
                const Divider(height: 1),
                _OverallStat(
                  label: context.tr('owner.uniqueMembers'),
                  value: (overall['uniqueMembers'] as num?)?.toInt() ?? 0,
                  icon: Icons.person,
                ),
                const Divider(height: 1),
                _OverallStat(
                  label: context.tr('owner.directVisits'),
                  value: (overall['directVisits'] as num?)?.toInt() ?? 0,
                  icon: Icons.person_pin,
                ),
                const Divider(height: 1),
                _OverallStat(
                  label: context.tr('owner.fitflexVisits'),
                  value: (overall['fitflexVisits'] as num?)?.toInt() ?? 0,
                  icon: Icons.card_membership,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Owner tools
          FFSectionTitle(context.tr('owner.actions')),
          FFActionTile(
            icon: Icons.qr_code_scanner,
            title: context.tr('owner.scan'),
            onTap: () => Navigator.pushNamed(context, '/owner/scan'),
          ),
          FFActionTile(
            icon: Icons.location_on_outlined,
            title: context.tr('owner.editLocation'),
            onTap: () => _openEditGymLocation(),
          ),
          FFActionTile(
            icon: Icons.trending_up,
            title: context.tr('owner.earnings'),
            onTap: () => Navigator.pushNamed(context, '/owner/earnings'),
          ),
          FFActionTile(
            icon: Icons.account_balance_outlined,
            title: context.tr('owner.bankDetails'),
            onTap: () => _openBankDetails(),
          ),
          const SizedBox(height: 20),

          // Gym summaries
          FFSectionTitle(context.tr('owner.gymBreakdown')),
          for (final g in gyms) _GymSummaryCard(gym: g as Map<String, dynamic>),
        ],
      ),
    );
  }

  void _openEditGymLocation() {
    final locationCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('owner.editLocation')),
        content: TextField(
          controller: locationCtrl,
          decoration: InputDecoration(
            labelText: context.tr('ownerReg.gymLocation'),
            hintText: 'e.g. Masaki, Dar es Salaam',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('member.cancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.tr('owner.gymUpdated'))),
              );
            },
            child: Text(context.tr('member.save')),
          ),
        ],
      ),
    );
  }

  void _openBankDetails() {
    final bankNameCtrl = TextEditingController();
    final branchCtrl = TextEditingController();
    final accountCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('owner.bankDetails')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: bankNameCtrl,
                decoration: InputDecoration(
                  labelText: context.tr('owner.bankName'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: branchCtrl,
                decoration: InputDecoration(
                  labelText: context.tr('owner.bankBranch'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: accountCtrl,
                decoration: InputDecoration(
                  labelText: context.tr('owner.accountNumber'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('member.cancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.tr('owner.bankUpdated'))),
              );
            },
            child: Text(context.tr('member.save')),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        boxShadow: FFTokens.shadowSm,
      ),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(FFTokens.radiusMd),
            ),
            child: Icon(icon, color: color, size: FFTokens.iconMd),
          ),
          const SizedBox(height: 10),
          Text(
            value.toString(),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _OverallStat extends StatelessWidget {
  const _OverallStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: FFTokens.iconMd,
          ),
          const SizedBox(width: FFTokens.spacingSm),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Text(value.toString(), style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _GymSummaryCard extends StatelessWidget {
  const _GymSummaryCard({required this.gym});

  final Map<String, dynamic> gym;

  @override
  Widget build(BuildContext context) {
    return FFCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            gym['gymName']?.toString() ?? gym['name']?.toString() ?? 'Unknown',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _GymStat(
                  label: 'Total Visits',
                  value: (gym['totalVisits'] as num?)?.toInt() ?? 0,
                ),
              ),
              Expanded(
                child: _GymStat(
                  label: 'Unique Members',
                  value: (gym['uniqueMembers'] as num?)?.toInt() ?? 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _GymStat(
                  label: 'Direct Visits',
                  value: (gym['directVisits'] as num?)?.toInt() ?? 0,
                ),
              ),
              Expanded(
                child: _GymStat(
                  label: 'FitFlex Visits',
                  value: (gym['fitflexVisits'] as num?)?.toInt() ?? 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GymStat extends StatelessWidget {
  const _GymStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
