// The inbox: every message the signed-in user has had — bookings, payments,
// renewals, and messages from their gym and FitFlex — plus one message's
// page with its button. Used by members and gym owners alike.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../api_error_message.dart';
import '../components/components.dart';
import '../design_tokens.dart';
import '../i18n.dart';
import 'inbox_controller.dart';

/// The bell with an unread count, opening the inbox.
class InboxBellButton extends StatelessWidget {
  const InboxBellButton({super.key});

  @override
  Widget build(BuildContext context) {
    final inbox = AppScope.of(context).inbox;
    if (inbox == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: inbox,
      builder: (context, _) => IconButton(
        key: const Key('inbox-bell'),
        tooltip: context.tr('inbox.title'),
        onPressed: () => context.push('/inbox'),
        icon: Badge(
          isLabelVisible: inbox.unread > 0,
          label: Text(inbox.unread > 99 ? '99+' : '${inbox.unread}'),
          child: const Icon(Icons.notifications_none),
        ),
      ),
    );
  }
}

String _when(DateTime? at) {
  if (at == null) return '';
  final now = DateTime.now();
  final sameDay =
      at.year == now.year && at.month == now.month && at.day == now.day;
  return sameDay
      ? DateFormat('HH:mm').format(at)
      : DateFormat('d MMM').format(at);
}

/// Where a message's button goes, for the signed-in role. Members get app
/// screens; everyone else stays on the message.
String? routeForMessage(BuildContext context, InboxMessage m) {
  final role =
      AppScope.of(context).auth.user?['userType']?.toString() ??
      AppScope.of(context).auth.role;
  if (role != 'member') return null;
  return memberRouteFor(
    deepLink: m.deepLink,
    type: m.type,
    gymId: m.gymId,
    trainerId: m.data['trainerId']?.toString(),
  );
}

class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  InboxCategory? _filter;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // After the first frame: loading notifies listeners, which mustn't
    // happen while the tree is building.
    final inbox = AppScope.of(context).inbox;
    WidgetsBinding.instance.addPostFrameCallback((_) => inbox?.load());
  }

  @override
  Widget build(BuildContext context) {
    final inbox = AppScope.of(context).inbox;
    final isMember =
        (AppScope.of(context).auth.user?['userType'] ??
            AppScope.of(context).auth.role) ==
        'member';
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('inbox.title')),
        actions: [
          if (inbox != null)
            ListenableBuilder(
              listenable: inbox,
              builder: (context, _) => TextButton(
                key: const Key('inbox-read-all'),
                onPressed: inbox.unread == 0 ? null : inbox.markAllRead,
                child: Text(context.tr('inbox.markAllRead')),
              ),
            ),
          if (isMember)
            IconButton(
              key: const Key('inbox-settings'),
              tooltip: context.tr('msgPrefs.title'),
              onPressed: () => context.push('/member/message-settings'),
              icon: const Icon(Icons.tune),
            ),
        ],
      ),
      body: inbox == null
          ? const SizedBox.shrink()
          : ListenableBuilder(
              listenable: inbox,
              builder: (context, _) => RefreshIndicator(
                onRefresh: inbox.load,
                child: _list(context, inbox),
              ),
            ),
    );
  }

  Widget _list(BuildContext context, InboxController inbox) {
    if (inbox.loading && inbox.messages.isEmpty) {
      return const Center(child: FFSpinner());
    }
    if (inbox.error != null && inbox.messages.isEmpty) {
      return ListView(
        children: [
          FFEmptyState(
            title: context.tr('inbox.loadFailed'),
            body: errorMessage(FFLocaleScope.of(context), inbox.error!),
            action: FilledButton(
              onPressed: inbox.load,
              child: Text(context.tr('comms.retry')),
            ),
          ),
        ],
      );
    }
    const filters = [
      null,
      InboxCategory.membership,
      InboxCategory.payments,
      InboxCategory.offers,
      InboxCategory.announcements,
    ];
    final shown = inbox.messages
        .where((m) => _filter == null || m.kind == _filter)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final f in filters)
                Padding(
                  padding: const EdgeInsets.only(right: FFTokens.spacingXs),
                  child: FFPill(
                    key: Key('inbox-filter-${f?.name ?? 'all'}'),
                    label: context.tr('inbox.filter.${f?.name ?? 'all'}'),
                    filled: _filter == f,
                    onTap: () => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        if (shown.isEmpty)
          FFEmptyState(
            title: context.tr('inbox.empty.title'),
            body: context.tr('inbox.empty.body'),
          )
        else
          for (final m in shown) _MessageTile(message: m),
      ],
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message});
  final InboxMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = message;
    return FFCard(
      margin: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: InkWell(
        key: Key('inbox-${m.id}'),
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        onTap: () => context.push('/inbox/${m.id}'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: FFTokens.spacingSm),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: m.unread
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          m.senderName ?? context.tr('inbox.from.fitflex'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      Text(
                        _when(m.createdAt),
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: FFTokens.spacing2xs),
                  Text(
                    m.title,
                    style: m.unread
                        ? theme.textTheme.titleSmall
                        : theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                  ),
                  Text(
                    m.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (m.kind == InboxCategory.offers)
                    Padding(
                      padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                      child: FFBadge(
                        label: context.tr('inbox.filter.offers'),
                        tone: FFBadgeTone.brand,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One message, marked read on open, with its button.
class InboxMessagePage extends StatefulWidget {
  const InboxMessagePage({super.key, required this.messageId});
  final String messageId;

  @override
  State<InboxMessagePage> createState() => _InboxMessagePageState();
}

class _InboxMessagePageState extends State<InboxMessagePage> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final inbox = AppScope.of(context).inbox;
    if (inbox == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (inbox.byId(widget.messageId) == null) await inbox.load();
      await inbox.markRead(widget.messageId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final inbox = AppScope.of(context).inbox;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('inbox.message'))),
      body: inbox == null
          ? const SizedBox.shrink()
          : ListenableBuilder(
              listenable: inbox,
              builder: (context, _) {
                final m = inbox.byId(widget.messageId);
                if (m == null) {
                  return inbox.loading
                      ? const Center(child: FFSpinner())
                      : FFEmptyState(title: context.tr('inbox.notFound'));
                }
                return _body(context, inbox, m);
              },
            ),
    );
  }

  Widget _body(BuildContext context, InboxController inbox, InboxMessage m) {
    final theme = Theme.of(context);
    final route = routeForMessage(context, m);
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Text(
          m.senderName ?? context.tr('inbox.from.fitflex'),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: FFTokens.spacingXs),
        Text(m.title, style: theme.textTheme.titleLarge),
        if (m.createdAt != null)
          Text(
            DateFormat('d MMM yyyy, HH:mm').format(m.createdAt!),
            style: theme.textTheme.bodySmall,
          ),
        const SizedBox(height: FFTokens.spacingMd),
        Text(m.body, style: theme.textTheme.bodyLarge),
        if (route != null) ...[
          const SizedBox(height: FFTokens.spacingLg),
          FilledButton(
            key: const Key('inbox-cta'),
            onPressed: () async {
              await inbox.click(m.id);
              // Member screens live in the member shell: go, like the rest
              // of the app does, rather than stacking the shell on the inbox.
              if (context.mounted) context.go(route);
            },
            child: Text(
              m.ctaLabel ??
                  context.tr(
                    'inbox.open.${m.deepLink.isEmpty ? 'membership' : m.deepLink}',
                  ),
            ),
          ),
        ],
        if (m.kind == InboxCategory.offers) ...[
          const SizedBox(height: FFTokens.spacingLg),
          Text(
            context.tr('inbox.offersNote'),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
