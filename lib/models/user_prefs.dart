import 'mood.dart';

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
    this.excludedPlaceIds = const {},
    this.excludedCategories = const {},
  });

  /// true=麵, false=飯, null=未選
  final bool? prefersNoodles;
  /// true=清淡, false=重口味
  final bool? prefersLight;
  /// true=內用, false=外帶
  final bool? prefersDineIn;
  /// true=省錢
  final bool? budgetSensitive;
  /// true=快速簡單
  final bool? prefersQuick;
  final bool coldStartDone;
  final Mood mood;
  final Set<String> excludedPlaceIds;
  final Set<String> excludedCategories;

  UserPrefs copyWith({
    bool? prefersNoodles,
    bool? prefersLight,
    bool? prefersDineIn,
    bool? budgetSensitive,
    bool? prefersQuick,
    bool? coldStartDone,
    Mood? mood,
    Set<String>? excludedPlaceIds,
    Set<String>? excludedCategories,
    bool clearNoodles = false,
    bool clearLight = false,
  }) {
    return UserPrefs(
      prefersNoodles:
          clearNoodles ? null : (prefersNoodles ?? this.prefersNoodles),
      prefersLight: clearLight ? null : (prefersLight ?? this.prefersLight),
      prefersDineIn: prefersDineIn ?? this.prefersDineIn,
      budgetSensitive: budgetSensitive ?? this.budgetSensitive,
      prefersQuick: prefersQuick ?? this.prefersQuick,
      coldStartDone: coldStartDone ?? this.coldStartDone,
      mood: mood ?? this.mood,
      excludedPlaceIds: excludedPlaceIds ?? this.excludedPlaceIds,
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
        'excludedPlaceIds': excludedPlaceIds.toList(),
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
    return UserPrefs(
      prefersNoodles: json['prefersNoodles'] as bool?,
      prefersLight: json['prefersLight'] as bool?,
      prefersDineIn: json['prefersDineIn'] as bool?,
      budgetSensitive: json['budgetSensitive'] as bool?,
      prefersQuick: json['prefersQuick'] as bool?,
      coldStartDone: json['coldStartDone'] as bool? ?? false,
      mood: mood,
      excludedPlaceIds:
          (json['excludedPlaceIds'] as List?)?.cast<String>().toSet() ?? {},
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

const coldStartQuestions = <ColdStartQuestion>[
  ColdStartQuestion(
    id: 'carb',
    prompt: '這一餐比較想吃？',
    optionA: '麵',
    optionB: '飯',
  ),
  ColdStartQuestion(
    id: 'flavor',
    prompt: '口味偏向？',
    optionA: '清淡',
    optionB: '重口味',
  ),
  ColdStartQuestion(
    id: 'dine',
    prompt: '用餐方式？',
    optionA: '內用',
    optionB: '外帶',
  ),
  ColdStartQuestion(
    id: 'budget',
    prompt: '預算？',
    optionA: '省錢',
    optionB: '可稍貴',
  ),
  ColdStartQuestion(
    id: 'tempo',
    prompt: '節奏？',
    optionA: '快速簡單',
    optionB: '可以慢慢吃',
  ),
];
