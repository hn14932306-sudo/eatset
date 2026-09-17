import 'package:flutter/foundation.dart';

import '../models/meal_slot.dart';
import '../models/mood.dart';
import '../models/place.dart';
import '../models/user_prefs.dart';
import '../services/decision_engine.dart';
import '../services/location_service.dart';
import '../services/maps_launcher.dart';
import '../services/places_service.dart';
import '../services/storage_service.dart';

enum AppLoadStatus { idle, loading, ready, error }

/// 全域 App 狀態。
class AppState extends ChangeNotifier {
  AppState({
    LocationService? locationService,
    PlacesService? placesService,
    StorageService? storageService,
    DecisionEngine? decisionEngine,
  })  : _location = locationService ?? LocationService(),
        _places = placesService ?? PlacesService(),
        _storage = storageService ?? StorageService(),
        _engine = decisionEngine ?? DecisionEngine();

  final LocationService _location;
  final PlacesService _places;
  final StorageService _storage;
  final DecisionEngine _engine;

  AppLoadStatus status = AppLoadStatus.idle;
  UserPrefs prefs = const UserPrefs();
  List<Place> nearby = const [];
  List<HistoryEntry> history = const [];
  Decision? current;
  String? statusNote;
  /// bootstrap／refresh 失敗時給 UI 的可恢復訊息
  String? errorMessage;
  bool isDemo = true;
  bool locationOk = false;
  int rerollsUsedToday = 0;
  final Set<String> _skippedThisSession = {};
  MealSlot mealSlot = MealSlot.fromDateTime(DateTime.now());

  int get rerollsLeft =>
      (DecisionEngine.dailyRerollLimit - rerollsUsedToday)
          .clamp(0, DecisionEngine.dailyRerollLimit);

  bool get hasExclusions =>
      prefs.excludedPlaceIds.isNotEmpty || prefs.excludedCategories.isNotEmpty;

  Future<void> bootstrap() async {
    status = AppLoadStatus.loading;
    errorMessage = null;
    notifyListeners();

    try {
      prefs = await _storage.loadPrefs();
      history = await _storage.loadHistory();
      rerollsUsedToday = await _storage.loadRerollCountToday();
      mealSlot = MealSlot.fromDateTime(DateTime.now());

      final loc = await _location.getCurrentLocation();
      locationOk = loc != null;

      final result = await _places.fetchNearby(location: loc);
      nearby = result.places;
      isDemo = result.isDemo;
      statusNote = result.noteZh;

      if (prefs.coldStartDone) {
        await _pickDecision(initial: true);
      }

      status = AppLoadStatus.ready;
      notifyListeners();
    } catch (e, st) {
      debugPrint('bootstrap failed: $e\n$st');
      errorMessage = '啟動時發生問題，請再試一次。';
      status = AppLoadStatus.error;
      notifyListeners();
    }
  }

  Future<void> completeColdStart(Map<String, bool> answers) async {
    // answers: id -> choseA
    prefs = prefs.copyWith(
      prefersNoodles: answers['carb'],
      prefersLight: answers['flavor'],
      prefersDineIn: answers['dine'],
      budgetSensitive: answers['budget'],
      prefersQuick: answers['tempo'],
      coldStartDone: true,
    );
    // carb: A=麵=true; flavor: A=清淡=true; dine: A=內用=true;
    // budget: A=省錢=true; tempo: A=快速=true
    await _storage.savePrefs(prefs);
    await _pickDecision(initial: true);
    notifyListeners();
  }

  Future<void> setMood(Mood mood) async {
    prefs = prefs.copyWith(mood: mood);
    await _storage.savePrefs(prefs);
    await _pickDecision(initial: true);
    notifyListeners();
  }

  /// 重抽：若沒有真正換到另一家，不扣每日次數。
  Future<void> reroll() async {
    if (rerollsLeft <= 0) return;
    final previousId = current?.place.id;
    if (previousId != null) {
      _skippedThisSession.add(previousId);
    }
    await _pickDecision();
    final newId = current?.place.id;
    if (newId == null || newId == previousId) {
      // 候選耗盡後清 session skip 仍同一家／沒有選項 → 不扣次數
      if (newId == previousId && previousId != null) {
        final prefix = statusNote == null ? '' : '$statusNote · ';
        statusNote = '$prefix目前沒有其他可換選項';
      }
      notifyListeners();
      return;
    }
    rerollsUsedToday += 1;
    await _storage.saveRerollCountToday(rerollsUsedToday);
    notifyListeners();
  }

  Future<void> confirmCurrent() async {
    final d = current;
    if (d == null) return;
    final entry = HistoryEntry(
      placeId: d.place.id,
      placeName: d.place.name,
      confirmedAt: DateTime.now(),
      cuisineTags: d.place.cuisineTags,
      mealSlot: mealSlot.labelZh,
    );
    history = [entry, ...history];
    await _storage.saveHistory(history);
    if (d.isBalanceNudge) {
      await _storage.saveLastBalanceNudgeAt(DateTime.now());
    }
    notifyListeners();
    await MapsLauncher.openPlace(d.place);
  }

  Future<void> excludeCurrentPlace() async {
    final d = current;
    if (d == null) return;
    final ids = {...prefs.excludedPlaceIds, d.place.id};
    final names = {...prefs.excludedPlaceNames, d.place.id: d.place.name};
    prefs = prefs.copyWith(excludedPlaceIds: ids, excludedPlaceNames: names);
    await _storage.savePrefs(prefs);
    _skippedThisSession.add(d.place.id);
    await _pickDecision();
    notifyListeners();
  }

  Future<void> excludeCategory(String category) async {
    final cats = {...prefs.excludedCategories, category};
    prefs = prefs.copyWith(excludedCategories: cats);
    await _storage.savePrefs(prefs);
    await _pickDecision();
    notifyListeners();
  }

  /// 從目前店家推斷「不要這類」的單一類別（無多選清單）。
  String? inferCategoryForCurrent() {
    final place = current?.place;
    if (place == null) return null;
    return inferCategoryForPlace(place);
  }

  /// 推斷店家代表類別（優先 cuisineTags，再依名稱關鍵字）。
  static String? inferCategoryForPlace(Place place) {
    if (place.cuisineTags.isNotEmpty) {
      // 優先較具體的料理標籤，避開「內用／外帶／快速」等體驗標
      const soft = {'內用', '外帶', '快速', '清淡', '重口味'};
      for (final t in place.cuisineTags) {
        if (!soft.contains(t)) return t;
      }
      return place.cuisineTags.first;
    }
    final name = place.name;
    if (name.contains('火鍋')) return '火鍋';
    if (name.contains('麵') || name.contains('面')) return '麵';
    if (name.contains('飯') || name.contains('便當') || name.contains('壽司')) {
      return '飯';
    }
    if (name.contains('早') || name.contains('蛋餅') || name.contains('粥')) {
      return '早餐';
    }
    if (name.contains('咖啡')) return '咖啡';
    return null;
  }

  Future<void> removeExcludedPlace(String placeId) async {
    final ids = {...prefs.excludedPlaceIds}..remove(placeId);
    final names = {...prefs.excludedPlaceNames}..remove(placeId);
    prefs = prefs.copyWith(excludedPlaceIds: ids, excludedPlaceNames: names);
    await _storage.savePrefs(prefs);
    await _pickDecision(initial: true);
    notifyListeners();
  }

  Future<void> removeExcludedCategory(String category) async {
    final cats = {...prefs.excludedCategories}..remove(category);
    prefs = prefs.copyWith(excludedCategories: cats);
    await _storage.savePrefs(prefs);
    await _pickDecision(initial: true);
    notifyListeners();
  }

  Future<void> clearAllExclusions() async {
    prefs = prefs.copyWith(
      excludedPlaceIds: {},
      excludedPlaceNames: {},
      excludedCategories: {},
    );
    await _storage.savePrefs(prefs);
    _skippedThisSession.clear();
    await _pickDecision(initial: true);
    notifyListeners();
  }

  /// 解析排除店家顯示名稱（prefs 名稱 → 歷史 → nearby）。
  String labelForExcludedPlace(String id) {
    final stored = prefs.excludedPlaceNames[id];
    if (stored != null && stored.isNotEmpty) return stored;
    for (final h in history) {
      if (h.placeId == id) return h.placeName;
    }
    for (final p in nearby) {
      if (p.id == id) return p.name;
    }
    return '已排除的店家';
  }

  Future<void> refreshPlaces() async {
    status = AppLoadStatus.loading;
    errorMessage = null;
    notifyListeners();
    try {
      final loc = await _location.getCurrentLocation();
      locationOk = loc != null;
      final result = await _places.fetchNearby(location: loc);
      nearby = result.places;
      isDemo = result.isDemo;
      statusNote = result.noteZh;
      mealSlot = MealSlot.fromDateTime(DateTime.now());
      await _pickDecision(initial: true);
      status = AppLoadStatus.ready;
      notifyListeners();
    } catch (e, st) {
      debugPrint('refreshPlaces failed: $e\n$st');
      errorMessage = '重新整理失敗，請再試一次。';
      status = AppLoadStatus.error;
      notifyListeners();
    }
  }

  Future<void> _pickDecision({bool initial = false}) async {
    final now = DateTime.now();
    mealSlot = MealSlot.fromDateTime(now);
    final lastBalance = await _storage.loadLastBalanceNudgeAt();
    final wantBalance = _engine.shouldOfferBalanceNudge(
      history: history,
      now: now,
      lastBalanceNudgeAt: lastBalance,
    );

    Decision? d;
    if (wantBalance && initial) {
      d = _engine.decide(
        nearby,
        prefs,
        mealSlot: mealSlot,
        history: history,
        skipIds: _skippedThisSession,
        forceBalance: true,
      );
    }
    d ??= _engine.decide(
      nearby,
      prefs,
      mealSlot: mealSlot,
      history: history,
      skipIds: _skippedThisSession,
      forceBalance: false,
    );

    // 若全被 skip，清空 session skip 再試一次
    if (d == null && _skippedThisSession.isNotEmpty) {
      _skippedThisSession.clear();
      d = _engine.decide(
        nearby,
        prefs,
        mealSlot: mealSlot,
        history: history,
        forceBalance: false,
      );
    }
    current = d;
    if (d == null) {
      final prefix = statusNote == null ? '' : '$statusNote · ';
      statusNote = '$prefix目前沒有合適選項，請放寬排除或稍後再試';
    }
  }
}
