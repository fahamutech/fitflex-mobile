import 'package:flutter/material.dart';

import '../components/components.dart';
import '../design_tokens.dart';
import '../i18n.dart';
import '../pin_credentials.dart';
import '../../screens/owner/owner_shell.dart';

/// Fullscreen form for creating/editing a gym staff account (receptionist
/// etc.) with a per-feature RBAC permission set. Returns the payload Map on
/// save, or null on cancel.
class StaffFormPage extends StatefulWidget {
  final Map<String, dynamic>? initial;
  final String title;
  final List<Map<String, dynamic>> ownerGyms;

  const StaffFormPage({
    super.key,
    this.initial,
    required this.title,
    required this.ownerGyms,
  });

  @override
  State<StaffFormPage> createState() => _StaffFormPageState();
}

class _StaffFormPageState extends State<StaffFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  String _pin = '';
  bool _obscurePin = true;
  late List<String> _selectedGymIds;
  late List<String> _selectedPermissions;
  bool _busy = false;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final t = widget.initial ?? const {};
    _name = TextEditingController(text: t['displayName']?.toString() ?? '');
    _email = TextEditingController(text: t['email']?.toString() ?? '');
    _selectedGymIds =
        (t['gymIds'] as List?)?.map((e) => e.toString()).toList() ??
        (widget.ownerGyms.length == 1
            ? [widget.ownerGyms.first['id'].toString()]
            : []);
    _selectedPermissions =
        (t['aclPermissions'] as List?)?.map((e) => e.toString()).toList() ?? [];
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty)
      ? context.tr('onboarding.required')
      : null;

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return context.tr('onboarding.required');
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());
    return ok ? null : context.tr('onboarding.invalidEmail');
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedGymIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('staff.selectAtLeastOneGym'))),
      );
      return;
    }
    if (!_isEdit && _pin.length != 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('staff.pinRequired'))));
      return;
    }
    setState(() => _busy = true);
    try {
      final payload = <String, dynamic>{
        'displayName': _name.text.trim(),
        'gymIds': _selectedGymIds,
        'aclPermissions': _selectedPermissions,
        if (!_isEdit) 'email': _email.text.trim(),
        if (!_isEdit) 'password': firebasePasswordForPin(_pin),
      };
      Navigator.of(context).pop(payload);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _togglePermission(String scope, bool selected) {
    setState(() {
      _selectedPermissions = selected
          ? [..._selectedPermissions, scope]
          : _selectedPermissions.where((s) => s != scope).toList();
    });
  }

  void _toggleGym(String gymId, bool selected) {
    setState(() {
      _selectedGymIds = selected
          ? [..._selectedGymIds, gymId]
          : _selectedGymIds.where((id) => id != gymId).toList();
    });
  }

  String _scopeLabel(String scope) {
    switch (scope) {
      case 'members':
        return context.tr('owner.members');
      case 'checkins':
        return context.tr('owner.checkin');
      case 'payments':
        return context.tr('owner.earnings');
      case 'trainers':
        return context.tr('owner.trainers');
      case 'gyms':
        return context.tr('owner.manageGyms');
      case 'shop':
        return context.tr('owner.shop');
      case 'communications':
        return context.tr('comms.title');
      default:
        return scope;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            key: const Key('staffFormSave'),
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
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            children: [
              FFTextField(
                key: const Key('staffFormName'),
                controller: _name,
                label: context.tr('staff.name'),
                validator: _required,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                key: const Key('staffFormEmail'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                enabled: !_isEdit,
                label: context.tr('staff.email'),
                validator: _isEdit ? null : _emailValidator,
              ),
              if (!_isEdit) ...[
                const SizedBox(height: FFTokens.spacingSm),
                FFFieldLabel(context.tr('staff.pin')),
                Stack(
                  alignment: Alignment.centerRight,
                  children: [
                    PinInputRow(pin: _pin, obscure: _obscurePin),
                    IconButton(
                      icon: Icon(
                        _obscurePin ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePin = !_obscurePin),
                    ),
                  ],
                ),
                const SizedBox(height: FFTokens.spacingSm),
                SizedBox(
                  height: 280,
                  child: CustomKeypad(
                    onDigit: (d) {
                      if (_pin.length < 4) {
                        setState(() => _pin += d.toString());
                      }
                    },
                    onDelete: () {
                      if (_pin.isNotEmpty) {
                        setState(
                          () => _pin = _pin.substring(0, _pin.length - 1),
                        );
                      }
                    },
                    onOk: () {},
                    okEnabled: false,
                  ),
                ),
              ],
              const SizedBox(height: FFTokens.spacingMd),
              FFFieldLabel(context.tr('staff.assignedGyms')),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.ownerGyms.map((gym) {
                  final id = gym['id'].toString();
                  final selected = _selectedGymIds.contains(id);
                  return FilterChip(
                    label: Text(gym['name']?.toString() ?? id),
                    selected: selected,
                    onSelected: (v) => _toggleGym(id, v),
                  );
                }).toList(),
              ),
              const SizedBox(height: FFTokens.spacingMd),
              FFFieldLabel(context.tr('staff.permissions')),
              Text(
                context.tr('staff.permissionsHint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: FFTokens.spacingXs),
              ...kGymStaffAclScopes.map(
                (scope) => CheckboxListTile(
                  key: Key('staffPermission_$scope'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(_scopeLabel(scope)),
                  value: _selectedPermissions.contains(scope),
                  onChanged: (v) => _togglePermission(scope, v ?? false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<Map<String, dynamic>?> openStaffForm(
  BuildContext context, {
  Map<String, dynamic>? initial,
  required String title,
  required List<Map<String, dynamic>> ownerGyms,
}) {
  return Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          StaffFormPage(initial: initial, title: title, ownerGyms: ownerGyms),
    ),
  );
}
