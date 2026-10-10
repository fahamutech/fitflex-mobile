import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/api_client.dart';
import '../../shared/api_error_message.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/widgets/location_picker.dart';
import '../../shared/widgets/persona_switcher.dart';

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

  static const int _fullMaxDimension = 1280;
  static const int _fullWebpQuality = 80;
  static const int _thumbMaxDimension = 320;
  static const int _thumbWebpQuality = 70;

  Future<String?> _compressToWebpDataUrl(
    String path, {
    required int maxDimension,
    required int quality,
  }) async {
    try {
      final Uint8List? bytes = await FlutterImageCompress.compressWithFile(
        path,
        minWidth: maxDimension,
        minHeight: maxDimension,
        quality: quality,
        format: CompressFormat.webp,
      );
      if (bytes == null) return null;
      return 'data:image/webp;base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }

  /// Converts local image paths to WebP data URIs, returning parallel
  /// full-size and thumbnail lists.
  Future<(List<String>, List<String>)> _encodeImages(List<String> paths) async {
    final images = <String>[];
    final thumbnails = <String>[];
    for (final path in paths) {
      try {
        final file = File(path);
        if (!await file.exists()) continue;
        final fullWebp = await _compressToWebpDataUrl(
          path,
          maxDimension: _fullMaxDimension,
          quality: _fullWebpQuality,
        );
        final thumbWebp = await _compressToWebpDataUrl(
          path,
          maxDimension: _thumbMaxDimension,
          quality: _thumbWebpQuality,
        );
        if (fullWebp != null) {
          images.add(fullWebp);
          thumbnails.add(thumbWebp ?? fullWebp);
        } else {
          final bytes = await file.readAsBytes();
          final ext = path.split('.').last.toLowerCase();
          final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
          final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
          images.add(dataUrl);
          thumbnails.add(dataUrl);
        }
      } catch (_) {
        // Skip unreadable files
      }
    }
    return (images, thumbnails);
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
          final (images, thumbnails) = await _encodeImages(g.imagePaths);
          json['images'] = images;
          json['thumbnails'] = thumbnails;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(FFLocaleScope.of(context), e))),
      );
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
          tooltip: context.tr('a11y.back'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_step > 0) {
              _back();
            } else {
              context.go(AppRoutes.role);
            }
          },
        ),
        actions: const [PersonaSwitchButton(), AppPrefsButtons()],
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
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
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
                            ? SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
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
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('ownerReg.ownerSubtitle'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: FFTokens.spacingLg),
        FFTextField(
          controller: _nameCtrl,
          label: context.tr('ownerReg.displayName'),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? context.tr('onboarding.required')
              : null,
        ),
        const SizedBox(height: FFTokens.spacingSm),
        FFTextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          label: context.tr('ownerReg.phone'),
          hint: '+255...',
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
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('ownerReg.gymSubtitle'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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

  const _GymCardWidget({
    required this.gym,
    required this.index,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
    required this.trainers,
    required this.loadingTrainers,
  });

  @override
  State<_GymCardWidget> createState() => _GymCardWidgetState();
}

class _GymCardWidgetState extends State<_GymCardWidget> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    final files = await _picker.pickMultiImage(
      maxWidth: 1024,
      imageQuality: 80,
    );
    if (files.isNotEmpty) {
      setState(() {
        widget.gym.imagePaths.addAll(files.map((file) => file.path));
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
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (widget.canRemove)
                  IconButton(
                    tooltip: context.tr('common.close'),
                    icon: const Icon(Icons.close, size: FFTokens.iconMd),
                    onPressed: widget.onRemove,
                  ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingSm),

            // Name
            FFTextField(
              controller: gym.nameCtrl,
              label: context.tr('ownerReg.gymName'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.tr('onboarding.required')
                  : null,
            ),
            const SizedBox(height: FFTokens.spacingSm),

            // Location (text)
            FFTextField(
              controller: gym.locationCtrl,
              label: context.tr('ownerReg.gymLocation'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.tr('onboarding.required')
                  : null,
            ),
            const SizedBox(height: FFTokens.spacingSm),

            // Rates
            FFTextField(
              controller: gym.rateDayCtrl,
              keyboardType: TextInputType.number,
              label: context.tr('ownerReg.ratePerDay'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.tr('onboarding.required')
                  : null,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            FFTextField(
              controller: gym.rateWeekCtrl,
              keyboardType: TextInputType.number,
              label: context.tr('ownerReg.ratePerWeek'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.tr('onboarding.required')
                  : null,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            FFTextField(
              controller: gym.rateMonthCtrl,
              keyboardType: TextInputType.number,
              label: context.tr('ownerReg.ratePerMonth'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.tr('onboarding.required')
                  : null,
            ),
            const SizedBox(height: FFTokens.spacingSm),

            // Trainer selection
            FFFieldLabel(context.tr('ownerReg.trainersLabel')),
            Text(
              context.tr('ownerReg.trainersHint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: FFTokens.spacingSm),
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
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.08),
                      side: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.3),
                      ),
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
            FFFieldLabel(context.tr('ownerReg.mapLabel')),
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
            FFFieldLabel(context.tr('ownerReg.imagesLabel')),
            Text(
              context.tr('ownerReg.imagesHint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: FFTokens.spacingSm),
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

  const _TrainerSearchDialog({
    required this.trainers,
    required this.selectedIds,
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
          tooltip: context.tr('common.close'),
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
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
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
                            ? Icon(
                                Icons.check_circle,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : Icon(
                                Icons.circle_outlined,
                                color: Theme.of(context).colorScheme.outline,
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
        ],
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
