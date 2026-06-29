// Widget tests for the owner member management UI components.
// Tests FFStatTile, MemberListTile and MemberStatusBadge in isolation.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/screens/owner/members/data/member_models.dart';
import 'package:fitflexmobile/screens/owner/members/widgets/member_list_tile.dart';
import 'package:fitflexmobile/screens/owner/members/widgets/member_presentation.dart';

// ── Harness ───────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) {
  final locale = FFLocale();
  return FFLocaleScope(
    notifier: locale,
    child: MaterialApp(
      theme: buildTheme(),
      supportedLocales: const [Locale('en'), Locale('sw')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    ),
  );
}

// ── FFStatTile ─────────────────────────────────────────────────────────────────

void main() {
  group('FFStatTile', () {
    testWidgets('renders value and label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FFStatTile(
            icon: Icons.groups_outlined,
            value: '128',
            label: 'Total Members',
          ),
        ),
      );
      expect(find.text('128'), findsOneWidget);
      expect(find.text('Total Members'), findsOneWidget);
    });

    testWidgets('renders icon', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FFStatTile(
            icon: Icons.groups_outlined,
            value: '0',
            label: 'Test',
          ),
        ),
      );
      expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
    });
  });

  // ── MemberListTile ─────────────────────────────────────────────────────────

  group('MemberListTile', () {
    OwnerMember _testMember({
      OwnerMemberStatus status = OwnerMemberStatus.active,
      OwnerMemberType type = OwnerMemberType.direct,
      String? name = 'Amina Juma',
      DateTime? lastCheckin,
    }) => OwnerMember(
      id: 'usr_1',
      publicId: 'FM100',
      displayName: name,
      phone: '+255712345678',
      memberType: type,
      tier: 'premium',
      status: status,
      lastCheckinAt: lastCheckin,
    );

    testWidgets('renders display name', (tester) async {
      await tester.pumpWidget(
        _wrap(MemberListTile(member: _testMember(), onTap: () {})),
      );
      expect(find.text('Amina Juma'), findsOneWidget);
    });

    testWidgets('falls back to publicId when displayName empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MemberListTile(
            member: _testMember(name: ''),
            onTap: () {},
          ),
        ),
      );
      expect(find.text('FM100'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          MemberListTile(member: _testMember(), onTap: () => tapped = true),
        ),
      );
      await tester.tap(find.byType(MemberListTile));
      expect(tapped, isTrue);
    });

    testWidgets('shows last checkin line when provided', (tester) async {
      final checkin = DateTime.now().subtract(const Duration(hours: 2));
      await tester.pumpWidget(
        _wrap(
          MemberListTile(
            member: _testMember(lastCheckin: checkin),
            onTap: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
    });

    testWidgets('does not show checkin line when null', (tester) async {
      await tester.pumpWidget(
        _wrap(MemberListTile(member: _testMember(), onTap: () {})),
      );
      expect(find.byIcon(Icons.calendar_today_outlined), findsNothing);
    });

    testWidgets('shows chevron icon', (tester) async {
      await tester.pumpWidget(
        _wrap(MemberListTile(member: _testMember(), onTap: () {})),
      );
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('shows FFBadge for status', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MemberListTile(
            member: _testMember(status: OwnerMemberStatus.expiringSoon),
            onTap: () {},
          ),
        ),
      );
      expect(find.byType(FFBadge), findsOneWidget);
    });
  });

  // ── MemberStatusBadge ──────────────────────────────────────────────────────

  group('MemberStatusBadge', () {
    for (final s in OwnerMemberStatus.values) {
      testWidgets('renders badge for $s', (tester) async {
        await tester.pumpWidget(_wrap(MemberStatusBadge(status: s)));
        expect(find.byType(FFBadge), findsOneWidget);
      });
    }

    testWidgets('active badge uses success tone', (tester) async {
      expect(OwnerMemberStatus.active.tone, FFBadgeTone.success);
    });

    testWidgets('suspended badge uses danger tone', (tester) async {
      expect(OwnerMemberStatus.suspended.tone, FFBadgeTone.danger);
    });

    testWidgets('expiring_soon uses warning tone', (tester) async {
      expect(OwnerMemberStatus.expiringSoon.tone, FFBadgeTone.warning);
    });

    testWidgets('checked_in uses brand tone', (tester) async {
      expect(OwnerMemberStatus.checkedIn.tone, FFBadgeTone.brand);
    });
  });
}
