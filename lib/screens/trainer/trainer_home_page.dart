import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import '../../shared/inbox/inbox_pages.dart';
import '../../shared/models.dart';
import '../../shared/root_back_navigation.dart';
import '../../shared/widgets/profile_form_page.dart';
import '../../shared/widgets/shop_browse_page.dart';
import '../../shared/widgets/social_links.dart';
import '../../shared/widgets/trainer_form_page.dart';
import '../language_screen.dart';
import '../member/member_message_settings_page.dart';
import 'trainer_clients_tab.dart';
import 'trainer_gyms_tab.dart';
import 'trainer_schedule.dart';
import 'widgets/clients_digest.dart';
import 'widgets/trainer_sheets.dart';

/// Standalone trainer dashboard shown after trainer is onboarded.
class TrainerHomePage extends StatefulWidget {
  const TrainerHomePage({super.key});

  @override
  State<TrainerHomePage> createState() => _TrainerHomePageState();
}

class _TrainerHomePageState extends State<TrainerHomePage> {
  Map<String, dynamic>? _me;
  List<Map<String, dynamic>> _trainers = [];

  /// The trainer's own profile from /trainer/me (works before approval too).
  Map<String, dynamic>? _profile;
  bool _started = false;
  int _tabIndex = 0;
  final _gymsTabKey = GlobalKey<TrainerGymsTabState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _refreshMe(),
      _refreshTrainers(),
      _refreshProfile(),
      if (_gymsTabKey.currentState != null) _gymsTabKey.currentState!.refresh(),
      AppScope.of(context).inbox?.load() ?? Future<void>.value(),
    ]);
  }

  Future<void> _refreshProfile() async {
    try {
      final res = await AppScope.of(context).api.trainerMe();
      if (mounted) setState(() => _profile = res);
    } on ApiException {
      // ignore — falls back to the public trainer list
    }
  }

  Future<void> _refreshMe() async {
    try {
      final res = await AppScope.of(context).api.me();
      if (mounted) setState(() => _me = res);
    } on ApiException {
      // ignore
    }
  }

  Future<void> _refreshTrainers() async {
    try {
      final res = await AppScope.of(context).api.listTrainers();
      if (mounted) {
        setState(() => _trainers = res.cast<Map<String, dynamic>>());
      }
    } on ApiException {
      // ignore
    }
  }

  String get _displayName {
    final user = (_me?['user'] as Map?) ?? AppScope.of(context).auth.user;
    return (user?['displayName'] ??
            user?['email'] ??
            user?['phone'] ??
            'Trainer')
        .toString();
  }

  Map<String, dynamic>? get _myProfile {
    if (_profile != null) return _profile;
    final email = AppScope.of(context).auth.user?['email']?.toString();
    return _trainers.where((t) => t['email']?.toString() == email).firstOrNull;
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('home.signout')),
        content: Text(context.tr('confirm.signout')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('member.cancel')),
          ),
          FilledButton(
            key: const Key('trainer-confirm-sign-out'),
            style: FilledButton.styleFrom(backgroundColor: FFTokens.error500),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('home.signout')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await AppScope.of(context).auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LanguageScreen()),
      (_) => false,
    );
  }

  void _openWhatsAppSupport() {
    final uri = Uri.parse('https://wa.me/255786670499');
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showEditProfileDialog() async {
    final user = Map<String, dynamic>.from(
      (_me?['user'] as Map?) ?? AppScope.of(context).auth.user ?? const {},
    );
    final saved = await openProfileForm(
      context,
      title: context.tr('member.editDetails'),
      initialUser: user,
      onSignOut: _signOut,
    );
    if (saved == true) {
      if (!mounted) return;
      await _refreshMe();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('member.profileUpdated'))),
      );
    }
  }

  /// C8 — edit professional details (rate, specialties, bio, photo) via the
  /// trainer profile endpoint.
  Future<void> _editProfessionalProfile() async {
    final trainer = _myProfile;
    if (trainer == null) return;
    final payload = await openTrainerForm(
      context,
      title: context.tr('trainer.editProfessional'),
      initial: trainer,
    );
    if (payload == null || !mounted) return;
    try {
      final result = await AppScope.of(
        context,
      ).api.trainerUpdateProfile(payload);
      if (!mounted) return;
      final updated = result['trainer'] ?? result;
      if (updated is Map<String, dynamic>) {
        setState(() {
          _profile = updated;
          _trainers = _trainers
              .map((item) => item['id'] == updated['id'] ? updated : item)
              .toList();
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('member.profileUpdated'))),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      final body = e.body;
      final invalidSocial =
          body is Map && body['error'] == 'invalid_social_handle';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              invalidSocial ? 'social.invalidHandle' : 'owner.errorGeneric',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _showEngagementInbox() async {
    try {
      final rows = await AppScope.of(context).api.trainerEngagements();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .7,
            child: ListView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                Text(
                  sheetContext.tr('trainer.enquiries'),
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: FFTokens.spacingMd),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(sheetContext.tr('trainer.noEnquiries')),
                  )
                else
                  ...rows.whereType<Map>().map((row) {
                    final member = row['member'] as Map?;
                    final isInterest = row['type'] == 'interest';
                    final email = member?['email']?.toString().trim() ?? '';
                    final phone = member?['phone']?.toString().trim() ?? '';
                    final contact = [
                      if (email.isNotEmpty) email,
                      if (phone.isNotEmpty) phone,
                    ].join(' · ');
                    final replyUri = email.isNotEmpty
                        ? Uri(scheme: 'mailto', path: email)
                        : phone.isNotEmpty
                        ? Uri(scheme: 'tel', path: phone)
                        : null;
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          isInterest
                              ? Icons.favorite_outline
                              : Icons.chat_bubble_outline,
                        ),
                        title: Text(
                          member?['displayName']?.toString() ??
                              sheetContext.tr('trainer.member'),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row['message']?.toString() ??
                                  (isInterest
                                      ? sheetContext.tr('trainer.interested')
                                      : ''),
                            ),
                            if (contact.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${sheetContext.tr('trainer.contact')}: $contact',
                              ),
                            ],
                          ],
                        ),
                        trailing: replyUri == null
                            ? null
                            : IconButton(
                                key: Key('trainer-reply-${row['id']}'),
                                tooltip: sheetContext.tr('trainer.reply'),
                                onPressed: () => launchUrl(
                                  replyUri,
                                  mode: LaunchMode.externalApplication,
                                ),
                                icon: Icon(
                                  email.isNotEmpty
                                      ? Icons.email_outlined
                                      : Icons.phone_outlined,
                                ),
                              ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      );
    } on ApiException {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('owner.errorGeneric'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        handleRootBack(didPop: didPop);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(context.tr('trainer.dashboard')),
          // Bookings, pass approvals, and FitFlex promotions and news.
          actions: const [InboxBellButton(), ThemeToggleButton()],
        ),
        body: RefreshIndicator(
          onRefresh: _refreshAll,
          child: IndexedStack(
            index: _tabIndex,
            children: [
              _dashboardTab(),
              const TrainerClientsTab(),
              const ShopBrowseBody(),
              TrainerGymsTab(
                key: _gymsTabKey,
                onProfileChanged: _refreshProfile,
              ),
              _profileTab(),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tabIndex,
          onDestinationSelected: (index) => setState(() => _tabIndex = index),
          destinations: [
            NavigationDestination(
              key: const Key('trainer-nav-home'),
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: context.tr('member.home'),
            ),
            NavigationDestination(
              key: const Key('trainer-nav-clients'),
              icon: const Icon(Icons.groups_outlined),
              selectedIcon: const Icon(Icons.groups),
              label: context.tr('clients.title'),
            ),
            NavigationDestination(
              key: const Key('trainer-nav-shop'),
              icon: const Icon(Icons.storefront_outlined),
              selectedIcon: const Icon(Icons.storefront),
              label: context.tr('member.shop'),
            ),
            NavigationDestination(
              key: const Key('trainer-nav-gyms'),
              icon: const Icon(Icons.fitness_center_outlined),
              selectedIcon: const Icon(Icons.fitness_center),
              label: context.tr('trainer.gyms'),
            ),
            NavigationDestination(
              key: const Key('trainer-nav-profile'),
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: context.tr('trainer.profile'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabScroll(List<Widget> children) => ListView(
    padding: const EdgeInsets.all(FFTokens.spacingLg),
    children: children,
  );

  Widget _dashboardTab() {
    final trainer = _myProfile;
    final socials = SocialLinks.fromJson(trainer?['socialLinks']);
    final gyms = (trainer?['gyms'] as List?)?.whereType<Map>().toList() ?? [];
    return _tabScroll([
      Text(
        context.tr('trainer.dashboardBody'),
        style: TextStyle(
          color: Theme.of(context).textTheme.bodySmall?.color,
          height: 1.35,
        ),
      ),
      const SizedBox(height: 14),
      FFCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('trainer.profile'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              trainer?['displayName']?.toString() ?? _displayName,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              (trainer?['specialties'] as List? ?? []).join(' / '),
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FFPill(
                  key: const Key('trainer-rate-per-session'),
                  label:
                      '${formatCurrency(trainer?['hourlyRateTzs'] as num? ?? 0, currency: trainer?['sessionRateCurrency'] as String? ?? 'TZS')}${context.tr('trainerReg.perSession')}',
                ),
                const Spacer(),
                SocialLinksRow(links: socials, compact: true),
              ],
            ),
            if (trainer != null && socials.isEmpty)
              TextButton.icon(
                key: const Key('trainer-add-socials'),
                onPressed: _editProfessionalProfile,
                icon: const Icon(Icons.add_link, size: 18),
                label: Text(context.tr('social.addPrompt')),
              ),
          ],
        ),
      ),
      ClientsDigest(onOpenClients: () => setState(() => _tabIndex = 1)),
      const SizedBox(height: 12),
      FFMetricCard(
        value: '${gyms.length}',
        label: context.tr('trainer.linkedGymsCount'),
      ),
      _section(context.tr('trainer.sessions')),
      FFActionTile(
        key: const Key('trainer-tile-sessions'),
        icon: Icons.event_available,
        title: context.tr('trainer.todaySessions'),
        onTap: () => showTrainerSessionsSheet(context),
      ),
      FFActionTile(
        key: const Key('trainer-tile-earnings'),
        icon: Icons.payments_outlined,
        title: context.tr('trainer.earnings'),
        onTap: () => showTrainerEarningsSheet(context),
      ),
      FFActionTile(
        key: const Key('trainer-engagement-inbox'),
        icon: Icons.mark_email_unread_outlined,
        title: context.tr('trainer.enquiries'),
        onTap: _showEngagementInbox,
      ),
      FFActionTile(
        key: const Key('trainer-tile-schedule'),
        icon: Icons.calendar_month_outlined,
        title: context.tr('cal.mySchedule'),
        subtitle: context.tr('trainer.scheduleTileHint'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const TrainerSessionsPage()),
        ),
      ),
    ]);
  }

  Widget _profileTab() => _tabScroll([
    Text(
      context.tr('trainer.profile'),
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    const SizedBox(height: 12),
    FFActionTile(
      key: const Key('trainer-edit-account'),
      icon: Icons.edit_outlined,
      title: context.tr('trainer.editProfile'),
      onTap: _showEditProfileDialog,
    ),
    FFActionTile(
      key: const Key('trainer-tile-professional'),
      icon: Icons.workspace_premium_outlined,
      title: context.tr('trainer.editProfessional'),
      onTap: _editProfessionalProfile,
    ),
    FFActionTile(
      key: const Key('trainer-verification'),
      icon: Icons.verified_user_outlined,
      title: context.tr('kyc.entry.title'),
      subtitle: context.tr('kyc.entry.subtitle'),
      onTap: () => context.push('/verification'),
    ),
    FFActionTile(
      key: const Key('trainer-message-settings'),
      icon: Icons.notifications_outlined,
      title: context.tr('msgPrefs.title'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const MemberMessageSettingsPage(),
        ),
      ),
    ),
    FFActionTile(
      key: const Key('trainer-help'),
      icon: Icons.help_outline,
      title: context.tr('member.help'),
      onTap: _openWhatsAppSupport,
    ),
    const SizedBox(height: 16),
    OutlinedButton.icon(
      key: const Key('trainer-sign-out'),
      onPressed: _signOut,
      icon: const Icon(Icons.logout),
      label: Text(context.tr('home.signout')),
    ),
  ]);

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    ),
  );
}
