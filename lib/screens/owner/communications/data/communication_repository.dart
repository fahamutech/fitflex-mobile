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

  // ── templates ────────────────────────────────────────────────────────────

  Future<List<CommTemplate>> templates({String? gymId, String? group}) async {
    final res = await _api.ownerTemplates(gymId: gymId, group: group);
    return ((res['templates'] as List?) ?? const [])
        .map((t) => CommTemplate.fromJson((t as Map).cast()))
        .toList();
  }

  Future<CommTemplate> template(String id) async => CommTemplate.fromJson(
    ((await _api.ownerTemplate(id))['template'] as Map).cast(),
  );

  Future<TemplatePreview> previewTemplate(
    String id, {
    String? gymId,
    Map<String, dynamic>? values,
  }) async => TemplatePreview.fromJson(
    await _api.ownerTemplatePreview(id, gymId: gymId, values: values),
  );

  Future<CommTemplate> createTemplate(Map<String, dynamic> body) async =>
      CommTemplate.fromJson(
        ((await _api.ownerCreateTemplate(body))['template'] as Map).cast(),
      );

  Future<CommTemplate> updateTemplate(
    String id,
    Map<String, dynamic> body,
  ) async => CommTemplate.fromJson(
    ((await _api.ownerUpdateTemplate(id, body))['template'] as Map).cast(),
  );

  Future<CommTemplate> duplicateTemplate(String id, {String? gymId}) async =>
      CommTemplate.fromJson(
        ((await _api.ownerDuplicateTemplate(id, gymId: gymId))['template']
                as Map)
            .cast(),
      );

  Future<void> archiveTemplate(String id) => _api.ownerArchiveTemplate(id);
}
