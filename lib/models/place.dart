import 'place_photo.dart';

/// 餐廳／餐點地點。
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.rating = 0,
    this.userRatingsTotal = 0,
    this.types = const [],
    this.priceLevel,
    this.openNow,
    this.vicinity,
    this.distanceMeters,
    this.cuisineTags = const [],
    this.isDemo = false,
    this.isReference = false,
    this.fetchedAt,
    this.attributions = const [],
    this.photos,
    this.photosExpiresAt,
    this.websiteUri,
    this.menuUri,
    this.menuNote,
    this.closesAt,
    this.typeLabel,
  });

  final String id;
  final String name;
  final double lat;
  final double lng;
  final double rating;
  final int userRatingsTotal;
  final List<String> types;
  final int? priceLevel; // 0–4
  final bool? openNow;
  final String? vicinity;
  final double? distanceMeters;
  final List<String> cuisineTags;
  final bool isDemo;
  final bool isReference;
  final DateTime? fetchedAt;
  final List<Map<String, dynamic>> attributions;
  // Only the current API response; never written to JSON/storage.
  final List<PlacePhoto>? photos;
  final DateTime? photosExpiresAt;
  final Uri? websiteUri;

  /// Only supplied for an explicitly verified menu, never inferred from a homepage.
  final Uri? menuUri;
  final String? menuNote;

  /// Next closing time while open (from Google's own opening-hours data).
  /// Session-only, like the other live fields.
  final DateTime? closesAt;

  /// Localized primary type such as 拉麵店, taken from Google, not guessed.
  final String? typeLabel;

  /// Place data has no clock expiry: it stays valid for the user's session.
  /// Only a reference (an ID restored from storage) still needs a fetch.
  bool get needsRefresh => !isDemo && isReference;

  factory Place.reference(String id) => Place(
    id: id,
    name: id.startsWith('demo_') ? '示範店家' : '店家資訊待更新',
    lat: 0,
    lng: 0,
    isDemo: id.startsWith('demo_'),
    isReference: true,
  );

  Map<String, dynamic> toStorageJson() =>
      isDemo ? toJson() : {'id': id, 'isDemo': false};
  factory Place.fromStorageJson(Map<String, dynamic> json) =>
      json['isDemo'] == true || (json['id'] as String).startsWith('demo_')
      ? Place.fromJson(json)
      : Place.reference(json['id'] as String);

  /// Open state at [at]. Google's answer was true when fetched and comes with
  /// the time it ends, so once that time passes the place is closed: this needs
  /// no new request.
  bool? isOpenAt(DateTime at) {
    final end = closesAt;
    if (openNow == true && end != null && !at.isBefore(end)) return false;
    return openNow;
  }

  /// Time left until closing, or null when unknown, closed, or not soon.
  Duration? timeUntilClose(DateTime at) {
    final end = closesAt;
    if (openNow != true || end == null || !at.isBefore(end)) return null;
    final left = end.difference(at);
    return left < const Duration(hours: 24) ? left : null;
  }

  /// 「還有 2 小時 15 分鐘」 style; rounds up so it never claims more time than
  /// there is, and never shows 0.
  static String durationLabel(Duration d) {
    final minutes = d.inSeconds <= 60 ? 1 : (d.inSeconds / 60).ceil();
    if (minutes < 60) return '$minutes 分鐘';
    final h = minutes ~/ 60, m = minutes % 60;
    return m == 0 ? '$h 小時' : '$h 小時 $m 分鐘';
  }

  /// One line for every surface that shows open state.
  String openStatusLabel(DateTime at) {
    if (isDemo) return '示範營業資訊';
    switch (isOpenAt(at)) {
      case true:
        final left = timeUntilClose(at);
        if (left == null) return '目前營業中';
        final end = closesAt!;
        final hh = end.hour.toString().padLeft(2, '0');
        final mm = end.minute.toString().padLeft(2, '0');
        return '目前營業中 · 還有 ${durationLabel(left)}打烊（$hh:$mm）';
      case false:
        return openNow == true ? '已打烊' : '目前休息中';
      case null:
        return '營業狀態未知 · 出發前請確認';
    }
  }

  int? get knownPriceLevel {
    final level = priceLevel;
    return level != null && level >= 0 && level <= 4 ? level : null;
  }

  String get priceLabel => switch (knownPriceLevel) {
    0 => '免費等級 · 請確認菜單',
    1 => r'$ · 平價',
    2 => r'$$ · 中等',
    3 => r'$$$ · 較高價',
    4 => r'$$$$ · 高價',
    _ => '價格未知 · 請確認菜單',
  };

  /// 保守辨識：不單憑「飯店」兩字排除，以免誤傷一般中式飯店。
  /// 獨立登錄且沒有住宿類型／名稱線索的飯店餐廳仍可能無法辨識。
  bool get isLikelyHotelRestaurant =>
      types.any(
        (t) => const ['lodging', 'hotel', 'resort_hotel'].contains(t),
      ) ||
      RegExp(
        r'大飯店|酒店|旅館|旅店|渡假村|度假村|\bhotels?\b|\bresorts?\b',
        caseSensitive: false,
      ).hasMatch(name);

  Place copyWith({double? distanceMeters, bool? openNow}) {
    return Place(
      id: id,
      name: name,
      lat: lat,
      lng: lng,
      rating: rating,
      userRatingsTotal: userRatingsTotal,
      types: types,
      priceLevel: priceLevel,
      openNow: openNow ?? this.openNow,
      vicinity: vicinity,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      cuisineTags: cuisineTags,
      isDemo: isDemo,
      isReference: isReference,
      fetchedAt: fetchedAt,
      attributions: attributions,
      photos: photos,
      photosExpiresAt: photosExpiresAt,
      websiteUri: websiteUri,
      menuUri: menuUri,
      menuNote: menuNote,
      closesAt: closesAt,
      typeLabel: typeLabel,
    );
  }

  String get distanceLabel {
    final d = distanceMeters;
    if (d == null) return '距離未知';
    if (d < 1000) return '約 ${d.round()} 公尺';
    return '約 ${(d / 1000).toStringAsFixed(1)} 公里';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lat': lat,
    'lng': lng,
    'rating': rating,
    'userRatingsTotal': userRatingsTotal,
    'types': types,
    'priceLevel': priceLevel,
    'vicinity': vicinity,
    'cuisineTags': cuisineTags,
    'isDemo': isDemo,
  };

  factory Place.fromJson(Map<String, dynamic> json) => Place(
    id: json['id'] as String,
    name: json['name'] as String,
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    rating: (json['rating'] as num?)?.toDouble() ?? 0,
    userRatingsTotal: json['userRatingsTotal'] as int? ?? 0,
    types: (json['types'] as List?)?.cast<String>() ?? const [],
    priceLevel: json['priceLevel'] as int?,
    vicinity: json['vicinity'] as String?,
    cuisineTags: (json['cuisineTags'] as List?)?.cast<String>() ?? const [],
    isDemo: json['isDemo'] as bool? ?? false,
  );
}

/// 一次決策結果。
class Decision {
  const Decision({
    required this.place,
    required this.reasonZh,
    required this.score,
    this.isBalanceNudge = false,
    this.mealSlot,
  });

  final Place place;
  final String reasonZh;
  final double score;
  final bool isBalanceNudge;
  final String? mealSlot;
}
