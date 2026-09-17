import 'package:eatset/models/meal_slot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('meal slot labels are Traditional Chinese', () {
    expect(MealSlot.breakfast.labelZh, '早餐');
    expect(MealSlot.lunch.labelZh, '午餐');
    expect(MealSlot.dinner.labelZh, '晚餐');
    expect(MealSlot.lateNight.labelZh, '宵夜');
  });
}
