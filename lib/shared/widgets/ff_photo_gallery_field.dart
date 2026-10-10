import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../design_tokens.dart';
import '../i18n.dart';

/// Several photos for a profile: add from the gallery or camera, remove, and
/// choose which one is the profile picture (always the first).
///
/// [values] are remote URLs or base64 data-URLs, as stored. [onChanged] gets
/// the new list after every change.
class FFPhotoGalleryField extends StatefulWidget {
  const FFPhotoGalleryField({
    super.key,
    required this.values,
    required this.onChanged,
    this.max = 6,
  });

  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final int max;

  @override
  State<FFPhotoGalleryField> createState() => _FFPhotoGalleryFieldState();
}

class _FFPhotoGalleryFieldState extends State<FFPhotoGalleryField> {
  final _picker = ImagePicker();
  bool _loading = false;

  int get _room => widget.max - widget.values.length;

  Future<String> _encode(XFile file) async {
    // WebP keeps the payload small; fall back to the picked bytes where
    // native compression isn't available (web).
    if (!kIsWeb) {
      try {
        final webp = await FlutterImageCompress.compressWithFile(
          file.path,
          minWidth: 1024,
          minHeight: 1024,
          quality: 75,
          format: CompressFormat.webp,
        );
        if (webp != null) return 'data:image/webp;base64,${base64Encode(webp)}';
      } catch (_) {
        // fall through to the raw bytes
      }
    }
    final bytes = kIsWeb
        ? await file.readAsBytes()
        : await File(file.path).readAsBytes();
    final ext = file.name.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  Future<void> _add(ImageSource? camera) async {
    if (_loading || _room <= 0) return;
    setState(() => _loading = true);
    try {
      final picked = camera != null
          ? [
              await _picker.pickImage(
                source: camera,
                maxWidth: 1024,
                maxHeight: 1024,
                imageQuality: 75,
              ),
            ].whereType<XFile>().toList()
          : await _picker.pickMultiImage(
              maxWidth: 1024,
              maxHeight: 1024,
              imageQuality: 75,
            );
      if (picked.isEmpty || !mounted) return;
      final added = <String>[];
      for (final f in picked.take(_room)) {
        added.add(await _encode(f));
      }
      if (!mounted) return;
      widget.onChanged([...widget.values, ...added]);
      if (picked.length > added.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('photos.max').replaceAll('{n}', '${widget.max}'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAddOptions() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(ctx.tr('photo.camera')),
              onTap: () {
                Navigator.of(ctx).pop();
                _add(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(ctx.tr('photo.gallery')),
              onTap: () {
                Navigator.of(ctx).pop();
                _add(null);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _remove(int i) => widget.onChanged([...widget.values]..removeAt(i));

  void _makeFirst(int i) {
    final next = [...widget.values];
    next.insert(0, next.removeAt(i));
    widget.onChanged(next);
  }

  Widget _image(String v) {
    const broken = Center(child: Icon(Icons.broken_image));
    if (v.startsWith('data:')) {
      // A damaged stored photo must not take the whole form down.
      try {
        return Image.memory(
          base64Decode(v.split(',').last),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => broken,
        );
      } on FormatException {
        return broken;
      }
    }
    return Image.network(
      v,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stack) =>
          const Center(child: Icon(Icons.broken_image)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const size = 92.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, v) in widget.values.indexed)
              SizedBox(
                key: Key('photo-gallery-item-$i'),
                width: size,
                height: size,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(FFTokens.radiusLg),
                      child: InkWell(
                        onTap: i == 0 ? null : () => _makeFirst(i),
                        child: _image(v),
                      ),
                    ),
                    if (i == 0)
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: FFTokens.brand500,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            context.tr('photos.profile'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: InkWell(
                          key: Key('photo-gallery-remove-$i'),
                          customBorder: const CircleBorder(),
                          onTap: () => _remove(i),
                          child: const Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_room > 0)
              InkWell(
                key: const Key('photo-gallery-add'),
                onTap: _loading ? null : _showAddOptions,
                borderRadius: BorderRadius.circular(FFTokens.radiusLg),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(FFTokens.radiusLg),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Center(
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.add_a_photo_outlined,
                            color: scheme.primary,
                          ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          context.tr('photos.hint').replaceAll('{n}', '${widget.max}'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
