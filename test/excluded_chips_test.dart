import 'package:eatset/widgets/excluded_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('collapses after 10 chips with 還有 N 項', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExcludedChipsWrap(
            chips: [
              for (var i = 0; i < 12; i++) InputChip(label: Text('chip_$i')),
            ],
          ),
        ),
      ),
    );

    expect(find.text('chip_0'), findsOneWidget);
    expect(find.text('chip_9'), findsOneWidget);
    expect(find.text('chip_10'), findsNothing);
    expect(find.text('還有 2 項'), findsOneWidget);

    await tester.tap(find.text('還有 2 項'));
    await tester.pumpAndSettle();

    expect(find.text('chip_10'), findsOneWidget);
    expect(find.text('chip_11'), findsOneWidget);
    expect(find.text('收合'), findsOneWidget);
  });

  testWidgets('does not show overflow chip when ≤10', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExcludedChipsWrap(
            chips: [
              for (var i = 0; i < 10; i++) InputChip(label: Text('only_$i')),
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('還有'), findsNothing);
    expect(find.text('only_9'), findsOneWidget);
  });
}
