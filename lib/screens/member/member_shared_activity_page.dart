import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/social.dart';
import 'member_community_page.dart';
import 'widgets/run_widgets.dart' show RunSplits;

/// One shared activity: the numbers, kudos and comments. Only people who
/// can see it (the server checks) get here.
class MemberSharedActivityPage extends StatefulWidget {
  const MemberSharedActivityPage({super.key, required this.activityId});

  final String activityId;

  @override
  State<MemberSharedActivityPage> createState() =>
      _MemberSharedActivityPageState();
}

class _MemberSharedActivityPageState extends State<MemberSharedActivityPage> {
  FeedItem? _item;
  List<SocialComment> _comments = const [];
  bool _missing = false;
  bool _sending = false;
  bool _started = false;
  final _text = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await AppScope.of(
        context,
      ).api.sharedActivity(widget.activityId);
      if (!mounted) return;
      setState(() {
        _item = FeedItem.fromJson(r['item'] as Map? ?? const {});
        _comments = [
          for (final c in (r['comments'] as List? ?? const []))
            if (c is Map) SocialComment.fromJson(c),
        ];
      });
    } catch (_) {
      if (mounted) setState(() => _missing = true);
    }
  }

  Future<void> _kudos() async {
    final item = _item!;
    try {
      final r = await AppScope.of(
        context,
      ).api.kudos(item.activity.id, !item.youKudoed);
      if (mounted) {
        setState(
          () => _item = item.copyWith(
            youKudoed: r['youKudoed'] == true,
            kudos: (r['kudos'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      await AppScope.of(context).api.addComment(widget.activityId, t);
      _text.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(errorText(context, e))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _commentAction(SocialComment c, String action) async {
    final api = AppScope.of(context).api;
    final messenger = ScaffoldMessenger.of(context);
    final reported = context.tr('community.reportedToast');
    if (action == 'delete') await api.deleteComment(c.id);
    if (action == 'report') {
      await api.report('comment', c.id);
      messenger.showSnackBar(SnackBar(content: Text(reported)));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = _item;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('community.activity')),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          if (item != null && item.owner.relationship != Relationship.you)
            PopupMenuButton<String>(
              onSelected: (_) async {
                final messenger = ScaffoldMessenger.of(context);
                final done = context.tr('community.reportedToast');
                await AppScope.of(
                  context,
                ).api.report('activity', item.activity.id);
                messenger.showSnackBar(SnackBar(content: Text(done)));
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'report',
                  child: Text(context.tr('community.report')),
                ),
              ],
            ),
        ],
      ),
      body: _missing
          ? FFEmptyState(title: context.tr('community.activityGone'))
          : item == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(FFTokens.spacingLg),
                    children: [
                      FeedCard(item: item, onKudos: _kudos, onOpen: () {}),
                      if (item.owner.relationship == Relationship.you)
                        _EngagementSection(activityId: item.activity.id),
                      RunSplits(splits: item.activity.splits),
                      FFSectionTitle(context.tr('community.comments')),
                      if (_comments.isEmpty)
                        Text(
                          context.tr('community.noComments'),
                          style: theme.textTheme.bodySmall,
                        ),
                      for (final c in _comments)
                        Padding(
                          key: Key('comment-${c.id}'),
                          padding: const EdgeInsets.only(
                            bottom: FFTokens.spacingSm,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FFAvatar(
                                name: c.author.name,
                                size: FFAvatarSize.sm,
                              ),
                              const SizedBox(width: FFTokens.spacingSm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${c.author.name} · ${DateFormat('d MMM HH:mm').format(c.createdAt)}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    Text(
                                      c.text,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (v) => _commentAction(c, v),
                                itemBuilder: (_) => [
                                  if (c.canDelete)
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(
                                        context.tr('community.deleteComment'),
                                      ),
                                    ),
                                  PopupMenuItem(
                                    value: 'report',
                                    child: Text(context.tr('community.report')),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      FFTokens.spacingLg,
                      0,
                      FFTokens.spacingSm,
                      FFTokens.spacingSm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('comment-input'),
                            controller: _text,
                            maxLength: 500,
                            minLines: 1,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: context.tr('community.commentHint'),
                              counterText: '',
                            ),
                          ),
                        ),
                        IconButton(
                          key: const Key('comment-send'),
                          onPressed: _sending ? null : _send,
                          icon: const Icon(Icons.send),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// On your own post: how many viewed it (viewers stay anonymous) and who
/// gave kudos or commented, with Follow back.
class _EngagementSection extends StatefulWidget {
  const _EngagementSection({required this.activityId});

  final String activityId;

  @override
  State<_EngagementSection> createState() => _EngagementSectionState();
}

class _EngagementSectionState extends State<_EngagementSection> {
  Engagement? _e;
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
      final r = await AppScope.of(
        context,
      ).api.postEngagement(widget.activityId);
      if (mounted) setState(() => _e = Engagement.fromJson(r));
    } catch (_) {}
  }

  Widget _row(SocialPerson p) {
    final t = context.tr;
    final canFollow =
        p.relationship == Relationship.none ||
        p.relationship == Relationship.followsYou;
    return Padding(
      key: Key('engaged-${p.id}'),
      padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
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
          if (canFollow)
            FilledButton.tonal(
              key: Key('follow-back-${p.id}'),
              style: compactButton,
              onPressed: () async {
                await AppScope.of(context).api.follow(p.id);
                await _load();
              },
              child: Text(t('community.followBack')),
            )
          else
            Text(
              t(
                p.relationship == Relationship.friends
                    ? 'community.friends'
                    : 'community.followingLabel',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = _e;
    if (e == null) return const SizedBox.shrink();
    final t = context.tr;
    final theme = Theme.of(context);
    return FFCard(
      key: const Key('engagement'),
      margin: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 18),
              const SizedBox(width: FFTokens.spacingXs),
              Text(
                t('community.views').replaceAll('{n}', '${e.views}'),
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          Text(t('community.viewsPrivate'), style: theme.textTheme.bodySmall),
          if (e.kudos.isNotEmpty) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Text(t('community.kudosFrom'), style: theme.textTheme.titleSmall),
            for (final p in e.kudos) _row(p),
          ],
          if (e.commenters.isNotEmpty) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Text(t('community.commentedBy'), style: theme.textTheme.titleSmall),
            for (final p in e.commenters) _row(p),
          ],
        ],
      ),
    );
  }
}
