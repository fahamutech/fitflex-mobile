import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/social.dart';
import 'member_community_page.dart';

/// Someone's profile: followers, how you're connected, Follow, and the posts
/// you can see — so you can decide whether they're worth a follow.
class MemberPersonPage extends StatefulWidget {
  const MemberPersonPage({super.key, required this.userId});

  final String userId;

  @override
  State<MemberPersonPage> createState() => _MemberPersonPageState();
}

class _MemberPersonPageState extends State<MemberPersonPage> {
  SocialProfile? _p;
  bool _missing = false;
  bool _busy = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await AppScope.of(context).api.personProfile(widget.userId);
      if (mounted) setState(() => _p = SocialProfile.fromJson(r));
    } catch (_) {
      if (mounted) setState(() => _missing = true);
    }
  }

  Future<void> _do(Future<Object?> Function() call, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr('community.error.generic');
    setState(() => _busy = true);
    try {
      await call();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final theme = Theme.of(context);
    final api = AppScope.of(context).api;
    final p = _p;
    final rel = p?.person.relationship;
    final followingThem =
        rel == Relationship.friends || rel == Relationship.following;
    return Scaffold(
      appBar: AppBar(
        title: Text(p?.person.name ?? t('community.profile')),
        leading: BackButton(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(AppRoutes.memberCommunity),
        ),
        actions: [
          if (p != null && rel != Relationship.you)
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'block' => _do(
                  () => api.block(widget.userId),
                  t('community.blockedToast'),
                ),
                'report' => _do(
                  () => api.report('user', widget.userId),
                  t('community.reportedToast'),
                ),
                _ => null,
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'block',
                  child: Text(t('community.block')),
                ),
                PopupMenuItem(
                  value: 'report',
                  child: Text(t('community.report')),
                ),
              ],
            ),
        ],
      ),
      body: _missing
          ? FFEmptyState(
              title: t('community.profileGone'),
              body: t('community.profileGoneBody'),
            )
          : p == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: [
                  Row(
                    children: [
                      FFAvatar(name: p.person.name, size: FFAvatarSize.lg),
                      const SizedBox(width: FFTokens.spacingMd),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.person.name,
                              style: theme.textTheme.titleLarge,
                            ),
                            Text(
                              [
                                t(
                                  'community.followerCount',
                                ).replaceAll('{n}', '${p.followers}'),
                                t(
                                  'community.followingCount',
                                ).replaceAll('{n}', '${p.following}'),
                                if (p.publicProfile) t('community.publicBadge'),
                              ].join(' · '),
                              key: const Key('person-counts'),
                              style: theme.textTheme.bodySmall,
                            ),
                            if (rel == Relationship.followsYou)
                              Text(
                                t('community.followsYouNote'),
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: FFTokens.spacingMd),
                  if (rel != Relationship.you)
                    followingThem
                        ? OutlinedButton(
                            key: const Key('person-unfollow'),
                            onPressed: _busy
                                ? null
                                : () => _do(
                                    () => api.unfollow(widget.userId),
                                    t('community.unfollowedToast'),
                                  ),
                            child: Text(
                              t(
                                rel == Relationship.friends
                                    ? 'community.friendsUnfollow'
                                    : 'community.followingUnfollow',
                              ),
                            ),
                          )
                        : FilledButton(
                            key: const Key('person-follow'),
                            onPressed: _busy
                                ? null
                                : () => _do(
                                    () => api.follow(widget.userId),
                                    t('community.followedToast'),
                                  ),
                            child: Text(
                              t(
                                rel == Relationship.followsYou
                                    ? 'community.followBack'
                                    : 'community.follow',
                              ),
                            ),
                          ),
                  FFSectionTitle(t('community.posts')),
                  if (p.items.isEmpty)
                    Text(
                      t(
                        followingThem
                            ? 'community.noPostsYet'
                            : 'community.noPublicPosts',
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  for (final item in p.items)
                    FeedCard(
                      item: item,
                      onKudos: () async {
                        await api.kudos(item.activity.id, !item.youKudoed);
                        await _load();
                      },
                      onOpen: () async {
                        await context.push(
                          AppRoutes.memberSharedActivity.replaceFirst(
                            ':activityId',
                            Uri.encodeComponent(item.activity.id),
                          ),
                        );
                        await _load();
                      },
                    ),
                ],
              ),
            ),
    );
  }
}
