import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/widgets/trainer_form_page.dart';
import 'owner_shell.dart';

/// Owner — trainer management view.
class OwnerTrainersPage extends StatelessWidget {
  const OwnerTrainersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = OwnerDataScope.of(context);
    final items = data.ownerTrainers;

    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        const SizedBox(height: 14),
        if (items.isEmpty)
          FFEmptyState(title: context.tr('member.noData'))
        else
          ...items.map(
            (t) => FFCard(
              child: Row(
                children: [
                  const Icon(
                    Icons.sports_gymnastics,
                    color: FFTokens.brandDark,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t['displayName']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          (t['specialties'] as List? ?? []).join(' / '),
                          style: const TextStyle(
                            color: FFTokens.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        if (t['phone'] != null)
                          Text(
                            t['phone'].toString(),
                            style: const TextStyle(
                              color: FFTokens.textMuted,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () => _showEditTrainerDialog(context, t),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.person_remove,
                      size: 20,
                      color: Colors.red,
                    ),
                    onPressed: () => _confirmRemoveTrainer(context, t),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _showAddTrainerDialog(context),
          icon: const Icon(Icons.add),
          label: Text(context.tr('owner.addTrainer')),
        ),
      ],
    );
  }

  Future<void> _showAddTrainerDialog(BuildContext context) async {
    final data = OwnerDataScope.of(context);
    final ownerGymIds = data.ownerGyms.map((g) => g['id'].toString()).toList();
    final payload = await openTrainerForm(
      context,
      title: context.tr('owner.addTrainer'),
      defaultGymIds: ownerGymIds,
    );
    if (payload == null) return;
    if (!context.mounted) return;
    final api = AppScope.of(context).api;
    final message = context.tr('owner.trainerAdded');
    try {
      await api.ownerAddTrainer(payload);
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

  Future<void> _showEditTrainerDialog(
    BuildContext context,
    Map<String, dynamic> trainer,
  ) async {
    final payload = await openTrainerForm(
      context,
      title: context.tr('owner.editTrainer'),
      initial: trainer,
    );
    if (payload == null) return;
    payload.remove('email');
    if (!context.mounted) return;
    final api = AppScope.of(context).api;
    final message = context.tr('owner.trainerUpdated');
    try {
      await api.ownerUpdateTrainer(trainer['id'].toString(), payload);
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Error ${e.status}')));
              }
            },
            child: Text(context.tr('owner.removeTrainer')),
          ),
        ],
      ),
    );
  }
}
