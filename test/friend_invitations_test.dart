// Friend invitations in Notifications: Approve / Reject sit on the card,
// answering updates it, and stale answers show what is true now.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';
import 'package:fitflexmobile/shared/inbox/inbox_pages.dart';

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://localhost:0');
  final calls = <String>[];
  String? failWith; // error code the server answers with
  Map<String, dynamic> row = {
    'id': 'ntf_fi_1',
    'type': 'friend_invitation',
    'title': 'Friend invitation',
    'body': 'Neema Star wants to connect with you on FitFlex Africa.',
    'createdAt': DateTime.now().toIso8601String(),
    'readAt': null,
    'data': {
      'type': 'friend_invitation',
      'invitationId': 'fri_1',
      'inviterName': 'Neema Star',
      'status': 'pending',
    },
  };

  @override
  Future<Map<String, dynamic>> notifications() async => {
    'notifications': [row],
    'unread': row['readAt'] == null ? 1 : 0,
  };

  @override
  Future<Map<String, dynamic>> approveFriendInvitation(String id) async {
    calls.add('approve:$id');
    if (failWith != null) throw ApiException(409, {'error': failWith});
    return {'invitation': {'id': id, 'status': 'accepted'}};
  }

  @override
  Future<Map<String, dynamic>> rejectFriendInvitation(String id) async {
    calls.add('reject:$id');
    if (failWith != null) throw ApiException(409, {'error': failWith});
    return {'invitation': {'id': id, 'status': 'rejected'}};
  }

  @override
  Future<void> markNotificationRead(String id) async {}
}

Widget _app(_FakeApi api, InboxController inbox) {
  final router = GoRouter(
    initialLocation: '/inbox',
    routes: [GoRoute(path: '/inbox', builder: (_, _) => const InboxPage())],
  );
  return AppScope(
    api: api,
    auth: AuthState(api),
    inbox: inbox,
    child: FFLocaleScope(
      notifier: FFLocale(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

void main() {
  test('controller approves once and marks the card accepted', () async {
    final api = _FakeApi();
    final inbox = InboxController(api);
    await inbox.load();
    expect(inbox.byId('ntf_fi_1')!.isFriendInvitation, isTrue);
    final status = await inbox.answerFriendInvitation('ntf_fi_1', approve: true);
    expect(status, 'accepted');
    expect(inbox.byId('ntf_fi_1')!.friendStatus, 'accepted');
    expect(inbox.unread, 0);
    expect(api.calls, ['approve:fri_1']);
  });

  test('an invitation already answered elsewhere shows its real state', () async {
    final api = _FakeApi()..failWith = 'invitation_rejected';
    final inbox = InboxController(api);
    await inbox.load();
    final status = await inbox.answerFriendInvitation('ntf_fi_1', approve: true);
    expect(status, 'rejected');
    expect(inbox.byId('ntf_fi_1')!.friendStatus, 'rejected');
  });

  test('a network failure leaves the card pending for a retry', () async {
    final api = _FakeApi()..failWith = 'boom';
    final inbox = InboxController(api);
    await inbox.load();
    expect(await inbox.answerFriendInvitation('ntf_fi_1', approve: false), isNull);
    expect(inbox.byId('ntf_fi_1')!.friendStatus, 'pending');
  });

  testWidgets('Approve and Reject are on the notification card', (tester) async {
    final api = _FakeApi();
    final inbox = InboxController(api);
    await tester.pumpWidget(_app(api, inbox));
    await tester.pumpAndSettle();
    expect(find.text('Friend invitation'), findsOneWidget);
    expect(
      find.text('Neema Star wants to connect with you on FitFlex Africa.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('invite-approve-ntf_fi_1')), findsOneWidget);
    expect(find.byKey(const Key('invite-reject-ntf_fi_1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('invite-approve-ntf_fi_1')));
    await tester.pumpAndSettle();
    expect(api.calls, ['approve:fri_1']);
    expect(find.byKey(const Key('invite-approve-ntf_fi_1')), findsNothing);
    expect(find.byKey(const Key('invite-status-ntf_fi_1')), findsOneWidget);
  });

  testWidgets('Reject answers without a detail screen', (tester) async {
    final api = _FakeApi();
    final inbox = InboxController(api);
    await tester.pumpWidget(_app(api, inbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('invite-reject-ntf_fi_1')));
    await tester.pumpAndSettle();
    expect(api.calls, ['reject:fri_1']);
    expect(find.text('Declined'), findsOneWidget);
  });
}
