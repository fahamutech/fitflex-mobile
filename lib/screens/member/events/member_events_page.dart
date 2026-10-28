import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../router.dart';
import '../../../shared/components/components.dart';
import '../../../shared/i18n.dart';
import '../member_shell.dart';
import 'events_discovery_view.dart';

/// `/member/events` (events S2 spec §11.1): the discovery list as a full
/// page with an app bar. Back pops to whatever pushed it, or Activity when
/// opened cold. With the server probe off it shows the unavailable state.
class MemberEventsPage extends StatelessWidget {
  const MemberEventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(AppRoutes.memberActivity),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.title')),
      ),
      body: data.eventsDiscovery
          ? const EventsDiscoveryView(key: Key('events-page'))
          : Center(
              child: FFEmptyState(
                key: const Key('events-unavailable'),
                icon: Icons.flag_outlined,
                title: context.tr('events.unavailable.title'),
                body: context.tr('events.unavailable.body'),
              ),
            ),
    );
  }
}
