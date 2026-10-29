import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../components/ff_logo_plate.dart';
import 'partner_media_flag.dart';
import 'partner_media_models.dart';
import 'partner_media_store.dart';

/// Builds a home band with the partner's saved photo and logo (spec §40.1).
///
/// The saved copy is read when the band is first built and again only when
/// the home comes back into view: [visible] turns true (a tab switch back to
/// Home / Products), [subject] changes (a gym switch), the route it is on
/// becomes the top one again, or the app's location returns to where it was
/// built (a pushed page such as the settings page closes). A photo saved
/// while the band is on screen never replaces the one it shows. After the
/// first frame, and on each of those moments, [PartnerMediaStore.refresh]
/// asks the server in the background (at most every 30 s per partner).
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

  @override
  State<PartnerHeroBuilder> createState() => _PartnerHeroBuilderState();
}

class _PartnerHeroBuilderState extends State<PartnerHeroBuilder> {
  PartnerHeroMedia? _media;
  bool _wasCurrent = true;
  GoRouter? _router;
  String? _homePath;
  bool _away = false;

  PartnerMediaStore? get _store =>
      partnerMediaUi ? PartnerMediaStore.instance : null;

  @override
  void initState() {
    super.initState();
    _media = _store?.readyFor(widget.subject);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ask(force: false);
    });
  }

  void _ask({required bool force}) {
    final s = widget.subject;
    final store = _store;
    if (s == null || store == null) return;
    unawaited(store.refresh(s, force: force));
  }

  /// The home came into view: show what is saved now, then check again.
  void _cameIntoView({bool force = false}) {
    final next = _store?.readyFor(widget.subject);
    if (next != _media) setState(() => _media = next);
    _ask(force: force);
  }

  @override
  void didUpdateWidget(PartnerHeroBuilder old) {
    super.didUpdateWidget(old);
    if (old.subject != widget.subject) {
      _media = _store?.readyFor(widget.subject);
      _ask(force: true);
    } else if (!old.visible && widget.visible) {
      _media = _store?.readyFor(widget.subject);
      _ask(force: false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current && !_wasCurrent) {
      // Built in this frame anyway (a dependency changed).
      _media = _store?.readyFor(widget.subject);
      _ask(force: false);
    }
    _wasCurrent = current;
    final router = _store == null ? null : GoRouter.maybeOf(context);
    if (router != _router) {
      _router?.routerDelegate.removeListener(_onLocation);
      _router = router;
      _homePath = _path();
      router?.routerDelegate.addListener(_onLocation);
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
      _cameIntoView();
    }
  }

  @override
  void dispose() {
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
