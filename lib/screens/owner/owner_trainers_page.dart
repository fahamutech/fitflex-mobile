import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import '../../shared/widgets/photo_gallery.dart';
import '../../shared/widgets/social_links.dart';
import '../../shared/widgets/trainer_form_page.dart';
import 'owner_shell.dart';
import '../../shared/widgets/invitations.dart';

String _apiErrorMessage(BuildContext context, ApiException e) {
  final code = (e.body is Map) ? (e.body as Map)['error']?.toString() : null;
  switch (code) {
    case 'email_already_in_use':
    case 'email_already_used_for_trainer':
      return context.tr('owner.errorEmailAlreadyInUse');
    default:
      return context.tr('owner.errorGeneric');
  }
}

/// Owner — trainer management view. Trainers self-register and then apply to
/// join a gym; the owner reviews pending applications here before the
/// trainer becomes linked and visible to members.
class OwnerTrainersPage extends StatelessWidget {
  const OwnerTrainersPage({super.key});

  int _crossAxisCount(double width) {
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final data = OwnerDataScope.of(context);
    final items = data.ownerTrainers;
    final pending = data.pendingTrainerRequests;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _crossAxisCount(constraints.maxWidth);
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                FFTokens.spacingLg,
                FFTokens.spacingLg,
                FFTokens.spacingLg,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    key: const Key('owner-add-trainer'),
                    onPressed: () => _createTrainer(context, data.ownerGyms),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: Text(context.tr('owner.addTrainer')),
                  ),
                ),
              ),
            ),
            if (pending.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: _PendingTrainerRequests(requests: pending),
                ),
              ),
            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  child: _EmptyTrainers(),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                ),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _OwnerTrainerGridCard(
                      trainer: items[i],
                      onView: () => _viewTrainer(context, items[i]),
                      onRemove: () => _confirmRemoveTrainer(context, items[i]),
                    ),
                    childCount: items.length,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: FFTokens.spacingMd,
                    mainAxisSpacing: FFTokens.spacingMd,
                    childAspectRatio: 0.64,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _createTrainer(
    BuildContext context,
    List<Map<String, dynamic>> gyms,
  ) async {
    if (gyms.isEmpty) return;
    final gymId = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              child: Text(
                sheetContext.tr('owner.chooseTrainerGym'),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            ...gyms.map(
              (gym) => ListTile(
                key: Key('owner-trainer-gym-${gym['id']}'),
                title: Text(gym['name']?.toString() ?? ''),
                onTap: () => Navigator.pop(sheetContext, gym['id']?.toString()),
              ),
            ),
          ],
        ),
      ),
    );
    if (gymId == null || !context.mounted) return;
    // Identity V2: a trainer is invited and joins with their own profile.
    if (AppScope.of(context).auth.invitesEnabled) {
      await openInvitePersonSheet(context, gymId: gymId, role: 'trainer');
      return;
    }
    final payload = await openTrainerForm(
      context,
      title: context.tr('owner.addTrainer'),
      defaultGymIds: [gymId],
      requireInitialPin: true,
    );
    if (payload == null || !context.mounted) return;
    payload['gymId'] = gymId;
    try {
      await AppScope.of(context).api.ownerCreateTrainer(payload);
      if (!context.mounted) return;
      await context.findAncestorStateOfType<OwnerShellState>()?.refreshAll();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('owner.trainerAdded'))));
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_apiErrorMessage(context, e))));
    }
  }

  /// A trainer's profile belongs to the trainer: the owner can look at it,
  /// but only the trainer changes it.
  void _viewTrainer(BuildContext context, Map<String, dynamic> trainer) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OwnerTrainerProfilePage(trainer: trainer),
      ),
    );
  }

  void _confirmRemoveTrainer(
    BuildContext context,
    Map<String, dynamic> trainer,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('owner.removeTrainer')),
        content: Text(context.tr('owner.confirmRemoveTrainer')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('member.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final api = AppScope.of(context).api;
              final message = context.tr('owner.trainerRemoved');
              try {
                await api.ownerRemoveTrainer(trainer['id'].toString());
                if (!context.mounted) return;
                final shell = context
                    .findAncestorStateOfType<OwnerShellState>();
                await shell?.refreshAll();
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(message)));
              } on ApiException catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_apiErrorMessage(context, e))),
                );
              }
            },
            child: Text(context.tr('owner.removeTrainer')),
          ),
        ],
      ),
    );
  }
}

class _OwnerTrainerGridCard extends StatelessWidget {
  const _OwnerTrainerGridCard({
    required this.trainer,
    required this.onView,
    required this.onRemove,
  });

  final Map<String, dynamic> trainer;
  final VoidCallback onView;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name = trainer['displayName']?.toString() ?? '';
    final specialties = (trainer['specialties'] as List? ?? [])
        .take(2)
        .join(' · ');
    final phone = trainer['phone']?.toString();
    final photoUrl = trainer['photoUrl']?.toString();
    final initials = name
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: InkWell(
              key: Key('owner-trainer-open-${trainer['id']}'),
              onTap: onView,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(FFTokens.radiusLg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(FFTokens.radiusLg),
                    ),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: photoUrl != null && photoUrl.isNotEmpty
                          ? FFRemoteImage(
                              src: photoUrl,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              fallback: _initials(cs, initials),
                            )
                          : _initials(cs, initials),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (specialties.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              specialties,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall?.copyWith(fontSize: 11),
                            ),
                          ],
                          if (phone != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              phone,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall?.copyWith(fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: cs.outlineVariant),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                key: Key('owner-trainer-view-${trainer['id']}'),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                onPressed: onView,
                tooltip: context.tr('owner.viewTrainer'),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: Icon(Icons.person_remove, size: 18, color: cs.error),
                onPressed: onRemove,
                tooltip: context.tr('owner.removeTrainer'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _initials(ColorScheme cs, String initials) => Container(
    color: cs.primary.withValues(alpha: 0.12),
    child: Center(
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: cs.primary,
        ),
      ),
    ),
  );
}

/// Owner — a trainer's profile, to read only. Photos, details, contact and
/// social profiles are the trainer's own; nothing here can be changed.
class OwnerTrainerProfilePage extends StatelessWidget {
  const OwnerTrainerProfilePage({super.key, required this.trainer});

  final Map<String, dynamic> trainer;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final profile = TrainerProfile.fromJson(trainer);
    final phone = trainer['phone']?.toString() ?? '';
    final email = trainer['email']?.toString() ?? '';
    final bio = profile.bio ?? '';
    final availability = (trainer['availability'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final rate = profile.hourlyRateTzs;

    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FFSectionTitle(title),
          const SizedBox(height: FFTokens.spacingSm),
          ...children,
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('owner.viewTrainer'))),
      body: ListView(
        key: const Key('owner-trainer-profile'),
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          if (profile.photos.isNotEmpty)
            PhotoGallery(
              key: const Key('owner-trainer-gallery'),
              images: profile.photos,
              keyPrefix: 'owner-trainer',
              emptyIcon: Icons.person,
              height: 220,
            ),
          const SizedBox(height: FFTokens.spacingMd),
          Text(
            profile.displayName,
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          // Clients see the nickname; the gym also knows the trainer's own name.
          if ((trainer['nickname']?.toString() ?? '').isNotEmpty &&
              (trainer['fullName']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              trainer['fullName'].toString(),
              key: const Key('owner-trainer-fullname'),
              style: tt.bodyMedium,
            ),
          ],
          if (rate > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${profile.sessionRateCurrency} ${rate.toStringAsFixed(0)}',
              style: tt.bodyMedium,
            ),
          ],
          const SizedBox(height: FFTokens.spacingMd),
          FFCard(
            key: const Key('owner-trainer-readonly-note'),
            child: Row(
              children: [
                const Icon(Icons.lock_outline, size: 18),
                const SizedBox(width: FFTokens.spacingSm),
                Expanded(
                  child: Text(
                    context.tr('owner.trainerReadOnly'),
                    style: tt.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          if (phone.isNotEmpty || email.isNotEmpty)
            section(context.tr('trainer.contact'), [
              if (phone.isNotEmpty)
                _ProfileLine(icon: Icons.phone_outlined, text: phone),
              if (email.isNotEmpty)
                _ProfileLine(icon: Icons.mail_outline, text: email),
            ]),
          if (!profile.socialLinks.isEmpty)
            section(context.tr('owner.trainerSocial'), [
              SocialLinksRow(
                key: const Key('owner-trainer-socials'),
                links: profile.socialLinks,
              ),
            ]),
          if (profile.specialties.isNotEmpty)
            section(context.tr('trainerReg.specialties'), [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in profile.specialties) Chip(label: Text(s)),
                ],
              ),
            ]),
          if (bio.isNotEmpty)
            section(context.tr('trainerReg.bio'), [
              Text(bio, style: tt.bodyMedium),
            ]),
          if (availability.isNotEmpty)
            section(context.tr('trainer.availability'), [
              for (final a in availability)
                _ProfileLine(
                  icon: Icons.schedule,
                  text: [
                    a['day']?.toString() ?? '',
                    (a['slots'] as List? ?? []).join(', '),
                  ].where((v) => v.isNotEmpty).join(' · '),
                ),
            ]),
        ],
      ),
    );
  }
}

class _ProfileLine extends StatelessWidget {
  const _ProfileLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: FFTokens.spacingSm),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _EmptyTrainers extends StatelessWidget {
  const _EmptyTrainers();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingXl),
      child: FFEmptyState(
        title: context.tr('owner.noTrainersTitle'),
        body: context.tr('owner.noTrainersBody'),
      ),
    );
  }
}

/// Trainers who self-registered and applied to join one of the owner's
/// gyms — the owner approves or rejects each request before the trainer is
/// linked to the gym and visible to members.
class _PendingTrainerRequests extends StatelessWidget {
  const _PendingTrainerRequests({required this.requests});

  final List<Map<String, dynamic>> requests;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: Text(
            context.tr('owner.pendingTrainerRequests'),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        ...requests.expand((trainer) {
          final pendingGyms = (trainer['pendingGyms'] as List? ?? [])
              .whereType<Map>()
              .map(Map<String, dynamic>.from);
          return pendingGyms.map(
            (gym) => _PendingTrainerCard(trainer: trainer, gym: gym),
          );
        }),
        const SizedBox(height: FFTokens.spacingSm),
      ],
    );
  }
}

class _PendingTrainerCard extends StatefulWidget {
  const _PendingTrainerCard({required this.trainer, required this.gym});

  final Map<String, dynamic> trainer;
  final Map<String, dynamic> gym;

  @override
  State<_PendingTrainerCard> createState() => _PendingTrainerCardState();
}

class _PendingTrainerCardState extends State<_PendingTrainerCard> {
  bool _busy = false;

  Future<void> _decide(String decision) async {
    setState(() => _busy = true);
    final api = AppScope.of(context).api;
    final message = decision == 'approve'
        ? context.tr('owner.trainerApproved')
        : context.tr('owner.trainerRejected');
    try {
      await api.ownerDecideTrainerJoin(
        widget.trainer['id'].toString(),
        gymId: widget.gym['id'].toString(),
        decision: decision,
      );
      if (!mounted) return;
      final shell = context.findAncestorStateOfType<OwnerShellState>();
      await shell?.refreshAll();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_apiErrorMessage(context, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.trainer['displayName']?.toString() ?? '';
    final specialties = (widget.trainer['specialties'] as List? ?? [])
        .take(2)
        .join(' · ');
    final gymName = widget.gym['name']?.toString() ?? '';

    return FFCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  specialties.isNotEmpty ? '$specialties · $gymName' : gymName,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            IconButton(
              icon: Icon(
                Icons.close,
                color: Theme.of(context).colorScheme.error,
              ),
              tooltip: context.tr('owner.reject'),
              onPressed: () => _decide('reject'),
            ),
            IconButton(
              icon: const Icon(Icons.check_circle, color: Colors.green),
              tooltip: context.tr('owner.approve'),
              onPressed: () => _decide('approve'),
            ),
          ],
        ],
      ),
    );
  }
}
