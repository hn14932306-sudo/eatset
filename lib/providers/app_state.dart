import 'package:flutter/foundation.dart';

import '../models/meal_slot.dart';
import '../models/mood.dart';
import '../models/place.dart';
import '../models/user_prefs.dart';
import '../services/decision_engine.dart';
import '../services/location_service.dart';
import '../services/places_service.dart';
import '../services/storage_service.dart';

enum AppLoadStatus { idle, loading, ready, error }

/// 同一本地日曆日（年／月／日）。
bool isSameLocalDay(DateTime a, DateTime b) {
  final la = a.toLocal();
  final lb = b.toLocal();
  return la.year == lb.year && la.month == lb.month && la.day == lb.day;
}

/// 當日最新一筆「就吃這個」紀錄（history 假設新→舊）。
HistoryEntry? latestConfirmedOnDay(
  List<HistoryEntry> history,
  DateTime day,
) {
  for (final h in history) {
    if (isSameLocalDay(h.confirmedAt, day)) return h;
  }
  return null;
}

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

  /// 使用者主動要「再決定一次」時暫時隱藏今日已決定態。
  bool _forceRedecide = false;

  /// 剛排除、可一鍵復原的店（完整 Place，不依賴 nearby 查找）。
  Place? _pendingUndoPlace;

  /// 供 Home 顯示持久復原按鈕（SnackBarAction 在 Flutter Web 常不觸發）。
  Place? get pendingUndoPlace => _pendingUndoPlace;

  bool get hasPendingUndo => _pendingUndoPlace != null;

  /// 冷啟動結束後首頁提示「想穩妥」（toast 用，顯示後清掉）。
  bool showDefaultMoodHint = false;

  int get rerollsLeft =>
      (DecisionEngine.dailyRerollLimit - rerollsUsedToday)
          .clamp(0, DecisionEngine.dailyRerollLimit);

  bool get hasExclusions =>
      prefs.excludedPlaceIds.isNotEmpty || prefs.excludedCategories.isNotEmpty;

  /// 無真實定位時不可顯示「約 N 公尺」（錨點距離會誤導）。
  bool get showRealDistance => locationOk;

  /// 今日已確認的歷史（若使用者要求再決定則為 null）。
  HistoryEntry? get todayConfirmed {
    if (_forceRedecide) return null;
    return latestConfirmedOnDay(history, DateTime.now());
  }

  bool get hasConfirmedToday => todayConfirmed != null;

  /// 解析今日已確認店家（nearby／current 優先，否則用歷史組最小 Place）。
  Place? placeForTodayConfirmed() {
    final entry = todayConfirmed;
    if (entry == null) return null;
    if (current?.place.id == entry.placeId) return current!.place;
    for (final p in nearby) {
      if (p.id == entry.placeId) return p;
    }
    return Place(
      id: entry.placeId,
      name: entry.placeName,
      lat: 25.0478,
      lng: 121.5170,
      cuisineTags: entry.cuisineTags,
      isDemo: entry.placeId.startsWith('demo_'),
    );
  }

  /// 軟路徑：離開「今天就這家」，回到一般決策卡。
  void requestRedecide() {
    _forceRedecide = true;
    notifyListeners();
  }

  void consumeDefaultMoodHint() {
    if (!showDefaultMoodHint) return;
    showDefaultMoodHint = false;
  }

  Future<void> bootstrap() async {
    status = AppLoadStatus.loading;
    errorMessage = null;
    notifyListeners();

    try {
      prefs = await _storage.loadPrefs();
      history = await _storage.loadHistory();
      rerollsUsedToday = await _storage.loadRerollCountToday();
      mealSlot = MealSlot.fromDateTime(DateTime.now());
      _forceRedecide = false;

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
    // carb: A=麵; flavor: A=清淡; mood: A=想穩妥
    final choseSafe = answers['mood'] ?? true;
    final mood = choseSafe ? Mood.safe : Mood.adventure;
    prefs = prefs.copyWith(
      prefersNoodles: answers['carb'],
      prefersLight: answers['flavor'],
      coldStartDone: true,
      mood: mood,
    );
    showDefaultMoodHint = mood == Mood.safe;
    await _storage.savePrefs(prefs);
    await _pickDecision(initial: true);
    notifyListeners();
  }

  /// 跳過冷啟動：套用預設「想穩妥」，直接進決策首頁。
  Future<void> skipColdStart() async {
    prefs = prefs.copyWith(
      coldStartDone: true,
      mood: Mood.safe,
    );
    showDefaultMoodHint = true;
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
    _pendingUndoPlace = null; // 換卡後立刻隱藏復原
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

  /// 確認這一餐：寫入歷史。地圖改由 S7 畫面開啟。
  Future<Place?> confirmCurrent() async {
    final d = current;
    if (d == null) return null;
    _pendingUndoPlace = null; // 確認後不再顯示復原
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
    _forceRedecide = false;
    notifyListeners();
    return d.place;
  }

  /// 排除目前店家；回傳被排除的店名供 snackbar／復原。
  Future<String?> excludeCurrentPlace() async {
    final d = current;
    if (d == null) return null;
    final name = d.place.name;
    // 復原前先快取完整 Place，避免只靠 nearby id 查找失敗。
    _pendingUndoPlace = d.place;
    final ids = {...prefs.excludedPlaceIds, d.place.id};
    final names = {...prefs.excludedPlaceNames, d.place.id: name};
    prefs = prefs.copyWith(excludedPlaceIds: ids, excludedPlaceNames: names);
    await _storage.savePrefs(prefs);
    _skippedThisSession.add(d.place.id);
    await _pickDecision();
    notifyListeners();
    return name;
  }

  Future<String?> excludeCategory(String category) async {
    final cats = {...prefs.excludedCategories, category};
    prefs = prefs.copyWith(excludedCategories: cats);
    await _storage.savePrefs(prefs);
    await _pickDecision();
    notifyListeners();
    return category;
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
    // 先取名稱再建 Place（在從 prefs 刪除名稱之前）。
    final storedName = prefs.excludedPlaceNames[placeId];

    Place? restored;
    if (_pendingUndoPlace?.id == placeId) {
      restored = _pendingUndoPlace;
    } else {
      for (final p in nearby) {
        if (p.id == placeId) {
          restored = p;
          break;
        }
      }
    }
    if (restored == null && storedName != null && storedName.isNotEmpty) {
      restored = Place(
        id: placeId,
        name: storedName,
        lat: 25.0478,
        lng: 121.5170,
        isDemo: placeId.startsWith('demo_'),
      );
    }

    final ids = {...prefs.excludedPlaceIds}..remove(placeId);
    final names = {...prefs.excludedPlaceNames}..remove(placeId);
    prefs = prefs.copyWith(excludedPlaceIds: ids, excludedPlaceNames: names);
    _skippedThisSession.remove(placeId);
    _pendingUndoPlace = null;

    if (restored != null) {
      current = Decision(
        place: restored,
        reasonZh: '已復原你剛才排除的店',
        score: 1,
        mealSlot: mealSlot.labelZh,
      );
      if (statusNote != null && statusNote!.contains('目前沒有合適選項')) {
        statusNote = isDemo
            ? '示範模式 · 非你附近的真實店家'
            : (locationOk ? null : statusNote);
      }
      notifyListeners();
      await _storage.savePrefs(prefs);
      return;
    }

    await _storage.savePrefs(prefs);
    await _pickDecision(initial: true);
    notifyListeners();
  }

  /// 一鍵復原剛排除的店（持久按鈕／SnackBar 共用）。
  Future<void> undoLastExcludedPlace() async {
    final pending = _pendingUndoPlace;
    if (pending == null) return;
    await removeExcludedPlace(pending.id);
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
