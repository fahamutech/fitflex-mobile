import 'package:go_router/go_router.dart';

import 'shared/auth_state.dart';
import 'screens/language_screen.dart';
import 'screens/role_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/member/member_shell.dart';
import 'screens/member/member_onboarding_page.dart';
import 'screens/trainer/trainer_registration_page.dart';
import 'screens/owner/owner_registration_page.dart';
import 'screens/owner/owner_qr_scanner_page.dart';

/// Route path constants.
abstract class AppRoutes {
  static const language = '/';
  static const role = '/role';
  static const auth = '/auth';
  static const pending = '/pending';
  static const home = '/home';

  // Trainer & Owner registration
  static const trainerRegistration = '/trainer/register';
  static const ownerRegistration = '/owner/register';
  static const ownerQrScanner = '/owner/scan';

  // Member sub-routes (shell)
  static const memberOnboarding = '/member/onboarding';
  static const memberHome = '/member';
  static const memberGyms = '/member/gyms';
  static const memberGymDetail = '/member/gyms/:gymId';
  static const memberTrainers = '/member/trainers';
  static const memberTrainerDetail = '/member/trainers/:trainerId';
  static const memberQr = '/member/qr';
  static const memberProfile = '/member/profile';
  static const memberPasses = '/member/passes';
  static const memberPayment = '/member/payment';
}

bool _isOnboarded(AuthState auth, String role) {
  if (role == 'gym_operator') {
    // Gym owner must have at least 1 gym to be considered onboarded
    final gymIds = auth.user?['gymIds'];
    return gymIds is List && gymIds.isNotEmpty;
  }
  if (role == 'trainer') {
    if (auth.user?['onboardingCompleted'] == true) return true;
    if (auth.user?['approvalStatus']?.toString() == 'approved') return true;
    return false;
  }
  // Member
  return auth.user?['onboardingCompleted'] == true;
}

GoRouter buildRouter(AuthState auth) {
  return GoRouter(
    initialLocation: AppRoutes.language,
    debugLogDiagnostics: false,
    refreshListenable: auth,
    redirect: (context, state) {
      final loggedIn = auth.isSignedIn;
      final isPending = auth.isPendingApproval;
      final loc = state.matchedLocation;

      // Public routes that don't need auth
      final publicRoutes = [AppRoutes.language, AppRoutes.role, AppRoutes.auth];

      if (!loggedIn && !publicRoutes.contains(loc)) {
        return AppRoutes.language;
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
            loc != AppRoutes.trainerRegistration &&
            loc != AppRoutes.ownerRegistration) {
          return AppRoutes.pending;
        }
        return null;
      }

      if (loggedIn && !isPending && publicRoutes.contains(loc)) {
        final role = auth.user?['userType']?.toString() ?? auth.role;
        if (role == 'member') {
          final onboarded = _isOnboarded(auth, role);
          return onboarded ? AppRoutes.memberHome : AppRoutes.memberOnboarding;
        }
        if (role == 'trainer') {
          final onboarded = _isOnboarded(auth, role);
          return onboarded ? AppRoutes.home : AppRoutes.trainerRegistration;
        }
        if (role == 'gym_operator') {
          final onboarded = _isOnboarded(auth, role);
          return onboarded ? AppRoutes.home : AppRoutes.ownerRegistration;
        }
        return AppRoutes.home;
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
        path: AppRoutes.pending,
        name: 'pending',
        builder: (context, state) => const PendingApprovalScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.memberOnboarding,
        name: 'memberOnboarding',
        builder: (context, state) => const MemberOnboardingPage(),
      ),
      GoRoute(
        path: AppRoutes.trainerRegistration,
        name: 'trainerRegistration',
        builder: (context, state) => const TrainerRegistrationPage(),
      ),
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
            path: AppRoutes.memberPayment,
            name: 'memberPayment',
            builder: (context, state) => const MemberPaymentPage(),
          ),
        ],
      ),
    ],
  );
}
