import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app_scope.dart';
import '../../../../shared/api_error_message.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_order.dart';
import '../../../../shared/events/events_checkout.dart';
import '../../../../shared/i18n.dart';

/// `self` | `selfOthers` | `others` (events S3 spec §5.4).
const registrationModes = ['self', 'selfOthers', 'others'];

/// Where the corporate info card sends coordinators (portal org / HR login).
const kFitFlexPortalUrl = 'https://fitflex-portal.web.app/';

/// What step 2 holds.
class RegistrationWho {
  const RegistrationWho({
    this.mode = 'self',
    this.teamOn = false,
    this.teamMode = 'create',
    this.teamName = '',
    this.teamType = 'community',
    this.teamCode = '',
    this.teamFound,
  });

  final String mode;
  final bool teamOn;

  /// `create` | `join`.
  final String teamMode;
  final String teamName;
  final String teamType;
  final String teamCode;

  /// The team a code check found (join mode).
  final EventTeam? teamFound;

  /// The team part of the order body, or null when none / incomplete.
  TeamChoice? get team {
    if (!teamOn) return null;
    if (teamMode == 'create') {
      return teamName.trim().isEmpty
          ? null
          : TeamChoice.create(name: teamName, teamType: teamType);
    }
    return teamFound == null ? null : TeamChoice.join(teamCode);
  }

  /// Team wanted but not yet complete (blocks Continue).
  bool get teamIncomplete => teamOn && team == null;

  RegistrationWho copyWith({
    String? mode,
    bool? teamOn,
    String? teamMode,
    String? teamName,
    String? teamType,
    String? teamCode,
    EventTeam? teamFound,
    bool clearFound = false,
  }) => RegistrationWho(
    mode: mode ?? this.mode,
    teamOn: teamOn ?? this.teamOn,
    teamMode: teamMode ?? this.teamMode,
    teamName: teamName ?? this.teamName,
    teamType: teamType ?? this.teamType,
    teamCode: teamCode ?? this.teamCode,
    teamFound: clearFound ? null : (teamFound ?? this.teamFound),
  );
}

/// Step 2: the radio group of who is registering, the optional Team
/// sub-card and the corporate info card.
class RegistrationModeTiles extends StatefulWidget {
  const RegistrationModeTiles({
    super.key,
    required this.eventId,
    required this.places,
    required this.value,
    required this.onChanged,
    this.teamsEnabled = false,
    this.corporateEnabled = false,
  });

  final String eventId;
  final int places;
  final RegistrationWho value;
  final ValueChanged<RegistrationWho> onChanged;
  final bool teamsEnabled;
  final bool corporateEnabled;

  @override
  State<RegistrationModeTiles> createState() => _RegistrationModeTilesState();
}

class _RegistrationModeTilesState extends State<RegistrationModeTiles> {
  late final _name = TextEditingController(text: widget.value.teamName);
  late final _code = TextEditingController(
    text: formatTeamCode(widget.value.teamCode),
  );
  bool _checking = false;
  String? _lookupError;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final code = normalizeTeamCode(_code.text);
    if (!teamCodeLooksValid(code)) {
      setState(() => _lookupError = context.tr('error.reason.teamNotFound'));
      return;
    }
    setState(() {
      _checking = true;
      _lookupError = null;
    });
    final locale = FFLocaleScope.of(context);
    try {
      final res = await AppScope.of(
        context,
      ).api.lookupEventTeam(eventId: widget.eventId, joinCode: code);
      if (!mounted) return;
      final team = res['team'] is Map
          ? EventTeam.fromJson(res['team'] as Map)
          : null;
      widget.onChanged(
        widget.value.copyWith(
          teamCode: code,
          teamFound: team,
          teamMode: 'join',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _lookupError = errorMessage(locale, e));
      widget.onChanged(widget.value.copyWith(teamCode: code, clearFound: true));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final n = widget.places;

    Widget tile(String mode, String key) => Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: FFChoiceTile(
        key: Key('mode-$key'),
        title: context.tr('events.register.mode.$key'),
        subtitle: context.tr('events.register.mode.$key.hint'),
        selected: v.mode == mode,
        minHeight: 56,
        onSelected: () => widget.onChanged(v.copyWith(mode: mode)),
      ),
    );

    final whoTiles = [
      if (n == 1) tile('self', 'self'),
      if (n >= 2) tile('selfOthers', 'selfOthers'),
      tile('others', 'others'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: context.tr('events.register.step.who'),
          child: Column(children: whoTiles),
        ),
        if (widget.teamsEnabled) ...[
          FFChoiceTile(
            key: const Key('mode-team'),
            title: context.tr('events.register.mode.team'),
            subtitle: context.tr('events.register.mode.team.hint'),
            selected: v.teamOn,
            minHeight: 56,
            onSelected: () => widget.onChanged(v.copyWith(teamOn: !v.teamOn)),
          ),
          if (v.teamOn) ...[
            const SizedBox(height: FFTokens.spacingSm),
            FFCard(
              key: const Key('team-card'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FFSegmented(
                    value: v.teamMode,
                    options: [
                      ('create', context.tr('events.team.create')),
                      ('join', context.tr('events.team.join')),
                    ],
                    onChanged: (m) => widget.onChanged(v.copyWith(teamMode: m)),
                  ),
                  const SizedBox(height: FFTokens.spacingMd),
                  if (v.teamMode == 'create') ...[
                    FFTextField(
                      key: const Key('team-name'),
                      controller: _name,
                      label: context.tr('events.team.name'),
                      maxLength: 120,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (s) =>
                          widget.onChanged(v.copyWith(teamName: s)),
                    ),
                    const SizedBox(height: FFTokens.spacingSm),
                    FFDropdownField<String>(
                      key: const Key('team-type'),
                      value: v.teamType,
                      label: context.tr('events.team.type'),
                      isExpanded: true,
                      items: [
                        for (final t in const ['club', 'community'])
                          DropdownMenuItem(
                            value: t,
                            child: Text(context.tr('events.team.type.$t')),
                          ),
                      ],
                      onChanged: (t) => widget.onChanged(
                        v.copyWith(teamType: t ?? 'community'),
                      ),
                    ),
                  ] else ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: FFTextField(
                            key: const Key('team-code'),
                            controller: _code,
                            label: context.tr('events.team.code'),
                            hint: 'AB12-CD34',
                            errorText: _lookupError,
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [_TeamCodeFormatter()],
                            onChanged: (s) {
                              _lookupError = null;
                              widget.onChanged(
                                v.copyWith(teamCode: s, clearFound: true),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: FFTokens.spacingSm),
                        FFButton(
                          key: const Key('team-check'),
                          label: context.tr('events.team.check'),
                          variant: FFButtonVariant.secondary,
                          loading: _checking,
                          onPressed: _check,
                        ),
                      ],
                    ),
                    if (v.teamFound case final team?)
                      Padding(
                        padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                        child: Text(
                          context
                              .tr('events.team.found')
                              .replaceFirst('{name}', team.name)
                              .replaceFirst('{n}', '${team.memberCount}')
                              .replaceFirst('{max}', '${team.maxMembers}'),
                          key: const Key('team-found'),
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ],
        if (widget.corporateEnabled) ...[
          const SizedBox(height: FFTokens.spacingMd),
          FFCard(
            key: const Key('mode-corporate'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('events.register.mode.corporate'),
                  style: tt.titleSmall,
                ),
                const SizedBox(height: FFTokens.spacingXs),
                Text(
                  context.tr('events.register.mode.corporate.body'),
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: FFTokens.spacingSm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FFButton(
                    key: const Key('corporate-copy'),
                    label: context.tr('events.register.mode.corporate.copy'),
                    variant: FFButtonVariant.ghost,
                    size: FFButtonSize.sm,
                    icon: Icons.link,
                    onPressed: () async {
                      final snack = FFSnack.of(context);
                      final copied = context.tr('common.copied');
                      await Clipboard.setData(
                        const ClipboardData(text: kFitFlexPortalUrl),
                      );
                      snack.success(copied);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Upper-cases and groups a team code as "AB12-CD34" while typing.
class _TeamCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = normalizeTeamCode(newValue.text);
    final clipped = raw.length > 8 ? raw.substring(0, 8) : raw;
    final text = formatTeamCode(clipped);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
