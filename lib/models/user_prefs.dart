import 'mood.dart';
import 'meal_budget.dart';
import 'search_range.dart';

/// Cold-start 與長期偏好。
class UserPrefs {
  const UserPrefs({
    this.prefersNoodles,
    this.prefersLight,
    this.prefersDineIn,
    this.budgetSensitive,
    this.prefersQuick,
    this.coldStartDone = false,
    this.mood = Mood.safe,
    this.mealBudget = MealBudget.everyday,
    this.includeHotelRestaurants = false,
    this.includeUnknownPrices = true,
    this.maxDistanceMeters = SearchRange.defaultMeters,
    this.excludedPlaceIds = const {},
    this.excludedPlaceNames = const {},
    this.excludedCategories = const {},
  });

  /// true=麵, false=飯, null=未選
  final bool? prefersNoodles;

  /// true=清淡, false=重口味
  final bool? prefersLight;

  /// true=內用, false=外帶（舊 cold-start 保留欄位）
  final bool? prefersDineIn;

  /// true=省錢（舊 cold-start 保留欄位）
  final bool? budgetSensitive;

  /// true=快速簡單（舊 cold-start 保留欄位）
  final bool? prefersQuick;
  final bool coldStartDone;
  final Mood mood;
  final MealBudget mealBudget;
  final bool includeHotelRestaurants;
  final bool includeUnknownPrices;

  /// Straight-line range in metres; also the radius sent to the search.
  final int maxDistanceMeters;
  final Set<String> excludedPlaceIds;

  /// placeId → 顯示名稱（避免 UI 只顯示 raw id）
  final Map<String, String> excludedPlaceNames;
  final Set<String> excludedCategories;

  /// 取得排除店家的顯示名稱。
  String excludedPlaceLabel(String id) => excludedPlaceNames[id] ?? '已排除的店家';

  UserPrefs copyWith({
    bool? prefersNoodles,
    bool? prefersLight,
    bool? prefersDineIn,
    bool? budgetSensitive,
    bool? prefersQuick,
    bool? coldStartDone,
    Mood? mood,
    MealBudget? mealBudget,
    bool? includeHotelRestaurants,
    bool? includeUnknownPrices,
    int? maxDistanceMeters,
    Set<String>? excludedPlaceIds,
    Map<String, String>? excludedPlaceNames,
    Set<String>? excludedCategories,
    bool clearNoodles = false,
    bool clearLight = false,
  }) {
    return UserPrefs(
      prefersNoodles: clearNoodles
          ? null
          : (prefersNoodles ?? this.prefersNoodles),
      prefersLight: clearLight ? null : (prefersLight ?? this.prefersLight),
      prefersDineIn: prefersDineIn ?? this.prefersDineIn,
      budgetSensitive: budgetSensitive ?? this.budgetSensitive,
      prefersQuick: prefersQuick ?? this.prefersQuick,
      coldStartDone: coldStartDone ?? this.coldStartDone,
      mood: mood ?? this.mood,
      mealBudget: mealBudget ?? this.mealBudget,
      includeHotelRestaurants:
          includeHotelRestaurants ?? this.includeHotelRestaurants,
      includeUnknownPrices: includeUnknownPrices ?? this.includeUnknownPrices,
      maxDistanceMeters: SearchRange.normalize(
        maxDistanceMeters ?? this.maxDistanceMeters,
      ),
      excludedPlaceIds: excludedPlaceIds ?? this.excludedPlaceIds,
      excludedPlaceNames: excludedPlaceNames ?? this.excludedPlaceNames,
      excludedCategories: excludedCategories ?? this.excludedCategories,
    );
  }

  Map<String, dynamic> toJson() => {
    'prefersNoodles': prefersNoodles,
    'prefersLight': prefersLight,
    'prefersDineIn': prefersDineIn,
    'budgetSensitive': budgetSensitive,
    'prefersQuick': prefersQuick,
    'coldStartDone': coldStartDone,
    'mood': mood.name,
    'mealBudget': mealBudget.name,
    'includeHotelRestaurants': includeHotelRestaurants,
    'includeUnknownPrices': includeUnknownPrices,
    'maxDistanceMeters': maxDistanceMeters,
    'excludedPlaceIds': excludedPlaceIds.toList(),
    'excludedPlaceNames': excludedPlaceNames,
    'excludedCategories': excludedCategories.toList(),
  };

  factory UserPrefs.fromJson(Map<String, dynamic> json) {
    Mood mood = Mood.safe;
    final moodName = json['mood'] as String?;
    if (moodName != null) {
      mood = Mood.values.firstWhere(
        (m) => m.name == moodName,
        orElse: () => Mood.safe,
      );
    }
    final ids =
        (json['excludedPlaceIds'] as List?)?.cast<String>().toSet() ?? {};
    final namesRaw = json['excludedPlaceNames'];
    final names = <String, String>{};
    if (namesRaw is Map) {
      namesRaw.forEach((k, v) {
        if (k is String && v is String) names[k] = v;
      });
    }
    // 舊資料只有 id：保留 id，顯示時再盡力解析名稱
    for (final id in ids) {
      names.putIfAbsent(id, () => '');
    }
    return UserPrefs(
      prefersNoodles: json['prefersNoodles'] as bool?,
      prefersLight: json['prefersLight'] as bool?,
      prefersDineIn: json['prefersDineIn'] as bool?,
      budgetSensitive: json['budgetSensitive'] as bool?,
      prefersQuick: json['prefersQuick'] as bool?,
      coldStartDone: json['coldStartDone'] as bool? ?? false,
      mood: mood,
      mealBudget: MealBudget.values.firstWhere(
        (b) => b.name == json['mealBudget'],
        orElse: () => json['budgetSensitive'] == true
            ? MealBudget.economical
            : MealBudget.everyday,
      ),
      includeHotelRestaurants: json['includeHotelRestaurants'] == true,
      includeUnknownPrices: json['includeUnknownPrices'] != false,
      maxDistanceMeters: SearchRange.normalize(json['maxDistanceMeters']),
      excludedPlaceIds: ids,
      excludedPlaceNames: names,
      excludedCategories:
          (json['excludedCategories'] as List?)?.cast<String>().toSet() ?? {},
    );
  }
}

/// Cold-start 單一題目。
class ColdStartQuestion {
  const ColdStartQuestion({
    required this.id,
    required this.prompt,
    required this.optionA,
    required this.optionB,
  });

  final String id;
  final String prompt;
  final String optionA;
  final String optionB;
}

/// P1-2：3 題（麵／飯、清淡／重口、穩妥／嘗鮮）。
const coldStartQuestions = <ColdStartQuestion>[
  ColdStartQuestion(id: 'carb', prompt: '這一餐比較想吃？', optionA: '麵', optionB: '飯'),
  ColdStartQuestion(
    id: 'flavor',
    prompt: '口味偏向？',
    optionA: '清淡',
    optionB: '重口味',
  ),
  ColdStartQuestion(
    id: 'mood',
    prompt: '這一餐想怎麼挑？',
    optionA: '想穩妥一點',
    optionB: '想試試新的',
  ),
];
