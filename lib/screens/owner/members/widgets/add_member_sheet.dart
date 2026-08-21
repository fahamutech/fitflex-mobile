// Add / Edit Member bottom sheet — collects the fields required to register or
// update a direct member and returns a payload map. Pure UI: it does NOT call
// the API itself; the caller performs the create/update via the repository.

import 'package:flutter/material.dart';

import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/i18n.dart';
import '../../../../shared/pin_credentials.dart';
import '../data/member_models.dart';

/// Opens the Add Member sheet, returning the create payload or null if cancelled.
Future<Map<String, dynamic>?> openAddMemberSheet(
  BuildContext context, {
  required List<Map<String, dynamic>> gyms,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _MemberFormSheet(gyms: gyms),
  );
}

/// Opens the Edit Member sheet prefilled with [member]'s current data.
/// Returns an update payload or null if cancelled.
Future<Map<String, dynamic>?> openEditMemberSheet(
  BuildContext context, {
  required MemberDetail member,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _MemberFormSheet(gyms: const [], initialMember: member),
  );
}

class _MemberFormSheet extends StatefulWidget {
  const _MemberFormSheet({required this.gyms, this.initialMember});

  final List<Map<String, dynamic>> gyms;
  final MemberDetail? initialMember;

  bool get isEditMode => initialMember != null;

  @override
  State<_MemberFormSheet> createState() => _MemberFormSheetState();
}

class _MemberFormSheetState extends State<_MemberFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _amount = TextEditingController();
  final _initialPassword = TextEditingController();

  String _durationUnit = 'M';
  String? _gymId;
  final DateTime _startDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMember;
    if (initial != null) {
      _name.text = initial.displayName ?? '';
      _email.text = initial.email ?? '';
      _phone.text = initial.phone ?? '';
    } else {
      _gymId = widget.gyms.isNotEmpty
          ? widget.gyms.first['id']?.toString()
          : null;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _amount.dispose();
    _initialPassword.dispose();
    super.dispose();
  }

  DateTime get _endDate => switch (_durationUnit) {
    'D' => _startDate.add(const Duration(days: 1)),
    'W' => _startDate.add(const Duration(days: 7)),
    _ => DateTime(_startDate.year, _startDate.month + 1, _startDate.day),
  };

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final Map<String, dynamic> payload;
    if (widget.isEditMode) {
      payload = {
        'displayName': _name.text.trim(),
        if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
      };
    } else {
      payload = {
        'displayName': _name.text.trim(),
        if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
        if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
        if (_gymId != null) 'gymId': _gymId,
        'durationUnit': _durationUnit,
        'startDate': _dateOnly(_startDate),
        'endDate': _dateOnly(_endDate),
        if (_amount.text.trim().isNotEmpty)
          'paidAmount': num.tryParse(_amount.text.trim()) ?? 0,
        // B2: optional login credential for the member.
        if (_initialPassword.text.isNotEmpty)
          'initialPassword': firebasePasswordForPin(_initialPassword.text),
      };
    }
    Navigator.pop(context, payload);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.isEditMode;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr(
                          isEdit ? 'members.editMember' : 'members.addMember',
                        ),
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: FFTokens.spacingMd),
                FFTextField(
                  key: const Key('add-member-name'),
                  controller: _name,
                  label: context.tr('member.fullName'),
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? context.tr('members.required')
                      : null,
                ),
                const SizedBox(height: FFTokens.spacingMd),
                if (!isEdit) ...[
                  FFTextField(
                    key: const Key('add-member-email'),
                    controller: _email,
                    label: context.tr('member.email'),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      if (_initialPassword.text.isNotEmpty &&
                          (v == null || v.trim().isEmpty)) {
                        return context.tr('members.required');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: FFTokens.spacingMd),
                ],
                FFTextField(
                  controller: _phone,
                  label: context.tr('members.phone'),
                  hint: '+255 7XX XXX XXX',
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: FFTokens.spacingMd),
                if (!isEdit && widget.gyms.length > 1) ...[
                  FFDropdownField<String>(
                    label: context.tr('owner.gym'),
                    value: _gymId,
                    items: widget.gyms
                        .map(
                          (g) => DropdownMenuItem(
                            value: g['id']?.toString(),
                            child: Text(g['name']?.toString() ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _gymId = v),
                  ),
                  const SizedBox(height: FFTokens.spacingMd),
                ],
                if (!isEdit) ...[
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
                  const SizedBox(height: FFTokens.spacingMd),
                  // B2: optional initial password so the member can log in.
                  FFTextField(
                    key: const Key('add-member-initial-password'),
                    controller: _initialPassword,
                    label: context.tr('members.initialPassword'),
                    hint: context.tr('members.initialPasswordHint'),
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    validator: (v) {
                      if (v != null &&
                          v.isNotEmpty &&
                          !RegExp(r'^\d{4,8}$').hasMatch(v)) {
                        return context.tr('members.initialPasswordTooShort');
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: FFTokens.spacingLg),
                FilledButton(
                  key: const Key('add-member-save'),
                  onPressed: _submit,
                  child: Text(
                    context.tr(
                      isEdit ? 'members.updateMember' : 'members.saveMember',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
