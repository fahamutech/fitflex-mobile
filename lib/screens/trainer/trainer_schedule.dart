import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import '../../shared/widgets/availability_calendar.dart';

const _weekdays = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

/// Hours a trainer can offer: 05:00 … 22:00 (EAT), one-hour sessions.
final editorHours = [
  for (var h = 5; h <= 22; h++) '${h.toString().padLeft(2, '0')}:00',
];

/// Trainer › Sessions: the trainer's own 21-day calendar with who booked
/// each taken slot, and the weekly-hours editor.
class TrainerScheduleCard extends StatefulWidget {
  const TrainerScheduleCard({super.key});

  @override
  State<TrainerScheduleCard> createState() => TrainerScheduleCardState();
}

class TrainerScheduleCardState extends State<TrainerScheduleCard> {
  List<ScheduleDay> _days = [];
  List<Map<String, dynamic>> _availability = [];
  bool _loading = true;
  bool _started = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    refresh();
  }

  Future<void> refresh() async {
    final api = AppScope.of(context).api;
    try {
      final results = await Future.wait([
        api.trainerMySchedule(days: 21),
        api.trainerMe(),
      ]);
      if (!mounted) return;
      setState(() {
        _days = ScheduleDay.listFromResponse(results[0]);
        _availability = ((results[1]['availability'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.tr('owner.errorGeneric');
      });
    }
  }

  Future<void> _editHours() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WeeklyHoursEditorPage(availability: _availability),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('hours.saved'))));
      await refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr('cal.mySchedule'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              key: const Key('trainer-edit-hours'),
              onPressed: _loading ? null : _editHours,
              icon: const Icon(Icons.edit_calendar_outlined, size: 18),
              label: Text(context.tr('hours.edit')),
            ),
          ],
        ),
        const SizedBox(height: FFTokens.spacingSm),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: FFSpinner(size: 28)),
          )
        else if (_error != null)
          FFAlert(message: _error!, tone: FFAlertTone.error)
        else if (_days.every((d) => d.slots.isEmpty))
          FFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('cal.noHours')),
                const SizedBox(height: 8),
                FilledButton(
                  key: const Key('trainer-set-hours'),
                  onPressed: _editHours,
                  child: Text(context.tr('hours.setUp')),
                ),
              ],
            ),
          )
        else
          AvailabilityCalendar(days: _days, showBookings: true),
      ],
    );
  }
}

/// Weekly recurring hours (one-hour slots, 05:00–22:00 EAT). Only plain
/// weekday entries are edited; gym-specific or dated entries set by an admin
/// or owner are kept as they are. Pops `true` after saving.
class WeeklyHoursEditorPage extends StatefulWidget {
  const WeeklyHoursEditorPage({super.key, required this.availability});

  final List<Map<String, dynamic>> availability;

  @override
  State<WeeklyHoursEditorPage> createState() => _WeeklyHoursEditorPageState();
}

class _WeeklyHoursEditorPageState extends State<WeeklyHoursEditorPage> {
  late final Map<String, Set<String>> _hours = {
    for (final d in _weekdays) d: <String>{},
  };
  late final List<Map<String, dynamic>> _kept = [];
  String _day = 'monday';
  bool _busy = false;
  String? _error;

  static String? _weekdayOf(Object? day) {
    final v = day?.toString().trim().toLowerCase() ?? '';
    return _weekdays.where((d) => d == v || d.substring(0, 3) == v).firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    for (final entry in widget.availability) {
      final weekday = _weekdayOf(entry['day']);
      final gymId = entry['gymId']?.toString() ?? '';
      if (weekday == null || gymId.isNotEmpty) {
        _kept.add(entry);
        continue;
      }
      _hours[weekday]!.addAll(
        (entry['slots'] as List? ?? const []).map((s) => s.toString()),
      );
    }
  }

  void _toggle(String slot) => setState(() {
    final set = _hours[_day]!;
    if (!set.remove(slot)) set.add(slot);
  });

  void _preset(Iterable<String> slots) =>
      setState(() => _hours[_day] = slots.toSet());

  void _copyToWeekdays() => setState(() {
    for (final d in _weekdays.take(5)) {
      _hours[d] = {..._hours[_day]!};
    }
  });

  List<Map<String, dynamic>> _payload() => [
    ..._kept,
    for (final d in _weekdays)
      if (_hours[d]!.isNotEmpty)
        {'day': d, 'slots': (_hours[d]!.toList()..sort())},
  ];

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.of(
        context,
      ).api.trainerUpdateProfile({'availability': _payload()});
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _error = context.tr('owner.errorGeneric'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _hours[_day]!;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('hours.title'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingMd),
          child: FilledButton(
            key: const Key('hours-save'),
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.tr('hours.save')),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          Text(
            context.tr('hours.body'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: FFTokens.spacingMd),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _weekdays.map((d) {
              final count = _hours[d]!.length;
              return ChoiceChip(
                key: Key('hours-day-$d'),
                selected: d == _day,
                onSelected: (_) => setState(() => _day = d),
                label: Text(
                  count == 0
                      ? context.tr('cal.day.$d')
                      : '${context.tr('cal.day.$d')} · $count',
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: FFTokens.spacingMd),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                key: const Key('hours-preset-mornings'),
                avatar: const Icon(Icons.wb_twilight, size: 16),
                label: Text(context.tr('hours.mornings')),
                onPressed: () => _preset(['06:00', '07:00', '08:00', '09:00']),
              ),
              ActionChip(
                key: const Key('hours-preset-evenings'),
                avatar: const Icon(Icons.nights_stay_outlined, size: 16),
                label: Text(context.tr('hours.evenings')),
                onPressed: () => _preset(['17:00', '18:00', '19:00', '20:00']),
              ),
              ActionChip(
                key: const Key('hours-preset-off'),
                avatar: const Icon(Icons.block, size: 16),
                label: Text(context.tr('hours.dayOff')),
                onPressed: () => _preset(const []),
              ),
              ActionChip(
                key: const Key('hours-copy-weekdays'),
                avatar: const Icon(Icons.copy_all_outlined, size: 16),
                label: Text(context.tr('hours.copyWeekdays')),
                onPressed: _copyToWeekdays,
              ),
            ],
          ),
          const SizedBox(height: FFTokens.spacingMd),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 360 ? 4 : 3;
              const gap = 8.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: editorHours.map((slot) {
                  final on = selected.contains(slot);
                  return SizedBox(
                    width: width,
                    child: FilterChip(
                      key: Key('hours-slot-$slot'),
                      showCheckmark: false,
                      selected: on,
                      selectedColor: FFTokens.brand500,
                      labelStyle: TextStyle(
                        color: on ? Colors.white : null,
                        fontWeight: FontWeight.w600,
                      ),
                      label: SizedBox(
                        width: double.infinity,
                        child: Text(slot, textAlign: TextAlign.center),
                      ),
                      onSelected: (_) => _toggle(slot),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          if (_kept.isNotEmpty) ...[
            const SizedBox(height: FFTokens.spacingMd),
            FFAlert(
              message: context
                  .tr('hours.keptEntries')
                  .replaceAll('{n}', '${_kept.length}'),
              tone: FFAlertTone.info,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: FFTokens.spacingMd),
            FFAlert(message: _error!, tone: FFAlertTone.error),
          ],
        ],
      ),
    );
  }
}
