import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../components/components.dart';
import '../design_tokens.dart';
import '../i18n.dart';
import '../models.dart';

/// Instagram / Facebook / X — the same list and order as the backend.
const socialPlatforms = ['instagram', 'facebook', 'twitter'];

const _hosts = {
  'instagram': ['instagram.com', 'instagr.am'],
  'facebook': ['facebook.com', 'fb.com', 'm.facebook.com'],
  'twitter': ['twitter.com', 'x.com', 'mobile.twitter.com'],
};

final _handleRe = RegExp(r'^[A-Za-z0-9._-]{1,50}$');
final _fbNumericRe = RegExp(r'^profile\.php\?id=\d{1,30}$');

/// Mirrors the backend rule: accepts `handle`, `@handle` or a profile URL and
/// returns the bare handle, '' for an empty value, or null when invalid.
String? normalizeSocialHandle(String platform, String? value) {
  var v = (value ?? '').trim();
  if (v.isEmpty) return '';
  if (RegExp(
    r'^(https?://)?(www\.)?[a-z.]+\.[a-z]{2,}/',
    caseSensitive: false,
  ).hasMatch(v)) {
    final uri = Uri.tryParse(
      RegExp(r'^https?://', caseSensitive: false).hasMatch(v)
          ? v
          : 'https://$v',
    );
    if (uri == null) return null;
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (!(_hosts[platform] ?? const []).contains(host)) return null;
    if (platform == 'facebook' && uri.path == '/profile.php') {
      final id = uri.queryParameters['id'] ?? '';
      return RegExp(r'^\d{1,30}$').hasMatch(id) ? 'profile.php?id=$id' : null;
    }
    v = uri.pathSegments.where((s) => s.isNotEmpty).firstOrNull ?? '';
  }
  if (platform == 'facebook' && _fbNumericRe.hasMatch(v)) return v;
  v = v.replaceFirst(RegExp(r'^@'), '');
  return _handleRe.hasMatch(v) ? v : null;
}

/// Public profile URL for a stored handle.
Uri socialProfileUri(String platform, String handle) => switch (platform) {
  'instagram' => Uri.parse('https://www.instagram.com/$handle'),
  'facebook' => Uri.parse('https://www.facebook.com/$handle'),
  _ => Uri.parse('https://x.com/$handle'),
};

String socialPlatformLabel(String platform) => switch (platform) {
  'instagram' => 'Instagram',
  'facebook' => 'Facebook',
  _ => 'X',
};

Widget _platformIcon(String platform, {double size = 18, Color? color}) =>
    switch (platform) {
      'instagram' => Icon(Icons.camera_alt_outlined, size: size, color: color),
      'facebook' => Icon(Icons.facebook, size: size, color: color),
      _ => SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            '𝕏',
            style: TextStyle(
              fontSize: size * .8,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1,
            ),
          ),
        ),
      ),
    };

Map<String, String> _present(SocialLinks links) => {
  if (links.instagram != null) 'instagram': links.instagram!,
  if (links.facebook != null) 'facebook': links.facebook!,
  if (links.twitter != null) 'twitter': links.twitter!,
};

/// Tappable social profiles. [compact] shows icon buttons only (hero cards);
/// otherwise pills with the handle. Opens the platform app/site externally.
class SocialLinksRow extends StatelessWidget {
  const SocialLinksRow({super.key, required this.links, this.compact = false});

  final SocialLinks links;
  final bool compact;

  Future<void> _open(
    BuildContext context,
    String platform,
    String handle,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr('social.openFailed');
    var ok = false;
    try {
      ok = await launchUrl(
        socialProfileUri(platform, handle),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      ok = false;
    }
    if (!ok) messenger.showSnackBar(SnackBar(content: Text(failed)));
  }

  @override
  Widget build(BuildContext context) {
    final present = _present(links);
    if (present.isEmpty) return const SizedBox.shrink();
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: present.entries
            .map(
              (e) => IconButton(
                key: Key('social-${e.key}'),
                tooltip: socialPlatformLabel(e.key),
                visualDensity: VisualDensity.compact,
                onPressed: () => _open(context, e.key, e.value),
                icon: _platformIcon(e.key, size: 20),
              ),
            )
            .toList(),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: present.entries.map((e) {
        final label = e.key == 'facebook' && e.value.startsWith('profile.php')
            ? socialPlatformLabel(e.key)
            : '@${e.value}';
        return Semantics(
          button: true,
          label: '${socialPlatformLabel(e.key)} $label',
          child: ActionChip(
            key: Key('social-${e.key}'),
            avatar: _platformIcon(e.key, size: 16, color: FFTokens.brand500),
            label: Text(label),
            onPressed: () => _open(context, e.key, e.value),
          ),
        );
      }).toList(),
    );
  }
}

/// Three optional inputs (Instagram / Facebook / X) that accept a handle,
/// @handle or profile link and validate with the backend's rule.
class SocialHandleFields extends StatelessWidget {
  const SocialHandleFields({super.key, required this.controllers});

  /// One controller per entry of [socialPlatforms].
  final Map<String, TextEditingController> controllers;

  static Map<String, TextEditingController> controllersFor(SocialLinks links) {
    final json = links.toJson();
    return {
      for (final p in socialPlatforms)
        p: TextEditingController(text: json[p] ?? ''),
    };
  }

  /// Cleaned `{ instagram, facebook, twitter }` ('' clears a handle).
  static Map<String, String> valuesOf(
    Map<String, TextEditingController> controllers,
  ) => {
    for (final p in socialPlatforms)
      p: normalizeSocialHandle(p, controllers[p]?.text) ?? '',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in socialPlatforms) ...[
          FFTextField(
            key: Key('social-field-$p'),
            controller: controllers[p],
            label: socialPlatformLabel(p),
            hint: context.tr('social.handleHint'),
            prefixIcon: _platformIcon(p),
            keyboardType: TextInputType.url,
            validator: (v) => normalizeSocialHandle(p, v) == null
                ? context.tr('social.invalidHandle')
                : null,
          ),
          const SizedBox(height: FFTokens.spacingSm),
        ],
      ],
    );
  }
}
