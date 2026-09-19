# 上線前檢查：Google 條款與雲端設定

更新：2026-09-19。這份清單分兩部分：**A. Google 條款**（決定 App 目前的資料處理方式能不能上線）與 **B. 雲端與後端設定**（控制費用與濫用）。每項都標明「已核對官方文件」或「未核對」，沒核對到的以官方原文為準。

## 先看結論

| 項目 | 狀態 | 一句話 |
| --- | --- | --- |
| A. 記憶體內資料處理是否合規 | **未確認，最重要** | 官方政策寫「不得快取，place ID 除外」，我們在記憶體保留資料的做法屬灰色地帶 |
| B1. API 金鑰限制 | 必做 | 限制 API 與伺服器 IP，開發與正式分開 |
| B2. 雲端每日配額 | 必做 | 這是唯一的硬上限，但**不是**金額上限 |
| B3. 預算與警示 | 必做 | 只會通知，不會停用服務 |
| B4. 用量監控 | 必做 | 每天看一次 |
| B5. 正式環境後端設定 | 必做 | 缺了就啟動失敗 |
| B6. 以裝置為單位的限流 | 建議在公開前完成 | 每 IP 限流在行動網路會誤傷用戶，也擋不住直接打後端 |

---

## A. Google 條款

### A1. 官方怎麼說（已核對）

[Places API 政策頁](https://developers.google.com/maps/documentation/places/web-service/policies)：

- place ID 不受快取限制，可以無限期保存。
- 其餘內容「不得預取、快取或儲存，除非屬於允許的例外」，包含名稱、評分、照片。
- 顯示照片或評論時必須標示作者，顯示 Google Maps 標誌或文字，連到 `googleMapsUri`，並提供 `flagContentUri` 檢舉連結；標示要清楚、對比足夠。

我沒能在官方頁面上確認「經緯度可快取 30 天」這個例外，這是我原先的印象，**請以 [Maps Platform 服務條款](https://cloud.google.com/maps-platform/terms/maps-service-terms) 原文為準**，不要引用這份文件的說法。

### A2. 我們目前保留了什麼

**持久保存（寫入手機儲存空間）：**
- 只有 place ID，以及使用者自己的資料：確認時間、餐段、評價、偏好、排除清單。
- 舊版存過的店名、地址等快照，讀取時會被清除。
- 照片、店名、評分、價格不落地。

**只放記憶體、App 關閉即消失：**

| 內容 | 保留多久 | 位置 |
| --- | --- | --- |
| 附近搜尋結果（名稱、地址、評分、價格、營業狀態、照片憑證） | 沒有時限，直到換餐段、隔天、移動超過 500 公尺，或使用者重新整理 | `AppState.nearby`，見 [app_state.dart](../lib/providers/app_state.dart) |
| 照片位元組 | 最多 8 張、10 分鐘 | [photo_memory_cache.dart](../lib/services/photo_memory_cache.dart) |
| 打烊時間 | 同搜尋結果，用來本機倒數 | [place.dart](../lib/models/place.dart) |

### A3. 為什麼是灰色地帶

政策禁止「快取或儲存」，但沒有明說「為了持續顯示畫面，在單次使用期間把已取得的回應留在記憶體」算不算。合理的讀法有兩種：

- **寬鬆**：只要不落地、不跨使用期間、不用於別的目的，就只是顯示，不算快取。
- **嚴格**：任何超出「單次回應當下顯示」的保留，都算快取；「沒有時限」的搜尋結果特別容易被認定。

最風險的兩項是：**搜尋結果沒有時限**，以及**照片位元組保留 10 分鐘**。

### A4. 上線前要做的事

- [ ] 讀完服務條款原文中 Places 的快取與儲存條款，記下條號與期限。
- [ ] 用書面問 Google Maps Platform 支援或業務窗口：「在單次使用期間，把 Nearby Search 結果與照片保留在記憶體以供瀏覽，是否允許？上限多久？」**保留回覆**，這比任何人的解讀都有效。
- [ ] 依回覆選一個做法（見 A5）。
- [ ] 歸因檢查：現在有「Google Maps」文字、作者名稱、來源連結、檢舉連結；**尚未顯示作者頭像與相對日期**（政策寫「空間允許時」與「建議」）。若要保守，補上。
- [ ] 隱私政策與商店審核說明中，寫明使用了 Google Places 資料，且不長期保存。

### A5. 依回覆調整（做法要先想好）

| Google 的回覆 | 建議做法 |
| --- | --- |
| 明確允許在記憶體保留 | 維持現狀，把回覆存檔 |
| 沒有明確答覆 | 採保守：把快取與時限調回去，見下 |
| 不允許 | 採保守，且移除照片記憶體快取 |

**保守做法要改的地方：**
1. 在 [place.dart](../lib/models/place.dart) 的 `needsRefresh` 恢復時限（先前用 5 分鐘），過期後的候選店家不再顯示，由回到 App、換店、選備選時觸發重新搜尋。
2. 縮短或移除 [photo_memory_cache.dart](../lib/services/photo_memory_cache.dart)：`maxAge` 調短，或直接讓 `PlacePhotosService` 不寫入快取。
3. 「不設時限」帶來的省費用效果會消失，重搜次數增加，費用約回到原先估算（見 B2 公式）。

> 目前這批修改**都還沒有 commit**。要保留退路，請先 commit 再決定，這樣任一做法都能回到清楚的版本。

---

## B. 雲端與後端設定

價格取自 [官方價目](https://developers.google.com/maps/billing-and-pricing/pricing)（2026-09-19 核對，實際以官方為準）：

| 項目 | 每千次價格 | 每月免費 |
| --- | --- | --- |
| Nearby Search（Enterprise，含評分、價格等欄位） | $35 | 1,000 次 |
| Place Details（Enterprise） | $20 | 1,000 次 |
| Place Photos | $7 | 1,000 次 |

### B1. API 金鑰

- [ ] 建立**專供後端使用**的金鑰，只放在後端環境變數 `GOOGLE_PLACES_API_KEY`，絕不進 Flutter 或 Git。
- [ ] 「API 限制」只勾 **Places API (New)**。
- [ ] 「應用程式限制」選 **IP 位址**，填後端出口 IP。
- [ ] 開發與正式用**不同的金鑰**，方便單獨停用。
- [ ] 記下更換金鑰的流程：建立新金鑰 → 更新後端環境 → 重啟 → 停用舊金鑰。

### B2. 每日配額（硬上限，已核對）

步驟（[官方說明](https://docs.cloud.google.com/apis/docs/capping-api-usage)）：

1. Cloud Console → **APIs & Services**，選專案。
2. 點 **Places API (New)** → **Quotas** 分頁；或到 **Google Maps Platform → Quotas**。
3. 勾選要限制的配額（依 API 方法分開計算：搜尋、取得店家、取得照片各一個）。
4. **Edit quotas** → 輸入新上限 → **Submit request**。

要注意：
- 超過上限的請求會直接失敗（`limit exceeded`）。
- **生效有延遲**，超量後要一段時間才開始擋。
- 官方明說配額**不是整個專案的金額上限**。

**怎麼決定數字：** 用「可接受的每日花費」反推。

```
每日搜尋上限  = 每日搜尋預算 ÷ 0.035
每日詳情上限  = 每日詳情預算 ÷ 0.020
每日照片上限  = 每日照片預算 ÷ 0.007
```

預設後端上限（搜尋與詳情共 500 次、照片 1000 次）的最壞情況是每日約 `500 × $0.035 + 1000 × $0.007 ≈ $24.5`（未扣免費額度）。雲端配額請設成**略高於後端計數**，當作後端失靈時的保險，不要比後端低，否則會先誤擋正常使用者。

### B3. 預算與警示（已核對）

步驟：Cloud Console → **Billing → Budgets & alerts → Create budget**。

- [ ] 金額設成你能接受的月支出。
- [ ] 門檻設 50%、90%、100%，並**加上「預測花費」門檻**，在花光前就通知。
- [ ] 收件人至少兩個人，避免漏看。

**要清楚：** 官方寫明只有警示的預算「不會自動限制或停止使用與計費」，只是寄通知。若要真的斷掉，可用 Pub/Sub 加雲端函式呼叫[停用專案計費](https://docs.cloud.google.com/billing/docs/how-to/disable-billing-with-notifications)。這是最後手段，因為**停用計費會讓整個專案的服務全部停擺**，且需要自己維護，我不建議一開始就用。

### B4. 用量監控

- [ ] 每天執行一次（在後端主機上）：

```bash
cd server
node --env-file=.env usage.mjs
```

- [ ] 看：搜尋、詳情、照片各自的成功與失敗數，以及 `daily_limit` 次數。`daily_limit` 常常出現，代表上限太低或有人濫用。
- [ ] Cloud Console 的 **Google Maps Platform → Metrics** 對照後端數字，差距大要查原因。
- [ ] 統計只保留 30 天且不含座標與店家 ID，這是刻意的。

### B5. 正式環境後端

正式環境（`NODE_ENV=production`）缺少下列任何一項都無法啟動，見 [server/README.md](../server/README.md)：

- [ ] `GOOGLE_PLACES_API_KEY`
- [ ] `SERVER_SECRET`：至少 32 字元的隨機值，跨重啟保留；更換會讓所有已發出的照片憑證失效（最長 30 分鐘）。
- [ ] `DB_PATH`：絕對路徑，且在持久磁碟上；更換或清空資料庫會重設用量計數。
- [ ] 所有上限為正數（正式環境不接受 0）：`CLIENT_REQUESTS_PER_MINUTE`、`CLIENT_REQUESTS_PER_DAY`、`GOOGLE_REQUESTS_PER_DAY`、`GOOGLE_PHOTO_REQUESTS_PER_DAY`。
- [ ] `TRUSTED_PROXY_IPS`：放在反向代理後面時，填代理的精確 IP，否則會把所有人算成同一個來源。
- [ ] `ALLOWED_ORIGINS`：只在有網頁版時才填。
- [ ] 只提供 HTTPS；App 在正式版只接受 `https`。
- [ ] 目前後端是單一實例，用量計數存在本機 SQLite；需要多實例時要改成共用儲存。

### B6. 以裝置為單位的限流

**為什麼現有的每 IP 限流不夠：**
- 行動網路很多人共用同一個 IP，一個人用完，其他人也被擋。
- 任何人只要拿到後端網址，就能直接打，不必經過 App。

**要先講清楚：** Firebase App Check 證明的是「這是正版 App 在呼叫」，**不是「這是哪一台裝置」**。所以它能擋掉直接打後端的腳本，但不能單獨拿來做每人限額。

**建議分兩步：**

1. **加 App Check（先做，效果最大）。**
   - App 每次請求帶 `X-Firebase-AppCheck` 標頭。
   - 後端驗證（[官方說明](https://firebase.google.com/docs/app-check/custom-resource-backend)）：用 RS256 與 `https://firebaseappcheck.googleapis.com/v1/jwks` 的公鑰驗簽章；檢查發行者為 `https://firebaseappcheck.googleapis.com/{專案編號}`、受眾包含 `projects/{專案編號}`、未過期。
   - 官方另有可選的重放保護（`consume`），目前標為測試版，且只有 Node.js 的 Admin SDK 支援；我們的後端刻意不裝套件，若要用要另評估。
   - iOS 與 Android 各自的認證提供者（App Attest、Play Integrity 等）**我沒有在這次核對**，請看 Firebase 的平台文件。
2. **加安裝識別碼（第二步）。** App 首次啟動產生隨機識別碼並存本機，每次請求帶上，後端以「識別碼加每日」計數。它可以被重置，所以一定要搭配第 1 步，攻擊者才無法無限產生新識別碼。

- [ ] 不管選哪個，先確認會不會被商店審核、Google 政策或隱私法規影響：識別碼是隨機值、不含個人資料。
- [ ] 上線後保留每 IP 限流當作最外層保險，數值可以放寬。

---

## 上線當天

- [ ] A：條款回覆已存檔，且程式行為與回覆一致。
- [ ] B1：金鑰已限制 API 與 IP，開發與正式分開。
- [ ] B2：三種 API 的雲端配額都已設定，數字略高於後端上限。
- [ ] B3：預算與警示已建立，含預測花費門檻。
- [ ] B4：知道誰每天看用量，以及超過什麼數字要處理。
- [ ] B5：正式環境變數齊全，後端可正常啟動。
- [ ] B6：至少完成 App Check，或明確決定延後並記錄原因。
- [ ] 把整批修改 commit，方便日後回退。

## 來源與核對狀態

| 內容 | 來源 | 狀態 |
| --- | --- | --- |
| place ID 可無限期保存；其餘不得快取 | [Places 政策](https://developers.google.com/maps/documentation/places/web-service/policies) | 已核對 |
| 歸因規定 | 同上 | 已核對 |
| 經緯度 30 天例外 | [服務條款](https://cloud.google.com/maps-platform/terms/maps-service-terms) | **未能核對** |
| 價格與免費額度 | [價目](https://developers.google.com/maps/billing-and-pricing/pricing) | 已核對 |
| 配額設定步驟與生效延遲 | [限制 API 用量](https://docs.cloud.google.com/apis/docs/capping-api-usage) | 已核對 |
| 預算只會警示、不會停用 | [預算說明](https://docs.cloud.google.com/billing/docs/how-to/budgets) | 已核對 |
| App Check 驗證方式 | [自訂後端驗證](https://firebase.google.com/docs/app-check/custom-resource-backend) | 已核對 |
| 各平台認證提供者細節 | Firebase 平台文件 | **未核對** |
