# 吃定了（EatSet）

幫有選擇困難的人**直接決定這一餐吃哪一家**——不是長清單，是一個答案。

- 顯示名稱：**吃定了**
- Package：`eatset` / Android `com.eatset.eatset`
- UI：Material 3、全文 **繁體中文（台灣）**

## 功能（MVP）

1. **定位 + Google Places**（未設定後端時使用 **Demo 模式**）
2. **首次使用**：歡迎頁可直接體驗，或先答 3 題二選一（麵/飯、清淡/重口味、想穩妥/想試試新的）；之後可在「我的」重設口味
3. **決策首頁**：依本地時間判斷早餐／午餐／晚餐／宵夜；只給**一家**店與一句理由；真實定位＋真實店家才顯示直線距離；「就吃這個」／「換一個」（每日最多 3 次）；依日期與餐段分開確認，顯示「午餐就這家」等；心情 chip：想穩妥／都可以／想試試新的
4. **均衡提醒**：以已回報吃過的紀錄判斷本週是否偏重口味，有清淡線索時才建議較清爽選項
5. **排除與歷史**：區分「這餐先跳過」與永久排除；收藏與吃過／沒去吃回饋；偏好與紀錄存於 `shared_preferences`
6. **降級**：未定位 → Demo；API 失敗 → 說明與重試，不留空白死畫面
7. **位置**：確認前可先查看地址／開啟 Google Maps，不會寫入用餐紀錄；確認後也能開啟 Google Maps
8. **價格與店家篩選**：首頁點「價格：日常」，可選省錢／日常／不限，切換是否包含飯店餐廳與價格未知店家；另可選距離範圍（500 公尺／800 公尺／1.2 公里／2 公里，以直線距離計算）；設定會保存，套用不扣換店次數。放寬距離會用新半徑重新搜尋一次；縮小距離只在剩下的店家少於 3 家時才重新搜尋，否則直接在已取得的清單中篩選

### 店家照片

決策卡與位置詳情已加入多張照片、攝影者歸因及來源連結，照片服務使用 Places API (New)。未設定後端／Demo 不抓圖。官方 API 未提供評論附圖對應或食物分類，因此目前標示「店家照片」，尚未完成只挑評論食物照。設定與限制見 [照片功能說明](docs/place-photos.md)。

### 新版導覽與回饋

- 底部「這餐／紀錄／我的」三個分頁；主決定按鈕固定，店家資訊可捲動。
- 收藏不會增加確認紀錄；紀錄區分尚未回報、喜歡、普通、不合口味與沒有去吃。
- 僅吃過的紀錄影響推薦學習；「不合口味」降低分數，「永久排除」完全排除。
- 暫時略過保留到本餐結束，重開 App 仍有效；可還原，不扣每日換店次數。
- 首次開啟先展示歡迎頁；未設定後端啟動 Demo 不先請求定位，使用者可主動開啟。
- 資料僅在本機，不會自動同步或備份。商業版功能分級與導入規格見 [UI／UX 與收費規劃](docs/product-and-monetization-plan.md)。目前無實際訂閱功能。

### 價格篩選行為

- 預設「日常」接受 Google `priceLevel` 對應的內部等級 0–2；「省錢」接受 0–1；「不限」接受全部價格等級。
- 卡片顯示相對價格等級（`$` 到 `$$$$`）；這不是人均台幣報價，實際消費仍以菜單為準。缺漏或無效等級顯示「價格未知」。
- 預設包含價格未知店家，但有預算時優先選擇價格已知、符合條件的候選；可關閉「包含價格未知的店家」以嚴格排除。
- 預設排除有住宿類型或明確旅宿名稱的店家；不單憑「飯店」兩字排除，避免誤傷一般中式飯店。沒有類型／名稱線索的附設餐廳可能無法辨識，可手動排除。
- 飯店開關與價格上限分開套用：選「不限」不會自動開啟飯店餐廳。
- 價格與飯店篩選都在附近候選資料上執行，沒有合適店家時提示調整條件，不自動放寬預算或飯店限制。
- 舊版 `budgetSensitive: true` 偏好載入時轉成「省錢」，其餘舊資料預設「日常」。

### 餐段、配額與資訊可信度

- 每一日的早餐／午餐／晚餐／宵夜分別確認，午餐紀錄不會佔用晚餐；舊紀錄未存餐段時依確認時間推算。
- 換店配額仍是每日共 3 次，不隨餐段重設。App 在前景每 30 秒、回到前景與操作前檢查時間；跨日重新讀取配額並清除上一餐的略過狀態。
- 操作進行中鎖定重複與衝突操作；確認成功後同餐重複點擊不再次寫入。換店／確認儲存失敗時提供重試，避免重複扣次或顯示假成功。
- Debug 測試座標不等於裝置定位；未定位、Debug 備援或 Demo 店家都不顯示公尺數。真實距離是直線距離，不宣稱「走路就到」。
- 均衡提醒只在候選具清淡／蔬食線索且無重口味線索時出現；沒有合適候選則用一般推薦，不宣稱已驗證營養或餐點內容。
- 回歸測試：`test/meal_lifecycle_test.dart`、`test/recommendation_honesty_test.dart`、`test/dining_filters_test.dart`。

## 環境需求

- Dart SDK `^3.9.2`（見 `pubspec.yaml`）；本次 macOS／iOS 驗證使用 Flutter **3.44.6**／Dart **3.12.2**
- Android Studio / Xcode（實機或模擬器）
- （真實店家）Node.js 22.16+ 後端與 Google Cloud **Places API (New)** 金鑰

iOS 本機試跑與驗證紀錄見 [docs/local-ios-run.md](docs/local-ios-run.md)。Windows／Android 舊環境筆記中的 Flutter 3.35.x 不代表目前 iOS 原生啟動程式的相容版本。

```bash
export PATH="/workspace/flutter/bin:$PATH"   # 若使用本機 box 上的 SDK
cd eatset
flutter pub get
```

## 執行（Demo 模式，免金鑰）

未提供 `EATSET_API_BASE_URL` 時，App 會載入台灣風格示範店家，完整可演示：

```bash
flutter run
# 或指定裝置
flutter run -d chrome   # Web 亦可，定位可能受限
```

## 使用 Google Places API

申請流程：建立 Cloud 專案 → 連結帳單 → 啟用 **Places API (New)** → 建立金鑰並限制 API 與伺服器出口 IP → 設預算告警及配額 → 只放入後端 secret。完整步驟見 [金鑰申請與接線](docs/places-setup.md)，啟動方式及部署限制見 [後端說明](server/README.md)。金鑰依目前安排最後設定。**上線前請完成 [上線前檢查](docs/launch-checklist.md)**：Google 條款確認、雲端配額與預算、以裝置為單位的限流。

App 只設定公開後端網址，Google 金鑰不進入 App：

```bash
flutter run --dart-define=EATSET_API_BASE_URL=https://api.example.com
```

上例網址須換成實際後端。附近搜尋、詳情和照片都已改走後端及 Places API (New)；舊客戶端金鑰設定不再使用。真實資料及定位成功時顯示 Google 來源說明。

### 收藏與最新資料

真實店家只長期保存 ID，另保存使用者的回饋、確認時間與偏好；旧快照會在讀取時移除。詳情頁重新查詢價格和營業狀態，紀錄／收藏頁先更新前 5 筆，其餘按需更新。更新失敗保留 ID 和個人紀錄、顯示重試；執行期店家資料沒有時限，只要人還在同一處、同一餐段就持續沿用；營業狀態顯示「還有多久打烊」並隨時間自動更新，過了打烊時間就視為已打烊、不再推薦。換餐段、隔天，或回到 App 時已移動超過 500 公尺，才重新搜尋一次。只有從儲存還原、尚無資料的店家，確認前才會重新查詢。Demo 仍可離線展示。

### 斷網時

已載入並篩好的店家全部留在記憶體，斷網後仍可瀏覽、換店、選備選、調整價格與距離篩選、開詳情、確認這餐，都不需要網路。搜尋失敗時保留目前所有結果，首頁顯示「目前沒有網路連線」橫幅與「重新連線」，回到 App 時若上次搜尋是因為沒網路而失敗，會自動重試一次（不使用計時器；換店與選備選不會等待網路）；重試成功後橫幅消失。已決定這餐時不重試。已看過的照片留在記憶體（見 [place-photos.md](docs/place-photos.md)），沒看過的照片在離線時只顯示一行「離線中」，網路恢復後自動載入。限制：關閉 App 後記憶體清空，此時沒有網路就無法顯示店家，因為 Google 條款不允許把店家內容存到手機（只可存 place ID）。

## 測試與分析

```bash
flutter analyze
flutter test
cd server
npm test
```

單元測試涵蓋決策評分、過濾、均衡提醒、餐段時段，以及後端傳輸、ID 儲存遷移、店家更新失敗與照片流程；後端測試涵蓋金鑰隔離、簽章、限額、重啟持久化及併發。

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
  models/          # Place、MealSlot、Mood、UserPrefs
  services/        # 定位、Places、Demo、決策引擎、儲存、Maps
  providers/       # AppState（provider）
  screens/         # Welcome、AppShell、Home、History、Preferences、位置預覽
  widgets/         # Mood chips、Decision card
docs/
  places-setup.md  # 金鑰申請及後端接線
server/            # Node HTTP 後端、SQLite 配額與用量
test/
  decision_engine_test.dart
  places_service_test.dart
```

## 刻意不做（Out of scope）

應用內地圖、付款、訂位、社交、完整營養引擎。

## 授權與金鑰安全

- `.env`、`server/.env` 與 SQLite 執行資料已列入 `.gitignore`。
- 後端尚未部署；目前匿名端點以 IP／全站配額限流，沒有會員或裝置驗證。
- 請勿將真實 API 金鑰推送到 Git。
