// Image source check (security fix 2026-10-29, fitflex-functions#273):
// server-supplied photo strings are drawn only from checked data URIs, our
// own /storage paths and API-host addresses, bundled assets, and (profile
// photos only) the Google sign-in photo host. Anything else shows the
// placeholder and makes no network request.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/components/ff_photo_hero.dart';
import 'package:fitflexmobile/shared/components/ff_remote_image.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/media/media_src.dart';
import 'package:fitflexmobile/shared/widgets/ff_photo_gallery_field.dart';

const _api = 'https://api.fitflex.test';

// Real 1x1 images.
const _pngB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
const _png = 'data:image/png;base64,$_pngB64';
final _jpeg =
    'data:image/jpeg;base64,${base64Encode([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46])}';
final _webp =
    'data:image/webp;base64,${base64Encode([0x52, 0x49, 0x46, 0x46, 0x1A, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x4C])}';

MediaSource? _r(String? src, {String apiBase = _api, bool profile = false}) =>
    resolveMediaSrc(src, apiBase: apiBase, profilePhoto: profile);

String? _url(String src, {String apiBase = _api, bool profile = false}) {
  final s = _r(src, apiBase: apiBase, profile: profile);
  return s is MediaNetwork ? s.uri.toString() : null;
}

void main() {
  setUp(() => MediaSrcPolicy.configure(_api));
  tearDown(MediaSrcPolicy.reset);

  group('data URIs', () {
    test('PNG, JPEG and WebP are decoded on the device', () {
      for (final src in [_png, _jpeg, _webp]) {
        expect(_r(src), isA<MediaBytes>(), reason: src.substring(0, 20));
      }
      expect(
        (_r(_png)! as MediaBytes).bytes.length,
        base64Decode(_pngB64).length,
      );
    });

    test('other types, bad base64 and non-image bytes are refused', () {
      final svg = base64Encode(
        utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"/>'),
      );
      for (final src in [
        'data:image/gif;base64,R0lGODlhAQABAAAAACw=',
        'data:image/svg+xml;base64,$svg',
        'data:image/png;base64,$svg', // SVG bytes labelled PNG
        'data:text/html;base64,PGgxPg==',
        'data:image/png;base64,***',
        'data:image/png;base64,',
        'data:image/png,$_pngB64', // not base64-encoded
        'data:image/PNG;base64,$_pngB64',
        'data:image/png;base64,$_pngB64 trailing',
      ]) {
        expect(_r(src), isNull, reason: src);
      }
    });

    test('more than 2 MB decoded is refused before it is drawn', () {
      final big = Uint8List(kMediaSrcMaxBytes + 1)
        ..setAll(0, base64Decode(_pngB64));
      expect(_r('data:image/png;base64,${base64Encode(big)}'), isNull);
      final ok = Uint8List(kMediaSrcMaxBytes)..setAll(0, base64Decode(_pngB64));
      expect(
        _r('data:image/png;base64,${base64Encode(ok)}'),
        isA<MediaBytes>(),
      );
    });
  });

  group('our own storage', () {
    test('/storage paths resolve against API_BASE', () {
      expect(
        _url('/storage/bafy123/photo-1x.webp'),
        '$_api/storage/bafy123/photo-1x.webp',
      );
      expect(
        _url('/storage/bafy/a.webp', apiBase: '$_api/'),
        '$_api/storage/bafy/a.webp',
      );
      expect(
        _url('/storage/bafy/a.webp', apiBase: 'https://h.test/api'),
        'https://h.test/api/storage/bafy/a.webp',
      );
      expect(
        _url('/storage/bafy/a.webp', apiBase: 'http://localhost:3000'),
        'http://localhost:3000/storage/bafy/a.webp',
      );
    });

    test('other paths, dot segments, escapes and queries are refused', () {
      for (final src in [
        '/storage/../admin/x.png',
        '/storage/bafy/../x.png',
        '/storage/./x.png',
        '/storage/bafy/..',
        '/storage/bafy/a%2f..%2fb.png',
        '/storage/bafy/a%5cb.png',
        '/storage/bafy/a%20b.png', // no % at all
        '/storage/b%61fy/a.png',
        '/storage/bafy/a(1).png',
        '/storage/bafy/a+b.png',
        '/storage/bafy/%2e%2e',
        '/storage/bafy/a.png?x=1',
        '/storage/bafy/a.png#f',
        '/storage/bafy/a b.png',
        '/storage/bafy/a\\b.png',
        '/storage/bafy/sub/a.png',
        '/storage/bafy',
        '/other/bafy/a.png',
        '//evil.example/storage/bafy/a.png',
      ]) {
        expect(_r(src), isNull, reason: src);
      }
    });

    test('nothing resolves against a broken API_BASE', () {
      expect(_r('/storage/bafy/a.webp', apiBase: ''), isNull);
      expect(_r('/storage/bafy/a.webp', apiBase: 'ftp://h.test'), isNull);
      expect(_r('$_api/storage/bafy/a.webp', apiBase: 'not a url'), isNull);
    });
  });

  group('absolute addresses', () {
    test('the API host is allowed (any path, e.g. a private preview)', () {
      expect(_url('$_api/storage/bafy/a.webp'), '$_api/storage/bafy/a.webp');
      expect(
        _url('$_api/vendor/merch/banners/b1/image?w=480'),
        '$_api/vendor/merch/banners/b1/image?w=480',
      );
      expect(_url('https://API.FITFLEX.TEST/storage/bafy/a.webp'), isNotNull);
      expect(
        _url('https://api.fitflex.test:443/storage/bafy/a.webp'),
        isNotNull,
      );
    });

    test('other hosts, schemes, ports and user info are refused', () {
      for (final src in [
        'https://images.unsplash.com/photo-1?w=400',
        'https://evil.example/track.png',
        'https://api.fitflex.test.evil.example/a.png',
        'https://evil.example/https://api.fitflex.test/a.png',
        'https://api.fitflex.test@evil.example/a.png',
        'https://user@api.fitflex.test/a.png',
        'http://api.fitflex.test/storage/bafy/a.webp', // downgraded scheme
        'https://api.fitflex.test:8443/storage/bafy/a.webp',
        '//api.fitflex.test/storage/bafy/a.webp',
        'javascript:alert(1)',
        'file:///etc/passwd',
        'content://media/external/images/1',
        'blob:https://api.fitflex.test/123',
        'a.webp',
        'photo.png',
        '',
        '   ',
      ]) {
        expect(_r(src), isNull, reason: src);
      }
      expect(_r(null), isNull);
    });

    test('Google sign-in photos only for profile photos, https only', () {
      const google = 'https://lh3.googleusercontent.com/a/ACg8ocK=s96-c';
      expect(_r(google), isNull);
      expect(_url(google, profile: true), google);
      expect(_r('http://lh3.googleusercontent.com/a/x', profile: true), isNull);
      expect(
        _r('https://lh4.googleusercontent.com/a/x', profile: true),
        isNull,
      );
      expect(
        _r('https://lh3.googleusercontent.com.evil.example/a', profile: true),
        isNull,
      );
      expect(_r('https://evil.example/a.png', profile: true), isNull);
    });
  });

  test('bundled assets are allowed; traversal is not', () {
    expect(_r('assets/images/gym.webp'), isA<MediaAsset>());
    expect(_r('assets/../secrets.png'), isNull);
    expect(_r('assets/images//x.png'), isNull);
    expect(_r('assets/images/x.svg'), isNull);
  });

  test('headers go to the API host only', () {
    const headers = {'authorization': 'Bearer t'};
    final own = mediaImageProvider(
      '$_api/vendor/merch/banners/b1/image?w=96',
      headers: headers,
    );
    expect(own, isA<NetworkImage>());
    expect((own! as NetworkImage).headers, headers);
    final google = mediaImageProvider(
      'https://lh3.googleusercontent.com/a/x',
      profilePhoto: true,
      headers: headers,
    );
    expect((google! as NetworkImage).headers, isNull);
    expect(
      mediaImageProvider('https://evil.example/a.png', headers: headers),
      isNull,
    );
  });

  test('without configure() the ApiClient default base is used', () {
    MediaSrcPolicy.reset();
    final base = ApiClient.defaultBaseUrl();
    expect(MediaSrcPolicy.apiBase, base);
    expect(isAllowedMediaSrc('$base/storage/bafy/a.webp'), isTrue);
    expect(isAllowedMediaSrc('https://evil.example/a.png'), isFalse);
  });

  group('widgets', () {
    Widget wrap(Widget child) => FFLocaleScope(
      notifier: FFLocale(),
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );

    testWidgets('FFRemoteImage shows the fallback for another host', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const FFRemoteImage(
            src: 'https://evil.example/track.png',
            width: 40,
            height: 40,
            fallback: Text('fallback'),
          ),
        ),
      );
      expect(find.text('fallback'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('FFRemoteImage loads a /storage path from the API host', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const FFRemoteImage(
            src: '/storage/bafy/gym.webp',
            width: 40,
            height: 40,
            fallback: Text('fallback'),
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image is ResizeImage
          ? (image.image as ResizeImage).imageProvider
          : image.image;
      expect(provider, isA<NetworkImage>());
      expect((provider as NetworkImage).url, '$_api/storage/bafy/gym.webp');
    });

    testWidgets('FFRemoteImage switches to the fallback when src changes', (
      tester,
    ) async {
      Widget at(String src) => wrap(
        FFRemoteImage(
          src: src,
          width: 40,
          height: 40,
          fallback: const Text('fb'),
        ),
      );
      await tester.pumpWidget(at(_png));
      expect(find.byType(Image), findsOneWidget);
      await tester.pumpWidget(at('https://evil.example/x.png'));
      expect(find.byType(Image), findsNothing);
      expect(find.text('fb'), findsOneWidget);
    });

    testWidgets('a stored outside URL in the gallery field shows the broken '
        'icon and no network image', (tester) async {
      await tester.pumpWidget(
        wrap(
          FFPhotoGalleryField(
            values: const ['https://evil.example/x.png', _png],
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.byIcon(Icons.broken_image), findsOneWidget);
      final providers = tester
          .widgetList<Image>(find.byType(Image))
          .map(
            (i) => i.image is ResizeImage
                ? (i.image as ResizeImage).imageProvider
                : i.image,
          );
      expect(providers.whereType<NetworkImage>(), isEmpty);
    });

    test('hero network images use the same check', () {
      const box = Size(400, 200);
      expect(
        heroNetworkImageProvider(
          const FFHeroNetworkImage('https://evil.example/hero.webp'),
          box,
          2,
        ),
        isNull,
      );
      final own = heroNetworkImageProvider(
        const FFHeroNetworkImage('$_api/storage/bafy/hero.webp'),
        box,
        2,
      );
      expect(own, isNotNull);
      final inner = own is ResizeImage ? own.imageProvider : own;
      expect((inner! as NetworkImage).url, '$_api/storage/bafy/hero.webp');
    });

    testWidgets('a refused hero address falls back to the bundled photo', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 400,
            height: 240,
            child: FFHeroBand(
              photo: FFHeroPhoto.owner,
              networkImage: FFHeroNetworkImage('https://evil.example/h.webp'),
              headlineLead: 'Lead',
            ),
          ),
        ),
      );
      await tester.pump();
      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        final p = image.image is ResizeImage
            ? (image.image as ResizeImage).imageProvider
            : image.image;
        expect(p, isNot(isA<NetworkImage>()));
      }
    });
  });

  group('refused photo messages', () {
    String msg(Map<String, dynamic> body, {String lang = 'en'}) {
      final locale = FFLocale()..set(Locale(lang));
      return apiErrorMessage(locale, ApiException(400, body));
    }

    test('invalid_media_src says what to do, in English and Swahili', () {
      final body = {
        'error': 'invalid_media_src',
        'field': 'logo',
        'reason': 'scheme_not_allowed',
      };
      expect(msg(body), contains("This photo can't be used"));
      expect(msg(body), isNot(contains('Scheme not allowed')));
      expect(msg(body, lang: 'sw'), contains('Picha hii haiwezi kutumika'));
    });

    test('too large photos say so', () {
      for (final reason in ['too_large', 'image_too_large']) {
        final body = {
          'error': 'invalid_media_src',
          'field': 'images',
          'index': 0,
          'reason': reason,
        };
        expect(msg(body), contains('too large'));
        expect(msg(body, lang: 'sw'), contains('kubwa mno'));
      }
    });

    test('upload_forbidden and rate_limited are mapped', () {
      expect(
        apiErrorMessage(
          FFLocale(),
          ApiException(403, {'error': 'upload_forbidden'}),
        ),
        contains("can't upload photos"),
      );
      expect(
        apiErrorMessage(
          FFLocale()..set(const Locale('sw')),
          ApiException(403, {'error': 'upload_forbidden'}),
        ),
        contains('haiwezi kupakia picha'),
      );
      expect(
        apiErrorMessage(
          FFLocale(),
          ApiException(429, {'error': 'rate_limited', 'retryAfterSeconds': 12}),
        ),
        contains('12 seconds'),
      );
    });
  });
}
