// Repository — the only place partner verification talks to the ApiClient.

import '../../../shared/api_client.dart';
import 'verification_models.dart';

class VerificationRepository {
  VerificationRepository(this._api);

  final ApiClient _api;

  Future<KycOverview> overview() async =>
      KycOverview.fromJson(await _api.myKyc());

  Future<KycOverview> updateBusiness(Map<String, dynamic> body) async =>
      KycOverview.fromJson(await _api.updateMyKycBusiness(body));

  Future<KycOverview> updatePerson(
    String role,
    Map<String, dynamic> body,
  ) async => KycOverview.fromJson(await _api.updateMyKycPerson(role, body));

  Future<KycOverview> updateDocument(
    String requirementKey,
    Map<String, dynamic> body,
  ) async => KycOverview.fromJson(
    await _api.updateMyKycDocument(requirementKey, body),
  );

  Future<KycOverview> uploadDocumentFile(
    String requirementKey, {
    required List<int> bytes,
    required String filename,
    String? docType,
  }) async => KycOverview.fromJson(
    await _api.uploadMyKycDocumentFile(
      requirementKey,
      bytes: bytes,
      filename: filename,
      docType: docType,
    ),
  );

  Future<void> addPayoutAccount(Map<String, dynamic> body) async =>
      _api.addMyKycSettlementAccount(body);

  Future<void> removePayoutAccount(String id) =>
      _api.removeMyKycSettlementAccount(id);

  Future<KycOverview> submit() async =>
      KycOverview.fromJson(await _api.submitMyKyc());

  Future<KycOverview> withdraw() async =>
      KycOverview.fromJson(await _api.withdrawMyKyc());

  Future<List<KycAgreement>> agreements(String lang) async {
    final json = await _api.myKycAgreements(lang);
    return [
      for (final a in (json['agreements'] as List? ?? const []))
        if (a is Map<String, dynamic>) KycAgreement.fromJson(a),
    ];
  }

  Future<KycOverview> acceptAgreement(KycAgreement agreement) async =>
      KycOverview.fromJson(
        await _api.acceptMyKycAgreement(
          agreement.agreementType,
          agreement.version,
        ),
      );
}
