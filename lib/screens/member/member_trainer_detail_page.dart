import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import '../../shared/api_error_message.dart';
import '../../shared/widgets/availability_calendar.dart';
import '../../shared/widgets/enquiry_thread.dart';
import '../../shared/widgets/social_links.dart';
import 'member_shell.dart';
import 'widgets/trainer_actions_sheet.dart';
import 'widgets/trainer_sharing.dart';

class MemberTrainerDetailPage extends StatefulWidget {
  const MemberTrainerDetailPage({super.key, required this.trainerId});

  final String trainerId;

  @override
  State<MemberTrainerDetailPage> createState() =>
      _MemberTrainerDetailPageState();
}

class _MemberTrainerDetailPageState extends State<MemberTrainerDetailPage> {
  static const _maxSlots = 12;

  bool _interestBusy = false;
  bool _started = false;

  // Live calendar (GET /trainers/:id/schedule).
  List<ScheduleDay>? _days;
  bool _scheduleFailed = false;
  String? _gymFilter;
  final Map<String, ({String date, String slot})> _picked = {};
  String? _pickedGymId;

  // The member's latest conversation with this trainer, if any.
  Map<String, dynamic>? _conversation;

  String get trainerId => widget.trainerId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _loadSchedule();
    _loadConversation();
  }

  Future<void> _loadConversation() async {
    try {
      final rows = await AppScope.of(context).api.myTrainerEngagements();
      final mine = rows
          .whereType<Map<String, dynamic>>()
          .where(
            (e) =>
                e['trainerId'] == trainerId &&
                EnquiryMessage.listFrom(e).isNotEmpty,
          )
          .firstOrNull; // newest activity first
      if (!mounted) return;
      setState(() => _conversation = mine);
      if (mine != null && mine['unread'] == true) {
        final read = await AppScope.of(
          context,
        ).api.memberReadEngagement(mine['id'].toString());
        if (mounted) setState(() => _conversation = read);
      }
    } catch (_) {
      // The page works without it; the conversation just isn't shown.
    }
  }

  Future<bool> _followUp(String text) async {
    final id = _conversation?['id']?.toString();
    if (id == null) return false;
    try {
      final updated = await AppScope.of(
        context,
      ).api.memberReplyEngagement(id, text);
      if (mounted) setState(() => _conversation = updated);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage(FFLocaleScope.of(context), e))),
        );
      }
      return false;
    }
  }

  Future<void> _loadSchedule() async {
    try {
      final res = await AppScope.of(
        context,
      ).api.trainerSchedule(trainerId, days: 21, gymId: _gymFilter);
      if (!mounted) return;
      setState(() {
        _days = ScheduleDay.listFromResponse(res);
        _scheduleFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _scheduleFailed = true);
    }
  }

  void _setGymFilter(String? gymId) {
    setState(() {
      _gymFilter = gymId;
      _days = null;
      _picked.clear();
      _pickedGymId = null;
    });
    _loadSchedule();
  }

  /// The gym a picked slot is booked at: the filter, the slot's own gym, or
  /// the trainer's first gym.
  String? _gymForSlot(TrainerProfile trainer, ScheduleSlot slot) =>
      _gymFilter ??
      slot.gymIds.firstOrNull ??
      trainer.gymIds.firstOrNull ??
      trainer.gyms.firstOrNull?.id;

  void _toggleSlot(TrainerProfile trainer, ScheduleDay day, ScheduleSlot slot) {
    final gymId = _gymForSlot(trainer, slot);
    if (gymId == null) return;
    final key = scheduleSlotKey(day.date, slot.slot);
    setState(() {
      // One booking is at one gym: a slot elsewhere starts a new selection.
      if (_pickedGymId != null && _pickedGymId != gymId) _picked.clear();
      _pickedGymId = gymId;
      if (_picked.remove(key) == null) {
        if (_picked.length >= _maxSlots) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('member.tooManySlots'))),
          );
          return;
        }
        _picked[key] = (date: day.date, slot: slot.slot);
      }
      if (_picked.isEmpty) _pickedGymId = null;
    });
  }

  Future<void> _book() async {
    final data = MemberDataScope.of(context);
    final trainer = data.trainers.where((t) => t.id == trainerId).firstOrNull;
    if (trainer == null) return;
    final slots = _picked.values.toList()
      ..sort((a, b) => '${a.date} ${a.slot}'.compareTo('${b.date} ${b.slot}'));
    final booked = await showTrainerBookingSheet(
      context,
      trainer,
      slots: slots,
      gymId: _pickedGymId,
    );
    if (booked == true && mounted) {
      setState(() {
        _picked.clear();
        _pickedGymId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('member.bookingRequested'))),
      );
      _loadSchedule();
    }
  }

  Future<void> _enquire() async {
    final data = MemberDataScope.of(context);
    final trainer = data.trainers.where((t) => t.id == trainerId).firstOrNull;
    if (trainer == null) return;
    final sent = await showTrainerEnquiryDialog(context, trainer);
    if (sent == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('member.enquirySent'))));
      _loadConversation();
    }
  }

  Future<void> _showInterest() async {
    setState(() => _interestBusy = true);
    try {
      await AppScope.of(context).api.engageTrainer(trainerId, type: 'interest');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('member.interestSent'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('member.enquiryFailed'))),
      );
    } finally {
      if (mounted) setState(() => _interestBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final trainer = data.trainers.where((t) => t.id == trainerId).firstOrNull;

    if (trainer == null) {
      return Center(child: FFEmptyState(title: context.tr('member.noData')));
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('trainer-detail-back'),
          onPressed: () => context.go(AppRoutes.memberTrainers),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('member.findTrainerTitle')),
      ),
      // A4 — pinned action bar: Book / Enquire / Show interest.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingMd),
          child: Row(
            key: const Key('trainer-actions'),
            children: [
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  key: const Key('trainer-action-book'),
                  onPressed: _book,
                  icon: const Icon(Icons.event_available, size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _picked.isEmpty
                          ? context.tr('member.bookSession')
                          : context
                                .tr('member.bookSlots')
                                .replaceAll('{n}', '${_picked.length}'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const Key('trainer-action-enquire'),
                  onPressed: _enquire,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(context.tr('member.enquire')),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('trainer-action-interest'),
                  onPressed: _interestBusy ? null : _showInterest,
                  icon: const Icon(Icons.favorite_border, size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(context.tr('member.showInterest')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          // Trainer header
          Row(
            children: [
              FFAvatar(
                name: trainer.displayName,
                src: trainer.photoUrl,
                size: FFAvatarSize.lg,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            trainer.displayName,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (trainer.isVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.verified,
                            size: 20,
                            color: FFTokens.success600,
                          ),
                        ],
                      ],
                    ),
                    if (trainer.specialties.isNotEmpty)
                      Text(
                        trainer.specialties.join(' / '),
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (!trainer.socialLinks.isEmpty) ...[
            const SizedBox(height: 12),
            SocialLinksRow(links: trainer.socialLinks),
          ],
          const SizedBox(height: 12),
          // A5 — standardized profile facts: rate, experience, rating.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              FFBadge(
                label:
                    '${trainer.sessionRateCurrency} ${trainer.hourlyRateTzs}${context.tr('trainerReg.perSession')}',
                tone: FFBadgeTone.brand,
              ),
              if ((trainer.experienceYears ?? 0) > 0)
                FFBadge(
                  label:
                      '${trainer.experienceYears} ${context.tr('member.yearsExp')}',
                  tone: FFBadgeTone.gray,
                ),
              if ((trainer.rating ?? 0) > 0)
                FFBadge(
                  label: '★ ${trainer.rating}',
                  tone: FFBadgeTone.success,
                ),
            ],
          ),

          // The member's conversation with the trainer (enquiry + replies).
          if (_conversation != null) ...[
            FFSectionTitle(
              context
                  .tr('enquiry.conversationWith')
                  .replaceAll('{name}', trainer.displayName),
              key: const Key('trainer-conversation'),
            ),
            FFCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EnquiryThread(
                    messages: EnquiryMessage.listFrom(_conversation),
                    me: 'member',
                  ),
                  if (_conversation!['lastMessageFrom'] == 'member')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        context.tr('enquiry.waitingForTrainer'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  EnquiryReplyBox(
                    onSend: _followUp,
                    hintKey: 'enquiry.followUpHint',
                  ),
                ],
              ),
            ),
          ],

          // Connect for a trainer plan — the member chooses what's shared.
          TrainerConnectCard(
            trainerId: trainer.id,
            trainerName: trainer.displayName,
          ),

          // About
          FFSectionTitle(context.tr('member.about')),
          FFCard(
            child: Text(
              trainer.bio ?? '',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
                height: 1.4,
              ),
            ),
          ),

          // Gyms
          FFSectionTitle(context.tr('member.availableGyms')),
          if (trainer.gyms.isEmpty)
            FFEmptyState(title: context.tr('member.noData'))
          else
            ...trainer.gyms.map(
              (g) => FFActionTile(
                icon: Icons.fitness_center,
                title: g.name,
                subtitle: g.location,
                onTap: () => context.go('/member/gyms/${g.id}'),
              ),
            ),

          // Live calendar: booked slots show as taken; pick, then Book.
          FFSectionTitle(context.tr('member.availability')),
          if (trainer.gyms.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    key: const Key('trainer-schedule-gym-all'),
                    label: Text(context.tr('trainerPass.filterAll')),
                    selected: _gymFilter == null,
                    onSelected: (_) => _setGymFilter(null),
                  ),
                  ...trainer.gyms.map(
                    (g) => ChoiceChip(
                      key: Key('trainer-schedule-gym-${g.id}'),
                      label: Text(g.name),
                      selected: _gymFilter == g.id,
                      onSelected: (_) => _setGymFilter(g.id),
                    ),
                  ),
                ],
              ),
            ),
          if (_scheduleFailed)
            FFAlert(
              message: context.tr('cal.loadFailed'),
              tone: FFAlertTone.error,
            )
          else if (_days == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: FFSpinner(size: 28)),
            )
          else
            AvailabilityCalendar(
              days: _days!,
              selected: _picked.keys.toSet(),
              onSlotTap: (day, slot) => _toggleSlot(trainer, day, slot),
            ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
