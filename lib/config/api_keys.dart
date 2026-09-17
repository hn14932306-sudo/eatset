/// Google Places API 金鑰來源（優先順序）：
/// 1. `--dart-define=GOOGLE_PLACES_API_KEY=...`
/// 2. 本機檔 `api_keys.local.dart`（透過 `api_keys_source.dart` 啟用）
/// 3. 空字串 → Demo 模式
///
/// 啟用本機檔（複製 example 後改一行即可，不會 silent no-op）：
/// ```bash
/// cp lib/config/api_keys.example.dart lib/config/api_keys.local.dart
/// # 編輯 api_keys.local.dart 填入金鑰
/// # 將 api_keys_source.dart 的 export 改為：export 'api_keys.local.dart';
/// ```
library;

import 'api_keys_source.dart';

const String _fromDefine = String.fromEnvironment(
  'GOOGLE_PLACES_API_KEY',
  defaultValue: '',
);

/// 目前可用的 Places API 金鑰；空字串表示 Demo 模式。
String get googlePlacesApiKey {
  if (_fromDefine.isNotEmpty) return _fromDefine;
  return ApiKeysLocal.googlePlacesApiKey;
}

bool get hasPlacesApiKey => googlePlacesApiKey.isNotEmpty;
