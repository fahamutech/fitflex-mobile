import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../shared/i18n.dart';
import '../data/communication_models.dart';

/// "5 Oct, 09:30", formatted like dates elsewhere in the owner app.
String formatWhen(BuildContext context, DateTime at) =>
    DateFormat('d MMM, HH:mm').format(at);

/// "5 Oct" — a day, for date-range filters.
String formatDay(DateTime at) => DateFormat('d MMM').format(at);

/// Localised name for a reason a member was skipped on a channel.
String skipReasonLabel(BuildContext context, String reason) {
  const known = {
    'in_app_marketing_off',
    'push_marketing_off',
    'whatsapp_marketing_not_opted_in',
    'whatsapp_opted_out',
    'whatsapp_transactional_off',
    'no_device',
    'no_phone',
    'push_disabled',
    'whatsapp_not_configured',
    'whatsapp_disabled',
    'whatsapp_template_not_approved',
    'invalid_phone',
    'marketing_cap',
  };
  return known.contains(reason) ? context.tr('comms.skip.$reason') : reason;
}

String channelLabel(BuildContext context, CommChannel c) =>
    context.tr('comms.channel.${c.wire}');

IconData channelIcon(CommChannel c) => switch (c) {
  CommChannel.inApp => Icons.inbox_outlined,
  CommChannel.push => Icons.notifications_active_outlined,
  CommChannel.whatsapp => Icons.chat_outlined,
};
