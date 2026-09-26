// Repository — the only place owner communications talk to the ApiClient.
// Maps JSON to typed models so controllers and screens never see transport.

import '../../../../shared/api_client.dart';
import 'communication_models.dart';

class CommunicationRepository {
  CommunicationRepository(this._api);

  final ApiClient _api;

  Future<CommunicationOverview> overview({String? gymId}) async =>
      CommunicationOverview.fromJson(
        await _api.ownerCommunicationOverview(gymId: gymId),
      );

  Future<List<Campaign>> campaigns({
    String? gymId,
    CampaignStatus? status,
  }) async {
    final res = await _api.ownerCampaigns(gymId: gymId, status: status?.wire);
    return ((res['campaigns'] as List?) ?? const [])
        .map((c) => Campaign.fromJson((c as Map).cast()))
        .toList();
  }

  Future<CampaignDetail> campaign(String id) async =>
      CampaignDetail.fromJson(await _api.ownerCampaign(id));

  Future<AudienceCount> audienceCount({
    String? gymId,
    required CampaignAudience audience,
    CampaignPurpose? purpose,
  }) async => AudienceCount.fromJson(
    await _api.ownerAudiencePreview({
      'gymId': ?gymId,
      ...audience.toJson(),
      if (purpose != null) 'purpose': purpose.name,
    }),
  );

  Future<CampaignPreview> preview(Map<String, dynamic> draft) async =>
      CampaignPreview.fromJson(await _api.ownerPreviewCampaignDraft(draft));

  Future<Campaign> create(Map<String, dynamic> draft) async =>
      Campaign.fromJson(
        ((await _api.ownerCreateCampaign(draft))['campaign'] as Map).cast(),
      );

  Future<Campaign> update(String id, Map<String, dynamic> draft) async =>
      Campaign.fromJson(
        ((await _api.ownerUpdateCampaign(id, draft))['campaign'] as Map).cast(),
      );

  Future<void> delete(String id) => _api.ownerDeleteCampaign(id);

  Future<Campaign> schedule(
    String id,
    DateTime at, {
    bool confirmLargeSend = false,
  }) async => Campaign.fromJson(
    ((await _api.ownerScheduleCampaign(
              id,
              at.toUtc().toIso8601String(),
              confirmLargeSend: confirmLargeSend,
            ))['campaign']
            as Map)
        .cast(),
  );

  Future<Campaign> unschedule(String id) async => Campaign.fromJson(
    ((await _api.ownerUnscheduleCampaign(id))['campaign'] as Map).cast(),
  );

  Future<Campaign> cancel(String id) async => Campaign.fromJson(
    ((await _api.ownerCancelCampaign(id))['campaign'] as Map).cast(),
  );

  Future<Campaign> send(
    String id, {
    required String sendRequestId,
    bool confirmLargeSend = false,
  }) async => Campaign.fromJson(
    ((await _api.ownerSendCampaign(
              id,
              sendRequestId: sendRequestId,
              confirmLargeSend: confirmLargeSend,
            ))['campaign']
            as Map)
        .cast(),
  );
}
