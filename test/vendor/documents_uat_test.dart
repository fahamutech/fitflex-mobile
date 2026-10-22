// Vendor tools · S5 UAT fixes: D1 cancelled ORDER invoices read as an
// order cancellation (vendor and buyer views), never as a voided document;
// D5 the web PDF row says "Open PDF of …" and a TIN taken from KYC is
// announced read-only. Every request goes to the in-process RecordingApi
// (http://fixtures.local); nothing reaches a real server.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/documents/document_models.dart';
import 'package:fitflexmobile/screens/vendor/documents/document_share_sheet.dart';
import 'package:fitflexmobile/screens/vendor/documents/document_view.dart';
import 'package:fitflexmobile/screens/vendor/settings/tax_details_page.dart';
import 'package:fitflexmobile/shared/formatters.dart';

import '../support/recording_api.dart';
import 'walkin_support.dart' show salesRoutes;

const owner = {'id': 'v1', 'userType': 'vendor', 'displayName': 'Asha'};
const member = {'id': 'm1', 'userType': 'member'};

Map<String, dynamic> cancelledOrderDoc({String? cancelledAt}) => {
  'docType': 'order_invoice',
  'number': 'INV-000007',
  'orderShortRef': 'ABC123',
  'status': 'cancelled',
  'issuedAt': '2026-10-19T08:00:00.000Z',
  'seller': {'businessName': 'Dar Gear'},
  'soldVia': 'Seller: Dar Gear. Sold through the FitFlex app.',
  'lines': [
    {
      'name': 'Whey',
      'qty': 1,
      'unitPriceTzs': 10000,
      'discountTzs': 0,
      'amountTzs': 10000,
    },
  ],
  'subtotalTzs': 10000,
  'discountsTzs': 0,
  'totalTzs': 10000,
  'vatIncludedTzs': 0,
  'vatSummary': [],
  'payments': [],
  'changeTzs': 0,
  'cancelledAt': cancelledAt,
  'vendorId': 'v1',
};

/// "20 Oct 2026" / "20 Okt 2026" as the views write it.
String day(String lang) => formatDate(DateTime(2026, 10, 20), locale: lang);

void main() {
  setUpAll(loadAppFonts);

  group('D1 cancelled order invoice', () {
    for (final lang in ['en', 'sw']) {
      apiTest('vendor view ($lang): order-cancelled wording, no void text', (
        tester,
        api,
      ) async {
        api.on('GET /vendor/tools/options', {'documents': true});
        api.on('GET /vendor/documents/order/ord_1', {
          'doc': cancelledOrderDoc(cancelledAt: '2026-10-20T07:00:00.000Z'),
        });
        final host = await pumpPage(
          tester,
          api,
          const VendorOrderInvoicePage(orderId: 'ord_1'),
          user: owner,
          lang: lang,
          size: const Size(420, 1400),
        );
        final sw = lang == 'sw';
        expect(
          find.text(sw ? 'Oda hii imeghairiwa.' : 'This order was cancelled.'),
          findsOneWidget,
        );
        expect(
          find.text(
            sw
                ? 'Imeghairiwa tarehe ${day('sw')}'
                : 'Cancelled on ${day('en')}',
          ),
          findsOneWidget,
        );
        // Not the voided-document texts.
        expect(find.text(host.tr('vendor.documents.voidedNote')), findsNothing);
        expect(find.text(host.tr('vendor.doc.statusCancelled')), findsNothing);
        expect(find.textContaining('cancelled this document'), findsNothing);
        expect(find.textContaining('imebatilisha'), findsNothing);
        // Its links can still be turned off; no new share.
        expect(find.byKey(const Key('order-invoice-links')), findsOneWidget);
        expect(find.byKey(const Key('order-invoice-share')), findsNothing);
      });

      apiTest('buyer view ($lang): order-cancelled wording', (
        tester,
        api,
      ) async {
        api.on('GET /me/shop-orders/ord_1/invoice', {
          'invoices': [
            cancelledOrderDoc(cancelledAt: '2026-10-20T07:00:00.000Z'),
          ],
        });
        await pumpPage(
          tester,
          api,
          const BuyerInvoicePage(orderId: 'ord_1'),
          user: member,
          lang: lang,
          size: const Size(420, 1400),
        );
        final sw = lang == 'sw';
        expect(
          find.text(sw ? 'Oda hii imeghairiwa.' : 'This order was cancelled.'),
          findsOneWidget,
        );
        expect(
          find.text(
            sw
                ? 'Imeghairiwa tarehe ${day('sw')}'
                : 'Cancelled on ${day('en')}',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('cancelled this document'), findsNothing);
        expect(find.textContaining('imebatilisha'), findsNothing);
      });
    }

    apiTest('no cancellation date: badge just says Cancelled', (
      tester,
      api,
    ) async {
      api.on('GET /me/shop-orders/ord_1/invoice', {
        'invoices': [cancelledOrderDoc()],
      });
      await pumpPage(
        tester,
        api,
        const BuyerInvoicePage(orderId: 'ord_1'),
        user: member,
        size: const Size(420, 1400),
      );
      final badge = find.byKey(const Key('doc-status'));
      expect(
        find.descendant(of: badge, matching: find.text('Cancelled')),
        findsOneWidget,
      );
      expect(find.textContaining('{date}'), findsNothing);
    });

    apiTest('a voided walk-in receipt keeps the voided-document wording', (
      tester,
      api,
    ) async {
      await pumpPage(
        tester,
        api,
        Builder(
          builder: (context) => VendorDocumentView(
            doc: VendorDoc.fromJson({
              ...cancelledOrderDoc(cancelledAt: '2026-10-20T07:00:00.000Z'),
              'docType': 'receipt',
              'number': 'R-000001',
            }),
            t: (k) =>
                const {
                  'vendor.doc.cancelled':
                      'Cancelled on {date}. {business} cancelled this document.',
                  'vendor.doc.statusCancelled': 'Cancelled',
                }[k] ??
                k,
            lang: 'en',
          ),
        ),
        user: owner,
        size: const Size(420, 1400),
      );
      expect(
        find.textContaining('Dar Gear cancelled this document.'),
        findsOneWidget,
      );
      expect(find.text('This order was cancelled.'), findsNothing);
    });
  });

  group('D5 accessibility', () {
    apiTest('web: the PDF row is announced "Open PDF of …"', (
      tester,
      api,
    ) async {
      final handle = tester.ensureSemantics();
      final isWeb = DocumentActions.isWeb;
      DocumentActions.isWeb = () => true;
      addTearDown(() => DocumentActions.isWeb = isWeb);
      await pumpPage(
        tester,
        api,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDocumentShareSheet(
              context,
              doc: DocumentRef.sale(
                saleId: 'sal_1',
                credit: false,
                number: 'R-000001',
              ),
              lang: 'en',
              shareText: (_) => 'T',
              shareSubject: (_) => 'S',
            ),
            child: const Text('OPEN'),
          ),
        ),
        user: owner,
        size: const Size(420, 1400),
      );
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      expect(find.text('Open PDF'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Open PDF of Receipt R-000001'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('^Send PDF')), findsNothing);
      handle.dispose();
    });

    apiTest('the TIN from verification is announced read-only', (
      tester,
      api,
    ) async {
      final handle = tester.ensureSemantics();
      api.on('GET /vendor/tools/options', {'vat': true});
      api.on('GET /vendor/tax-profile', {
        'taxProfile': {
          'vatRegistered': true,
          'tin': '123456789',
          'tinFromKyc': true,
          'vrn': '40012345X',
          'certificateDocumentId': 'pdoc_1',
          'status': 'pending',
          'updatedAt': '2026-10-20T08:00:00.000Z',
        },
      });
      await pumpPage(
        tester,
        api,
        const TaxDetailsPage(),
        user: owner,
        size: const Size(420, 1400),
        extraRoutes: salesRoutes,
      );
      final tin = find.bySemanticsLabel(
        RegExp('^TIN, read-only, from your verification'),
      );
      expect(tin, findsOneWidget);
      final data = tester.getSemantics(tin).getSemanticsData();
      expect(data.flagsCollection.isReadOnly, isTrue);
      // The VRN the owner may change is not read-only.
      expect(find.bySemanticsLabel(RegExp('read-only')), findsOneWidget);
      handle.dispose();
    });
  });
}
