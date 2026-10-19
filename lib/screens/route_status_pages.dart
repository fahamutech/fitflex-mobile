// Pages the router shows when it cannot show the page asked for: the
// account could not be loaded at start-up (H6), or the address matches no
// page (D7).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_scope.dart';
import '../router.dart';
import '../shared/components/components.dart';
import '../shared/design_tokens.dart';
import '../shared/i18n.dart';

/// Signed in, but the account could not be loaded (offline, timeout, server
/// error) and this device does not know enough to pick the right screen.
/// Never the setup flow: that would ask a member who finished it to start
/// again. Retry loads the account; the router moves on once it is in.
class StartupOfflinePage extends StatefulWidget {
  const StartupOfflinePage({super.key});

  @override
  State<StartupOfflinePage> createState() => _StartupOfflinePageState();
}

class _StartupOfflinePageState extends State<StartupOfflinePage> {
  bool _busy = false;
  bool _failedAgain = false;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await AppScope.of(context).auth.retryProfile();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failedAgain = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return Scaffold(
      key: const Key('startup-offline'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FFErrorState(
                  icon: Icons.cloud_off_outlined,
                  title: context.tr('startup.offline.title'),
                  message: context.tr(
                    _failedAgain
                        ? 'startup.offline.stillOffline'
                        : 'startup.offline.body',
                  ),
                ),
                const SizedBox(height: FFTokens.spacingMd),
                FFButton(
                  key: const Key('startup-offline-retry'),
                  label: context.tr('common.retry'),
                  icon: Icons.refresh,
                  loading: _busy,
                  onPressed: _retry,
                ),
                const SizedBox(height: FFTokens.spacingSm),
                FFButton(
                  key: const Key('startup-offline-sign-out'),
                  label: context.tr('home.signout'),
                  variant: FFButtonVariant.ghost,
                  onPressed: _busy ? null : auth.signOut,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An address that matches no page (a typed or old link such as
/// /vendor/orders): says so in the user's language and leads home, instead
/// of the router's raw "GoException" text.
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return Scaffold(
      key: const Key('not-found'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FFErrorState(
                  icon: Icons.explore_off_outlined,
                  title: context.tr('notFound.title'),
                  message: context.tr('notFound.body'),
                ),
                const SizedBox(height: FFTokens.spacingMd),
                FFButton(
                  key: const Key('not-found-home'),
                  label: context.tr('notFound.home'),
                  icon: Icons.home_outlined,
                  onPressed: () => context.go(
                    auth.isSignedIn
                        ? routeForSignedInUser(auth)
                        : AppRoutes.language,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
