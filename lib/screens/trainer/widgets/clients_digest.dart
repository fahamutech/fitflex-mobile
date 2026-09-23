import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../shared/activity/trainer_connection.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import 'client_summary_card.dart';

/// Trainer Home: who to check in with today, in a few lines. Opens the
/// Clients tab for everything else.
class ClientsDigest extends StatefulWidget {
  const ClientsDigest({super.key, required this.onOpenClients});

  final VoidCallback onOpenClients;

  @override
  State<ClientsDigest> createState() => _ClientsDigestState();
}

class _ClientsDigestState extends State<ClientsDigest> {
  List<TrainerConnection>? _clients;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_clients == null) _load();
  }

  Future<void> _load() async {
    try {
      final rows = await AppScope.of(context).api.trainerClients();
      if (!mounted) return;
      setState(
        () => _clients = [
          for (final r in rows.whereType<Map>())
            TrainerConnection.fromJson(Map<String, dynamic>.from(r)),
        ],
      );
    } catch (_) {
      // The Clients tab shows errors; Home just leaves this out.
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = _clients;
    if (clients == null || clients.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final requests = clients
        .where((c) => c.status == TrainerConnectionStatus.pending)
        .length;
    final active = clients
        .where((c) => c.status == TrainerConnectionStatus.active)
        .toList();
    final toCheck = active
        .where((c) => (c.summary?.needsAttention ?? const []).isNotEmpty)
        .toList();
    return FFCard(
      key: const Key('trainer-clients-digest'),
      margin: const EdgeInsets.only(top: FFTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('clients.title'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            [
              context
                  .tr('digest.clientCount')
                  .replaceAll('{n}', '${active.length}'),
              if (requests > 0)
                context
                    .tr('digest.requestCount')
                    .replaceAll('{n}', '$requests'),
              context
                  .tr('digest.toCheck')
                  .replaceAll('{n}', '${toCheck.length}'),
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          for (final c in toCheck.take(3))
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingSm),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: FFTokens.iconSm,
                    color: FFTokens.warning500,
                  ),
                  const SizedBox(width: FFTokens.spacingSm),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${c.member?.displayName ?? ''}: ',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text: promptText(
                              context,
                              c.summary!.needsAttention.first,
                            ),
                          ),
                        ],
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('trainer-digest-open'),
              onPressed: widget.onOpenClients,
              child: Text(context.tr('digest.seeClients')),
            ),
          ),
        ],
      ),
    );
  }
}
