import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_scope.dart';
import '../components/components.dart';
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

  /// Owner-set trainer-pass fee per period (empty = not sold).
  final Map<String, TextEditingController> _trainerPassFees = {
    for (final p in _passPeriods) p: TextEditingController(),
  };
  String _tier = 'standard';
  bool _trainerPassEnabled = false;

  static const _passPeriods = ['daily', 'weekly', 'monthly'];
  final List<Map<String, dynamic>> _classes = [];
  double? _lat;
  double? _lng;

  /// Mix of existing remote URLs/data-URIs (kept as-is) and new local file
  /// paths (converted to WebP + encoded to base64 on save).
  final List<String> _images = [];

  /// Small WebP thumbnail counterpart for each entry in [_images] (same
  /// index = same photo). `null` means "not generated yet" — filled in on
  /// save, either by compressing a new local file or reusing an existing
  /// pre-thumbnail image as its own thumbnail.
  final List<String?> _thumbnails = [];

  static const int _fullMaxDimension = 1280;
  static const int _fullWebpQuality = 80;
  static const int _thumbMaxDimension = 320;
  static const int _thumbWebpQuality = 70;

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
    final trainerPass = g['trainerPass'];
    if (trainerPass is Map) {
      _trainerPassEnabled = trainerPass['enabled'] == true;
      final options = trainerPass['options'];
      if (options is Map) {
        for (final p in _passPeriods) {
          final fee = options[p];
          if (fee is num && fee > 0) _trainerPassFees[p]!.text = _numText(fee);
        }
      } else {
        // Older single-fee shape: { feeTzs, period }.
        final period = trainerPass['period']?.toString();
        final fee = trainerPass['feeTzs'];
        if (_passPeriods.contains(period) && fee is num && fee > 0) {
          _trainerPassFees[period]!.text = _numText(fee);
        }
      }
    }
    final classes = g['classes'];
    if (classes is List) {
      _classes.addAll(
        classes.whereType<Map>().map((item) => Map<String, dynamic>.from(item)),
      );
    }
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
    final thumbs = g['thumbnails'];
    final existingThumbs = thumbs is List
        ? thumbs.whereType<String>().toList()
        : <String>[];
    for (var i = 0; i < _images.length; i++) {
      _thumbnails.add(i < existingThumbs.length ? existingThumbs[i] : null);
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
    for (final c in _trainerPassFees.values) {
      c.dispose();
    }
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
      setState(() {
        _images.addAll(files.map((file) => file.path));
        _thumbnails.addAll(List<String?>.filled(files.length, null));
      });
    }
  }

  /// Downscales+re-encodes a local image file as WebP. Returns `null` if the
  /// file can't be read or compressed (e.g. unsupported platform/format).
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

  /// Builds the final `images`/`thumbnails` payload arrays. New local files
  /// are converted to WebP (full + thumbnail); pre-existing remote
  /// URLs/data-URIs are kept as-is, reusing the full image as its own
  /// thumbnail when no dedicated thumbnail was recorded.
  Future<(List<String>, List<String>)> _encodeImages() async {
    final outImages = <String>[];
    final outThumbnails = <String>[];
    for (var i = 0; i < _images.length; i++) {
      final p = _images[i];
      final existingThumb = i < _thumbnails.length ? _thumbnails[i] : null;

      // Pre-existing remote URL or data URI — keep as-is.
      if (p.startsWith('http') || p.startsWith('data:')) {
        outImages.add(p);
        outThumbnails.add(existingThumb ?? p);
        continue;
      }

      try {
        final f = File(p);
        if (!await f.exists()) continue;
        final fullWebp = await _compressToWebpDataUrl(
          p,
          maxDimension: _fullMaxDimension,
          quality: _fullWebpQuality,
        );
        final thumbWebp = await _compressToWebpDataUrl(
          p,
          maxDimension: _thumbMaxDimension,
          quality: _thumbWebpQuality,
        );
        if (fullWebp != null) {
          outImages.add(fullWebp);
          outThumbnails.add(thumbWebp ?? fullWebp);
        } else {
          // Compression unavailable (e.g. web) — fall back to the raw bytes.
          final bytes = await f.readAsBytes();
          final ext = p.split('.').last.toLowerCase();
          final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
          final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
          outImages.add(dataUrl);
          outThumbnails.add(dataUrl);
        }
      } catch (_) {
        // Skip unreadable file
      }
    }
    return (outImages, outThumbnails);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final (images, thumbnails) = await _encodeImages();
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
        'thumbnails': thumbnails,
        'trainerIds': List<String>.from(_trainerIds),
        'classes': _classes,
        'trainerPass': {
          'enabled': _trainerPassEnabled,
          'options': {
            for (final p in _passPeriods)
              p: num.tryParse(_trainerPassFees[p]!.text.trim()) ?? 0,
          },
        },
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

  String? _optionalFee(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    final n = num.tryParse(t);
    return n == null || n < 0 ? context.tr('onboarding.required') : null;
  }

  String? _requiredNumber(String? v) {
    if (v == null || v.trim().isEmpty) {
      return context.tr('onboarding.required');
    }
    final n = num.tryParse(v.trim());
    if (n == null || n < 0) return context.tr('onboarding.required');
    return null;
  }

  String? _optionalNonNegativeNumber(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = num.tryParse(v.trim());
    return n == null || n < 0 ? context.tr('onboarding.required') : null;
  }

  Future<void> _showClassEditor({int? index}) async {
    final existing = index == null
        ? const <String, dynamic>{}
        : _classes[index];
    final name = TextEditingController(
      text: existing['name']?.toString() ?? '',
    );
    final schedule = TextEditingController(
      text: existing['schedule']?.toString() ?? '',
    );
    final price = TextEditingController(text: _numText(existing['price']));
    final location = TextEditingController(
      text: existing['location']?.toString() ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('ownerReg.classEditorTitle')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('gym-class-name'),
                controller: name,
                decoration: InputDecoration(
                  labelText: context.tr('ownerReg.className'),
                ),
              ),
              TextField(
                key: const Key('gym-class-schedule'),
                controller: schedule,
                decoration: InputDecoration(
                  labelText: context.tr('ownerReg.classSchedule'),
                ),
              ),
              TextField(
                key: const Key('gym-class-price'),
                controller: price,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('ownerReg.classPrice'),
                ),
              ),
              TextField(
                key: const Key('gym-class-location'),
                controller: location,
                decoration: InputDecoration(
                  labelText: context.tr('ownerReg.classLocation'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('member.cancel')),
          ),
          FilledButton(
            key: const Key('gym-class-save'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('member.save')),
          ),
        ],
      ),
    );
    if (saved == true && name.text.trim().isNotEmpty && mounted) {
      setState(() {
        final item = <String, dynamic>{
          if (existing['id'] != null) 'id': existing['id'],
          'name': name.text.trim(),
          'schedule': schedule.text.trim(),
          'price': num.tryParse(price.text.trim()) ?? 0,
          'location': location.text.trim(),
        };
        if (index == null) {
          _classes.add(item);
        } else {
          _classes[index] = item;
        }
      });
    }
    // The dialog route is still animating out immediately after `await
    // showDialog`; disposing now can leave its TextFields rebuilding against
    // disposed controllers. Release them after that transition settles.
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      name.dispose();
      schedule.dispose();
      price.dispose();
      location.dispose();
    });
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
            key: const Key('gym-form-save'),
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
            key: const Key('gym-form-scroll'),
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            children: [
              FFTextField(
                controller: _nameCtrl,
                label: context.tr('ownerReg.gymName'),
                validator: _required,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                controller: _locationCtrl,
                label: context.tr('ownerReg.gymLocation'),
                validator: _required,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                controller: _rateDayCtrl,
                keyboardType: TextInputType.number,
                label: context.tr('ownerReg.ratePerDay'),
                validator: _requiredNumber,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                controller: _rateWeekCtrl,
                keyboardType: TextInputType.number,
                label: context.tr('ownerReg.ratePerWeek'),
                validator: _optionalNonNegativeNumber,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                controller: _rateMonthCtrl,
                keyboardType: TextInputType.number,
                label: context.tr('ownerReg.ratePerMonth'),
                validator: _optionalNonNegativeNumber,
              ),
              const SizedBox(height: FFTokens.spacingMd),
              FFFieldLabel(context.tr('ownerReg.trainersLabel')),
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
              const SizedBox(height: FFTokens.spacingMd),
              FFFieldLabel(context.tr('ownerReg.classesLabel')),
              if (_classes.isEmpty)
                Text(
                  context.tr('ownerReg.noClasses'),
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                ..._classes.asMap().entries.map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.value['name']?.toString() ?? ''),
                    subtitle: Text(
                      [entry.value['schedule'], entry.value['location']]
                          .whereType<String>()
                          .where((v) => v.isNotEmpty)
                          .join(' · '),
                    ),
                    trailing: IconButton(
                      tooltip: context.tr('ownerReg.editClass'),
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _showClassEditor(index: entry.key),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                key: const Key('gym-add-class'),
                onPressed: _showClassEditor,
                icon: const Icon(Icons.add, size: 18),
                label: Text(context.tr('ownerReg.addClass')),
              ),
              const SizedBox(height: FFTokens.spacingMd),
              FFFieldLabel(context.tr('ownerReg.trainerPassLabel')),
              SwitchListTile(
                key: const Key('gym-trainer-pass-enabled'),
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('ownerReg.trainerPassEnabled')),
                value: _trainerPassEnabled,
                onChanged: (value) =>
                    setState(() => _trainerPassEnabled = value),
              ),
              Text(
                context.tr('ownerReg.trainerPassHint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_trainerPassEnabled) ...[
                const SizedBox(height: FFTokens.spacingSm),
                for (final p in _passPeriods) ...[
                  FFTextField(
                    key: Key('gym-trainer-pass-fee-$p'),
                    controller: _trainerPassFees[p],
                    keyboardType: TextInputType.number,
                    label: context.tr('ownerReg.trainerPassFee_$p'),
                    hint: context.tr('ownerReg.trainerPassFeeOptional'),
                    validator: _optionalFee,
                  ),
                  const SizedBox(height: FFTokens.spacingSm),
                ],
                FormField<void>(
                  validator: (_) =>
                      _passPeriods.any(
                        (p) =>
                            (num.tryParse(_trainerPassFees[p]!.text.trim()) ??
                                0) >
                            0,
                      )
                      ? null
                      : context.tr('ownerReg.trainerPassNeedsFee'),
                  builder: (field) => field.hasError
                      ? Text(
                          field.errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
              const SizedBox(height: FFTokens.spacingMd),
              FFFieldLabel(context.tr('ownerReg.mapLabel')),
              LocationPicker(
                initialLat: _lat,
                initialLng: _lng,
                height: 200,
                onChanged: (latlng) {
                  _lat = latlng.latitude;
                  _lng = latlng.longitude;
                },
              ),
              const SizedBox(height: FFTokens.spacingMd),
              FFFieldLabel(context.tr('ownerReg.imagesLabel')),
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
                              onTap: () => setState(() {
                                _images.removeAt(i);
                                if (i < _thumbnails.length) {
                                  _thumbnails.removeAt(i);
                                }
                              }),
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
