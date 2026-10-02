import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'shared/auth_state.dart';
import 'screens/splash_screen.dart';
import 'screens/language_screen.dart';
import 'screens/role_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/sign_up_screen.dart';
import 'screens/email_auth_screen.dart';
import 'screens/verify_email_screen.dart';
import 'shared/widgets/persona_switcher.dart';
import 'screens/member/member_shell.dart';
import 'shared/activity/activity.dart';
import 'screens/member/member_shop_tab.dart';
import 'screens/member/member_onboarding_page.dart';
import 'screens/member/member_privacy_page.dart';
import 'screens/member/member_community_page.dart';
import 'screens/member/member_group_page.dart';
import 'screens/member/member_person_page.dart';
import 'screens/member/member_shared_activity_page.dart';
import 'screens/member/member_record_run_page.dart';
import 'screens/member/member_run_detail_page.dart';
import 'screens/trainer/trainer_registration_page.dart';
import 'screens/trainer/trainer_home_page.dart';
import 'screens/owner/owner_registration_page.dart';
import 'screens/owner/owner_qr_scanner_page.dart';
import 'screens/owner/owner_shop_page.dart';
import 'screens/owner/owner_staff_page.dart';
import 'screens/owner/owner_shell.dart';
import 'screens/owner/members/members_list_page.dart';
import 'screens/owner/members/member_detail_page.dart';
import 'screens/owner/members/member_history_page.dart';
import 'screens/owner/communications/campaign_composer_page.dart';
import 'screens/owner/communications/campaign_detail_page.dart';
import 'screens/owner/communications/communication_center_page.dart';
import 'screens/owner/communications/template_pages.dart';
import 'screens/owner/communications/history_pages.dart';
import 'screens/owner/communications/automation_pages.dart';
import 'screens/member/member_benefits_page.dart';
import 'screens/member/member_sessions_page.dart';
import 'screens/member/member_message_settings_page.dart';
import 'shared/inbox/inbox_pages.dart';
import 'screens/vendor/vendor_home_page.dart';
import 'screens/partner/verification/verification_center_page.dart';
import 'shared/widgets/invitations.dart';

/// Route path constants.
abstract class AppRoutes {
  static const splash = '/';
  static const language = '/language';
  static const role = '/role';
  static const auth = '/auth';
  static const signUp = '/auth/signup';
  static const emailAuth = '/auth/email';
  static const verifyEmail = '/auth/verify-email';
  static const personaPicker = '/personas';
  static const invitations = '/invitations';

  /// Verify-email step, carrying the role to retry with (sign-up only).
  static String verifyEmailFor(String? requestedRole) =>
      requestedRole == null || requestedRole.isEmpty
      ? verifyEmail
      : '$verifyEmail?role=${Uri.encodeQueryComponent(requestedRole)}';
  static const googleWebCallback = '/auth/google-web-callback';
  static const pending = '/pending';

  /// Partner KYC / KYB — open to partners while they wait for approval.
  static const verification = '/verification';
  static const home = '/home';

  // Trainer
  static const trainerRegistration = '/trainer/register';
  static const trainerHome = '/trainer/home';

  // Vendor
  static const vendorHome = '/vendor/home';

  // Owner sub-routes (shell)
  static const ownerRegistration = '/owner/register';
  static const ownerHome = '/owner/home';
  static const ownerGyms = '/owner/gyms';
  static const ownerGymCheckins = '/owner/gyms/:gymId/checkins';
  static const ownerMembers = '/owner/members';
  static const ownerMemberDetail = '/owner/members/:memberId';
  static const ownerMemberCheckins = '/owner/members/:memberId/checkins';
  static const ownerMemberPayments = '/owner/members/:memberId/payments';
  static const inbox = '/inbox';
  static const inboxMessage = '/inbox/:messageId';
  static const memberMessageSettings = '/member/message-settings';
  static const memberBenefits = '/member/benefits';
  static const memberSessions = '/member/sessions';
  static const ownerCommunications = '/owner/communications';
  static const ownerCampaignNew = '/owner/communications/new';
  static const ownerCampaignDetail =
      '/owner/communications/campaigns/:campaignId';
  static const ownerTemplateNew = '/owner/communications/templates/new';
  static const ownerTemplateDetail =
      '/owner/communications/templates/:templateId';
  static const ownerTemplateEdit =
      '/owner/communications/templates/:templateId/edit';
  static const ownerCampaignEdit =
      '/owner/communications/campaigns/:campaignId/edit';
  static const ownerCampaignRecipients =
      '/owner/communications/campaigns/:campaignId/recipients';
  static const ownerMemberMessages = '/owner/members/:memberId/messages';
  static const ownerAutomation =
      '/owner/communications/automations/:automationId';
  static const ownerTrainers = '/owner/trainers';
  static const ownerProfile = '/owner/profile';
  static const ownerQrScanner = '/owner/scan';
  static const ownerEarnings = '/owner/earnings';
  static const ownerShop = '/owner/shop';
  static const ownerStaff = '/owner/staff';

  // Member sub-routes (shell)
  static const memberOnboarding = '/member/onboarding';
  static const memberHome = '/member';
  static const memberActivity = '/member/activity';
  static const memberActivityLog = '/member/activity/log';
  static const memberRecordRun = '/member/activity/run';
  static const memberRunDetail = '/member/activity/runs/:activityId';
  static const memberProgress = '/member/activity/progress';
  static const memberWorkout = '/member/activity/workouts/:workoutId';
  static const memberChallenge = '/member/activity/challenges/:challengeId';
  static const memberGyms = '/member/gyms';
  static const memberGymDetail = '/member/gyms/:gymId';
  static const memberTrainers = '/member/trainers';
  static const memberTrainerDetail = '/member/trainers/:trainerId';
  static const memberQr = '/member/qr';
  static const memberShop = '/member/shop';
  static const memberProfile = '/member/profile';
  static const memberPasses = '/member/passes';
  static const memberPayment = '/member/payment';
  static const memberPrivacy = '/member/privacy';
  static const memberCommunity = '/member/community';
  static const memberSharedActivity =
      '/member/community/activities/:activityId';
  static const memberGroup = '/member/community/groups/:groupId';
  static const memberPerson = '/member/community/people/:userId';
  static const memberActivitySharing = '/member/privacy/activity-sharing';
}

bool _isOnboarded(AuthState auth, String role) {
  if (role == 'gym_operator') {
    // Gym owner must have at least 1 gym to be considered onboarded
    final gymIds = auth.user?['gymIds'];
    return gymIds is List && gymIds.isNotEmpty;
  }
  if (role == 'gym_staff') {
    // Staff accounts are created directly by their gym owner — always
    // fully onboarded, never self-register or await approval.
    return true;
  }
  if (role == 'trainer') {
    if (auth.user?['onboardingCompleted'] == true) return true;
    if (auth.user?['approvalStatus']?.toString() == 'approved') return true;
    return false;
  }
  // Member
  return auth.user?['onboardingCompleted'] == true;
}

String routeForSignedInUser(AuthState auth) {
  final role = auth.user?['userType']?.toString() ?? auth.role;
  final onboarded = _isOnboarded(auth, role);
  if (auth.isPendingApproval) {
    if (role == 'trainer' && !onboarded) {
      return AppRoutes.trainerRegistration;
    }
    if (role == 'gym_operator' && !onboarded) {
      return AppRoutes.ownerRegistration;
    }
    return AppRoutes.pending;
  }
  if (role == 'member') {
    return onboarded ? AppRoutes.memberHome : AppRoutes.memberOnboarding;
  }
  if (role == 'trainer') {
    return onboarded ? AppRoutes.trainerHome : AppRoutes.trainerRegistration;
  }
  if (role == 'gym_operator') {
    return onboarded ? AppRoutes.ownerHome : AppRoutes.ownerRegistration;
  }
  if (role == 'gym_staff') {
    // Staff reuse the owner shell, gated by their ACL permissions.
    return AppRoutes.ownerHome;
  }
  if (role == 'vendor' || role == 'vendor_staff') return AppRoutes.vendorHome;
  return AppRoutes.home;
}

GoRouter buildRouter(AuthState auth) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    refreshListenable: auth,
    redirect: (context, state) {
      final loggedIn = auth.isSignedIn;
      final isPending = auth.isPendingApproval;
      final loc = state.matchedLocation;

      // Splash controls its own transition; skip auth redirects while showing.
      if (loc == AppRoutes.splash) return null;

      // Public routes that don't need auth
      final publicRoutes = [
        AppRoutes.language,
        AppRoutes.role,
        AppRoutes.auth,
        AppRoutes.signUp,
        AppRoutes.emailAuth,
        AppRoutes.verifyEmail,
        AppRoutes.googleWebCallback,
      ];

      if (!loggedIn && !publicRoutes.contains(loc)) {
        return AppRoutes.language;
      }

      // Identity V2: several personas and none used last — ask first.
      if (loggedIn && auth.personaChoiceRequired) {
        return loc == AppRoutes.personaPicker ? null : AppRoutes.personaPicker;
      }
      if (loc == AppRoutes.personaPicker && loggedIn) {
        return routeForSignedInUser(auth);
      }

      // Trainer/Owner: redirect to registration if onboarding not done, even while pending
      if (loggedIn && isPending) {
        final role = auth.user?['userType']?.toString() ?? auth.role;
        final onboarded = _isOnboarded(auth, role);
        if (role == 'trainer' &&
            !onboarded &&
            loc != AppRoutes.trainerRegistration) {
          return AppRoutes.trainerRegistration;
        }
        if (role == 'gym_operator' &&
            !onboarded &&
            loc != AppRoutes.ownerRegistration) {
          return AppRoutes.ownerRegistration;
        }
        if (loc != AppRoutes.pending &&
            loc != AppRoutes.verification &&
            loc != AppRoutes.trainerRegistration &&
            loc != AppRoutes.ownerRegistration &&
            loc != AppRoutes.ownerProfile) {
          return AppRoutes.pending;
        }
        return null;
      }

      if (loggedIn && !isPending && publicRoutes.contains(loc)) {
        return routeForSignedInUser(auth);
      }

      // Redirect member to onboarding if not completed
      if (loggedIn && !isPending) {
        final role = auth.user?['userType']?.toString() ?? auth.role;
        final onboarded = _isOnboarded(auth, role);
        if (role == 'member' &&
            !onboarded &&
            loc != AppRoutes.memberOnboarding) {
          return AppRoutes.memberOnboarding;
        }
        if (role == 'trainer' &&
            !onboarded &&
            loc != AppRoutes.trainerRegistration) {
          return AppRoutes.trainerRegistration;
        }
        if (role == 'gym_operator' &&
            !onboarded &&
            loc != AppRoutes.ownerRegistration) {
          return AppRoutes.ownerRegistration;
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.language,
        name: 'language',
        builder: (context, state) => const LanguageScreen(),
      ),
      GoRoute(
        path: AppRoutes.role,
        name: 'role',
        builder: (context, state) => const RoleScreen(),
      ),
      GoRoute(
        path: AppRoutes.auth,
        name: 'auth',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        name: 'signUp',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SignUpScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 0.05),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  ),
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                ),
                child: child,
              ),
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.emailAuth,
        name: 'emailAuth',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: EmailAuthScreen(
            initialEmail: state.uri.queryParameters['email'] ?? '',
            initialMode: state.uri.queryParameters['mode'] == 'signup'
                ? EmailAuthMode.signUp
                : EmailAuthMode.signIn,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 0.05),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  ),
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                ),
                child: child,
              ),
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.invitations,
        name: 'invitations',
        builder: (context, state) =>
            InvitationsScreen(token: state.uri.queryParameters['token']),
      ),
      GoRoute(
        path: AppRoutes.personaPicker,
        name: 'personaPicker',
        builder: (context, state) => const PersonaPickerScreen(),
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        name: 'verifyEmail',
        builder: (context, state) =>
            VerifyEmailScreen(requestedRole: state.uri.queryParameters['role']),
      ),
      GoRoute(
        path: AppRoutes.googleWebCallback,
        name: 'googleWebCallback',
        builder: (context, state) => const GoogleWebCallbackScreen(),
      ),
      GoRoute(
        path: AppRoutes.pending,
        name: 'pending',
        builder: (context, state) => const PendingApprovalScreen(),
      ),
      GoRoute(
        path: AppRoutes.verification,
        name: 'verification',
        builder: (context, state) => const VerificationCenterPage(),
      ),
      GoRoute(
        path: AppRoutes.memberOnboarding,
        name: 'memberOnboarding',
        builder: (context, state) => const MemberOnboardingPage(),
      ),
      // Trainer routes
      GoRoute(
        path: AppRoutes.trainerRegistration,
        name: 'trainerRegistration',
        builder: (context, state) => const TrainerRegistrationPage(),
      ),
      GoRoute(
        path: AppRoutes.trainerHome,
        name: 'trainerHome',
        builder: (context, state) => const TrainerHomePage(),
      ),
      GoRoute(
        path: AppRoutes.vendorHome,
        name: 'vendorHome',
        builder: (context, state) => const VendorHomePage(),
      ),
      // Owner routes
      GoRoute(
        path: AppRoutes.ownerRegistration,
        name: 'ownerRegistration',
        builder: (context, state) => const OwnerRegistrationPage(),
      ),
      GoRoute(
        path: AppRoutes.ownerQrScanner,
        name: 'ownerQrScanner',
        builder: (context, state) => const OwnerQrScannerPage(),
      ),
      GoRoute(
        path: AppRoutes.ownerEarnings,
        name: 'ownerEarnings',
        builder: (context, state) => const OwnerEarningsPage(),
      ),
      GoRoute(
        path: AppRoutes.ownerShop,
        name: 'ownerShop',
        builder: (context, state) => const OwnerShopPage(),
      ),
      GoRoute(
        path: AppRoutes.ownerStaff,
        name: 'ownerStaff',
        builder: (context, state) => const OwnerStaffPage(),
      ),
      GoRoute(
        path: AppRoutes.ownerGymCheckins,
        name: 'ownerGymCheckins',
        builder: (context, state) {
          final gymId = state.pathParameters['gymId']!;
          return OwnerCheckinsPage(gymId: gymId);
        },
      ),
      GoRoute(
        path: AppRoutes.ownerProfile,
        name: 'ownerProfile',
        builder: (context, state) => const OwnerProfilePage(),
      ),
      GoRoute(
        path: AppRoutes.ownerMemberDetail,
        name: 'ownerMemberDetail',
        builder: (context, state) =>
            MemberDetailPage(memberId: state.pathParameters['memberId']!),
      ),
      GoRoute(
        path: AppRoutes.ownerMemberCheckins,
        name: 'ownerMemberCheckins',
        builder: (context, state) => MemberHistoryPage(
          memberId: state.pathParameters['memberId']!,
          kind: MemberHistoryKind.checkins,
        ),
      ),
      GoRoute(
        path: AppRoutes.ownerMemberPayments,
        name: 'ownerMemberPayments',
        builder: (context, state) => MemberHistoryPage(
          memberId: state.pathParameters['memberId']!,
          kind: MemberHistoryKind.payments,
        ),
      ),
      // The member's messages from this gym (communication history).
      GoRoute(
        path: AppRoutes.ownerMemberMessages,
        name: 'ownerMemberMessages',
        builder: (context, state) => MemberCommunicationsPage(
          memberId: state.pathParameters['memberId']!,
        ),
      ),
      // Inbox — every signed-in role's messages.
      GoRoute(
        path: AppRoutes.inbox,
        name: 'inbox',
        builder: (context, state) => const InboxPage(),
      ),
      GoRoute(
        path: AppRoutes.inboxMessage,
        name: 'inboxMessage',
        builder: (context, state) =>
            InboxMessagePage(messageId: state.pathParameters['messageId']!),
      ),
      GoRoute(
        path: AppRoutes.memberMessageSettings,
        name: 'memberMessageSettings',
        builder: (context, state) => const MemberMessageSettingsPage(),
      ),
      GoRoute(
        path: AppRoutes.memberBenefits,
        name: 'memberBenefits',
        builder: (context, state) => const MemberBenefitsPage(),
      ),
      GoRoute(
        path: AppRoutes.memberSessions,
        name: 'memberSessions',
        builder: (context, state) => const MemberSessionsPage(),
      ),
      // Message templates. "new" comes before ":templateId" so it wins.
      GoRoute(
        path: AppRoutes.ownerTemplateNew,
        name: 'ownerTemplateNew',
        builder: (context, state) =>
            TemplateEditorPage(gymId: state.uri.queryParameters['gymId']),
      ),
      GoRoute(
        path: AppRoutes.ownerTemplateDetail,
        name: 'ownerTemplateDetail',
        builder: (context, state) => TemplateDetailPage(
          templateId: state.pathParameters['templateId']!,
          gymId: state.uri.queryParameters['gymId'],
        ),
      ),
      GoRoute(
        path: AppRoutes.ownerTemplateEdit,
        name: 'ownerTemplateEdit',
        builder: (context, state) => TemplateEditorPage(
          templateId: state.pathParameters['templateId'],
          gymId: state.uri.queryParameters['gymId'],
        ),
      ),
      // Communication Center — messages to the gym's direct members.
      GoRoute(
        path: AppRoutes.ownerCommunications,
        name: 'ownerCommunications',
        builder: (context, state) =>
            CommunicationCenterPage(gymId: state.uri.queryParameters['gymId']),
      ),
      GoRoute(
        path: AppRoutes.ownerCampaignNew,
        name: 'ownerCampaignNew',
        builder: (context, state) => CampaignComposerPage(
          gymId: state.uri.queryParameters['gymId'],
          templateId: state.uri.queryParameters['templateId'],
        ),
      ),
      GoRoute(
        path: AppRoutes.ownerCampaignDetail,
        name: 'ownerCampaignDetail',
        builder: (context, state) =>
            CampaignDetailPage(campaignId: state.pathParameters['campaignId']!),
      ),
      GoRoute(
        path: AppRoutes.ownerCampaignEdit,
        name: 'ownerCampaignEdit',
        builder: (context, state) => CampaignComposerPage(
          campaignId: state.pathParameters['campaignId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.ownerAutomation,
        name: 'ownerAutomation',
        builder: (context, state) => AutomationDetailPage(
          automationId: state.pathParameters['automationId']!,
          gymId: state.uri.queryParameters['gymId'],
        ),
      ),
      GoRoute(
        path: AppRoutes.ownerCampaignRecipients,
        name: 'ownerCampaignRecipients',
        builder: (context, state) => CampaignRecipientsPage(
          campaignId: state.pathParameters['campaignId']!,
        ),
      ),
      // Owner shell with bottom nav
      ShellRoute(
        builder: (context, state, child) =>
            OwnerShell(state: state, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.ownerHome,
            name: 'ownerHome',
            builder: (context, state) => const OwnerHomeTab(),
          ),
          GoRoute(
            path: AppRoutes.ownerGyms,
            name: 'ownerGyms',
            builder: (context, state) => const OwnerManageGymsPage(),
          ),
          GoRoute(
            path: AppRoutes.ownerMembers,
            name: 'ownerMembers',
            builder: (context, state) => const OwnerMembersPage(),
          ),
          GoRoute(
            path: AppRoutes.ownerTrainers,
            name: 'ownerTrainers',
            builder: (context, state) => const OwnerTrainersPage(),
          ),
        ],
      ),
      // Member shell with bottom nav
      ShellRoute(
        builder: (context, state, child) =>
            MemberShell(state: state, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.memberHome,
            name: 'memberHome',
            builder: (context, state) => const MemberHomeTab(),
          ),
          GoRoute(
            path: AppRoutes.memberActivity,
            name: 'memberActivity',
            builder: (context, state) => const MemberActivityTab(),
            routes: [
              GoRoute(
                path: 'progress',
                name: 'memberProgress',
                builder: (context, state) =>
                    const MemberActivityTab(initialSection: 'progress'),
              ),
              GoRoute(
                path: 'run',
                name: 'memberRecordRun',
                builder: (context, state) => const MemberRecordRunPage(),
              ),
              GoRoute(
                path: 'runs/:activityId',
                name: 'memberRunDetail',
                builder: (context, state) => MemberRunDetailPage(
                  activityId: state.pathParameters['activityId']!,
                ),
              ),
              GoRoute(
                path: 'log',
                name: 'memberActivityLog',
                builder: (context, state) => MemberLogActivityPage(
                  initialType: ActivityType.values
                      .where((t) => t.wire == state.uri.queryParameters['type'])
                      .firstOrNull,
                ),
              ),
              GoRoute(
                path: 'challenges/:challengeId',
                name: 'memberChallenge',
                builder: (context, state) => MemberChallengePage(
                  challengeId: state.pathParameters['challengeId']!,
                ),
              ),
              GoRoute(
                path: 'workouts/:workoutId',
                name: 'memberWorkout',
                builder: (context, state) => MemberWorkoutPage(
                  workoutId: state.pathParameters['workoutId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.memberGyms,
            name: 'memberGyms',
            builder: (context, state) => const MemberGymsTab(),
            routes: [
              GoRoute(
                path: ':gymId',
                name: 'memberGymDetail',
                builder: (context, state) {
                  final gymId = state.pathParameters['gymId']!;
                  return MemberGymDetailPage(gymId: gymId);
                },
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.memberTrainers,
            name: 'memberTrainers',
            builder: (context, state) => const MemberTrainersTab(),
            routes: [
              GoRoute(
                path: ':trainerId',
                name: 'memberTrainerDetail',
                builder: (context, state) {
                  final trainerId = state.pathParameters['trainerId']!;
                  return MemberTrainerDetailPage(trainerId: trainerId);
                },
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.memberQr,
            name: 'memberQr',
            builder: (context, state) => const MemberQrTab(),
          ),
          GoRoute(
            path: AppRoutes.memberShop,
            name: 'memberShop',
            builder: (context, state) => const MemberShopTab(),
          ),
          GoRoute(
            path: AppRoutes.memberProfile,
            name: 'memberProfile',
            builder: (context, state) => const MemberProfileTab(),
          ),
          GoRoute(
            path: AppRoutes.memberPasses,
            name: 'memberPasses',
            builder: (context, state) => const MemberPassesPage(),
          ),
          GoRoute(
            path: AppRoutes.memberCommunity,
            name: 'memberCommunity',
            builder: (context, state) => MemberCommunityPage(
              initialTab:
                  int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
            ),
            routes: [
              GoRoute(
                path: 'activities/:activityId',
                name: 'memberSharedActivity',
                builder: (context, state) => MemberSharedActivityPage(
                  activityId: state.pathParameters['activityId']!,
                ),
              ),
              GoRoute(
                path: 'people/:userId',
                name: 'memberPerson',
                builder: (context, state) =>
                    MemberPersonPage(userId: state.pathParameters['userId']!),
              ),
              GoRoute(
                path: 'groups/:groupId',
                name: 'memberGroup',
                builder: (context, state) =>
                    GroupPage(groupId: state.pathParameters['groupId']!),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.memberPrivacy,
            name: 'memberPrivacy',
            builder: (context, state) => const MemberPrivacyPage(),
            routes: [
              GoRoute(
                path: 'activity-sharing',
                name: 'memberActivitySharing',
                builder: (context, state) => const MemberActivitySharingPage(),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.memberPayment,
            name: 'memberPayment',
            builder: (context, state) => const MemberPaymentPage(),
          ),
        ],
      ),
    ],
  );
}
