// Owner communications — WhatsApp in the composer: it can only be picked
// when WhatsApp is set up and the message started from a template approved
// for WhatsApp (free text never goes out on WhatsApp).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/owner/communications/communication_controller.dart';
import 'package:fitflexmobile/screens/owner/communications/data/communication_models.dart';
import 'package:fitflexmobile/screens/owner/communications/data/communication_repository.dart';
import 'package:fitflexmobile/screens/owner/communications/widgets/channel_selector.dart';
import 'package:fitflexmobile/screens/owner/communications/widgets/comms_format.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/i18n.dart';

const _body = {'en': MessageText(title: 'Renew', body: 'Hi {{member_name}}')};
const _approved = CommTemplate(
  id: 'tpl_sys_renewal_reminder',
  key: 'renewal_reminder',
  name: 'renewal_reminder',
  system: true,
  purpose: CampaignPurpose.renewal,
  bodies: _body,
  whatsappReady: true,
);
const _notApproved = CommTemplate(
  id: 'tpl_gym_1',
  key: 'custom',
  name: 'Mine',
  system: false,
  purpose: CampaignPurpose.renewal,
  bodies: _body,
);

CampaignComposerController _composer({bool whatsapp = true}) =>
    CampaignComposerController(
      CommunicationRepository(ApiClient(baseUrl: 'http://localhost:0')),
      gymId: 'gym_1',
      channelsAvailable: ChannelAvailability(push: true, whatsapp: whatsapp),
      countDebounce: Duration.zero,
    );

void main() {
  test('the template JSON says whether it is approved for WhatsApp', () {
    final t = CommTemplate.fromJson({
      'id': 'x',
      'whatsapp': {'ready': true},
    });
    expect(t.whatsappReady, isTrue);
    expect(CommTemplate.fromJson({'id': 'y'}).whatsappReady, isFalse);
  });

  test('WhatsApp needs an approved template, and is dropped when the '
      'template changes', () {
    final c = _composer();
    expect(c.channelUsable(CommChannel.whatsapp), isFalse, reason: 'free text');
    c.toggleChannel(CommChannel.whatsapp, true);
    expect(c.channels, isNot(contains(CommChannel.whatsapp)));

    c.applyTemplate(_approved);
    expect(c.channelUsable(CommChannel.whatsapp), isTrue);
    c.toggleChannel(CommChannel.whatsapp, true);
    expect(c.channels, contains(CommChannel.whatsapp));
    expect(c.draftJson()['channels'], contains('whatsapp'));

    c.applyTemplate(_notApproved);
    expect(c.channels, isNot(contains(CommChannel.whatsapp)));

    c.applyTemplate(_approved);
    c.toggleChannel(CommChannel.whatsapp, true);
    c.clearTemplate();
    expect(c.channels, isNot(contains(CommChannel.whatsapp)));
    expect(c.channelUsable(CommChannel.whatsapp), isFalse);
  });

  test('with WhatsApp not set up, even an approved template can\'t use it', () {
    final c = _composer(whatsapp: false)..applyTemplate(_approved);
    expect(c.channelUsable(CommChannel.whatsapp), isFalse);
  });

  test('a loaded draft learns whether its template still allows WhatsApp', () {
    final c = _composer()..applyTemplate(_approved);
    c.toggleChannel(CommChannel.whatsapp, true);
    c.setWhatsappReady(false);
    expect(c.channels, isNot(contains(CommChannel.whatsapp)));
  });

  testWidgets('the channel step says why WhatsApp can\'t be picked', (
    tester,
  ) async {
    Future<void> pump(CampaignComposerController c) => tester.pumpWidget(
      FFLocaleScope(
        notifier: FFLocale(),
        child: MaterialApp(
          home: Scaffold(body: ChannelSelector(controller: c)),
        ),
      ),
    );
    await pump(_composer());
    expect(
      find.text(
        'To use WhatsApp, start from a FitFlex template approved for WhatsApp',
      ),
      findsOneWidget,
    );
    await pump(_composer(whatsapp: false));
    expect(
      find.textContaining('FitFlex is setting up WhatsApp'),
      findsOneWidget,
    );
    await pump(_composer()..applyTemplate(_approved));
    final tile = tester.widget<CheckboxListTile>(
      find.byKey(const Key('channel-whatsapp')),
    );
    expect(tile.onChanged, isNotNull);
  });

  testWidgets('new skip reasons have labels', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      FFLocaleScope(
        notifier: FFLocale(),
        child: MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(
      skipReasonLabel(ctx, 'whatsapp_disabled'),
      'WhatsApp paused by FitFlex',
    );
    expect(skipReasonLabel(ctx, 'invalid_phone'), "Phone number can't be used");
    expect(
      skipReasonLabel(ctx, 'whatsapp_template_not_approved'),
      'Template not approved for WhatsApp',
    );
  });
}
