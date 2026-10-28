// Events S2 (spec §11.12): i18n parity for the new keys, the error-reason
// copy, the routes behind the flag, and the inbox deep-link cases.
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const keys = [
    'activity.events',
    'home.events.title',
    'home.events.seeAll',
    'home.events.semantics',
    'events.title',
    'events.search.hint',
    'events.chip.open',
    'events.chip.thisMonth',
    'events.chip.filters',
    'events.chip.filtersCount',
    'events.chip.saved',
    'events.filters.title',
    'events.filters.date',
    'events.filters.date.anytime',
    'events.filters.date.thisMonth',
    'events.filters.date.next3',
    'events.filters.date.custom',
    'events.filters.from',
    'events.filters.to',
    'events.filters.distance',
    'events.filters.distance.other',
    'events.filters.type',
    'events.filters.location',
    'events.filters.anywhere',
    'events.filters.price',
    'events.filters.price.free',
    'events.filters.price.under20k',
    'events.filters.price.under50k',
    'events.filters.price.any',
    'events.filters.openOnly',
    'events.filters.clear',
    'events.filters.show',
    'events.filters.showCount',
    'events.results.count',
    'events.sort',
    'events.sort.soonest',
    'events.sort.priceLow',
    'events.sort.newest',
    'events.type.road',
    'events.type.trail',
    'events.type.fun',
    'events.type.charity',
    'events.type.virtual',
    'events.card.from',
    'events.card.free',
    'events.card.verifiedOrganizer',
    'events.availability.open',
    'events.availability.closing_soon',
    'events.availability.sold_out',
    'events.availability.closed',
    'events.availability.not_yet_open',
    'events.availability.cancelled',
    'events.availability.in_progress',
    'events.availability.completed',
    'events.loadMore',
    'events.loadMoreFailed',
    'events.empty.title',
    'events.empty.body',
    'events.empty.filtered.title',
    'events.empty.filtered.body',
    'events.empty.filtered.action',
    'events.offline.body',
    'events.offline.savedCopy',
    'events.unavailable.title',
    'events.unavailable.body',
    'events.detail.starts',
    'events.detail.ends',
    'events.detail.regCloses',
    'events.detail.distances',
    'events.detail.fromPrice',
    'events.detail.about',
    'events.detail.readMore',
    'events.detail.readLess',
    'events.detail.noSwahili',
    'events.detail.organizer',
    'events.detail.dateTime',
    'events.detail.timezoneNote',
    'events.detail.localTime',
    'events.detail.venue',
    'events.detail.openMaps',
    'events.detail.routeLink',
    'events.detail.routeImage',
    'events.detail.opensBrowser',
    'events.detail.categories',
    'events.detail.until',
    'events.detail.left',
    'events.detail.inclusions',
    'events.detail.eligibility',
    'events.detail.minAge',
    'events.detail.accessibility',
    'events.detail.kit',
    'events.detail.schedule',
    'events.detail.sponsors',
    'events.detail.contact',
    'events.detail.terms',
    'events.detail.refundPolicy',
    'events.detail.policy.no_refund',
    'events.detail.policy.refund_until_close',
    'events.detail.showAll',
    'events.detail.updated',
    'events.detail.report',
    'events.detail.gone.title',
    'events.detail.gone.body',
    'events.detail.back',
    'events.detail.cancelledBanner',
    'events.cta.register',
    'events.cta.registerFrom',
    'events.cta.soon',
    'events.cta.closes',
    'events.cta.closingSoon',
    'events.cta.soldOut',
    'events.cta.soldOutHint',
    'events.cta.closed',
    'events.cta.opens',
    'events.cta.cancelled',
    'events.save',
    'events.saved',
    'events.unsave',
    'events.share',
    'events.share.text',
    'error.reason.eventNotFound',
    'error.offlineTitle',
    'a11y.clear',
    'common.share',
    'common.copied',
  ];

  test('every §11.9 key exists in both languages', () {
    final en = FFLocale.keysOf('en');
    final sw = FFLocale.keysOf('sw');
    for (final k in keys) {
      expect(en, contains(k), reason: 'en $k');
      expect(sw, contains(k), reason: 'sw $k');
    }
    expect(en, sw);
  });

  test('Swahili lines are translated (except shared tokens)', () {
    const same = {
      'events.share.text',
      'events.availability.in_progress', // "Inaendelea" differs; listed for clarity
    };
    for (final k in keys) {
      if (same.contains(k)) continue;
      expect(
        FFLocale.textOf('sw', k),
        isNot(FFLocale.textOf('en', k)),
        reason: k,
      );
    }
  });

  test('event error reasons map to copy in both languages', () {
    for (final lang in ['en', 'sw']) {
      final locale = FFLocale()..set(Locale(lang));
      final e = ApiException(404, {'error': 'event_not_found'});
      expect(
        errorMessage(locale, e),
        contains(locale.t('error.reason.eventNotFound')),
      );
      final f = ApiException(404, {'error': 'feature_disabled'});
      expect(
        errorMessage(locale, f),
        contains(locale.t('error.reason.featureDisabled')),
      );
      final r = ApiException(429, {'error': 'rate_limited'});
      expect(
        errorMessage(locale, r),
        contains(locale.t('error.reason.rateLimited')),
      );
    }
  });

  group('routes', () {
    tearDown(() => debugEventsDiscoveryOverride = null);

    test('flag on: /member/events/:eventId matches the detail route', () {
      debugEventsDiscoveryOverride = true;
      final router = buildRouter(AuthState(ApiClient(baseUrl: 'http://x')));
      addTearDown(router.dispose);
      final match = router.configuration.findMatch(
        Uri.parse('/member/events/evt_123'),
      );
      expect(match.isError, isFalse);
      expect(match.last.route.name, 'memberEventDetail');
      expect(match.pathParameters['eventId'], 'evt_123');
      final list = router.configuration.findMatch(Uri.parse('/member/events'));
      expect(list.last.route.name, 'memberEvents');
      expect(AppRoutes.memberEvents, '/member/events');
      expect(AppRoutes.memberEventDetail, '/member/events/:eventId');
    });

    test('flag off: the routes do not exist (not found)', () {
      debugEventsDiscoveryOverride = false;
      final router = buildRouter(AuthState(ApiClient(baseUrl: 'http://x')));
      addTearDown(router.dispose);
      expect(
        router.configuration
            .findMatch(Uri.parse('/member/events/evt_123'))
            .isError,
        isTrue,
      );
      expect(
        router.configuration.findMatch(Uri.parse('/member/events')).isError,
        isTrue,
      );
    });
  });

  group('inbox deep links', () {
    test('an event notice opens its detail, or the list without an id', () {
      expect(
        memberRouteFor(deepLink: '', type: 'event', eventId: 'evt_9'),
        '/member/events/evt_9',
      );
      expect(memberRouteFor(deepLink: '', type: 'event'), '/member/events');
      expect(
        memberRouteFor(deepLink: '', type: 'event', eventId: 'bad id!'),
        '/member/events',
      );
      expect(memberLinkFor(deepLink: '', type: 'event'), 'event');
    });
  });
}
