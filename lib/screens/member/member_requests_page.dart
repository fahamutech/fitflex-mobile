// Requests from organisations (fitflex-functions#241): an organisation or a
// company's HR that names someone only by their FitFlex account id no longer
// adds them. The person sees the request here and accepts or declines it.
// Until they accept nothing changes: no enrolment, no staff link, no portal
// role, and no organisation sees their activity (privacy ruling A-02).
//
// Each request says who is asking, what for, what the organisation will see
// once accepted (the server's wording, in the app language), what the person
// would get, and until when they can answer. Accepting asks once more,
// restating what will be shared.
//
// An older backend without the endpoint answers 404: the screen then shows
// "no requests" rather than an error.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart' show AppRoutes;
import '../../shared/api_client.dart';
import '../../shared/api_error_message.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';

/// The items of a `/b2b/me/member-requests` or `/b2b/me/benefits` answer
/// (`items` or `memberRequests`), only those still waiting for an answer.
List<Map<String, dynamic>> pendingMemberRequests(Object? list) =>
    ((list is List) ? list : const [])
        .whereType<Map>()
        .map((r) => r.cast<String, dynamic>())
        .where((r) => (r['status'] ?? 'pending') == 'pending')
        .toList();

/// The translation key for a failed accept or decline, or null when the
/// shared error copy should be used.
String? memberRequestErrorKey(Object error) {
  if (error is! ApiException) return null;
  return switch (error.code) {
    'member_request_expired' => 'memberRequests.error.expired',
    'member_request_not_pending' => 'memberRequests.error.notPending',
    'member_request_not_found' => 'memberRequests.error.gone',
    'request_no_longer_valid' ||
    'employee_not_found' ||
    'employee_exited' ||
    'organization_not_found' ||
    'managed_by_corporate' => 'memberRequests.error.noLongerValid',
    'already_enrolled' ||
    'already_organization_user' ||
    'user_already_linked' ||
    'employee_already_linked' => 'memberRequests.error.alreadyLinked',
    _ =>
      error.status == 404
          ? 'memberRequests.error.gone'
          : error.status == 410
          ? 'memberRequests.error.expired'
          : null,
  };
}

/// The words for one of the server's visibility keys (`gym_visits`,
/// `email`…), or null for a key this app version doesn't know.
String? _itemLabel(FFLocale locale, String key) {
  final k = 'memberRequests.item.$key';
  final text = locale.t(k);
  return text == k ? null : text;
}

String _orgName(Map<String, dynamic> item) =>
    '${(item['organization'] as Map?)?['name'] ?? ''}';

class MemberRequestsPage extends StatefulWidget {
  const MemberRequestsPage({super.key});

  @override
  State<MemberRequestsPage> createState() => _MemberRequestsPageState();
}

class _MemberRequestsPageState extends State<MemberRequestsPage> {
  List<Map<String, dynamic>>? _items;
  Object? _error;
  String? _busy;
  bool _acceptedAny = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await AppScope.of(context).api.myMemberRequests();
      if (!mounted) return;
      setState(() {
        _items = pendingMemberRequests(res['items']);
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // A backend from before member requests: nothing to answer.
      if (e.status == 404) {
        setState(() {
          _items = const [];
          _error = null;
        });
      } else {
        setState(() => _error = e);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _errorText(FFLocale locale, Object e) {
    final key = memberRequestErrorKey(e);
    return key == null ? errorMessage(locale, e) : locale.t(key);
  }

  Future<void> _accept(Map<String, dynamic> item) async {
    final locale = FFLocaleScope.of(context);
    final ok = await _confirmAccept(context, item);
    if (!ok || !mounted) return;
    await _answer(
      item,
      call: (api, id) => api.acceptMemberRequest(id),
      done: locale
          .t('memberRequests.accepted')
          .replaceAll('{org}', _orgName(item)),
      accepted: true,
    );
  }

  Future<void> _decline(Map<String, dynamic> item) async {
    final locale = FFLocaleScope.of(context);
    await _answer(
      item,
      call: (api, id) => api.declineMemberRequest(id),
      done: locale
          .t('memberRequests.declined')
          .replaceAll('{org}', _orgName(item)),
    );
  }

  Future<void> _answer(
    Map<String, dynamic> item, {
    required Future<Object?> Function(ApiClient api, String id) call,
    required String done,
    bool accepted = false,
  }) async {
    final api = AppScope.of(context).api;
    final messenger = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    final id = '${item['id']}';
    setState(() => _busy = id);
    try {
      await call(api, id);
      if (accepted) _acceptedAny = true;
      messenger.success(done);
    } catch (e) {
      messenger.error(_errorText(locale, e));
    } finally {
      // Answered, expired or withdrawn: the list shows what is left.
      await _load();
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Back to Benefits: the page below when there is one, else open it.
  void _openBenefits() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop(true);
    } else {
      GoRouter.maybeOf(context)?.go(AppRoutes.memberBenefits);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('memberRequests.title'))),
      body: items == null
          ? (_error == null
                ? const Center(child: FFSpinner())
                : FFEmptyState(
                    title: context.tr('memberRequests.loadFailed'),
                    body: errorMessage(FFLocaleScope.of(context), _error!),
                    action: FFButton(
                      key: const Key('member-requests-retry'),
                      label: context.tr('comms.retry'),
                      onPressed: _load,
                    ),
                  ))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                key: const Key('member-requests-list'),
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: items.isEmpty
                    ? [
                        FFEmptyState(
                          key: const Key('member-requests-empty'),
                          title: context.tr('memberRequests.empty.title'),
                          body: context.tr('memberRequests.empty.body'),
                          action: _acceptedAny
                              ? FFButton(
                                  key: const Key('member-requests-benefits'),
                                  label: context.tr(
                                    'memberRequests.backToBenefits',
                                  ),
                                  onPressed: _openBenefits,
                                  maxLines: 2,
                                )
                              : null,
                        ),
                      ]
                    : [
                        Text(
                          context.tr('memberRequests.intro'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: FFTokens.spacingMd),
                        for (final item in items) ...[
                          _RequestCard(
                            item: item,
                            busy: _busy == '${item['id']}',
                            disabled: _busy != null,
                            onAccept: () => _accept(item),
                            onDecline: () => _decline(item),
                          ),
                          const SizedBox(height: FFTokens.spacingMd),
                        ],
                      ],
              ),
            ),
    );
  }
}

/// What the organisation will see, in the app language: the server's
/// sentence (A-02), else lines built from its shown / not-shown keys.
String visibilityText(FFLocale locale, Map<String, dynamic> item) {
  final v = (item['visibility'] as Map?)?.cast<String, dynamic>() ?? const {};
  final lang = locale.locale.languageCode == 'sw' ? 'sw' : 'en';
  final own = '${v[lang] ?? ''}'.trim();
  if (own.isNotEmpty) return own;
  final lists = visibilityLists(locale, item);
  if (lists != null) return lists;
  final other = '${v[lang == 'sw' ? 'en' : 'sw'] ?? ''}'.trim();
  if (other.isNotEmpty) return other;
  return locale
      .t('memberRequests.seesUnknown')
      .replaceAll('{org}', _orgName(item));
}

/// "Will see: … / Won't see: …" from the server's keys, or null when there
/// are none or one is a key this app version can't put into words (then
/// the server's own sentence is used instead).
String? visibilityLists(FFLocale locale, Map<String, dynamic> item) {
  final v = (item['visibility'] as Map?)?.cast<String, dynamic>() ?? const {};
  List<String>? words(Object? keys) {
    final out = <String>[];
    for (final k in (keys is List) ? keys : const []) {
      final w = _itemLabel(locale, '$k');
      if (w == null) return null;
      out.add(w);
    }
    return out;
  }

  final shown = words(v['shown']);
  final hidden = words(v['notShown']);
  if (shown == null || hidden == null || shown.isEmpty) return null;
  return [
    locale.t('memberRequests.willSee').replaceAll('{items}', shown.join(', ')),
    if (hidden.isNotEmpty)
      locale
          .t('memberRequests.wontSee')
          .replaceAll('{items}', hidden.join(', ')),
  ].join('\n');
}

/// Asks once more before sharing, restating what the organisation will see.
Future<bool> _confirmAccept(
  BuildContext context,
  Map<String, dynamic> item,
) async {
  final locale = FFLocaleScope.of(context);
  final sentence = visibilityText(locale, item);
  final lists = visibilityLists(locale, item);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('member-request-confirm-dialog'),
      scrollable: true,
      title: Text(
        ctx
            .tr('memberRequests.confirm.title')
            .replaceAll('{org}', _orgName(item)),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sentence),
          if (lists != null && lists != sentence) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Text(lists, style: Theme.of(ctx).textTheme.bodySmall),
          ],
        ],
      ),
      actions: [
        FFButton(
          key: const Key('member-request-confirm-cancel'),
          label: ctx.tr('common.cancel'),
          variant: FFButtonVariant.ghost,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
        FFButton(
          key: const Key('member-request-confirm'),
          label: ctx.tr('memberRequests.confirm.action'),
          onPressed: () => Navigator.of(ctx).pop(true),
          maxLines: 2,
        ),
      ],
    ),
  );
  return result ?? false;
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.item,
    required this.busy,
    required this.disabled,
    required this.onAccept,
    required this.onDecline,
  });

  final Map<String, dynamic> item;
  final bool busy;
  final bool disabled;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = FFLocaleScope.of(context);
    final lang = locale.locale.languageCode;
    final id = '${item['id']}';
    final kind = '${item['kind']}';
    final org = _orgName(item);
    final group = '${item['groupName'] ?? ''}'.trim();
    final benefits =
        ((item['benefits'] is List) ? item['benefits'] as List : [])
            .whereType<Map>()
            .map((b) => b.cast<String, dynamic>())
            .toList();
    final sponsor = (item['sponsor'] as Map?)?.cast<String, dynamic>();
    final expires = item['expiresAt'];

    return FFCard(
      key: Key('member-request-$id'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(org, style: theme.textTheme.titleMedium),
          const SizedBox(height: FFTokens.spacingXs),
          Text(_ask(context, kind), style: theme.textTheme.bodyMedium),
          if (kind == 'beneficiary' && group.isNotEmpty)
            Text(
              context.tr('memberRequests.group').replaceAll('{group}', group),
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: FFTokens.spacingMd),
          Text(
            context.tr('memberRequests.sees').replaceAll('{org}', org),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Text(
            visibilityText(locale, item),
            key: Key('member-request-visibility-$id'),
            style: theme.textTheme.bodySmall,
          ),
          if (kind != 'org_user') ...[
            const SizedBox(height: FFTokens.spacingMd),
            Text(
              context.tr('memberRequests.gets'),
              style: theme.textTheme.titleSmall,
            ),
            if (sponsor != null) ..._sponsor(context, sponsor),
            if (benefits.isEmpty && sponsor == null)
              Text(
                context.tr('memberRequests.noBenefits'),
                style: theme.textTheme.bodySmall,
              ),
            for (final b in benefits) _BenefitLine(row: b, lang: lang),
          ],
          if (expires != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Text(
              context
                  .tr('memberRequests.expires')
                  .replaceAll('{date}', formatDate(expires, locale: lang)),
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: FFTokens.spacingMd),
          Row(
            children: [
              Expanded(
                child: FFButton(
                  key: Key('member-request-decline-$id'),
                  label: context.tr('memberRequests.decline'),
                  variant: FFButtonVariant.secondary,
                  onPressed: disabled ? null : onDecline,
                  fullWidth: true,
                  maxLines: 2,
                ),
              ),
              const SizedBox(width: FFTokens.spacingSm),
              Expanded(
                child: FFButton(
                  key: Key('member-request-accept-$id'),
                  label: context.tr('memberRequests.accept'),
                  onPressed: disabled ? null : onAccept,
                  loading: busy,
                  fullWidth: true,
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _ask(BuildContext context, String kind) {
    final key = 'memberRequests.ask.$kind';
    final text = context.tr(key);
    if (text == key) return context.tr('memberRequests.ask.beneficiary');
    final role = '${item['role'] ?? ''}';
    final roleKey = 'memberRequests.role.$role';
    final roleText = context.tr(roleKey);
    return text.replaceAll('{role}', roleText == roleKey ? role : roleText);
  }

  /// A company staff link: the company's pass and how it is paid for.
  List<Widget> _sponsor(BuildContext context, Map<String, dynamic> s) {
    final style = Theme.of(context).textTheme.bodySmall;
    String? label(String prefix, Object? v) {
      final value = v?.toString() ?? '';
      if (value.isEmpty) return null;
      final k = '$prefix$value';
      final t = context.tr(k);
      return t == k ? null : t;
    }

    final tierText = label('tier.', s['passTier']);
    final modelText = label('memberRequests.subsidy.', s['subsidyModel']);
    return [
      if (tierText != null)
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingXs),
          child: Text(
            context
                .tr('memberRequests.sponsorTier')
                .replaceAll('{tier}', tierText),
            style: style,
          ),
        ),
      if (modelText != null) Text(modelText, style: style),
    ];
  }
}

/// One benefit the person would get: name, programme and type, how much,
/// and who pays.
class _BenefitLine extends StatelessWidget {
  const _BenefitLine({required this.row, required this.lang});

  final Map<String, dynamic> row;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final program =
        (row['program'] as Map?)?.cast<String, dynamic>() ?? const {};
    final b = (row['benefit'] as Map?)?.cast<String, dynamic>() ?? const {};
    final typeKey = 'benefits.type.${b['benefitType']}';
    final typeText = context.tr(typeKey);
    final limit = b['usageLimit'] as num?;
    final periodKey = 'benefits.period.${b['usagePeriod']}';
    final period = context.tr(periodKey);
    final tierKey = 'tier.${b['passTier']}';
    final tier = b['passTier'] == null ? null : context.tr(tierKey);
    final details = [
      if ('${program['name'] ?? ''}'.isNotEmpty) '${program['name']}',
      if (typeText != typeKey) typeText,
    ].join(' · ');

    return Padding(
      key: Key('member-request-benefit-${b['id']}'),
      padding: const EdgeInsets.only(top: FFTokens.spacingXs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${b['name'] ?? ''}', style: theme.textTheme.bodyMedium),
          if (details.isNotEmpty)
            Text(details, style: theme.textTheme.bodySmall),
          if (limit != null)
            Text(
              context
                  .tr('memberRequests.upTo')
                  .replaceAll('{limit}', '$limit')
                  .replaceAll('{period}', period == periodKey ? '' : period)
                  .trim(),
              style: theme.textTheme.bodySmall,
            ),
          if (tier != null && tier != tierKey)
            Text(
              context
                  .tr('memberRequests.sponsorTier')
                  .replaceAll('{tier}', tier),
              style: theme.textTheme.bodySmall,
            ),
          Text(_funding(context, b), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  /// The server's summary carries the amounts but is English only, so it is
  /// used in English; Swahili gets a line without amounts.
  String _funding(BuildContext context, Map<String, dynamic> b) {
    final summary = '${b['fundingSummary'] ?? ''}'.trim();
    if (lang != 'sw' && summary.isNotEmpty) return summary;
    final key = 'memberRequests.funding.${b['fundingType']}';
    final text = context.tr(key);
    return text == key ? context.tr('memberRequests.funding.none') : text;
  }
}

/// On Benefits: organisations waiting for the member's answer. Nothing when
/// there are none.
class MemberRequestsCard extends StatelessWidget {
  const MemberRequestsCard({
    super.key,
    required this.count,
    required this.onOpen,
  });

  final int count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return FFCard(
      key: const Key('benefits-member-requests'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count == 1
                ? context.tr('memberRequests.card.one')
                : context
                      .tr('memberRequests.card.many')
                      .replaceAll('{n}', '$count'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            context.tr('memberRequests.card.body'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: FFTokens.spacingMd),
          FFButton(
            key: const Key('benefits-member-requests-open'),
            label: context.tr('memberRequests.card.action'),
            onPressed: onOpen,
            fullWidth: true,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}
