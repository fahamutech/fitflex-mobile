import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';

/// Owner — view check-ins for a specific gym (standalone pushed page).
class OwnerCheckinsPage extends StatefulWidget {
  const OwnerCheckinsPage({super.key, required this.gymId});

  final String gymId;

  @override
  State<OwnerCheckinsPage> createState() => _OwnerCheckinsPageState();
}

class _OwnerCheckinsPageState extends State<OwnerCheckinsPage> {
  DateTime? _statsFrom;
  DateTime? _statsTo;

  String _dateOnly(DateTime value) => value.toIso8601String().split('T').first;

  Future<void> _pickStatsRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: (_statsFrom != null && _statsTo != null)
          ? DateTimeRange(start: _statsFrom!, end: _statsTo!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _statsFrom = DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        );
        _statsTo = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rangeLabel = (_statsFrom != null && _statsTo != null)
        ? '${_dateOnly(_statsFrom!)} → ${_dateOnly(_statsTo!)}'
        : context.tr('owner.allTime');

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('owner.gymCheckins'))),
      body: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickStatsRange,
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text(rangeLabel, overflow: TextOverflow.ellipsis),
                ),
              ),
              if (_statsFrom != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: context.tr('owner.clearFilter'),
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() {
                    _statsFrom = null;
                    _statsTo = null;
                  }),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<dynamic>>(
            future: AppScope.of(context).api.ownerGymCheckins(widget.gymId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              var items = (snap.data ?? []).cast<Map<String, dynamic>>();
              if (_statsFrom != null && _statsTo != null) {
                items = items.where((c) {
                  final ts = DateTime.tryParse(
                    c['timestamp']?.toString() ?? '',
                  );
                  if (ts == null) return false;
                  return !ts.isBefore(_statsFrom!) && !ts.isAfter(_statsTo!);
                }).toList();
              }
              if (items.isEmpty) {
                return FFCard(
                  child: Text(
                    context.tr('owner.noCheckins'),
                    style: const TextStyle(color: FFTokens.textMuted),
                  ),
                );
              }
              return Column(
                children: [
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FFMetricCard(
                          label: context.tr('owner.checkins'),
                          value: '${items.length}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...items.take(50).map((c) {
                    final member = c['member'] as Map?;
                    final memberName =
                        c['memberPublicId']?.toString() ??
                        member?['displayName']?.toString() ??
                        member?['email']?.toString() ??
                        c['memberName']?.toString() ??
                        c['memberId']?.toString() ??
                        '';
                    return FFActionTile(
                      icon: Icons.check_circle_outline,
                      title: memberName,
                      subtitle: c['timestamp']?.toString() ?? '',
                      onTap: () {},
                    );
                  }),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
