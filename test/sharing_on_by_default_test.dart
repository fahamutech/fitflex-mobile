// Member sharing is on by default (owner decision 2026-10-19): the default
// audience can cover all groups, and the copy says what is shared.
import 'package:fitflexmobile/shared/activity/trainer_connection.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/social.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShareWith.allGroups', () {
    test('parses from the server', () {
      final s = ShareWith.fromJson({'public': true, 'allGroups': true})!;
      expect(s.public, isTrue);
      expect(s.allGroups, isTrue);
      expect(s.groups, isEmpty);
    });

    test('all groups alone is not private', () {
      final s = ShareWith.fromJson({'allGroups': true});
      expect(s, isNotNull);
      expect(s!.isPrivate, isFalse);
    });

    test('missing allGroups reads as false', () {
      expect(ShareWith.fromJson({'public': true})!.allGroups, isFalse);
    });

    test('is always sent, true or false', () {
      expect(const ShareWith(public: true).toJson()['allGroups'], isFalse);
      expect(ShareWith.wire(const ShareWith(public: true, allGroups: true)), {
        'v': 2,
        'friends': false,
        'followers': false,
        'public': true,
        'groups': <String>[],
        'company': false,
        'allGroups': true,
      });
    });

    test('round-trips and compares by value', () {
      const a = ShareWith(public: true, allGroups: true);
      final b = ShareWith.fromJson(a.toJson());
      expect(b, a);
      expect(b.hashCode, a.hashCode);
      expect(b == const ShareWith(public: true), isFalse);
      expect(
        const ShareWith(groups: ['a', 'b']),
        const ShareWith(groups: ['b', 'a']),
      );
    });
  });

  test('a new trainer connection starts with every permission on', () {
    for (final p in TrainerPermission.values) {
      expect(TrainerPermissions.all.has(p), isTrue, reason: p.wire);
    }
    expect(TrainerPermissions.all.toJson().values, everyElement(isTrue));
  });

  group('copy', () {
    const keys = [
      'privacy.body',
      'share.body',
      'share.requestNote',
      'connect.body',
      'sharing.body',
      'sharing.noTrainers',
      'share.nothing',
      'gymShare.always',
      'gymShare.neverShared',
      'challenge.creatorDoesNotSee',
      'leaderboard.optInHint',
      'leaderboard.joinNote',
      'audience.privateHint',
      'audience.allGroups',
      'audience.allGroupsHint',
    ];

    test('every new or changed line exists in English and Swahili', () {
      for (final key in keys) {
        expect(FFLocale.textOf('en', key), isNotNull, reason: 'en: $key');
        expect(FFLocale.textOf('sw', key), isNotNull, reason: 'sw: $key');
        expect(
          FFLocale.textOf('sw', key),
          isNot(FFLocale.textOf('en', key)),
          reason: 'sw copied from en: $key',
        );
      }
    });

    test('nothing still promises private by default', () {
      for (final key in keys) {
        final en = FFLocale.textOf('en', key)!;
        expect(en, isNot(contains('Off by default')), reason: key);
        expect(en, isNot(contains('Your activity is private')), reason: key);
        expect(en, isNot(contains('Nothing is shared unless')), reason: key);
      }
    });

    test('placeholders survive translation', () {
      for (final key in keys) {
        final en = FFLocale.textOf('en', key)!;
        final sw = FFLocale.textOf('sw', key)!;
        for (final ph in ['{name}', '{gym}']) {
          expect(sw.contains(ph), en.contains(ph), reason: '$key $ph');
        }
      }
    });
  });
}
