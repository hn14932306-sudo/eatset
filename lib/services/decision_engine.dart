import 'dart:math';

import '../models/meal_slot.dart';
import '../models/mood.dart';
import '../models/place.dart';
import '../models/user_prefs.dart';

/// 歷史紀錄條目（用於平衡建議與排除）。
class HistoryEntry {
  const HistoryEntry({
    required this.placeId,
    required this.placeName,
    required this.confirmedAt,
    this.cuisineTags = const [],
    this.mealSlot,
  });

  final String placeId;
  final String placeName;
  final DateTime confirmedAt;
  final List<String> cuisineTags;
  final String? mealSlot;

  Map<String, dynamic> toJson() => {
        'placeId': placeId,
        'placeName': placeName,
        'confirmedAt': confirmedAt.toIso8601String(),
        'cuisineTags': cuisineTags,
        'mealSlot': mealSlot,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        placeId: json['placeId'] as String,
        placeName: json['placeName'] as String,
        confirmedAt: DateTime.parse(json['confirmedAt'] as String),
        cuisineTags:
            (json['cuisineTags'] as List?)?.cast<String>() ?? const [],
        mealSlot: json['mealSlot'] as String?,
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

  /// 過濾關閉、過遠、過低評、已排除。
  List<Place> filterCandidates(
    List<Place> places,
    UserPrefs prefs, {
    Set<String> skipIds = const {},
  }) {
    return places.where((p) {
      if (prefs.excludedPlaceIds.contains(p.id)) return false;
      if (skipIds.contains(p.id)) return false;
      if (p.openNow == false) return false;
      if (p.distanceMeters != null &&
          p.distanceMeters! > maxDistanceMeters) {
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
        final visited =
            recentHistory.any((h) => h.placeId == place.id);
        score += visited ? -12 : 10;
        if (place.userRatingsTotal < 300) score += 4;
    }

    // 餐段微調
    score += _mealSlotBoost(place, mealSlot);

    // 平衡建議：偏好清淡／蔬食標籤
    if (favorBalance) {
      if (place.cuisineTags.contains('清淡') ||
          place.types.contains('health') ||
          place.types.contains('vegetarian') ||
          place.name.contains('蔬') ||
          place.name.contains('沙拉') ||
          place.name.contains('粥')) {
        score += 18;
      } else {
        score -= 6;
      }
    }

    // 輕微隨機，避免永遠同一家
    score += _random.nextDouble() * 3;

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

    if (prefs.budgetSensitive == true) {
      final price = place.priceLevel ?? 1;
      if (price <= 1) {
        s += 8;
      } else if (price >= 3) {
        s -= 8;
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
    final week = history.where((h) => h.confirmedAt.isAfter(weekAgo)).toList();
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
  }) {
    final candidates = filterCandidates(places, prefs, skipIds: skipIds);
    if (candidates.isEmpty) return null;

    final favorBalance = forceBalance;
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
  }) {
    if (isBalanceNudge) {
      return '這週吃得偏重，換個較均衡的選擇：${place.name} 評價不錯又相對清爽。';
    }
    final parts = <String>[];
    if (place.rating >= 4.5) {
      parts.add('高評價（${place.rating.toStringAsFixed(1)}）');
    } else if (place.rating >= 4.0) {
      parts.add('口碑穩定');
    }
    if (place.distanceMeters != null && place.distanceMeters! < 500) {
      parts.add('走路就到');
    } else if (place.distanceMeters != null) {
      parts.add(place.distanceLabel);
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
      return '綜合距離與評價，這一餐就吃「${place.name}」。';
    }
    return '${parts.take(3).join('、')}，適合當${mealSlot.labelZh}。';
  }
}
