/// Google Places API 金鑰來源（優先順序）：
/// 1. `--dart-define=GOOGLE_PLACES_API_KEY=...`
/// 2. 可選的本機檔 `api_keys.local.dart`（gitignored）
/// 3. 空字串 → Demo 模式
library;

// 若存在本機金鑰檔，取消下一行註解並實作 ApiKeysLocal：
// import 'api_keys.local.dart' as local;

const String _fromDefine = String.fromEnvironment(
  'GOOGLE_PLACES_API_KEY',
  defaultValue: '',
);

/// 目前可用的 Places API 金鑰；空字串表示 Demo 模式。
String get googlePlacesApiKey {
  if (_fromDefine.isNotEmpty) return _fromDefine;
  // try {
  //   return local.ApiKeysLocal.googlePlacesApiKey;
  // } catch (_) {}
  return '';
}

bool get hasPlacesApiKey => googlePlacesApiKey.isNotEmpty;
