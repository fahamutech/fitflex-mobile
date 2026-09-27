import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import '../../shared/widgets/reviews_section.dart';

/// Trainer: what members say about their sessions. Read-only.
class TrainerReviewsPage extends StatefulWidget {
  const TrainerReviewsPage({super.key});

  @override
  State<TrainerReviewsPage> createState() => _TrainerReviewsPageState();
}

class _TrainerReviewsPageState extends State<TrainerReviewsPage> {
  ({ReviewSummary summary, List<Review> reviews})? _data;
  bool _failed = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final data = await AppScope.of(context).api.myTrainerReviews();
      if (mounted) setState(() => _data = data);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('reviews.myReviews'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [
            if (_failed) ...[
              FFAlert(
                message: context.tr('reviews.loadFailed'),
                tone: FFAlertTone.error,
              ),
              TextButton(
                key: const Key('trainer-reviews-retry'),
                onPressed: _load,
                child: Text(context.tr('reviews.retry')),
              ),
            ] else if (data == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: FFSpinner(size: 28)),
              )
            else if (data.summary.count == 0)
              FFEmptyState(
                key: const Key('trainer-reviews-empty'),
                title: context.tr('reviews.none'),
                body: context.tr('reviews.trainerNone'),
              )
            else ...[
              ReviewSummaryCard(summary: data.summary),
              const SizedBox(height: 8),
              ...data.reviews.map((r) => ReviewTile(review: r)),
            ],
          ],
        ),
      ),
    );
  }
}
