import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'app_scope.dart';
import 'shared/activity/activity_config.dart';
import 'shared/activity/phone_steps.dart';
import 'shared/activity/run_recorder.dart';
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
  // Phone step counting runs a background reading on Android.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android && !mockAuth) {
    await initPhoneStepsBackground();
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
  PhoneSteps? _phoneSteps;
  RunRecorder? _runs;
  String? _lastToken;

  @override
  void initState() {
    super.initState();
    _router = buildRouter(widget.auth);
    final sample = activitySampleDataEnabled();
    _activity = ActivityBackend.create(widget.api, sample: sample);
    // Real steps go to the server, so the phone counter only runs with real
    // activity data (not sample mode).
    if (!sample && phoneStepsSupported()) {
      _phoneSteps = createPhoneSteps()..load();
    }
    // Runs are saved to the server, so recording needs real activity data.
    if (!sample && runRecordingSupported()) {
      _runs = createRunRecorder()..restore();
    }
    _lastToken = widget.auth.token;
    widget.auth.addListener(_onAuth);
  }

  void _onAuth() {
    final token = widget.auth.token;
    // Signed out: this phone's steps aren't the next person's.
    if (_lastToken != null && token == null) {
      _phoneSteps?.forget();
      _runs?.discard();
    }
    _lastToken = token;
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onAuth);
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
      manualActivityLog: _activity.manualLog,
      phoneSteps: _phoneSteps,
      runRecorder: _runs,
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
