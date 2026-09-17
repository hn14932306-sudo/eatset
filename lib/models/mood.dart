/// 使用者當下情緒／決策風格。
enum Mood {
  safe('想穩妥', '穩妥'),
  any('都可以', '都行'),
  adventure('想試試新的', '嘗鮮');

  const Mood(this.labelZh, this.shortLabel);
  final String labelZh;
  final String shortLabel;
}
