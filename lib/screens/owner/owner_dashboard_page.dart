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
          // Welcome header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [FFTokens.brand700, FFTokens.brand600],
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr('owner.dashboardBody'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Gym selector
          if (gyms.length > 1) ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedGymId ?? gym?['id']?.toString(),
              decoration: InputDecoration(
                labelText: context.tr('ownerScan.gym'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
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

          // Today / This Month cards
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: context.tr('owner.todayVisits'),
                  value: (data['todayCount'] as num?)?.toInt() ?? 0,
                  icon: Icons.today,
                  color: FFTokens.brand600,
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
                  color: FFTokens.brand700,
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
          _SectionTitle(context.tr('owner.actions')),
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
          _SectionTitle(context.tr('owner.gymBreakdown')),
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
    this.color = FFTokens.brand700,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FFTokens.surface,
        border: Border.all(color: FFTokens.border),
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
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 26,
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
