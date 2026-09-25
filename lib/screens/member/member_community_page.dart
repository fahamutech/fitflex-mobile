import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/activity/run_metrics.dart' show formatPace;
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/social.dart';

/// Friends & groups: the feed of what people shared, finding and following
/// people, and groups. Only mutual followers, group-mates and colleagues
/// ever see what a member shares.
class MemberCommunityPage extends StatelessWidget {
  const MemberCommunityPage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    initialIndex: initialTab,
    child: Scaffold(
      appBar: AppBar(
        title: Text(context.tr('community.title')),
        leading: BackButton(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(AppRoutes.memberProfile),
        ),
        bottom: TabBar(
          tabs: [
            Tab(
              key: const Key('community-tab-feed'),
              text: context.tr('community.feed'),
            ),
            Tab(
              key: const Key('community-tab-explore'),
              text: context.tr('community.explore'),
            ),
            Tab(
              key: const Key('community-tab-people'),
              text: context.tr('community.people'),
            ),
            Tab(
              key: const Key('community-tab-groups'),
              text: context.tr('community.groups'),
            ),
          ],
        ),
      ),
      body: const TabBarView(
        children: [FeedTab(), FeedTab(explore: true), PeopleTab(), GroupsTab()],
      ),
    ),
  );
}

String errorText(BuildContext context, Object e) {
  final s = e.toString();
  for (final code in [
    'not_found',
    'company_only',
    'members_only',
    'last_admin',
    'group_full',
    'empty_comment',
    'invalid_name',
  ]) {
    if (s.contains(code)) return context.tr('community.error.$code');
  }
  return context.tr('community.error.generic');
}

/// Small buttons for rows (the theme's default is wide).
final compactButton = FilledButton.styleFrom(
  minimumSize: const Size(0, 36),
  padding: const EdgeInsets.symmetric(horizontal: 12),
  visualDensity: VisualDensity.compact,
);

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

// ── Feed ─────────────────────────────────────────────────────────────────

/// Your feed (people you follow, friends, groups, company), or with
/// [explore] recent public posts from public profiles.
class FeedTab extends StatefulWidget {
  const FeedTab({super.key, this.explore = false});

  final bool explore;

  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> {
  List<FeedItem>? _items;
  String? _next;
  bool _loadingMore = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load({bool more = false}) async {
    final api = AppScope.of(context).api;
    try {
      if (more) setState(() => _loadingMore = true);
      final before = more ? _next : null;
      final res = widget.explore
          ? await api.explore(before: before)
          : await api.feed(before: before);
      final items = [
        for (final i in (res['items'] as List? ?? const []))
          if (i is Map) FeedItem.fromJson(i),
      ];
      if (!mounted) return;
      setState(() {
        _items = more ? [...?_items, ...items] : items;
        _next = res['next'] as String?;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => (_items ??= const [], _loadingMore = false));
    }
  }

  Future<void> _kudos(int i) async {
    final item = _items![i];
    final on = !item.youKudoed;
    setState(
      () => _items![i] = item.copyWith(
        youKudoed: on,
        kudos: item.kudos + (on ? 1 : -1),
      ),
    );
    try {
      final r = await AppScope.of(context).api.kudos(item.activity.id, on);
      if (mounted) {
        setState(
          () => _items![i] = item.copyWith(
            youKudoed: r['youKudoed'] == true,
            kudos: (r['kudos'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _items![i] = item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          if (items.isEmpty)
            FFEmptyState(
              key: Key(widget.explore ? 'explore-empty' : 'feed-empty'),
              title: context.tr(
                widget.explore
                    ? 'community.exploreEmptyTitle'
                    : 'community.feedEmptyTitle',
              ),
              body: context.tr(
                widget.explore
                    ? 'community.exploreEmptyBody'
                    : 'community.feedEmptyBody',
              ),
            ),
          for (final (i, item) in items.indexed)
            FeedCard(
              item: item,
              onKudos: () => _kudos(i),
              onOpen: () async {
                await context.push(
                  AppRoutes.memberSharedActivity.replaceFirst(
                    ':activityId',
                    Uri.encodeComponent(item.activity.id),
                  ),
                );
                if (mounted) _load();
              },
            ),
          if (_next != null)
            Center(
              child: TextButton(
                onPressed: _loadingMore ? null : () => _load(more: true),
                child: Text(context.tr('community.more')),
              ),
            ),
        ],
      ),
    );
  }
}

IconData sharedTypeIcon(String type) => switch (type) {
  'running' || 'jogging' => Icons.directions_run,
  'walking' || 'hiking' => Icons.directions_walk,
  'cycling' => Icons.directions_bike,
  'swimming' => Icons.pool,
  'strength' || 'functional' || 'hiit' => Icons.fitness_center,
  _ => Icons.bolt,
};

/// "5.20 km · 28:14 · 5:26 /km · 12 m climb"
String sharedStats(BuildContext context, SharedActivity a) {
  final secs =
      a.movingSeconds ??
      (a.durationMinutes != null ? a.durationMinutes! * 60 : null);
  String dur(int s) =>
      s >= 3600 ? '${s ~/ 3600}h ${(s % 3600) ~/ 60}m' : '${s ~/ 60} min';
  return [
    if ((a.distanceKm ?? 0) > 0) '${a.distanceKm!.toStringAsFixed(2)} km',
    if (secs != null) dur(secs),
    if ((a.distanceKm ?? 0) > 0.1 && a.movingSeconds != null)
      '${formatPace((a.movingSeconds! / a.distanceKm!).round())} /km',
    if ((a.elevationGainM ?? 0) >= 1)
      '${a.elevationGainM!.round()} m ${context.tr('run.climb').toLowerCase()}',
    if (a.steps != null && (a.distanceKm ?? 0) == 0)
      '${NumberFormat.decimalPattern().format(a.steps)} ${context.tr('activity.steps').toLowerCase()}',
  ].join(' · ');
}

class FeedCard extends StatelessWidget {
  const FeedCard({
    super.key,
    required this.item,
    required this.onKudos,
    required this.onOpen,
  });

  final FeedItem item;
  final VoidCallback onKudos;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = item.activity;
    final you = item.owner.relationship == Relationship.you;
    return FFCard(
      key: Key('feed-${a.id}'),
      margin: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: Key('feed-owner-${a.id}'),
              // The poster's profile, to follow them or see more.
              onTap: you ? null : () => openPerson(context, item.owner.id),
              child: Row(
                children: [
                  FFAvatar(name: item.owner.name, size: FFAvatarSize.sm),
                  const SizedBox(width: FFTokens.spacingSm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          you ? context.tr('community.you') : item.owner.name,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          DateFormat('EEE d MMM · HH:mm').format(a.startedAt),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (!you && item.owner.relationship == Relationship.none)
                    Text(
                      context.tr('community.notFollowing'),
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            Row(
              children: [
                Icon(
                  sharedTypeIcon(a.type),
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: FFTokens.spacingXs),
                Expanded(
                  child: Text(
                    (a.title ?? '').isNotEmpty
                        ? a.title!
                        : context.tr('activity.type.${a.type}'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingXs),
            Text(sharedStats(context, a), style: theme.textTheme.bodyMedium),
            const SizedBox(height: FFTokens.spacingSm),
            Row(
              children: [
                TextButton.icon(
                  key: Key('kudos-${a.id}'),
                  onPressed: you ? null : onKudos,
                  icon: Icon(
                    item.youKudoed ? Icons.thumb_up : Icons.thumb_up_outlined,
                    size: 18,
                  ),
                  label: Text('${item.kudos}'),
                ),
                TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: Text('${item.comments}'),
                ),
                if (you && item.views != null) ...[
                  const Spacer(),
                  Icon(
                    Icons.visibility_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: FFTokens.spacingXs),
                  Text(
                    context
                        .tr('community.views')
                        .replaceAll('{n}', '${item.views}'),
                    key: Key('views-${a.id}'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── People ───────────────────────────────────────────────────────────────

class PeopleTab extends StatefulWidget {
  const PeopleTab({super.key});

  @override
  State<PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<PeopleTab> {
  List<SocialPerson> _friends = const [],
      _following = const [],
      _followers = const [];
  List<SocialPerson>? _found;
  String _code = '';
  bool _loaded = false;
  bool _started = false;
  final _search = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SocialPerson> _people(Object? v) => [
    for (final p in (v as List? ?? const []))
      if (p is Map) SocialPerson.fromJson(p),
  ];

  Future<void> _load() async {
    final api = AppScope.of(context).api;
    try {
      final r = await Future.wait([api.connections(), api.socialSettings()]);
      if (!mounted) return;
      setState(() {
        _friends = _people(r[0]['friends']);
        _following = _people(r[0]['following']);
        _followers = _people(r[0]['followers']);
        _code = r[1]['inviteCode'] as String? ?? '';
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _find() async {
    final q = _search.text.trim();
    if (q.isEmpty) return setState(() => _found = null);
    final api = AppScope.of(context).api;
    // Invite codes are 8 letters/digits; anything else searches by name.
    final isCode = RegExp(r'^[A-Za-z0-9]{8}$').hasMatch(q);
    try {
      final r = await api.findPeople(
        q: isCode ? null : q,
        code: isCode ? q : null,
      );
      if (mounted) setState(() => _found = _people(r['people']));
    } catch (_) {
      if (mounted) setState(() => _found = const []);
    }
  }

  Future<void> _act(Future<Object?> Function() call, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = errorText(context, '');
    try {
      await call();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
    await _load();
    if (_found != null) await _find();
  }

  Widget _personTile(SocialPerson p) {
    final api = AppScope.of(context).api;
    final t = context.tr;
    final (label, action) = switch (p.relationship) {
      Relationship.friends => (t('community.friends'), null),
      Relationship.following => (t('community.followingLabel'), null),
      Relationship.followsYou => (
        t('community.followBack'),
        () => _act(() => api.follow(p.id), t('community.followedToast')),
      ),
      _ => (
        t('community.follow'),
        () => _act(() => api.follow(p.id), t('community.followedToast')),
      ),
    };
    return FFCard(
      key: Key('person-${p.id}'),
      margin: const EdgeInsets.only(bottom: FFTokens.spacingXs),
      child: Row(
        children: [
          FFAvatar(name: p.name, size: FFAvatarSize.sm),
          const SizedBox(width: FFTokens.spacingSm),
          Expanded(
            child: InkWell(
              onTap: () => openPerson(context, p.id),
              child: Text(
                p.name,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          if (action != null)
            FilledButton.tonal(
              key: Key('follow-${p.id}'),
              style: compactButton,
              onPressed: action,
              child: Text(label),
            )
          else
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          PopupMenuButton<String>(
            key: Key('person-menu-${p.id}'),
            onSelected: (v) => switch (v) {
              'unfollow' => _act(
                () => api.unfollow(p.id),
                t('community.unfollowedToast'),
              ),
              'remove' => _act(
                () => api.removeFollower(p.id),
                t('community.removedToast'),
              ),
              'block' => _act(
                () => api.block(p.id),
                t('community.blockedToast'),
              ),
              'report' => _act(
                () => api.report('user', p.id),
                t('community.reportedToast'),
              ),
              _ => null,
            },
            itemBuilder: (_) => [
              if (p.relationship == Relationship.friends ||
                  p.relationship == Relationship.following)
                PopupMenuItem(
                  value: 'unfollow',
                  child: Text(t('community.unfollow')),
                ),
              if (p.relationship == Relationship.friends ||
                  p.relationship == Relationship.followsYou)
                PopupMenuItem(
                  value: 'remove',
                  child: Text(t('community.removeFollower')),
                ),
              PopupMenuItem(value: 'block', child: Text(t('community.block'))),
              PopupMenuItem(
                value: 'report',
                child: Text(t('community.report')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          FFCard(
            key: const Key('my-invite-code'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('community.yourCode'),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: FFTokens.spacingXs),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        _code,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('community.copy'),
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _code));
                        _toast(context, context.tr('community.copied'));
                      },
                    ),
                  ],
                ),
                Text(
                  context.tr('community.codeHint'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: FFTokens.spacingMd),
          TextField(
            key: const Key('people-search'),
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _find(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: context.tr('community.searchHint'),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: _find,
              ),
            ),
          ),
          if (_found != null) ...[
            FFSectionTitle(context.tr('community.results')),
            if (_found!.isEmpty)
              Text(
                context.tr('community.noResults'),
                style: theme.textTheme.bodySmall,
              ),
            for (final p in _found!) _personTile(p),
          ],
          if (_followers.isNotEmpty) ...[
            FFSectionTitle(context.tr('community.followsYou')),
            for (final p in _followers) _personTile(p),
          ],
          FFSectionTitle(context.tr('community.friends')),
          if (_friends.isEmpty)
            Text(
              context.tr('community.noFriends'),
              style: theme.textTheme.bodySmall,
            ),
          for (final p in _friends) _personTile(p),
          if (_following.isNotEmpty) ...[
            FFSectionTitle(context.tr('community.waitingTitle')),
            for (final p in _following) _personTile(p),
          ],
        ],
      ),
    );
  }
}

// ── Groups ───────────────────────────────────────────────────────────────

class GroupsTab extends StatefulWidget {
  const GroupsTab({super.key});

  @override
  State<GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<GroupsTab> {
  List<SocialGroup>? _mine;
  List<SocialGroup> _found = const [];
  bool _started = false;
  final _q = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<SocialGroup> _groups(Object? v) => [
    for (final g in (v as List? ?? const []))
      if (g is Map) SocialGroup.fromJson(g),
  ];

  Future<void> _load() async {
    final api = AppScope.of(context).api;
    try {
      final r = await Future.wait([
        api.myGroups(),
        api.discoverGroups(q: _q.text.trim()),
      ]);
      if (mounted) {
        setState(
          () => (
            _mine = _groups(r[0]['groups']),
            _found = _groups(r[1]['groups']),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _mine ??= const []);
    }
  }

  Future<void> _join({String? groupId, String? code}) async {
    final messenger = ScaffoldMessenger.of(context);
    final t = context.tr;
    try {
      final r = await AppScope.of(
        context,
      ).api.joinGroup(groupId: groupId, inviteCode: code);
      final g = SocialGroup.fromJson(r['group'] as Map? ?? const {});
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            t(g.isPending ? 'community.requestSent' : 'community.joinedToast'),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(errorText(context, e))));
      }
    }
    await _load();
  }

  Future<void> _joinByCode() async {
    final code = await _askText(
      context,
      title: context.tr('community.joinByCode'),
      hint: 'ABCD1234',
    );
    if (code != null && code.trim().isNotEmpty) await _join(code: code.trim());
  }

  Future<void> _create() async {
    final created = await showGroupForm(
      context,
      onSave: (body) async {
        final r = await AppScope.of(context).api.createMyGroup(body);
        return SocialGroup.fromJson(r['group'] as Map? ?? const {});
      },
    );
    if (created != null) {
      await _load();
      if (mounted) openGroup(context, created.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = _mine;
    if (mine == null) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('group-create'),
                  onPressed: _create,
                  icon: const Icon(Icons.add),
                  label: Text(context.tr('community.createGroup')),
                ),
              ),
              const SizedBox(width: FFTokens.spacingSm),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('group-join-code'),
                  onPressed: _joinByCode,
                  icon: const Icon(Icons.vpn_key_outlined),
                  label: Text(context.tr('community.joinByCode')),
                ),
              ),
            ],
          ),
          FFSectionTitle(context.tr('community.myGroups')),
          if (mine.isEmpty)
            Text(
              context.tr('community.noGroups'),
              style: theme.textTheme.bodySmall,
            ),
          for (final g in mine)
            FFActionTile(
              key: Key('group-${g.id}'),
              icon: Icons.groups_outlined,
              title: g.name,
              subtitle: [
                context
                    .tr('community.members')
                    .replaceAll('{n}', '${g.memberCount}'),
                if (g.isPending) context.tr('community.pending'),
                if (g.role == 'admin') context.tr('community.admin'),
              ].join(' · '),
              onTap: () async {
                await openGroup(context, g.id);
                _load();
              },
            ),
          FFSectionTitle(context.tr('community.findGroups')),
          TextField(
            controller: _q,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: context.tr('community.findGroupsHint'),
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          if (_found.isEmpty)
            Text(
              context.tr('community.noDiscover'),
              style: theme.textTheme.bodySmall,
            ),
          for (final g in _found)
            FFCard(
              key: Key('discover-${g.id}'),
              margin: const EdgeInsets.only(bottom: FFTokens.spacingXs),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.name, style: theme.textTheme.titleSmall),
                        Text(
                          [
                            context
                                .tr('community.members')
                                .replaceAll('{n}', '${g.memberCount}'),
                            context.tr(
                              g.joinPolicy == 'open'
                                  ? 'community.openToJoin'
                                  : 'community.needsApproval',
                            ),
                          ].join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    style: compactButton,
                    onPressed: () => _join(groupId: g.id),
                    child: Text(
                      context.tr(
                        g.joinPolicy == 'open'
                            ? 'community.join'
                            : 'community.askToJoin',
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> openPerson(BuildContext context, String userId) => context.push(
  AppRoutes.memberPerson.replaceFirst(':userId', Uri.encodeComponent(userId)),
);

Future<void> openGroup(BuildContext context, String id) => context.push(
  AppRoutes.memberGroup.replaceFirst(':groupId', Uri.encodeComponent(id)),
);

Future<String?> _askText(
  BuildContext context, {
  required String title,
  String? hint,
}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const Key('ask-text'),
        controller: c,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(ctx.tr('trainer.cancel')),
        ),
        FilledButton(
          key: const Key('ask-text-ok'),
          onPressed: () => Navigator.pop(ctx, c.text),
          child: Text(ctx.tr('audience.done')),
        ),
      ],
    ),
  );
}

/// Create or edit a group. [onSave] sends it and returns the saved group.
Future<SocialGroup?> showGroupForm(
  BuildContext context, {
  SocialGroup? existing,
  required Future<SocialGroup> Function(Map<String, dynamic> body) onSave,
}) => showModalBottomSheet<SocialGroup>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _GroupForm(existing: existing, onSave: onSave),
);

class _GroupForm extends StatefulWidget {
  const _GroupForm({this.existing, required this.onSave});

  final SocialGroup? existing;
  final Future<SocialGroup> Function(Map<String, dynamic> body) onSave;

  @override
  State<_GroupForm> createState() => _GroupFormState();
}

class _GroupFormState extends State<_GroupForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _desc = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late bool _open = widget.existing?.joinPolicy == 'open';
  late bool _listed = widget.existing?.discoverable ?? false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => (_busy = true, _error = null));
    try {
      final g = await widget.onSave({
        'name': _name.text.trim(),
        'description': _desc.text.trim(),
        'joinPolicy': _open ? 'open' : 'approval',
        'discoverable': _listed,
      });
      if (mounted) Navigator.pop(context, g);
    } catch (e) {
      if (mounted) {
        setState(() => (_busy = false, _error = errorText(context, e)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        FFTokens.spacingLg,
        FFTokens.spacingLg,
        FFTokens.spacingLg,
        FFTokens.spacingLg + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr(
              widget.existing == null
                  ? 'community.createGroup'
                  : 'community.editGroup',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingSm),
              child: FFAlert(message: _error!, tone: FFAlertTone.error),
            ),
          TextField(
            key: const Key('group-name'),
            controller: _name,
            maxLength: 60,
            decoration: InputDecoration(
              labelText: context.tr('community.groupName'),
            ),
          ),
          TextField(
            controller: _desc,
            maxLength: 300,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: context.tr('community.groupDescription'),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _open,
            onChanged: (v) => setState(() => _open = v),
            title: Text(context.tr('community.openToJoin')),
            subtitle: Text(context.tr('community.openHint')),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _listed,
            onChanged: (v) => setState(() => _listed = v),
            title: Text(context.tr('community.listed')),
            subtitle: Text(context.tr('community.listedHint')),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          FilledButton(
            key: const Key('group-save'),
            onPressed: _busy ? null : _save,
            child: Text(context.tr('community.saveGroup')),
          ),
        ],
      ),
    ),
  );
}
