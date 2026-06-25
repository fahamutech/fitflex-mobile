import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../i18n.dart';

/// A form-friendly photo picker that lets the user choose from the gallery
/// or capture a photo with the camera.
///
/// [value] is the current photo URL (remote URL or base64 data-URL).
/// [onChanged] is called with the new base64 data-URL after picking.
class FFPhotoPickerField extends StatefulWidget {
  const FFPhotoPickerField({
    super.key,
    this.value,
    required this.onChanged,
    this.size = 96.0,
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final double size;

  @override
  State<FFPhotoPickerField> createState() => _FFPhotoPickerFieldState();
}

class _FFPhotoPickerFieldState extends State<FFPhotoPickerField> {
  final _picker = ImagePicker();
  bool _loading = false;

  Future<void> _pick(ImageSource source) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );
      if (file == null || !mounted) return;
      final bytes = kIsWeb
          ? await file.readAsBytes()
          : await File(file.path).readAsBytes();
      final b64 = base64Encode(bytes);
      final ext = file.name.split('.').last.toLowerCase();
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      widget.onChanged('data:$mime;base64,$b64');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showOptions() {
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
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(ctx.tr('photo.gallery')),
              onTap: () {
                Navigator.of(ctx).pop();
                _pick(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final v = widget.value;
    if (v == null || v.isEmpty) {
      return Icon(
        Icons.person,
        size: 40,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      );
    }
    if (v.startsWith('data:')) {
      final b64 = v.split(',').last;
      return Image.memory(base64Decode(b64), fit: BoxFit.cover);
    }
    return Image.network(
      v,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stack) =>
          const Icon(Icons.broken_image, size: 40),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _loading ? null : _showOptions,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : ClipOval(child: _buildPreview()),
          ),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary,
              border: Border.all(
                color: Theme.of(context).colorScheme.onPrimary,
                width: 2,
              ),
            ),
            child: Icon(
              Icons.camera_alt,
              size: 14,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
