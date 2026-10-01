import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../api_client.dart';
import '../api_error_message.dart';
import '../components/ff_action_tile.dart';
import '../design_tokens.dart';
import '../i18n.dart';

/// Human label for a persona's userType.
String personaLabel(BuildContext context, Object? userType) {
  switch (userType?.toString()) {
    case 'member':
      return context.tr('role.member');
    case 'trainer':
      return context.tr('role.trainer');
    case 'gym_operator':
      return context.tr('role.owner');
    case 'gym_staff':
      return context.tr('role.staff');
    case 'vendor':
    case 'vendor_staff':
      return context.tr('role.vendor');
    default:
      return userType?.toString() ?? '';
  }
}

IconData _personaIcon(Object? userType) {
  switch (userType?.toString()) {
    case 'trainer':
      return Icons.fitness_center;
    case 'gym_operator':
    case 'gym_staff':
      return Icons.store_mall_directory_outlined;
    case 'vendor':
    case 'vendor_staff':
      return Icons.shopping_bag_outlined;
    default:
      return Icons.person_outline;
  }
}

/// Switch this session to [personaId], then route to that persona's home.
Future<void> switchToPersona(BuildContext context, String personaId) async {
  final auth = AppScope.of(context).auth;
  final messenger = ScaffoldMessenger.of(context);
  final locale = FFLocaleScope.of(context);
  final failed = context.tr('persona.switchFailed');
  try {
    if (personaId == auth.user?['id']) {
      auth.keepCurrentPersona();
    } else {
      await auth.switchPersona(personaId);
    }
    if (context.mounted) context.go(routeForSignedInUser(auth));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('$failed ${errorMessage(locale, e)}'.trim())),
    );
  }
}

/// What adding each role is called, e.g. "Become a trainer".
String addPersonaLabel(BuildContext context, String userType) {
  switch (userType) {
    case 'trainer':
      return context.tr('persona.addTrainer');
    case 'gym_operator':
      return context.tr('persona.addOwner');
    case 'vendor':
      return context.tr('persona.addVendor');
    default:
      return context.tr('persona.addMember');
  }
}

/// Add [userType] to this Person and continue as it. The router then sends
/// the new persona through that role's own registration.
Future<void> addPersonaAndContinue(
  BuildContext context,
  String userType,
) async {
  final auth = AppScope.of(context).auth;
  final messenger = ScaffoldMessenger.of(context);
  final locale = FFLocaleScope.of(context);
  final failed = context.tr('persona.addFailed');
  final inUse = context.tr('persona.addInUse');
  try {
    await auth.addPersona(userType);
    if (context.mounted) context.go(routeForSignedInUser(auth));
  } on ApiException catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          e.code == 'persona_identifier_in_use'
              ? inUse
              : '$failed ${errorMessage(locale, e)}'.trim(),
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('$failed ${errorMessage(locale, e)}'.trim())),
    );
  }
}

/// Bottom sheet: switch to another persona, or add a role this Person
/// doesn't have yet.
Future<void> showPersonaSwitcher(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final auth = AppScope.of(context).auth;
      final others = auth.switchablePersonas;
      final addable = auth.addablePersonaTypes;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            FFTokens.spacingMd,
            0,
            FFTokens.spacingMd,
            FFTokens.spacingMd,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (others.isNotEmpty) ...[
                Text(
                  context.tr('persona.switchTitle'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: FFTokens.spacingSm),
              ],
              for (final p in others)
                ListTile(
                  key: Key('persona-${p['id']}'),
                  leading: Icon(_personaIcon(p['userType'])),
                  title: Text(personaLabel(context, p['userType'])),
                  subtitle: p['approvalStatus'] == 'pending_approval'
                      ? Text(context.tr('persona.pending'))
                      : null,
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await switchToPersona(context, p['id'].toString());
                  },
                ),
              if (addable.isNotEmpty) ...[
                if (others.isNotEmpty) const Divider(),
                Text(
                  context.tr('persona.addTitle'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: FFTokens.spacingSm),
                for (final type in addable)
                  ListTile(
                    key: Key('add-persona-$type'),
                    leading: const Icon(Icons.add_circle_outline),
                    title: Text(addPersonaLabel(context, type)),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await addPersonaAndContinue(context, type);
                    },
                  ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// "Switch role" tile for profile pages. Renders nothing unless the Person
/// has another usable persona or can add one, so nothing shows before V2.
class PersonaSwitcherTile extends StatelessWidget {
  const PersonaSwitcherTile({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final others = auth.switchablePersonas;
        if (others.isEmpty && auth.addablePersonaTypes.isEmpty) {
          return const SizedBox.shrink();
        }
        return FFActionTile(
          key: const Key('persona-switch'),
          icon: Icons.swap_horiz,
          title: context.tr(
            others.isEmpty ? 'persona.roles' : 'persona.switch',
          ),
          subtitle: others.isEmpty
              ? context.tr('persona.addTitle')
              : others
                    .map((p) => personaLabel(context, p['userType']))
                    .join(' · '),
          onTap: () => showPersonaSwitcher(context),
        );
      },
    );
  }
}

/// App-bar variant for screens without a profile list (vendor).
class PersonaSwitchButton extends StatelessWidget {
  const PersonaSwitchButton({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        if (auth.switchablePersonas.isEmpty &&
            auth.addablePersonaTypes.isEmpty) {
          return const SizedBox.shrink();
        }
        return IconButton(
          key: const Key('persona-switch-button'),
          tooltip: context.tr('persona.switch'),
          icon: const Icon(Icons.swap_horiz),
          onPressed: () => showPersonaSwitcher(context),
        );
      },
    );
  }
}

/// Shown after sign-in when the backend couldn't choose a persona.
class PersonaPickerScreen extends StatelessWidget {
  const PersonaPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    final choices = auth.personas
        .where(
          (p) =>
              p['portalOnly'] != true &&
              p['accountStatus'] != 'suspended' &&
              p['approvalStatus'] != 'rejected',
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('app.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [
            Text(
              context.tr('persona.pickTitle'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            Text(context.tr('persona.pickBody')),
            const SizedBox(height: FFTokens.spacingMd),
            for (final p in choices)
              Card(
                child: ListTile(
                  key: Key('pick-persona-${p['id']}'),
                  leading: Icon(_personaIcon(p['userType'])),
                  title: Text(personaLabel(context, p['userType'])),
                  subtitle: p['approvalStatus'] == 'pending_approval'
                      ? Text(context.tr('persona.pending'))
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => switchToPersona(context, p['id'].toString()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
