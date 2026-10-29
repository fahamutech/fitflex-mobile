// Vendor reports · S6 (design spec docs/design/vendor-reports-s6.md §3):
// the period a report covers, worked out on EAT calendar days.
//
// The app sends dates only (`from`, `to`, inclusive, YYYY-MM-DD) and never
// instants: the server owns the EAT bucketing (Q-16). These rules mirror the
// server's (src/shared/vendor-reports.mjs, fitflex-functions#275) so a choice
// the server would refuse is not offered:
// - a week is Monday–Sunday, a month the calendar month;
// - `to` is today at the latest, the range at most 366 days;
// - grouping auto = day up to 31 days, week up to 182 days, else month;
//   a grouping that gives more than 120 bars is not offered.
import '../../../shared/formatters.dart' show formatDayMonth;
import '../stock/stock_options.dart' show eatDay, eatToday;

/// The period presets, in the order the pills show them (§3).
enum ReportPreset {
  today,
  yesterday,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  custom,
}

/// How bars and rows are grouped (Sales and Profit).
enum ReportGroupBy { day, week, month }

/// Limits the server holds (Q-10).
const reportMaxDays = 366;
const reportMaxBuckets = 120;

/// Charts are drawn up to this many bars; beyond, the table only (§5).
const reportChartMaxBars = 31;

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
DateTime _addDays(DateTime d, int n) =>
    DateTime.utc(d.year, d.month, d.day + n);

/// Monday of [day]'s week.
DateTime weekStartOf(DateTime day) => _addDays(_day(day), -(day.weekday - 1));
DateTime _monthStart(DateTime d) => DateTime.utc(d.year, d.month);
DateTime _monthEnd(DateTime d) => DateTime.utc(d.year, d.month + 1, 0);

/// Days from [from] to [to], both counted.
int daysInclusive(DateTime from, DateTime to) =>
    _day(to).difference(_day(from)).inDays + 1;

/// The grouping the server picks when none is sent.
ReportGroupBy autoGroupBy(int days) => days <= 31
    ? ReportGroupBy.day
    : days <= 182
    ? ReportGroupBy.week
    : ReportGroupBy.month;

/// How many bars [groupBy] gives over [from]..[to] (the server's count:
/// weeks and months that start before [from] still count once).
int bucketCount(DateTime from, DateTime to, ReportGroupBy groupBy) {
  switch (groupBy) {
    case ReportGroupBy.day:
      return daysInclusive(from, to);
    case ReportGroupBy.week:
      return weekStartOf(to).difference(weekStartOf(from)).inDays ~/ 7 + 1;
    case ReportGroupBy.month:
      return (to.year - from.year) * 12 + to.month - from.month + 1;
  }
}

/// Why a custom range cannot be used, or null when it can.
enum RangeProblem { toBeforeFrom, future, tooLong }

RangeProblem? checkRange(DateTime from, DateTime to, {DateTime? now}) {
  final today = eatToday(now);
  if (_day(to).isBefore(_day(from))) return RangeProblem.toBeforeFrom;
  if (_day(to).isAfter(today)) return RangeProblem.future;
  if (daysInclusive(from, to) > reportMaxDays) return RangeProblem.tooLong;
  return null;
}

/// One chosen period: a preset (or a custom range) resolved to EAT dates.
class ReportPeriod {
  const ReportPeriod._(this.preset, this.from, this.to);

  /// A preset as of [now] (today in EAT).
  factory ReportPeriod.preset(ReportPreset preset, {DateTime? now}) {
    final today = eatToday(now);
    switch (preset) {
      case ReportPreset.today:
        return ReportPeriod._(preset, today, today);
      case ReportPreset.yesterday:
        final y = _addDays(today, -1);
        return ReportPeriod._(preset, y, y);
      case ReportPreset.thisWeek:
        return ReportPeriod._(preset, weekStartOf(today), today);
      case ReportPreset.lastWeek:
        final start = _addDays(weekStartOf(today), -7);
        return ReportPeriod._(preset, start, _addDays(start, 6));
      case ReportPreset.thisMonth:
        return ReportPeriod._(preset, _monthStart(today), today);
      case ReportPreset.lastMonth:
        final start = DateTime.utc(today.year, today.month - 1);
        return ReportPeriod._(preset, start, _monthEnd(start));
      case ReportPreset.custom:
        return ReportPeriod._(preset, _monthStart(today), today);
    }
  }

  /// A custom range; check it with [checkRange] first.
  factory ReportPeriod.custom(DateTime from, DateTime to) =>
      ReportPeriod._(ReportPreset.custom, _day(from), _day(to));

  /// The default (This month).
  factory ReportPeriod.initial({DateTime? now}) =>
      ReportPeriod.preset(ReportPreset.thisMonth, now: now);

  final ReportPreset preset;
  final DateTime from;
  final DateTime to;

  String get fromParam => eatDay(from);
  String get toParam => eatDay(to);
  int get days => daysInclusive(from, to);
  ReportGroupBy get autoGrouping => autoGroupBy(days);

  /// Whether [groupBy] stays within the server's bar limit.
  bool allows(ReportGroupBy groupBy) =>
      bucketCount(from, to, groupBy) <= reportMaxBuckets;

  @override
  bool operator ==(Object other) =>
      other is ReportPeriod &&
      other.preset == preset &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(preset, from, to);
}

/// The API value of a grouping.
String groupByParam(ReportGroupBy g) => g.name;

ReportGroupBy? groupByOf(Object? value) => switch (value) {
  'day' => ReportGroupBy.day,
  'week' => ReportGroupBy.week,
  'month' => ReportGroupBy.month,
  _ => null,
};

/// A YYYY-MM-DD date from the server, as a UTC calendar day.
DateTime? parseDay(Object? value) {
  final s = value?.toString() ?? '';
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return null;
  final d = DateTime.tryParse('${s}T00:00:00Z');
  return d == null ? null : _day(d);
}

String _month(DateTime d, String lang) =>
    formatDayMonth(d, locale: lang).split(' ').last;

/// "14 Oct 2026", "1–31 Oct 2026", "28 Sep – 4 Oct 2026",
/// "30 Dec 2025 – 2 Jan 2026" (sw "1–31 Okt 2026"): the same words as the
/// server's PDF and CSV.
String periodInWords(DateTime from, DateTime to, String lang) {
  if (from == to) return '${from.day} ${_month(from, lang)} ${from.year}';
  if (from.year == to.year && from.month == to.month) {
    return '${from.day}–${to.day} ${_month(from, lang)} ${from.year}';
  }
  if (from.year == to.year) {
    return '${from.day} ${_month(from, lang)} – '
        '${to.day} ${_month(to, lang)} ${to.year}';
  }
  return '${from.day} ${_month(from, lang)} ${from.year} – '
      '${to.day} ${_month(to, lang)} ${to.year}';
}

/// "12 Oct" (sw "12 Okt"): one day of a bucket or a row.
String dayInWords(DateTime d, String lang) => formatDayMonth(d, locale: lang);

/// The time an instant reads in EAT: a 12-hour clock with the part of the
/// day in both languages (owner rule for S6): "2:05 pm" / "2:05 mchana",
/// "12:30 am" / "12:30 usiku".
String reportTime(DateTime instant, String lang) {
  final eat = instant.toUtc().add(const Duration(hours: 3));
  final h12 = eat.hour % 12 == 0 ? 12 : eat.hour % 12;
  final mm = eat.minute.toString().padLeft(2, '0');
  if (lang == 'sw') {
    final h = eat.hour;
    final part = h >= 5 && h < 12
        ? 'asubuhi'
        : h >= 12 && h < 16
        ? 'mchana'
        : h >= 16 && h < 19
        ? 'jioni'
        : 'usiku';
    return '$h12:$mm $part';
  }
  return '$h12:$mm ${eat.hour < 12 ? 'am' : 'pm'}';
}
