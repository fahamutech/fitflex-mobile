import 'package:flutter/material.dart';

import '../../../shared/i18n.dart';
import '../../../shared/components/components.dart';
import '../../../shared/formatters.dart';

/// Bottom sheet for adding a direct member (by owner).
class AddMemberSheet extends StatefulWidget {
  const AddMemberSheet({
    super.key,
    required this.ownerGymIds,
    required this.onSaved,
  });

  final List<String> ownerGymIds;
  final Future<void> Function(Map<String, dynamic> payload) onSaved;

  @override
  State<AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<AddMemberSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _durationUnit = 'M';
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 30));
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final payload = <String, dynamic>{
      'displayName': _nameCtrl.text.trim(),
      if (_emailCtrl.text.trim().isNotEmpty) 'email': _emailCtrl.text.trim(),
      if (_phoneCtrl.text.trim().isNotEmpty) 'phone': _phoneCtrl.text.trim(),
      if (widget.ownerGymIds.isNotEmpty) 'gymId': widget.ownerGymIds.first,
      'durationUnit': _durationUnit,
      'startDate': _startDate.toIso8601String().split('T').first,
      'endDate': _endDate.toIso8601String().split('T').first,
      if (_amountCtrl.text.isNotEmpty)
        'paidAmount': num.tryParse(_amountCtrl.text) ?? 0,
    };
    try {
      await widget.onSaved(payload);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate.add(const Duration(days: 30));
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('owner.addMember'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              FFTextField(
                controller: _nameCtrl,
                label: context.tr('member.fullName'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? context.tr('onboarding.required')
                    : null,
              ),
              const SizedBox(height: 12),
              FFTextField(
                controller: _emailCtrl,
                label: context.tr('auth.email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              FFTextField(
                controller: _phoneCtrl,
                label: context.tr('auth.phone'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              FFTextField(
                controller: _amountCtrl,
                label: context.tr('owner.paidAmount'),
                suffixText: currencyLabel('TZS'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _durationUnit,
                decoration: InputDecoration(
                  labelText: context.tr('owner.durationUnit'),
                  border: const OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'D', child: Text('Daily')),
                  DropdownMenuItem(value: 'W', child: Text('Weekly')),
                  DropdownMenuItem(value: 'M', child: Text('Monthly')),
                ],
                onChanged: (v) => setState(() => _durationUnit = v ?? 'M'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(isStart: true),
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(
                        '${context.tr('owner.startDate')}: ${_startDate.toIso8601String().split('T').first}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(isStart: false),
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(
                        '${context.tr('owner.endDate')}: ${_endDate.toIso8601String().split('T').first}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FFButton(
                      label: context.tr('owner.registerMember'),
                      onPressed: _busy ? null : _submit,
                      loading: _busy,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FFButton(
                      label: context.tr('member.cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      variant: FFButtonVariant.secondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
