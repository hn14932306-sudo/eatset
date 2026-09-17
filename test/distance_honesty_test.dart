import 'package:eatset/models/place.dart';
import 'package:eatset/widgets/decision_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hides misleading meters when showRealDistance is false',
      (tester) async {
    const place = Place(
      id: 'demo_x',
      name: '示範麵店',
      lat: 25.0,
      lng: 121.5,
      distanceMeters: 156,
      isDemo: true,
      rating: 4.5,
    );
    const decision = Decision(
      place: place,
      reasonZh: '測試理由',
      score: 1,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DecisionCard(
            decision: decision,
            showRealDistance: false,
          ),
        ),
      ),
    );

    expect(find.text('示範距離'), findsOneWidget);
    expect(find.textContaining('公尺'), findsNothing);
  });

  testWidgets('shows meters when location is real', (tester) async {
    const place = Place(
      id: 'demo_x',
      name: '示範麵店',
      lat: 25.0,
      lng: 121.5,
      distanceMeters: 156,
      isDemo: true,
      rating: 4.5,
    );
    const decision = Decision(
      place: place,
      reasonZh: '測試理由',
      score: 1,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DecisionCard(
            decision: decision,
            showRealDistance: true,
          ),
        ),
      ),
    );

    expect(find.textContaining('156'), findsOneWidget);
  });

  testWidgets('balance nudge banner is visible', (tester) async {
    const place = Place(
      id: 'p',
      name: '清粥',
      lat: 25.0,
      lng: 121.5,
      isDemo: true,
    );
    const decision = Decision(
      place: place,
      reasonZh: '清淡一點',
      score: 1,
      isBalanceNudge: true,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DecisionCard(decision: decision),
        ),
      ),
    );

    expect(find.textContaining('均衡小提醒'), findsOneWidget);
  });
}
