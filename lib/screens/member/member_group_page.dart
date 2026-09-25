import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/social.dart';
import 'member_community_page.dart';

/// A group: who's in it, its invite code (for those who run it), requests
/// to approve, and leaving. [scope] is null for members, or `trainer` /
/// `owner` when a trainer or gym runs the group (they manage it but aren't
/// members, so they see no one's activity through it).
class GroupPage extends StatefulWidget {
  const GroupPage({super.key, required this.groupId, this.scope, this.gymId});

  final String groupId;
  final String? scope;
  final String? gymId;

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  SocialGroup? _group;
  List<GroupMember> _members = const [];
  bool _missing = false;
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
      final r = await AppScope.of(context).api.groupDetail(
        widget.groupId,
        scope: widget.scope,
        gymId: widget.gymId,
      );
      if (!mounted) return;
      setState(() {
        _group = SocialGroup.fromJson(r['group'] as Map? ?? const {});
        _members = [
          for (final m in (r['members'] as List? ?? const []))
            if (m is Map) GroupMember.fromJson(m),
        ];
      });
    } catch (_) {
      if (mounted) setState(() => _missing = true);
    }
  }

  Future<void> _do(
    Future<Object?> Function() call, {
    String? done,
    bool close = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.maybeOf(context);
    try {
      await call();
      if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
      if (close) {
        router?.pop();
        return;
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(errorText(context, e))));
      }
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = AppScope.of(context).api;
    final g = _group;
    final t = context.tr;
    final manage = g != null && (g.canManage || widget.scope != null);
    return Scaffold(
      appBar: AppBar(
        title: Text(g?.name ?? t('community.group')),
        actions: [
          if (g != null)
            PopupMenuButton<String>(
              key: const Key('group-menu'),
              onSelected: (v) async {
                switch (v) {
                  case 'edit':
                    await showGroupForm(
                      context,
                      existing: g,
                      onSave: (body) async {
                        await api.updateGroup(
                          g.id,
                          body,
                          scope: widget.scope,
                          gymId: widget.gymId,
                        );
                        return g;
                      },
                    );
                    await _load();
                  case 'archive':
                    await _do(
                      () => api.archiveGroup(
                        g.id,
                        scope: widget.scope,
                        gymId: widget.gymId,
                      ),
                      done: t('community.archivedToast'),
                      close: true,
                    );
                  case 'leave':
                    await _do(
                      () => api.leaveGroup(g.id),
                      done: t('community.leftToast'),
                      close: true,
                    );
                  case 'report':
                    await _do(
                      () => api.report('group', g.id),
                      done: t('community.reportedToast'),
                    );
                }
              },
              itemBuilder: (_) => [
                if (manage)
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(t('community.editGroup')),
                  ),
                if (manage)
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(t('community.archiveGroup')),
                  ),
                if (widget.scope == null && g.status != null)
                  PopupMenuItem(
                    value: 'leave',
                    child: Text(t('community.leaveGroup')),
                  ),
                if (widget.scope == null)
                  PopupMenuItem(
                    value: 'report',
                    child: Text(t('community.report')),
                  ),
              ],
            ),
        ],
      ),
      body: _missing
          ? FFEmptyState(title: t('community.groupGone'))
          : g == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: [
                  if ((g.description ?? '').isNotEmpty)
                    Text(g.description!, style: theme.textTheme.bodyMedium),
                  Text(
                    [
                      t(
                        'community.members',
                      ).replaceAll('{n}', '${g.memberCount}'),
                      t(
                        g.joinPolicy == 'open'
                            ? 'community.openToJoin'
                            : 'community.needsApproval',
                      ),
                      if (g.discoverable) t('community.listed'),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (g.isPending)
                    Padding(
                      padding: const EdgeInsets.only(top: FFTokens.spacingMd),
                      child: FFAlert(message: t('community.pendingBody')),
                    ),
                  if (g.inviteCode != null) ...[
                    const SizedBox(height: FFTokens.spacingMd),
                    FFCard(
                      key: const Key('group-invite-code'),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t('community.groupCode'),
                                  style: theme.textTheme.titleSmall,
                                ),
                                SelectableText(
                                  g.inviteCode!,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 2,
                                      ),
                                ),
                                Text(
                                  t('community.groupCodeHint'),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: g.inviteCode!),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(t('community.copied'))),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (widget.scope != null)
                    Padding(
                      padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                      child: Text(
                        t('community.ownerPrivacy'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  FFSectionTitle(t('community.membersTitle')),
                  if (_members.isEmpty)
                    Text(
                      t('community.noMembers'),
                      style: theme.textTheme.bodySmall,
                    ),
                  for (final m in _members)
                    FFCard(
                      key: Key('member-${m.id}'),
                      margin: const EdgeInsets.only(bottom: FFTokens.spacingXs),
                      child: Row(
                        children: [
                          FFAvatar(name: m.name, size: FFAvatarSize.sm),
                          const SizedBox(width: FFTokens.spacingSm),
                          Expanded(
                            child: Text(
                              [
                                m.name,
                                if (m.role == 'admin') t('community.admin'),
                                if (m.status == 'pending')
                                  t('community.pending'),
                              ].join(' · '),
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          if (manage && m.status == 'pending')
                            FilledButton.tonal(
                              key: Key('approve-${m.id}'),
                              style: compactButton,
                              onPressed: () => _do(
                                () => api.groupMemberAction(
                                  g.id,
                                  m.id,
                                  'approve',
                                  scope: widget.scope,
                                  gymId: widget.gymId,
                                ),
                              ),
                              child: Text(t('community.approve')),
                            ),
                          if (manage)
                            PopupMenuButton<String>(
                              onSelected: (v) => _do(
                                () => api.groupMemberAction(
                                  g.id,
                                  m.id,
                                  v,
                                  scope: widget.scope,
                                  gymId: widget.gymId,
                                ),
                              ),
                              itemBuilder: (_) => [
                                if (m.role != 'admin')
                                  PopupMenuItem(
                                    value: 'make_admin',
                                    child: Text(t('community.makeAdmin')),
                                  ),
                                if (m.role == 'admin')
                                  PopupMenuItem(
                                    value: 'make_member',
                                    child: Text(t('community.makeMember')),
                                  ),
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Text(t('community.removeMember')),
                                ),
                              ],
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

/// Groups a trainer or gym runs: create, open, manage.
class GroupManagerPage extends StatefulWidget {
  const GroupManagerPage({super.key, required this.scope, this.gymId});

  /// `trainer` or `owner`.
  final String scope;
  final String? gymId;

  @override
  State<GroupManagerPage> createState() => _GroupManagerPageState();
}

class _GroupManagerPageState extends State<GroupManagerPage> {
  List<SocialGroup>? _groups;
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
      ).api.ownedGroups(widget.scope, gymId: widget.gymId);
      if (mounted) {
        setState(
          () => _groups = [
            for (final g in (r['groups'] as List? ?? const []))
              if (g is Map) SocialGroup.fromJson(g),
          ],
        );
      }
    } catch (_) {
      if (mounted) setState(() => _groups = const []);
    }
  }

  void _open(SocialGroup g) => Navigator.of(context)
      .push(
        MaterialPageRoute<void>(
          builder: (_) => GroupPage(
            groupId: g.id,
            scope: widget.scope,
            gymId: widget.gymId,
          ),
        ),
      )
      .then((_) => _load());

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final api = AppScope.of(context).api;
    final groups = _groups;
    return Scaffold(
      appBar: AppBar(title: Text(t('community.yourGroups'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('owner-group-create'),
        onPressed: () async {
          final g = await showGroupForm(
            context,
            onSave: (body) async {
              final r = await api.createOwnedGroup(
                widget.scope,
                body,
                gymId: widget.gymId,
              );
              return SocialGroup.fromJson(r['group'] as Map? ?? const {});
            },
          );
          await _load();
          if (g != null && mounted) _open(g);
        },
        icon: const Icon(Icons.add),
        label: Text(t('community.createGroup')),
      ),
      body: groups == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                Text(
                  t('community.ownerIntro.${widget.scope}'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: FFTokens.spacingMd),
                if (groups.isEmpty)
                  FFEmptyState(title: t('community.noOwnedGroups')),
                for (final g in groups)
                  FFActionTile(
                    key: Key('owned-${g.id}'),
                    icon: Icons.groups_outlined,
                    title: g.name,
                    subtitle: [
                      t(
                        'community.members',
                      ).replaceAll('{n}', '${g.memberCount}'),
                      if (g.pending > 0)
                        t(
                          'community.requests',
                        ).replaceAll('{n}', '${g.pending}'),
                      if (g.inviteCode != null)
                        '${t('community.code')} ${g.inviteCode}',
                    ].join(' · '),
                    onTap: () => _open(g),
                  ),
              ],
            ),
    );
  }
}

void openGroupManager(
  BuildContext context, {
  required String scope,
  String? gymId,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => GroupManagerPage(scope: scope, gymId: gymId),
  ),
);
