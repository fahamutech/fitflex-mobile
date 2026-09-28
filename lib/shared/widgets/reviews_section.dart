import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../api_error_message.dart';
import '../components/components.dart';
import '../design_tokens.dart';
import '../i18n.dart';
import '../models.dart';

const _minText = 3;
const _maxText = 1000;

/// Reviews for a gym or trainer: the rating summary, the member's own review
/// (write, edit, delete) when [canWrite], and the published reviews.
class ReviewsSection extends StatefulWidget {
  const ReviewsSection({
    super.key,
    required this.subject,
    required this.subjectId,
    this.canWrite = true,
    this.onRatingChanged,
  });

  final ReviewSubject subject;
  final String subjectId;

  /// Members may review; other roles only read.
  final bool canWrite;

  /// Called with the new average and count after the member posts, edits or
  /// deletes their review, so cached gym/trainer lists stay current.
  final void Function(num average, int count)? onRatingChanged;

  @override
  State<ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<ReviewsSection> {
  ReviewSummary? _summary;
  List<Review> _reviews = const [];
  MyReviewState? _mine;
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
    final api = AppScope.of(context).api;
    setState(() => _failed = false);
    try {
      final results = await Future.wait([
        api.reviewSummary(widget.subject, widget.subjectId),
        api.reviews(widget.subject, widget.subjectId),
      ]);
      MyReviewState? mine;
      if (widget.canWrite) {
        // Reading still works if eligibility can't be checked; the member
        // just doesn't get the write button this time.
        try {
          mine = await api.myReviewState(widget.subject, widget.subjectId);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _summary = results[0] as ReviewSummary;
        _reviews = results[1] as List<Review>;
        _mine = mine;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _write() async {
    final mine = _mine;
    final result = await showReviewSheet(
      context,
      subject: widget.subject,
      subjectId: widget.subjectId,
      initialRating: mine?.rating,
      initialText: mine?.text,
    );
    if (result == null || !mounted) return;
    widget.onRatingChanged?.call(result.average, result.count);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.tr('reviews.posted'))));
    _load();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('reviews.deleteConfirmTitle')),
        content: Text(ctx.tr('reviews.deleteConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('reviews.cancel')),
          ),
          FilledButton(
            key: const Key('review-delete-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('reviews.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final locale = FFLocaleScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await AppScope.of(
        context,
      ).api.deleteMyReview(widget.subject, widget.subjectId);
      widget.onRatingChanged?.call(result.average, result.count);
      messenger.showSnackBar(
        SnackBar(content: Text(locale.t('reviews.deleted'))),
      );
      if (mounted) _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(locale, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return FFAlert(
        key: const Key('reviews-failed'),
        message: context.tr('reviews.loadFailed'),
        tone: FFAlertTone.error,
      );
    }
    final summary = _summary;
    if (summary == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: FFSpinner(size: 28)),
      );
    }
    final mine = _mine;
    return Column(
      key: const Key('reviews-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReviewSummaryCard(summary: summary),
        if (widget.canWrite && mine != null) ...[
          const SizedBox(height: 12),
          if (mine.hasReview)
            _MyReviewCard(mine: mine, onEdit: _write, onDelete: _delete)
          else if (mine.eligible)
            FilledButton.icon(
              key: const Key('review-write'),
              onPressed: _write,
              icon: const Icon(Icons.rate_review_outlined, size: 18),
              label: Text(context.tr('reviews.write')),
            )
          else
            Text(
              context.tr(
                widget.subject == ReviewSubject.gym
                    ? 'reviews.gymHint'
                    : 'reviews.trainerHint',
              ),
              key: const Key('review-not-eligible'),
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
        ],
        const SizedBox(height: 8),
        ..._reviews.map((r) => ReviewTile(review: r)),
      ],
    );
  }
}

/// Average, star row, count and a 5→1 star distribution.
class ReviewSummaryCard extends StatelessWidget {
  const ReviewSummaryCard({super.key, required this.summary});

  final ReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final average = summary.average;
    if (summary.count == 0 || average == null) {
      return Text(
        context.tr('reviews.none'),
        key: const Key('reviews-empty'),
        style: TextStyle(color: muted),
      );
    }
    return FFCard(
      key: const Key('reviews-summary'),
      child: Row(
        children: [
          Column(
            children: [
              Text(
                average.toStringAsFixed(1),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              StarRating(value: average, size: 16),
              const SizedBox(height: 4),
              Text(
                reviewCountLabel(context, summary.count),
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                for (var star = 5; star >= 1; star--)
                  _DistributionBar(
                    star: star,
                    share: (summary.distribution[star] ?? 0) / summary.count,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DistributionBar extends StatelessWidget {
  const _DistributionBar({required this.star, required this.share});

  final int star;
  final double share;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: 12,
          child: Text('$star', style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 6,
              color: FFTokens.warning500,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
      ],
    ),
  );
}

class _MyReviewCard extends StatelessWidget {
  const _MyReviewCard({
    required this.mine,
    required this.onEdit,
    required this.onDelete,
  });

  final MyReviewState mine;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => FFCard(
    key: const Key('review-mine'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              context.tr('reviews.yours'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            StarRating(value: (mine.rating ?? 0).toDouble(), size: 16),
          ],
        ),
        if ((mine.text ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(mine.text!),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              key: const Key('review-edit'),
              onPressed: onEdit,
              child: Text(context.tr('reviews.edit')),
            ),
            TextButton(
              key: const Key('review-delete'),
              onPressed: onDelete,
              child: Text(context.tr('reviews.delete')),
            ),
          ],
        ),
      ],
    ),
  );
}

/// One published review.
class ReviewTile extends StatelessWidget {
  const ReviewTile({super.key, required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final at = review.createdAt;
    return Padding(
      key: Key('review-${review.id}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FFAvatar(
            name: review.memberName,
            src: review.memberPhotoUrl,
            size: FFAvatarSize.sm,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        review.memberName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StarRating(value: review.rating.toDouble(), size: 14),
                    if (at != null) ...[
                      const Spacer(),
                      Text(
                        DateFormat('d MMM yyyy').format(at.toLocal()),
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ],
                ),
                if ((review.text ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(review.text!, style: const TextStyle(height: 1.35)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Five stars, filled to [value] in half-star steps.
class StarRating extends StatelessWidget {
  const StarRating({super.key, required this.value, this.size = 18});

  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final halves = (value * 2).round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            halves >= i * 2
                ? Icons.star
                : halves == i * 2 - 1
                ? Icons.star_half
                : Icons.star_border,
            size: size,
            color: FFTokens.warning500,
          ),
      ],
    );
  }
}

/// "1 review" / "12 reviews".
String reviewCountLabel(BuildContext context, int count) => count == 1
    ? context.tr('reviews.countOne')
    : context.tr('reviews.count').replaceAll('{n}', '$count');

/// Opens the rating sheet. Returns the subject's new average and count once
/// the review is saved, or null if the member backs out.
Future<({num average, int count})?> showReviewSheet(
  BuildContext context, {
  required ReviewSubject subject,
  required String subjectId,
  int? initialRating,
  String? initialText,
}) => showModalBottomSheet<({num average, int count})>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => ReviewSheet(
    subject: subject,
    subjectId: subjectId,
    initialRating: initialRating,
    initialText: initialText,
  ),
);

class ReviewSheet extends StatefulWidget {
  const ReviewSheet({
    super.key,
    required this.subject,
    required this.subjectId,
    this.initialRating,
    this.initialText,
  });

  final ReviewSubject subject;
  final String subjectId;
  final int? initialRating;
  final String? initialText;

  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<ReviewSheet> {
  late int _rating = widget.initialRating ?? 0;
  late final _text = TextEditingController(text: widget.initialText ?? '');
  String? _textError;
  String? _submitError;
  bool _busy = false;

  bool get _editing => widget.initialRating != null;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _text.text.trim();
    final textError = text.isNotEmpty && text.length < _minText
        ? 'reviews.textTooShort'
        : text.length > _maxText
        ? 'reviews.textTooLong'
        : null;
    setState(() {
      _textError = textError == null ? null : context.tr(textError);
      _submitError = null;
    });
    if (textError != null || _rating == 0) return;
    final locale = FFLocaleScope.of(context);
    setState(() => _busy = true);
    try {
      final result = await AppScope.of(context).api.submitReview(
        widget.subject,
        widget.subjectId,
        rating: _rating,
        text: text,
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) setState(() => _submitError = errorMessage(locale, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      FFTokens.spacingLg,
      0,
      FFTokens.spacingLg,
      MediaQuery.of(context).viewInsets.bottom + FFTokens.spacingLg,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(
            widget.subject == ReviewSubject.gym
                ? 'reviews.sheetTitleGym'
                : 'reviews.sheetTitleTrainer',
          ),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var star = 1; star <= 5; star++)
              IconButton(
                key: Key('review-star-$star'),
                iconSize: 36,
                tooltip: '$star',
                onPressed: _busy ? null : () => setState(() => _rating = star),
                icon: Icon(
                  star <= _rating ? Icons.star : Icons.star_border,
                  color: FFTokens.warning500,
                ),
              ),
          ],
        ),
        if (_rating == 0)
          Text(
            context.tr('reviews.pickRating'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        const SizedBox(height: 12),
        FFTextField(
          key: const Key('review-text'),
          controller: _text,
          hint: context.tr('reviews.textHint'),
          errorText: _textError,
          maxLines: 4,
          enabled: !_busy,
        ),
        if (_submitError != null) ...[
          const SizedBox(height: 8),
          FFAlert(message: _submitError!, tone: FFAlertTone.error),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('review-submit'),
          onPressed: _rating == 0 || _busy ? null : _submit,
          child: _busy
              ? const FFSpinner(size: 18)
              : Text(
                  context.tr(_editing ? 'reviews.update' : 'reviews.submit'),
                ),
        ),
      ],
    ),
  );
}
