// Renew Membership bottom sheet — collects the new period + amount and returns
// the renewal payload. UI only; the caller performs the API call.

import 'package:flutter/material.dart';

import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/i18n.dart';
import '../data/member_models.dart';

Future<Map<String, dynamic>?> openRenewMemberSheet(
  BuildContext context, {
  MembershipPlan? current,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _RenewMemberSheet(current: current),
  );
}

class _RenewMemberSheet extends StatefulWidget {
  const _RenewMemberSheet({this.current});

  final MembershipPlan? current;

  @override
  State<_RenewMemberSheet> createState() => _RenewMemberSheetState();
}

class _RenewMemberSheetState extends State<_RenewMemberSheet> {
  final _amount = TextEditingController();
  late String _tier = widget.current?.tier ?? 'premium';
  String _durationUnit = 'M';

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  DateTime get _start => DateTime.now();

  DateTime get _end => switch (_durationUnit) {
    'D' => _start.add(const Duration(days: 1)),
    'W' => _start.add(const Duration(days: 7)),
    _ => DateTime(_start.year, _start.month + 1, _start.day),
  };

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _submit() {
    Navigator.pop(context, <String, dynamic>{
      'tier': _tier,
      'durationUnit': _durationUnit,
      'startDate': _dateOnly(_start),
      'endDate': _dateOnly(_end),
      if (_amount.text.trim().isNotEmpty)
        'paidAmount': num.tryParse(_amount.text.trim()) ?? 0,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('members.renewTitle'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('common.close'),
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: FFTokens.spacingMd),
              FFDropdownField<String>(
                label: context.tr('members.membershipPlan'),
                value: _tier,
                items: const [
                  DropdownMenuItem(value: 'basic', child: Text('Basic')),
                  DropdownMenuItem(value: 'pro', child: Text('Pro')),
                  DropdownMenuItem(value: 'premium', child: Text('Premium')),
                  DropdownMenuItem(
                    value: 'executive',
                    child: Text('Executive'),
                  ),
                ],
                onChanged: (v) => setState(() => _tier = v ?? 'premium'),
              ),
              const SizedBox(height: FFTokens.spacingMd),
              FFDropdownField<String>(
                label: context.tr('owner.durationUnit'),
                value: _durationUnit,
                items: [
                  DropdownMenuItem(
                    value: 'D',
                    child: Text(context.tr('owner.filterDaily')),
                  ),
                  DropdownMenuItem(
                    value: 'W',
                    child: Text(context.tr('owner.filterWeekly')),
                  ),
                  DropdownMenuItem(
                    value: 'M',
                    child: Text(context.tr('owner.filterMonthly')),
                  ),
                ],
                onChanged: (v) => setState(() => _durationUnit = v ?? 'M'),
              ),
              const SizedBox(height: FFTokens.spacingMd),
              FFTextField(
                controller: _amount,
                label: context.tr('owner.paidAmount'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: FFTokens.spacingLg),
              FilledButton(
                onPressed: _submit,
                child: Text(context.tr('members.renew')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
