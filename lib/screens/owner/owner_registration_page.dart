import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/api_client.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/widgets/location_picker.dart';

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
  final _phoneCtrl = TextEditingController();

  // Step 1 — Gym list
  final List<_GymDraft> _gyms = [_GymDraft()];

  // Available trainers for selection
  List<Map<String, dynamic>> _trainers = [];
  bool _loadingTrainers = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTrainers());
  }

  Future<void> _loadTrainers() async {
    setState(() => _loadingTrainers = true);
    try {
      final api = AppScope.of(context).api;
      final result = await api.listTrainers();
      if (mounted) {
        setState(() {
          _trainers = result.cast<Map<String, dynamic>>();
          _loadingTrainers = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTrainers = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    for (final g in _gyms) {
      g.dispose();
    }
    super.dispose();
  }

  Future<List<String>> _encodeImages(List<String> paths) async {
    final encoded = <String>[];
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final ext = path.split('.').last.toLowerCase();
          final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
          encoded.add('data:$mime;base64,${base64Encode(bytes)}');
        }
      } catch (_) {
        // Skip unreadable files
      }
    }
    return encoded;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final api = AppScope.of(context).api;
      // Convert local image paths to base64 data URIs
      final gymPayloads = <Map<String, dynamic>>[];
      for (final g in _gyms) {
        final json = g.toJson();
        if (g.imagePaths.isNotEmpty) {
          json['images'] = await _encodeImages(g.imagePaths);
        }
        gymPayloads.add(json);
      }
      await api.gymOwnerRegister({
        'displayName': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isNotEmpty
            ? _phoneCtrl.text.trim()
            : null,
        'gyms': gymPayloads,
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
    if (_step == 0) {
      if (!_formKey.currentState!.validate()) return;
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

  Future<void> _removeGym(int index) async {
    if (_gyms.length <= 1) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('ownerReg.removeGym')),
        content: Text(context.tr('ownerReg.confirmRemoveGym')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('member.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FFTokens.error500),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('ownerReg.removeGym')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _gyms[index].dispose();
      _gyms.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('ownerReg.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_step > 0) {
              _back();
            } else {
              context.go(AppRoutes.role);
            }
          },
        ),
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
        const SizedBox(height: 12),
        TextFormField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: context.tr('ownerReg.phone'),
            border: const OutlineInputBorder(),
            hintText: '+255...',
          ),
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
          return _GymCardWidget(
            gym: g,
            index: i,
            canRemove: _gyms.length > 1,
            onRemove: () => _removeGym(i),
            onChanged: () => setState(() {}),
            trainers: _trainers,
            loadingTrainers: _loadingTrainers,
            onTrainerCreated: (trainer) async {
              setState(() => _trainers.add(trainer));
            },
          );
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
}

/// Gym card widget — extracted as its own stateful widget for map/images state
class _GymCardWidget extends StatefulWidget {
  final _GymDraft gym;
  final int index;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final List<Map<String, dynamic>> trainers;
  final bool loadingTrainers;
  final Future<void> Function(Map<String, dynamic> trainer) onTrainerCreated;

  const _GymCardWidget({
    required this.gym,
    required this.index,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
    required this.trainers,
    required this.loadingTrainers,
    required this.onTrainerCreated,
  });

  @override
  State<_GymCardWidget> createState() => _GymCardWidgetState();
}

class _GymCardWidgetState extends State<_GymCardWidget> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 80,
    );
    if (file != null) {
      setState(() {
        widget.gym.imagePaths.add(file.path);
      });
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final gym = widget.gym;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${context.tr('ownerReg.gym')} ${widget.index + 1}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: FFTokens.fgPrimary,
                    ),
                  ),
                ),
                if (widget.canRemove)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: widget.onRemove,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Name
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

            // Location (text)
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

            // Tier
            DropdownButtonFormField<String>(
              initialValue: gym.tier,
              decoration: InputDecoration(
                labelText: context.tr('ownerReg.tier'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'standard',
                  child: Text(context.tr('ownerReg.tier_standard')),
                ),
                DropdownMenuItem(
                  value: 'midtier',
                  child: Text(context.tr('ownerReg.tier_midtier')),
                ),
                DropdownMenuItem(
                  value: 'premium',
                  child: Text(context.tr('ownerReg.tier_premium')),
                ),
                DropdownMenuItem(
                  value: 'luxury_executive',
                  child: Text(context.tr('ownerReg.tier_luxury')),
                ),
              ],
              onChanged: (v) {
                gym.tier = v ?? 'standard';
                widget.onChanged();
              },
            ),
            const SizedBox(height: 12),

            // Rates row — day / week / month
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: gym.rateDayCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.tr('ownerReg.ratePerDay'),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? context.tr('onboarding.required')
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: gym.rateWeekCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.tr('ownerReg.ratePerWeek'),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? context.tr('onboarding.required')
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: gym.rateMonthCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.tr('ownerReg.ratePerMonth'),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? context.tr('onboarding.required')
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Trainer selection
            Text(
              context.tr('ownerReg.trainersLabel'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: FFTokens.fgSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('ownerReg.trainersHint'),
              style: const TextStyle(
                fontSize: 12,
                color: FFTokens.fgQuaternary,
              ),
            ),
            const SizedBox(height: 8),
            // Selected trainers chips
            if (gym.trainerIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: gym.trainerIds.map((id) {
                    final t = widget.trainers
                        .cast<Map<String, dynamic>?>()
                        .firstWhere(
                          (tr) => tr?['id'] == id,
                          orElse: () => null,
                        );
                    final name = t != null
                        ? ((t['displayName'] as String?) ??
                              (t['email'] as String?) ??
                              id)
                        : id;
                    return Chip(
                      label: Text(name, style: const TextStyle(fontSize: 12)),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        setState(() => gym.trainerIds.remove(id));
                        widget.onChanged();
                      },
                      backgroundColor: FFTokens.brand50,
                      side: const BorderSide(color: FFTokens.brand200),
                    );
                  }).toList(),
                ),
              ),
            // Select trainer button — opens fullscreen search dialog
            OutlinedButton.icon(
              onPressed: () => _openTrainerSearchDialog(context, gym),
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: Text(context.tr('ownerReg.searchTrainers')),
            ),
            const SizedBox(height: 16),

            // Map picker
            Text(
              context.tr('ownerReg.mapLabel'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: FFTokens.fgSecondary,
              ),
            ),
            const SizedBox(height: 8),
            LocationPicker(
              initialLat: gym.lat,
              initialLng: gym.lng,
              height: 200,
              onChanged: (latlng) {
                gym.lat = latlng.latitude;
                gym.lng = latlng.longitude;
                widget.onChanged();
              },
            ),
            const SizedBox(height: 16),

            // Image picker
            Text(
              context.tr('ownerReg.imagesLabel'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: FFTokens.fgSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('ownerReg.imagesHint'),
              style: const TextStyle(
                fontSize: 12,
                color: FFTokens.fgQuaternary,
              ),
            ),
            const SizedBox(height: 8),
            if (gym.imagePaths.isNotEmpty)
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: gym.imagePaths.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            FFTokens.radiusMd,
                          ),
                          child: Image.file(
                            File(gym.imagePaths[i]),
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                gym.imagePaths.removeAt(i);
                              });
                              widget.onChanged();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.add_a_photo, size: 18),
              label: Text(context.tr('ownerReg.pickImage')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTrainerSearchDialog(
    BuildContext context,
    _GymDraft gym,
  ) async {
    final result = await Navigator.of(context).push<_TrainerDialogResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TrainerSearchDialog(
          trainers: widget.trainers,
          selectedIds: gym.trainerIds,
          onTrainerCreated: widget.onTrainerCreated,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        gym.trainerIds
          ..clear()
          ..addAll(result.selectedIds);
      });
      widget.onChanged();
    }
  }
}

// ─── Result types for fullscreen dialogs ───

class _TrainerDialogResult {
  final List<String> selectedIds;
  _TrainerDialogResult(this.selectedIds);
}

// ─── Fullscreen Trainer Search & Select Dialog ───

class _TrainerSearchDialog extends StatefulWidget {
  final List<Map<String, dynamic>> trainers;
  final List<String> selectedIds;
  final Future<void> Function(Map<String, dynamic> trainer) onTrainerCreated;

  const _TrainerSearchDialog({
    required this.trainers,
    required this.selectedIds,
    required this.onTrainerCreated,
  });

  @override
  State<_TrainerSearchDialog> createState() => _TrainerSearchDialogState();
}

class _TrainerSearchDialogState extends State<_TrainerSearchDialog> {
  final _searchCtrl = TextEditingController();
  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.toLowerCase();
    final filtered = widget.trainers.where((t) {
      final name =
          ((t['displayName'] as String?) ?? (t['email'] as String?) ?? '')
              .toLowerCase();
      return name.contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('ownerReg.trainersLabel')),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_TrainerDialogResult(_selected)),
            child: Text(context.tr('ownerReg.done')),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(FFTokens.spacingMd),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: context.tr('ownerReg.searchTrainers'),
                prefixIcon: const Icon(Icons.search, size: 20),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      context.tr('ownerReg.noTrainersFound'),
                      style: const TextStyle(color: FFTokens.fgQuaternary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FFTokens.spacingMd,
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final t = filtered[i];
                      final id = t['id'] as String;
                      final name =
                          (t['displayName'] as String?) ??
                          (t['email'] as String?) ??
                          id;
                      final email = t['email'] as String? ?? '';
                      final isSelected = _selected.contains(id);
                      return ListTile(
                        title: Text(name),
                        subtitle: email.isNotEmpty ? Text(email) : null,
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle,
                                color: FFTokens.brand600,
                              )
                            : const Icon(
                                Icons.circle_outlined,
                                color: FFTokens.fgDisabled,
                              ),
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selected.remove(id);
                            } else {
                              _selected.add(id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
          // Create new trainer button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(FFTokens.spacingMd),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openCreateTrainer(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(context.tr('ownerReg.createTrainer')),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreateTrainer(BuildContext context) async {
    final created = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            _TrainerCreateDialog(onTrainerCreated: widget.onTrainerCreated),
      ),
    );
    if (created != null && mounted) {
      setState(() {
        _selected.add(created['id'] as String);
      });
    }
  }
}

// ─── Fullscreen Create Trainer Dialog ───

class _TrainerCreateDialog extends StatefulWidget {
  final Future<void> Function(Map<String, dynamic> trainer) onTrainerCreated;

  const _TrainerCreateDialog({required this.onTrainerCreated});

  @override
  State<_TrainerCreateDialog> createState() => _TrainerCreateDialogState();
}

class _TrainerCreateDialogState extends State<_TrainerCreateDialog> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _specialtiesCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _specialtiesCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (name.isEmpty || email.isEmpty) {
      setState(() => _error = 'Name and email are required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = AppScope.of(context).api;
      final specialties = _specialtiesCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final result = await api.ownerAddTrainer({
        'displayName': name,
        'email': email,
        'specialties': specialties,
        'hourlyRateTzs': num.tryParse(_rateCtrl.text) ?? 0,
        'status': 'active',
      });
      final created = Map<String, dynamic>.from(result);
      await widget.onTrainerCreated(created);
      if (mounted) {
        Navigator.of(context).pop(created);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.status == 409
              ? 'This email is already in use.'
              : 'Error: ${e.status}';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Failed to create trainer.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('ownerReg.createTrainer')),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: InputDecoration(
                          labelText: context.tr('ownerReg.trainerName'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: context.tr('ownerReg.trainerEmail'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _specialtiesCtrl,
                        decoration: InputDecoration(
                          labelText: context.tr('ownerReg.trainerSpecialties'),
                          hintText: 'e.g. Yoga, Cardio',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _rateCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: context.tr('ownerReg.trainerRate'),
                          suffixText: 'TZS',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: FFTokens.error500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(context.tr('ownerReg.createTrainer')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Gym Draft Model ───

class _GymDraft {
  final nameCtrl = TextEditingController();
  final locationCtrl = TextEditingController();
  final rateDayCtrl = TextEditingController();
  final rateWeekCtrl = TextEditingController();
  final rateMonthCtrl = TextEditingController();
  String tier = 'standard';
  double? lat;
  double? lng;
  List<String> imagePaths = [];
  List<String> trainerIds = [];

  Map<String, dynamic> toJson() => {
    'name': nameCtrl.text.trim(),
    'location': locationCtrl.text.trim(),
    'tier': tier,
    'ratePerDay': num.tryParse(rateDayCtrl.text) ?? 0,
    'ratePerWeek': num.tryParse(rateWeekCtrl.text) ?? 0,
    'ratePerMonth': num.tryParse(rateMonthCtrl.text) ?? 0,
    'perVisitRate': num.tryParse(rateDayCtrl.text) ?? 0,
    'venueType': 'physical',
    'status': 'active',
    'accessMode': 'paid_visit',
    if (lat != null && lng != null) 'coordinates': {'lat': lat, 'lng': lng},
    // images are encoded by _submit() and set separately
    if (trainerIds.isNotEmpty) 'trainerIds': trainerIds,
  };

  void dispose() {
    nameCtrl.dispose();
    locationCtrl.dispose();
    rateDayCtrl.dispose();
    rateWeekCtrl.dispose();
    rateMonthCtrl.dispose();
  }
}
