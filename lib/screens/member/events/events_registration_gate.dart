import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../router.dart';
import '../../../shared/components/components.dart';
import '../../../shared/events/events_options.dart';
import '../../../shared/events_flag.dart';
import '../../../shared/i18n.dart';
import '../member_shell.dart';

/// The server's events options for [context]: the page's own when given,
/// else the member scope's, else off.
EventsOptions eventsOptionsOf(BuildContext context, EventsOptions? own) =>
    own ??
    context
        .dependOnInheritedWidgetOfExactType<MemberDataScope>()
        ?.notifier
        ?.eventsOptions ??
    EventsOptions.off;

/// Events S3 spec §4: with the build flag off or options `registration:
/// false`, every S3 route sends the member to Activity with an info snack.
/// Returns true when the page may render. Call from `initState` (post
/// frame) or `didChangeDependencies`.
bool eventsRegistrationAllowed(BuildContext context, EventsOptions options) {
  if (eventsDiscoveryEnabled && options.registration) return true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    FFSnack.info(context, context.tr('events.register.unavailable'));
    context.go(AppRoutes.memberActivity);
  });
  return false;
}
