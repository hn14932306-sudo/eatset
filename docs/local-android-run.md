# 本機 Android 模擬器執行筆記（DESKTOP／Windows）

給在 Windows 上跑 `E:\project\eatset`、驗證真 Places 與定位用。  
Places 金鑰步驟見 [places-setup.md](./places-setup.md)。

## 成功標準

- `flutter run -d emulator-…` 能裝上模擬器
- 後端與金鑰就緒且取得裝置定位時底部可見「店家資料來自 Google」
- 模擬器 GPS 逾時／Debug 備援座標只展示 Demo；取得裝置定位後才查真店

## 1. Flutter／JDK（重要）

以下為原 Windows 環境紀錄，這輪未重新驗證 Android。macOS 本輪使用 Flutter 3.44.6，請以實際建置結果確認相容性：

| 項目 | 建議 |
|------|------|
| Flutter | **3.35.x**（勿用過新的 3.47，會要求 AGP 9／Gradle 9／Kotlin 2.2+） |
| JDK | **17+**（本機用 Microsoft JDK 21 亦可） |
| 模擬器 | **API 31+**（API 28 在新 Flutter 會標 unsupported） |

設定 JDK（PowerShell）：

```powershell
flutter config --jdk-dir="C:\Program Files\Microsoft\jdk-21.0.12.8-hotspot"
```

確認：

```powershell
flutter --version
flutter doctor
```

## 2. 模擬器

建議 AVD：`Pixel_API_31`（`system-images;android-31;google_apis;x86_64`）。

```powershell
emulator -avd Pixel_API_31 -no-snapshot-load
adb devices
flutter devices
```

若出現 `unauthorized`：清除 AVD 資料後冷開機，或在模擬器上允許 USB 偵錯。

## 3. 指定後端執行

在專案根目錄（**勿把金鑰 commit／貼到聊天**）：

```powershell
cd E:\project\eatset
flutter pub get
flutter run -d emulator-5554 --dart-define=EATSET_API_BASE_URL=http://10.0.2.2:8787
```

裝置 id 以 `flutter devices` 為準。不要選 `windows` 桌面目標（本專案未開 Windows 桌面）。

先依 [後端說明](../server/README.md) 在主機啟動服務。Google 金鑰只放後端，以 API 與伺服器出口 IP 限制；不再使用 Android 套件／SHA-1 限制 REST 金鑰。正式版／真機使用 HTTPS 網址。

## 4. 定位在模擬器上的行為

常見現象：`Geolocator.getCurrentPosition` **TimeoutException（約 6～12 秒）**，權限已允許仍失敗。這是模擬器 GPS／fused location 問題，不是 Places 金鑰壞掉。

App 行為（`lib/services/location_service.dart`）：

1. 先 `getCurrentPosition`（短逾時）
2. 失敗則 `getLastKnownPosition`
3. Android 再試 `forceLocationManager: true`
4. **僅 `kDebugMode`**：仍失敗則使用台北車站附近測試座標（`25.0478, 121.5170`），僅供 Demo；不送真實 Places 查詢
5. **Release 建置**：不會走第 4 步；逾時會顯示定位失敗說明＋「開啟定位」。Debug 真機也可能使用測試座標，仍不當成真實定位

手動餵模擬器座標（較可靠）：

1. 模擬器右側 `…`（Extended controls）→ **Location**
2. 選點或輸入緯經度 → **Send**
3. App 內點「開啟定位」或下拉重新整理

`adb emu geo fix <lng> <lat>` 在部分映像不一定會進到 Geolocator。

## 5. 畫面判讀

- 「店家資料來自 Google」：後端回傳真實店家。
- 示範橫幅：未設定後端或尚無装置定位，不冒充附近真店。
- 查詢失敗：提供重試，既有紀錄仍保留；過期價格與營業狀態不再當成最新資訊。

## 6. 相關檔案

- `lib/services/location_service.dart` — 定位與 Debug 後備
- `docs/places-setup.md` — Cloud Console 金鑰
- `android/` — AGP 8.9.1、Gradle 8.12（配合 Flutter 3.35）
