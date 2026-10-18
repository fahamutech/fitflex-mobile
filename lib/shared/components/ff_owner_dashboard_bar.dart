import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../i18n.dart';
import 'theme_toggle_button.dart';
import '../inbox/inbox_pages.dart';

/// Shared top action bar for the owner dashboard home tab.
///
/// Renders consistently for both approved owners (gym picker + dropdown) and
/// pending owners (static "Pending Approval" label, no picker). Implements
/// [PreferredSizeWidget] so it can be passed directly as [Scaffold.appBar].
class FFOwnerDashboardBar extends StatelessWidget
    implements PreferredSizeWidget {
  const FFOwnerDashboardBar({
    super.key,
    required this.selectedGymName,
    required this.initials,
    required this.ownerGyms,
    required this.subtitleLabel,
    this.onGymSelected,
    this.onAvatarTap,
    this.showBackButton = false,
  });

  /// The display name of the currently selected gym (or a pending label).
  final String selectedGymName;

  /// Two-letter initials rendered inside the avatar circle.
  final String initials;

  /// Full list of gyms the owner has. Pass an empty list when unapproved —
  /// the dropdown arrow will be hidden automatically.
  final List<Map<String, dynamic>> ownerGyms;

  /// Label shown below the gym name (e.g. "Dashboard").
  final String subtitleLabel;

  /// Called with the selected gym id when the owner switches gyms.
  /// Only invoked when [ownerGyms] has items.
  final void Function(String gymId)? onGymSelected;

  /// Called when the avatar circle is tapped (navigate to profile).
  final VoidCallback? onAvatarTap;

  /// Shows a back button instead of the brand mark — for pushed screens
  /// (e.g. Earnings) reached from an owner tab rather than the bottom nav.
  final bool showBackButton;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      automaticallyImplyLeading: false,
      leading: showBackButton
          ? IconButton(
              tooltip: context.tr('a11y.back'),
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : null,
      titleSpacing: showBackButton ? 0 : FFTokens.spacingLg,
      title: Row(
        children: [
          // Brand mark
          SizedBox(
            width: 36,
            height: 36,
            child: Image.asset(
              'assets/brand/fitflex-icon.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 10),
          // Gym name + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (ownerGyms.isEmpty)
                  Text(
                    selectedGymName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  )
                else
                  // The name and the arrow are one tap target: a separate
                  // popup button keeps a 48dp minimum and used to leave the
                  // name only a few characters.
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    itemBuilder: (ctx) => ownerGyms
                        .map(
                          (gym) => PopupMenuItem<String>(
                            value: gym['id']?.toString(),
                            child: Text(gym['name']?.toString() ?? ''),
                          ),
                        )
                        .toList(),
                    onSelected: (value) => onGymSelected?.call(value),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            selectedGymName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_down, size: 18),
                      ],
                    ),
                  ),
                Text(
                  subtitleLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // The inbox bell, with a real unread count.
        const InboxBellButton(),
        const AppPrefsButtons(),
        const SizedBox(width: 4),
        // Avatar
        Semantics(
          button: true,
          label: context.tr('owner.profile'),
          excludeSemantics: true,
          onTap: onAvatarTap,
          child: GestureDetector(
            key: const Key('owner-profile-button'),
            onTap: onAvatarTap,
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text(
                initials,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: FFTokens.spacingMd),
      ],
    );
  }
}
