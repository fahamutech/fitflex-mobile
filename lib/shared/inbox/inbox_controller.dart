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
        // Their trainer recorded that they missed a session: open it.
        'trainer_booking_no_show' => 'session',
        // A running event (events S2; a future `event` notice type with
        // `data.eventId`): open the event, or the list without an id.
        'event' => 'event',
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
  String? bookingId,
  String? eventId,
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
    'session' when bookingId != null && _safeId.hasMatch(bookingId) => Uri(
      path: '/member/sessions',
      queryParameters: {'booking': bookingId},
    ).toString(),
    'session' => '/member/sessions',
    'event' when eventId != null && _safeId.hasMatch(eventId) =>
      '/member/events/$eventId',
    'event' => '/member/events',
    _ => null,
  };
}

/// Where a tapped push takes the signed-in user: `go` replaces the stack
/// with a screen; otherwise the location is pushed over it. Members with a
/// plan from their trainer, and partners with news about one of their
/// screens, go straight there; anything else (a gym or FitFlex campaign,
/// for every role) opens its in-app copy, or the inbox when there is none.
({String location, bool go}) pushTargetFor({
  required String? role,
  required Map<String, dynamic> data,
  InboxMessage? message,
}) {
  final type = data['type']?.toString() ?? '';
  // A plan from their trainer opens on the plan itself, where they answer.
  if (role == 'member' && opensScreenDirectly(type)) {
    final direct = memberRouteFor(
      deepLink: '',
      type: type,
      planId: data['planId']?.toString(),
    );
    if (direct != null) return (location: direct, go: true);
  }
  // Trainers, vendors and gyms go straight to the screen the news is about.
  if (partnerSide(role) case final side?) {
    final direct = partnerRouteFor(
      side: side,
      type: type,
      gymId: data['gymId']?.toString(),
      memberId: data['memberId']?.toString(),
      productId: data['productId']?.toString(),
      variant: data['variant']?.toString(),
      saleId: data['saleId']?.toString(),
      customerId: data['customerId']?.toString(),
      bannerId: (data['bannerId'] ?? data['item'])?.toString(),
    );
    if (direct != null) return (location: direct, go: true);
  }
  if (message != null) {
    // A friend request is answered on its card in the list.
    return (
      location: message.isFriendInvitation ? '/inbox' : '/inbox/${message.id}',
      go: false,
    );
  }
  final route = role == 'member'
      ? memberRouteFor(
          deepLink: data['deepLink']?.toString() ?? '',
          type: type,
          gymId: data['gymId']?.toString(),
          trainerId: data['trainerId']?.toString(),
          planId: data['planId']?.toString(),
          bookingId: data['bookingId']?.toString(),
          eventId: data['eventId']?.toString(),
        )
      : null;
  if (route != null) return (location: route, go: true);
  return (location: '/inbox', go: false);
}

/// A notice's words in the app language. Some notices carry both languages
/// in their data (`titleEn`/`bodyEn`, `titleSw`/`bodySw`, e.g.
/// trainer_booking_no_show), while the top-level title/body follow the
/// member's saved `locale`, which may differ from the app's. The app
/// language's copy wins; a missing line keeps the server's text.
({String title, String body}) localisedNoticeText({
  required String lang,
  required Map<String, dynamic> data,
  required String title,
  required String body,
}) {
  final suffix = lang == 'sw' ? 'Sw' : 'En';
  final t = data['title$suffix']?.toString().trim() ?? '';
  final b = data['body$suffix']?.toString().trim() ?? '';
  return (title: t.isEmpty ? title : t, body: b.isEmpty ? body : b);
}

final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

// ── Trainers, vendors and gyms ──────────────────────────────────────────────

/// The side of FitFlex a signed-in partner works on, from their account
/// type: `trainer`, `vendor` (and vendor staff) or `gym` (owner and staff).
/// Null for members and anyone else.
String? partnerSide(String? userType) => switch (userType) {
  'trainer' => 'trainer',
  'vendor' || 'vendor_staff' => 'vendor',
  'gym_operator' || 'gym_staff' => 'gym',
  _ => null,
};

/// The kind of screen a partner's message leads to — also the name of its
/// button (`inbox.open.<link>`). Empty when the message leads nowhere, or
/// isn't one this side of the app receives.
String partnerLinkFor({required String side, required String type}) =>
    switch (side) {
      'trainer' => switch (type) {
        'trainer_client_request' ||
        'training_plan_accepted' ||
        'training_plan_declined' ||
        'training_plan_stopped' => 'clients',
        'trainer_booking_requested' ||
        'trainer_booking_confirmed' ||
        'trainer_booking_cancelled' => 'sessions',
        'trainer_enquiry' || 'trainer_interest' => 'enquiries',
        'trainer_payout_paid' => 'payouts',
        _ => '',
      },
      'vendor' => switch (type) {
        'vendor_new_order' || 'vendor_order_cancelled' => 'orders',
        'vendor_customer_enquiry' => 'customerQuestions',
        'vendor_product_approved' || 'vendor_product_rejected' => 'products',
        'vendor_payout_paid' => 'payments',
        'vendor_low_stock' => 'lowStock',
        // S3: a walk-in sale was voided (sent to the vendor account).
        'vendor_sale_voided' => 'sale',
        // S4: the daily overdue digest, and a payment voided by staff.
        'vendor_customers_overdue' => 'owed',
        'vendor_customer_payment_voided' => 'customer',
        // S5: a KYC reviewer verified or did not accept the VAT details
        // (push data.open = 'tax').
        'vendor_vat_verified' || 'vendor_vat_rejected' => 'tax',
        // Shop home Phase 2 S1: a banner was approved, rejected, expired or
        // ended by FitFlex (push `vendor_shop_banner_*`, inbox
        // `shop_banner_*`).
        'vendor_shop_banner_approved' ||
        'vendor_shop_banner_rejected' ||
        'vendor_shop_banner_expired' ||
        'vendor_shop_banner_ended' ||
        'shop_banner_approved' ||
        'shop_banner_rejected' ||
        'shop_banner_expired' ||
        'shop_banner_ended' => 'merch',
        _ => '',
      },
      'gym' => switch (type) {
        'gym_checkin' => 'checkins',
        'gym_member_joined' => 'member',
        // A renewal is a payment: open what that member has paid.
        'gym_membership_renewed' => 'memberPayments',
        'gym_trainer_request' => 'gymTrainers',
        'gym_review' => 'gyms',
        'gym_statement_approved' || 'gym_payout_paid' => 'earnings',
        _ => '',
      },
      _ => '',
    };

/// Where a partner's message (or a tap on its push) takes them. Null means
/// "show the message itself". Only fixed app screens; ids are checked.
String? partnerRouteFor({
  required String side,
  required String type,
  String? gymId,
  String? memberId,
  String? productId,
  String? variant,
  String? saleId,
  String? customerId,
  String? bannerId,
}) {
  bool ok(String? id) => id != null && _safeId.hasMatch(id);
  return switch (partnerLinkFor(side: side, type: type)) {
    // Trainers and vendors work from one home screen: say which part.
    'clients' => '/trainer/home?open=clients',
    'sessions' => '/trainer/home?open=sessions',
    'enquiries' => '/trainer/home?open=enquiries',
    'payouts' => '/trainer/home?open=payouts',
    'orders' => '/vendor/home?open=orders',
    'customerQuestions' => '/vendor/home?open=enquiries',
    'products' => '/vendor/home?open=products',
    'payments' => '/vendor/home?open=payments',
    // Low stock: that product's stock history (the screen checks the ledger
    // is on and the person may see products); else the low products.
    'lowStock' when ok(productId) => Uri(
      path: '/vendor/products/$productId/stock',
      queryParameters: {
        if (variant != null && variant.isNotEmpty) 'variant': variant,
        'from': 'push',
      },
    ).toString(),
    'lowStock' => '/vendor/home?open=products&filter=low',
    // The sale detail checks the feature and the `sales` permission.
    'sale' when ok(saleId) => '/vendor/sales/$saleId',
    'sale' => '/vendor/home?open=sales',
    // The customer pages check the feature and the `customers` permission.
    'owed' => '/vendor/home?open=customers&view=owed',
    'customer' when ok(customerId) => '/vendor/customers/$customerId',
    'customer' => '/vendor/home?open=customers',
    // The page checks the `vat` tool and who may see it.
    'tax' => '/vendor/settings/tax',
    // The Promotions page checks the tool and the `products` permission.
    'merch' when ok(bannerId) => '/vendor/merch?item=$bannerId',
    'merch' => '/vendor/merch',
    'checkins' when ok(gymId) => '/owner/gyms/$gymId/checkins',
    'member' when ok(memberId) => '/owner/members/$memberId',
    'memberPayments' when ok(memberId) => '/owner/members/$memberId/payments',
    'gymTrainers' => '/owner/trainers',
    'gyms' => '/owner/gyms',
    'earnings' => '/owner/earnings',
    _ => null,
  };
}

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
  Future<String?> answerFriendInvitation(
    String id, {
    required bool approve,
  }) async {
    final m = byId(id);
    final invitationId = m?.invitationId;
    if (m == null || invitationId == null || _answering.contains(id)) {
      return null;
    }
    _answering.add(id);
    notifyListeners();
    try {
      final res = approve
          ? await _api.approveFriendInvitation(invitationId)
          : await _api.rejectFriendInvitation(invitationId);
      final status =
          ((res['invitation'] as Map?)?['status'] ??
                  (approve ? 'accepted' : 'rejected'))
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
