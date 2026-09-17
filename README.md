# 吃定了（EatSet）

幫有選擇困難的人**直接決定這一餐吃哪一家**——不是長清單，是一個答案。

- 顯示名稱：**吃定了**
- Package：`eatset` / Android `com.eatset.eatset`
- UI：Material 3、全文 **繁體中文（台灣）**

## 功能（MVP）

1. **定位 + Google Places**（無金鑰時自動 **Demo 模式**）
2. **Cold start**：3 題二選一（麵/飯、清淡/重口味、想穩妥/想試試新的）；可「先用預設，直接決定」
3. **決策首頁**：依本地時間判斷早餐／午餐／晚餐／宵夜；只給**一家**店、距離與一句理由；「就吃這個」／「換一個」（每日最多 3 次）；當日確認後回首頁顯示「今天就這家」；心情 chip：想穩妥／都可以／想試試新的
4. **均衡提醒**：若本週偏重口味，偶爾建議較清爽選項
5. **排除與歷史**：不要這家／不要這類；偏好與紀錄存於 `shared_preferences`
6. **降級**：定位或 API 失敗 → Demo／說明文字，不留空白死畫面
7. **導航**：確認後以 `url_launcher` 開啟 Google Maps 搜尋／導航

## 環境需求

- Flutter SDK 3.9+（本專案開發時使用 `/workspace/flutter/bin`）
- Android Studio / Xcode（實機或模擬器）
- （可選）Google Cloud **Places API** 金鑰

```bash
export PATH="/workspace/flutter/bin:$PATH"   # 若使用本機 box 上的 SDK
cd eatset
flutter pub get
```

## 執行（Demo 模式，免金鑰）

未提供 `GOOGLE_PLACES_API_KEY` 時，App 會載入台灣風格示範店家，完整可演示：

```bash
flutter run
# 或指定裝置
flutter run -d chrome   # Web 亦可，定位可能受限
```

## 使用 Google Places API

完整步驟（啟用 API、限制金鑰、驗證歸因）：見 **[docs/places-setup.md；本機模擬器見 [local-android-run.md](docs/local-android-run.md)](docs/places-setup.md)**。

1. 在 [Google Cloud Console](https://console.cloud.google.com/) 啟用 **Places API**（Nearby Search）。
2. 建立 API 金鑰，並依平台限制（Android `com.eatset.eatset`／iOS `com.eatset.eatset`／Web referrer）。
3. **擇一**提供金鑰（**勿提交真實金鑰**）：

### A. 執行時 dart-define（**建議／優先**，不必改任何 source 檔）

```bash
flutter run --dart-define=GOOGLE_PLACES_API_KEY=你的金鑰
```

成功時首頁底部會出現細字「店家資料來自 Google」；Demo 模式不會顯示。

### B. 本機設定檔（gitignored）

```bash
cp lib/config/api_keys.example.dart lib/config/api_keys.local.dart
# 編輯 api_keys.local.dart 填入金鑰
# 啟用：編輯 lib/config/api_keys_source.dart
#   把 export 'api_keys_stub.dart';
#   改成 export 'api_keys.local.dart';
```

未改 `api_keys_source.dart` 時會繼續走 stub（空金鑰 → Demo），避免「檔案存在卻沒生效」的 silent no-op。  
協作時請優先用 dart-define，避免把 local export 推上共用分支。

亦見專案根目錄 `.env.example`（文件用途；本 MVP 以 dart-define／local dart 為準）。

### 決策篩選（已內建）

Nearby 回傳後由 `DecisionEngine` 偏好營業中、較高評分店家（見 `docs/places-setup.md；本機模擬器見 [local-android-run.md](docs/local-android-run.md)`）。

## 測試與分析

```bash
flutter analyze
flutter test
```

單元測試涵蓋決策評分、過濾、均衡提醒、餐段時段，以及 Places（mock HTTP：OK／REQUEST_DENIED／無金鑰）。

## Android 注意事項

- `AndroidManifest.xml` 已設顯示名稱「吃定了」，並宣告 `INTERNET`、`ACCESS_FINE_LOCATION`、`ACCESS_COARSE_LOCATION`。
- `minSdk` 依 Flutter 預設；定位需在系統設定允許權限。
- 確認後開啟 Maps 需可處理 `https` intent（已加 `queries`）。

## iOS 注意事項

- `CFBundleDisplayName`／`CFBundleName` 為「吃定了」。
- `Info.plist` 已加 `NSLocationWhenInUseUsageDescription`（繁中說明）。
- 實機／模擬器需允許定位；模擬器可自行設定位置。
- 需能開啟 Safari／Maps 的 https URL。

## 專案結構

```
lib/
  main.dart
  config/          # API 金鑰（stub / source 切換 + example／local）
  models/          # Place、MealSlot、Mood、UserPrefs
  services/        # 定位、Places、Demo、決策引擎、儲存、Maps
  providers/       # AppState（provider）
  screens/         # Cold start、Home、History
  widgets/         # Mood chips、Decision card
docs/
  places-setup.md  # 科林本機接真 Places 的清單
test/
  decision_engine_test.dart
  places_service_test.dart
```

## 刻意不做（Out of scope）

應用內地圖、付款、訂位、社交、完整營養引擎。

## 授權與金鑰安全

- `lib/config/api_keys.local.dart`、`.env` 已列入 `.gitignore`。
- 請勿將真實 API 金鑰推送到 Git。
