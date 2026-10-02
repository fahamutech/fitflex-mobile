import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/api_client.dart';
import '../../shared/api_error_message.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/firebase_auth_service.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import '../../shared/pin_credentials.dart';
import '../../shared/widgets/profile_form_page.dart';
import 'member_shell.dart';
import 'widgets/checkin_list.dart';
import 'widgets/membership_card.dart';
import '../../shared/widgets/persona_switcher.dart';
import '../../shared/widgets/invitations.dart';

class MemberProfileTab extends StatefulWidget {
  const MemberProfileTab({super.key});

  @override
  State<MemberProfileTab> createState() => _MemberProfileTabState();
}

class _MemberProfileTabState extends State<MemberProfileTab> {
  static const _goals = [
    'lose_weight',
    'build_muscle',
    'stay_fit',
    'improve_flexibility',
    'stress_relief',
  ];
  static const _levels = ['beginner', 'intermediate', 'advanced'];
  static const _timeOptions = ['morning', 'afternoon', 'evening'];

  String? _pinError(String value) {
    if (value.trim().isEmpty) return context.tr('onboarding.required');
    if (!RegExp(r'^\d+$').hasMatch(value)) {
      return context.tr('auth.pinDigitsOnly');
    }
    if (value.length < 4 || value.length > 8) {
      return context.tr('auth.pinLength');
    }
    return null;
  }

  Future<void> _refreshMemberData(MemberData data) async {
    final res = await AppScope.of(context).api.me();
    if (!mounted) return;
    data.update(
      (d) => d.me = MemberMeResponse.fromJson(
        Map<String, dynamic>.from(res as Map),
      ),
    );
    final updatedUser = Map<String, dynamic>.from(
      (res as Map)['user'] as Map? ?? {},
    );
    final token = AppScope.of(context).auth.token;
    if (token != null) {
      await AppScope.of(context).auth.signIn(token, updatedUser);
    }
  }

  Future<void> _saveMemberProfilePatch(
    Map<String, dynamic> payload, {
    required String successMessage,
  }) async {
    final data = MemberDataScope.of(context);
    try {
      await AppScope.of(context).api.updateProfile(payload);
      if (!mounted) return;
      await _refreshMemberData(data);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(FFLocaleScope.of(context), e))),
      );
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('home.signout')),
        content: Text(context.tr('confirm.signout')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('member.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FFTokens.error500),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('home.signout')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await AppScope.of(context).auth.signOut();
    if (!mounted) return;
    context.go(AppRoutes.language);
  }

  Future<void> _openEditDetails() async {
    final data = MemberDataScope.of(context);
    final me = data.me;
    final user = <String, dynamic>{
      'userType': 'member',
      'displayName': me?.user.displayName,
      'email': me?.user.email,
      'phone': me?.user.phone,
      'photoUrl': me?.user.photoUrl,
      'memberProfile': {
        'heightCm': me?.user.memberProfile?.heightCm,
        'weightKg': me?.user.memberProfile?.weightKg,
        'dateOfBirth': me?.user.memberProfile?.dateOfBirth,
        'gender': me?.user.memberProfile?.gender,
      },
    };
    final saved = await openProfileForm(
      context,
      title: context.tr('member.editDetails'),
      initialUser: user,
    );
    if (saved == true && mounted) {
      try {
        await _refreshMemberData(data);
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('member.profileUpdated'))),
        );
      }
    }
  }

  void _openWhatsAppSupport() {
    final uri = Uri.parse('https://wa.me/255786670499');
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openChangePinDialog() async {
    final currentPinCtrl = TextEditingController();
    final newPinCtrl = TextEditingController();
    final confirmPinCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final authService = FirebaseAuthService();
    final email = MemberDataScope.of(context).me?.user.email ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        var busy = false;
        String? error;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(context.tr('member.changePin')),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: currentPinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      validator: (value) => _pinError(value ?? ''),
                      decoration: InputDecoration(
                        labelText: context.tr('member.currentPin'),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: newPinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      validator: (value) => _pinError(value ?? ''),
                      decoration: InputDecoration(
                        labelText: context.tr('member.newPin'),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmPinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      validator: (value) => value != newPinCtrl.text
                          ? context.tr('auth.pinMismatch')
                          : null,
                      decoration: InputDecoration(
                        labelText: context.tr('auth.confirmPin'),
                        counterText: '',
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      FFAlert(message: error!, tone: FFAlertTone.error),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx, false),
                child: Text(context.tr('member.cancel')),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setDialogState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await authService.updateEmailPassword(
                            email: email,
                            currentPassword: firebasePasswordForPin(
                              currentPinCtrl.text,
                            ),
                            newPassword: firebasePasswordForPin(
                              newPinCtrl.text,
                            ),
                          );
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } on FirebaseAuthException catch (e) {
                          setDialogState(() {
                            busy = false;
                            error = switch (e.code) {
                              'invalid-credential' || 'wrong-password' =>
                                context.tr('auth.invalidCredentials'),
                              _ => e.message ?? e.code,
                            };
                          });
                        } catch (e) {
                          setDialogState(() {
                            busy = false;
                            error = errorMessage(FFLocaleScope.of(context), e);
                          });
                        }
                      },
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(context.tr('member.save')),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('member.pinUpdated'))));
    }
    await Future<void>.delayed(kThemeAnimationDuration);
    currentPinCtrl.dispose();
    newPinCtrl.dispose();
    confirmPinCtrl.dispose();
  }

  Future<void> _openGoalsDialog() async {
    final data = MemberDataScope.of(context);
    final profile = data.me?.user.memberProfile;
    final selected = <String>{
      ...profile?.fitnessGoals ?? const [],
      if ((profile?.fitnessGoal ?? '').isNotEmpty) profile!.fitnessGoal!,
    };
    var level = profile?.fitnessLevel;
    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(context.tr('member.changeGoals')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _goals.map((goal) {
                    final isSelected = selected.contains(goal);
                    return FilterChip(
                      label: Text(context.tr('onboarding.goal_$goal')),
                      selected: isSelected,
                      selectedColor: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.1),
                      checkmarkColor: Theme.of(context).colorScheme.primary,
                      onSelected: (value) => setDialogState(() {
                        if (value) {
                          selected.add(goal);
                        } else {
                          selected.remove(goal);
                        }
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: level,
                  decoration: InputDecoration(
                    labelText: context.tr('onboarding.fitnessLevel'),
                    border: const OutlineInputBorder(),
                  ),
                  items: _levels
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(context.tr('onboarding.level_$item')),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => level = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.tr('member.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {
                'fitnessGoals': selected.toList(),
                'fitnessLevel': level,
              }),
              child: Text(context.tr('member.save')),
            ),
          ],
        ),
      ),
    );
    if (saved == null || !mounted) return;
    await _saveMemberProfilePatch(
      saved,
      successMessage: context.tr('member.profileUpdated'),
    );
  }

  Future<void> _openWorkoutPreferencesDialog() async {
    final data = MemberDataScope.of(context);
    final selected = <String>{
      ...data.me?.user.memberProfile?.preferredWorkoutTimes ?? const [],
    };
    final saved = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(context.tr('member.workoutPreferences')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _timeOptions.map((time) {
              return CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('onboarding.time_$time')),
                value: selected.contains(time),
                onChanged: (value) => setDialogState(() {
                  if (value == true) {
                    selected.add(time);
                  } else {
                    selected.remove(time);
                  }
                }),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.tr('member.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected.toList()),
              child: Text(context.tr('member.save')),
            ),
          ],
        ),
      ),
    );
    if (saved == null || !mounted) return;
    await _saveMemberProfilePatch({
      'preferredWorkoutTimes': saved,
    }, successMessage: context.tr('member.profileUpdated'));
  }

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final me = data.me;
    final displayName = me?.user.resolvedName ?? 'Member';
    final visitsUsed = me?.visitsUsed ?? 0;
    final visitCap = me?.visitCap;

    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        // Profile header
        FFCard(
          child: Row(
            children: [
              FFAvatar(
                name: displayName,
                src: me?.user.photoUrl,
                size: FFAvatarSize.lg,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FFBadge(
                      label: data.subscription?.isDirect == true
                          ? context.tr(
                              'member.plan_${data.subscription?.plan ?? 'monthly'}',
                            )
                          : data.subscription?.tier ??
                                context.tr('pass.pending'),
                      tone: data.hasActivePass
                          ? FFBadgeTone.success
                          : FFBadgeTone.gray,
                      dot: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Membership (A2/A3): plan, expiry date, days left, subscribed gym
        MembershipCard(subscription: data.subscription),
        const SizedBox(height: 12),

        // Stats
        if (data.subscription?.isDirect == true)
          FFMetricCard(
            label: context.tr('member.membershipDaysLeft'),
            value: '${(data.subscription?.daysLeft ?? 0).clamp(0, 99999)}',
          )
        else
          Row(
            children: [
              Expanded(
                child: FFMetricCard(
                  label: context.tr('home.visits'),
                  value: '$visitsUsed',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FFMetricCard(
                  label: context.tr('pass.visits'),
                  value: visitCap == null ? '-' : '$visitCap',
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),

        // Visit history
        FFSectionTitle(context.tr('member.visitHistory')),
        CheckinList(checkins: data.checkins, limit: 8),

        // Settings
        FFSectionTitle(context.tr('member.accountSettings')),
        FFActionTile(
          icon: Icons.edit,
          title: context.tr('member.editDetails'),
          onTap: _openEditDetails,
        ),
        FFActionTile(
          icon: Icons.flag_outlined,
          title: context.tr('member.changeGoals'),
          onTap: _openGoalsDialog,
        ),
        FFActionTile(
          key: const Key('profile-community'),
          icon: Icons.people_outline,
          title: context.tr('community.title'),
          subtitle: context.tr('community.profileHint'),
          onTap: () => context.push(AppRoutes.memberCommunity),
        ),
        FFActionTile(
          key: const Key('profile-benefits'),
          icon: Icons.volunteer_activism_outlined,
          title: context.tr('benefits.title'),
          subtitle: context.tr('benefits.tile'),
          onTap: () => context.push(AppRoutes.memberBenefits),
        ),
        FFActionTile(
          key: const Key('profile-sessions'),
          icon: Icons.event_repeat_outlined,
          title: context.tr('sessions.title'),
          subtitle: context.tr('sessions.tile'),
          onTap: () => context.push(AppRoutes.memberSessions),
        ),
        FFActionTile(
          key: const Key('profile-privacy'),
          icon: Icons.privacy_tip_outlined,
          title: context.tr('privacy.title'),
          onTap: () => context.go(AppRoutes.memberPrivacy),
        ),
        FFActionTile(
          icon: Icons.schedule_outlined,
          title: context.tr('member.workoutPreferences'),
          onTap: _openWorkoutPreferencesDialog,
        ),
        FFActionTile(
          icon: Icons.lock_outline,
          title: context.tr('member.changePin'),
          onTap: _openChangePinDialog,
        ),
        FFActionTile(
          icon: Icons.help_outline,
          title: context.tr('member.help'),
          onTap: _openWhatsAppSupport,
        ),
        const InvitationsTile(),
        const PersonaSwitcherTile(),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _confirmSignOut,
          icon: Icon(
            Icons.logout,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          label: Text(
            context.tr('home.signout'),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
      ],
    );
  }
}
