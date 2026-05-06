import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_scope.dart';
import 'router.dart';
import 'shared/api_client.dart';
import 'shared/auth_state.dart';
import 'shared/design_tokens.dart';
import 'shared/i18n.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final api = ApiClient();
  final auth = AuthState(api);
  await auth.hydrate();

  final prefs = await SharedPreferences.getInstance();
  final locale = FFLocale();
  final saved = prefs.getString('locale');
  if (saved != null) locale.set(Locale(saved));

  runApp(FitFlexApp(api: api, auth: auth, locale: locale));
}

class FitFlexApp extends StatefulWidget {
  const FitFlexApp({
    super.key,
    required this.api,
    required this.auth,
    required this.locale,
  });

  final ApiClient api;
  final AuthState auth;
  final FFLocale locale;

  @override
  State<FitFlexApp> createState() => _FitFlexAppState();
}

class _FitFlexAppState extends State<FitFlexApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = buildRouter(widget.auth);
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
      child: FFLocaleScope(
        notifier: widget.locale,
        child: AnimatedBuilder(
          animation: widget.locale,
          builder: (context, _) {
            return MaterialApp.router(
              title: 'FitFlex Af',
              debugShowCheckedModeBanner: false,
              theme: buildTheme(),
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
    );
  }
}
