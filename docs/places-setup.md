# Google Places 設定清單（科林／本機 PC）

真實店家路徑的**程式已就緒**；此文件只在你要接上 Cloud Console 金鑰時使用。  
**請勿把真實金鑰 commit 進 Git。**

## 成功標準

- App 啟動後**不再**顯示「示範模式」橫幅（有定位時）。
- 首頁底部出現細字：「店家資料來自 Google」。
- Demo 模式**不會**出現該歸因文字。

## 1. Google Cloud Console

1. 開啟 [Google Cloud Console](https://console.cloud.google.com/)。
2. 建立或選擇專案。
3. 啟用 **Places API**（Nearby Search / Place Search 傳統 REST）。
4. 「憑證」→ 建立 **API 金鑰**。
5. **限制金鑰**（建議上線前就設好）：
   - **Android**：應用程式限制 → 套件名 `com.eatset.eatset` + SHA-1（debug／release）。
   - **iOS**：應用程式限制 → Bundle ID `com.eatset.eatset`。
   - **Web**（若用 Chrome）：HTTP 參照網址限制（本機開發可用 `http://localhost:*`）。
   - API 限制：只勾選 Places API（或你實際呼叫的 Places 相關 API）。

## 2. 本機執行（優先：dart-define，不必改 source）

在專案根目錄：

```bash
export PATH="/workspace/flutter/bin:$PATH"   # 若使用 box 上的 SDK
cd /path/to/eatset
flutter pub get
flutter run --dart-define=GOOGLE_PLACES_API_KEY=你的金鑰
```

指定裝置範例：

```bash
flutter run -d <deviceId> --dart-define=GOOGLE_PLACES_API_KEY=你的金鑰
```

金鑰優先順序見 `lib/config/api_keys.dart`：

1. `--dart-define=GOOGLE_PLACES_API_KEY=...`（**建議**）
2. 本機 `api_keys.local.dart`（需手動切換 `api_keys_source.dart`）
3. 空 → Demo

## 3. 可選：本機檔（gitignored）

僅在不想每次打 dart-define 時使用：

```bash
cp lib/config/api_keys.example.dart lib/config/api_keys.local.dart
# 編輯 api_keys.local.dart，把 YOUR_GOOGLE_PLACES_API_KEY 換成真金鑰
```

然後**必須**改 `lib/config/api_keys_source.dart`：

```dart
// 從：
export 'api_keys_stub.dart';
// 改成：
export 'api_keys.local.dart';
```

未改 source 時會繼續走 stub（空金鑰 → Demo），這是刻意設計，避免「檔案在卻沒生效」。

確認：

- `lib/config/api_keys.local.dart` 已在 `.gitignore`（勿强制 add）。
- **不要**把 `api_keys_source.dart` 的 local export 永久推到共用 main（若與他人協作，優先用 dart-define）。

## 4. 權限（已就緒，通常不用改）

- Android：`INTERNET`、`ACCESS_FINE_LOCATION`、`ACCESS_COARSE_LOCATION`（`android/app/src/main/AndroidManifest.xml`）。
- iOS：`NSLocationWhenInUseUsageDescription` 繁中說明（`ios/Runner/Info.plist`）。

實機／模擬器仍需在系統對話框允許定位。

## 5. 驗證

| 情況 | 預期 |
|------|------|
| 無金鑰 `flutter run` | Demo 橫幅；**無**「店家資料來自 Google」 |
| 有金鑰但 `REQUEST_DENIED` | Demo 後備 + `noteZh` 含 `REQUEST_DENIED` |
| 有金鑰 + Places 正常 + 定位 OK | `isDemo == false`；底部歸因文字；附近真實店家 |

單元測試（mock，不需真金鑰）：

```bash
flutter test test/places_service_test.dart
```

## 6. 刻意不做（等你審過執行中 App）

- App Store / Play 上架截圖與文案
- 開發者帳號申請流程

## 篩選說明（產品行為）

Nearby Search 回傳原始餐廳列表後，由 `DecisionEngine`：

- 排除 `openNow == false`
- 真實店家：評分低於 3.5 或評論數過低則過濾
- 評分時偏好較高評分／較近距離

因此 API 請求不加 `opennow` 參數，避免營業中過少時整批失敗落入 Demo。
