import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../shared/api_error_message.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/widgets/enquiry_thread.dart';

/// Trainer › Enquiries: member enquiries and "interested" members, most recent
/// activity first, with unread ones marked. Open conversations first; closed
/// ones on their own tab.
class TrainerEnquiriesPage extends StatefulWidget {
  const TrainerEnquiriesPage({super.key});

  @override
  State<TrainerEnquiriesPage> createState() => _TrainerEnquiriesPageState();
}

class _TrainerEnquiriesPageState extends State<TrainerEnquiriesPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _started = false;
  String? _error;
  String _tab = 'open';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await AppScope.of(context).api.trainerEngagements();
      if (!mounted) return;
      setState(() {
        _rows = rows.whereType<Map<String, dynamic>>().toList();
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.tr('owner.errorGeneric');
      });
    }
  }

  Future<void> _open(Map<String, dynamic> row) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrainerEnquiryPage(engagement: row),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _rows
        .where((r) => (r['status'] == 'closed') == (_tab == 'closed'))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('trainer.enquiries'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [
            FFSegmented(
              key: const Key('enquiries-tab'),
              value: _tab,
              options: [
                ('open', context.tr('enquiry.tabOpen')),
                ('closed', context.tr('enquiry.tabClosed')),
              ],
              onChanged: (v) => setState(() => _tab = v),
            ),
            const SizedBox(height: FFTokens.spacingMd),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: FFSpinner(size: 28)),
              )
            else if (_error != null)
              FFAlert(message: _error!, tone: FFAlertTone.error)
            else if (visible.isEmpty)
              FFEmptyState(title: context.tr('trainer.noEnquiries'))
            else
              ...visible.map(
                (r) => _EnquiryTile(row: r, onTap: () => _open(r)),
              ),
          ],
        ),
      ),
    );
  }
}

class _EnquiryTile extends StatelessWidget {
  const _EnquiryTile({required this.row, required this.onTap});

  final Map<String, dynamic> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final member = row['member'] as Map?;
    final name =
        member?['displayName']?.toString() ?? context.tr('trainer.member');
    final messages = EnquiryMessage.listFrom(row);
    final last = messages.lastOrNull;
    final unread = row['unread'] == true;
    final interest = row['type'] == 'interest';
    final preview = last == null
        ? context.tr('trainer.interested')
        : '${last.from == 'trainer' ? '${context.tr('enquiry.you')}: ' : ''}${last.text}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: Key('enquiry-${row['id']}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: FFCard(
          child: Row(
            children: [
              FFAvatar(
                name: name,
                src: member?['photoUrl']?.toString(),
                size: FFAvatarSize.md,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: unread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        FFBadge(
                          label: context.tr(
                            interest
                                ? 'enquiry.kindInterest'
                                : 'enquiry.kindEnquiry',
                          ),
                          tone: interest
                              ? FFBadgeTone.warning
                              : FFBadgeTone.brand,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: unread ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread)
                Container(
                  key: Key('enquiry-unread-${row['id']}'),
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(left: 8),
                  decoration: const BoxDecoration(
                    color: FFTokens.brand500,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One conversation with a member: read it, reply (with quick replies), call
/// or email them, or close it.
class TrainerEnquiryPage extends StatefulWidget {
  const TrainerEnquiryPage({super.key, required this.engagement});

  final Map<String, dynamic> engagement;

  @override
  State<TrainerEnquiryPage> createState() => _TrainerEnquiryPageState();
}

class _TrainerEnquiryPageState extends State<TrainerEnquiryPage> {
  late Map<String, dynamic> _e = widget.engagement;
  bool _started = false;

  String get _id => _e['id'].toString();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (_e['unread'] == true || _e['status'] == 'new') _markRead();
  }

  Future<void> _markRead() async {
    try {
      final updated = await AppScope.of(context).api.trainerReadEngagement(_id);
      if (mounted) setState(() => _e = updated);
    } catch (_) {
      // Reading still works; the unread dot just stays until next time.
    }
  }

  Future<bool> _reply(String text) async {
    try {
      final updated = await AppScope.of(
        context,
      ).api.trainerReplyEngagement(_id, text);
      if (mounted) setState(() => _e = updated);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage(FFLocaleScope.of(context), e))),
        );
      }
      return false;
    }
  }

  Future<void> _close() async {
    try {
      final updated = await AppScope.of(
        context,
      ).api.trainerCloseEngagement(_id);
      if (!mounted) return;
      setState(() => _e = updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('enquiry.closed'))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('owner.errorGeneric'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = _e['member'] as Map?;
    final name =
        member?['displayName']?.toString() ?? context.tr('trainer.member');
    final email = member?['email']?.toString().trim() ?? '';
    final phone = member?['phone']?.toString().trim() ?? '';
    final messages = EnquiryMessage.listFrom(_e);
    final closed = _e['status'] == 'closed';
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          if (phone.isNotEmpty)
            IconButton(
              key: const Key('enquiry-call'),
              tooltip: context.tr('enquiry.call'),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
              icon: const Icon(Icons.phone_outlined),
            ),
          if (email.isNotEmpty)
            IconButton(
              key: const Key('enquiry-email'),
              tooltip: context.tr('enquiry.email'),
              onPressed: () => launchUrl(
                Uri(scheme: 'mailto', path: email),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.email_outlined),
            ),
          if (!closed)
            TextButton(
              key: const Key('enquiry-close'),
              onPressed: _close,
              child: Text(context.tr('enquiry.close')),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                key: const Key('enquiry-thread'),
                reverse: true,
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: [
                  if (messages.isEmpty)
                    FFAlert(
                      message: context
                          .tr('enquiry.interestBody')
                          .replaceAll('{name}', name),
                      tone: FFAlertTone.info,
                    ),
                  EnquiryThread(messages: messages, me: 'trainer'),
                  if (closed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        context.tr('enquiry.closedNote'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ].reversed.toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FFTokens.spacingMd,
                0,
                FFTokens.spacingMd,
                FFTokens.spacingMd,
              ),
              child: EnquiryReplyBox(
                onSend: _reply,
                suggestions: [
                  context.tr('enquiry.quick1'),
                  context.tr('enquiry.quick2'),
                  context.tr('enquiry.quick3'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
