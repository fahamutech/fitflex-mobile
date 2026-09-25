import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../shared/activity/activity.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/social.dart';
import '../member_shell.dart';

/// "Private", "Friends", "Friends · Dar Runners", "My company"…
String shareLabel(
  BuildContext context,
  ShareWith? s, {
  Map<String, String> groupNames = const {},
}) {
  if (s == null || s.isPrivate) return context.tr('audience.private');
  return [
    if (s.public) context.tr('audience.public'),
    if (s.followers) context.tr('audience.followers'),
    if (s.friends) context.tr('audience.friends'),
    for (final g in s.groups) groupNames[g] ?? context.tr('audience.aGroup'),
    if (s.company) context.tr('audience.company'),
  ].join(' · ');
}

/// Pick who can see an activity. Returns the choice (null = private), or
/// [cancelled] when dismissed.
Future<({ShareWith? share, bool cancelled})> pickShare(
  BuildContext context, {
  ShareWith? initial,
  String? title,
}) async {
  final res = await showModalBottomSheet<({ShareWith? share})>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SharePicker(initial: initial, title: title),
  );
  return res == null
      ? (share: initial, cancelled: true)
      : (share: res.share, cancelled: false);
}

class _SharePicker extends StatefulWidget {
  const _SharePicker({this.initial, this.title});

  final ShareWith? initial;
  final String? title;

  @override
  State<_SharePicker> createState() => _SharePickerState();
}

class _SharePickerState extends State<_SharePicker> {
  late bool _friends = widget.initial?.friends ?? false;
  late bool _followers = widget.initial?.followers ?? false;
  late bool _public = widget.initial?.public ?? false;
  bool _publicProfile = false;
  late final Set<String> _groups = {...?widget.initial?.groups};
  late bool _company = widget.initial?.company ?? false;
  List<SocialGroup>? _mine;
  bool _hasCompany = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final api = AppScope.of(context).api;
    try {
      final r = await Future.wait([api.myGroups(), api.socialSettings()]);
      if (!mounted) return;
      setState(() {
        _mine = [
          for (final g in (r[0]['groups'] as List? ?? const []))
            if (g is Map && SocialGroup.fromJson(g).isMember)
              SocialGroup.fromJson(g),
        ];
        _hasCompany = r[1]['hasCompany'] == true;
        _publicProfile = r[1]['publicProfile'] == true;
        if (!_publicProfile) _public = false;
      });
    } catch (_) {
      if (mounted) setState(() => _mine = const []);
    }
  }

  ShareWith? get _choice {
    final s = ShareWith(
      friends: _friends,
      followers: _followers,
      public: _public,
      groups: _groups.toList(),
      company: _company,
    );
    return s.isPrivate ? null : s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final private = _choice == null;
    return SafeArea(
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
              widget.title ?? context.tr('audience.title'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: FFTokens.spacingXs),
            Text(context.tr('audience.body'), style: theme.textTheme.bodySmall),
            const SizedBox(height: FFTokens.spacingSm),
            ListTile(
              key: const Key('share-private'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                private
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: theme.colorScheme.primary,
              ),
              onTap: () => setState(() {
                _friends = false;
                _followers = false;
                _public = false;
                _groups.clear();
                _company = false;
              }),
              title: Text(context.tr('audience.private')),
              subtitle: Text(context.tr('audience.privateHint')),
            ),
            CheckboxListTile(
              key: const Key('share-public'),
              contentPadding: EdgeInsets.zero,
              value: _public,
              onChanged: _publicProfile
                  ? (v) => setState(() => _public = v ?? false)
                  : null,
              title: Text(context.tr('audience.public')),
              subtitle: Text(
                context.tr(
                  _publicProfile
                      ? 'audience.publicHint'
                      : 'audience.publicNeedsProfile',
                ),
              ),
            ),
            CheckboxListTile(
              key: const Key('share-followers'),
              contentPadding: EdgeInsets.zero,
              value: _followers,
              onChanged: (v) => setState(() => _followers = v ?? false),
              title: Text(context.tr('audience.followers')),
              subtitle: Text(context.tr('audience.followersHint')),
            ),
            CheckboxListTile(
              key: const Key('share-friends'),
              contentPadding: EdgeInsets.zero,
              value: _friends,
              onChanged: (v) => setState(() => _friends = v ?? false),
              title: Text(context.tr('audience.friends')),
              subtitle: Text(context.tr('audience.friendsHint')),
            ),
            if (_mine == null)
              const Padding(
                padding: EdgeInsets.all(FFTokens.spacingSm),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final g in _mine!)
                CheckboxListTile(
                  key: Key('share-group-${g.id}'),
                  contentPadding: EdgeInsets.zero,
                  value: _groups.contains(g.id),
                  onChanged: (v) => setState(
                    () => v == true ? _groups.add(g.id) : _groups.remove(g.id),
                  ),
                  title: Text(g.name),
                  subtitle: Text(context.tr('audience.groupHint')),
                ),
            if (_hasCompany)
              CheckboxListTile(
                key: const Key('share-company'),
                contentPadding: EdgeInsets.zero,
                value: _company,
                onChanged: (v) => setState(() => _company = v ?? false),
                title: Text(context.tr('audience.company')),
                subtitle: Text(context.tr('audience.companyHint')),
              ),
            const SizedBox(height: FFTokens.spacingSm),
            Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: FFTokens.spacingXs),
                Expanded(
                  child: Text(
                    context.tr('audience.neverShared'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingMd),
            FilledButton(
              key: const Key('share-done'),
              onPressed: () => Navigator.pop(context, (share: _choice)),
              child: Text(context.tr('audience.done')),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row showing who can see something, which opens the picker.
class ShareRow extends StatelessWidget {
  const ShareRow({
    super.key,
    required this.share,
    required this.onChanged,
    this.groupNames = const {},
  });

  final ShareWith? share;
  final ValueChanged<ShareWith?> onChanged;
  final Map<String, String> groupNames;

  @override
  Widget build(BuildContext context) => FFActionTile(
    key: const Key('share-row'),
    icon: share == null ? Icons.lock_outline : Icons.people_outline,
    title: context.tr('audience.whoCanSee'),
    subtitle: shareLabel(context, share, groupNames: groupNames),
    onTap: () async {
      final r = await pickShare(context, initial: share);
      if (!r.cancelled) onChanged(r.share);
    },
  );
}

/// Change who can see one of the member's own activities, and update it
/// everywhere on screen.
Future<void> editActivitySharing(BuildContext context, Activity a) async {
  final api = AppScope.of(context).api;
  final data = context
      .getInheritedWidgetOfExactType<MemberDataScope>()
      ?.notifier;
  final messenger = ScaffoldMessenger.of(context);
  final done = context.tr('audience.savedToast');
  final failed = context.tr('community.error.generic');
  final r = await pickShare(context, initial: ShareWith.fromJson(a.shareWith));
  if (r.cancelled) return;
  try {
    final res = await api.shareActivity(a.id, ShareWith.wire(r.share));
    final share = res['shareWith'] is Map
        ? Map<String, dynamic>.from(res['shareWith'] as Map)
        : null;
    data?.update(
      (d) => d.activities = [
        for (final x in d.activities)
          x.id == a.id
              ? Activity.fromJson({...x.toJson(), 'shareWith': share})
              : x,
      ],
    );
    messenger.showSnackBar(SnackBar(content: Text(done)));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }
}

/// Privacy & data: the default audience for new activities, and blocked
/// people.
class SocialPrivacySection extends StatefulWidget {
  const SocialPrivacySection({super.key});

  @override
  State<SocialPrivacySection> createState() => _SocialPrivacySectionState();
}

class _SocialPrivacySectionState extends State<SocialPrivacySection> {
  SocialSettings? _s;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    if (scope == null) return;
    try {
      final r = await scope.api.socialSettings();
      if (mounted) setState(() => _s = SocialSettings.fromJson(r));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const SizedBox.shrink();
    final api = AppScope.of(context).api;
    final t = context.tr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FFSectionTitle(t('audience.sectionTitle')),
        FFCard(
          margin: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: SwitchListTile(
            key: const Key('privacy-public-profile'),
            contentPadding: EdgeInsets.zero,
            value: s.publicProfile,
            title: Text(t('audience.publicProfile')),
            subtitle: Text(t('audience.publicProfileHint')),
            onChanged: (on) async {
              await api.setPublicProfile(on);
              await _load();
            },
          ),
        ),
        FFActionTile(
          key: const Key('privacy-default-share'),
          icon: s.defaultShare == null
              ? Icons.lock_outline
              : Icons.people_outline,
          title: t('audience.defaultTitle'),
          subtitle: shareLabel(context, s.defaultShare),
          onTap: () async {
            final r = await pickShare(
              context,
              initial: s.defaultShare,
              title: t('audience.defaultTitle'),
            );
            if (r.cancelled) return;
            await api.updateSocialSettings(ShareWith.wire(r.share));
            await _load();
          },
        ),
        FFActionTile(
          key: const Key('privacy-blocked'),
          icon: Icons.block,
          title: t('audience.blockedTitle'),
          subtitle: s.blocked.isEmpty
              ? t('audience.noneBlocked')
              : s.blocked.map((p) => p.name).join(', '),
          onTap: s.blocked.isEmpty
              ? () {}
              : () async {
                  await showModalBottomSheet<void>(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final p in s.blocked)
                            ListTile(
                              title: Text(p.name),
                              trailing: TextButton(
                                onPressed: () async {
                                  await api.unblock(p.id);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                                child: Text(t('audience.unblock')),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                  await _load();
                },
        ),
      ],
    );
  }
}
