import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:eatset/models/place.dart';
import 'package:eatset/models/place_photo.dart';
import 'package:eatset/screens/place_details_sheet.dart';
import 'package:eatset/services/photo_memory_cache.dart';
import 'package:eatset/services/place_photos_service.dart';
import 'package:eatset/services/places_service.dart';
import 'package:eatset/services/storage_service.dart';
import 'package:eatset/widgets/place_photo_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const shop = Place(id: 'a', name: '甲店', lat: 25, lng: 121);
const other = Place(id: 'b', name: '乙店', lat: 25, lng: 121);
const demo = Place(id: 'demo_a', name: '示範', lat: 25, lng: 121, isDemo: true);

// A generated single-color PNG, used only to exercise decoding in tests.
final pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGPYXu7yHwAFzQJyQRqgsAAAAABJRU5ErkJggg==',
);
Map<String, dynamic> photoJson(String id, String name) => {
  'name': 'places/$id/photos/$name',
  'authorAttributions': [
    {'displayName': '攝影者甲', 'uri': '//maps.google.com/maps/contrib/author-a'},
    {
      'displayName': '攝影者乙',
      'uri': 'https://maps.google.com/maps/contrib/author-b',
    },
  ],
  'googleMapsUri': 'https://maps.google.com/photo/$name',
  'flagContentUri': 'https://maps.google.com/report/$name',
};

http.Response jsonResponse(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class FakePhotos extends PlacePhotosService {
  FakePhotos() : super(baseUrl: 'https://api.example');
  int lists = 0;
  final requested = <String>[];
  bool fail = false;
  bool corrupt = false;
  List<String> names = ['one', 'two'];
  Completer<Uint8List>? slowFirst;
  Completer<Uint8List>? slowSecond;
  @override
  Future<List<PlacePhoto>> fetchPhotos(Place place) async {
    lists++;
    if (fail) throw const PhotoLoadException();
    return names
        .map(
          (name) => PlacePhoto.fromGoogle(photoJson(place.id, name), place.id)!,
        )
        .toList();
  }

  @override
  Future<List<PlacePhoto>> refreshPhotos(Place place) => fetchPhotos(place);

  @override
  Future<Uint8List> fetchImage(
    PlacePhoto photo, {
    PhotoSize size = PhotoSize.card,
  }) async {
    requested.add(photo.name);
    if (photo.name == 'places/a/photos/one' && slowFirst != null) {
      return slowFirst!.future;
    }
    if (photo.name == 'places/a/photos/two' && slowSecond != null) {
      return slowSecond!.future;
    }
    if (corrupt) return Uint8List.fromList([1, 2, 3]);
    return pixel;
  }
}

Widget gallery(
  Place place,
  PlacePhotosService service, {
  Future<bool> Function(Uri)? open,
  double scale = 1,
  bool compact = false,
  bool thumbnail = false,
  bool autoLoad = true,
  Duration delay = Duration.zero,
  bool offline = false,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: PlacePhotoGallery(
        place: place,
        service: service,
        openLink: open,
        compact: compact,
        thumbnail: thumbnail,
        autoLoad: autoLoad,
        autoLoadDelay: delay,
        offline: offline,
      ),
    ),
  ),
);

Future<void> settleImages(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(
    () async => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}

void main() {
  // The photo cache is process-wide by design; keep tests independent.
  setUp(PhotoMemoryCache.shared.clear);
  for (final compact in [false, true]) {
    testWidgets(
      'gallery only loads three photos on demand (compact=$compact)',
      (tester) async {
        final photos = FakePhotos()
          ..names = ['one', 'two', 'three', 'four', 'five'];
        await tester.pumpWidget(gallery(shop, photos, compact: compact));
        await settleImages(tester);
        expect(photos.requested, hasLength(1));
        expect(find.text('1 / 3'), findsOneWidget);
        await tester.tap(find.byTooltip('下一張照片'));
        await settleImages(tester);
        await tester.tap(find.byTooltip('下一張照片'));
        await settleImages(tester);
        expect(find.text('3 / 3'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.chevron_right),
              )
              .onPressed,
          isNull,
        );
        expect(photos.requested, [
          'places/a/photos/one',
          'places/a/photos/two',
          'places/a/photos/three',
        ]);
      },
    );
  }
  testWidgets('manual thumbnails request nothing until explicitly opened', (
    tester,
  ) async {
    final service = FakePhotos();
    await tester.pumpWidget(
      gallery(shop, service, thumbnail: true, autoLoad: false),
    );
    await tester.pumpAndSettle();
    expect(service.lists, 0);
    expect(service.requested, isEmpty);
    await tester.tap(find.text('查看照片'));
    await settleImages(tester);
    expect(service.lists, 1);
    expect(service.requested, ['places/a/photos/one']);
    await tester.pumpWidget(
      gallery(shop, service, thumbnail: true, autoLoad: false),
    );
    await settleImages(tester);
    expect(service.requested, hasLength(1));
    await tester.pumpWidget(
      gallery(other, service, thumbnail: true, autoLoad: false),
    );
    await tester.pumpAndSettle();
    expect(service.lists, 1);
    expect(find.text('查看照片'), findsOneWidget);
  });

  testWidgets(
    'repeated paging taps cannot download the same pending photo twice',
    (tester) async {
      final pending = Completer<Uint8List>();
      final service = FakePhotos()..slowSecond = pending;
      await tester.pumpWidget(gallery(shop, service));
      await settleImages(tester);
      await tester.tap(find.byTooltip('下一張照片'));
      await tester.tap(find.byTooltip('下一張照片'));
      await tester.pump();
      expect(service.requested, ['places/a/photos/one', 'places/a/photos/two']);
      final previous = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left),
      );
      expect(previous.onPressed, isNull);
      pending.complete(pixel);
      await settleImages(tester);
      expect(find.text('2 / 2'), findsOneWidget);
    },
  );

  testWidgets(
    'fresh bundled metadata needs only one image request and is never persisted',
    (tester) async {
      final requests = <String>[];
      final place = PlacesService.parsePlace({
        'id': 'a',
        'displayName': {'text': '甲店'},
        'location': {'latitude': 25, 'longitude': 121},
        'photos': [
          {...photoJson('a', 'one'), 'token': 'signed-token'},
        ],
        'photosExpiresAt': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
      });
      final service = PlacePhotosService(
        baseUrl: 'https://api.example',
        client: MockClient((r) async {
          requests.add(r.url.path);
          expect(jsonDecode(r.body), {'token': 'signed-token'});
          return http.Response.bytes(
            pixel,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      addTearDown(service.dispose);
      await tester.pumpWidget(gallery(place, service));
      await settleImages(tester);
      expect(requests, ['/v1/photo']);
      expect(find.text('攝影：攝影者甲'), findsOneWidget);
      expect(place.toStorageJson(), {'id': 'a', 'isDemo': false});
      expect(jsonEncode(place.toJson()), isNot(contains('signed-token')));
      expect(place.copyWith(distanceMeters: 10).photos, place.photos);
    },
  );

  test(
    'expired bundled tokens refresh metadata while empty photo lists do not',
    () async {
      var requests = 0;
      final service = PlacePhotosService(
        baseUrl: 'https://api.example',
        client: MockClient((r) async {
          requests++;
          expect(r.url.path, '/v1/places/a/photos');
          return jsonResponse({
            'id': 'a',
            'photos': [
              {...photoJson('a', 'two'), 'token': 'fresh-token'},
            ],
          });
        }),
      );
      addTearDown(service.dispose);
      final noPhotos = Place(
        id: 'a',
        name: '甲店',
        lat: 25,
        lng: 121,
        photos: [],
        photosExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      expect(await service.fetchPhotos(noPhotos), isEmpty);
      expect(requests, 0);
      final expired = Place(
        id: 'a',
        name: '甲店',
        lat: 25,
        lng: 121,
        photos: [],
        photosExpiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect((await service.fetchPhotos(expired)).single.token, 'fresh-token');
      expect(requests, 1);
      expect(
        (await service.refreshPhotos(noPhotos)).single.token,
        'fresh-token',
      );
      expect(requests, 2);
    },
  );
  for (final thumbnail in [false, true]) {
    testWidgets(
      'compact photo keeps authors and retry (thumbnail=$thumbnail)',
      (tester) async {
        final service = FakePhotos()..corrupt = true;
        await tester.pumpWidget(
          gallery(shop, service, compact: true, thumbnail: thumbnail),
        );
        await settleImages(tester);
        expect(find.byTooltip('重試照片'), findsOneWidget);
        service.corrupt = false;
        await tester.tap(find.byTooltip('重試照片'));
        await settleImages(tester);
        expect(find.byTooltip('重試照片'), findsNothing);
        expect(find.text('Google Maps'), findsOneWidget);
        expect(find.text('攝影：攝影者甲'), findsOneWidget);
        expect(find.text('攝影：攝影者乙'), findsOneWidget);
        await tester.tap(find.byTooltip('照片來源與回報'));
        await tester.pumpAndSettle();
        expect(find.text('查看照片來源'), findsOneWidget);
        expect(find.text('回報照片'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final blockedStage in ['metadata', 'image']) {
    testWidgets('shows daily limit from $blockedStage and recovers on retry', (
      tester,
    ) async {
      var blocked = true;
      final service = PlacePhotosService(
        baseUrl: 'https://api.example',
        client: MockClient((request) async {
          final metadata = request.url.path.endsWith('/photos');
          if (blocked && (blockedStage == 'metadata' ? metadata : !metadata)) {
            return jsonResponse({
              'error': {'code': 'DAILY_LIMIT'},
            }, 429);
          }
          if (metadata) {
            return jsonResponse({
              'id': 'a',
              'photos': [
                {...photoJson('a', 'one'), 'token': 'signed-token'},
              ],
            });
          }
          return http.Response.bytes(
            pixel,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      addTearDown(service.dispose);
      await tester.pumpWidget(gallery(shop, service));
      await tester.pumpAndSettle();
      expect(find.textContaining('今日店家查詢額度已用完'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      blocked = false;
      await tester.tap(find.byTooltip('重試照片'));
      await settleImages(tester);
      expect(find.textContaining('今日店家查詢額度已用完'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });
  }

  testWidgets('fresh details do not reload the same restaurant photo', (
    tester,
  ) async {
    final photos = FakePhotos();
    await tester.pumpWidget(gallery(shop, photos));
    await settleImages(tester);
    await tester.tap(find.byTooltip('下一張照片'));
    await settleImages(tester);
    final updated = Place(
      id: shop.id,
      name: shop.name,
      lat: shop.lat,
      lng: shop.lng,
      fetchedAt: DateTime.now(),
    );
    await tester.pumpWidget(gallery(updated, photos));
    await settleImages(tester);
    expect(photos.lists, 1);
    expect(photos.requested.length, 2);
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('details wait for refresh before mounting a photo gallery', (
    tester,
  ) async {
    final ready = Completer<Place>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaceDetailsSheet(
            place: shop,
            refreshPlace: () => ready.future,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(PlacePhotoGallery), findsNothing);
    ready.complete(demo);
    await tester.pumpAndSettle();
    expect(find.byType(PlacePhotoGallery), findsOneWidget);
  });

  test('no backend and Demo never call the network', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return jsonResponse({});
    });
    expect(
      await PlacePhotosService(client: client, baseUrl: '').fetchPhotos(shop),
      isEmpty,
    );
    expect(
      await PlacePhotosService(
        client: client,
        baseUrl: 'https://api.example',
      ).fetchPhotos(demo),
      isEmpty,
    );
    expect(calls, 0);
  });

  test(
    'metadata and image requests go only to backend without credentials',
    () async {
      final paths = <String>[];
      final service = PlacePhotosService(
        baseUrl: 'https://api.example',
        client: MockClient((r) async {
          paths.add(r.url.path);
          expect(r.url.host, 'api.example');
          expect(
            r.headers.keys.map((k) => k.toLowerCase()),
            isNot(contains('x-goog-api-key')),
          );
          if (r.url.path == '/v1/places/a/photos') {
            return jsonResponse({
              'id': 'a',
              'photos': [
                {...photoJson('a', 'one'), 'token': 'signed-short-lived-token'},
                photoJson('b', 'wrong'),
              ],
            });
          }
          expect(r.method, 'POST');
          expect(jsonDecode(r.body), {'token': 'signed-short-lived-token'});
          return http.Response.bytes(
            pixel,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      final photos = await service.fetchPhotos(shop);
      expect(photos, hasLength(1));
      expect(photos.single.authors, hasLength(2));
      expect(photos.single.authors.first.uri!.scheme, 'https');
      expect(await service.fetchImage(photos.single), pixel);
      expect(paths, ['/v1/places/a/photos', '/v1/photo']);
      expect(safePhotoLink('javascript:alert(1)'), isNull);
    },
  );

  test('backend errors and missing photo token do not leak details', () async {
    var calls = 0;
    final service = PlacePhotosService(
      baseUrl: 'https://api.example',
      client: MockClient((_) async {
        calls++;
        return http.Response('sensitive upstream body', 502);
      }),
    );
    await expectLater(
      service.fetchPhotos(shop),
      throwsA(isA<PhotoLoadException>()),
    );
    await expectLater(
      service.fetchImage(const PlacePhoto(name: 'places/a/photos/x')),
      throwsA(isA<PhotoLoadException>()),
    );
    expect(calls, 1);
  });

  test('photos are never added to persisted favorites', () async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().saveFavorites([shop]);
    final sp = await SharedPreferences.getInstance();
    expect(jsonDecode(sp.getString('eatset_favorites')!), [
      {'id': 'a', 'isDemo': false},
    ]);
  });

  testWidgets(
    'photos decode, page on demand, show all credits and open their source',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = FakePhotos();
      Uri? opened;
      await tester.pumpWidget(
        gallery(
          shop,
          service,
          scale: 2,
          open: (uri) async {
            opened = uri;
            return true;
          },
        ),
      );
      await settleImages(tester);
      expect(service.requested, ['places/a/photos/one']);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('攝影：攝影者甲'), findsOneWidget);
      expect(find.text('攝影：攝影者乙'), findsOneWidget);
      expect(find.text('Google Maps'), findsOneWidget);
      expect(find.textContaining('顧客食物照'), findsNothing);
      await tester.tap(find.byTooltip('下一張照片'));
      await settleImages(tester);
      expect(service.requested, ['places/a/photos/one', 'places/a/photos/two']);
      expect(find.text('2 / 2'), findsOneWidget);
      await tester.ensureVisible(find.text('查看照片來源'));
      await tester.tap(find.text('查看照片來源'));
      await tester.pumpAndSettle();
      expect(opened.toString(), 'https://maps.google.com/photo/two');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late response from previous restaurant cannot replace current photo',
    (tester) async {
      final service = FakePhotos()..slowFirst = Completer<Uint8List>();
      await tester.pumpWidget(gallery(shop, service));
      await tester.pump();
      expect(service.requested, ['places/a/photos/one']);
      await tester.pumpWidget(gallery(other, service));
      await settleImages(tester);
      service.slowFirst!.complete(Uint8List.fromList([1, 2, 3]));
      await settleImages(tester);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.semanticLabel, startsWith('乙店'));
      expect((image.image as MemoryImage).bytes, pixel);
      expect(find.byTooltip('重試照片'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retry refreshes metadata, and Demo does not pretend to have food photos',
    (tester) async {
      final service = FakePhotos()..fail = true;
      await tester.pumpWidget(gallery(shop, service));
      await tester.pumpAndSettle();
      expect(find.byTooltip('重試照片'), findsOneWidget);
      service.fail = false;
      await tester.tap(find.byTooltip('重試照片'));
      await settleImages(tester);
      expect(service.lists, 2);
      expect(find.byType(Image), findsOneWidget);
      await tester.pumpWidget(gallery(demo, service));
      await tester.pumpAndSettle();
      expect(find.text('示範店家沒有實景照片'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(service.lists, 2);
    },
  );

  testWidgets('corrupt image keeps a retry option at large text size', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      gallery(shop, FakePhotos()..corrupt = true, scale: 2),
    );
    await settleImages(tester);
    expect(find.byTooltip('重試照片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  group('cost controls', () {
    Place placeWithPhoto({DateTime? expires, DateTime? fetchedAt}) => Place(
      id: 'a',
      name: '甲店',
      lat: 25,
      lng: 121,
      fetchedAt: fetchedAt,
      photos: [
        PlacePhoto.fromGoogle({...photoJson('a', 'one'), 'token': 't1'}, 'a')!,
      ],
      photosExpiresAt:
          expires ?? DateTime.now().add(const Duration(minutes: 20)),
    );

    PlacePhotosService counting(List<String> bodies, {int busy = 0}) {
      var busyLeft = busy;
      return PlacePhotosService(
        baseUrl: 'https://api.example',
        client: MockClient((r) async {
          if (r.url.path == '/v1/photo') {
            bodies.add(r.body);
            if (busyLeft-- > 0) {
              return jsonResponse({
                'error': {'code': 'BUSY'},
              }, 503);
            }
            return http.Response.bytes(
              pixel,
              200,
              headers: {'content-type': 'image/png'},
            );
          }
          return jsonResponse({'id': 'a', 'photos': []});
        }),
      )..retryDelay = Duration.zero;
    }

    test('cache: LRU size limit, recency, expiry', () {
      var now = DateTime(2026, 9, 19, 12);
      final cache = PhotoMemoryCache(
        maxEntries: 2,
        maxAge: const Duration(minutes: 10),
        now: () => now,
      );
      cache.put('a', pixel);
      cache.put('b', pixel);
      expect(cache.get('a'), isNotNull); // a is now most recent
      cache.put('c', pixel); // evicts b, the least recent
      expect(cache.contains('b'), isFalse);
      expect(cache.contains('a'), isTrue);
      now = now.add(const Duration(minutes: 11));
      expect(cache.contains('a'), isFalse);
      expect(cache.get('c'), isNull);
    });

    test(
      'the same photo is billed once; thumbnails are served from a card',
      () async {
        final bodies = <String>[];
        final service = counting(bodies);
        addTearDown(service.dispose);
        final photo = placeWithPhoto().photos!.first;
        await service.fetchImage(photo);
        await service.fetchImage(photo);
        await service.fetchImage(photo, size: PhotoSize.thumb);
        expect(bodies, ['{"token":"t1"}']);
      },
    );

    test(
      'thumbnails ask for the small size and are cached separately',
      () async {
        final bodies = <String>[];
        final service = counting(bodies);
        addTearDown(service.dispose);
        final photo = placeWithPhoto().photos!.first;
        await service.fetchImage(photo, size: PhotoSize.thumb);
        await service.fetchImage(photo, size: PhotoSize.thumb);
        expect(bodies, ['{"token":"t1","size":"thumb"}']);
        await service.fetchImage(
          photo,
        ); // a card is a different, larger request
        expect(bodies, hasLength(2));
      },
    );

    test('a busy server is retried once, then reported plainly', () async {
      final bodies = <String>[];
      final once = counting(bodies, busy: 1);
      addTearDown(once.dispose);
      final photo = placeWithPhoto().photos!.first;
      expect(await once.fetchImage(photo), pixel);
      expect(bodies, hasLength(2));

      PhotoMemoryCache.shared.clear();
      final twice = counting(<String>[], busy: 2);
      addTearDown(twice.dispose);
      await expectLater(
        twice.fetchImage(photo),
        throwsA(
          isA<PhotoLoadException>()
              .having((e) => e.code, 'code', 'BUSY')
              .having((e) => e.message, 'message', contains('忙碌')),
        ),
      );
    });

    test(
      'a photo already in memory needs no metadata lookup even after its token expires',
      () async {
        final bodies = <String>[];
        final service = counting(bodies);
        addTearDown(service.dispose);
        final fresh = placeWithPhoto();
        await service.fetchImage(fresh.photos!.first);
        final expired = placeWithPhoto(
          expires: DateTime.now().subtract(const Duration(minutes: 1)),
        );
        expect(service.hasCachedFirstPhoto(expired), isTrue);
        expect(await service.fetchPhotos(expired), hasLength(1));
        expect(bodies, hasLength(1));
      },
    );

    testWidgets(
      'auto-load waits until the card settles, and a swap cancels it',
      (tester) async {
        final photos = FakePhotos();
        const wait = Duration(milliseconds: 350);
        await tester.pumpWidget(gallery(shop, photos, delay: wait));
        await tester.pump(const Duration(milliseconds: 100));
        expect(photos.lists, 0);
        await tester.pumpWidget(gallery(other, photos, delay: wait));
        await tester.pump(const Duration(milliseconds: 300));
        expect(photos.lists, 0, reason: 'the first card was swapped away');
        await tester.pump(const Duration(milliseconds: 200));
        await settleImages(tester);
        expect(photos.lists, 1);
        expect(photos.requested, ['places/b/photos/one']);
      },
    );

    testWidgets('a cached photo shows without a tap and without a request', (
      tester,
    ) async {
      final bodies = <String>[];
      final service = counting(bodies);
      addTearDown(service.dispose);
      final place = placeWithPhoto();
      await service.fetchImage(place.photos!.first);
      await tester.pumpWidget(
        gallery(place, service, thumbnail: true, autoLoad: false),
      );
      await settleImages(tester);
      expect(find.text('查看照片'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      expect(bodies, hasLength(1));
    });

    for (final compact in [false, true]) {
      testWidgets(
        'swipe pages photos and tap opens a closable full view (compact=$compact)',
        (tester) async {
          final photos = FakePhotos();
          await tester.pumpWidget(gallery(shop, photos, compact: compact));
          await settleImages(tester);
          await tester.fling(find.byType(Image), const Offset(-300, 0), 1200);
          await settleImages(tester);
          expect(find.text('2 / 2'), findsOneWidget);
          await tester.fling(find.byType(Image), const Offset(300, 0), 1200);
          await settleImages(tester);
          expect(find.text('1 / 2'), findsOneWidget);
          await tester.tap(find.byType(Image));
          await tester.pumpAndSettle();
          expect(find.byTooltip('關閉'), findsOneWidget);
          await tester.tap(find.byTooltip('關閉'));
          await tester.pumpAndSettle();
          expect(find.byTooltip('關閉'), findsNothing);
        },
      );

      testWidgets(
        'an expiring place keeps showing its photo (compact=$compact)',
        (tester) async {
          final photos = FakePhotos();
          await tester.pumpWidget(gallery(shop, photos, compact: compact));
          await settleImages(tester);
          final stale = Place(
            id: 'a',
            name: '甲店',
            lat: 25,
            lng: 121,
            fetchedAt: DateTime.now().subtract(const Duration(minutes: 10)),
          );
          await tester.pumpWidget(gallery(stale, photos, compact: compact));
          await settleImages(tester);
          expect(find.byType(Image), findsOneWidget);
          expect(find.text('更新店家資訊後可看照片'), findsNothing);
        },
      );
    }

    testWidgets(
      'the photo area keeps one height while loading and once loaded',
      (tester) async {
        final pending = Completer<Uint8List>();
        final photos = FakePhotos()..slowFirst = pending;
        await tester.pumpWidget(gallery(shop, photos, compact: true));
        await tester.pump();
        await tester.pump();
        final loading = tester.getSize(find.byType(LayoutBuilder).last).height;
        pending.complete(pixel);
        await settleImages(tester);
        final loaded = tester.getSize(find.byType(LayoutBuilder).last).height;
        expect(loaded, loading);
      },
    );
  });
  group('quiet failures and retries', () {
    Place withToken(String token) => Place(
      id: 'a',
      name: '甲店',
      lat: 25,
      lng: 121,
      photos: [
        PlacePhoto.fromGoogle({...photoJson('a', 'one'), 'token': token}, 'a')!,
      ],
      photosExpiresAt: DateTime.now().add(const Duration(minutes: 20)),
    );

    http.Response image(Uint8List bytes) =>
        http.Response.bytes(bytes, 200, headers: {'content-type': 'image/png'});

    testWidgets(
      'retrying a failed picture asks for the picture only, never the photo list',
      (tester) async {
        final paths = <String>[];
        var fail = true;
        final service = PlacePhotosService(
          baseUrl: 'https://api.example',
          client: MockClient((r) async {
            paths.add(r.url.path);
            if (fail) throw http.ClientException('offline');
            return image(pixel);
          }),
        )..retryDelay = Duration.zero;
        addTearDown(service.dispose);
        await tester.pumpWidget(
          gallery(withToken('t1'), service, compact: true),
        );
        await settleImages(tester);
        expect(find.text('沒有網路 · 點一下重試'), findsOneWidget);
        fail = false;
        await tester.tap(find.byTooltip('重試照片'));
        await settleImages(tester);
        expect(find.byType(Image), findsOneWidget);
        expect(find.byTooltip('重試照片'), findsNothing);
        // One quiet automatic retry, then the user's tap: three picture
        // requests, and not a single photo-list lookup.
        expect(paths, ['/v1/photo', '/v1/photo', '/v1/photo']);
      },
    );

    testWidgets(
      'an expired token is replaced behind the spinner without ever showing an error',
      (tester) async {
        final paths = <String>[];
        var sawFailure = false;
        final service = PlacePhotosService(
          baseUrl: 'https://api.example',
          client: MockClient((r) async {
            paths.add(r.url.path);
            if (r.url.path == '/v1/photo') {
              final token = jsonDecode(r.body)['token'];
              if (token == 'old') {
                return jsonResponse({
                  'error': {'code': 'INVALID_PHOTO'},
                }, 403);
              }
              return image(pixel);
            }
            return jsonResponse({
              'id': 'a',
              'photos': [
                {...photoJson('a', 'one'), 'token': 'fresh'},
              ],
            });
          }),
        );
        addTearDown(service.dispose);
        await tester.pumpWidget(
          gallery(withToken('old'), service, compact: true),
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          if (find.byTooltip('重試照片').evaluate().isNotEmpty) sawFailure = true;
        }
        await settleImages(tester);
        expect(sawFailure, isFalse);
        expect(find.byType(Image), findsOneWidget);
        expect(paths, ['/v1/photo', '/v1/places/a/photos', '/v1/photo']);
      },
    );

    testWidgets(
      'a picture that will not decode is dropped from memory so retry gets a fresh copy',
      (tester) async {
        var served = 0;
        final service = PlacePhotosService(
          baseUrl: 'https://api.example',
          client: MockClient((r) async {
            served++;
            return image(served == 1 ? Uint8List.fromList([1, 2, 3]) : pixel);
          }),
        );
        addTearDown(service.dispose);
        await tester.pumpWidget(
          gallery(withToken('t1'), service, compact: true),
        );
        await settleImages(tester);
        expect(find.byTooltip('重試照片'), findsOneWidget);
        await tester.tap(find.byTooltip('重試照片'));
        await settleImages(tester);
        expect(served, 2, reason: 'not served from memory');
        expect(find.byTooltip('重試照片'), findsNothing);
        expect(find.byType(Image), findsOneWidget);
      },
    );

    testWidgets(
      'a quota message is short inside the picture and in full underneath',
      (tester) async {
        final service = PlacePhotosService(
          baseUrl: 'https://api.example',
          client: MockClient(
            (r) async => jsonResponse({
              'error': {'code': 'DAILY_LIMIT'},
            }, 429),
          ),
        );
        addTearDown(service.dispose);
        await tester.pumpWidget(
          gallery(withToken('t1'), service, compact: true),
        );
        await settleImages(tester);
        expect(find.text('今日照片額度已用完'), findsOneWidget);
        expect(find.textContaining('每日台灣時間上午 8 點重設'), findsOneWidget);
      },
    );

    testWidgets(
      'a thumbnail that failed is an icon to tap, with no text to squeeze in',
      (tester) async {
        final service = PlacePhotosService(
          baseUrl: 'https://api.example',
          client: MockClient(
            (r) async => throw http.ClientException('offline'),
          ),
        );
        addTearDown(service.dispose);
        await tester.pumpWidget(
          gallery(withToken('t1'), service, thumbnail: true, autoLoad: true),
        );
        await settleImages(tester);
        expect(find.byTooltip('重試照片'), findsOneWidget);
        expect(find.byIcon(Icons.refresh), findsOneWidget);
        expect(find.textContaining('點一下重試'), findsNothing);
        expect(find.textContaining('沒有網路'), findsNothing);
      },
    );
  });
  group('network blips and a known-offline app', () {
    Place withToken(String token) => Place(
      id: 'a',
      name: '甲店',
      lat: 25,
      lng: 121,
      photos: [
        PlacePhoto.fromGoogle({...photoJson('a', 'one'), 'token': token}, 'a')!,
      ],
      photosExpiresAt: DateTime.now().add(const Duration(minutes: 20)),
    );
    http.Response ok() =>
        http.Response.bytes(pixel, 200, headers: {'content-type': 'image/png'});

    testWidgets(
      'a quick network drop is retried once and the user never sees it',
      (tester) async {
        var calls = 0;
        var sawFailure = false;
        final service = PlacePhotosService(
          baseUrl: 'https://api.example',
          client: MockClient((r) async {
            calls++;
            if (calls == 1) throw http.ClientException('reset');
            return ok();
          }),
        )..retryDelay = Duration.zero;
        addTearDown(service.dispose);
        await tester.pumpWidget(
          gallery(withToken('t'), service, compact: true),
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          if (find.byTooltip('重試照片').evaluate().isNotEmpty) sawFailure = true;
        }
        await settleImages(tester);
        expect(calls, 2);
        expect(sawFailure, isFalse);
        expect(find.byType(Image), findsOneWidget);
      },
    );

    testWidgets(
      'a connection that is really down is tried twice, then reported',
      (tester) async {
        var calls = 0;
        final service = PlacePhotosService(
          baseUrl: 'https://api.example',
          client: MockClient((r) async {
            calls++;
            throw http.ClientException('down');
          }),
        )..retryDelay = Duration.zero;
        addTearDown(service.dispose);
        await tester.pumpWidget(
          gallery(withToken('t'), service, compact: true),
        );
        await settleImages(tester);
        expect(calls, 2);
        expect(find.byTooltip('重試照片'), findsOneWidget);
      },
    );

    testWidgets('a request that sat until it failed is not repeated', (
      tester,
    ) async {
      var calls = 0;
      final service =
          PlacePhotosService(
              baseUrl: 'https://api.example',
              client: MockClient((r) async {
                calls++;
                throw http.ClientException('timed out');
              }),
            )
            ..retryDelay = Duration.zero
            ..fastFailure = Duration.zero; // every failure counts as slow
      addTearDown(service.dispose);
      await tester.pumpWidget(gallery(withToken('t'), service, compact: true));
      await settleImages(tester);
      expect(calls, 1);
      expect(find.byTooltip('重試照片'), findsOneWidget);
    });

    testWidgets(
      'when the app is offline photos stay quiet, then load by themselves',
      (tester) async {
        var calls = 0;
        final service = PlacePhotosService(
          baseUrl: 'https://api.example',
          client: MockClient((r) async {
            calls++;
            return ok();
          }),
        );
        addTearDown(service.dispose);
        await tester.pumpWidget(
          gallery(withToken('t'), service, compact: true, offline: true),
        );
        await settleImages(tester);
        expect(calls, 0, reason: 'no doomed request');
        expect(find.text('離線中 · 暫時看不到照片'), findsOneWidget);
        expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
        expect(find.byTooltip('重試照片'), findsNothing);
        expect(find.byType(Image), findsNothing);

        await tester.pumpWidget(
          gallery(withToken('t'), service, compact: true),
        );
        await settleImages(tester);
        expect(calls, 1);
        expect(find.byType(Image), findsOneWidget);
        expect(find.text('離線中 · 暫時看不到照片'), findsNothing);
      },
    );

    testWidgets(
      'offline, the full gallery and a thumbnail show one short line and no load button',
      (tester) async {
        final service = PlacePhotosService(
          baseUrl: 'https://api.example',
          client: MockClient((r) async => ok()),
        );
        addTearDown(service.dispose);
        await tester.pumpWidget(
          gallery(
            withToken('t'),
            service,
            thumbnail: true,
            autoLoad: false,
            offline: true,
          ),
        );
        await settleImages(tester);
        expect(find.text('離線中'), findsOneWidget);
        expect(find.text('查看照片'), findsNothing);

        await tester.pumpWidget(
          gallery(withToken('t'), service, autoLoad: false, offline: true),
        );
        await settleImages(tester);
        expect(find.text('離線中 · 暫時看不到照片'), findsOneWidget);

        await tester.pumpWidget(
          gallery(withToken('t'), service, thumbnail: true, autoLoad: false),
        );
        await settleImages(tester);
        expect(find.text('查看照片'), findsOneWidget, reason: 'back online');
      },
    );

    testWidgets('offline still shows a photo that is already in memory', (
      tester,
    ) async {
      var calls = 0;
      final service = PlacePhotosService(
        baseUrl: 'https://api.example',
        client: MockClient((r) async {
          calls++;
          return ok();
        }),
      );
      addTearDown(service.dispose);
      final place = withToken('t');
      await service.fetchImage(place.photos!.first);
      await tester.pumpWidget(
        gallery(place, service, compact: true, offline: true),
      );
      await settleImages(tester);
      expect(find.byType(Image), findsOneWidget);
      expect(calls, 1);
    });
  });
}
