import 'package:flutter/material.dart';

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
        _error = e.toString();
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
                    style: const TextStyle(color: FFTokens.error500),
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
          // Gym selector
          if (gyms.length > 1) ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedGymId ?? gym?['id']?.toString(),
              decoration: InputDecoration(
                labelText: context.tr('ownerScan.gym'),
                border: const OutlineInputBorder(),
              ),
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

          // Today / This Month cards with labels
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: context.tr('owner.todayVisits'),
                  value: (data['todayCount'] as num?)?.toInt() ?? 0,
                  icon: Icons.today,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  label: context.tr('owner.monthVisits'),
                  value: (data['monthVisits'] as num?)?.toInt() ?? 0,
                  icon: Icons.calendar_month,
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
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  label: context.tr('owner.periodMembers'),
                  value: (data['periodMembers'] as num?)?.toInt() ?? 0,
                  icon: Icons.people,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Overall performance section
          _SectionTitle(context.tr('owner.overallPerformance')),
          FFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OverallStat(
                  label: context.tr('owner.totalGyms'),
                  value: (overall['gymCount'] as num?)?.toInt() ?? 0,
                  icon: Icons.business,
                ),
                const Divider(),
                _OverallStat(
                  label: context.tr('owner.totalVisits'),
                  value: (overall['totalVisits'] as num?)?.toInt() ?? 0,
                  icon: Icons.bar_chart,
                ),
                const Divider(),
                _OverallStat(
                  label: context.tr('owner.uniqueMembers'),
                  value: (overall['uniqueMembers'] as num?)?.toInt() ?? 0,
                  icon: Icons.person,
                ),
                const Divider(),
                _OverallStat(
                  label: context.tr('owner.directVisits'),
                  value: (overall['directVisits'] as num?)?.toInt() ?? 0,
                  icon: Icons.person_pin,
                ),
                const Divider(),
                _OverallStat(
                  label: context.tr('owner.fitflexVisits'),
                  value: (overall['fitflexVisits'] as num?)?.toInt() ?? 0,
                  icon: Icons.card_membership,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Gym summaries
          _SectionTitle(context.tr('owner.gymBreakdown')),
          for (final g in gyms) _GymSummaryCard(gym: g as Map<String, dynamic>),
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
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return FFCard(
      child: Column(
        children: [
          Icon(icon, color: FFTokens.brand700, size: 24),
          const SizedBox(height: 8),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: FFTokens.fgPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: FFTokens.fgSecondary),
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
          Icon(icon, color: FFTokens.brand600, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: FFTokens.fgSecondary),
            ),
          ),
          Text(
            value.toString(),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: FFTokens.fgPrimary,
            ),
          ),
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
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: FFTokens.fgPrimary,
            ),
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
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: FFTokens.fgPrimary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: FFTokens.fgQuaternary),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: FFTokens.fgPrimary,
        ),
      ),
    );
  }
}
