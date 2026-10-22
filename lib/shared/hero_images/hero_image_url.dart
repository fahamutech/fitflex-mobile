/// The address of a published app photo, or null when the server sent
/// anything other than a root-relative `/storage/<cid>/<file>` path.
///
/// Mirrors the portal's `heroAssetUrl`: no absolute or protocol-relative
/// addresses (so no other hosts), no percent-escapes (no `%2e` / `%2f`
/// smuggling), no `..` and no `.` segment. The path is resolved against the
/// app's own API base only, and the result must still be on that host.
Uri? heroAssetUri(Object? path, String apiBase) {
  if (path is! String) return null;
  final m = _storagePath.firstMatch(path);
  if (m == null) return null;
  final cid = m.group(1)!;
  final file = m.group(2)!;
  if ([cid, file].any((s) => s == '.' || s.contains('..'))) return null;
  final base = Uri.tryParse(apiBase.trim().replaceAll(RegExp(r'/+$'), ''));
  if (base == null ||
      !(base.isScheme('https') || base.isScheme('http')) ||
      base.host.isEmpty ||
      base.hasQuery ||
      base.hasFragment) {
    return null;
  }
  final out = Uri.tryParse('$base$path');
  if (out == null ||
      out.scheme != base.scheme ||
      out.host != base.host ||
      out.port != base.port ||
      out.path != '${base.path}$path') {
    return null;
  }
  return out;
}

final _storagePath = RegExp(
  r'^/storage/([A-Za-z0-9._~-]+)/([A-Za-z0-9._~-]+)$',
);
