/// Google 的相對價格等級，不代表固定的人均台幣金額。
enum MealBudget {
  economical('省錢', 1),
  everyday('日常', 2),
  any('不限', null);

  const MealBudget(this.labelZh, this.maxPriceLevel);
  final String labelZh;
  final int? maxPriceLevel;
}
