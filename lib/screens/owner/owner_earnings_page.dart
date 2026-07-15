import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import 'owner_shell.dart';

class OwnerEarningsPage extends StatefulWidget {
  const OwnerEarningsPage({super.key});

  @override
  State<OwnerEarningsPage> createState() => _OwnerEarningsPageState();
}

class _OwnerEarningsPageState extends State<OwnerEarningsPage> {
  DateTimeRange? _dateRange;
  String _earningsType = 'all';
  String _visitFilter = 'all';

  bool _loadingEarnings = true;
  num _totalPaid = 0;
  num _totalPending = 0;
  String? _loadedForGymId;

  static const _earningsTypes = ['all', 'direct', 'fitflex'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final activeGymId = OwnerDataScope.maybeOf(context)?.activeGymId;
    if (activeGymId != _loadedForGymId) {
      _loadedForGymId = activeGymId;
      _loadEarnings(activeGymId);
    }
  }

  Future<void> _loadEarnings(String? gymId) async {
    setState(() => _loadingEarnings = true);
    try {
      final res = await AppScope.of(context).api.ownerEarnings(gymId: gymId);
      if (!mounted) return;
      setState(() {
        _totalPaid = (res['totalPaid'] as num?) ?? 0;
        _totalPending = (res['totalPending'] as num?) ?? 0;
        _loadingEarnings = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _loadingEarnings = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = OwnerDataScope.maybeOf(context);
    return Scaffold(
      appBar: FFOwnerDashboardBar(
        showBackButton: true,
        selectedGymName:
            data?.activeGymName(
              context.tr('owner.pendingApproval'),
              context.tr('owner.gym'),
            ) ??
            context.tr('owner.earnings'),
        initials: '',
        ownerGyms: data?.ownerGyms ?? const [],
        subtitleLabel: context.tr('owner.earnings'),
        onGymSelected: (gymId) async {
          final shell = context.findAncestorStateOfType<OwnerShellState>();
          await shell?.setActiveGym(gymId);
        },
      ),
      body: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          // Period selector
          InkWell(
            onTap: _pickDateRange,
            borderRadius: BorderRadius.circular(FFTokens.radiusMd),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(FFTokens.radiusMd),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _dateRange == null
                          ? context.tr('owner.allTime')
                          : '${_formatDate(_dateRange!.start)} - ${_formatDate(_dateRange!.end)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  if (_dateRange != null)
                    GestureDetector(
                      onTap: () => setState(() => _dateRange = null),
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Earnings type filter (Direct vs FitFlex Roaming)
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _earningsTypes.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final selected = _earningsType == _earningsTypes[i];
                return GestureDetector(
                  onTap: () =>
                      setState(() => _earningsType = _earningsTypes[i]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surface,
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(FFTokens.radiusXl),
                    ),
                    child: Text(
                      _earningsTypeLabel(context, _earningsTypes[i]),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: selected
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Summary cards
          Row(
            children: [
              Expanded(
                child: _EarningsCard(
                  label: context.tr('owner.earningsTotal'),
                  value: 'TZS 0',
                  icon: Icons.trending_up,
                  color: FFTokens.success600,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _EarningsCard(
                  label: context.tr('owner.earningsPending'),
                  value: 'TZS 0',
                  icon: Icons.hourglass_top,
                  color: FFTokens.warning500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Pending Invoices (expandable)
          FFSectionTitle(context.tr('owner.pendingInvoices')),
          _PendingInvoiceCard(
            month: 'March 2026',
            totalVisits: 45,
            visitFilter: _visitFilter,
            onFilterChanged: (f) => setState(() => _visitFilter = f),
          ),
          const SizedBox(height: 12),
          _PendingInvoiceCard(
            month: 'February 2026',
            totalVisits: 38,
            visitFilter: _visitFilter,
            onFilterChanged: (f) => setState(() => _visitFilter = f),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  String _earningsTypeLabel(BuildContext context, String type) {
    switch (type) {
      case 'direct':
        return context.tr('owner.directEarnings');
      case 'fitflex':
        return context.tr('owner.fitflexEarnings');
      default:
        return context.tr('owner.allEarnings');
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _dateRange,
    );
    if (picked != null) setState(() => _dateRange = picked);
  }
}

class _EarningsCard extends StatelessWidget {
  const _EarningsCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: FFTokens.iconMd),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _PendingInvoiceCard extends StatefulWidget {
  const _PendingInvoiceCard({
    required this.month,
    required this.totalVisits,
    required this.visitFilter,
    required this.onFilterChanged,
  });

  final String month;
  final int totalVisits;
  final String visitFilter;
  final ValueChanged<String> onFilterChanged;

  @override
  State<_PendingInvoiceCard> createState() => _PendingInvoiceCardState();
}

class _PendingInvoiceCardState extends State<_PendingInvoiceCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.month,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 12),
            _DetailRow(
              label: context.tr('owner.totalVisitsInMonth'),
              value: '${widget.totalVisits}',
            ),
            const SizedBox(height: 8),
            // Visit filter chips
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: ['all', 'daily', 'weekly', 'monthly'].map((f) {
                final selected = widget.visitFilter == f;
                return GestureDetector(
                  onTap: () => widget.onFilterChanged(f),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.1)
                          : Theme.of(context).colorScheme.surface,
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                    ),
                    child: Text(
                      _filterLabel(context, f),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            _DetailRow(label: context.tr('owner.numberOfUsers'), value: '12'),
          ],
        ],
      ),
    );
  }

  String _filterLabel(BuildContext context, String f) {
    switch (f) {
      case 'daily':
        return context.tr('owner.filterDaily');
      case 'weekly':
        return context.tr('owner.filterWeekly');
      case 'monthly':
        return context.tr('owner.filterMonthly');
      default:
        return context.tr('owner.filterAll');
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
