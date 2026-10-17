import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../api_client.dart';
import '../api_error_message.dart';
import '../components/components.dart';
import '../design_tokens.dart';
import '../i18n.dart';

/// Fullscreen profile editor + sign-out for gym owners. Members use
/// [MemberEditProfilePage] instead.
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
  String? _photoUrl;
  bool _busy = false;
  String? _error;

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
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
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
                ? FFSpinner(size: 18)
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
              FFTextField(
                initialValue: email,
                enabled: false,
                label: context.tr('member.email'),
              ),
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
