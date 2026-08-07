import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import 'owner_shell.dart';
import 'widgets/invoice_utils.dart';

class OwnerEarningsPage extends StatefulWidget {
  const OwnerEarningsPage({super.key});

  @override
  State<OwnerEarningsPage> createState() => _OwnerEarningsPageState();
}

class _OwnerEarningsPageState extends State<OwnerEarningsPage> {
  DateTimeRange? _dateRange;
  String _earningsType = 'all';
  bool _loadingEarnings = true;
  num _totalPaid = 0;
  num _totalPending = 0;
  List<OwnerInvoice> _invoices = const [];
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
    final api = AppScope.of(context).api;
    try {
      final res = await api.ownerEarnings(gymId: gymId);
      if (!mounted) return;
      setState(() {
        _totalPaid = (res['totalPaid'] as num?) ?? 0;
        _totalPending = (res['totalPending'] as num?) ?? 0;
      });
    } on ApiException {
      // keep previous totals
    }
    if (!mounted) return;
    try {
      final rows = await api.ownerInvoices();
      if (!mounted) return;
      final parsed = rows
          .whereType<Map<String, dynamic>>()
          .map(OwnerInvoice.fromJson)
          .where((i) => gymId == null || gymId.isEmpty || i.gymId == gymId)
          .toList();
      setState(() {
        // B1: month summaries run from the current month backwards.
        _invoices = sortInvoicesCurrentMonthBackwards(parsed);
        _loadingEarnings = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _loadingEarnings = false);
    }
  }

  List<OwnerInvoice> get _visibleInvoices {
    var rows = _invoices.where((i) => !i.isPaid).toList();
    final range = _dateRange;
    if (range != null) {
      rows = rows.where((i) {
        final d = i.monthAnchor;
        if (d == null) return false;
        return !d.isBefore(range.start) &&
            !d.isAfter(range.end.add(const Duration(days: 1)));
      }).toList();
    }
    return rows;
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

          // Summary cards — real earnings totals (B1/B10)
          Row(
            children: [
              Expanded(
                child: _EarningsCard(
                  key: const Key('earnings-total-paid'),
                  label: context.tr('owner.earningsTotal'),
                  value: _loadingEarnings ? '…' : formatCurrency(_totalPaid),
                  icon: Icons.trending_up,
                  color: FFTokens.success600,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _EarningsCard(
                  key: const Key('earnings-total-pending'),
                  label: context.tr('owner.earningsPending'),
                  value: _loadingEarnings ? '…' : formatCurrency(_totalPending),
                  icon: Icons.hourglass_top,
                  color: FFTokens.warning500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Pending Invoices — real data, current month backwards (B1)
          FFSectionTitle(context.tr('owner.pendingInvoices')),
          if (_loadingEarnings)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(FFTokens.spacingLg),
                child: FFSpinner(),
              ),
            )
          else if (_visibleInvoices.isEmpty)
            FFEmptyState(title: context.tr('owner.noInvoices'))
          else
            ..._visibleInvoices.map(
              (inv) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _InvoiceCard(invoice: inv),
              ),
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
    super.key,
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

class _InvoiceCard extends StatefulWidget {
  const _InvoiceCard({required this.invoice});

  final OwnerInvoice invoice;

  @override
  State<_InvoiceCard> createState() => _InvoiceCardState();
}

class _InvoiceCardState extends State<_InvoiceCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
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
                    inv.monthLabel,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                FFBadge(
                  label: inv.isPaid
                      ? context.tr('owner.invoicePaid')
                      : context.tr('owner.invoiceUnpaid'),
                  tone: inv.isPaid ? FFBadgeTone.success : FFBadgeTone.warning,
                ),
                const SizedBox(width: 6),
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
              label: context.tr('owner.invoiceAmount'),
              value: formatCurrency(inv.amount),
            ),
            if (inv.gymName != null) ...[
              const SizedBox(height: 8),
              _DetailRow(label: context.tr('owner.gym'), value: inv.gymName!),
            ],
          ],
        ],
      ),
    );
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
