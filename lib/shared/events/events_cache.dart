import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The last good answers, for low-bandwidth and offline use (spec §11.8):
/// page 1 of the default list and the last [maxDetails] opened details. Held
/// in memory and in SharedPreferences (the store the app already uses); a
/// failed read or write is ignored. Nothing in `member_gyms_tab` keeps an
/// offline list, so this is the module's own small store.
class EventsCache {
  EventsCache._();

  static const listKey = 'events.cache.list.default';
  static const detailPrefix = 'events.cache.detail.';
  static const detailIndexKey = 'events.cache.detail.index';
  static const maxDetails = 10;

  static Map<String, dynamic>? _list;
  static DateTime? _listAt;
  static final Map<String, (DateTime, Map<String, dynamic>)> _details = {};

  /// Forget everything (tests).
  static void reset() {
    _list = null;
    _listAt = null;
    _details.clear();
  }

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  static Future<void> putList(Map<String, dynamic> page) async {
    _list = page;
    _listAt = DateTime.now();
    final p = await _prefs();
    try {
      await p?.setString(
        listKey,
        jsonEncode({'at': _listAt!.toIso8601String(), 'page': page}),
      );
    } catch (_) {}
  }

  /// The cached default list and when it was saved, or null.
  static Future<(DateTime, Map<String, dynamic>)?> getList() async {
    if (_list != null) return (_listAt!, _list!);
    final p = await _prefs();
    final raw = p?.getString(listKey);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map;
      final at = DateTime.tryParse(m['at']?.toString() ?? '') ?? DateTime.now();
      final page = Map<String, dynamic>.from(m['page'] as Map);
      _list = page;
      _listAt = at;
      return (at, page);
    } catch (_) {
      return null;
    }
  }

  static Future<void> putDetail(String id, Map<String, dynamic> json) async {
    final now = DateTime.now();
    _details[id] = (now, json);
    final p = await _prefs();
    if (p == null) return;
    try {
      final index = (p.getStringList(detailIndexKey) ?? [])..remove(id);
      index.insert(0, id);
      while (index.length > maxDetails) {
        final dropped = index.removeLast();
        await p.remove('$detailPrefix$dropped');
        _details.remove(dropped);
      }
      await p.setStringList(detailIndexKey, index);
      await p.setString(
        '$detailPrefix$id',
        jsonEncode({'at': now.toIso8601String(), 'detail': json}),
      );
    } catch (_) {}
  }

  static Future<(DateTime, Map<String, dynamic>)?> getDetail(String id) async {
    final hit = _details[id];
    if (hit != null) return hit;
    final p = await _prefs();
    final raw = p?.getString('$detailPrefix$id');
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map;
      final at = DateTime.tryParse(m['at']?.toString() ?? '') ?? DateTime.now();
      final detail = Map<String, dynamic>.from(m['detail'] as Map);
      _details[id] = (at, detail);
      return (at, detail);
    } catch (_) {
      return null;
    }
  }
}
