import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/place.dart';
import '../models/place_photo.dart';
import 'backend_client.dart';
import 'photo_memory_cache.dart';

/// Thumbnails are ~96dp tall; the card and full-screen viewer use [card].
enum PhotoSize { thumb, card }

/// All photo traffic passes through the backend, including the image bytes.
class PlacePhotosService {
  PlacePhotosService({
    http.Client? client,
    String? baseUrl,
    PhotoMemoryCache? cache,
  }) : _backend = BackendClient(client: client, baseUrl: baseUrl),
       _cache = cache ?? PhotoMemoryCache.shared;
  final BackendClient _backend;
  final PhotoMemoryCache _cache;

  static String _key(PlacePhoto photo, PhotoSize size) =>
      '${photo.name}#${size.name}';

  Uint8List? _cached(PlacePhoto photo, PhotoSize size) =>
      _cache.get(_key(photo, PhotoSize.card)) ??
      (size == PhotoSize.thumb ? _cache.get(_key(photo, size)) : null);

  /// Drop a photo from memory, both sizes. Used when what arrived would not
  /// decode, so a retry fetches it again instead of reusing the bad bytes.
  void evict(PlacePhoto photo) {
    for (final size in PhotoSize.values) {
      _cache.remove(_key(photo, size));
    }
  }

  /// True when the first photo of [place] is already in memory, so showing it
  /// costs no request at all.
  bool hasCachedFirstPhoto(Place place, {PhotoSize size = PhotoSize.card}) {
    final first = place.photos == null || place.photos!.isEmpty
        ? null
        : place.photos!.first;
    if (first == null) return false;
    return _cache.contains(_key(first, PhotoSize.card)) ||
        (size == PhotoSize.thumb &&
            _cache.contains(_key(first, PhotoSize.thumb)));
  }

  bool get isConfigured => _backend.isConfigured;
  Future<List<PlacePhoto>> fetchPhotos(Place place) async {
    if (!isConfigured || place.isDemo || place.id.startsWith('demo_')) {
      return [];
    }
    // A photo already in memory never needs a new token, so an expired token
    // must not trigger a metadata lookup just to show it again.
    if (hasCachedFirstPhoto(place, size: PhotoSize.thumb)) {
      return place.photos!.take(3).toList();
    }
    // Consume the fresh search/detail response directly, without an extra
    // Place Details call. Leave a margin before server-issued token expiry.
    if (place.photos != null &&
        place.photosExpiresAt?.isAfter(
              DateTime.now().add(const Duration(seconds: 15)),
            ) ==
            true) {
      return place.photos!.take(3).toList();
    }
    return refreshPhotos(place);
  }

  Future<List<PlacePhoto>> refreshPhotos(Place place) async {
    if (!isConfigured || place.isDemo || place.id.startsWith('demo_')) {
      return [];
    }
    try {
      final body = await _backend.json(
        '/v1/places/${Uri.encodeComponent(place.id)}/photos',
      );
      if (body['id'] != place.id) throw const PhotoLoadException();
      return (body['photos'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((p) => PlacePhoto.fromGoogle(p, place.id))
          .whereType<PlacePhoto>()
          .take(3)
          .toList();
    } on BackendException catch (error) {
      throw PhotoLoadException(code: error.code);
    } catch (_) {
      throw const PhotoLoadException();
    }
  }

  Future<Uint8List> fetchImage(
    PlacePhoto photo, {
    PhotoSize size = PhotoSize.card,
  }) async {
    if (!isConfigured || photo.token.isEmpty) throw const PhotoLoadException();
    final hit = _cached(photo, size);
    if (hit != null) return hit;
    try {
      final bytes = await _download(photo, size);
      _cache.put(_key(photo, size), bytes);
      return bytes;
    } on BackendException catch (error) {
      throw PhotoLoadException(code: error.code);
    } catch (_) {
      throw const PhotoLoadException();
    }
  }

  /// Transient trouble is retried once, quietly: a BUSY answer, or a network
  /// failure that came back quickly (a dropped packet, a reset connection). A
  /// request that sat until it timed out is not repeated: the connection is
  /// really down, and waiting twice as long helps nobody.
  Future<Uint8List> _download(PlacePhoto photo, PhotoSize size) async {
    final sizeArg = size == PhotoSize.thumb ? 'thumb' : null;
    final clock = Stopwatch()..start();
    try {
      return await _backend.image(photo.token, size: sizeArg);
    } on BackendException catch (error) {
      final busy = error.code == 'BUSY';
      final quickDrop =
          error.code == 'NETWORK_FAILED' && clock.elapsed < fastFailure;
      if (!busy && !quickDrop) rethrow;
      await Future<void>.delayed(retryDelay);
      return _backend.image(photo.token, size: sizeArg);
    }
  }

  /// Overridable so tests need not wait.
  Duration retryDelay = const Duration(milliseconds: 700);

  /// A network failure faster than this counts as a blip worth one retry.
  Duration fastFailure = const Duration(seconds: 3);

  void dispose() => _backend.dispose();
}

class PhotoLoadException implements Exception {
  const PhotoLoadException({this.code});
  final String? code;
  String get message => switch (code) {
    'DAILY_LIMIT' => '今日店家查詢額度已用完，暫時無法載入照片。每日台灣時間上午 8 點重設。',
    'CLIENT_LIMIT' => '目前查詢次數已達上限，請稍後再試照片。',
    'BUSY' => '照片服務目前忙碌，請稍後再試。',
    'NETWORK_FAILED' => '無法連線至照片服務，請確認網路連線後再試。',
    _ => '店家照片暫時無法載入',
  };
  @override
  String toString() => message;
}
