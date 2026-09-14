import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';

String _dateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// C3 — today's sessions sheet: bookings + manual sessions with an
/// "add manual session" action.
Future<void> showTrainerSessionsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const TrainerSessionsSheet(),
  );
}

class TrainerSessionsSheet extends StatefulWidget {
  const TrainerSessionsSheet({super.key});

  @override
  State<TrainerSessionsSheet> createState() => _TrainerSessionsSheetState();
}

class _TrainerSessionsSheetState extends State<TrainerSessionsSheet> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  DateTime _date = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await AppScope.of(
        context,
      ).api.trainerSessions(date: _dateOnly(_date));
      if (!mounted) return;
      setState(() {
        _sessions = (res['sessions'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        _loading = false;
      });
    } on ApiException {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addManualSession() async {
    final added = await showTrainerAddSessionSheet(context, date: _date);
    if (added == true && mounted) await _load();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('trainer.todaySessions'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(_dateOnly(_date)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(FFTokens.spacingLg),
                  child: FFSpinner(),
                ),
              )
            else if (_sessions.isEmpty)
              FFEmptyState(title: context.tr('trainer.noSessions'))
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _sessions.length,
                  itemBuilder: (context, i) {
                    final s = _sessions[i];
                    final memberName = ((s['member'] as Map?)?['displayName'])
                        ?.toString();
                    final customer =
                        memberName ??
                        s['customerName']?.toString() ??
                        context.tr('trainer.walkIn');
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        s['source'] == 'booking'
                            ? Icons.event_available
                            : Icons.person_add_alt,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(customer),
                      subtitle: Text(
                        [
                          if (s['slot'] != null) s['slot'].toString(),
                          if ((s['gym'] as Map?)?['name'] != null)
                            (s['gym'] as Map)['name'].toString(),
                          if (s['locationLabel'] != null)
                            s['locationLabel'].toString(),
                        ].join(' · '),
                      ),
                      trailing: Text(
                        formatCurrency(s['amountTzs'] as num? ?? 0),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('trainer-add-session'),
                onPressed: _addManualSession,
                icon: const Icon(Icons.add),
                label: Text(context.tr('trainer.addSession')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// C3 — manual session form (customer email/phone + gym + amount).
Future<bool?> showTrainerAddSessionSheet(
  BuildContext context, {
  required DateTime date,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => TrainerAddSessionSheet(date: date),
  );
}

class TrainerAddSessionSheet extends StatefulWidget {
  const TrainerAddSessionSheet({super.key, required this.date});

  final DateTime date;

  @override
  State<TrainerAddSessionSheet> createState() => _TrainerAddSessionSheetState();
}

class _TrainerAddSessionSheetState extends State<TrainerAddSessionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _slot = TextEditingController();
  final _amount = TextEditingController();
  final _location = TextEditingController();
  String _locationType = 'my_gym';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _slot.dispose();
    _amount.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_name.text.trim().isEmpty &&
        _email.text.trim().isEmpty &&
        _phone.text.trim().isEmpty) {
      setState(() => _error = context.tr('trainer.customerContactRequired'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.of(context).api.trainerCreateSession({
        if (_name.text.trim().isNotEmpty) 'customerName': _name.text.trim(),
        if (_email.text.trim().isNotEmpty) 'customerEmail': _email.text.trim(),
        if (_phone.text.trim().isNotEmpty) 'customerPhone': _phone.text.trim(),
        'date': _dateOnly(widget.date),
        if (_slot.text.trim().isNotEmpty) 'slot': _slot.text.trim(),
        if (_amount.text.trim().isNotEmpty)
          'amountTzs': num.tryParse(_amount.text.trim()) ?? 0,
        'locationType': _locationType,
        if (_locationType != 'my_gym') 'locationLabel': _location.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.tr('owner.errorGeneric');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: FFTokens.spacingLg,
          right: FFTokens.spacingLg,
          bottom: MediaQuery.of(context).viewInsets.bottom + FFTokens.spacingLg,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr('trainer.addSession'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              FFTextField(
                key: const Key('session-customer-name'),
                controller: _name,
                label: context.tr('member.fullName'),
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                key: const Key('session-customer-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                label: context.tr('member.email'),
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                key: const Key('session-customer-phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                label: context.tr('members.phone'),
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                controller: _slot,
                label: context.tr('trainer.sessionTime'),
                hint: '10:00',
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                label: context.tr('owner.paidAmount'),
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFDropdownField<String>(
                key: const Key('session-location-type'),
                value: _locationType,
                label: context.tr('trainer.sessionLocation'),
                items: [
                  DropdownMenuItem(
                    value: 'my_gym',
                    child: Text(context.tr('trainer.locationMyGym')),
                  ),
                  DropdownMenuItem(
                    value: 'other_gym',
                    child: Text(context.tr('trainer.locationOtherGym')),
                  ),
                  DropdownMenuItem(
                    value: 'other_location',
                    child: Text(context.tr('trainer.locationOther')),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _locationType = value ?? 'my_gym'),
              ),
              if (_locationType != 'my_gym') ...[
                const SizedBox(height: FFTokens.spacingSm),
                FFTextField(
                  key: const Key('session-other-location'),
                  controller: _location,
                  label: context.tr('trainer.locationName'),
                  validator: (value) =>
                      _locationType != 'my_gym' &&
                          (value == null || value.trim().isEmpty)
                      ? context.tr('onboarding.required')
                      : null,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                FFAlert(message: _error!, tone: FFAlertTone.error),
              ],
              const SizedBox(height: 14),
              FilledButton(
                key: const Key('session-save'),
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(context.tr('member.save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// C2 — earnings sheet bound to /trainer/earnings.
Future<void> showTrainerEarningsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => const TrainerEarningsSheet(),
  );
}

class TrainerEarningsSheet extends StatefulWidget {
  const TrainerEarningsSheet({super.key});

  @override
  State<TrainerEarningsSheet> createState() => _TrainerEarningsSheetState();
}

class _TrainerEarningsSheetState extends State<TrainerEarningsSheet> {
  Map<String, dynamic>? _earnings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final res = await AppScope.of(context).api.trainerEarnings();
      if (mounted) {
        setState(() {
          _earnings = res;
          _loading = false;
        });
      }
    } on ApiException {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _earnings;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('trainer.earnings'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(child: FFSpinner())
            else if (e == null)
              FFEmptyState(title: context.tr('member.noData'))
            else ...[
              FFMetricCard(
                key: const Key('trainer-earnings-total'),
                label: context.tr('trainer.totalEarnings'),
                value: formatCurrency(e['totalTzs'] as num? ?? 0),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FFMetricCard(
                      label: context.tr('trainer.fromBookings'),
                      value: formatCurrency(e['bookingTzs'] as num? ?? 0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FFMetricCard(
                      label: context.tr('trainer.fromManualSessions'),
                      value: formatCurrency(e['manualTzs'] as num? ?? 0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                context
                    .tr('trainer.earningsCounts')
                    .replaceFirst('{bookings}', '${e['bookingCount'] ?? 0}')
                    .replaceFirst(
                      '{sessions}',
                      '${e['manualSessionCount'] ?? 0}',
                    ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
