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
  /// A request to connect: answered with Approve / Reject on the card.
  bool get isFriendInvitation => type == 'friend_invitation';
  String get friendStatus => data['status']?.toString() ?? 'pending';
  String? get invitationId => _nonEmpty(data['invitationId']);
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

  InboxMessage copyWith({DateTime? readAt, Map<String, dynamic>? data}) =>
      InboxMessage(
    id: id,
    type: type,
    title: title,
    body: body,
    data: data ?? this.data,
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

/// The kind of screen a message leads to (`membership`, `trainer`,
/// `trainingOffer`…), from its own link or, failing that, its type. Empty
/// when it leads nowhere. Also names the button: `inbox.open.<link>`.
String memberLinkFor({required String deepLink, required String type}) =>
    deepLink.isNotEmpty
    ? deepLink
    : switch (type) {
        'subscription_renewal' || 'subscription_activated' => 'membership',
        // A trainer answered the member's enquiry: open that trainer.
        'trainer_enquiry_reply' => 'trainer',
        // A trainer made the member a plan: open the offer to answer it.
        'training_plan_offered' => 'trainingOffer',
        // Their trainer changed or stopped the plan they are on.
        'training_plan_updated' || 'training_plan_stopped' => 'trainingPlan',
        _ => '',
      };

/// Messages whose push opens their screen directly, not the message: the
/// screen says everything the message does, and is where the member acts.
bool opensScreenDirectly(String type) =>
    memberLinkFor(deepLink: '', type: type).startsWith('training');

/// Where a message's button (or a tap on its push) takes a member. Null
/// means "show the message itself". Only fixed app screens are allowed.
String? memberRouteFor({
  required String deepLink,
  required String type,
  String? gymId,
  String? trainerId,
  String? planId,
}) {
  final link = memberLinkFor(deepLink: deepLink, type: type);
  return switch (link) {
    'membership' || 'renewal' => '/member/passes',
    'payment' => '/member/payment',
    'gym' when gymId != null && gymId.isNotEmpty => '/member/gyms/$gymId',
    'trainer' when trainerId != null && _safeId.hasMatch(trainerId) =>
      '/member/trainers/$trainerId',
    'trainingOffer' when planId != null && _safeId.hasMatch(planId) =>
      '/member/activity/training/offers/$planId',
    'trainingPlan' => '/member/activity/training',
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

  final Set<String> _answering = {};
  bool isAnswering(String id) => _answering.contains(id);

  /// Approve or reject a friend invitation from its card. Returns the
  /// invitation's status afterwards, or null if it couldn't be answered
  /// (the card then stays as it was and the member can retry).
  Future<String?> answerFriendInvitation(String id, {required bool approve}) async {
    final m = byId(id);
    final invitationId = m?.invitationId;
    if (m == null || invitationId == null || _answering.contains(id)) return null;
    _answering.add(id);
    notifyListeners();
    try {
      final res = approve
          ? await _api.approveFriendInvitation(invitationId)
          : await _api.rejectFriendInvitation(invitationId);
      final status =
          ((res['invitation'] as Map?)?['status'] ?? (approve ? 'accepted' : 'rejected'))
              .toString();
      _setStatus(id, status);
      return status;
    } catch (e) {
      // Already answered elsewhere, expired, or withdrawn: show what is true now.
      final status = _statusFromError(e);
      if (status != null) {
        _setStatus(id, status);
        return status;
      }
      return null;
    } finally {
      _answering.remove(id);
      notifyListeners();
    }
  }

  static String? _statusFromError(Object e) {
    final code = e is ApiException ? e.code : null;
    for (final s in const ['accepted', 'rejected', 'expired', 'revoked']) {
      if (code == 'invitation_$s') return s;
    }
    return null;
  }

  void _setStatus(String id, String status) {
    final i = _messages.indexWhere((m) => m.id == id);
    if (i < 0) return;
    final wasUnread = _messages[i].unread;
    _messages = [..._messages]
      ..[i] = _messages[i].copyWith(
        readAt: DateTime.now(),
        data: {..._messages[i].data, 'status': status},
      );
    if (wasUnread && _unread > 0) _unread -= 1;
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
