import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/activity/activity.dart';
import '../../shared/activity/manual_activity_log.dart';
import '../../shared/api_error_message.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import '../../shared/social.dart';
import 'widgets/share_picker.dart';
import 'widgets/activity_widgets.dart';
import '../../shared/ff_datetime.dart';

/// Activity → Log activity: a session the member did without FitFlex
/// tracking it. Saved through the existing `POST /me/activities` contract
/// (sample mode keeps it in the session's sample log).
class MemberLogActivityPage extends StatefulWidget {
  const MemberLogActivityPage({super.key, this.now, this.initialType});

  /// Injectable clock for tests.
  final DateTime? now;
  final ActivityType? initialType;

  @override
  State<MemberLogActivityPage> createState() => _MemberLogActivityPageState();
}

class _MemberLogActivityPageState extends State<MemberLogActivityPage> {
  late ActivityType _type = widget.initialType ?? ActivityType.walking;
  late DateTime _day;
  late TimeOfDay _time;
  final _duration = TextEditingController();
  final _distance = TextEditingController();
  final _steps = TextEditingController();
  final _name = TextEditingController();
  final _notes = TextEditingController();
  ActivityIntensity? _intensity;
  Map<String, String> _errors = const {};
  String? _submitError;
  bool _saving = false;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    // Default: today, starting an hour ago (on the quarter hour).
    final start = _now.subtract(const Duration(hours: 1));
    _day = DateTime(start.year, start.month, start.day);
    _time = TimeOfDay(hour: start.hour, minute: start.minute ~/ 15 * 15);
  }

  @override
  void dispose() {
    for (final c in [_duration, _distance, _steps, _name, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime get _startedAt =>
      DateTime(_day.year, _day.month, _day.day, _time.hour, _time.minute);

  ManualActivityDraft _draft() => ManualActivityDraft(
    type: _type,
    startedAt: _startedAt,
    durationMinutes: int.tryParse(_duration.text.trim()),
    distanceKm: double.tryParse(_distance.text.trim().replaceAll(',', '.')),
    steps: int.tryParse(_steps.text.trim().replaceAll(',', '')),
    intensity: _intensity,
    name: _name.text,
    notes: _notes.text,
    shareWith: _share?.toJson(),
    shareChosen: _shareChosen,
  );

  ShareWith? _share;
  bool _shareChosen = false;

  Future<void> _pickDay() async {
    final now = _now;
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(now.year, now.month, now.day - manualMaxDaysBack),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    final draft = _draft();
    final errors = validateManualActivity(draft, _now);
    setState(() {
      _errors = errors;
      _submitError = null;
    });
    if (errors.isNotEmpty) return;

    final scope = AppScope.of(context);
    final data = MemberDataScope.of(context);
    final locale = FFLocaleScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final done = context.tr('logActivity.saved');
    setState(() => _saving = true);
    try {
      final saved = await scope.manualLog.log(draft);
      // Everything on the Activity screens (history, totals, goals,
      // streaks, challenges) derives from this list, so they all move.
      data.update(
        (d) =>
            d.activities = [...d.activities, saved]
              ..sort((a, b) => b.startedAt.compareTo(a.startedAt)),
      );
      messenger.showSnackBar(SnackBar(content: Text(done)));
      if (router.canPop()) {
        router.pop(true);
      } else {
        router.go(AppRoutes.memberActivity);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _submitError = errorMessage(locale, error);
      });
    }
  }

  String? _err(String field) {
    final key = _errors[field];
    return key == null ? null : context.tr(key);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = manualFieldsFor(_type);
    final dateLabel = DateFormat('EEE d MMM').format(_day);

    return ListView(
      key: const Key('log-activity'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.canPop()
                ? context.pop()
                : context.go(AppRoutes.memberActivity),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(context.tr('activity.title')),
          ),
        ),
        FFPageHeader(title: context.tr('logActivity.title')),
        Text(context.tr('logActivity.intro'), style: theme.textTheme.bodySmall),
        const SizedBox(height: FFTokens.spacingMd),
        Text(
          context.tr('logActivity.type').toUpperCase(),
          style: FFTokens.monoLabel(theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        Wrap(
          spacing: FFTokens.spacingSm,
          runSpacing: FFTokens.spacingSm,
          children: [
            for (final t in manualActivityTypes)
              ChoiceChip(
                key: Key('log-type-${t.wire}'),
                avatar: Icon(activityTypeIcon(t), size: FFTokens.iconSm),
                label: Text(activityTypeLabel(context, t)),
                selected: _type == t,
                showCheckmark: false,
                onSelected: (_) => setState(() {
                  _type = t;
                  _errors = const {};
                }),
              ),
          ],
        ),
        const SizedBox(height: FFTokens.spacingLg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('log-date'),
                onPressed: _pickDay,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(dateLabel),
              ),
            ),
            const SizedBox(width: FFTokens.spacingSm),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('log-time'),
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(
                  // English keeps the device's own clock style.
                  datesInSwahili
                      ? formatClockTime(_time.hour, _time.minute)
                      : _time.format(context),
                ),
              ),
            ),
          ],
        ),
        if (_err('startedAt') case final e?)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingXs),
            child: Text(
              e,
              key: const Key('log-time-error'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        const SizedBox(height: FFTokens.spacingMd),
        if (f.name) ...[
          _field(
            key: 'log-name',
            controller: _name,
            label: context.tr('logActivity.name'),
            hint: context.tr('logActivity.nameHint.${_type.wire}'),
            error: _err('name'),
          ),
          const SizedBox(height: FFTokens.spacingMd),
        ],
        _field(
          key: 'log-duration',
          controller: _duration,
          label: context.tr('logActivity.duration'),
          suffix: context.tr('activity.min'),
          error: _err('duration'),
          digits: true,
        ),
        if (f.distance) ...[
          const SizedBox(height: FFTokens.spacingMd),
          _field(
            key: 'log-distance',
            controller: _distance,
            label: context.tr('logActivity.distance'),
            suffix: 'km',
            error: _err('distance'),
            decimal: true,
          ),
        ],
        if (f.steps) ...[
          const SizedBox(height: FFTokens.spacingMd),
          _field(
            key: 'log-steps',
            controller: _steps,
            label: context.tr('logActivity.steps'),
            error: _err('steps'),
            digits: true,
          ),
        ],
        if (f.intensity) ...[
          const SizedBox(height: FFTokens.spacingMd),
          Text(
            context.tr('logActivity.intensity').toUpperCase(),
            style: FFTokens.monoLabel(theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Wrap(
            spacing: FFTokens.spacingSm,
            children: [
              for (final i in ActivityIntensity.values)
                ChoiceChip(
                  key: Key('log-intensity-${i.wire}'),
                  label: Text(context.tr('logActivity.intensity.${i.wire}')),
                  selected: _intensity == i,
                  onSelected: (on) =>
                      setState(() => _intensity = on ? i : null),
                ),
            ],
          ),
        ],
        const SizedBox(height: FFTokens.spacingMd),
        _field(
          key: 'log-notes',
          controller: _notes,
          label: context.tr('logActivity.notes'),
          error: _err('notes'),
          lines: 3,
        ),
        const SizedBox(height: FFTokens.spacingSm),
        Text(
          context.tr('logActivity.manualNote'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: FFTokens.spacingMd),
        FFActionTile(
          key: const Key('log-share'),
          icon: _shareChosen && _share == null
              ? Icons.lock_outline
              : Icons.people_outline,
          title: context.tr('audience.whoCanSee'),
          subtitle: _shareChosen
              ? shareLabel(context, _share)
              : context.tr('audience.useDefault'),
          onTap: () async {
            final r = await pickShare(context, initial: _share);
            if (!r.cancelled) {
              setState(() {
                _share = r.share;
                _shareChosen = true;
              });
            }
          },
        ),
        if (_submitError case final e?) ...[
          const SizedBox(height: FFTokens.spacingMd),
          FFCard(
            key: const Key('log-submit-error'),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: FFTokens.spacingSm),
                Expanded(child: Text(e, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
        ],
        const SizedBox(height: FFTokens.spacingLg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('log-save'),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.tr('logActivity.save')),
          ),
        ),
      ],
    );
  }

  Widget _field({
    required String key,
    required TextEditingController controller,
    required String label,
    String? hint,
    String? suffix,
    String? error,
    bool digits = false,
    bool decimal = false,
    int lines = 1,
  }) => TextField(
    key: Key(key),
    controller: controller,
    maxLines: lines,
    keyboardType: digits
        ? TextInputType.number
        : decimal
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    inputFormatters: [
      if (digits) FilteringTextInputFormatter.digitsOnly,
      if (decimal) FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
    ],
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      suffixText: suffix,
      errorText: error,
    ),
  );
}

/// Opens Log activity, optionally with a type chosen.
void openLogActivity(BuildContext context, {ActivityType? type}) =>
    context.push(
      type == null
          ? AppRoutes.memberActivityLog
          : '${AppRoutes.memberActivityLog}?type=${type.wire}',
    );
