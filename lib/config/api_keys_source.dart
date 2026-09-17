/// 金鑰來源匯出。
///
/// 預設使用 stub（空金鑰 → Demo）。
/// 啟用本機金鑰：
/// 1. `cp lib/config/api_keys.example.dart lib/config/api_keys.local.dart`
/// 2. 編輯 `api_keys.local.dart` 填入金鑰
/// 3. 將下方 export 改成：`export 'api_keys.local.dart';`
library;

export 'api_keys_stub.dart';
