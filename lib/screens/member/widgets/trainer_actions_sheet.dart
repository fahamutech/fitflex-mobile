import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
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

class _TrainerBookingSheetState extends State<TrainerBookingSheet> {
  TrainerAvailability? _selectedDay;
  String? _selectedSlot;
  bool _busy = false;
  String? _error;

  String? get _gymId {
    final entryGym = _selectedDay?.gymId;
    if (entryGym != null && entryGym.isNotEmpty) return entryGym;
    return widget.trainer.gymIds.firstOrNull ??
        widget.trainer.gyms.firstOrNull?.id;
  }

  Future<void> _book() async {
    final day = _selectedDay;
    final slot = _selectedSlot;
    final gymId = _gymId;
    if (day == null || slot == null || gymId == null) return;
    final date = nextDateForAvailabilityDay(day.day);
    if (date == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.of(context).api.bookTrainer(
        trainerId: widget.trainer.id,
        gymId: gymId,
        date: date,
        slot: slot,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      final code = (e.body is Map)
          ? (e.body as Map)['error']?.toString()
          : null;
      setState(() {
        _busy = false;
        _error = switch (code) {
          'slot_already_booked' => context.tr('member.slotAlreadyBooked'),
          'slot_not_available' => context.tr('member.slotNotAvailable'),
          _ => context.tr('member.bookingFailed'),
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.tr('member.bookingFailed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final availability = widget.trainer.availability;
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
              context.tr('member.bookSession'),
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
            if (availability.isEmpty)
              FFEmptyState(title: context.tr('member.noAvailability'))
            else ...[
              // A4/C1: members may only pick from the trainer's open slots.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: availability
                        .map(
                          (a) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      a.dayLabel,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    if (a.gymName != null) ...[
                                      const SizedBox(width: 8),
                                      FFBadge(
                                        label: a.gymName!,
                                        tone: FFBadgeTone.brand,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: a.slots.map((slot) {
                                    final selected =
                                        _selectedDay == a &&
                                        _selectedSlot == slot;
                                    return ChoiceChip(
                                      key: Key('slot-${a.day}-$slot'),
                                      label: Text(slot),
                                      selected: selected,
                                      onSelected: _busy
                                          ? null
                                          : (_) => setState(() {
                                              _selectedDay = a;
                                              _selectedSlot = slot;
                                            }),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
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
                  key: const Key('trainer-book-confirm'),
                  onPressed: _selectedSlot == null || _busy ? null : _book,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.tr('member.bookSession')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
