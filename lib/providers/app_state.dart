import 'package:flutter/foundation.dart';

import '../models/meal_slot.dart';
import '../models/meal_budget.dart';
import '../models/mood.dart';
import '../models/place.dart';
import '../models/user_prefs.dart';
import '../services/decision_engine.dart';
import '../services/demo_places.dart';
import '../services/location_service.dart';
import '../services/places_service.dart';
import '../services/storage_service.dart';
import '../services/backend_client.dart';

enum AppLoadStatus { idle, loading, ready, error }

/// 同一本地日曆日（年／月／日）。
bool isSameLocalDay(DateTime a, DateTime b) {
  final la = a.toLocal();
  final lb = b.toLocal();
  return la.year == lb.year && la.month == lb.month && la.day == lb.day;
}

/// 當日最新一筆「就吃這個」紀錄（history 假設新→舊）。
HistoryEntry? latestConfirmedOnDay(List<HistoryEntry> history, DateTime day) {
  for (final h in history) {
    if (isSameLocalDay(h.confirmedAt, day)) return h;
  }
  return null;
}

/// 同一日、同一餐段的最新確認；舊資料沒有餐段時依確認時間推算。
HistoryEntry? latestConfirmedForMeal(List<HistoryEntry> history, DateTime now) {
  final slot = MealSlot.fromDateTime(now.toLocal());
  for (final entry in history) {
    final entrySlot =
        entry.mealSlot ??
        MealSlot.fromDateTime(entry.confirmedAt.toLocal()).labelZh;
    if (entry.feedback != MealFeedback.notEaten &&
        isSameLocalDay(entry.confirmedAt, now) &&
        entrySlot == slot.labelZh) {
      return entry;
    }
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
    DateTime Function()? now,
  }) : _location = locationService ?? LocationService(),
       _places = placesService ?? PlacesService(),
       _storage = storageService ?? StorageService(),
       _engine = decisionEngine ?? DecisionEngine(),
       _now = now ?? DateTime.now,
       _period = (now ?? DateTime.now)().toLocal() {
    mealSlot = MealSlot.fromDateTime(_period);
  }

  final LocationService _location;
  final PlacesService _places;
  final StorageService _storage;
  final DecisionEngine _engine;
  final DateTime Function() _now;
  DateTime _period;
  bool _actionInProgress = false;
  bool _disposed = false;
  bool get isBusy => _actionInProgress || status == AppLoadStatus.loading;
  String? actionError;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// 第一個操作同步上鎖；重複點擊與互相衝突的操作不排隊。
  Future<T> _runAction<T>(
    Future<T> Function() action, {
    required T ignored,
  }) async {
    if (isBusy || _disposed) return ignored;
    _actionInProgress = true;
    actionError = null;
    notifyListeners();
    try {
      await _syncTime();
      return await action();
    } finally {
      _actionInProgress = false;
      notifyListeners();
    }
  }

  /// 前景定時檢查、從背景返回，以及每次操作前共用同一路徑。
  Future<void> syncTime() async {
    final at = _now().toLocal();
    if (isSameLocalDay(_period, at) &&
        MealSlot.fromDateTime(_period) == MealSlot.fromDateTime(at)) {
      return;
    }
    try {
      await _runAction<void>(() async {}, ignored: null);
    } catch (_) {
      actionError = '更新餐段失敗，請重新整理後再試。';
      notifyListeners();
    }
  }

  Future<void> _syncTime() async {
    final at = _now().toLocal();
    final newSlot = MealSlot.fromDateTime(at);
    final newDay = !isSameLocalDay(_period, at);
    if (!newDay && MealSlot.fromDateTime(_period) == newSlot) return;
    if (newDay) {
      rerollsUsedToday = await _storage.loadRerollCountToday(day: at);
    }
    final mealSkips = await _storage.loadMealSkips(_mealKey(at));
    _period = at;
    mealSlot = newSlot;
    _forceRedecide = false;
    _skippedThisSession.clear();
    _skippedThisMeal = mealSkips;
    _pendingUndoPlace = null;
    if (status == AppLoadStatus.ready && prefs.coldStartDone) {
      await _pickDecision(initial: true);
    }
  }

  AppLoadStatus status = AppLoadStatus.idle;
  UserPrefs prefs = const UserPrefs();
  List<Place> nearby = const [];

  /// When and where the current [nearby] list came from a real search.
  /// Public so tests can set them.
  DateTime? nearbyFetchedAt;
  UserLocation? nearbyCenter;

  /// True once a search failed for lack of a connection; the next successful
  /// search clears it. Everything already loaded stays fully usable meanwhile,
  /// because it lives in memory and needs no request to browse, filter, pick,
  /// or confirm.
  bool offline = false;
  static bool _isOffline(Object e) =>
      e is BackendException && e.code == 'NETWORK_FAILED';

  /// The radius that search used; candidates beyond it were never fetched.
  int? nearbyRadius;

  /// A second pull within this window would buy identical results.
  static const minRefreshInterval = Duration(seconds: 90);

  /// Beyond this the list describes another neighbourhood.
  static const movedMeters = 500.0;

  /// Place data has no expiry: it stays valid for as long as the user is in the
  /// same place and the same meal. What changes the answer is context, not the
  /// clock. A list searched in an earlier meal (or on another day) is outdated:
  /// restaurants that opened since are missing and the ones that closed are shown.
  bool get nearbyIsOutdated {
    final at = nearbyFetchedAt?.toLocal();
    if (isDemo || nearby.isEmpty || at == null) return false;
    final now = _now().toLocal();
    return !isSameLocalDay(at, now) ||
        MealSlot.fromDateTime(at) != MealSlot.fromDateTime(now);
  }

  /// A wider range needs a new search (nothing beyond the old radius was
  /// fetched). A narrower one is a local filter, unless it leaves too few
  /// candidates, when one search at the smaller radius gives a fuller list.
  /// Demo data has nothing to search.
  bool _rangeNeedsSearch() {
    if (isDemo || nearby.isEmpty) return false;
    final fetched = nearbyRadius;
    if (fetched == null) return false;
    if (prefs.maxDistanceMeters > fetched) return true;
    return _engine.filterCandidates(nearby, prefs).length < thinCandidateCount;
  }

  /// On returning to the foreground after a search failed for lack of a
  /// connection, try once more (a cold start with nothing loaded is retried the
  /// same way). Only then, never on a timer or for reroll/selection, which must
  /// not wait on a dead connection. A failed attempt never reaches Google.
  Future<void> retryAfterOffline() async {
    if (!offline || isBusy) return;
    if (status == AppLoadStatus.error) {
      await bootstrap();
      return;
    }
    if (isDemo || nearby.isEmpty || !prefs.coldStartDone || hasConfirmedMeal) {
      return;
    }
    await _runAction(() => _refreshNearby(onlyIfMoved: false), ignored: null);
  }

  /// Pull-to-refresh entry point. Repeating it inside [minRefreshInterval]
  /// returns immediately instead of paying for the same search again.
  Future<void> refreshPlacesUnlessRecent() {
    final at = nearbyFetchedAt;
    final recent =
        !isDemo &&
        nearby.isNotEmpty &&
        status == AppLoadStatus.ready &&
        at != null &&
        DateTime.now().difference(at) < minRefreshInterval;
    return recent ? Future.value() : refreshPlaces();
  }

  /// Re-search only when the answer would actually differ, and only when the
  /// user is back (resume, reroll, picking an alternative), never on a timer:
  /// the list is from an earlier meal, or (with [checkMoved], which reads the
  /// device location) the user is now somewhere else. Keeps the restaurant on
  /// screen if it is still eligible, and never swaps real results for demo or
  /// empty ones.
  Future<void> refreshIfOutdated({bool checkMoved = false}) async {
    if (isDemo || nearby.isEmpty || hasConfirmedMeal || !prefs.coldStartDone) {
      return;
    }
    final outdated = nearbyIsOutdated;
    if (!outdated && !checkMoved) return;
    await _runAction(
      () => _refreshNearby(onlyIfMoved: !outdated),
      ignored: null,
    );
  }

  Future<void> _refreshNearby({required bool onlyIfMoved}) async {
    status = AppLoadStatus.loading;
    notifyListeners();
    try {
      final locResult = await _location.getCurrentLocation();
      final here = locResult.location;
      if (here?.fromDevice != true) {
        status = AppLoadStatus.ready;
        return;
      }
      if (onlyIfMoved) {
        final c = nearbyCenter;
        if (c == null ||
            DemoPlaces.haversineMeters(c.lat, c.lng, here!.lat, here.lng) <
                movedMeters) {
          status = AppLoadStatus.ready;
          return;
        }
      }
      final result = await _places.fetchNearby(
        location: here,
        radiusMeters: prefs.maxDistanceMeters,
      );
      if (result.isDemo || result.places.isEmpty) {
        status = AppLoadStatus.ready;
        return;
      }
      _applyLocationResult(locResult);
      final keepId = current?.place.id;
      nearby = result.places;
      nearbyFetchedAt = _now();
      offline = false;
      nearbyCenter = here;
      nearbyRadius = prefs.maxDistanceMeters;
      isDemo = false;
      statusNote = result.noteZh;
      final shown = current;
      final same = keepId == null
          ? null
          : result.places.where((p) => p.id == keepId).firstOrNull;
      if (shown != null &&
          same != null &&
          _engine
              .filterCandidates(
                [same],
                prefs,
                skipIds: {..._skippedThisSession, ..._skippedThisMeal},
              )
              .isNotEmpty) {
        current = Decision(
          place: same,
          reasonZh: shown.reasonZh,
          score: shown.score,
          mealSlot: shown.mealSlot,
          isBalanceNudge: shown.isBalanceNudge,
        );
      } else {
        await _pickDecision(initial: true);
      }
      status = AppLoadStatus.ready;
    } catch (e, st) {
      debugPrint('refreshIfOutdated failed: $e\n$st');
      status = AppLoadStatus.ready;
      if (_isOffline(e)) {
        offline = true;
      } else {
        actionError = '更新附近店家失敗，先保留目前推薦；可下拉重新整理。';
      }
    }
  }

  List<HistoryEntry> history = const [];
  List<Place> favorites = const [];
  final Map<String, Place> _resolvedPlaces = {};
  final Map<String, Future<Place>> _placeRequests = {};
  final Map<String, String> placeErrors = {};
  bool isRefreshingPlace(String id) => _placeRequests.containsKey(id);

  Place resolvePlace(String id, {Place? fallback}) {
    if (placeErrors.containsKey(id)) return Place.reference(id);
    for (final p in [
      _resolvedPlaces[id],
      if (id.startsWith('demo_'))
        ...DemoPlaces.seededNear().where((p) => p.id == id),
      ...nearby.where((p) => p.id == id),
      fallback,
    ]) {
      if (p != null && !p.needsRefresh) return p;
    }
    return Place.reference(id);
  }

  Future<Place> refreshPlace(String id, {bool force = false}) {
    final active = _placeRequests[id];
    if (active != null) return active;
    final known = resolvePlace(id);
    if (!force && !known.needsRefresh) return Future.value(known);
    final request = () async {
      try {
        final fresh = await _places.fetchDetails(id);
        _resolvedPlaces[id] = fresh;
        placeErrors.remove(id);
        nearby = nearby.map((p) => p.id == id ? fresh : p).toList();
        final shown = current;
        if (shown?.place.id == id) {
          current = Decision(
            place: fresh,
            reasonZh: '店家資訊已更新，出發前請確認。',
            score: shown!.score,
            mealSlot: shown.mealSlot,
          );
        }
        return fresh;
      } catch (error) {
        _resolvedPlaces.remove(id);
        placeErrors[id] = error is BackendException
            ? error.message
            : '店家資訊暫時無法更新，請稍後再試。';
        rethrow;
      } finally {
        _placeRequests.remove(id);
        notifyListeners();
      }
    }();
    _placeRequests[id] = request;
    notifyListeners();
    return request;
  }

  Set<String> _skippedThisMeal = {};
  int get skippedThisMealCount => _skippedThisMeal.length;
  String _mealKey(DateTime at) =>
      '${at.year}-${at.month}-${at.day}-${MealSlot.fromDateTime(at).name}';
  bool isFavorite(String placeId) => favorites.any((p) => p.id == placeId);

  Future<void> toggleFavorite(Place place) => _runAction(() async {
    final updated = isFavorite(place.id)
        ? favorites.where((p) => p.id != place.id).toList()
        : [place, ...favorites];
    await _storage.saveFavorites(updated);
    favorites = updated;
  }, ignored: null);

  Future<void> recordFeedback(String entryId, MealFeedback feedback) =>
      _runAction(() async {
        final updated = history
            .map((h) => h.id == entryId ? h.withFeedback(feedback) : h)
            .toList();
        await _storage.saveHistory(updated);
        history = updated;
        if (!hasConfirmedMeal) await _pickDecision(initial: true);
      }, ignored: null);

  Future<void> skipCurrentMeal() => _runAction(() async {
    final place = current?.place;
    if (place == null) return;
    final updated = {..._skippedThisMeal, place.id};
    await _storage.saveMealSkips(_mealKey(_now().toLocal()), updated);
    _skippedThisMeal = updated;
    _pendingUndoPlace = null;
    await _pickDecision();
  }, ignored: null);

  Future<void> restoreMealSkips() => _runAction(() async {
    await _storage.saveMealSkips(_mealKey(_now().toLocal()), {});
    _skippedThisMeal = {};
    await _pickDecision(initial: true);
  }, ignored: null);
  Decision? current;

  /// The two visible alternatives use the same eligibility rules as the main
  /// recommendation. Stable scores prevent unrelated rebuilds changing cards.
  List<Place> get alternatives {
    if (hasConfirmedMeal || current == null) return const [];
    final candidates = _engine.filterCandidates(
      nearby,
      prefs,
      skipIds: {..._skippedThisMeal, ..._skippedThisSession, current!.place.id},
    );
    final scores = {
      for (final p in candidates)
        p.id: _engine.scorePlace(
          p,
          prefs,
          mealSlot: mealSlot,
          recentHistory: history,
          addJitter: false,
        ),
    };
    candidates.sort((a, b) {
      if (prefs.mealBudget.maxPriceLevel != null &&
          (a.knownPriceLevel == null) != (b.knownPriceLevel == null)) {
        return a.knownPriceLevel == null ? 1 : -1;
      }
      final score = scores[b.id]!.compareTo(scores[a.id]!);
      return score == 0 ? a.id.compareTo(b.id) : score;
    });
    final seen = <String>{};
    return candidates.where((p) => seen.add(p.id)).take(2).toList();
  }

  /// Choosing a visible restaurant is browsing, not a random reroll or meal
  /// confirmation. Recheck after the action lock and meal-period sync.
  Future<bool> selectAlternative(String id) async {
    try {
      await refreshIfOutdated();
      return await _runAction(() async {
        if (hasConfirmedMeal) return false;
        final choices = alternatives.where((p) => p.id == id);
        if (choices.isEmpty) {
          actionError = '這家店目前不在備選中，請重新整理後再選。';
          return false;
        }
        final place = choices.first;
        current = _engine.decide(
          [place],
          prefs,
          mealSlot: mealSlot,
          history: history,
          showRealDistance: showRealDistance,
        );
        _pendingUndoPlace = null;
        return current != null;
      }, ignored: false);
    } catch (_) {
      actionError = '切換店家失敗，請再試一次。';
      notifyListeners();
      return false;
    }
  }

  String? statusNote;

  /// bootstrap／refresh 失敗時給 UI 的可恢復訊息
  String? errorMessage;
  bool isDemo = true;
  bool locationOk = false;

  /// 系統定位服務關閉。
  bool locationServiceDisabled = false;

  /// 定位權限被拒（可再請求）。
  bool locationDenied = false;

  /// 定位權限永久拒絕（需開設定）。
  bool locationDeniedForever = false;
  int rerollsUsedToday = 0;
  final Set<String> _skippedThisSession = {};
  late MealSlot mealSlot;

  /// 使用者主動要「再決定一次」時暫時隱藏這餐已決定態。
  bool _forceRedecide = false;

  /// 剛排除、可一鍵復原的店（完整 Place，不依賴 nearby 查找）。
  Place? _pendingUndoPlace;

  /// 供 Home 顯示持久復原按鈕（SnackBarAction 在 Flutter Web 常不觸發）。
  Place? get pendingUndoPlace => _pendingUndoPlace;

  bool get hasPendingUndo => _pendingUndoPlace != null;

  /// 冷啟動結束後首頁提示「想穩妥」（toast 用，顯示後清掉）。
  bool showDefaultMoodHint = false;

  /// 心情變更後重算提示（toast 用，顯示後清掉）。
  bool showMoodReselectedHint = false;

  int get rerollsLeft => (DecisionEngine.dailyRerollLimit - rerollsUsedToday)
      .clamp(0, DecisionEngine.dailyRerollLimit);

  bool get hasExclusions =>
      prefs.excludedPlaceIds.isNotEmpty || prefs.excludedCategories.isNotEmpty;

  /// 無真實定位時不可顯示「約 N 公尺」（錨點距離會誤導）。
  bool get showRealDistance => locationOk && !isDemo;

  /// 這餐已確認的歷史（若使用者要求再決定則為 null）。
  HistoryEntry? get mealConfirmed {
    final at = _now().toLocal();
    if (_forceRedecide &&
        isSameLocalDay(_period, at) &&
        mealSlot == MealSlot.fromDateTime(at)) {
      return null;
    }
    return latestConfirmedForMeal(history, at);
  }

  bool get hasConfirmedMeal => mealConfirmed != null;

  /// 解析這餐已確認店家（nearby／current 優先，否則用歷史組最小 Place）。
  Place? placeForConfirmedMeal() {
    final entry = mealConfirmed;
    if (entry == null) return null;
    return resolvePlace(entry.placeId, fallback: entry.place);
  }

  /// 軟路徑：離開這餐已確認畫面，回到一般決策卡。
  void requestRedecide() {
    if (isBusy) return;
    _forceRedecide = true;
    notifyListeners();
  }

  void consumeDefaultMoodHint() {
    if (!showDefaultMoodHint) return;
    showDefaultMoodHint = false;
  }

  void consumeMoodReselectedHint() {
    if (!showMoodReselectedHint) return;
    showMoodReselectedHint = false;
  }

  void _applyLocationResult(LocationResult result) {
    locationOk = result.location?.fromDevice == true;
    locationServiceDisabled =
        result.failure == LocationFailureReason.serviceDisabled;
    locationDenied = result.failure == LocationFailureReason.denied;
    locationDeniedForever =
        result.failure == LocationFailureReason.deniedForever;
  }

  /// 橫幅用：依最後定位結果給誠實短說明。
  String? get locationHelpSubtitle {
    if (locationOk) return null;
    if (locationServiceDisabled) {
      return '裝置定位服務已關閉；請開啟後再試';
    }
    if (locationDeniedForever) {
      return '定位權限被永久拒絕；請到系統設定開啟';
    }
    if (locationDenied) {
      return '尚未允許定位權限；點下方可再請求';
    }
    return isDemo ? '目前先用示範店家 · 何時開定位都可以' : '定位失敗，請再試一次';
  }

  Future<void> bootstrap() async {
    if (isBusy) return;
    status = AppLoadStatus.loading;
    errorMessage = null;
    notifyListeners();

    try {
      prefs = await _storage.loadPrefs();
      history = await _storage.loadHistory();
      favorites = await _storage.loadFavorites();
      _period = _now().toLocal();
      rerollsUsedToday = await _storage.loadRerollCountToday(day: _period);
      mealSlot = MealSlot.fromDateTime(_period);
      _forceRedecide = false;

      _skippedThisMeal = await _storage.loadMealSkips(_mealKey(_period));
      if (!prefs.coldStartDone) {
        nearby = DemoPlaces.seededNear();
        isDemo = true;
        locationOk = false;
        statusNote = '示範模式 · 開啟定位並連接店家資料後可找附近餐廳';
        status = AppLoadStatus.ready;
        notifyListeners();
        return;
      }

      final locResult = _places.isConfigured
          ? await _location.getCurrentLocation()
          : const LocationResult.failure(LocationFailureReason.error);
      _applyLocationResult(locResult);
      final loc = locResult.location;

      final result = await _places.fetchNearby(
        location: loc,
        radiusMeters: prefs.maxDistanceMeters,
      );
      nearby = result.places;
      nearbyFetchedAt = _now();
      offline = false;
      nearbyCenter = loc;
      nearbyRadius = prefs.maxDistanceMeters;
      isDemo = result.isDemo;
      statusNote = result.noteZh;

      if (prefs.coldStartDone) {
        await _pickDecision(initial: true);
      }

      status = AppLoadStatus.ready;
      notifyListeners();
    } catch (e, st) {
      debugPrint('bootstrap failed: $e\n$st');
      offline = _isOffline(e);
      errorMessage = offline ? '目前沒有網路連線，無法載入附近店家。連線後再試一次。' : '啟動時發生問題，請再試一次。';
      status = AppLoadStatus.error;
      notifyListeners();
    }
  }

  Future<void> completeColdStart(Map<String, bool> answers) =>
      _runAction(() => _completeColdStart(answers), ignored: null);

  Future<void> _completeColdStart(Map<String, bool> answers) async {
    // answers: id -> choseA
    // carb: A=麵; flavor: A=清淡; mood: A=想穩妥
    final choseSafe = answers['mood'] ?? true;
    final mood = choseSafe ? Mood.safe : Mood.adventure;
    final updated = prefs.copyWith(
      prefersNoodles: answers['carb'],
      prefersLight: answers['flavor'],
      coldStartDone: true,
      mood: mood,
    );
    await _storage.savePrefs(updated);
    prefs = updated;
    showDefaultMoodHint = mood == Mood.safe;
    await _pickDecision(initial: true);
    notifyListeners();
  }

  /// 跳過冷啟動：套用預設「想穩妥」，直接進決策首頁。
  Future<void> skipColdStart() => _runAction(_skipColdStart, ignored: null);

  Future<void> _skipColdStart() async {
    final updated = prefs.copyWith(coldStartDone: true, mood: Mood.safe);
    await _storage.savePrefs(updated);
    prefs = updated;
    showDefaultMoodHint = true;
    await _pickDecision(initial: true);
    notifyListeners();
  }

  /// 變更心情並重算；不扣每日換次。相同心情則 no-op。
  /// 成功變更時設 [showMoodReselectedHint] 供 UI toast。
  Future<bool> setMood(Mood mood) =>
      _runAction(() => _setMood(mood), ignored: false);

  Future<bool> _setMood(Mood mood) async {
    if (prefs.mood == mood) return false;
    final updated = prefs.copyWith(mood: mood);
    await _storage.savePrefs(updated);
    prefs = updated;
    await _pickDecision(initial: true);
    showMoodReselectedHint = true;
    notifyListeners();
    return true;
  }

  /// 預算調整不扣換店次數；重新開始候選，不沿用舊的略過清單。
  Future<void> setDiningFilters({
    required MealBudget budget,
    required bool includeHotels,
    required bool includeUnknownPrices,
    int? maxDistanceMeters,
  }) => _runAction(
    () => _setDiningFilters(
      budget: budget,
      includeHotels: includeHotels,
      includeUnknownPrices: includeUnknownPrices,
      maxDistanceMeters: maxDistanceMeters,
    ),
    ignored: null,
  );

  /// Fewer than this many eligible candidates after narrowing the range means
  /// the fetched list (chosen by popularity over the old, wider radius) is too
  /// thin to choose from.
  static const thinCandidateCount = 3;

  Future<void> _setDiningFilters({
    required MealBudget budget,
    required bool includeHotels,
    required bool includeUnknownPrices,
    int? maxDistanceMeters,
  }) async {
    final updated = prefs.copyWith(
      mealBudget: budget,
      includeHotelRestaurants: includeHotels,
      includeUnknownPrices: includeUnknownPrices,
      maxDistanceMeters: maxDistanceMeters,
    );
    await _storage.savePrefs(updated);
    final rangeChanged = updated.maxDistanceMeters != prefs.maxDistanceMeters;
    prefs = updated;
    _pendingUndoPlace = null;
    _skippedThisSession.clear();
    _forceRedecide = true;
    if (rangeChanged && _rangeNeedsSearch()) {
      await _refreshNearby(onlyIfMoved: false);
    }
    await _pickDecision(initial: true);
    notifyListeners();
  }

  /// 重抽：若沒有真正換到另一家，不扣每日次數。
  Future<void> reroll() async {
    try {
      await refreshIfOutdated();
      await _runAction(_reroll, ignored: null);
    } catch (_) {
      actionError = '換店失敗，請再試一次；這次未扣次數。';
      notifyListeners();
    }
  }

  Future<void> _reroll() async {
    if (rerollsLeft <= 0) return;
    final actionDay = _now().toLocal();
    final previous = current;
    final previousSkipped = {..._skippedThisSession};
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
    final nextCount = rerollsUsedToday + 1;
    try {
      await _storage.saveRerollCountToday(nextCount, day: actionDay);
    } catch (_) {
      current = previous;
      _skippedThisSession
        ..clear()
        ..addAll(previousSkipped);
      rethrow;
    }
    rerollsUsedToday = nextCount;
    notifyListeners();
  }

  /// 確認這一餐：寫入歷史。地圖改由 S7 畫面開啟。
  Future<Place?> confirmCurrent() async {
    try {
      return await _runAction(_confirmCurrent, ignored: null);
    } catch (_) {
      actionError = '這餐尚未儲存成功，請再試一次。';
      notifyListeners();
      return null;
    }
  }

  Future<Place?> _confirmCurrent() async {
    if (hasConfirmedMeal) return null;
    var d = current;
    if (d == null) return null;
    if (!d.place.isDemo &&
        (d.place.needsRefresh ||
            _resolvedPlaces.containsKey(d.place.id) ||
            placeErrors.containsKey(d.place.id))) {
      var fresh = resolvePlace(d.place.id, fallback: d.place);
      if (fresh.needsRefresh) {
        fresh = await refreshPlace(d.place.id, force: true);
      }
      if (_engine.filterCandidates([fresh], prefs).isEmpty) {
        actionError = '店家資訊已更新，目前不符合這餐條件，請換一家。';
        return null;
      }
      d = Decision(
        place: fresh,
        reasonZh: d.reasonZh,
        score: d.score,
        mealSlot: d.mealSlot,
        isBalanceNudge: d.isBalanceNudge,
      );
      current = d;
    }
    _pendingUndoPlace = null; // 確認後不再顯示復原
    final entry = HistoryEntry(
      placeId: d.place.id,
      placeName: d.place.name,
      confirmedAt: _now().toLocal(),
      cuisineTags: d.place.cuisineTags,
      mealSlot: mealSlot.labelZh,
      place: d.place,
    );
    final updated = [entry, ...history];
    await _storage.saveHistory(updated);
    history = updated;
    if (d.isBalanceNudge) {
      // 主紀錄已成功，提醒時間的儲存失敗不能讓使用者重複確認。
      try {
        await _storage.saveLastBalanceNudgeAt(entry.confirmedAt);
      } catch (e) {
        debugPrint('saveLastBalanceNudgeAt failed: $e');
      }
    }
    _forceRedecide = false;
    notifyListeners();
    return d.place;
  }

  /// 排除目前店家；回傳被排除的店名供 snackbar／復原。
  Future<String?> excludeCurrentPlace() =>
      _runAction(_excludeCurrentPlace, ignored: null);

  Future<String?> _excludeCurrentPlace() async {
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

  Future<String?> excludeCategory(String category) =>
      _runAction(() => _excludeCategory(category), ignored: null);

  Future<String?> _excludeCategory(String category) async {
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

  Future<void> removeExcludedPlace(String placeId) =>
      _runAction(() => _removeExcludedPlace(placeId), ignored: null);

  Future<void> _removeExcludedPlace(String placeId) async {
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
    if (restored == null &&
        placeId.startsWith('demo_') &&
        storedName != null &&
        storedName.isNotEmpty) {
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

    if (restored != null && !restored.needsRefresh) {
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

  Future<void> removeExcludedCategory(String category) =>
      _runAction(() => _removeExcludedCategory(category), ignored: null);

  Future<void> _removeExcludedCategory(String category) async {
    final cats = {...prefs.excludedCategories}..remove(category);
    prefs = prefs.copyWith(excludedCategories: cats);
    await _storage.savePrefs(prefs);
    await _pickDecision(initial: true);
    notifyListeners();
  }

  Future<void> clearAllExclusions() =>
      _runAction(_clearAllExclusions, ignored: null);

  Future<void> _clearAllExclusions() async {
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
    final resolved = resolvePlace(id);
    if (!resolved.needsRefresh) return resolved.name;
    final stored = prefs.excludedPlaceNames[id];
    if (id.startsWith('demo_') && stored != null && stored.isNotEmpty) {
      return stored;
    }
    for (final h in history) {
      if (h.placeId == id && id.startsWith('demo_')) return h.placeName;
    }
    for (final p in nearby) {
      if (p.id == id) return p.name;
    }
    return '已排除的店家';
  }

  Future<void> refreshPlaces() => _runAction(_refreshPlaces, ignored: null);

  Future<void> _refreshPlaces() async {
    final hadContent = nearby.isNotEmpty;
    status = AppLoadStatus.loading;
    errorMessage = null;
    notifyListeners();
    try {
      final locResult = await _location.getCurrentLocation();
      _applyLocationResult(locResult);
      final loc = locResult.location;
      final result = await _places.fetchNearby(
        location: loc,
        radiusMeters: prefs.maxDistanceMeters,
      );
      nearby = result.places;
      nearbyFetchedAt = _now();
      offline = false;
      nearbyCenter = loc;
      nearbyRadius = prefs.maxDistanceMeters;
      isDemo = result.isDemo;
      statusNote = result.noteZh;
      mealSlot = MealSlot.fromDateTime(_now().toLocal());
      await _pickDecision(initial: true);
      status = AppLoadStatus.ready;
      notifyListeners();
    } catch (e, st) {
      debugPrint('refreshPlaces failed: $e\n$st');
      offline = _isOffline(e);
      errorMessage = offline ? '目前沒有網路連線，請連線後再試。' : '重新整理失敗，請再試一次。';
      status = hadContent ? AppLoadStatus.ready : AppLoadStatus.error;
      // With content on screen the offline banner says it; no second message.
      actionError = offline && hadContent ? null : errorMessage;
      notifyListeners();
    }
  }

  /// 「開啟定位」CTA：再請求權限；永久拒絕／服務關閉則開設定，再刷新。
  Future<void> enableLocation() => _runAction(_enableLocation, ignored: null);

  Future<void> _enableLocation() async {
    final hadContent = nearby.isNotEmpty;
    status = AppLoadStatus.loading;
    errorMessage = null;
    notifyListeners();
    try {
      var locResult = await _location.getCurrentLocation();
      _applyLocationResult(locResult);

      if (!locResult.ok) {
        if (locResult.failure == LocationFailureReason.serviceDisabled) {
          await _location.openLocationSettingsSafe();
          locResult = await _location.getCurrentLocation();
          _applyLocationResult(locResult);
        } else if (locResult.failure == LocationFailureReason.deniedForever) {
          await _location.openAppSettingsSafe();
          locResult = await _location.getCurrentLocation();
          _applyLocationResult(locResult);
        }
      }

      final loc = locResult.location;
      final result = await _places.fetchNearby(
        location: loc,
        radiusMeters: prefs.maxDistanceMeters,
      );
      nearby = result.places;
      nearbyFetchedAt = _now();
      offline = false;
      nearbyCenter = loc;
      nearbyRadius = prefs.maxDistanceMeters;
      isDemo = result.isDemo;
      statusNote = result.noteZh;
      mealSlot = MealSlot.fromDateTime(_now().toLocal());
      await _pickDecision(initial: true);
      status = AppLoadStatus.ready;
      notifyListeners();
    } catch (e, st) {
      debugPrint('enableLocation failed: $e\n$st');
      offline = _isOffline(e);
      errorMessage = offline ? '目前沒有網路連線，請連線後再試。' : '開啟定位失敗，請再試一次。';
      status = hadContent ? AppLoadStatus.ready : AppLoadStatus.error;
      actionError = offline && hadContent ? null : errorMessage;
      notifyListeners();
    }
  }

  Future<void> _pickDecision({bool initial = false}) async {
    final now = _now().toLocal();
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
        skipIds: {..._skippedThisSession, ..._skippedThisMeal},
        forceBalance: true,
        showRealDistance: showRealDistance,
      );
    }
    d ??= _engine.decide(
      nearby,
      prefs,
      mealSlot: mealSlot,
      history: history,
      skipIds: {..._skippedThisSession, ..._skippedThisMeal},
      forceBalance: false,
      showRealDistance: showRealDistance,
    );

    // 若全被 skip，清空 session skip 再試一次
    if (d == null && _skippedThisSession.isNotEmpty) {
      _skippedThisSession.clear();
      d = _engine.decide(
        nearby,
        prefs,
        mealSlot: mealSlot,
        history: history,
        skipIds: _skippedThisMeal,
        forceBalance: false,
        showRealDistance: showRealDistance,
      );
    }
    current = d;
    if (d == null) {
      final prefix = statusNote == null ? '' : '$statusNote · ';
      statusNote = '$prefix目前沒有合適選項，請放寬排除或稍後再試';
    }
  }
}
