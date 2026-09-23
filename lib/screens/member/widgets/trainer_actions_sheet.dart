import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';

/// A4 — next calendar date (YYYY-MM-DD) for an availability day label.
/// Supports weekday names ('monday'...) and legacy exact dates ('2026-05-05').
String? nextDateForAvailabilityDay(String day, {DateTime? from}) {
  final base = from ?? DateTime.now();
  const weekdays = {
    'monday': DateTime.monday,
    'tuesday': DateTime.tuesday,
    'wednesday': DateTime.wednesday,
    'thursday': DateTime.thursday,
    'friday': DateTime.friday,
    'saturday': DateTime.saturday,
    'sunday': DateTime.sunday,
  };
  final normalized = day.trim().toLowerCase();
  final weekday = weekdays[normalized];
  if (weekday != null) {
    var delta = (weekday - base.weekday) % 7;
    if (delta < 0) delta += 7;
    final target = base.add(Duration(days: delta));
    return _dateOnly(target);
  }
  final parsed = DateTime.tryParse(day);
  return parsed == null ? null : _dateOnly(parsed);
}

String _dateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A4 — bottom sheet to book a trainer session on an AVAILABLE slot only.
Future<bool?> showTrainerBookingSheet(
  BuildContext context,
  TrainerProfile trainer,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => TrainerBookingSheet(trainer: trainer),
  );
}

class TrainerBookingSheet extends StatefulWidget {
  const TrainerBookingSheet({super.key, required this.trainer});

  final TrainerProfile trainer;

  @override
  State<TrainerBookingSheet> createState() => _TrainerBookingSheetState();
}

/// One selectable slot: availability entry + time, resolved to a date.
class _PickedSlot {
  _PickedSlot(this.entry, this.slot, this.date);
  final TrainerAvailability entry;
  final String slot;
  final String date;

  String get key => '$date|$slot';
  Map<String, String> toJson() => {'date': date, 'slot': slot};
}

class _TrainerBookingSheetState extends State<TrainerBookingSheet> {
  static const _maxSlots = 12;

  // UAT #58: members pick several slots, see a priced summary, then confirm.
  final Map<String, _PickedSlot> _picked = {};
  String? _pickedGymId;
  Map<String, dynamic>? _summary; // non-null = summary step
  bool _busy = false;
  String? _error;

  String? _gymFor(TrainerAvailability entry) {
    final entryGym = entry.gymId;
    if (entryGym != null && entryGym.isNotEmpty) return entryGym;
    return widget.trainer.gymIds.firstOrNull ??
        widget.trainer.gyms.firstOrNull?.id;
  }

  List<Map<String, String>> get _slotJson {
    final list = _picked.values.toList()
      ..sort((a, b) => '${a.date} ${a.slot}'.compareTo('${b.date} ${b.slot}'));
    return list.map((p) => p.toJson()).toList();
  }

  void _toggle(TrainerAvailability entry, String slot) {
    final date = nextDateForAvailabilityDay(entry.day);
    final gymId = _gymFor(entry);
    if (date == null || gymId == null) return;
    final pick = _PickedSlot(entry, slot, date);
    setState(() {
      _error = null;
      // One booking is at one gym: picking a slot elsewhere starts over.
      if (_pickedGymId != null && _pickedGymId != gymId) _picked.clear();
      _pickedGymId = gymId;
      if (_picked.remove(pick.key) == null) {
        if (_picked.length >= _maxSlots) {
          _error = context.tr('member.tooManySlots');
          return;
        }
        _picked[pick.key] = pick;
      }
      if (_picked.isEmpty) _pickedGymId = null;
    });
  }

  String _errorText(Object e) {
    final code = (e is ApiException && e.body is Map)
        ? (e.body as Map)['error']?.toString()
        : null;
    return switch (code) {
      'slot_already_booked' => context.tr('member.slotAlreadyBooked'),
      'slot_not_available' => context.tr('member.slotNotAvailable'),
      'too_many_slots' => context.tr('member.tooManySlots'),
      'trainer_rate_not_set' => context.tr('member.trainerRateNotSet'),
      _ => context.tr('member.bookingFailed'),
    };
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _quote() => _run(() async {
    final res = await AppScope.of(context).api.quoteTrainerBooking(
      trainerId: widget.trainer.id,
      gymId: _pickedGymId!,
      slots: _slotJson,
    );
    if (mounted) {
      setState(() => _summary = res['summary'] as Map<String, dynamic>?);
    }
  });

  Future<void> _confirm() => _run(() async {
    await AppScope.of(context).api.bookTrainer(
      trainerId: widget.trainer.id,
      gymId: _pickedGymId!,
      slots: _slotJson,
    );
    if (mounted) Navigator.pop(context, true);
  });

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: FFTokens.spacingLg,
          right: FFTokens.spacingLg,
          bottom: MediaQuery.of(context).viewInsets.bottom + FFTokens.spacingLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr(
                summary == null
                    ? 'member.bookSession'
                    : 'member.bookingSummary',
              ),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              widget.trainer.displayName,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('trainer-book-close'),
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: Text(context.tr('member.close')),
              ),
            ),
            const SizedBox(height: 14),
            if (summary != null) ..._summaryStep(summary) else ..._pickStep(),
          ],
        ),
      ),
    );
  }

  List<Widget> _pickStep() {
    final availability = widget.trainer.availability;
    if (availability.isEmpty) {
      return [FFEmptyState(title: context.tr('member.noAvailability'))];
    }
    final count = _picked.length;
    return [
      Text(
        context.tr('member.selectSlots'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      // A4/C1: members may only pick from the trainer's open slots.
      Flexible(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: availability.map((a) {
              final date = nextDateForAvailabilityDay(a.day);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          date == null ? a.dayLabel : '${a.dayLabel} · $date',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (a.gymName != null) ...[
                          const SizedBox(width: 8),
                          FFBadge(label: a.gymName!, tone: FFBadgeTone.brand),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: a.slots.map((slot) {
                        final selected =
                            _picked.containsKey('$date|$slot') &&
                            _pickedGymId == _gymFor(a);
                        return FilterChip(
                          key: Key('slot-${a.day}-$slot'),
                          label: Text(slot),
                          selected: selected,
                          onSelected: _busy ? null : (_) => _toggle(a, slot),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 6),
        FFAlert(message: _error!, tone: FFAlertTone.error),
      ],
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const Key('trainer-book-slots'),
          onPressed: count == 0 || _busy ? null : _quote,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  count == 0
                      ? context.tr('member.bookSession')
                      : context
                            .tr('member.bookSlots')
                            .replaceAll('{n}', '$count'),
                ),
        ),
      ),
    ];
  }

  List<Widget> _summaryStep(Map<String, dynamic> summary) {
    final currency = summary['currency']?.toString() ?? 'TZS';
    num n(String k) => (summary[k] as num?) ?? 0;
    final slots = (summary['slots'] as List? ?? const [])
        .whereType<Map>()
        .map((s) => '${s['date']}  ${s['slot']}')
        .toList();
    final textTheme = Theme.of(context).textTheme;
    Widget row(String label, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: strong ? textTheme.titleSmall : textTheme.bodyMedium,
            ),
          ),
          Text(
            value,
            style: strong ? textTheme.titleSmall : textTheme.bodyMedium,
          ),
        ],
      ),
    );
    return [
      ...slots.map(
        (s) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              const Icon(Icons.event_available, size: 16),
              const SizedBox(width: 8),
              Text(s, key: Key('summary-slot-$s')),
            ],
          ),
        ),
      ),
      const Divider(height: 20),
      row(
        context.tr('member.pricePerSession'),
        formatCurrency(n('pricePerSession'), currency: currency),
      ),
      row(
        context.tr('member.subtotal'),
        formatCurrency(n('subtotal'), currency: currency),
      ),
      if (n('discount') > 0)
        row(
          '${context.tr('member.passDiscount')} (${n('discountPct')}%)',
          '− ${formatCurrency(n('discount'), currency: currency)}',
        ),
      row(
        context.tr('member.total'),
        formatCurrency(n('total'), currency: currency),
        strong: true,
      ),
      const SizedBox(height: 8),
      Text(context.tr('member.bookingPaymentNote'), style: textTheme.bodySmall),
      if (_error != null) ...[
        const SizedBox(height: 8),
        FFAlert(message: _error!, tone: FFAlertTone.error),
      ],
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('trainer-book-back'),
              onPressed: _busy ? null : () => setState(() => _summary = null),
              child: Text(context.tr('member.back')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              key: const Key('trainer-book-confirm'),
              onPressed: _busy ? null : _confirm,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.tr('member.confirmBooking')),
            ),
          ),
        ],
      ),
    ];
  }
}

/// A4 — enquiry dialog: sends a message to the trainer.
Future<bool?> showTrainerEnquiryDialog(
  BuildContext context,
  TrainerProfile trainer,
) async {
  final ctrl = TextEditingController();
  final sent = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      var busy = false;
      String? error;
      return StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(ctx.tr('member.enquire')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('trainer-enquiry-message'),
                controller: ctrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: ctx.tr('member.enquiryHint'),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                FFAlert(message: error!, tone: FFAlertTone.error),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx, false),
              child: Text(ctx.tr('member.cancel')),
            ),
            FilledButton(
              key: const Key('trainer-enquiry-send'),
              onPressed: busy
                  ? null
                  : () async {
                      if (ctrl.text.trim().isEmpty) return;
                      setDialogState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await AppScope.of(ctx).api.engageTrainer(
                          trainer.id,
                          type: 'enquiry',
                          message: ctrl.text.trim(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (_) {
                        setDialogState(() {
                          busy = false;
                          error = ctx.tr('member.enquiryFailed');
                        });
                      }
                    },
              child: Text(ctx.tr('member.send')),
            ),
          ],
        ),
      );
    },
  );
  // AlertDialog remains mounted during its exit transition. Defer disposal so
  // its TextField is never rebuilt with an already-disposed controller.
  Future<void>.delayed(const Duration(milliseconds: 300), ctrl.dispose);
  return sent;
}
