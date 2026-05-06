import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../api_client.dart';
import '../design_tokens.dart';
import '../i18n.dart';

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
      await AppScope.of(context).api.updateProfile({
        'displayName': _name.text.trim(),
        'phone': _phone.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = 'Error ${e.status}';
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
              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: context.tr('ownerReg.displayName'),
                  border: const OutlineInputBorder(),
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: context.tr('member.phone'),
                  border: const OutlineInputBorder(),
                  hintText: '+255...',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: email,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: FFTokens.error500),
                  ),
                ),
              const SizedBox(height: 24),
              if (widget.onSignOut != null)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
