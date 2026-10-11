// Friend invitations: the Approve / Reject card actions, the native share of
// a personal invitation link, and the page an invitation link opens.
//
// FitFlex never sends an invitation itself. The inviter shares the composed
// message through the device's share sheet (WhatsApp, SMS, email, …) and any
// SMS charge is theirs; opening the sheet says nothing about delivery.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../router.dart';
import 'api_client.dart' show ApiException;
import 'api_error_message.dart';
import 'components/components.dart';
import 'design_tokens.dart';
import 'i18n.dart';
import 'inbox/inbox_controller.dart';

/// The invitation token a signed-out visitor arrived with, kept through
/// sign-in / registration so it can be claimed afterwards.
class PendingFriendInvite {
  static const _key = 'pending_friend_invite_token';

  static Future<void> save(String token) async {
    try {
      (await SharedPreferences.getInstance()).setString(_key, token);
    } catch (_) {}
  }

  /// Returns and clears the saved token.
  static Future<String?> take() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_key);
      if (token != null) await prefs.remove(_key);
      return token;
    } catch (_) {
      return null;
    }
  }
}

/// Opens the native share sheet with the invitation message. If the device
/// has no sharing app (or sharing fails), offers copy-message / copy-link.
/// Returns true when the share sheet was shown — not that anything was sent.
Future<bool> shareFriendInvite(
  BuildContext context, {
  required String text,
  required String link,
  String? subject,
}) async {
  try {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
    return true;
  } catch (_) {
    if (!context.mounted) return false;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('invite-copy-message'),
              leading: const Icon(Icons.copy),
              title: Text(context.tr('friendInvite.copyMessage')),
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              key: const Key('invite-copy-link'),
              leading: const Icon(Icons.link),
              title: Text(context.tr('friendInvite.copyLink')),
              onTap: () {
                Clipboard.setData(ClipboardData(text: link));
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
    return false;
  }
}

/// Approve / Reject on an inbox card. Shown for pending requests; once
/// answered the card shows the outcome instead of buttons.
class FriendInvitationActions extends StatelessWidget {
  const FriendInvitationActions({
    super.key,
    required this.message,
    required this.inbox,
  });

  final InboxMessage message;
  final InboxController inbox;

  Future<void> _answer(BuildContext context, bool approve) async {
    final messenger = ScaffoldMessenger.of(context);
    final t = context.tr;
    final done = await inbox.answerFriendInvitation(message.id, approve: approve);
    if (done == null) {
      messenger.showSnackBar(SnackBar(content: Text(t('friendInvite.answerFailed'))));
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text(t('friendInvite.answered.$done'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = message.friendStatus;
    final theme = Theme.of(context);
    if (status != 'pending') {
      return Padding(
        padding: const EdgeInsets.only(top: FFTokens.spacingXs),
        child: FFBadge(
          key: Key('invite-status-${message.id}'),
          label: context.tr('friendInvite.status.$status'),
          tone: status == 'accepted' ? FFBadgeTone.success : FFBadgeTone.gray,
        ),
      );
    }
    final busy = inbox.isAnswering(message.id);
    return Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingSm),
      child: Row(
        children: [
          Expanded(
            child: FilledButton(
              key: Key('invite-approve-${message.id}'),
              onPressed: busy ? null : () => _answer(context, true),
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.tr('friendInvite.approve')),
            ),
          ),
          const SizedBox(width: FFTokens.spacingSm),
          Expanded(
            child: OutlinedButton(
              key: Key('invite-reject-${message.id}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: busy ? null : () => _answer(context, false),
              child: Text(context.tr('friendInvite.reject')),
            ),
          ),
        ],
      ),
    );
  }
}

/// What an invitation link opens. Signed out: who invited them and a way to
/// register or sign in (the link is kept through that). Signed in: it is
/// claimed, and the request appears under Notifications to approve.
class FriendInvitePage extends StatefulWidget {
  const FriendInvitePage({super.key, required this.token});
  final String token;

  @override
  State<FriendInvitePage> createState() => _FriendInvitePageState();
}

class _FriendInvitePageState extends State<FriendInvitePage> {
  bool _started = false;
  bool _loading = true;
  Object? _error;
  String? _status;
  String? _inviter;
  String? _mismatch;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final scope = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (scope.auth.isSignedIn) {
        final res = await scope.api.claimFriendInvitation(widget.token);
        await scope.inbox?.load();
        if (!mounted) return;
        _status = ((res['invitation'] as Map?)?['status'] ?? 'pending').toString();
        if (_status == 'pending') {
          context.go(AppRoutes.inbox);
          return;
        }
      } else {
        final res = await scope.api.previewFriendInvitation(widget.token);
        final inv = (res['invitation'] as Map?) ?? const {};
        _status = inv['status']?.toString();
        _inviter = inv['inviterName']?.toString();
        if (_status == 'pending') await PendingFriendInvite.save(widget.token);
      }
    } catch (e) {
      if (e is ApiException) {
        final code = e.code ?? '';
        if (code == 'contact_mismatch') {
          _mismatch = ((e.body as Map?)?['contactType'] ?? '').toString();
        } else if (code.startsWith('invitation_')) {
          _status = code.substring('invitation_'.length);
        } else if (code == 'invalid_invitation') {
          _status = 'invalid';
        } else {
          _error = e;
        }
      } else {
        _error = e;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final theme = Theme.of(context);
    final signedIn = AppScope.of(context).auth.isSignedIn;
    Widget body;
    if (_loading) {
      body = const Center(child: FFSpinner());
    } else if (_error != null) {
      body = FFEmptyState(
        title: t('friendInvite.loadFailed'),
        body: errorMessage(FFLocaleScope.of(context), _error!),
        action: FilledButton(onPressed: _load, child: Text(t('comms.retry'))),
      );
    } else if (_mismatch != null) {
      body = FFEmptyState(
        title: t('friendInvite.mismatchTitle'),
        body: t('friendInvite.mismatch.$_mismatch'),
      );
    } else if (_status != null && _status != 'pending') {
      body = FFEmptyState(
        title: t('friendInvite.unavailable.$_status'),
        body: t('friendInvite.unavailableBody'),
      );
    } else {
      final who = (_inviter ?? '').trim();
      body = Padding(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              who.isEmpty
                  ? t('friendInvite.pageTitleAnon')
                  : t('friendInvite.pageTitle').replaceFirst('{name}', who),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            Text(
              t('friendInvite.pageBody'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: FFTokens.spacingLg),
            FilledButton(
              key: const Key('invite-continue'),
              onPressed: () => context.go(
                signedIn ? AppRoutes.inbox : AppRoutes.language,
              ),
              child: Text(t('friendInvite.continue')),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(t('friendInvite.pageAppBar'))),
      body: body,
    );
  }
}
