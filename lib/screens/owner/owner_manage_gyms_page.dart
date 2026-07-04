import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/widgets/gym_form_page.dart';
import 'owner_shell.dart';

/// Owner — manage gyms grid view with add / edit / delete.
class OwnerManageGymsPage extends StatelessWidget {
  const OwnerManageGymsPage({super.key});

  int _crossAxisCount(double width) {
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final data = OwnerDataScope.of(context);
    final ownerGymList = data.ownerGyms;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _crossAxisCount(constraints.maxWidth);
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                  0,
                ),
                child: Text(
                  context.tr('owner.gymProfile'),
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                    height: 1.35,
                  ),
                ),
              ),
            ),
            if (ownerGymList.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  child: FFEmptyState(title: context.tr('member.noData')),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _OwnerGymGridCard(
                      gym: ownerGymList[i],
                      onEdit: () =>
                          _showEditGymDialog(context, ownerGymList[i]),
                      onDelete: () =>
                          _confirmDeleteGym(context, ownerGymList[i]),
                    ),
                    childCount: ownerGymList.length,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: FFTokens.spacingMd,
                    mainAxisSpacing: FFTokens.spacingMd,
                    childAspectRatio: 0.65,
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  FFTokens.spacingLg,
                  ownerGymList.isEmpty ? 0 : 0,
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                ),
                child: OutlinedButton.icon(
                  onPressed: () => _showAddGymDialog(context),
                  icon: const Icon(Icons.add),
                  label: Text(context.tr('owner.addGym')),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddGymDialog(BuildContext context) async {
    final payload = await openGymForm(context);
    if (payload == null) return;
    if (!context.mounted) return;
    final api = AppScope.of(context).api;
    final message = context.tr('owner.gymAdded');
    try {
      await api.ownerCreateGym(payload);
      if (!context.mounted) return;
      final shell = context.findAncestorStateOfType<OwnerShellState>();
      await shell?.refreshAll();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error ${e.status}')));
    }
  }

  Future<void> _showEditGymDialog(
    BuildContext context,
    Map<String, dynamic> gym,
  ) async {
    final payload = await openGymForm(context, initial: gym);
    if (payload == null) return;
    if (!context.mounted) return;
    final api = AppScope.of(context).api;
    final message = context.tr('owner.gymUpdated');
    try {
      await api.ownerUpdateGym(gym['id'].toString(), payload);
      if (!context.mounted) return;
      final shell = context.findAncestorStateOfType<OwnerShellState>();
      await shell?.refreshAll();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error ${e.status}')));
    }
  }

  void _confirmDeleteGym(BuildContext context, Map<String, dynamic> gym) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('owner.deleteGym')),
        content: Text(context.tr('owner.confirmDelete')),
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
              final message = context.tr('owner.gymDeleted');
              try {
                await api.ownerDeleteGym(gym['id'].toString());
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
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Error ${e.status}')));
              }
            },
            child: Text(context.tr('owner.deleteGym')),
          ),
        ],
      ),
    );
  }
}

class _OwnerGymGridCard extends StatelessWidget {
  const _OwnerGymGridCard({
    required this.gym,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> gym;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final images = (gym['images'] as List?)?.whereType<String>().toList() ?? [];
    final thumbnails =
        (gym['thumbnails'] as List?)?.whereType<String>().toList() ?? [];
    final coverThumbnail = thumbnails.isNotEmpty
        ? thumbnails.first
        : (images.isNotEmpty ? images.first : null);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(FFTokens.radiusLg),
            ),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: coverThumbnail == null
                  ? Container(
                      color: cs.primary.withValues(alpha: 0.1),
                      child: Icon(
                        Icons.fitness_center,
                        size: 36,
                        color: cs.primary,
                      ),
                    )
                  : FFRemoteImage(
                      src: coverThumbnail,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      fallback: Container(
                        color: cs.primary.withValues(alpha: 0.1),
                        child: Icon(
                          Icons.fitness_center,
                          size: 36,
                          color: cs.primary,
                        ),
                      ),
                    ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gym['name']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    gym['location']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      FFPill(label: gym['tier']?.toString() ?? ''),
                      FFPill(
                        label:
                            gym['status']?.toString() ??
                            context.tr('ownerReg.status_active'),
                      ),
                    ],
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
                icon: const Icon(Icons.edit, size: 18),
                onPressed: onEdit,
                tooltip: context.tr('owner.editGym'),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
                onPressed: onDelete,
                tooltip: context.tr('owner.deleteGym'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
