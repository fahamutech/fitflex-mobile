import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'app_scope.dart';
import 'shared/activity/activity_config.dart';
import 'router.dart';
import 'shared/api_client.dart';
import 'shared/auth_state.dart';
import 'shared/push_service.dart';
import 'shared/design_tokens.dart';
import 'shared/i18n.dart';
import 'shared/theme_notifier.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const mockAuth = bool.fromEnvironment('MOCK_AUTH');

  // GoRouter uses hash URL strategy by default on web (e.g. /#/member/gyms).
  // This works without server-side rewrites for single-page apps.
  GoRouter.optionURLReflectsImperativeAPIs = true;

  // Load runtime config from bundled .env (API_BASE, etc.).
  // Failure is non-fatal — ApiClient will fall back to its built-in default.
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // .env not bundled or unreadable; continue with defaults.
  }

  // Idempotent: avoids a duplicate-app crash if main() runs twice in one
  // process (e.g. across Patrol integration test cases).
  if (!mockAuth && Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  final api = ApiClient();
  final auth = AuthState(api, push: mockAuth ? null : PushService(api));
  await auth.hydrate();

  final locale = FFLocale();

  final themeNotifier = ThemeNotifier();

  runApp(
    FitFlexApp(
      api: api,
      auth: auth,
      locale: locale,
      themeNotifier: themeNotifier,
    ),
  );
}

class FitFlexApp extends StatefulWidget {
  const FitFlexApp({
    super.key,
    required this.api,
    required this.auth,
    required this.locale,
    required this.themeNotifier,
  });

  final ApiClient api;
  final AuthState auth;
  final FFLocale locale;
  final ThemeNotifier themeNotifier;

  @override
  State<FitFlexApp> createState() => _FitFlexAppState();
}

class _FitFlexAppState extends State<FitFlexApp> {
  late final GoRouter _router;
  late final ActivityBackend _activity;

  @override
  void initState() {
    super.initState();
    _router = buildRouter(widget.auth);
    _activity = ActivityBackend.create(
      widget.api,
      sample: activitySampleDataEnabled(),
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      api: widget.api,
      auth: widget.auth,
      activityProvider: _activity.activity,
      goalRepository: _activity.goals,
      workoutRepository: _activity.workouts,
      child: ThemeScope(
        notifier: widget.themeNotifier,
        child: FFLocaleScope(
          notifier: widget.locale,
          child: AnimatedBuilder(
            animation: Listenable.merge([widget.locale, widget.themeNotifier]),
            builder: (context, _) {
              return MaterialApp.router(
                title: 'FitFlex',
                debugShowCheckedModeBanner: kDebugMode,
                theme: buildTheme(),
                darkTheme: buildDarkTheme(),
                themeMode: widget.themeNotifier.mode,
                locale: widget.locale.locale,
                supportedLocales: const [Locale('en'), Locale('sw')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                routerConfig: _router,
              );
            },
          ),
        ),
      ),
    );
  }
}
