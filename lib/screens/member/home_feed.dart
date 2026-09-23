import 'package:flutter/foundation.dart';

import '../../shared/activity/activity_summary.dart';
import '../../shared/activity/challenge.dart';
import '../../shared/activity/goal.dart';
import '../../shared/activity/progress_engine.dart';
import '../../shared/activity/streaks.dart';
import '../../shared/activity/trainer_connection.dart';
import '../../shared/activity/workout.dart';
import '../../shared/models.dart';
import 'member_shell.dart';
import 'widgets/workout_widgets.dart' show todaysWorkouts;

/// What Home can show. Declaration order breaks ties between equal scores.
enum HomeCardKind {
  passport,
  todayWorkout,
  streak,
  challenge,
  goal,
  todayActivity,
  recommendation,
}

/// Why a card made it onto Home. Drives the copy on streak and
/// recommendation cards, and makes the ranking testable.
enum HomeReason {
  // Passport
  passNeedsAction,
  passActive,
  // Today's workout
  workoutInProgress,
  workoutPlanned,
  // Streak
  streakAtRisk,
  streakMilestone,
  streakBest,
  streakEnded,
  // Challenge
  challengeEndingSoon,
  challengeAlmostThere,
  challengeActive,
  challengeInvite,
  // Goal
  goalAlmostThere,
  goalInProgress,
  goalSetOne,
  // Today's activity
  todayActivity,
  // Recommendation
  gymUsePass,
  gymExplore,
  gymTryNew,
  trainerRegular,
}

@immutable
class HomeCardPick {
  final HomeCardKind kind;
  final HomeReason reason;
  final int score;

  final Workout? workout;
  final StreakStatus? streak;
  final ChallengeStanding? standing;
  final Challenge? invite;
  final GoalProgress? goal;
  final Gym? gym;
  final TrainerProfile? trainer;

  const HomeCardPick(
    this.kind,
    this.reason,
    this.score, {
    this.workout,
    this.streak,
    this.standing,
    this.invite,
    this.goal,
    this.gym,
    this.trainer,
  });

  @override
  String toString() => '$kind/$reason($score)';
}

/// Streak lengths worth celebrating on Home.
const streakMilestones = {7, 14, 21, 30, 50, 75, 100, 150, 200, 365};

/// Hour of day after which an unbroken streak with nothing logged today is
/// "at risk". Earlier than this the member still has most of the day.
const streakAtRiskHour = 15;

/// Picks at most [max] cards for Home, most relevant first. The Gym
/// Passport is always one of them: it holds the check-in QR.
///
/// Scores are coarse on purpose: something that needs doing today (a
/// workout in progress, a streak about to break, a challenge closing)
/// beats progress updates, which beat invitations and recommendations.
/// Cards below [minScore] never show, so a quiet day gives a short Home.
List<HomeCardPick> pickHomeCards(
  MemberData d,
  DateTime now, {
  int max = 4,
  int minScore = 20,
  double? lat,
  double? lng,
}) {
  final picks = <HomeCardPick>[
    _passport(d),
    ?_workout(d, now),
    ?_streak(d, now),
    ?_challenge(d, now),
    ?_goal(d, now),
    if (d.activityLoaded)
      const HomeCardPick(
        HomeCardKind.todayActivity,
        HomeReason.todayActivity,
        60,
      ),
    ?_recommendation(d, now, lat: lat, lng: lng),
  ].where((p) => p.score >= minScore).toList();

  picks.sort((a, b) {
    final s = b.score.compareTo(a.score);
    return s != 0 ? s : a.kind.index.compareTo(b.kind.index);
  });
  final top = picks.take(max).toList();
  if (!top.any((p) => p.kind == HomeCardKind.passport)) {
    top
      ..removeLast()
      ..add(picks.firstWhere((p) => p.kind == HomeCardKind.passport));
  }
  return top;
}

HomeCardPick _passport(MemberData d) {
  final sub = d.subscription;
  final me = d.me;
  final cap = me?.visitCap;
  final lowVisits = cap != null && cap - (me?.visitsUsed ?? 0) <= 1;
  final expiring = sub?.isDirect == true && (sub?.daysLeft ?? 99) <= 5;
  final action =
      !d.hasActivePass || d.pendingPayment != null || lowVisits || expiring;
  return HomeCardPick(
    HomeCardKind.passport,
    action ? HomeReason.passNeedsAction : HomeReason.passActive,
    action ? 100 : 50,
  );
}

HomeCardPick? _workout(MemberData d, DateTime now) {
  if (!d.workoutsLoaded) return null;
  final w = todaysWorkouts(d.workouts, now).firstOrNull;
  if (w == null) return null;
  if (w.status == WorkoutStatus.inProgress) {
    return HomeCardPick(
      HomeCardKind.todayWorkout,
      HomeReason.workoutInProgress,
      95,
      workout: w,
    );
  }
  return HomeCardPick(
    HomeCardKind.todayWorkout,
    HomeReason.workoutPlanned,
    w.fromTrainer ? 85 : 80,
    workout: w,
  );
}

HomeCardPick? _streak(MemberData d, DateTime now) {
  if (!d.activityLoaded) return null;
  final s = computeStreak(
    StreakKind.activity,
    today: now,
    activities: d.activities,
  );
  if (s == null) return null;
  final todayDone = summarizeDay(d.activities, now).countsForStreak;
  HomeCardPick pick(HomeReason r, int score) =>
      HomeCardPick(HomeCardKind.streak, r, score, streak: s);
  if (s.current >= 2 && !todayDone && now.hour >= streakAtRiskHour) {
    return pick(HomeReason.streakAtRisk, 90);
  }
  if (todayDone && streakMilestones.contains(s.current)) {
    return pick(HomeReason.streakMilestone, 70);
  }
  if (todayDone && s.current >= 3 && s.current == s.best) {
    return pick(HomeReason.streakBest, 55);
  }
  if (s.justEnded && (s.endedLength ?? 0) >= 3) {
    return pick(HomeReason.streakEnded, 52);
  }
  return null;
}

HomeCardPick? _challenge(MemberData d, DateTime now) {
  if (!d.challengesLoaded) return null;
  final g = groupChallenges(
    d.challenges,
    d.activities,
    checkIns: d.checkInMoments,
  );
  final s = g.active
      .where((s) => s.challenge.phase == ChallengePhase.active)
      .firstOrNull;
  if (s != null) {
    if (s.challenge.daysLeft(now) <= 2) {
      return HomeCardPick(
        HomeCardKind.challenge,
        HomeReason.challengeEndingSoon,
        88,
        standing: s,
      );
    }
    return HomeCardPick(
      HomeCardKind.challenge,
      s.fraction >= 0.8
          ? HomeReason.challengeAlmostThere
          : HomeReason.challengeActive,
      s.fraction >= 0.8 ? 68 : 58,
      standing: s,
    );
  }
  final open = g.available.firstOrNull;
  if (open == null) return null;
  return HomeCardPick(
    HomeCardKind.challenge,
    HomeReason.challengeInvite,
    25,
    invite: open,
  );
}

HomeCardPick? _goal(MemberData d, DateTime now) {
  if (!d.goalsLoaded) return null;
  if (d.goals.isEmpty) {
    return const HomeCardPick(HomeCardKind.goal, HomeReason.goalSetOne, 28);
  }
  // The daily step goal already shows as the bar on Today's activity.
  final steps = dailyStepGoal(d.goals);
  final open = [
    for (final g in d.goals)
      if (g.status == GoalStatus.active && g.id != steps?.id)
        evaluateGoal(g, d.activities, now),
  ].where((p) => !p.completed && !p.ended && !p.upcoming).toList();
  if (open.isEmpty) return null;
  open.sort((a, b) => b.fraction.compareTo(a.fraction));
  final best = open.first;
  return HomeCardPick(
    HomeCardKind.goal,
    best.fraction >= 0.75
        ? HomeReason.goalAlmostThere
        : HomeReason.goalInProgress,
    best.fraction >= 0.75 ? 78 : 48,
    goal: best,
  );
}

/// One recommendation at most: a gym or a trainer, whichever fits better.
HomeCardPick? _recommendation(
  MemberData d,
  DateTime now, {
  double? lat,
  double? lng,
}) {
  final visits = d.checkInMoments;
  final visited = {for (final v in visits) ?v.gymId};
  final gymPick = _gymPick(d, visited, lat: lat, lng: lng);

  HomeCardPick? gym;
  if (gymPick != null) {
    final sub = d.subscription;
    final since = now.subtract(const Duration(days: 30));
    final recentGyms = {
      for (final v in visits)
        if (v.at.isAfter(since)) ?v.gymId,
    };
    if (visits.isEmpty && d.hasActivePass) {
      gym = HomeCardPick(
        HomeCardKind.recommendation,
        HomeReason.gymUsePass,
        75,
        gym: gymPick,
      );
    } else if (!d.hasActivePass) {
      gym = HomeCardPick(
        HomeCardKind.recommendation,
        HomeReason.gymExplore,
        35,
        gym: gymPick,
      );
    } else if (sub != null && !sub.isDirect && recentGyms.length <= 1) {
      // A multi-gym pass used at one gym only.
      gym = HomeCardPick(
        HomeCardKind.recommendation,
        HomeReason.gymTryNew,
        30,
        gym: gymPick,
      );
    }
  }

  HomeCardPick? trainer;
  final hasTrainer = d.trainerConnections.any(
    (c) =>
        c.status == TrainerConnectionStatus.active ||
        c.status == TrainerConnectionStatus.pending,
  );
  final t = d.trainers.firstOrNull;
  if (!hasTrainer && t != null) {
    final since = now.subtract(const Duration(days: 30));
    final recentWorkouts = d.activities
        .where((a) => a.startedAt.isAfter(since) && a.isWorkout)
        .length;
    if (recentWorkouts >= 3) {
      trainer = HomeCardPick(
        HomeCardKind.recommendation,
        HomeReason.trainerRegular,
        40,
        trainer: t,
      );
    }
  }

  if (gym == null) return trainer;
  if (trainer == null) return gym;
  return trainer.score > gym.score ? trainer : gym;
}

/// Nearest gym the member hasn't visited (the first one when there's no
/// location), skipping their home gym.
Gym? _gymPick(MemberData d, Set<String> visited, {double? lat, double? lng}) {
  final home = d.subscription?.homeGymId;
  final fresh = d.gyms
      .where((g) => !visited.contains(g.id) && g.id != home)
      .toList();
  if (fresh.isEmpty) return null;
  if (lat != null && lng != null) {
    fresh.sort(
      (a, b) =>
          gymDistanceKm(a, lat, lng).compareTo(gymDistanceKm(b, lat, lng)),
    );
  }
  return fresh.first;
}
