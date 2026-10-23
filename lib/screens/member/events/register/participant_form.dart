import 'package:flutter/material.dart';

import '../../../../shared/components/components.dart';
import '../../../../shared/date_of_birth.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_detail.dart';
import '../../../../shared/events/event_order.dart';
import '../../../../shared/events/events_checkout.dart';
import '../../../../shared/i18n.dart';
import '../event_status.dart';

/// The translated line for a server / local validation problem.
String validationText(BuildContext context, FieldProblem p) {
  final key = 'events.validation.${p.code}';
  var text = context.tr(key);
  if (text == key) text = context.tr('events.validation.unknown');
  final extra = p.extra ?? const {};
  return text
      .replaceFirst('{minAge}', '${extra['minAge'] ?? ''}')
      .replaceFirst('{age}', '${extra['ageOnEventDay'] ?? ''}');
}

/// One repeatable participant card (events S3 spec §5.5): an expandable
/// header, the fields the event collects, a per-card consent row for
/// others, and the read-only verified contact for the member's own place.
class ParticipantForm extends StatefulWidget {
  const ParticipantForm({
    super.key,
    required this.index,
    required this.total,
    required this.participant,
    required this.fields,
    required this.category,
    required this.ticketName,
    required this.problems,
    required this.expanded,
    required this.onToggle,
    required this.onChanged,
    this.consentText = '',
    this.selfHasVerifiedContact = true,
    this.onEditProfile,
    this.onCopyEmergency,
  });

  final int index;
  final int total;
  final EventParticipantInput participant;
  final ParticipantFields fields;
  final EventCategory category;
  final String ticketName;

  /// Field → problem (local and server, merged by the page).
  final Map<String, FieldProblem> problems;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onChanged;

  /// The `purchaser_authorised` consent copy from the quote; the i18n
  /// fallback is used while it has not answered.
  final String consentText;
  final bool selfHasVerifiedContact;
  final VoidCallback? onEditProfile;

  /// "Use my emergency contact" (others, when the self card has one).
  final VoidCallback? onCopyEmergency;

  @override
  State<ParticipantForm> createState() => _ParticipantFormState();
}

class _ParticipantFormState extends State<ParticipantForm> {
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _dob;
  late final TextEditingController _emName;
  late final TextEditingController _emPhone;

  EventParticipantInput get p => widget.participant;

  @override
  void initState() {
    super.initState();
    _first = TextEditingController(text: p.firstName);
    _last = TextEditingController(text: p.lastName);
    _phone = TextEditingController(text: p.phone);
    _email = TextEditingController(text: p.email);
    _dob = TextEditingController(text: p.dateOfBirth);
    _emName = TextEditingController(text: p.emergencyName);
    _emPhone = TextEditingController(text: p.emergencyPhone);
  }

  @override
  void didUpdateWidget(ParticipantForm old) {
    super.didUpdateWidget(old);
    // The page may rewrite a value (copying an emergency contact).
    void sync(TextEditingController c, String v) {
      if (c.text != v) c.text = v;
    }

    sync(_emName, p.emergencyName);
    sync(_emPhone, p.emergencyPhone);
    sync(_dob, p.dateOfBirth);
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _phone, _email, _dob, _emName, _emPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _err(String field) {
    final pr = widget.problems[field];
    return pr == null ? null : validationText(context, pr);
  }

  String _label(String key, FieldPolicy policy) {
    final base = context.tr(key);
    return policy == FieldPolicy.required ? '$base *' : base;
  }

  Future<void> _pickDob() async {
    final picked = await showDateOfBirthPicker(
      context,
      current: parseDateOfBirth(_dob.text.trim()),
      helpText: context.tr('events.participant.dob'),
    );
    if (picked == null || !mounted) return;
    _dob.text = formatDateOfBirth(picked);
    p.dateOfBirth = _dob.text;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final f = widget.fields;
    final count = widget.problems.length;
    final title = context
        .tr('events.participant.title')
        .replaceFirst('{i}', '${widget.index + 1}')
        .replaceFirst('{n}', '${widget.total}')
        .replaceFirst('{category}', widget.category.name)
        .replaceFirst('{ticket}', widget.ticketName);
    final name = [
      p.firstName,
      p.lastName,
    ].where((s) => s.trim().isNotEmpty).join(' ');
    final summary = [
      if (name.isNotEmpty) name,
      if (p.phone.trim().isNotEmpty) _maskPhone(p.phone),
      if (count == 0 && name.isNotEmpty) '✓',
    ].join(' · ');

    final header = Semantics(
      button: true,
      expanded: widget.expanded,
      label: [
        title,
        if (count > 0)
          context.tr('events.participant.toFix').replaceFirst('{n}', '$count')
        else if (name.isNotEmpty)
          context.tr('events.participant.complete'),
      ].join(', '),
      child: InkWell(
        key: Key('participant-header-${widget.index}'),
        onTap: widget.onToggle,
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Expanded(
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: tt.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!widget.expanded && summary.isNotEmpty)
                        Text(
                          summary,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (count > 0)
                Padding(
                  padding: const EdgeInsets.only(right: FFTokens.spacingSm),
                  child: ExcludeSemantics(
                    child: Text(
                      context
                          .tr('events.participant.toFix')
                          .replaceFirst('{n}', '$count'),
                      key: Key('participant-tofix-${widget.index}'),
                      style: tt.labelMedium?.copyWith(
                        color: fuelTextColor(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ExcludeSemantics(
                child: Icon(
                  widget.expanded ? Icons.expand_less : Icons.expand_more,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final body = <Widget>[
      if (p.isSelf && !widget.selfHasVerifiedContact) ...[
        FFAlert(
          key: const Key('participant-need-verified'),
          tone: FFAlertTone.warning,
          message: context.tr('events.participant.needVerified'),
        ),
        if (widget.onEditProfile != null)
          Align(
            alignment: Alignment.centerLeft,
            child: FFButton(
              key: const Key('participant-edit-profile'),
              label: context.tr('events.participant.editProfile'),
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
              onPressed: widget.onEditProfile,
            ),
          ),
        const SizedBox(height: FFTokens.spacingSm),
      ],
      FFTextField(
        key: Key('participant-first-${widget.index}'),
        controller: _first,
        label: '${context.tr('events.participant.firstName')} *',
        semanticsLabel:
            '${context.tr('events.participant.firstName')}, '
            '${context.tr('events.participant.required')}',
        textCapitalization: TextCapitalization.words,
        maxLength: 80,
        errorText: _err('firstName'),
        onChanged: (s) {
          p.firstName = s;
          widget.onChanged();
        },
      ),
      const SizedBox(height: FFTokens.spacingSm),
      FFTextField(
        key: Key('participant-last-${widget.index}'),
        controller: _last,
        label: '${context.tr('events.participant.lastName')} *',
        semanticsLabel:
            '${context.tr('events.participant.lastName')}, '
            '${context.tr('events.participant.required')}',
        textCapitalization: TextCapitalization.words,
        maxLength: 80,
        errorText: _err('lastName'),
        onChanged: (s) {
          p.lastName = s;
          widget.onChanged();
        },
      ),
      if (f.phone != FieldPolicy.off) ...[
        const SizedBox(height: FFTokens.spacingSm),
        FFTextField(
          key: Key('participant-phone-${widget.index}'),
          controller: _phone,
          label: _label('events.participant.phone', f.phone),
          keyboardType: TextInputType.phone,
          readOnly: p.isSelf,
          suffixIcon: p.isSelf ? const Icon(Icons.lock_outline) : null,
          helperText: p.isSelf
              ? context.tr('events.participant.fromProfile')
              : null,
          errorText: _err('phone'),
          onChanged: (s) {
            p.phone = s;
            widget.onChanged();
          },
        ),
      ],
      if (f.email != FieldPolicy.off) ...[
        const SizedBox(height: FFTokens.spacingSm),
        FFTextField(
          key: Key('participant-email-${widget.index}'),
          controller: _email,
          label: _label('events.participant.email', f.email),
          keyboardType: TextInputType.emailAddress,
          readOnly: p.isSelf,
          suffixIcon: p.isSelf ? const Icon(Icons.lock_outline) : null,
          helperText: p.isSelf
              ? context.tr('events.participant.fromProfile')
              : null,
          errorText: _err('email'),
          onChanged: (s) {
            p.email = s;
            widget.onChanged();
          },
        ),
      ],
      if (f.dateOfBirth != FieldPolicy.off) ...[
        const SizedBox(height: FFTokens.spacingSm),
        FFTextField(
          key: Key('participant-dob-${widget.index}'),
          controller: _dob,
          label: _label('events.participant.dob', f.dateOfBirth),
          hint: 'YYYY-MM-DD',
          keyboardType: TextInputType.datetime,
          helperText: widget.category.minAge == null
              ? null
              : context
                    .tr('events.participant.dob.hint')
                    .replaceFirst('{category}', widget.category.name),
          errorText: _err('dateOfBirth'),
          suffixIcon: IconButton(
            key: Key('participant-dob-pick-${widget.index}'),
            tooltip: context.tr('events.participant.dob'),
            icon: const Icon(Icons.calendar_today_outlined),
            onPressed: _pickDob,
          ),
          onChanged: (s) {
            p.dateOfBirth = s;
            widget.onChanged();
          },
        ),
      ],
      if (f.gender != FieldPolicy.off) ...[
        const SizedBox(height: FFTokens.spacingSm),
        FFDropdownField<String>(
          key: Key('participant-gender-${widget.index}'),
          value: p.gender.isEmpty ? '' : p.gender,
          label: _label('events.participant.gender', f.gender),
          isExpanded: true,
          items: [
            DropdownMenuItem(
              value: '',
              child: Text(context.tr('events.participant.gender.none')),
            ),
            for (final g in participantGenders)
              DropdownMenuItem(
                value: g,
                child: Text(context.tr('onboarding.gender_$g')),
              ),
          ],
          onChanged: (g) {
            p.gender = g ?? '';
            widget.onChanged();
          },
        ),
        if (_err('gender') case final e?)
          Text(e, style: tt.bodySmall?.copyWith(color: cs.error)),
      ],
      if (f.kitSize != FieldPolicy.off) ...[
        const SizedBox(height: FFTokens.spacingSm),
        FFDropdownField<String>(
          key: Key('participant-kit-${widget.index}'),
          value: p.kitSize.isEmpty ? '' : p.kitSize,
          label: _label('events.participant.kitSize', f.kitSize),
          isExpanded: true,
          items: [
            DropdownMenuItem(
              value: '',
              child: Text(context.tr('events.participant.notSet')),
            ),
            for (final k in kitSizes)
              DropdownMenuItem(value: k, child: Text(k.toUpperCase())),
          ],
          onChanged: (k) {
            p.kitSize = k ?? '';
            widget.onChanged();
          },
        ),
        if (_err('kitSize') case final e?)
          Text(e, style: tt.bodySmall?.copyWith(color: cs.error)),
      ],
      if (f.emergencyContact != FieldPolicy.off) ...[
        const SizedBox(height: FFTokens.spacingMd),
        Text(
          _label('events.participant.emergency', f.emergencyContact),
          style: tt.titleSmall,
        ),
        Text(
          context.tr('events.participant.emergency.note'),
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        if (widget.onCopyEmergency != null)
          Align(
            alignment: Alignment.centerLeft,
            child: FFButton(
              key: Key('participant-copy-emergency-${widget.index}'),
              label: context.tr('events.participant.emergency.copy'),
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
              onPressed: widget.onCopyEmergency,
            ),
          ),
        const SizedBox(height: FFTokens.spacingSm),
        FFTextField(
          key: Key('participant-emname-${widget.index}'),
          controller: _emName,
          label: context.tr('events.participant.emergency.name'),
          textCapitalization: TextCapitalization.words,
          errorText: _err('emergencyContact'),
          onChanged: (s) {
            p.emergencyName = s;
            widget.onChanged();
          },
        ),
        const SizedBox(height: FFTokens.spacingSm),
        FFTextField(
          key: Key('participant-emphone-${widget.index}'),
          controller: _emPhone,
          label: context.tr('events.participant.emergency.phone'),
          keyboardType: TextInputType.phone,
          onChanged: (s) {
            p.emergencyPhone = s;
            widget.onChanged();
          },
        ),
      ],
      if (!p.isSelf) ...[
        const SizedBox(height: FFTokens.spacingSm),
        Semantics(
          container: true,
          child: CheckboxListTile(
            key: Key('participant-consent-${widget.index}'),
            value: p.consented,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              widget.consentText.isNotEmpty
                  ? widget.consentText
                  : context.tr('events.participant.consent'),
              style: tt.bodySmall,
            ),
            subtitle: _err('consent') == null
                ? null
                : Text(
                    _err('consent')!,
                    style: tt.bodySmall?.copyWith(color: cs.error),
                  ),
            onChanged: (v) {
              p.consented = v ?? false;
              widget.onChanged();
            },
          ),
        ),
      ],
    ];

    return FFCard(
      key: Key('participant-card-${widget.index}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (widget.expanded) ...[
            const SizedBox(height: FFTokens.spacingSm),
            ...body,
          ],
        ],
      ),
    );
  }
}

/// "+255 7•• ••• 678": only the last three digits show in a summary line.
String _maskPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 4) return phone;
  final tail = digits.substring(digits.length - 3);
  return '••• $tail';
}
