import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/api_client.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';

class OwnerRegistrationPage extends StatefulWidget {
  const OwnerRegistrationPage({super.key});

  @override
  State<OwnerRegistrationPage> createState() => _OwnerRegistrationPageState();
}

class _OwnerRegistrationPageState extends State<OwnerRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  int _step = 0;
  bool _busy = false;

  // Step 0 — Owner info
  final _nameCtrl = TextEditingController();

  // Step 1 — Gym list
  final List<_GymDraft> _gyms = [_GymDraft()];

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final g in _gyms) {
      g.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final api = AppScope.of(context).api;
      await api.gymOwnerRegister({
        'displayName': _nameCtrl.text.trim(),
        'gyms': _gyms.map((g) => g.toJson()).toList(),
      });
      if (!mounted) return;
      // Re-hydrate auth
      final meRes = await api.me();
      if (!mounted) return;
      final user = Map<String, dynamic>.from(meRes['user'] as Map);
      await AppScope.of(
        context,
      ).auth.signIn(AppScope.of(context).auth.token!, user);
      if (!mounted) return;
      context.go(AppRoutes.pending);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.status}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _next() {
    if (_step < 1) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  void _addGym() {
    setState(() => _gyms.add(_GymDraft()));
  }

  void _removeGym(int index) {
    if (_gyms.length > 1) {
      setState(() {
        _gyms[index].dispose();
        _gyms.removeAt(index);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('ownerReg.title')),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Step indicator
                Row(
                  children: List.generate(2, (i) {
                    final active = i <= _step;
                    return Expanded(
                      child: Container(
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: active
                              ? FFTokens.brand600
                              : FFTokens.borderSecondary,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(child: _buildStep(context)),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (_step > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _back,
                          child: Text(context.tr('onboarding.back')),
                        ),
                      ),
                    if (_step > 0) const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _next,
                        child: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _step < 1
                                    ? context.tr('onboarding.next')
                                    : context.tr('ownerReg.submit'),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    switch (_step) {
      case 0:
        return _ownerInfoStep(context);
      case 1:
        return _gymsStep(context);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _ownerInfoStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('ownerReg.ownerTitle'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: FFTokens.fgPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('ownerReg.ownerSubtitle'),
          style: const TextStyle(fontSize: 14, color: FFTokens.fgTertiary),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: context.tr('ownerReg.displayName'),
            border: const OutlineInputBorder(),
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? context.tr('onboarding.required')
              : null,
        ),
      ],
    );
  }

  Widget _gymsStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('ownerReg.gymTitle'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: FFTokens.fgPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('ownerReg.gymSubtitle'),
          style: const TextStyle(fontSize: 14, color: FFTokens.fgTertiary),
        ),
        const SizedBox(height: 20),
        ..._gyms.asMap().entries.map((entry) {
          final i = entry.key;
          final g = entry.value;
          return _gymCard(context, g, i);
        }),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _addGym,
          icon: const Icon(Icons.add),
          label: Text(context.tr('ownerReg.addGym')),
        ),
      ],
    );
  }

  Widget _gymCard(BuildContext context, _GymDraft gym, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${context.tr('ownerReg.gym')} ${index + 1}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: FFTokens.fgPrimary,
                    ),
                  ),
                ),
                if (_gyms.length > 1)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => _removeGym(index),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: gym.nameCtrl,
              decoration: InputDecoration(
                labelText: context.tr('ownerReg.gymName'),
                border: const OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.tr('onboarding.required')
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: gym.locationCtrl,
              decoration: InputDecoration(
                labelText: context.tr('ownerReg.gymLocation'),
                border: const OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.tr('onboarding.required')
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: gym.rateCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.tr('ownerReg.perVisitRate'),
                suffixText: 'TZS',
                border: const OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.tr('onboarding.required')
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: gym.venueType,
              decoration: InputDecoration(
                labelText: context.tr('ownerReg.venueType'),
                border: const OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'physical', child: Text('Physical')),
                DropdownMenuItem(value: 'online', child: Text('Online')),
                DropdownMenuItem(value: 'hybrid', child: Text('Hybrid')),
              ],
              onChanged: (v) => gym.venueType = v ?? 'physical',
            ),
          ],
        ),
      ),
    );
  }
}

class _GymDraft {
  final nameCtrl = TextEditingController();
  final locationCtrl = TextEditingController();
  final rateCtrl = TextEditingController();
  String venueType = 'physical';

  Map<String, dynamic> toJson() => {
    'name': nameCtrl.text.trim(),
    'location': locationCtrl.text.trim(),
    'perVisitRate': num.tryParse(rateCtrl.text) ?? 0,
    'venueType': venueType,
  };

  void dispose() {
    nameCtrl.dispose();
    locationCtrl.dispose();
    rateCtrl.dispose();
  }
}
