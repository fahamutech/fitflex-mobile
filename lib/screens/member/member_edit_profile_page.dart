import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/api_error_message.dart';
import '../../shared/components/components.dart';
import '../../shared/date_of_birth.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import '../../shared/partner_details.dart';
import '../../shared/tone_theme.dart';
import '../../shared/widgets/ff_photo_picker_field.dart';
import '../../shared/widgets/verify_identifier.dart';

/// The translated line for a username reason code, or null for one we don't know.
String? usernameReasonText(BuildContext context, String? code) {
  return switch (code) {
    'invalid_username' => context.tr('username.invalid'),
    'username_reserved' => context.tr('username.reserved'),
    'username_taken' => context.tr('username.taken'),
    'username_released_recently' => context.tr('username.releasedRecently'),
    'username_not_allowed' => context.tr('username.notAllowed'),
    _ => null,
  };
}

/// Opens the member's single profile editor. Resolves to true when anything
/// was saved, so the caller can reload the member.
Future<bool?> openMemberEditProfile(BuildContext context, MemberMeResponse me) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => MemberEditProfilePage(me: me),
    ),
  );
}

enum _Check { idle, checking, available, unavailable }

/// One page for everything a member can change about themselves: photo,
/// personal details, username, fitness goals and level, and preferred
/// workout times. One Save writes it all. Phone and email are shown but
/// only change through Contact details, where the new one is verified.
class MemberEditProfilePage extends StatefulWidget {
  const MemberEditProfilePage({super.key, required this.me});

  final MemberMeResponse me;

  static const goals = [
    'lose_weight',
    'build_muscle',
    'stay_fit',
    'improve_flexibility',
    'stress_relief',
  ];
  static const levels = ['beginner', 'intermediate', 'advanced'];
  static const timeOptions = ['morning', 'afternoon', 'evening'];

  @override
  State<MemberEditProfilePage> createState() => _MemberEditProfilePageState();
}

class _MemberEditProfilePageState extends State<MemberEditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _username;
  late final TextEditingController _height;
  late final TextEditingController _weight;
  late final TextEditingController _dateOfBirth;
  late String _gender;
  late String? _level;
  late final Set<String> _goals;
  late final Set<String> _times;
  String? _photoUrl;

  Timer? _debounce;
  _Check _check = _Check.idle;
  String? _usernameReason;
  String? _usernameError;
  int _seq = 0;

  bool _busy = false;
  String? _error;

  /// The server refused the date of birth (400 invalid_field dateOfBirth).
  String? _dobError;

  MemberSummary get _user => widget.me.user;
  MemberProfile? get _profile => _user.memberProfile;

  bool get _usernameEnabled => widget.me.usernameEnabled;
  String get _currentUsername => widget.me.username ?? '';
  bool get _usernameLocked =>
      widget.me.usernameChangeableAt != null &&
      widget.me.usernameChangeableAt!.isAfter(DateTime.now());
  String get _typedUsername =>
      _username.text.trim().replaceFirst(RegExp(r'^@'), '');
  bool get _usernameUnchanged =>
      _typedUsername.toLowerCase() == _currentUsername.toLowerCase();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _user.displayName ?? '');
    _username = TextEditingController(text: _currentUsername);
    _height = TextEditingController(text: _profile?.heightCm?.toString() ?? '');
    _weight = TextEditingController(text: _profile?.weightKg?.toString() ?? '');
    _dateOfBirth = TextEditingController(
      text: normaliseDateOfBirth(_profile?.dateOfBirth ?? ''),
    );
    _initialDob = _dateOfBirth.text.trim();
    _gender = _profile?.gender ?? '';
    _level = _profile?.fitnessLevel;
    _goals = {
      ...?_profile?.fitnessGoals,
      if ((_profile?.fitnessGoal ?? '').isNotEmpty) _profile!.fitnessGoal!,
    };
    _times = {...?_profile?.preferredWorkoutTimes};
    _photoUrl = _user.photoUrl;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _username.dispose();
    _height.dispose();
    _weight.dispose();
    _dateOfBirth.dispose();
    super.dispose();
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty)
      ? context.tr('onboarding.required')
      : null;

  // ── Username availability ──

  void _onUsernameChanged(String _) {
    _debounce?.cancel();
    setState(() {
      _usernameError = null;
      _usernameReason = null;
      _check = _typedUsername.length >= 3 && !_usernameUnchanged
          ? _Check.checking
          : _Check.idle;
    });
    if (_check != _Check.checking) return;
    _debounce = Timer(const Duration(milliseconds: 400), _runUsernameCheck);
  }

  Future<void> _runUsernameCheck() async {
    final handle = _typedUsername;
    final seq = ++_seq;
    try {
      final res = await AppScope.of(context).api.usernameAvailable(handle);
      if (!mounted || seq != _seq) return;
      setState(() {
        _check = res['available'] == true
            ? _Check.available
            : _Check.unavailable;
        _usernameReason = res['reason']?.toString();
      });
    } catch (_) {
      // The save itself explains any problem; just stop showing "checking".
      if (mounted && seq == _seq) setState(() => _check = _Check.idle);
    }
  }

  String _dateOf(DateTime d) {
    final lang = Localizations.localeOf(context).languageCode;
    return DateFormat('d MMM y', lang).format(d);
  }

  String _usernameApiError(ApiException e) {
    var text = usernameReasonText(context, e.code);
    if (e.code == 'username_cooldown') {
      final next = DateTime.tryParse(
        (e.body is Map ? (e.body as Map)['nextChangeAt'] : null)?.toString() ??
            '',
      )?.toLocal();
      text = context
          .tr('username.cooldown')
          .replaceAll('{date}', next == null ? '' : _dateOf(next));
    }
    return text ?? apiErrorMessage(FFLocaleScope.of(context), e);
  }

  /// Whether the username as typed can go to the server. Unchanged or
  /// locked means "nothing to send"; a known-unavailable name blocks Save.
  bool get _usernameBlocksSave {
    if (!_usernameEnabled || _usernameLocked || _usernameUnchanged) {
      return false;
    }
    if (_typedUsername.isEmpty) return false; // clearing is always allowed
    return _check != _Check.available;
  }

  // ── Date of birth ──

  /// What is wrong with the date of birth (see shared/date_of_birth.dart).
  /// Null for an empty field.
  ///
  /// The field takes typed text, so a value that is not YYYY-MM-DD at all
  /// gets the format message; each message also says why the shop cannot
  /// be personalised until it is fixed (the server fails closed).
  String? _dobProblem(String? value) {
    final text = value?.trim() ?? '';
    final key = dateOfBirthProblemKey(text);
    if (key == null) return null;
    final shown = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)
        ? key
        : 'member.dobFormat';
    return '${context.tr(shown)} ${context.tr('member.dobNoPersonalisation')}';
  }

  /// A stored value that is not valid is flagged as soon as the page opens.
  /// The date of birth as it was when the page opened.
  late final String _initialDob;
  bool get _dobChanged => _dateOfBirth.text.trim() != _initialDob;

  late final bool _storedDobInvalid =
      dateOfBirthProblemKey(_dateOfBirth.text) != null;

  Future<void> _pickDateOfBirth() async {
    final picked = await showDateOfBirthPicker(
      context,
      current: parseDateOfBirth(_dateOfBirth.text.trim()),
      helpText: context.tr('member.dateOfBirth'),
      // Calendar only: the picker's own typed entry follows the device
      // locale (M/D/YYYY in US English). Typing is done in the field
      // itself, always as YYYY-MM-DD.
      entryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) {
        final theme = Theme.of(context);
        const buttons = Size(64, 48);
        return Theme(
          data: theme.copyWith(
            datePickerTheme: theme.datePickerTheme.copyWith(
              // Smaller than the default so a Swahili date fits the header.
              headerHeadlineStyle: theme.textTheme.titleLarge,
              cancelButtonStyle: TextButton.styleFrom(minimumSize: buttons),
              confirmButtonStyle: TextButton.styleFrom(minimumSize: buttons),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dateOfBirth.text = formatDateOfBirth(picked);
      _dobError = null;
    });
  }

  Widget _dateOfBirthField(BuildContext context) {
    final hasValue = _dateOfBirth.text.trim().isNotEmpty;
    return FFTextField(
      key: const Key('edit-profile-dob'),
      controller: _dateOfBirth,
      enabled: !_busy,
      // Typed as YYYY-MM-DD only (digits and dashes, 10 characters).
      keyboardType: TextInputType.datetime,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
        LengthLimitingTextInputFormatter(10),
      ],
      label: context.tr('member.dateOfBirth'),
      hint: 'YYYY-MM-DD',
      helperText: _dobError == null ? 'YYYY-MM-DD' : null,
      errorText: _dobError,
      validator: _dobProblem,
      autovalidateMode: _storedDobInvalid
          ? AutovalidateMode.always
          : AutovalidateMode.onUserInteraction,
      onChanged: (_) {
        if (_dobError != null) setState(() => _dobError = null);
      },
      suffixIcon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasValue)
            IconButton(
              key: const Key('edit-profile-dob-clear'),
              tooltip: context.tr('member.dobClear'),
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.clear),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _dateOfBirth.clear();
                      _dobError = null;
                    }),
            ),
          IconButton(
            key: const Key('edit-profile-dob-pick'),
            tooltip: context.tr('member.dobPick'),
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.calendar_today_outlined),
            onPressed: _busy ? null : _pickDateOfBirth,
          ),
        ],
      ),
    );
  }

  // ── Save ──

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_usernameBlocksSave) {
      setState(() {
        _usernameError =
            usernameReasonText(context, _usernameReason) ??
            context.tr('username.invalid');
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _usernameError = null;
      _dobError = null;
    });
    final api = AppScope.of(context).api;
    var savedAnything = false;
    try {
      final payload = <String, dynamic>{
        'displayName': _name.text.trim(),
        if (_photoUrl != null && _photoUrl!.isNotEmpty) 'photoUrl': _photoUrl,
        'heightCm': _height.text.trim().isEmpty
            ? null
            : num.tryParse(_height.text.trim()),
        'weightKg': _weight.text.trim().isEmpty
            ? null
            : num.tryParse(_weight.text.trim()),
        // POST /me/profile: "" clears the date of birth; leaving it out
        // keeps the stored one (functions#239). Sent only when changed, so
        // a stored date the server now refuses (a Trainer or gym owner
        // under 18, functions#253) never stops the other fields saving.
        if (_dobChanged) 'dateOfBirth': _dateOfBirth.text.trim(),
        'gender': _gender.isEmpty ? null : _gender,
        'fitnessGoals': _goals.toList(),
        'fitnessLevel': _level,
        'preferredWorkoutTimes': _times.toList(),
      };
      await api.updateProfile(payload);
      savedAnything = true;

      if (_usernameEnabled && !_usernameLocked && !_usernameUnchanged) {
        if (_typedUsername.isEmpty) {
          await api.clearUsername();
        } else {
          await api.setUsername(_typedUsername);
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (!savedAnything && isPartnerUnder18Error(e)) {
          _dobError = context.tr('partnerDob.errUnder18');
        } else if (!savedAnything && isDateOfBirthError(e)) {
          _dobError =
              '${context.tr('member.dobInvalid')} '
              '${context.tr('member.dobNoPersonalisation')}';
        } else if (savedAnything) {
          // Profile went through; only the username was refused.
          _usernameError = _usernameApiError(e);
        } else {
          _error = apiErrorMessage(FFLocaleScope.of(context), e);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(FFLocaleScope.of(context), e);
      });
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('member.editProfile')),
        leading: IconButton(
          key: const Key('edit-profile-close'),
          tooltip: context.tr('common.close'),
          icon: const Icon(Icons.close),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            key: const Key('edit-profile-save'),
            // 48dp tall on every platform (web/desktop default to 40).
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.tr('member.save')),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            children: [
              Center(
                child: FFPhotoPickerField(
                  semanticLabel: context.tr('member.photoPick'),
                  value: _photoUrl,
                  onChanged: (value) => setState(() => _photoUrl = value),
                ),
              ),
              const SizedBox(height: FFTokens.spacingMd),

              // Personal details
              FFSectionTitle(context.tr('member.section.personal')),
              FFTextField(
                key: const Key('edit-profile-name'),
                controller: _name,
                label: context.tr('ownerReg.displayName'),
                validator: _required,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              _ContactField(
                fieldKey: const Key('edit-profile-phone'),
                label: context.tr('member.phone'),
                value: _user.phone ?? '',
              ),
              const SizedBox(height: FFTokens.spacingSm),
              _ContactField(
                fieldKey: const Key('edit-profile-email'),
                label: context.tr('member.email'),
                value: _user.email ?? '',
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFDropdownField<String>(
                value: _gender.isEmpty ? null : _gender,
                label: context.tr('onboarding.gender'),
                items: [
                  for (final g in const ['male', 'female', 'other'])
                    DropdownMenuItem(
                      value: g,
                      child: Text(context.tr('onboarding.gender_$g')),
                    ),
                ],
                onChanged: (value) => setState(() => _gender = value ?? ''),
              ),
              const SizedBox(height: FFTokens.spacingSm),
              _dateOfBirthField(context),
              const SizedBox(height: FFTokens.spacingSm),
              Row(
                children: [
                  Expanded(
                    child: FFTextField(
                      controller: _height,
                      keyboardType: TextInputType.number,
                      label: context.tr('member.height'),
                    ),
                  ),
                  const SizedBox(width: FFTokens.spacingSm),
                  Expanded(
                    child: FFTextField(
                      controller: _weight,
                      keyboardType: TextInputType.number,
                      label: context.tr('member.weight'),
                    ),
                  ),
                ],
              ),

              // Username (only when the server has the feature on)
              if (_usernameEnabled) ...[
                const SizedBox(height: FFTokens.spacingLg),
                FFSectionTitle(context.tr('username.title')),
                Text(
                  context.tr('username.visibility'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: FFTokens.spacingSm),
                FFTextField(
                  key: const Key('username-field'),
                  controller: _username,
                  label: context.tr('username.hint'),
                  helperText: _currentUsername.isEmpty
                      ? context.tr('username.rules')
                      : context.tr('username.emptyRemoves'),
                  enabled: !_usernameLocked && !_busy,
                  maxLength: 20,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 16, right: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: 1,
                      child: Text('@'),
                    ),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[A-Za-z0-9._@]'),
                    ),
                  ],
                  onChanged: _onUsernameChanged,
                ),
                ..._usernameStatus(theme),
              ],

              // Fitness goals + level
              const SizedBox(height: FFTokens.spacingLg),
              FFSectionTitle(context.tr('member.section.goals')),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final goal in MemberEditProfilePage.goals)
                    FilterChip(
                      key: Key('goal-$goal'),
                      label: Text(context.tr('onboarding.goal_$goal')),
                      selected: _goals.contains(goal),
                      selectedColor: theme.colorScheme.primary.withValues(
                        alpha: 0.1,
                      ),
                      checkmarkColor: theme.colorScheme.primary,
                      onSelected: (value) => setState(() {
                        if (value) {
                          _goals.add(goal);
                        } else {
                          _goals.remove(goal);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: FFTokens.spacingMd),
              FFDropdownField<String>(
                value: _level,
                label: context.tr('onboarding.fitnessLevel'),
                items: [
                  for (final item in MemberEditProfilePage.levels)
                    DropdownMenuItem(
                      value: item,
                      child: Text(context.tr('onboarding.level_$item')),
                    ),
                ],
                onChanged: (value) => setState(() => _level = value),
              ),

              // Preferred workout times
              const SizedBox(height: FFTokens.spacingLg),
              FFSectionTitle(context.tr('member.section.workoutTimes')),
              for (final time in MemberEditProfilePage.timeOptions)
                CheckboxListTile(
                  key: Key('time-$time'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr('onboarding.time_$time')),
                  value: _times.contains(time),
                  onChanged: (value) => setState(() {
                    if (value == true) {
                      _times.add(time);
                    } else {
                      _times.remove(time);
                    }
                  }),
                ),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                  child: Text(
                    _error!,
                    key: const Key('edit-profile-error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: FFTokens.spacingLg),
              FFButton(
                key: const Key('edit-profile-save-bottom'),
                fullWidth: true,
                label: context.tr('member.save'),
                loading: _busy,
                onPressed: _busy ? null : _save,
              ),
              const SizedBox(height: FFTokens.spacingLg),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _usernameStatus(ThemeData theme) {
    final good = FFToneTheme.of(context).success.fg;
    final line = _usernameError != null
        ? (_usernameError!, theme.colorScheme.error)
        : switch (_check) {
            _Check.checking => (context.tr('username.checking'), null),
            _Check.available => (context.tr('username.available'), good),
            _Check.unavailable => (
              usernameReasonText(context, _usernameReason) ??
                  context.tr('username.invalid'),
              theme.colorScheme.error,
            ),
            _Check.idle => (null, null),
          };
    return [
      if (line.$1 != null)
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingXs),
          child: Text(
            line.$1!,
            key: const Key('username-status'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: line.$2 ?? theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      if (_usernameLocked)
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingXs),
          child: Text(
            context
                .tr('username.cooldown')
                .replaceAll('{date}', _dateOf(widget.me.usernameChangeableAt!)),
            key: const Key('username-cooldown'),
            style: theme.textTheme.bodySmall,
          ),
        ),
    ];
  }
}

/// A phone number or email as it is on the account. Not editable here: a new
/// one is added and verified under Contact details (when the backend has
/// identifier verification on), which the field opens on tap.
class _ContactField extends StatelessWidget {
  const _ContactField({
    required this.fieldKey,
    required this.label,
    required this.value,
  });

  final Key fieldKey;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final canChange = auth.identifiersEnabled;
        return FFTextField(
          key: fieldKey,
          initialValue: value,
          label: label,
          readOnly: true,
          helperText: canChange ? context.tr('member.contactChangeHint') : null,
          suffixIcon: canChange ? const Icon(Icons.chevron_right) : null,
          onTap: canChange
              ? () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ContactDetailsScreen(),
                  ),
                )
              : null,
        );
      },
    );
  }
}
