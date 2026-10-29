import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../components/ff_logo_plate.dart';
import 'partner_media_flag.dart';
import 'partner_media_models.dart';
import 'partner_media_store.dart';

/// Watches the app's root navigator for full pages coming and going, so a
/// home knows when it is uncovered again (a pushed page such as Profile or
/// the settings page closes; spec §40.1). Dialogs, sheets and other popups
/// are ignored: the home never left view under them. Registered on the
/// GoRouter only while `PARTNER_MEDIA_UI` is on (router.dart).
class PartnerRouteWatch extends NavigatorObserver with ChangeNotifier {
  /// The watch on the running router, or null (flag off, tests without it).
  static PartnerRouteWatch? root;

  final List<Route<dynamic>> _pages = [];

  /// The top full page of the root navigator.
  Route<dynamic>? get top => _pages.isEmpty ? null : _pages.last;

  static bool _isPage(Route<dynamic>? r) => r is PageRoute;

  void _changed() {
    // Navigator callbacks run while it is updating: tell listeners after.
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_isPage(route)) return;
    _pages.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_isPage(route)) return;
    _pages.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_isPage(route)) return;
    _pages.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _pages.indexOf(oldRoute);
    if (i >= 0) _pages.removeAt(i);
    if (_isPage(newRoute)) {
      _pages.insert(i >= 0 ? i : _pages.length, newRoute!);
    }
    _changed();
  }
}

/// Builds a home band with the partner's saved photo and logo (spec §40.1).
///
/// The saved copy is read when the band is first built and again only when
/// the home comes back into view: [visible] turns true (a tab switch back to
/// Home / Products), [subject] changes (a gym switch), a full page pushed
/// over the home closes ([PartnerRouteWatch]), or the app's location returns
/// to where it was built. A photo saved while the band is on screen never
/// replaces the one it shows, with one exception: the very first answer of
/// the session for this partner (no saved copy yet: the web after a reload,
/// a first sign-in, a staff member with one tab), which may bring the photo
/// in once, fading in over the bundled one ([firstLoadWindow]).
///
/// With `PARTNER_MEDIA_UI` off, or no [subject], [builder] gets null and
/// nothing is asked.
class PartnerHeroBuilder extends StatefulWidget {
  const PartnerHeroBuilder({
    super.key,
    required this.subject,
    required this.builder,
    this.visible = true,
  });

  final PartnerMediaSubject? subject;
  final bool visible;
  final Widget Function(BuildContext context, PartnerHeroMedia? media) builder;

  /// The first answer may still bring the photo in this long after the home
  /// was first built; later, it waits for the next view.
  static const Duration firstLoadWindow = Duration(seconds: 8);

  @override
  State<PartnerHeroBuilder> createState() => _PartnerHeroBuilderState();
}

class _PartnerHeroBuilderState extends State<PartnerHeroBuilder> {
  PartnerHeroMedia? _media;
  GoRouter? _router;
  String? _homePath;
  bool _away = false;
  PartnerRouteWatch? _watch;
  Route<dynamic>? _myPage;
  bool _covered = false;

  /// Bumped on every view change, so a late first answer never lands on a
  /// view it wasn't asked for.
  int _view = 0;

  PartnerMediaStore? get _store =>
      partnerMediaUi ? PartnerMediaStore.instance : null;

  @override
  void initState() {
    super.initState();
    _media = _store?.readyFor(widget.subject);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _firstLoad();
    });
  }

  /// Asks the server; when this partner had no answer yet this session,
  /// shows what it brings (once, within [PartnerHeroBuilder.firstLoadWindow]).
  void _firstLoad({bool force = false}) {
    final s = widget.subject;
    final store = _store;
    if (s == null || store == null) return;
    final first = !store.resolved(s);
    final view = _view;
    final started = DateTime.now();
    unawaited(
      store.refresh(s, force: force).then((_) {
        if (!first || !mounted || view != _view) return;
        if (DateTime.now().difference(started) >
            PartnerHeroBuilder.firstLoadWindow) {
          return;
        }
        final next = store.readyFor(widget.subject);
        if (next != _media) setState(() => _media = next);
      }),
    );
  }

  /// The home came into view: show what is saved now, then check again.
  void _cameIntoView() {
    if (!mounted) return;
    _view++;
    final next = _store?.readyFor(widget.subject);
    if (next != _media) setState(() => _media = next);
    _firstLoad();
  }

  @override
  void didUpdateWidget(PartnerHeroBuilder old) {
    super.didUpdateWidget(old);
    if (old.subject != widget.subject) {
      _view++;
      _media = _store?.readyFor(widget.subject);
      _firstLoad(force: true);
    } else if (!old.visible && widget.visible) {
      _view++;
      _media = _store?.readyFor(widget.subject);
      _firstLoad();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = _store;
    final watch = store == null ? null : PartnerRouteWatch.root;
    if (watch != _watch) {
      _watch?.removeListener(_onPages);
      _watch = watch;
      _myPage = watch?.top;
      watch?.addListener(_onPages);
    }
    final router = store == null ? null : GoRouter.maybeOf(context);
    if (router != _router) {
      _router?.routerDelegate.removeListener(_onLocation);
      _router = router;
      _homePath = _path();
      router?.routerDelegate.addListener(_onLocation);
    }
  }

  void _onPages() {
    final watch = _watch;
    if (!mounted || watch == null) return;
    _myPage ??= watch.top;
    final covered = watch.top != _myPage;
    if (covered) {
      _covered = true;
    } else if (_covered) {
      _covered = false;
      _away = false;
      _cameIntoView();
    }
  }

  String? _path() {
    try {
      return _router?.routerDelegate.currentConfiguration.uri.path;
    } catch (_) {
      return null;
    }
  }

  void _onLocation() {
    if (!mounted) return;
    final path = _path();
    if (path == null) return;
    _homePath ??= path;
    if (path != _homePath) {
      _away = true;
    } else if (_away) {
      _away = false;
      // The page watch may already have shown it.
      if (!_covered) _cameIntoView();
    }
  }

  @override
  void dispose() {
    _watch?.removeListener(_onPages);
    _router?.routerDelegate.removeListener(_onLocation);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    widget.subject == null || _store == null ? null : _media,
  );
}

/// The plate for a saved [logo], or null.
Widget? partnerLogoPlate(PartnerLogoImage? logo) => logo == null
    ? null
    : FFLogoPlate(
        key: ValueKey('plate-${logo.id}'),
        image: logo.provider,
        aspect: logo.aspect,
        dark: logo.dark,
      );
