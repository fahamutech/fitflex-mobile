import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/widgets/gym_form_page.dart';
import 'owner_shell.dart';

/// Owner — manage gyms list view with add / edit / delete.
class OwnerManageGymsPage extends StatelessWidget {
  const OwnerManageGymsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = OwnerDataScope.of(context);
    final ownerGymList = data.ownerGyms;

    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Text(
          context.tr('owner.gymProfile'),
          style: const TextStyle(color: FFTokens.textMuted, height: 1.35),
        ),
        const SizedBox(height: 14),
        if (ownerGymList.isEmpty)
          FFEmptyState(title: context.tr('member.noData'))
        else
          ...ownerGymList.map((gym) => _OwnerGymCard(gym: gym)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _showAddGymDialog(context),
          icon: const Icon(Icons.add),
          label: Text(context.tr('owner.addGym')),
        ),
      ],
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
}

class _OwnerGymCard extends StatelessWidget {
  const _OwnerGymCard({required this.gym});

  final Map<String, dynamic> gym;

  @override
  Widget build(BuildContext context) {
    return FFCard(
      child: InkWell(
        onTap: () {
          // Could navigate to checkins detail
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 86, height: 86, child: _gymThumb(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gym['name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    gym['location']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: FFTokens.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
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
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: context.tr('owner.editGym'),
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _showEditGymDialog(context),
                ),
                IconButton(
                  tooltip: context.tr('owner.deleteGym'),
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.red,
                  ),
                  onPressed: () => _confirmDeleteGym(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _gymThumb(BuildContext context) {
    final images = (gym['images'] as List?)?.whereType<String>().toList() ?? [];
    if (images.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: FFTokens.brandLight,
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        ),
        child: const Icon(Icons.fitness_center, color: FFTokens.brandDark),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(FFTokens.radiusMd),
      child: FFRemoteImage(
        src: images.first,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        fallback: Container(
          color: FFTokens.brandLight,
          child: const Icon(Icons.fitness_center, color: FFTokens.brandDark),
        ),
      ),
    );
  }

  Future<void> _showEditGymDialog(BuildContext context) async {
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

  void _confirmDeleteGym(BuildContext context) {
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
