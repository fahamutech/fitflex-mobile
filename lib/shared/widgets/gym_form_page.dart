import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_scope.dart';
import '../design_tokens.dart';
import '../i18n.dart';
import 'location_picker.dart';

/// Fullscreen form for creating/editing a gym. Mirrors the fields used during
/// gym-owner onboarding (registration page) so all gym-creation paths produce
/// the same data shape. Returns the full payload `Map<String, dynamic>` on
/// save, or `null` if cancelled.
class GymFormPage extends StatefulWidget {
  /// Existing gym data when editing; `null` for create.
  final Map<String, dynamic>? initial;

  /// Optional title override.
  final String? title;

  const GymFormPage({super.key, this.initial, this.title});

  @override
  State<GymFormPage> createState() => _GymFormPageState();
}

class _GymFormPageState extends State<GymFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _rateDayCtrl;
  late final TextEditingController _rateWeekCtrl;
  late final TextEditingController _rateMonthCtrl;
  String _tier = 'standard';
  double? _lat;
  double? _lng;

  /// Mix of existing remote URLs/data-URIs (kept as-is) and new local file
  /// paths (encoded to base64 on save).
  final List<String> _images = [];

  /// Selected trainer ids
  final List<String> _trainerIds = [];

  List<Map<String, dynamic>> _trainers = [];
  bool _loadingTrainers = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final g = widget.initial ?? const {};
    _nameCtrl = TextEditingController(text: g['name']?.toString() ?? '');
    _locationCtrl = TextEditingController(
      text: g['location']?.toString() ?? '',
    );
    _rateDayCtrl = TextEditingController(
      text: _numText(g['ratePerDay'] ?? g['perVisitRate']),
    );
    _rateWeekCtrl = TextEditingController(text: _numText(g['ratePerWeek']));
    _rateMonthCtrl = TextEditingController(text: _numText(g['ratePerMonth']));
    _tier = (g['tier']?.toString().isNotEmpty ?? false)
        ? g['tier'].toString()
        : 'standard';
    final coords = g['coordinates'];
    if (coords is Map) {
      _lat = (coords['lat'] as num?)?.toDouble();
      _lng = (coords['lng'] as num?)?.toDouble();
    }
    final imgs = g['images'];
    if (imgs is List) {
      _images.addAll(imgs.whereType<String>());
    }
    final tids = g['trainerIds'];
    if (tids is List) {
      _trainerIds.addAll(tids.whereType<String>());
    } else {
      // Fall back to derived list when backend returns hydrated trainers.
      final tList = g['trainers'];
      if (tList is List) {
        for (final t in tList.whereType<Map>()) {
          final id = t['id']?.toString();
          if (id != null) _trainerIds.add(id);
        }
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTrainers());
  }

  String _numText(dynamic v) {
    if (v == null) return '';
    final n = v is num ? v : num.tryParse(v.toString()) ?? 0;
    return n == 0 ? '' : n.toString();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    _rateDayCtrl.dispose();
    _rateWeekCtrl.dispose();
    _rateMonthCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTrainers() async {
    setState(() => _loadingTrainers = true);
    final api = AppScope.of(context).api;
    try {
      final result = await api.ownerTrainers();
      if (mounted) {
        setState(() {
          _trainers = result.cast<Map<String, dynamic>>();
          _loadingTrainers = false;
        });
      }
    } catch (_) {
      // Owners that haven't created any gyms yet may get an error here; that's
      // fine — fall back to platform-wide trainer list.
      try {
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
  }

  Future<void> _pickImage() async {
    final files = await _picker.pickMultiImage(
      maxWidth: 1024,
      imageQuality: 80,
    );
    if (files.isNotEmpty) {
      setState(() => _images.addAll(files.map((file) => file.path)));
    }
  }

  Future<List<String>> _encodeImages() async {
    final out = <String>[];
    for (final p in _images) {
      // Pre-existing remote URL or data URI — keep as-is.
      if (p.startsWith('http') || p.startsWith('data:')) {
        out.add(p);
        continue;
      }
      try {
        final f = File(p);
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          final ext = p.split('.').last.toLowerCase();
          final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
          out.add('data:$mime;base64,${base64Encode(bytes)}');
        }
      } catch (_) {
        // Skip unreadable file
      }
    }
    return out;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final images = await _encodeImages();
      final payload = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'location': _locationCtrl.text.trim(),
        'tier': _tier,
        'ratePerDay': num.tryParse(_rateDayCtrl.text) ?? 0,
        'ratePerWeek': num.tryParse(_rateWeekCtrl.text) ?? 0,
        'ratePerMonth': num.tryParse(_rateMonthCtrl.text) ?? 0,
        'perVisitRate': num.tryParse(_rateDayCtrl.text) ?? 0,
        'venueType': 'physical',
        'accessMode': 'paid_visit',
        if (_lat != null && _lng != null)
          'coordinates': {'lat': _lat, 'lng': _lng},
        'images': images,
        'trainerIds': List<String>.from(_trainerIds),
      };
      if (!mounted) return;
      Navigator.of(context).pop(payload);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty)
      ? context.tr('onboarding.required')
      : null;

  String? _requiredNumber(String? v) {
    if (v == null || v.trim().isEmpty) {
      return context.tr('onboarding.required');
    }
    final n = num.tryParse(v.trim());
    if (n == null || n < 0) return context.tr('onboarding.required');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title ??
              (isEdit
                  ? context.tr('owner.editGym')
                  : context.tr('owner.addGym')),
        ),
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
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: context.tr('ownerReg.gymName'),
                  border: const OutlineInputBorder(),
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationCtrl,
                decoration: InputDecoration(
                  labelText: context.tr('ownerReg.gymLocation'),
                  border: const OutlineInputBorder(),
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _tier,
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
                onChanged: (v) => setState(() => _tier = v ?? 'standard'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _rateDayCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('ownerReg.ratePerDay'),
                  border: const OutlineInputBorder(),
                ),
                validator: _requiredNumber,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _rateWeekCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('ownerReg.ratePerWeek'),
                  border: const OutlineInputBorder(),
                ),
                validator: _requiredNumber,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _rateMonthCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('ownerReg.ratePerMonth'),
                  border: const OutlineInputBorder(),
                ),
                validator: _requiredNumber,
              ),
              const SizedBox(height: 16),
              Text(
                context.tr('ownerReg.trainersLabel'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: FFTokens.fgSecondary,
                ),
              ),
              const SizedBox(height: 8),
              if (_loadingTrainers)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: LinearProgressIndicator(),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _trainers.map((t) {
                    final id = t['id']?.toString() ?? '';
                    final selected = _trainerIds.contains(id);
                    final name =
                        (t['displayName'] as String?) ??
                        (t['email'] as String?) ??
                        id;
                    return FilterChip(
                      label: Text(name),
                      selected: selected,
                      onSelected: (v) => setState(() {
                        if (v) {
                          if (!_trainerIds.contains(id)) _trainerIds.add(id);
                        } else {
                          _trainerIds.remove(id);
                        }
                      }),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 16),
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
                initialLat: _lat,
                initialLng: _lng,
                height: 200,
                onChanged: (latlng) {
                  _lat = latlng.latitude;
                  _lng = latlng.longitude;
                },
              ),
              const SizedBox(height: 16),
              Text(
                context.tr('ownerReg.imagesLabel'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: FFTokens.fgSecondary,
                ),
              ),
              const SizedBox(height: 8),
              if (_images.isNotEmpty)
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _images.length,
                    separatorBuilder: (_, separatorIndex) =>
                        const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final src = _images[i];
                      final widgetImg =
                          (src.startsWith('http') || src.startsWith('data:'))
                          ? Image.network(
                              src.startsWith('data:')
                                  ? src // data URI works in Image.network on most platforms
                                  : src,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (_, error, stackTrace) =>
                                  const Icon(Icons.broken_image),
                            )
                          : Image.file(
                              File(src),
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            );
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              FFTokens.radiusMd,
                            ),
                            child: widgetImg,
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: GestureDetector(
                              onTap: () => setState(() => _images.removeAt(i)),
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
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper to push the form as a fullscreen dialog.
Future<Map<String, dynamic>?> openGymForm(
  BuildContext context, {
  Map<String, dynamic>? initial,
  String? title,
}) {
  return Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => GymFormPage(initial: initial, title: title),
    ),
  );
}
