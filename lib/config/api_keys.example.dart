/// 範例：複製此檔為 `api_keys.local.dart` 並填入金鑰。
/// `api_keys.local.dart` 已列入 .gitignore，請勿提交真實金鑰。
///
/// 啟用步驟：
/// 1. `cp lib/config/api_keys.example.dart lib/config/api_keys.local.dart`
/// 2. 將下方金鑰改成你的 Places API key
/// 3. 編輯 `lib/config/api_keys_source.dart`，把
///    `export 'api_keys_stub.dart';` 改成 `export 'api_keys.local.dart';`
///
/// 亦可在執行時使用：
///   flutter run --dart-define=GOOGLE_PLACES_API_KEY=你的金鑰
class ApiKeysLocal {
  static const String googlePlacesApiKey = 'YOUR_GOOGLE_PLACES_API_KEY';
}
