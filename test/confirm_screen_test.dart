import 'package:eatset/models/place.dart';
import 'package:eatset/screens/confirm_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const place = Place(
    id: 'demo_beef_noodle',
    name: '老王紅燒牛肉麵',
    lat: 25.0478,
    lng: 121.5170,
    isDemo: true,
  );

  testWidgets('S7 maps failure stays on screen with retry and later', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConfirmScreen(
          place: place,
          isDemo: true,
          openMapsOverride: (_) async => false,
          forceWebCopyLink: true,
        ),
      ),
    );

    expect(find.text('就這家了'), findsOneWidget);
    expect(find.text('開啟地圖'), findsOneWidget);

    await tester.tap(find.text('開啟地圖'));
    await tester.pumpAndSettle();

    expect(find.text('就這家了'), findsOneWidget);
    expect(find.textContaining('無法開啟地圖'), findsOneWidget);
    expect(find.text('再試一次'), findsOneWidget);
    expect(find.text('稍後再說'), findsOneWidget);
    expect(find.text('複製地圖連結'), findsOneWidget);
    // 不可假裝成功：主按鈕應改為再試一次，不再顯示開啟地圖
    expect(find.text('開啟地圖'), findsNothing);
  });

  testWidgets('S7 maps success does not show failure banner', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConfirmScreen(place: place, openMapsOverride: (_) async => true),
      ),
    );

    await tester.tap(find.text('開啟地圖'));
    await tester.pumpAndSettle();

    expect(find.textContaining('無法開啟地圖'), findsNothing);
    expect(find.text('開啟地圖'), findsOneWidget);
    expect(find.text('再試一次'), findsNothing);
  });
}
