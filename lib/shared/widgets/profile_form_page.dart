import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../api_client.dart';
import '../api_error_message.dart';
import '../components/components.dart';
import '../design_tokens.dart';
import '../i18n.dart';
import 'ff_photo_picker_field.dart';

/// Fullscreen profile editor + sign-out. Used by gym owners and trainers.
class ProfileFormPage extends StatefulWidget {
  final String title;
  final Map<String, dynamic> initialUser;
  final VoidCallback? onSignOut;

  const ProfileFormPage({
    super.key,
    required this.title,
    required this.initialUser,
    this.onSignOut,
  });

  @override
  State<ProfileFormPage> createState() => _ProfileFormPageState();
}

class _ProfileFormPageState extends State<ProfileFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _height;
  late final TextEditingController _weight;
  late final TextEditingController _dateOfBirth;
  late String _gender;
  String? _photoUrl;
  bool _busy = false;
  String? _error;
  bool get _isMember => widget.initialUser['userType']?.toString() == 'member';

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.initialUser['displayName']?.toString() ?? '',
    );
    _phone = TextEditingController(
      text: widget.initialUser['phone']?.toString() ?? '',
    );
    _photoUrl = widget.initialUser['photoUrl']?.toString();
    final profile = widget.initialUser['memberProfile'] as Map? ?? const {};
    _height = TextEditingController(
      text: profile['heightCm']?.toString() ?? '',
    );
    _weight = TextEditingController(
      text: profile['weightKg']?.toString() ?? '',
    );
    _dateOfBirth = TextEditingController(
      text: profile['dateOfBirth']?.toString() ?? '',
    );
    _gender = profile['gender']?.toString() ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _height.dispose();
    _weight.dispose();
    _dateOfBirth.dispose();
    super.dispose();
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty)
      ? context.tr('onboarding.required')
      : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final payload = <String, dynamic>{
        'displayName': _name.text.trim(),
        'phone': _phone.text.trim(),
        if (_photoUrl != null && _photoUrl!.isNotEmpty) 'photoUrl': _photoUrl,
      };
      if (_isMember) {
        payload.addAll({
          'heightCm': _height.text.trim().isEmpty
              ? null
              : num.tryParse(_height.text.trim()),
          'weightKg': _weight.text.trim().isEmpty
              ? null
              : num.tryParse(_weight.text.trim()),
          'dateOfBirth': _dateOfBirth.text.trim().isEmpty
              ? null
              : _dateOfBirth.text.trim(),
          'gender': _gender.isEmpty ? null : _gender,
        });
      }
      await AppScope.of(context).api.updateProfile(payload);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = apiErrorMessage(FFLocaleScope.of(context), e);
      });
    } catch (_) {
      setState(() {
        _busy = false;
        _error = context.tr('home.passesLoadError');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.initialUser['email']?.toString() ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          tooltip: context.tr('common.close'),
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
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
              if (_isMember) ...[
                Center(
                  child: FFPhotoPickerField(
                    value: _photoUrl,
                    onChanged: (value) => setState(() => _photoUrl = value),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              FFTextField(
                controller: _name,
                label: context.tr('ownerReg.displayName'),
                validator: _required,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                label: context.tr('member.phone'),
                hint: '+255...',
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(initialValue: email, enabled: false, label: 'Email'),
              if (_isMember) ...[
                const SizedBox(height: FFTokens.spacingSm),
                FFDropdownField<String>(
                  value: _gender.isEmpty ? null : _gender,
                  label: context.tr('onboarding.gender'),
                  items: [
                    DropdownMenuItem(
                      value: 'male',
                      child: Text(context.tr('onboarding.gender_male')),
                    ),
                    DropdownMenuItem(
                      value: 'female',
                      child: Text(context.tr('onboarding.gender_female')),
                    ),
                    DropdownMenuItem(
                      value: 'other',
                      child: Text(context.tr('onboarding.gender_other')),
                    ),
                  ],
                  onChanged: (value) => setState(() => _gender = value ?? ''),
                ),
                const SizedBox(height: FFTokens.spacingSm),
                FFTextField(
                  controller: _dateOfBirth,
                  keyboardType: TextInputType.datetime,
                  label: context.tr('member.dateOfBirth'),
                  hint: 'YYYY-MM-DD',
                ),
                const SizedBox(height: FFTokens.spacingSm),
                Row(
                  children: [
                    Expanded(
                      child: FFTextField(
                        controller: _height,
                        keyboardType: TextInputType.number,
                        label: context.tr('member.height'),
                      ),
                    ),
                    const SizedBox(width: FFTokens.spacingSm),
                    Expanded(
                      child: FFTextField(
                        controller: _weight,
                        keyboardType: TextInputType.number,
                        label: context.tr('member.weight'),
                      ),
                    ),
                  ],
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              if (widget.onSignOut != null)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: FFTokens.error500,
                  ),
                  onPressed: () {
                    Navigator.of(context).pop(false);
                    widget.onSignOut!();
                  },
                  icon: const Icon(Icons.logout),
                  label: Text(context.tr('home.signout')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool?> openProfileForm(
  BuildContext context, {
  required String title,
  required Map<String, dynamic> initialUser,
  VoidCallback? onSignOut,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ProfileFormPage(
        title: title,
        initialUser: initialUser,
        onSignOut: onSignOut,
      ),
    ),
  );
}
