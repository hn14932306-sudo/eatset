/// 依台灣常見作息劃分的餐段。
enum MealSlot {
  breakfast('早餐'),
  lunch('午餐'),
  dinner('晚餐'),
  lateNight('宵夜');

  const MealSlot(this.labelZh);
  final String labelZh;

  /// 依本地時間判斷目前餐段（台灣友善時段）。
  static MealSlot fromDateTime(DateTime now) {
    final minutes = now.hour * 60 + now.minute;
    // 早餐 05:00–10:29、午餐 10:30–14:29、晚餐 14:30–20:29、宵夜其餘
    if (minutes >= 5 * 60 && minutes < 10 * 60 + 30) return MealSlot.breakfast;
    if (minutes >= 10 * 60 + 30 && minutes < 14 * 60 + 30) {
      return MealSlot.lunch;
    }
    if (minutes >= 14 * 60 + 30 && minutes < 20 * 60 + 30) {
      return MealSlot.dinner;
    }
    return MealSlot.lateNight;
  }
}
