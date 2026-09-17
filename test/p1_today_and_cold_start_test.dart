import 'package:eatset/models/user_prefs.dart';
import 'package:eatset/providers/app_state.dart';
import 'package:eatset/services/decision_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P1-2 cold start', () {
    test('has exactly 3 questions: carb, flavor, mood', () {
      expect(coldStartQuestions.length, 3);
      expect(coldStartQuestions.map((q) => q.id).toList(), [
        'carb',
        'flavor',
        'mood',
      ]);
      expect(coldStartQuestions[0].optionA, '麵');
      expect(coldStartQuestions[0].optionB, '飯');
      expect(coldStartQuestions[1].optionA, '清淡');
      expect(coldStartQuestions[1].optionB, '重口味');
      expect(coldStartQuestions[2].optionA, '想穩妥一點');
      expect(coldStartQuestions[2].optionB, '想試試新的');
    });
  });

  group('P1-1 today confirmed', () {
    test('isSameLocalDay ignores time-of-day', () {
      final a = DateTime(2026, 9, 17, 8, 0);
      final b = DateTime(2026, 9, 17, 22, 30);
      final c = DateTime(2026, 9, 18, 0, 1);
      expect(isSameLocalDay(a, b), isTrue);
      expect(isSameLocalDay(a, c), isFalse);
    });

    test('latestConfirmedOnDay returns newest same-day entry', () {
      final today = DateTime(2026, 9, 17, 12);
      final history = [
        HistoryEntry(
          placeId: 'newer',
          placeName: '新店',
          confirmedAt: DateTime(2026, 9, 17, 19),
        ),
        HistoryEntry(
          placeId: 'older',
          placeName: '舊店',
          confirmedAt: DateTime(2026, 9, 17, 11),
        ),
        HistoryEntry(
          placeId: 'yesterday',
          placeName: '昨天',
          confirmedAt: DateTime(2026, 9, 16, 20),
        ),
      ];
      final hit = latestConfirmedOnDay(history, today);
      expect(hit?.placeId, 'newer');
      expect(hit?.placeName, '新店');
    });

    test('latestConfirmedOnDay is null when none today', () {
      final today = DateTime(2026, 9, 17);
      final history = [
        HistoryEntry(
          placeId: 'y',
          placeName: '昨天',
          confirmedAt: DateTime(2026, 9, 16, 20),
        ),
      ];
      expect(latestConfirmedOnDay(history, today), isNull);
    });
  });
}
