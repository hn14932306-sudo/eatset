import 'package:eatset/models/place.dart';
import 'package:eatset/providers/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Place place({
    required String id,
    required String name,
    List<String> tags = const [],
  }) {
    return Place(
      id: id,
      name: name,
      lat: 25.0,
      lng: 121.5,
      cuisineTags: tags,
      isDemo: true,
    );
  }

  test('inferCategoryForPlace prefers concrete cuisine tag', () {
    final p = place(id: '1', name: '隨便', tags: ['內用', '麵', '快速']);
    expect(AppState.inferCategoryForPlace(p), '麵');
  });

  test('inferCategoryForPlace falls back to name keywords', () {
    expect(
      AppState.inferCategoryForPlace(place(id: '2', name: '老王牛肉麵')),
      '麵',
    );
    expect(
      AppState.inferCategoryForPlace(place(id: '3', name: '麻辣火鍋')),
      '火鍋',
    );
  });

  test('inferCategoryForPlace returns null when unknown', () {
    expect(
      AppState.inferCategoryForPlace(place(id: '4', name: '神秘小館')),
      isNull,
    );
  });
}
