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
  bool isDemo = true;
  bool locationOk = false;
  int rerollsUsedToday = 0;
  final Set<String> _skippedThisSession = {};
  MealSlot mealSlot = MealSlot.fromDateTime(DateTime.now());

  int get rerollsLeft =>
      (DecisionEngine.dailyRerollLimit - rerollsUsedToday)
          .clamp(0, DecisionEngine.dailyRerollLimit);

  Future<void> bootstrap() async {
    status = AppLoadStatus.loading;
    notifyListeners();

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

  Future<void> reroll() async {
    if (rerollsLeft <= 0) return;
    if (current != null) {
      _skippedThisSession.add(current!.place.id);
    }
    rerollsUsedToday += 1;
    await _storage.saveRerollCountToday(rerollsUsedToday);
    await _pickDecision();
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
    prefs = prefs.copyWith(excludedPlaceIds: ids);
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

  Future<void> refreshPlaces() async {
    status = AppLoadStatus.loading;
    notifyListeners();
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
