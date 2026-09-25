import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/activity/gps_source.dart';
import '../../shared/activity/run_metrics.dart';
import '../../shared/activity/run_recorder.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import '../../shared/social.dart';
import 'widgets/run_widgets.dart';
import 'widgets/share_picker.dart';

/// Record a run with GPS: Start, Pause/Resume, Finish, then save or discard.
/// Everything is measured automatically; the route is private.
class MemberRecordRunPage extends StatefulWidget {
  const MemberRecordRunPage({super.key});

  @override
  State<MemberRecordRunPage> createState() => _MemberRecordRunPageState();
}

class _MemberRecordRunPageState extends State<MemberRecordRunPage> {
  bool _saving = false;
  final _notes = TextEditingController();
  ShareWith? _share;
  bool _shareChosen = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _start(RunRecorder r, {bool resume = false}) async {
    final title = context.tr('run.notificationTitle');
    final text = context.tr('run.notificationText');
    if (resume) {
      await r.resume(notificationTitle: title, notificationText: text);
    } else {
      await r.start(notificationTitle: title, notificationText: text);
    }
  }

  Future<void> _finish(RunRecorder r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('run.finishTitle')),
        content: Text(ctx.tr('run.finishBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('run.keepGoing')),
          ),
          FilledButton(
            key: const Key('run-finish-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('run.finish')),
          ),
        ],
      ),
    );
    if (ok == true) await r.finish();
  }

  Future<void> _save(RunRecorder r) async {
    final scope = AppScope.of(context);
    final shell = context.findAncestorStateOfType<MemberShellState>();
    final messenger = ScaffoldMessenger.of(context);
    final saved = context.tr('run.savedToast');
    final failed = context.tr('run.saveFailed');
    final tooShort = context.tr('run.tooShort');
    setState(() => _saving = true);
    try {
      await r.save(
        scope.api,
        notes: _notes.text,
        shareWith: _share?.toJson(),
        shareChosen: _shareChosen,
      );
      await shell?.refreshAfterWorkout();
      messenger.showSnackBar(SnackBar(content: Text(saved)));
      if (mounted) context.go(AppRoutes.memberActivity);
    } catch (e) {
      final short = e.toString().contains('too_short');
      messenger.showSnackBar(
        SnackBar(content: Text(short ? tooShort : failed)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _discard(RunRecorder r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('run.discardTitle')),
        content: Text(ctx.tr('run.discardBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('trainer.cancel')),
          ),
          FilledButton(
            key: const Key('run-discard-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('run.discard')),
          ),
        ],
      ),
    );
    if (ok == true) await r.discard();
  }

  @override
  Widget build(BuildContext context) {
    final r = AppScope.of(context).runRecorder;
    if (r == null || !r.supported) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('run.title'))),
        body: FFEmptyState(
          title: context.tr('run.unsupportedTitle'),
          body: context.tr('run.unsupportedBody'),
        ),
      );
    }
    final weightKg = MemberDataScope.of(
      context,
    ).me?.user.memberProfile?.weightKg;
    return ListenableBuilder(
      listenable: r,
      builder: (context, _) {
        final m = r.metrics;
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(
            title: Text(context.tr('run.title')),
            leading: BackButton(
              onPressed: () => context.go(AppRoutes.memberActivity),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            children: [
              if (r.restored)
                Padding(
                  padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
                  child: FFAlert(
                    key: const Key('run-restored'),
                    message: context.tr('run.restoredBody'),
                  ),
                ),
              if (r.access != null && r.access != GpsAccess.granted)
                _AccessAlert(recorder: r),
              RunMap(
                segments: r.segments,
                follow: r.state == RunState.recording,
                height: r.state == RunState.finished ? 220 : 280,
              ),
              const SizedBox(height: FFTokens.spacingMd),
              if (r.state == RunState.finished) ...[
                RunSummaryGrid(
                  distanceKm: m.distanceKm,
                  seconds: m.movingSeconds,
                  elevationGainM: m.elevationGainM,
                  calories: runCalories(
                    distanceKm: m.distanceKm,
                    movingSeconds: m.movingSeconds,
                    weightKg: weightKg,
                  ),
                ),
                const SizedBox(height: FFTokens.spacingMd),
                RunSplits(splits: m.splits),
                const SizedBox(height: FFTokens.spacingMd),
                TextField(
                  controller: _notes,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: context.tr('run.notes'),
                    hintText: context.tr('run.notesHint'),
                  ),
                ),
                FFActionTile(
                  key: const Key('run-share'),
                  icon: _shareChosen && _share == null
                      ? Icons.lock_outline
                      : Icons.people_outline,
                  title: context.tr('audience.whoCanSee'),
                  subtitle: _shareChosen
                      ? shareLabel(context, _share)
                      : context.tr('audience.useDefault'),
                  onTap: () async {
                    final res = await pickShare(context, initial: _share);
                    if (!res.cancelled) {
                      setState(() {
                        _share = res.share;
                        _shareChosen = true;
                      });
                    }
                  },
                ),
                Text(
                  context.tr('run.privateNote'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: FFTokens.spacingMd),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('run-discard'),
                        onPressed: _saving ? null : () => _discard(r),
                        child: Text(context.tr('run.discard')),
                      ),
                    ),
                    const SizedBox(width: FFTokens.spacingSm),
                    Expanded(
                      child: FilledButton(
                        key: const Key('run-save'),
                        onPressed: _saving ? null : () => _save(r),
                        child: Text(context.tr('run.save')),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                FFCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RunStat(
                        value: formatRunKm(m.distanceKm),
                        label: context.tr('run.distance'),
                        big: true,
                      ),
                      const SizedBox(height: FFTokens.spacingMd),
                      Row(
                        children: [
                          Expanded(
                            child: RunStat(
                              value: formatDuration(r.elapsed.inSeconds),
                              label: context.tr('run.time'),
                            ),
                          ),
                          Expanded(
                            child: RunStat(
                              value: formatPace(m.paceSecPerKm),
                              label: context.tr('run.avgPace'),
                            ),
                          ),
                          Expanded(
                            child: RunStat(
                              value: '${m.elevationGainM} m',
                              label: context.tr('run.climb'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: FFTokens.spacingSm),
                Text(
                  context.tr(switch (r.state) {
                    RunState.recording when !r.hasFix => 'run.waitingGps',
                    RunState.recording => 'run.recordingHint',
                    RunState.paused => 'run.pausedHint',
                    _ => 'run.startHint',
                  }),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: FFTokens.spacingLg),
                _Controls(
                  recorder: r,
                  onStart: () => _start(r),
                  onResume: () => _start(r, resume: true),
                  onFinish: () => _finish(r),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.recorder,
    required this.onStart,
    required this.onResume,
    required this.onFinish,
  });

  final RunRecorder recorder;
  final VoidCallback onStart;
  final VoidCallback onResume;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final big = FilledButton.styleFrom(minimumSize: const Size.fromHeight(56));
    switch (recorder.state) {
      case RunState.idle:
        return FilledButton.icon(
          key: const Key('run-start'),
          style: big,
          onPressed: onStart,
          icon: const Icon(Icons.play_arrow),
          label: Text(context.tr('run.start')),
        );
      case RunState.recording:
        return FilledButton.tonalIcon(
          key: const Key('run-pause'),
          style: big,
          onPressed: recorder.pause,
          icon: const Icon(Icons.pause),
          label: Text(context.tr('run.pause')),
        );
      case RunState.paused:
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('run-resume'),
                style: big,
                onPressed: onResume,
                icon: const Icon(Icons.play_arrow),
                label: Text(context.tr('run.resume')),
              ),
            ),
            const SizedBox(width: FFTokens.spacingSm),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('run-finish'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: onFinish,
                icon: const Icon(Icons.flag),
                label: Text(context.tr('run.finish')),
              ),
            ),
          ],
        );
      case RunState.finished:
        return const SizedBox.shrink();
    }
  }
}

class _AccessAlert extends StatelessWidget {
  const _AccessAlert({required this.recorder});

  final RunRecorder recorder;

  @override
  Widget build(BuildContext context) {
    final off = recorder.access == GpsAccess.serviceOff;
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FFAlert(
            key: const Key('run-access'),
            tone: FFAlertTone.warning,
            message: context.tr(
              off ? 'run.locationOffBody' : 'run.permissionBody',
            ),
          ),
          TextButton(
            onPressed: off
                ? recorder.gps.openLocationSettings
                : recorder.gps.openAppSettings,
            child: Text(context.tr('phoneSteps.openSettings')),
          ),
        ],
      ),
    );
  }
}
