import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/activity/exercise_library_cache.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';

// Programmes P1 (M2): the rest timer between sets and an exercise's picture
// and clip (PD-4: the clip opens outside the app; no in-app video player).

/// "0:45".
String restClock(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// The bar that slides up after a set is ticked: "Rest 0:45", +15 s, Skip;
/// at 0 it reads "Next set".
class WorkoutRestBar extends StatelessWidget {
  const WorkoutRestBar({
    super.key,
    required this.secondsLeft,
    required this.onAdd,
    required this.onDismiss,
  });

  final int secondsLeft;
  final VoidCallback onAdd;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = secondsLeft <= 0;
    return Material(
      key: const Key('workout-rest-bar'),
      color: theme.colorScheme.surfaceContainerHighest,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FFTokens.spacingLg,
            vertical: FFTokens.spacingSm,
          ),
          child: Row(
            children: [
              Icon(Icons.timer_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: FFTokens.spacingSm),
              Expanded(
                child: ExcludeSemantics(
                  // The time is announced at 10 s and at 0, not every second.
                  child: Text(
                    done
                        ? context.tr('workout.nextSet')
                        : context
                              .tr('workout.rest')
                              .replaceAll('{time}', restClock(secondsLeft)),
                    key: const Key('workout-rest-time'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              if (!done)
                Semantics(
                  button: true,
                  label: context.tr('workout.addRestLabel'),
                  excludeSemantics: true,
                  child: FFButton(
                    key: const Key('workout-rest-add'),
                    label: context.tr('workout.addRest'),
                    variant: FFButtonVariant.ghost,
                    size: FFButtonSize.sm,
                    onPressed: onAdd,
                  ),
                ),
              Semantics(
                button: true,
                label: done
                    ? context.tr('workout.nextSet')
                    : context.tr('workout.skipRestLabel'),
                excludeSemantics: true,
                child: FFButton(
                  key: const Key('workout-rest-skip'),
                  label: done
                      ? context.tr('workout.nextSet')
                      : context.tr('workout.skipRest'),
                  variant: done
                      ? FFButtonVariant.primary
                      : FFButtonVariant.secondary,
                  size: FFButtonSize.sm,
                  onPressed: onDismiss,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _clipNoticeKey = 'ff.workout.clipNoticeSeen';

/// An exercise's picture (16:9) and a "Watch clip" button, when the library
/// has them. Nothing at all otherwise.
class ExerciseMedia extends StatelessWidget {
  const ExerciseMedia({super.key, required this.libraryId, required this.name});

  final String? libraryId;
  final String name;

  Future<void> _watch(BuildContext context, String url) async {
    final messenger = FFSnack.of(context);
    final failed = context.tr('workout.clipFailed');
    var seen = false;
    try {
      seen =
          (await SharedPreferences.getInstance()).getBool(_clipNoticeKey) ??
          false;
    } catch (_) {}
    if (!seen) {
      if (!context.mounted) return;
      final go = await showFFSheet<bool>(
        context,
        title: context.tr('workout.clipTitle'),
        child: const _ClipNotice(),
      );
      if (go != true) return;
    }
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!ok) messenger.error(failed);
  }

  @override
  Widget build(BuildContext context) {
    final lib = ExerciseLibraryCache.of(libraryId);
    final still = lib?.stillUrl;
    final clip = lib?.clipUrl;
    if (still == null && clip == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (still != null)
            Semantics(
              image: true,
              label: context.tr('workout.stillAlt').replaceAll('{name}', name),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: FFRemoteImage(
                    key: Key('exercise-still-$libraryId'),
                    src: still,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          if (clip != null)
            FFButton(
              key: Key('exercise-clip-$libraryId'),
              label: context.tr('workout.watchClip'),
              icon: Icons.play_circle_outline,
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
              onPressed: () => _watch(context, clip),
            ),
        ],
      ),
    );
  }
}

class _ClipNotice extends StatefulWidget {
  const _ClipNotice();

  @override
  State<_ClipNotice> createState() => _ClipNoticeState();
}

class _ClipNoticeState extends State<_ClipNotice> {
  bool _dontShow = false;

  Future<void> _open() async {
    final navigator = Navigator.of(context);
    if (_dontShow) {
      try {
        await (await SharedPreferences.getInstance()).setBool(
          _clipNoticeKey,
          true,
        );
      } catch (_) {}
    }
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(context.tr('workout.clipBody')),
      CheckboxListTile(
        key: const Key('workout-clip-dont-show'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _dontShow,
        onChanged: (v) => setState(() => _dontShow = v ?? false),
        title: Text(context.tr('workout.clipDontShow')),
      ),
      FFButton(
        key: const Key('workout-clip-open'),
        fullWidth: true,
        label: context.tr('workout.clipOpen'),
        onPressed: _open,
      ),
    ],
  );
}
