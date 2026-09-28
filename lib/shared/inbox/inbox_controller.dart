// The signed-in user's messages: booking, payment and renewal notifications
// the app already sends, plus messages from their gym and from FitFlex.
// One controller for the whole app, so the bell's unread badge, the inbox
// and push taps all agree.

import 'package:flutter/foundation.dart';

import '../api_client.dart';

/// What kind of message this is, for filtering and labels.
enum InboxCategory { membership, payments, offers, announcements, other }

class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
    this.category,
    this.gymId,
    this.campaignId,
    this.createdAt,
    this.readAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;

  /// 'transactional' | 'marketing' for gym/FitFlex messages, else null.
  final String? category;
  final String? gymId;
  final String? campaignId;
  final DateTime? createdAt;
  final DateTime? readAt;

  bool get unread => readAt == null;
  bool get fromCampaign => data['source'] == 'communication';
  String get deepLink => data['deepLink']?.toString() ?? '';
  String? get ctaLabel => _nonEmpty(data['ctaLabel']);
  String? get senderName => _nonEmpty(data['senderName']);

  InboxCategory get kind {
    if (fromCampaign) {
      if (category == 'marketing') return InboxCategory.offers;
      return switch (deepLink) {
        'membership' || 'renewal' => InboxCategory.membership,
        'payment' => InboxCategory.payments,
        _ => InboxCategory.announcements,
      };
    }
    if (type.startsWith('subscription_')) return InboxCategory.membership;
    if (type.contains('payment') || type == 'trainer_booking_confirmed') {
      return InboxCategory.payments;
    }
    return InboxCategory.other;
  }

  InboxMessage copyWith({DateTime? readAt}) => InboxMessage(
    id: id,
    type: type,
    title: title,
    body: body,
    data: data,
    category: category,
    gymId: gymId,
    campaignId: campaignId,
    createdAt: createdAt,
    readAt: readAt ?? this.readAt,
  );

  factory InboxMessage.fromJson(Map<String, dynamic> j) => InboxMessage(
    id: j['id'].toString(),
    type: j['type']?.toString() ?? '',
    title: j['title']?.toString() ?? '',
    body: j['body']?.toString() ?? '',
    data: (j['data'] as Map?)?.cast<String, dynamic>() ?? const {},
    category: j['category']?.toString(),
    gymId: j['gymId']?.toString(),
    campaignId: j['campaignId']?.toString(),
    createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal(),
    readAt: DateTime.tryParse(j['readAt']?.toString() ?? '')?.toLocal(),
  );

  static String? _nonEmpty(dynamic v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty ? null : s;
  }
}

/// Where a message's button (or a tap on its push) takes a member. Null
/// means "show the message itself". Only fixed app screens are allowed.
String? memberRouteFor({
  required String deepLink,
  required String type,
  String? gymId,
  String? trainerId,
}) {
  final link = deepLink.isNotEmpty
      ? deepLink
      : switch (type) {
          'subscription_renewal' || 'subscription_activated' => 'membership',
          // A trainer answered the member's enquiry: open that trainer.
          'trainer_enquiry_reply' => 'trainer',
          _ => '',
        };
  return switch (link) {
    'membership' || 'renewal' => '/member/passes',
    'payment' => '/member/payment',
    'gym' when gymId != null && gymId.isNotEmpty => '/member/gyms/$gymId',
    'trainer' when trainerId != null && _safeId.hasMatch(trainerId) =>
      '/member/trainers/$trainerId',
    _ => null,
  };
}

final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

class InboxController extends ChangeNotifier {
  InboxController(this._api);

  final ApiClient _api;

  List<InboxMessage> _messages = const [];
  int _unread = 0;
  bool _loading = false;
  Object? _error;

  List<InboxMessage> get messages => _messages;
  int get unread => _unread;
  bool get loading => _loading;
  Object? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _api.notifications();
      _messages = ((res['notifications'] as List?) ?? const [])
          .map((n) => InboxMessage.fromJson((n as Map).cast()))
          .toList();
      _unread = (res['unread'] as num?)?.toInt() ?? 0;
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Signed out: nothing from the last person may linger.
  void clear() {
    _messages = const [];
    _unread = 0;
    _error = null;
    notifyListeners();
  }

  InboxMessage? byId(String id) =>
      _messages.where((m) => m.id == id).firstOrNull;

  Future<void> markRead(String id) async {
    final m = byId(id);
    if (m != null && !m.unread) return;
    _setRead(id);
    try {
      await _api.markNotificationRead(id);
    } catch (_) {
      // Reading must never fail for the member; the server catches up.
    }
  }

  Future<void> markAllRead() async {
    _messages = [
      for (final m in _messages)
        m.unread ? m.copyWith(readAt: DateTime.now()) : m,
    ];
    _unread = 0;
    notifyListeners();
    try {
      await _api.markNotificationRead('all');
    } catch (_) {}
  }

  /// The member tapped the message's button (or its push).
  Future<void> click(String id, {String via = 'inbox'}) async {
    _setRead(id);
    try {
      await _api.clickNotification(id, via: via);
    } catch (_) {}
  }

  /// A push was tapped: records that the push was opened and its inbox
  /// copy read, and returns that copy (loading the inbox if needed). Null
  /// for a push with no inbox copy — the caller follows its link instead.
  Future<InboxMessage?> openFromPush(Map<String, dynamic> data) async {
    final messageId = data['messageId']?.toString() ?? '';
    if (data['source'] == 'communication' && messageId.isNotEmpty) {
      try {
        await _api.pushMessageOpened(messageId);
      } catch (_) {}
    }
    final id = data['notificationId']?.toString() ?? '';
    if (id.isEmpty) return null;
    if (byId(id) == null) await load();
    await markRead(id);
    return byId(id);
  }

  void _setRead(String id) {
    final i = _messages.indexWhere((m) => m.id == id && m.unread);
    if (i < 0) return;
    _messages = [..._messages]
      ..[i] = _messages[i].copyWith(readAt: DateTime.now());
    if (_unread > 0) _unread -= 1;
    notifyListeners();
  }
}
