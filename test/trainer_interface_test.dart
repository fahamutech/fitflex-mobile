// Trainer interface: social handles, the availability calendar, the
// calendar → booking hand-off, trainer gym access and the owner's
// trainer-pass form.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/widgets/trainer_actions_sheet.dart';
import 'package:fitflexmobile/screens/trainer/trainer_gyms_tab.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:fitflexmobile/shared/widgets/availability_calendar.dart';
import 'package:fitflexmobile/shared/widgets/social_links.dart';

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://localhost:0');

  final quotes = <Map<String, dynamic>>[];
  final passRequests = <Map<String, String?>>[];
  final planRequests = <Map<String, String>>[];

  @override
  Future<Map<String, dynamic>> quoteTrainerBooking({
    required String trainerId,
    required String gymId,
    required List<Map<String, String>> slots,
  }) async {
    quotes.add({'trainerId': trainerId, 'gymId': gymId, 'slots': slots});
    return {
      'summary': {
        'slots': slots,
        'currency': 'TZS',
        'pricePerSession': 20000,
        'subtotal': 20000 * slots.length,
        'discount': 0,
        'discountPct': 0,
        'total': 20000 * slots.length,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> trainerBuyPass(
    String gymId, {
    String? period,
  }) async {
    passRequests.add({'gymId': gymId, 'period': period});
    return {};
  }

  @override
  Future<Map<String, dynamic>> trainerBuyMemberPlan(
    String gymId,
    String plan,
  ) async {
    planRequests.add({'gymId': gymId, 'plan': plan});
    return {};
  }
}

Widget _wrap(Widget child, {ApiClient? api}) {
  final client = api ?? _FakeApi();
  return AppScope(
    api: client,
    auth: AuthState(client),
    child: ThemeScope(
      notifier: ThemeNotifier(),
      child: FFLocaleScope(
        notifier: FFLocale(),
        child: MaterialApp(
          theme: buildTheme(),
          supportedLocales: const [Locale('en'), Locale('sw')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    ),
  );
}

ScheduleDay _day(String date, String weekday, List<(String, String)> slots) =>
    ScheduleDay(
      date: date,
      weekday: weekday,
      slots: [
        for (final (slot, status) in slots)
          ScheduleSlot(slot: slot, status: status, gymIds: const ['gym_1']),
      ],
    );

void main() {
  group('social handles (same rule as the backend)', () {
    test('handles, @handles and profile links reduce to the handle', () {
      expect(normalizeSocialHandle('instagram', '@coach.asha'), 'coach.asha');
      expect(
        normalizeSocialHandle(
          'instagram',
          'https://www.instagram.com/coach.asha/?hl=en',
        ),
        'coach.asha',
      );
      expect(
        normalizeSocialHandle('twitter', 'x.com/coach_asha'),
        'coach_asha',
      );
      expect(
        normalizeSocialHandle(
          'facebook',
          'https://facebook.com/profile.php?id=100012345',
        ),
        'profile.php?id=100012345',
      );
      expect(normalizeSocialHandle('instagram', '  '), '');
    });

    test('other sites and invalid characters are rejected', () {
      expect(
        normalizeSocialHandle('instagram', 'https://evil.example/c'),
        isNull,
      );
      expect(normalizeSocialHandle('twitter', 'coach asha'), isNull);
    });

    test('links parse from the API and build profile URLs', () {
      final links = SocialLinks.fromJson({'instagram': 'asha', 'twitter': ''});
      expect(links.instagram, 'asha');
      expect(links.twitter, isNull);
      expect(links.isEmpty, isFalse);
      expect(
        socialProfileUri('instagram', 'asha').toString(),
        'https://www.instagram.com/asha',
      );
      expect(socialProfileUri('twitter', 'asha').host, 'x.com');
    });

    testWidgets('invalid handles block the form', (tester) async {
      final controllers = SocialHandleFields.controllersFor(
        const SocialLinks(),
      );
      final form = GlobalKey<FormState>();
      await tester.pumpWidget(
        _wrap(
          Form(
            key: form,
            child: SocialHandleFields(controllers: controllers),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('social-field-instagram')),
        'not valid!',
      );
      expect(form.currentState!.validate(), isFalse);
      await tester.enterText(
        find.byKey(const Key('social-field-instagram')),
        'instagram.com/coach',
      );
      expect(form.currentState!.validate(), isTrue);
      expect(SocialHandleFields.valuesOf(controllers)['instagram'], 'coach');
    });
  });

  group('schedule models', () {
    test('parse the schedule response, including the trainer view', () {
      final days = ScheduleDay.listFromResponse({
        'days': [
          {
            'date': '2099-05-04',
            'weekday': 'monday',
            'slots': [
              {
                'slot': '09:00',
                'status': 'available',
                'gymIds': ['g1'],
              },
              {
                'slot': '10:00',
                'status': 'booked',
                'booking': {
                  'id': 'b1',
                  'status': 'payment_pending',
                  'member': {'displayName': 'Neema'},
                },
              },
            ],
          },
        ],
      });
      expect(days.single.openCount, 1);
      expect(days.single.slots.last.memberName, 'Neema');
      expect(days.single.slots.last.bookingStatus, 'payment_pending');
    });
  });

  group('availability calendar', () {
    final days = [
      _day('2099-05-04', 'monday', [('08:00', 'past'), ('09:00', 'booked')]),
      _day('2099-05-05', 'tuesday', [
        ('07:00', 'available'),
        ('13:00', 'available'),
        ('18:00', 'booked'),
      ]),
      _day('2099-05-06', 'wednesday', []),
    ];

    testWidgets('opens on the first day with open slots and picks slots', (
      tester,
    ) async {
      final picked = <String>[];
      await tester.pumpWidget(
        _wrap(
          AvailabilityCalendar(
            days: days,
            onSlotTap: (d, s) => picked.add(scheduleSlotKey(d.date, s.slot)),
          ),
        ),
      );
      expect(find.text('May 2099'), findsOneWidget);
      expect(find.text('Morning'), findsOneWidget);
      expect(find.text('Afternoon'), findsOneWidget);
      expect(find.text('Evening'), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar-slot-2099-05-05-07:00')));
      // Booked slots cannot be picked.
      await tester.tap(find.byKey(const Key('calendar-slot-2099-05-05-18:00')));
      expect(picked, ['2099-05-05|07:00']);
      expect(find.byKey(const Key('calendar-legend')), findsOneWidget);
    });

    testWidgets('a day with nothing open offers the next available day', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(AvailabilityCalendar(days: days, onSlotTap: (_, _) {})),
      );
      await tester.tap(find.byKey(const Key('calendar-day-2099-05-04')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar-empty-day')), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar-next-available')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('calendar-slot-2099-05-05-07:00')),
        findsOneWidget,
      );
    });

    testWidgets('fits at large system text sizes', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        _wrap(AvailabilityCalendar(days: days, onSlotTap: (_, _) {})),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the trainer view lists who booked', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AvailabilityCalendar(
            days: [
              ScheduleDay(
                date: '2099-05-04',
                weekday: 'monday',
                slots: const [
                  ScheduleSlot(
                    slot: '10:00',
                    status: 'booked',
                    memberName: 'Neema',
                  ),
                ],
              ),
            ],
            showBookings: true,
          ),
        ),
      );
      expect(
        find.byKey(const Key('calendar-booking-2099-05-04-10:00')),
        findsOneWidget,
      );
      expect(find.text('Neema'), findsWidgets);
    });
  });

  testWidgets(
    'slots picked on the calendar go straight to the priced summary',
    (tester) async {
      final api = _FakeApi();
      final trainer = TrainerProfile(
        id: 'trn_1',
        displayName: 'Coach Asha',
        hourlyRateTzs: 20000,
        gymIds: const ['gym_1'],
        status: 'active',
      );
      await tester.pumpWidget(
        _wrap(
          TrainerBookingSheet(
            trainer: trainer,
            gymId: 'gym_1',
            slots: const [
              (date: '2099-05-05', slot: '07:00'),
              (date: '2099-05-05', slot: '13:00'),
            ],
          ),
          api: api,
        ),
      );
      await tester.pumpAndSettle();
      expect(api.quotes.single['gymId'], 'gym_1');
      expect((api.quotes.single['slots'] as List).length, 2);
      expect(find.byKey(const Key('trainer-book-confirm')), findsOneWidget);
    },
  );

  group('trainer gym sheet', () {
    Map<String, dynamic> gym(String access, List<Map<String, dynamic>> opts) =>
        {
          'id': 'gym_1',
          'name': 'Gym Tu',
          'location': 'Masaki',
          'trainerAccess': {'access': access, 'options': opts},
        };

    testWidgets('buys the chosen trainer pass period', (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(
        _wrap(
          TrainerGymSheet(
            gym: gym('trainer_pass', [
              {'kind': 'trainer_pass', 'period': 'daily', 'feeTzs': 8000},
              {'kind': 'trainer_pass', 'period': 'weekly', 'feeTzs': 40000},
            ]),
          ),
          api: api,
        ),
      );
      expect(find.text('Trainer pass from TZS 8,000'), findsOneWidget);
      await tester.tap(find.byKey(const Key('trainer-pass-option-weekly')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('trainer-pass-buy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('trainer-pass-confirm')));
      await tester.pumpAndSettle();
      expect(api.passRequests.single, {'gymId': 'gym_1', 'period': 'weekly'});
    });

    testWidgets('falls back to member plans where no trainer pass is sold', (
      tester,
    ) async {
      final api = _FakeApi();
      await tester.pumpWidget(
        _wrap(
          TrainerGymSheet(
            gym: gym('member_plan', [
              {'kind': 'member_plan', 'period': 'daily', 'feeTzs': 5000},
            ]),
          ),
          api: api,
        ),
      );
      expect(find.text('Get member plan'), findsOneWidget);
      await tester.tap(find.byKey(const Key('trainer-pass-buy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('trainer-pass-confirm')));
      await tester.pumpAndSettle();
      expect(api.planRequests.single, {'gymId': 'gym_1', 'plan': 'daily'});
      expect(api.passRequests, isEmpty);
    });

    testWidgets('a linked gym is free — nothing to buy', (tester) async {
      await tester.pumpWidget(_wrap(TrainerGymSheet(gym: gym('home', []))));
      expect(find.text('My gym · Free'), findsOneWidget);
      expect(find.byKey(const Key('trainer-pass-buy')), findsNothing);
      expect(find.byKey(const Key('trainer-gym-apply')), findsNothing);
    });
  });

  test('every new trainer-interface string has a Swahili translation', () {
    final en = FFLocale.keysOf('en').where(
      (k) =>
          k.startsWith('cal.') ||
          k.startsWith('hours.') ||
          k.startsWith('social.') ||
          k.startsWith('trainerPass.'),
    );
    final sw = FFLocale.keysOf('sw');
    expect(en.length, greaterThan(100));
    expect(en.where((k) => !sw.contains(k)), isEmpty);
  });
}
