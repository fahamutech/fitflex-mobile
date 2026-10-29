import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../components/ff_remote_image.dart';
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
    this.semanticLabel,
    this.profilePhoto = false,
  });

  /// Read out for the button (e.g. "Change profile photo"). Null keeps the
  /// field as before (no label of its own).

  final String? value;
  final ValueChanged<String> onChanged;
  final double size;
  final String? semanticLabel;

  /// A person's own photo: the stored Google sign-in photo may show too
  /// (see [FFRemoteImage.profilePhoto]).
  final bool profilePhoto;

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

      // Convert to WebP for a smaller payload; fall back to the raw picked
      // bytes if native compression is unavailable (e.g. some web setups).
      Uint8List? webpBytes;
      if (!kIsWeb) {
        try {
          webpBytes = await FlutterImageCompress.compressWithFile(
            file.path,
            minWidth: 800,
            minHeight: 800,
            quality: 80,
            format: CompressFormat.webp,
          );
        } catch (_) {
          webpBytes = null;
        }
      }

      if (webpBytes != null) {
        widget.onChanged('data:image/webp;base64,${base64Encode(webpBytes)}');
      } else {
        final bytes = kIsWeb
            ? await file.readAsBytes()
            : await File(file.path).readAsBytes();
        final b64 = base64Encode(bytes);
        final ext = file.name.split('.').last.toLowerCase();
        final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
        widget.onChanged('data:$mime;base64,$b64');
      }
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
    // Stored and newly picked photos alike pass the source check: no
    // request to another host (fitflex-functions#273).
    return FFRemoteImage(
      src: v,
      fit: BoxFit.cover,
      profilePhoto: widget.profilePhoto,
      fallback: const Icon(Icons.broken_image, size: 40),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.semanticLabel;
    if (label != null) {
      // A labelled, focusable button (keyboard and screen readers).
      return Semantics(
        button: true,
        label: label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const Key('ff-photo-picker-button'),
            customBorder: const CircleBorder(),
            onTap: _loading ? null : _showOptions,
            child: ExcludeSemantics(child: _picture(context)),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: _loading ? null : _showOptions,
      child: _picture(context),
    );
  }

  Widget _picture(BuildContext context) {
    return Stack(
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
    );
  }
}
