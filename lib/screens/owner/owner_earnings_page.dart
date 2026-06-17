import 'package:flutter/material.dart';

import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';

class OwnerEarningsPage extends StatefulWidget {
  const OwnerEarningsPage({super.key});

  @override
  State<OwnerEarningsPage> createState() => _OwnerEarningsPageState();
}

class _OwnerEarningsPageState extends State<OwnerEarningsPage> {
  DateTimeRange? _dateRange;
  String _earningsType = 'all';
  String _visitFilter = 'all';

  static const _earningsTypes = ['all', 'direct', 'fitflex'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('owner.earnings'))),
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
                border: Border.all(color: FFTokens.borderSecondary),
                borderRadius: BorderRadius.circular(FFTokens.radiusMd),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    size: 18,
                    color: FFTokens.brand600,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _dateRange == null
                          ? context.tr('owner.allTime')
                          : '${_formatDate(_dateRange!.start)} - ${_formatDate(_dateRange!.end)}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: FFTokens.fgSecondary,
                      ),
                    ),
                  ),
                  if (_dateRange != null)
                    GestureDetector(
                      onTap: () => setState(() => _dateRange = null),
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: FFTokens.fgTertiary,
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
                          ? FFTokens.brand700
                          : FFTokens.bgSecondary,
                      border: Border.all(
                        color: selected
                            ? FFTokens.brand700
                            : FFTokens.borderSecondary,
                      ),
                      borderRadius: BorderRadius.circular(FFTokens.radiusXl),
                    ),
                    child: Text(
                      _earningsTypeLabel(context, _earningsTypes[i]),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: selected ? Colors.white : FFTokens.fgSecondary,
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
          _SectionTitle(context.tr('owner.pendingInvoices')),
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
        color: FFTokens.surface,
        border: Border.all(color: FFTokens.border),
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: FFTokens.fgPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: FFTokens.fgSecondary),
          ),
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
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: FFTokens.fgPrimary,
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: FFTokens.fgTertiary,
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
                          ? FFTokens.brand100
                          : FFTokens.bgSecondary,
                      border: Border.all(
                        color: selected
                            ? FFTokens.brand500
                            : FFTokens.borderSecondary,
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
                            ? FFTokens.brand700
                            : FFTokens.fgSecondary,
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
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: FFTokens.fgSecondary),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: FFTokens.fgPrimary,
          ),
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
      padding: const EdgeInsets.only(bottom: 10),
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
