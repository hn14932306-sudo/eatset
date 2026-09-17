import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_prefs.dart';
import 'decision_engine.dart';

class StorageService {
  static const _prefsKey = 'eatset_user_prefs';
  static const _historyKey = 'eatset_history';
  static const _rerollKey = 'eatset_reroll';
  static const _balanceKey = 'eatset_last_balance_nudge';

  Future<UserPrefs> loadPrefs() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_prefsKey);
    if (raw == null) return const UserPrefs();
    try {
      return UserPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const UserPrefs();
    }
  }

  Future<void> savePrefs(UserPrefs prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_prefsKey, jsonEncode(prefs.toJson()));
  }

  Future<List<HistoryEntry>> loadHistory() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_historyKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveHistory(List<HistoryEntry> history) async {
    final sp = await SharedPreferences.getInstance();
    final trimmed = history.take(100).toList();
    await sp.setString(
      _historyKey,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  /// 回傳今日已重抽次數。
  Future<int> loadRerollCountToday() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_rerollKey);
    if (raw == null) return 0;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final day = map['day'] as String?;
      final today = _dayKey(DateTime.now());
      if (day != today) return 0;
      return map['count'] as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> saveRerollCountToday(int count) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _rerollKey,
      jsonEncode({'day': _dayKey(DateTime.now()), 'count': count}),
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
