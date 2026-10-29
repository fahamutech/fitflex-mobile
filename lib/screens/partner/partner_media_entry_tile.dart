import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../shared/components/components.dart';
import '../../shared/i18n.dart';
import '../../shared/partner_media/partner_media_flag.dart';
import '../../shared/partner_media/partner_media_models.dart';
import '../../shared/partner_media/partner_media_store.dart';

/// The "Home photo and logo" settings entry (spec §41.1). Nothing at all
/// with `PARTNER_MEDIA_UI` off. With [askServer] (gym staff with `gyms`,
/// vendor staff) it stays hidden until `GET /partner/media` answers
/// `canEdit: true`, so it never flickers into a disabled tile.
class PartnerMediaEntryTile extends StatefulWidget {
  const PartnerMediaEntryTile({
    super.key,
    required this.side,
    this.gymId,
    this.gymName,
    this.askServer = false,
  });

  /// `gym`, `trainer` or `vendor`.
  final String side;
  final String? gymId;

  /// Owners with two or more gyms: "For {gym}".
  final String? gymName;
  final bool askServer;

  @override
  State<PartnerMediaEntryTile> createState() => _PartnerMediaEntryTileState();
}

class _PartnerMediaEntryTileState extends State<PartnerMediaEntryTile> {
  bool? _canEdit;
  String? _askedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ask();
  }

  @override
  void didUpdateWidget(PartnerMediaEntryTile old) {
    super.didUpdateWidget(old);
    if (old.gymId != widget.gymId || old.askServer != widget.askServer) _ask();
  }

  Future<void> _ask() async {
    if (!partnerMediaUi || !widget.askServer) return;
    final key = '${widget.side}|${widget.gymId}';
    if (_askedFor == key) return;
    _askedFor = key;
    _canEdit = null;
    try {
      final raw = await AppScope.of(
        context,
      ).api.partnerMedia(gymId: widget.side == 'gym' ? widget.gymId : null);
      final o = PartnerMediaOverview.tryParse(raw);
      if (mounted && _askedFor == key) setState(() => _canEdit = o?.canEdit);
    } catch (_) {
      if (mounted && _askedFor == key) setState(() => _canEdit = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!partnerMediaUi) return const SizedBox.shrink();
    if (PartnerMediaStore.instance?.featureOff ?? false) {
      return const SizedBox.shrink();
    }
    if (widget.askServer && _canEdit != true) return const SizedBox.shrink();
    final key = switch (widget.side) {
      'gym' => 'owner-brand-media',
      'trainer' => 'trainer-brand-media',
      _ => 'vendor-brand-media',
    };
    final subtitle = widget.side == 'vendor'
        ? context.tr('partnerMedia.entryHintVendor')
        : widget.gymName != null
        ? context
              .tr('partnerMedia.entryForGym')
              .replaceAll('{gym}', widget.gymName!)
        : context.tr('partnerMedia.entryHint');
    return FFActionTile(
      key: Key(key),
      icon: Icons.add_photo_alternate_outlined,
      title: context.tr('partnerMedia.title'),
      subtitle: subtitle,
      onTap: () =>
          context.push(partnerMediaRoute(widget.side, gymId: widget.gymId)),
    );
  }
}
