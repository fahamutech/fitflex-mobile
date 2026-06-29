import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'owner_shell.dart';

/// Owner dashboard home tab — shows stats, quick actions, and gym summary.
class OwnerHomeTab extends StatefulWidget {
  const OwnerHomeTab({super.key});

  @override
  State<OwnerHomeTab> createState() => _OwnerHomeTabState();
}

/// Named preset periods for the analytics date filter.
enum _DatePreset { today, yesterday, thisMonth, thisYear, custom }

class _OwnerHomeTabState extends State<OwnerHomeTab> {
  _DatePreset _activePreset = _DatePreset.thisMonth;

  /// Opens the analytics-style date range bottom sheet.
  Future<void> _showDateFilter() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FFTokens.radiusXl),
        ),
      ),
      builder: (ctx) => _DateFilterSheet(
        activePreset: _activePreset,
        onApply: (preset, from, to) async {
          _activePreset = preset;
          final data = OwnerDataScope.of(context);
          data.update((d) {
            d.statsFrom = from;
            d.statsTo = to;
          });
          final shell = context.findAncestorStateOfType<OwnerShellState>();
          await shell?.refreshDashboard();
          if (mounted) setState(() {});
        },
      ),
    );
  }

  String _presetLabel(BuildContext context) {
    return switch (_activePreset) {
      _DatePreset.today => context.tr('owner.filterToday'),
      _DatePreset.yesterday => context.tr('owner.filterYesterday'),
      _DatePreset.thisMonth => context.tr('owner.filterThisMonth'),
      _DatePreset.thisYear => context.tr('owner.filterThisYear'),
      _DatePreset.custom => context.tr('owner.filterCustom'),
    };
  }

  /// Builds a trend label + direction from current vs previous period counts.
  /// Returns null if previous period has no data.
  (FFTrendDirection?, String?) _computeTrend(
    int current,
    int prev,
    BuildContext ctx,
  ) {
    if (prev == 0 && current == 0) return (null, null);
    if (prev == 0) {
      return (
        FFTrendDirection.up,
        ctx.tr('owner.trendUp').replaceAll('{pct}', '100'),
      );
    }
    final pct = ((current - prev) / prev * 100).round();
    if (pct > 0) {
      return (
        FFTrendDirection.up,
        ctx.tr('owner.trendUp').replaceAll('{pct}', pct.abs().toString()),
      );
    } else if (pct < 0) {
      return (
        FFTrendDirection.down,
        ctx.tr('owner.trendDown').replaceAll('{pct}', pct.abs().toString()),
      );
    } else {
      return (FFTrendDirection.neutral, ctx.tr('owner.trendFlat'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = OwnerDataScope.of(context);
    final dashboard = data.dashboard;
    final ownerGymList = data.ownerGyms;

    if (ownerGymList.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          FFGymUnapprovedCard(
            checking: data.loading,
            onRefresh: () async {
              final shell = context.findAncestorStateOfType<OwnerShellState>();
              await shell?.refreshAll();
            },
          ),
        ],
      );
    }

    final periodVisits = (dashboard?['periodVisits'] as num?)?.toInt() ?? 0;
    final periodMembers = (dashboard?['periodMembers'] as num?)?.toInt() ?? 0;
    final directCount = (dashboard?['directMembers'] as num?)?.toInt() ?? 0;
    final fitflexCount = (dashboard?['fitflexMembers'] as num?)?.toInt() ?? 0;
    // Parse chartSeries from API
    final rawSeries =
        (dashboard?['chartSeries'] as List<dynamic>?) ?? <dynamic>[];
    final chartLabels = rawSeries
        .map((e) => (e as Map<String, dynamic>)['label']?.toString() ?? '')
        .toList();
    final chartDirect = rawSeries
        .map(
          (e) =>
              ((e as Map<String, dynamic>)['direct'] as num?)?.toDouble() ??
              0.0,
        )
        .toList();
    final chartFitflex = rawSeries
        .map(
          (e) =>
              ((e as Map<String, dynamic>)['fitflex'] as num?)?.toDouble() ??
              0.0,
        )
        .toList();

    final prevPeriodVisits =
        (dashboard?['prevPeriodVisits'] as num?)?.toInt() ?? 0;
    final prevPeriodMembers =
        (dashboard?['prevPeriodMembers'] as num?)?.toInt() ?? 0;

    final (visitsTrendDir, visitsTrendLabel) = _computeTrend(
      periodVisits,
      prevPeriodVisits,
      context,
    );
    final (membersTrendDir, membersTrendLabel) = _computeTrend(
      periodMembers,
      prevPeriodMembers,
      context,
    );

    final rawName = data.displayName;
    final cleanName = rawName.split('@').first.split(' ').first;
    final greeting = context.tr('member.goodMorning');

    final bool showChart = directCount > 0 || fitflexCount > 0;

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: FFTokens.spacingLg,
        vertical: FFTokens.spacingMd,
      ),
      children: [
        // 2. Greeting / Overview
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting, $cleanName \ud83d\udc4b',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr('owner.gymSnapshot'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // Filter Picker
            InkWell(
              onTap: _showDateFilter,
              borderRadius: BorderRadius.circular(FFTokens.radiusMd),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      _presetLabel(context),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.keyboard_arrow_down, size: 14),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: FFTokens.spacingLg),

        // 3. Summary cards
        Row(
          children: [
            Expanded(
              child: FFMetricCard(
                label: context.tr('owner.totalMembers'),
                value: '$periodMembers',
                trendDirection: membersTrendDir,
                trendLabel: membersTrendLabel,
                icon: const Icon(
                  Icons.people_outline,
                  color: FFTokens.brand600,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FFMetricCard(
                label: context.tr('owner.checkins'),
                value: '$periodVisits',
                trendDirection: visitsTrendDir,
                trendLabel: visitsTrendLabel,
                icon: const Icon(
                  Icons.check_circle_outline,
                  color: FFTokens.brand600,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: FFTokens.spacingLg),

        // 4. Quick actions
        FFCard(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: IntrinsicHeight(
            child: Row(
              children: [
                _buildQuickAction(
                  context,
                  icon: Icons.qr_code_scanner,
                  title: context.tr('owner.checkin'),
                  onTap: () => context.push('/owner/scan'),
                ),
                _buildActionDivider(context),
                _buildQuickAction(
                  context,
                  icon: Icons.wallet_outlined,
                  title: context.tr('owner.earnings'),
                  onTap: () => context.push('/owner/earnings'),
                ),
                _buildActionDivider(context),
                _buildQuickAction(
                  context,
                  icon: Icons.shopping_bag_outlined,
                  title: context.tr('owner.shop'),
                  onTap: () => context.push('/owner/shop'),
                ),
                _buildActionDivider(context),
                _buildQuickAction(
                  context,
                  icon: Icons.people_outline,
                  title: context.tr('owner.members'),
                  onTap: () => context.go('/owner/members'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: FFTokens.spacingLg),

        // 5. Grow your gym card
        Container(
          padding: const EdgeInsets.all(FFTokens.spacingMd),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                : FFTokens.brand50,
            borderRadius: BorderRadius.circular(FFTokens.radiusXl),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                  : FFTokens.brand100,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.trending_up,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('owner.growGym'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : FFTokens.brand800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('owner.growGymSubtitle'),
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withValues(alpha: 0.8)
                            : FFTokens.brand700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: FFTokens.brand600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                  ),
                  elevation: 0,
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.tr('owner.reportsComingSoon')),
                    ),
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.tr('owner.viewReports'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: FFTokens.spacingLg),

        // 6. Membership insight graph
        FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.tr('owner.membershipOverview'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _presetLabel(context),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down, size: 12),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!showChart) ...[
                // Empty State
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Center(
                        child: Icon(
                          Icons.bar_chart_outlined,
                          size: 48,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.tr('owner.noMembershipData'),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.tr('owner.noMembershipDataSub'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Legends
                Row(
                  children: [
                    _buildLegendItem(
                      context,
                      FFTokens.brand600,
                      context.tr('owner.directMembers'),
                    ),
                    const SizedBox(width: 16),
                    _buildLegendItem(
                      context,
                      FFTokens.brand200,
                      context.tr('owner.fitflexRoaming'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Simple line chart using custom paint
                SizedBox(
                  height: 150,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: MembershipLineChartPainter(
                      directPoints: chartDirect,
                      fitflexPoints: chartFitflex,
                      labels: chartLabels,
                      isDark: Theme.of(context).brightness == Brightness.dark,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                // Insights underneath
                Row(
                  children: [
                    Expanded(
                      child: _buildChartDetail(
                        context,
                        bulletColor: FFTokens.brand600,
                        title: context.tr('owner.directMembers'),
                        value: '$directCount',
                        trendDir: membersTrendDir,
                        trendPct: membersTrendLabel,
                      ),
                    ),
                    Container(
                      height: 45,
                      width: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    Expanded(
                      child: _buildChartDetail(
                        context,
                        bulletColor: FFTokens.brand200,
                        title: context.tr('owner.fitflexRoaming'),
                        value: '$fitflexCount',
                        trendDir: visitsTrendDir,
                        trendPct: visitsTrendLabel,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAction(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 24),
            const SizedBox(height: 8),
            Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildActionDivider(BuildContext context) {
    return VerticalDivider(
      width: 1,
      thickness: 1,
      indent: 8,
      endIndent: 8,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }

  Widget _buildLegendItem(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildChartDetail(
    BuildContext context, {
    required Color bulletColor,
    required String title,
    required String value,
    FFTrendDirection? trendDir,
    String? trendPct,
  }) {
    final theme = Theme.of(context);

    // Derive badge colours from trend direction
    final Color badgeBg;
    final Color badgeFg;
    final IconData badgeIcon;
    switch (trendDir) {
      case FFTrendDirection.down:
        badgeBg = theme.colorScheme.errorContainer;
        badgeFg = theme.colorScheme.onErrorContainer;
        badgeIcon = Icons.arrow_downward;
      case FFTrendDirection.neutral:
        badgeBg = theme.colorScheme.surfaceContainerHighest;
        badgeFg = theme.colorScheme.onSurfaceVariant;
        badgeIcon = Icons.remove;
      case FFTrendDirection.up:
      case null:
        badgeBg = FFTokens.success50;
        badgeFg = FFTokens.success700;
        badgeIcon = Icons.arrow_upward;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: bulletColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
              ),
              if (trendPct != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(FFTokens.radiusFull),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badgeIcon, size: 8, color: badgeFg),
                      const SizedBox(width: 1),
                      Text(
                        trendPct,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: badgeFg,
                          fontWeight: FontWeight.bold,
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class MembershipLineChartPainter extends CustomPainter {
  MembershipLineChartPainter({
    required this.directPoints,
    required this.fitflexPoints,
    required this.labels,
    required this.isDark,
  });

  final List<double> directPoints;
  final List<double> fitflexPoints;
  final List<String> labels;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    const double paddingLeft = 32.0;
    const double paddingBottom = 20.0;
    const double paddingTop = 10.0;
    const double paddingRight = 10.0;

    final double chartWidth = size.width - paddingLeft - paddingRight;
    final double chartHeight = size.height - paddingTop - paddingBottom;

    final int n = directPoints.length;
    if (n == 0) return;

    // Dynamic Y scale: next nice number above the max data value, minimum 5
    final double dataMax = [
      ...directPoints,
      ...fitflexPoints,
    ].fold<double>(0, (a, b) => b > a ? b : a);
    final double maxVal = dataMax <= 0 ? 5 : (dataMax * 1.2).ceilToDouble();

    // Nice round step for Y-axis grid (4 or 5 lines)
    final double rawStep = maxVal / 4;
    final double step = rawStep <= 1
        ? 1
        : rawStep <= 2
        ? 2
        : rawStep <= 5
        ? 5
        : rawStep <= 10
        ? 10
        : (rawStep / 10).ceil() * 10.0;
    final double adjustedMax = (maxVal / step).ceil() * step;

    final gridPaint = Paint()
      ..color = isDark ? Colors.white10 : Colors.grey.shade200
      ..strokeWidth = 1.0;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final labelColor = isDark ? Colors.grey.shade500 : Colors.grey.shade600;

    // Horizontal grid lines + Y-axis labels
    int gridLines = (adjustedMax / step).round();
    for (int i = 0; i <= gridLines; i++) {
      final double yVal = i * step;
      final double y = paddingTop + chartHeight * (1 - yVal / adjustedMax);
      canvas.drawLine(
        Offset(paddingLeft, y),
        Offset(size.width - paddingRight, y),
        gridPaint,
      );
      textPainter.text = TextSpan(
        text: yVal.toInt().toString(),
        style: TextStyle(color: labelColor, fontSize: 9),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(paddingLeft - textPainter.width - 6, y - textPainter.height / 2),
      );
    }

    final double xStep = n > 1 ? chartWidth / (n - 1) : chartWidth;

    Offset getOffset(int index, double val) {
      final double x = paddingLeft + index * xStep;
      final double clamped = val > adjustedMax ? adjustedMax : val;
      final double y = paddingTop + chartHeight * (1 - clamped / adjustedMax);
      return Offset(x, y);
    }

    // Direct members — shaded gradient area
    final Path fillPath = Path();
    fillPath.moveTo(paddingLeft, paddingTop + chartHeight);
    for (int i = 0; i < n; i++) {
      final offset = getOffset(i, directPoints[i]);
      fillPath.lineTo(offset.dx, offset.dy);
    }
    fillPath.lineTo(paddingLeft + (n - 1) * xStep, paddingTop + chartHeight);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                FFTokens.brand500.withValues(alpha: 0.15),
                FFTokens.brand500.withValues(alpha: 0.0),
              ],
            ).createShader(
              Rect.fromLTWH(paddingLeft, paddingTop, chartWidth, chartHeight),
            ),
    );

    // Direct members — solid line
    final directLinePaint = Paint()
      ..color = FFTokens.brand600
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Path directPath = Path();
    directPath.moveTo(
      getOffset(0, directPoints[0]).dx,
      getOffset(0, directPoints[0]).dy,
    );
    for (int i = 1; i < n; i++) {
      final offset = getOffset(i, directPoints[i]);
      directPath.lineTo(offset.dx, offset.dy);
    }
    canvas.drawPath(directPath, directLinePaint);

    // Direct dots
    final dotOuterPaint = Paint()
      ..color = isDark ? const Color(0xFF0D1B2A) : Colors.white
      ..style = PaintingStyle.fill;
    final dotPaintDirect = Paint()
      ..color = FFTokens.brand600
      ..style = PaintingStyle.fill;

    for (int i = 0; i < n; i++) {
      final offset = getOffset(i, directPoints[i]);
      canvas.drawCircle(offset, 4.0, dotOuterPaint);
      canvas.drawCircle(offset, 2.5, dotPaintDirect);
    }

    // FitFlex — dashed line
    final fitflexLinePaint = Paint()
      ..color = FFTokens.brand200
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Path fitflexPath = Path();
    fitflexPath.moveTo(
      getOffset(0, fitflexPoints[0]).dx,
      getOffset(0, fitflexPoints[0]).dy,
    );
    for (int i = 1; i < n; i++) {
      final offset = getOffset(i, fitflexPoints[i]);
      fitflexPath.lineTo(offset.dx, offset.dy);
    }
    _drawDashedPath(canvas, fitflexPath, fitflexLinePaint);

    // FitFlex dots
    final dotPaintFitflex = Paint()
      ..color = FFTokens.brand200
      ..style = PaintingStyle.fill;

    for (int i = 0; i < n; i++) {
      final offset = getOffset(i, fitflexPoints[i]);
      canvas.drawCircle(offset, 4.0, dotOuterPaint);
      canvas.drawCircle(offset, 2.5, dotPaintFitflex);
    }

    // X-axis labels from API
    for (int i = 0; i < labels.length && i < n; i++) {
      final offset = getOffset(i, 0);
      textPainter.text = TextSpan(
        text: labels[i],
        style: TextStyle(color: labelColor, fontSize: 8),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(offset.dx - textPainter.width / 2, paddingTop + chartHeight + 6),
      );
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    const double dashWidth = 5.0;
    const double dashSpace = 3.0;
    final Path dashedPath = Path();

    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        dashedPath.addPath(
          metric.extractPath(distance, distance + dashWidth),
          Offset.zero,
        );
        distance += dashWidth + dashSpace;
      }
    }
    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(covariant MembershipLineChartPainter old) =>
      old.directPoints != directPoints ||
      old.fitflexPoints != fitflexPoints ||
      old.labels != labels ||
      old.isDark != isDark;
}

// ─────────────────────────── Date Filter Bottom Sheet ────────────────────────

typedef _ApplyCallback =
    Future<void> Function(_DatePreset preset, DateTime from, DateTime to);

class _DateFilterSheet extends StatefulWidget {
  const _DateFilterSheet({required this.activePreset, required this.onApply});

  final _DatePreset activePreset;
  final _ApplyCallback onApply;

  @override
  State<_DateFilterSheet> createState() => _DateFilterSheetState();
}

class _DateFilterSheetState extends State<_DateFilterSheet> {
  late _DatePreset _selected;
  DateTimeRange? _customRange;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.activePreset;
  }

  DateTimeRange _rangeForPreset(_DatePreset preset) {
    final now = DateTime.now();
    return switch (preset) {
      _DatePreset.today => DateTimeRange(
        start: DateTime(now.year, now.month, now.day),
        end: DateTime(now.year, now.month, now.day, 23, 59, 59),
      ),
      _DatePreset.yesterday => () {
        final y = now.subtract(const Duration(days: 1));
        return DateTimeRange(
          start: DateTime(y.year, y.month, y.day),
          end: DateTime(y.year, y.month, y.day, 23, 59, 59),
        );
      }(),
      _DatePreset.thisMonth => DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
      ),
      _DatePreset.thisYear => DateTimeRange(
        start: DateTime(now.year, 1, 1),
        end: DateTime(now.year, 12, 31, 23, 59, 59),
      ),
      _DatePreset.custom =>
        _customRange ??
            DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
    };
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _customRange,
    );
    if (picked != null && mounted) {
      setState(() {
        _customRange = picked;
        _selected = _DatePreset.custom;
      });
    }
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    final range = _rangeForPreset(_selected);
    await widget.onApply(_selected, range.start, range.end);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presets = [
      (
        _DatePreset.today,
        context.tr('owner.filterToday'),
        Icons.today_outlined,
      ),
      (
        _DatePreset.yesterday,
        context.tr('owner.filterYesterday'),
        Icons.history_outlined,
      ),
      (
        _DatePreset.thisMonth,
        context.tr('owner.filterThisMonth'),
        Icons.calendar_month_outlined,
      ),
      (
        _DatePreset.thisYear,
        context.tr('owner.filterThisYear'),
        Icons.calendar_today_outlined,
      ),
    ];

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(FFTokens.radiusFull),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FFTokens.spacingLg,
                vertical: FFTokens.spacingSm,
              ),
              child: Text(
                context.tr('owner.selectDateRange'),
                style: theme.textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(FFTokens.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Preset chips grid (2 × 2)
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: FFTokens.spacingSm,
                    crossAxisSpacing: FFTokens.spacingSm,
                    childAspectRatio: 3.4,
                    children: presets.map((entry) {
                      final (preset, label, icon) = entry;
                      final isActive = _selected == preset;
                      return InkWell(
                        onTap: () => setState(() => _selected = preset),
                        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                        child: AnimatedContainer(
                          duration: FFTokens.motionFast,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.12,
                                  )
                                : theme.colorScheme.surfaceContainerHighest,
                            border: Border.all(
                              color: isActive
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                              width: isActive ? 1.5 : 1,
                            ),
                            borderRadius: BorderRadius.circular(
                              FFTokens.radiusMd,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                icon,
                                size: 16,
                                color: isActive
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  label,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: isActive
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isActive
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: FFTokens.spacingSm),
                  // Custom range tile
                  InkWell(
                    onTap: _pickCustom,
                    borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                    child: AnimatedContainer(
                      duration: FFTokens.motionFast,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _selected == _DatePreset.custom
                            ? theme.colorScheme.primary.withValues(alpha: 0.12)
                            : theme.colorScheme.surfaceContainerHighest,
                        border: Border.all(
                          color: _selected == _DatePreset.custom
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: _selected == _DatePreset.custom ? 1.5 : 1,
                        ),
                        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.date_range_outlined,
                            size: 16,
                            color: _selected == _DatePreset.custom
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _customRange == null
                                  ? context.tr('owner.filterCustom')
                                  : '${_fmt(_customRange!.start)} → ${_fmt(_customRange!.end)}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: _selected == _DatePreset.custom
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _selected == _DatePreset.custom
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: FFTokens.spacingMd),
                  FilledButton(
                    onPressed: _applying ? null : _apply,
                    child: _applying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(context.tr('owner.applyFilter')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
