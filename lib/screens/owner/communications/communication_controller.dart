// Controllers for owner communications — ChangeNotifier state and use
// cases only, no widgets, so the screens stay thin and the logic is tested
// without a widget tree.

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../shared/api_client.dart';
import 'data/communication_models.dart';
import 'data/communication_repository.dart';

/// The Communication Center: overview numbers and the campaign list.
class CommunicationCenterController extends ChangeNotifier {
  CommunicationCenterController(this._repo, {this.gymId});

  final CommunicationRepository _repo;
  final String? gymId;

  CommunicationRepository get repository => _repo;

  bool _loading = false;
  Object? _error;
  CommunicationOverview? _overview;
  List<Campaign> _campaigns = const [];
  CampaignStatus? _statusFilter;

  bool get loading => _loading;
  Object? get error => _error;
  CommunicationOverview? get overview => _overview;
  List<Campaign> get campaigns => _campaigns;
  CampaignStatus? get statusFilter => _statusFilter;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _repo.overview(gymId: gymId),
        _repo.campaigns(gymId: gymId, status: _statusFilter),
      ]);
      _overview = results[0] as CommunicationOverview;
      _campaigns = results[1] as List<Campaign>;
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setStatusFilter(CampaignStatus? status) async {
    if (status == _statusFilter) return;
    _statusFilter = status;
    notifyListeners();
    try {
      _campaigns = await _repo.campaigns(gymId: gymId, status: status);
      _error = null;
    } catch (e) {
      _error = e;
    }
    notifyListeners();
  }
}

/// Days-until-expiry, days-without-a-visit and so on, added on top of a
/// preset. Each maps to one backend audience condition.
class AudienceRefinements {
  const AudienceRefinements({
    this.expiresWithinDays,
    this.noVisitForDays,
    this.plans = const {},
    this.gender,
    this.minAge,
    this.maxAge,
  });

  final int? expiresWithinDays;
  final int? noVisitForDays;
  final Set<String> plans;
  final String? gender;
  final int? minAge;
  final int? maxAge;

  bool get isEmpty =>
      expiresWithinDays == null &&
      noVisitForDays == null &&
      plans.isEmpty &&
      gender == null &&
      minAge == null &&
      maxAge == null;

  AudienceRefinements copyWith({
    int? Function()? expiresWithinDays,
    int? Function()? noVisitForDays,
    Set<String>? plans,
    String? Function()? gender,
    int? Function()? minAge,
    int? Function()? maxAge,
  }) => AudienceRefinements(
    expiresWithinDays: expiresWithinDays != null
        ? expiresWithinDays()
        : this.expiresWithinDays,
    noVisitForDays: noVisitForDays != null
        ? noVisitForDays()
        : this.noVisitForDays,
    plans: plans ?? this.plans,
    gender: gender != null ? gender() : this.gender,
    minAge: minAge != null ? minAge() : this.minAge,
    maxAge: maxAge != null ? maxAge() : this.maxAge,
  );

  /// The backend filter for these refinements, or null when there are none.
  Map<String, dynamic>? toFilter() {
    final all = <Map<String, dynamic>>[
      if (expiresWithinDays != null)
        {
          'field': 'daysUntilExpiry',
          'op': 'between',
          'value': [0, expiresWithinDays],
        },
      if (noVisitForDays != null)
        {
          'any': [
            {'field': 'lastVisitDaysAgo', 'op': 'gte', 'value': noVisitForDays},
            {
              'all': [
                {'field': 'lastVisitDaysAgo', 'op': 'exists', 'value': false},
                {
                  'field': 'joinedDaysAgo',
                  'op': 'gte',
                  'value': noVisitForDays,
                },
              ],
            },
          ],
        },
      if (plans.isNotEmpty)
        {'field': 'plan', 'op': 'in', 'value': plans.toList()..sort()},
      if (gender != null) {'field': 'gender', 'op': 'eq', 'value': gender},
      if (minAge != null && maxAge != null)
        {
          'field': 'age',
          'op': 'between',
          'value': [minAge, maxAge],
        }
      else if (minAge != null)
        {'field': 'age', 'op': 'gte', 'value': minAge}
      else if (maxAge != null)
        {'field': 'age', 'op': 'lte', 'value': maxAge},
    ];
    return all.isEmpty ? null : {'all': all};
  }

  /// Reads back a filter this app built. Anything else is kept as-is by the
  /// composer and shown as "custom conditions".
  static AudienceRefinements? fromFilter(Map<String, dynamic>? filter) {
    if (filter == null) return const AudienceRefinements();
    final all = filter['all'];
    if (filter.length != 1 || all is! List) return null;
    var r = const AudienceRefinements();
    for (final raw in all) {
      if (raw is! Map) return null;
      final c = raw.cast<String, dynamic>();
      final v = c['value'];
      switch ((c['field'], c['op'])) {
        case ('daysUntilExpiry', 'between') when v is List && v.length == 2:
          r = r.copyWith(expiresWithinDays: () => (v[1] as num).toInt());
        case ('plan', 'in') when v is List:
          r = r.copyWith(plans: v.map((e) => e.toString()).toSet());
        case ('gender', 'eq'):
          r = r.copyWith(gender: () => v?.toString());
        case ('age', 'between') when v is List && v.length == 2:
          r = r.copyWith(
            minAge: () => (v[0] as num).toInt(),
            maxAge: () => (v[1] as num).toInt(),
          );
        case ('age', 'gte'):
          r = r.copyWith(minAge: () => (v as num).toInt());
        case ('age', 'lte'):
          r = r.copyWith(maxAge: () => (v as num).toInt());
        case (null, null) when c['any'] is List:
          final first = (c['any'] as List).first;
          if (first is Map && first['field'] == 'lastVisitDaysAgo') {
            r = r.copyWith(
              noVisitForDays: () => (first['value'] as num).toInt(),
            );
          } else {
            return null;
          }
        default:
          return null;
      }
    }
    return r;
  }
}

/// The steps of the campaign flow, in order.
enum ComposerStep {
  purpose,
  audience,
  message,
  channels,
  schedule,
  preview,
  confirm,
}

/// The seven-step campaign flow: purpose → audience → message → channels →
/// schedule → preview → confirm.
class CampaignComposerController extends ChangeNotifier {
  CampaignComposerController(
    this._repo, {
    this.gymId,
    this.channelsAvailable = const ChannelAvailability(),
    Campaign? existing,
    Duration countDebounce = const Duration(milliseconds: 400),
    DateTime Function()? clock,
  }) : _countDebounce = countDebounce,
       _now = clock ?? DateTime.now {
    if (existing != null) _loadExisting(existing);
  }

  final CommunicationRepository _repo;
  final String? gymId;
  final ChannelAvailability channelsAvailable;
  final Duration _countDebounce;
  final DateTime Function() _now;

  // Made once per composer: pressing Send again (or retrying after a lost
  // connection) repeats the same request instead of sending twice.
  final String sendRequestId = _newRequestId();

  static const minScheduleLead = Duration(minutes: 5);

  // ── state ──────────────────────────────────────────────────────────────
  ComposerStep _step = ComposerStep.purpose;
  CampaignPurpose? _purpose;
  String? _preset = 'active';
  AudienceRefinements _refine = const AudienceRefinements();
  Map<String, dynamic>? _customFilter; // a filter this app can't edit
  CampaignContent _content = const CampaignContent();
  Set<CommChannel> _channels = {CommChannel.inApp};
  bool _scheduleLater = false;
  DateTime? _scheduledAt;

  String? _campaignId;
  String? _savedSnapshot;

  AudienceCount? _count;
  bool _countLoading = false;
  Object? _countError;
  Timer? _countTimer;
  int _countSeq = 0;

  CampaignPreview? _preview;
  CampaignPreview? _reach; // preview across every available channel
  bool _previewLoading = false;
  Object? _previewError;

  bool _submitting = false;
  Object? _submitError;
  bool _confirmLargeSend = false;
  bool _needsLargeSendConfirm = false;

  ComposerStep get step => _step;
  CampaignPurpose? get purpose => _purpose;
  String? get preset => _preset;
  AudienceRefinements get refinements => _refine;
  bool get hasCustomFilter => _customFilter != null;
  CampaignContent get content => _content;
  Set<CommChannel> get channels => _channels;
  bool get scheduleLater => _scheduleLater;
  DateTime? get scheduledAt => _scheduledAt;
  String? get campaignId => _campaignId;
  AudienceCount? get audienceCount => _count;
  bool get countLoading => _countLoading;
  Object? get countError => _countError;
  CampaignPreview? get preview => _preview;
  CampaignPreview? get reach => _reach;
  bool get previewLoading => _previewLoading;
  Object? get previewError => _previewError;
  bool get submitting => _submitting;
  Object? get submitError => _submitError;
  bool get confirmLargeSend => _confirmLargeSend;
  bool get needsLargeSendConfirm =>
      _needsLargeSendConfirm || (_preview?.needsLargeSendConfirm ?? false);

  CampaignAudience get audience => CampaignAudience(
    preset: _preset,
    filter: _customFilter ?? _refine.toFilter(),
  );

  /// Variables that need a value typed in once for the whole campaign.
  static const senderVariables = {'offer_name', 'discount', 'amount'};

  List<String> get missingSenderValues {
    final used = _content.variables;
    return [
      if (used.contains('offer_name') && _blank(_content.offerName))
        'offer_name',
      if (used.contains('discount') && _blank(_content.discount)) 'discount',
      if (used.contains('amount') && _content.amountTzs == null) 'amount',
    ];
  }

  List<String> get unknownVariables =>
      _content.variables.where((v) => !kMessageVariables.contains(v)).toList();

  bool canContinue(ComposerStep s) => switch (s) {
    ComposerStep.purpose => _purpose != null,
    ComposerStep.audience => (_count?.count ?? 0) > 0 && !_countLoading,
    ComposerStep.message =>
      _content.title.trim().isNotEmpty &&
          _content.body.trim().isNotEmpty &&
          _content.title.length <= 65 &&
          _content.body.length <= 1000 &&
          missingSenderValues.isEmpty &&
          unknownVariables.isEmpty,
    ComposerStep.channels => _channels.isNotEmpty,
    ComposerStep.schedule =>
      !_scheduleLater ||
          (_scheduledAt != null &&
              !_scheduledAt!.isBefore(_now().add(minScheduleLead))),
    ComposerStep.preview => _preview != null && !_preview!.nobodyReachable,
    ComposerStep.confirm =>
      !_submitting && (!needsLargeSendConfirm || _confirmLargeSend),
  };

  // ── navigation ─────────────────────────────────────────────────────────
  void next() {
    if (!canContinue(_step) || _step == ComposerStep.confirm) return;
    goTo(ComposerStep.values[_step.index + 1]);
  }

  void back() {
    if (_step.index > 0) goTo(ComposerStep.values[_step.index - 1]);
  }

  void goTo(ComposerStep s) {
    _step = s;
    notifyListeners();
    if (s == ComposerStep.audience && _count == null) refreshCount();
    if (s == ComposerStep.channels) loadReach();
    if (s == ComposerStep.preview) loadPreview();
  }

  // ── edits ──────────────────────────────────────────────────────────────
  void setPurpose(CampaignPurpose p) {
    _purpose = p;
    _invalidatePreview();
    notifyListeners();
    // Offer opt-outs change how many members a message can reach.
    if (_count != null) refreshCount();
  }

  void setPreset(String preset) {
    _preset = preset;
    _audienceChanged();
  }

  void setRefinements(AudienceRefinements r) {
    _refine = r;
    _customFilter = null;
    _audienceChanged();
  }

  void clearCustomFilter() {
    _customFilter = null;
    _audienceChanged();
  }

  void setContent(CampaignContent c) {
    _content = c;
    _invalidatePreview();
    notifyListeners();
  }

  void toggleChannel(CommChannel c, bool on) {
    if (!channelsAvailable.of(c)) return;
    _channels = {..._channels};
    on ? _channels.add(c) : _channels.remove(c);
    _invalidatePreview();
    notifyListeners();
  }

  void setScheduleLater(bool later) {
    _scheduleLater = later;
    if (later && _scheduledAt == null) {
      _scheduledAt = _now().add(const Duration(hours: 1));
    }
    notifyListeners();
  }

  void setScheduledAt(DateTime at) {
    _scheduledAt = at;
    notifyListeners();
  }

  void setConfirmLargeSend(bool v) {
    _confirmLargeSend = v;
    notifyListeners();
  }

  void _audienceChanged() {
    _invalidatePreview();
    notifyListeners();
    _countTimer?.cancel();
    _countTimer = Timer(_countDebounce, refreshCount);
  }

  void _invalidatePreview() {
    _preview = null;
    _reach = null;
  }

  // ── server calls ───────────────────────────────────────────────────────
  Future<void> refreshCount() async {
    final seq = ++_countSeq;
    _countLoading = true;
    _countError = null;
    notifyListeners();
    try {
      final r = await _repo.audienceCount(
        gymId: gymId,
        audience: audience,
        purpose: _purpose,
      );
      if (seq != _countSeq) return; // a newer request is on its way
      _count = r;
    } catch (e) {
      if (seq != _countSeq) return;
      _countError = e;
    } finally {
      if (seq == _countSeq) {
        _countLoading = false;
        notifyListeners();
      }
    }
  }

  Map<String, dynamic> draftJson({Set<CommChannel>? channels}) => {
    if (gymId != null) 'gymId': gymId,
    'name': _content.title.trim().isEmpty
        ? null
        : _content.title.trim().substring(
            0,
            min(80, _content.title.trim().length),
          ),
    'purpose': _purpose?.name,
    'audience': audience.toJson(),
    'content': _content.toJson(),
    'channels': (channels ?? _channels).map((c) => c.wire).toList(),
  }..removeWhere((k, v) => v == null);

  /// Reach on every available channel, for the channel step.
  Future<void> loadReach() async {
    final all = CommChannel.values.where(channelsAvailable.of).toSet();
    try {
      _reach = await _repo.preview(draftJson(channels: all));
    } catch (_) {
      _reach = null; // the channel step still works without numbers
    }
    notifyListeners();
  }

  Future<void> loadPreview() async {
    _previewLoading = true;
    _previewError = null;
    notifyListeners();
    try {
      _preview = await _repo.preview(draftJson());
    } catch (e) {
      _previewError = e;
    } finally {
      _previewLoading = false;
      notifyListeners();
    }
  }

  /// Saves the draft (only if it changed since the last save).
  Future<String> saveDraft() async {
    final body = draftJson();
    final snapshot = body.toString();
    if (_campaignId == null) {
      final created = await _repo.create(body);
      _campaignId = created.id;
    } else if (snapshot != _savedSnapshot) {
      body.remove('gymId');
      await _repo.update(_campaignId!, body);
    }
    _savedSnapshot = snapshot;
    return _campaignId!;
  }

  /// Saves, then sends now or schedules. Safe to call again after a failure.
  Future<Campaign?> submit() async {
    if (_submitting) return null;
    _submitting = true;
    _submitError = null;
    notifyListeners();
    try {
      final id = await saveDraft();
      final result = _scheduleLater
          ? await _repo.schedule(id, _scheduledAt!)
          : await _repo.send(
              id,
              sendRequestId: sendRequestId,
              confirmLargeSend: _confirmLargeSend,
            );
      return result;
    } on ApiException catch (e) {
      if (e.code == 'confirm_large_send') _needsLargeSendConfirm = true;
      _submitError = e;
      return null;
    } catch (e) {
      _submitError = e;
      return null;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  void _loadExisting(Campaign c) {
    _campaignId = c.id;
    _purpose = c.purpose;
    _preset = c.audience.preset;
    final parsed = AudienceRefinements.fromFilter(c.audience.filter);
    if (parsed == null) {
      _customFilter = c.audience.filter;
    } else {
      _refine = parsed;
    }
    _content = c.content;
    if (c.channels.isNotEmpty) _channels = c.channels.toSet();
    if (c.scheduledAt != null) {
      _scheduleLater = true;
      _scheduledAt = c.scheduledAt;
    }
    _savedSnapshot = draftJson().toString();
  }

  @override
  void dispose() {
    _countTimer?.cancel();
    super.dispose();
  }

  static bool _blank(String? s) => s == null || s.trim().isEmpty;

  static String _newRequestId() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
