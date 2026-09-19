import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_prefs.dart';
import '../models/place.dart';
import 'decision_engine.dart';

class StorageService {
  Future<List<Place>> loadFavorites() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('eatset_favorites');
    if (raw == null) return [];
    List<Place> places;
    try {
      places = (jsonDecode(raw) as List)
          .map((p) => Place.fromStorageJson(p as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
    final clean = jsonEncode(places.map((p) => p.toStorageJson()).toList());
    if (clean != raw) await _write(sp, 'eatset_favorites', clean);
    return places;
  }

  Future<void> saveFavorites(List<Place> places) async {
    final sp = await SharedPreferences.getInstance();
    await _write(
      sp,
      'eatset_favorites',
      jsonEncode(places.map((p) => p.toStorageJson()).toList()),
    );
  }

  Future<Set<String>> loadMealSkips(String mealKey) async {
    final sp = await SharedPreferences.getInstance();
    try {
      final data = jsonDecode(sp.getString('eatset_meal_skips') ?? '{}') as Map;
      if (data['meal'] != mealKey) return {};
      return (data['ids'] as List).cast<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> saveMealSkips(String mealKey, Set<String> ids) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      'eatset_meal_skips',
      jsonEncode({'meal': mealKey, 'ids': ids.toList()}),
    );
  }

  static const _prefsKey = 'eatset_user_prefs';
  static const _historyKey = 'eatset_history';
  static const _rerollKey = 'eatset_reroll';
  static const _balanceKey = 'eatset_last_balance_nudge';

  Map<String, dynamic> _storedPrefs(UserPrefs prefs) => {
    ...prefs.toJson(),
    'excludedPlaceNames': Map.fromEntries(
      prefs.excludedPlaceNames.entries.where((e) => e.key.startsWith('demo_')),
    ),
  };

  Future<UserPrefs> loadPrefs() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_prefsKey);
    if (raw == null) return const UserPrefs();
    UserPrefs prefs;
    try {
      prefs = UserPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const UserPrefs();
    }
    final clean = _storedPrefs(prefs);
    final encoded = jsonEncode(clean);
    if (raw != encoded) await _write(sp, _prefsKey, encoded);
    return UserPrefs.fromJson(clean);
  }

  Future<void> savePrefs(UserPrefs prefs) async {
    await _write(
      await SharedPreferences.getInstance(),
      _prefsKey,
      jsonEncode(_storedPrefs(prefs)),
    );
  }

  Future<List<HistoryEntry>> loadHistory() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_historyKey);
    if (raw == null) return [];
    List<HistoryEntry> history;
    try {
      history = (jsonDecode(raw) as List)
          .map((e) => HistoryEntry.fromStorageJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
    final clean = jsonEncode(
      history.take(100).map((e) => e.toStorageJson()).toList(),
    );
    if (raw != clean) await _write(sp, _historyKey, clean);
    return history.take(100).toList();
  }

  Future<void> saveHistory(List<HistoryEntry> history) async {
    final sp = await SharedPreferences.getInstance();
    await _write(
      sp,
      _historyKey,
      jsonEncode(history.take(100).map((e) => e.toStorageJson()).toList()),
    );
  }

  Future<void> _write(SharedPreferences sp, String key, String value) async {
    if (!await sp.setString(key, value)) throw StateError('Local save failed');
  }

  /// 回傳今日已重抽次數。
  Future<int> loadRerollCountToday({DateTime? day}) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_rerollKey);
    if (raw == null) return 0;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final savedDay = map['day'] as String?;
      final today = _dayKey((day ?? DateTime.now()).toLocal());
      if (savedDay != today) return 0;
      return (map['count'] as int? ?? 0).clamp(
        0,
        DecisionEngine.dailyRerollLimit,
      );
    } catch (_) {
      return 0;
    }
  }

  Future<void> saveRerollCountToday(int count, {DateTime? day}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _rerollKey,
      jsonEncode({
        'day': _dayKey((day ?? DateTime.now()).toLocal()),
        'count': count,
      }),
    );
  }

  Future<DateTime?> loadLastBalanceNudgeAt() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_balanceKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> saveLastBalanceNudgeAt(DateTime at) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_balanceKey, at.toIso8601String());
  }

  String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
