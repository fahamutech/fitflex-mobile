// Repository — the only place owner communications talk to the ApiClient.
// Maps JSON to typed models so controllers and screens never see transport.

import '../../../../shared/api_client.dart';
import 'communication_models.dart';
import 'analytics_models.dart';
import 'automation_models.dart';
import 'history_models.dart';

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

  static Map<String, String> _page(
    HistoryFilter filter,
    String? cursor,
    int limit,
  ) => {...filter.toQuery(), 'limit': '$limit', 'cursor': ?cursor};

  Future<HistoryPage<Recipient>> recipients(
    String campaignId, {
    HistoryFilter filter = const HistoryFilter(),
    String? cursor,
    int limit = 20,
  }) async {
    final res = await _api.ownerCampaignRecipients(
      campaignId,
      query: _page(filter, cursor, limit),
    );
    return HistoryPage(
      ((res['recipients'] as List?) ?? const [])
          .map((r) => Recipient.fromJson((r as Map).cast()))
          .toList(),
      res['nextCursor']?.toString(),
    );
  }

  Future<HistoryPage<CommunicationItem>> memberCommunications(
    String memberId, {
    HistoryFilter filter = const HistoryFilter(),
    String? cursor,
    int limit = 20,
  }) async {
    final res = await _api.ownerMemberCommunications(
      memberId,
      query: _page(filter, cursor, limit),
    );
    return HistoryPage(
      ((res['items'] as List?) ?? const [])
          .map((r) => CommunicationItem.fromJson((r as Map).cast()))
          .toList(),
      res['nextCursor']?.toString(),
    );
  }

  Future<CommsResults> results({int days = 30, String? gymId}) async =>
      CommsResults.fromJson(
        await _api.ownerCommunicationAnalytics(days: days, gymId: gymId),
      );

  Future<CommsResults> campaignResults(String id) async =>
      CommsResults.fromJson(await _api.ownerCampaignAnalytics(id));

  Future<CommsResults> automationResults(String id, {int days = 30}) async =>
      CommsResults.fromJson(
        await _api.ownerAutomationAnalytics(id, days: days),
      );

  Future<List<Automation>> automations({String? gymId}) async {
    final res = await _api.ownerAutomations(gymId: gymId);
    return ((res['automations'] as List?) ?? const [])
        .map((a) => Automation.fromJson((a as Map).cast()))
        .toList();
  }

  Future<Automation> updateAutomation(
    String id, {
    bool? enabled,
    List<CommChannel>? channels,
    String? templateId,
  }) async => Automation.fromJson(
    ((await _api.ownerUpdateAutomation(id, {
              if (enabled != null) 'status': enabled ? 'enabled' : 'disabled',
              if (channels != null)
                'channels': channels.map((c) => c.wire).toList(),
              'templateId': ?templateId,
            }))['automation']
            as Map)
        .cast(),
  );

  Future<List<AutomationFiring>> automationRuns(String id) async {
    final res = await _api.ownerAutomationRuns(id);
    return ((res['runs'] as List?) ?? const [])
        .map((r) => AutomationFiring.fromJson((r as Map).cast()))
        .toList();
  }

  Future<TemplatePreview> automationPreview(String id) async =>
      TemplatePreview.fromJson(await _api.ownerAutomationPreview(id));

  Future<CommMessage> message(String id) async => CommMessage.fromJson(
    ((await _api.ownerCommunicationMessage(id))['message'] as Map).cast(),
  );

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

  Future<CommTemplate> duplicateTemplate(
    String id, {
    String? gymId,
    String? name,
  }) async => CommTemplate.fromJson(
    ((await _api.ownerDuplicateTemplate(
              id,
              gymId: gymId,
              name: name,
            ))['template']
            as Map)
        .cast(),
  );

  Future<void> archiveTemplate(String id) => _api.ownerArchiveTemplate(id);
}
