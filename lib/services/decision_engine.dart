import 'dart:math';

import '../models/meal_slot.dart';
import '../models/mood.dart';
import '../models/place.dart';
import '../models/user_prefs.dart';

enum MealFeedback {
  planned('尚未回報'),
  liked('吃過，喜歡'),
  neutral('吃過，普通'),
  disliked('吃過，不合口味'),
  notEaten('沒有去吃');

  const MealFeedback(this.labelZh);
  final String labelZh;
  bool get isEaten => this == liked || this == neutral || this == disliked;
}

/// 歷史紀錄條目（用於平衡建議與排除）。
class HistoryEntry {
  const HistoryEntry({
    required this.placeId,
    required this.placeName,
    required this.confirmedAt,
    this.cuisineTags = const [],
    this.mealSlot,
    this.feedback = MealFeedback.planned,
    this.place,
  });

  final String placeId;
  final String placeName;
  final DateTime confirmedAt;
  final List<String> cuisineTags;
  final String? mealSlot;
  final MealFeedback feedback;
  final Place? place;
  String get id => '$placeId@${confirmedAt.microsecondsSinceEpoch}';
  HistoryEntry withFeedback(MealFeedback value) => HistoryEntry(
    placeId: placeId,
    placeName: placeName,
    confirmedAt: confirmedAt,
    cuisineTags: cuisineTags,
    mealSlot: mealSlot,
    feedback: value,
    place: place,
  );

  Map<String, dynamic> toStorageJson() =>
      place?.isDemo == true || placeId.startsWith('demo_')
      ? toJson()
      : {
          'placeId': placeId,
          'confirmedAt': confirmedAt.toIso8601String(),
          'mealSlot': mealSlot,
          'feedback': feedback.name,
        };

  factory HistoryEntry.fromStorageJson(Map<String, dynamic> json) {
    final id = json['placeId'] as String;
    final demo =
        id.startsWith('demo_') || (json['place'] as Map?)?['isDemo'] == true;
    return HistoryEntry.fromJson(
      demo
          ? json
          : {
              'placeId': id,
              'placeName': '店家資訊待更新',
              'confirmedAt': json['confirmedAt'],
              'mealSlot': json['mealSlot'],
              'feedback': json['feedback'],
            },
    );
  }

  Map<String, dynamic> toJson() => {
    'placeId': placeId,
    'placeName': placeName,
    'confirmedAt': confirmedAt.toIso8601String(),
    'cuisineTags': cuisineTags,
    'mealSlot': mealSlot,
    'feedback': feedback.name,
    'place': place?.toJson(),
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    placeId: json['placeId'] as String,
    placeName: json['placeName'] as String,
    confirmedAt: DateTime.parse(json['confirmedAt'] as String),
    cuisineTags: (json['cuisineTags'] as List?)?.cast<String>() ?? const [],
    mealSlot: json['mealSlot'] as String?,
    feedback: MealFeedback.values.firstWhere(
      (f) => f.name == json['feedback'],
      orElse: () => MealFeedback.planned,
    ),
    place: json['place'] is Map<String, dynamic>
        ? Place.fromJson(json['place'] as Map<String, dynamic>)
        : null,
  );
}

/// 評分與決策核心（可單元測試）。
class DecisionEngine {
  DecisionEngine({Random? random}) : _random = random ?? Random();

  final Random _random;

  static const double maxDistanceMeters = 2000;
  static const double minRating = 3.5;
  static const int minReviews = 20;
  static const int dailyRerollLimit = 3;

  /// 只能說明現有清淡線索，不把所有餐廳都視為均衡選項。
  /// 重口味線索優先否決，避免「麻辣蔬食」也被標成清爽。
  bool hasLightEvidence(Place place) =>
      !place.cuisineTags.contains('重口味') &&
      !RegExp('炸|麻辣|燒烤|燒肉|炭烤').hasMatch(place.name) &&
      (place.cuisineTags.contains('清淡') ||
          place.types.contains('health') ||
          place.types.contains('vegetarian') ||
          RegExp('沙拉|清粥').hasMatch(place.name));

  /// 過濾關閉、過遠、過低評、已排除。
  ///
  /// 真實 Places 路徑：排除 `openNow == false`，並套用 [minRating]／[minReviews]；
  /// 與 PlacesService 不加 `opennow` 查詢參數的策略一致（營業中偏好在此層完成）。
  List<Place> filterCandidates(
    List<Place> places,
    UserPrefs prefs, {
    Set<String> skipIds = const {},
  }) {
    return places.where((p) {
      if (p.needsRefresh) return false;
      if (prefs.excludedPlaceIds.contains(p.id)) return false;
      if (skipIds.contains(p.id)) return false;
      if (p.isOpenAt(DateTime.now()) == false) return false;
      if (!prefs.includeHotelRestaurants && p.isLikelyHotelRestaurant) {
        return false;
      }
      final price = p.knownPriceLevel;
      final maxPrice = prefs.mealBudget.maxPriceLevel;
      if (price == null && !prefs.includeUnknownPrices) return false;
      if (price != null && maxPrice != null && price > maxPrice) return false;
      if (p.distanceMeters != null &&
          p.distanceMeters! > prefs.maxDistanceMeters) {
        return false;
      }
      // Demo 店家放寬評論數；真實 API 才嚴格
      if (!p.isDemo) {
        if (p.rating > 0 && p.rating < minRating) return false;
        if (p.userRatingsTotal > 0 && p.userRatingsTotal < minReviews) {
          return false;
        }
      }
      for (final cat in prefs.excludedCategories) {
        if (p.cuisineTags.contains(cat) || p.name.contains(cat)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  /// 計算單一店家分數（越高越好）。
  double scorePlace(
    Place place,
    UserPrefs prefs, {
    required MealSlot mealSlot,
    List<HistoryEntry> recentHistory = const [],
    bool favorBalance = false,
    bool addJitter = true,
  }) {
    var score = 0.0;

    // 評分與評論可信度
    score += place.rating * 12;
    score += (place.userRatingsTotal.clamp(0, 2000) / 2000) * 8;

    // 距離：越近越好
    final dist = place.distanceMeters ?? 800;
    score += (1 - (dist / maxDistanceMeters).clamp(0.0, 1.0)) * 15;

    // Cold-start 偏好
    score += _prefMatch(place, prefs);

    // Mood
    switch (prefs.mood) {
      case Mood.safe:
        score += place.rating >= 4.3 ? 10 : 0;
        score += place.userRatingsTotal >= 200 ? 6 : 0;
      case Mood.any:
        score += 3;
      case Mood.adventure:
        final visited = recentHistory.any(
          (h) => h.placeId == place.id && h.feedback.isEaten,
        );
        score += visited ? -12 : 10;
        if (place.userRatingsTotal < 300) score += 4;
    }

    // 餐段微調
    // 只依實際吃過的最新回饋調整，不把「確認」當成喜歡或用餐。
    for (final h in recentHistory) {
      if (h.placeId != place.id || !h.feedback.isEaten) continue;
      if (h.feedback == MealFeedback.liked) score += 8;
      if (h.feedback == MealFeedback.disliked) score -= 20;
      break;
    }
    score += _mealSlotBoost(place, mealSlot);

    // 平衡建議：偏好清淡／蔬食標籤
    if (favorBalance) {
      if (hasLightEvidence(place)) {
        score += 18;
      } else {
        score -= 6;
      }
    }

    // 輕微隨機，避免永遠同一家
    if (addJitter) score += _random.nextDouble() * 3;

    return score;
  }

  double _prefMatch(Place place, UserPrefs prefs) {
    var s = 0.0;
    final tags = place.cuisineTags;
    final name = place.name;

    if (prefs.prefersNoodles == true) {
      if (tags.contains('麵') || name.contains('麵') || name.contains('面')) {
        s += 10;
      }
      if (tags.contains('飯') && !tags.contains('麵')) s -= 4;
    } else if (prefs.prefersNoodles == false) {
      if (tags.contains('飯') ||
          name.contains('飯') ||
          name.contains('便當') ||
          name.contains('壽司')) {
        s += 10;
      }
      if (tags.contains('麵') && !tags.contains('飯')) s -= 4;
    }

    if (prefs.prefersLight == true) {
      if (tags.contains('清淡')) {
        s += 8;
      } else if (tags.contains('重口味')) {
        s -= 5;
      }
    } else if (prefs.prefersLight == false) {
      if (tags.contains('重口味')) {
        s += 8;
      } else if (tags.contains('清淡')) {
        s -= 3;
      }
    }

    if (prefs.prefersDineIn == true) {
      if (tags.contains('內用')) s += 4;
      if (tags.contains('外帶') && !tags.contains('內用')) s -= 2;
    } else if (prefs.prefersDineIn == false) {
      if (tags.contains('外帶') || place.types.contains('meal_takeaway')) {
        s += 6;
      }
    }

    if (prefs.prefersQuick == true) {
      if (tags.contains('快速') || place.types.contains('meal_takeaway')) {
        s += 6;
      }
      if (name.contains('火鍋') || name.contains('燒肉')) s -= 4;
    }

    return s;
  }

  double _mealSlotBoost(Place place, MealSlot slot) {
    final name = place.name;
    switch (slot) {
      case MealSlot.breakfast:
        if (name.contains('蛋') ||
            name.contains('粥') ||
            name.contains('早') ||
            name.contains('咖啡') ||
            place.types.contains('cafe') ||
            place.types.contains('bakery')) {
          return 8;
        }
        return 0;
      case MealSlot.lateNight:
        if (name.contains('夜') ||
            name.contains('串燒') ||
            name.contains('拉麵') ||
            name.contains('麵')) {
          return 5;
        }
        return 0;
      case MealSlot.lunch:
      case MealSlot.dinner:
        return 0;
    }
  }

  /// 本週是否應給平衡建議（約每週一次機會）。
  bool shouldOfferBalanceNudge({
    required List<HistoryEntry> history,
    required DateTime now,
    required DateTime? lastBalanceNudgeAt,
  }) {
    if (lastBalanceNudgeAt != null) {
      final days = now.difference(lastBalanceNudgeAt).inDays;
      if (days < 7) return false;
    }
    final weekAgo = now.subtract(const Duration(days: 7));
    final week = history
        .where(
          (h) =>
              h.feedback.isEaten &&
              h.confirmedAt.isAfter(weekAgo) &&
              !h.confirmedAt.isAfter(now),
        )
        .toList();
    if (week.length < 3) return false;

    var heavy = 0;
    for (final h in week) {
      if (h.cuisineTags.contains('重口味') ||
          h.placeName.contains('火鍋') ||
          h.placeName.contains('炸') ||
          h.placeName.contains('燒烤')) {
        heavy++;
      }
    }
    return heavy >= (week.length / 2).ceil();
  }

  /// 產出單一決策。
  Decision? decide(
    List<Place> places,
    UserPrefs prefs, {
    required MealSlot mealSlot,
    List<HistoryEntry> history = const [],
    Set<String> skipIds = const {},
    bool forceBalance = false,
    bool showRealDistance = false,
  }) {
    var candidates = filterCandidates(places, prefs, skipIds: skipIds);
    if (candidates.isEmpty) return null;

    // 有預算時先選價格已知且合適的店，價格未知只作後備，不能當成便宜。
    if (prefs.mealBudget.maxPriceLevel != null) {
      final priced = candidates
          .where((p) => p.knownPriceLevel != null)
          .toList();
      if (priced.isNotEmpty) candidates = priced;
    }

    var favorBalance = false;
    if (forceBalance) {
      final light = candidates.where(hasLightEvidence).toList();
      if (light.isNotEmpty) {
        candidates = light;
        favorBalance = true;
      }
    }
    Decision? best;
    for (final p in candidates) {
      final s = scorePlace(
        p,
        prefs,
        mealSlot: mealSlot,
        recentHistory: history,
        favorBalance: favorBalance,
      );
      if (best == null || s > best.score) {
        best = Decision(
          place: p,
          reasonZh: buildReason(
            p,
            prefs,
            mealSlot: mealSlot,
            isBalanceNudge: favorBalance,
            showRealDistance: showRealDistance,
          ),
          score: s,
          isBalanceNudge: favorBalance,
          mealSlot: mealSlot.labelZh,
        );
      }
    }
    return best;
  }

  /// 繁中一句話理由。
  String buildReason(
    Place place,
    UserPrefs prefs, {
    required MealSlot mealSlot,
    bool isBalanceNudge = false,
    bool showRealDistance = false,
  }) {
    if (isBalanceNudge && hasLightEvidence(place)) {
      return '這週的紀錄偏重口味，${place.name} 有清淡或蔬食線索，實際餐點請確認菜單。';
    }
    final parts = <String>[];
    if (place.rating >= 4.5) {
      parts.add('高評價（${place.rating.toStringAsFixed(1)}）');
    } else if (place.rating >= 4.0) {
      parts.add('口碑穩定');
    }
    if (showRealDistance && !place.isDemo && place.distanceMeters != null) {
      parts.add('直線距離${place.distanceLabel}');
    }
    if (prefs.mood == Mood.safe) {
      parts.add('符合想穩妥');
    } else if (prefs.mood == Mood.adventure) {
      parts.add('適合想換口味');
    }
    if (prefs.prefersNoodles == true &&
        (place.cuisineTags.contains('麵') || place.name.contains('麵'))) {
      parts.add('對上你選的麵');
    }
    if (prefs.prefersNoodles == false &&
        (place.cuisineTags.contains('飯') || place.name.contains('飯'))) {
      parts.add('對上你選的飯');
    }
    if (parts.isEmpty) {
      return '依目前可用的店家資料，這一餐可選「${place.name}」。';
    }
    return '${parts.take(3).join('、')}，適合當${mealSlot.labelZh}。';
  }
}
