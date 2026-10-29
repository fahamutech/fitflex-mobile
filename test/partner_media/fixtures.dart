// Shared answers for the partner photo and logo tests, shaped as
// fitflex-functions#277 docs/partner-media-api.md says.
import 'dart:convert';
import 'dart:typed_data';

/// A real 1x1 transparent PNG.
final Uint8List onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

const confirmation = {
  'version': '2026-10-29.draft1',
  'status': 'draft_pending_counsel',
  'rights': {
    'en':
        'I took this photo or have the right to use it, and FitFlex may show it on my home in the FitFlex app.',
    'sw':
        'Nilipiga picha hii au nina haki ya kuitumia, na FitFlex inaweza kuionyesha kwenye ukurasa wangu wa mwanzo kwenye app ya FitFlex.',
  },
  'ownLogo': {
    'en': "This is my own business's logo, not another brand's.",
    'sw': 'Hii ni nembo ya biashara yangu mwenyewe, si ya chapa nyingine.',
  },
};

const limits = {
  'hero': {
    'minWidth': 1080,
    'maxBytes': 15728640,
    'types': [
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/heic',
      'image/heif',
    ],
  },
  'logo': {
    'minSide': 256,
    'maxBytes': 2097152,
    'types': ['image/png', 'image/jpeg', 'image/webp'],
  },
};

Map<String, dynamic> heroItem({
  String id = 'pmd_hero1',
  String status = 'live',
  String origin = 'partner',
  bool bright = false,
  Map<String, dynamic>? takedown,
  int bytes = 120000,
}) => {
  'id': id,
  'kind': 'hero',
  'subject': {'type': 'trainer', 'id': 'trn_1', 'name': 'Asha'},
  'status': status,
  'origin': origin,
  'review': {'state': 'to_review', 'at': null},
  'takedown': takedown,
  'width': 1080,
  'height': 720,
  'focal': {'x': 0.5, 'y': -0.25},
  'bright': bright,
  'files': status == 'live'
      ? {
          'x2': '/partner/media/$id/file?variant=x2',
          'x1': '/partner/media/$id/file?variant=x1',
        }
      : {},
  'bytes': status == 'live' ? {'x2': bytes, 'x1': 40000} : {},
  'createdAt': '2026-10-29T08:00:00.000Z',
  'updatedAt': '2026-10-29T08:00:00.000Z',
  'revision': 1,
};

Map<String, dynamic> logoItem({
  String id = 'pmd_logo1',
  String status = 'live',
  String plate = 'dark',
  Map<String, dynamic>? takedown,
}) => {
  'id': id,
  'kind': 'logo',
  'subject': {'type': 'trainer', 'id': 'trn_1', 'name': 'Asha'},
  'status': status,
  'origin': 'partner',
  'review': {'state': 'to_review', 'at': null},
  'takedown': takedown,
  'width': 512,
  'height': 256,
  'plate': plate,
  'plateChoice': 'auto',
  'files': status == 'live'
      ? {
          'logo256': '/partner/media/$id/file?variant=logo256',
          'logo128': '/partner/media/$id/file?variant=logo128',
        }
      : {},
  'bytes': status == 'live' ? {'logo256': 9000, 'logo128': 4000} : {},
  'createdAt': '2026-10-29T08:00:00.000Z',
  'revision': 1,
};

Map<String, dynamic> overview({
  String type = 'trainer',
  String id = 'trn_1',
  String? name = 'Asha',
  bool canEdit = true,
  Map<String, dynamic>? hero,
  Map<String, dynamic>? heroDown,
  Map<String, dynamic>? logo,
  Map<String, dynamic>? logoDown,
  Map<String, dynamic> conf = confirmation,
}) => {
  'subject': {'type': type, 'id': id, 'name': name},
  'canEdit': canEdit,
  'hero': {'live': hero, 'lastTakedown': heroDown},
  'logo': {'live': logo, 'lastTakedown': logoDown},
  'confirmation': conf,
  'limits': limits,
};
