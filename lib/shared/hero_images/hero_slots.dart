import '../components/ff_photo_footer.dart' show fnv1a32;
import '../components/ff_photo_hero.dart';

/// The slot id of `fitflex-functions` `src/shared/hero-slots.mjs` for each
/// bundled photo. The hero names match the backend registry one to one;
/// every footer photo is in the one `footerPool` slot. `portalLogin` is the
/// portal's and never read here.
const Map<FFHeroPhoto, String> heroSlotOf = {
  FFHeroPhoto.language: 'language',
  FFHeroPhoto.signIn: 'signIn',
  FFHeroPhoto.signUp: 'signUp',
  FFHeroPhoto.role: 'role',
  FFHeroPhoto.pin: 'pin',
  FFHeroPhoto.homeStart: 'homeStart',
  FFHeroPhoto.homePass: 'homePass',
  FFHeroPhoto.profile: 'profile',
  FFHeroPhoto.upgrade: 'upgrade',
  FFHeroPhoto.activityToday: 'activityToday',
  FFHeroPhoto.activityTraining: 'activityTraining',
  FFHeroPhoto.activityChallenges: 'activityChallenges',
  FFHeroPhoto.activityProgress: 'activityProgress',
  FFHeroPhoto.gyms: 'gyms',
  FFHeroPhoto.trainers: 'trainers',
  FFHeroPhoto.shop: 'shop',
  FFHeroPhoto.trainer: 'trainer',
  FFHeroPhoto.vendor: 'vendor',
  FFHeroPhoto.owner: 'owner',
  FFHeroPhoto.footerStretch: kFooterPoolSlot,
  FFHeroPhoto.footerRooftop: kFooterPoolSlot,
  FFHeroPhoto.footerHydration: kFooterPoolSlot,
  FFHeroPhoto.footerNightHall: kFooterPoolSlot,
};

const String kFooterPoolSlot = 'footerPool';

/// Every mobile slot the app understands (the manifest's other slots are
/// ignored).
final Set<String> kMobileHeroSlots = heroSlotOf.values.toSet();

/// Screens shown before sign-in (and the PIN screens), downloaded for
/// everyone.
const List<String> kPreSignInSlots = [
  'language',
  'signIn',
  'signUp',
  'role',
  'pin',
];

const List<String> _memberSlots = [
  'homeStart',
  'homePass',
  'gyms',
  'trainers',
  'shop',
  'profile',
  'upgrade',
  'activityToday',
  'activityTraining',
  'activityChallenges',
  'activityProgress',
];

/// The slots worth downloading for this session, most useful first: the
/// signed-in role's screens, then the pre-sign-in screens, then the footer
/// pool (only when the footer is on). Signed out: the pre-sign-in screens
/// only.
List<String> relevantHeroSlots({
  required bool signedIn,
  required String? role,
  required bool footer,
}) {
  if (!signedIn) return kPreSignInSlots;
  final own = switch (role) {
    'member' => _memberSlots,
    'trainer' => const ['trainer'],
    'gym_operator' || 'gym_staff' => const ['owner'],
    'vendor' || 'vendor_staff' => const ['vendor'],
    _ => const <String>[],
  };
  return [
    ...own,
    ...kPreSignInSlots,
    if (footer && own.isNotEmpty) kFooterPoolSlot,
  ];
}

/// The day's pick for [slot] out of [count] photos (D-5: a new photo per
/// day): FNV-1a over "date|slot", so it is the same on every platform and
/// every run (never `String.hashCode`). [salt] spreads footers by page.
int heroRotationIndex(DateTime day, String slot, int count, {String? salt}) {
  if (count <= 1) return 0;
  return fnv1a32('${heroDayKey(day)}|$slot${salt == null ? '' : '|$salt'}') %
      count;
}

/// The local calendar day, e.g. "2026-10-20".
String heroDayKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';
