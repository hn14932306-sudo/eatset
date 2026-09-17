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

  Place copyWith({
    double? distanceMeters,
    bool? openNow,
  }) {
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
        cuisineTags:
            (json['cuisineTags'] as List?)?.cast<String>() ?? const [],
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
