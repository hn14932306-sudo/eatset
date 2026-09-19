# EatSet Places 後端

Node.js 22.16+，使用內建 HTTP、fetch 與 SQLite，無額外 npm 套件。搜尋、店家詳情、照片皆使用 Places API (New)；Google 金鑰不進入 Flutter。這是已實作並可本機測試的單一實例服務，尚未部署。

## 本機

```bash
cd server
cp .env.example .env
node --env-file=.env index.mjs
```

目前可先保留空金鑰：`GET /healthz` 正常，Google 查詢回 `503 SERVICE_NOT_CONFIGURED`。金鑰最後設定，流程見 [申請文件](../docs/places-setup.md)。不需 `npm install`。

Flutter（iOS Simulator）：

```bash
flutter run --dart-define=EATSET_API_BASE_URL=http://127.0.0.1:8787
```

Android Emulator 改用 `http://10.0.2.2:8787`。真機用 HTTPS 測試站，不對區網開放 HTTP。未指定網址的 App 維持 Demo。

```bash
npm test
node --env-file=.env usage.mjs
```

測試用假上游回應與本機 HTTP，不使用真實金鑰。SQLite 在 Node 22 可能顯示實驗功能提醒。

## 路由與成本控制

| 路由 | 用途 |
| --- | --- |
| POST /v1/nearby | lat、lng、radiusMeters；半徑 100–2000 公尺，最多 20 家餐廳 |
| GET /v1/places/:id | 最新店家資料、價格等級、營業狀態 |
| GET /v1/places/:id/photos | 最多 3 張照片中繼資料與 30 分鐘簽章憑證 |
| POST /v1/photo | 只接受上述憑證；`size` 只能是 `card`（1000×750，預設）或 `thumb`（400×300），最多 8 MB。Google 照片依請求次數計費，尺寸不影響費用，只影響流量與清晰度 |
| GET /healthz | 程序健康檢查，不代表 Google 金鑰可用 |

欄位遮罩、Google 網域與圖片尺寸由伺服器固定；用戶不能自選付費欄位或任意代理網址。Google 錯誤內容與金鑰不回傳到 App。Google API 請求帶金鑰標頭，圖片 CDN 不帶金鑰。資料回應均 `no-store`，沒有持久保存 Google 內容。JSON 超過 1 KB 且用戶端接受 gzip 時自動壓縮。

| 環境變數 | 預設／要求 |
| --- | --- |
| GOOGLE_PLACES_API_KEY | 只存伺服器；production 必填 |
| SERVER_SECRET | production 必須至少 32 字元，使用隨機值並跨重啟保留 |
| DB_PATH | 開發 `./data/usage.sqlite`；production 要絕對路徑及持久卷 |
| CLIENT_REQUESTS_PER_MINUTE | 每來源 IP 30 次 |
| CLIENT_REQUESTS_PER_DAY | 每來源 IP 150 次 |
| GOOGLE_REQUESTS_PER_DAY | 搜尋與店家詳情共用 500 次 Google 嘗試，失敗也計入 |
| GOOGLE_PHOTO_REQUESTS_PER_DAY | 照片（清單＋圖片）獨立 1000 次；用完不影響搜尋 |
| MAX_CONCURRENT_REQUESTS | 同時 4 個業務請求 |
| ALLOWED_ORIGINS | Web 精確來源，逗號分隔；預設不接受跨站 Origin |
| TRUSTED_PROXY_IPS | 精確代理 IP，逗號分隔；預設忽略 X-Forwarded-For |

每日上限按 **UTC** 換日。分鐘／日 IP 識別使用每日 HMAC，不保存原始 IP。用量計數與限額存 SQLite，重啟仍保留；清除／更換 DB 會重設。統計只存日期、API 類型與結果，保留 30 天；不存座標、店家 ID、URL 或金鑰。`usage.mjs` 只在主機本地讀取統計，沒有公開管理端點。

開發測試可將 `GOOGLE_REQUESTS_PER_DAY=0`、`CLIENT_REQUESTS_PER_DAY=0` 與 `CLIENT_REQUESTS_PER_MINUTE=0` 分別關閉每日及分鐘上限，重新啟動後生效；同時請求數限制仍保留。關閉期間仍累計用量，恢復上限時會計入。`NODE_ENV=production` 不接受上述任何上限為 0。2026-09-19 依使用者測試要求，本機三項上限均已關閉。照片首頁包含主推薦與兩家備選，連續瀏覽容易超過原先每分鐘 30 次設定；Google Cloud 配額未變更，測試仍可能產生 API 費用。

這是**請求次數**上限，不是金額上限。不同 API／欄位 SKU 不同，Nearby 的價格、評分和營業時間欄位會影響計費。實際成本應核對 [Nearby 欄位與 SKU](https://developers.google.com/maps/documentation/places/web-service/nearby-search) 與 Cloud Billing；Google 預算告警不會自動停用服務。

## 部署邊界

- 使用 HTTPS 反向代理／平台 TLS，`NODE_ENV=production`。Dockerfile 可建置映像，但本輪尚未執行雲端部署。
- 設定金鑰、隨機 secret，掛載 `/data` 持久卷供 SQLite。Docker 容器以非 root 執行；自訂主機目錄須給該使用者寫入權限。
- 後端應只供可信反向代理連入。`TRUSTED_PROXY_IPS` 填實際代理的精確 IP，代理必須正確覆寫／追加來源鏈；不能把任意來源設為可信。
- **僅支援單一服務實例**。多副本／無狀態或 serverless 擴容前，須改用共用、原子限流儲存；不要每個副本各建自己的 SQLite。
- 目前端點供匿名 App 使用，**沒有會員驗證或裝置驗證**。Origin 白名單不是驗證；IP 限制也無法防止多 IP 耗盡全站額度，同一 NAT 使用者會共用額度。公开發布前按流量需求接裝置驗證／WAF 或登入配額；全站上限是目前的成本保護線。
- 如平台保留代理存取日誌，另外設定座標／照片 token 請求本文及敏感標頭不入日誌；本程式不記錄它們。

## 菜單與官網

搜尋／詳情一併請求 `websiteUri`，只傳回有效 HTTPS 官網；不從官網網址猜測菜單。`menu-links.mjs` 維護人工確認的官方菜單連結與備註，按精確 place ID 配對，確認超過 90 天即不再輸出 `menuUri`，直到重新查核。上游自行帶入的 `menuUri` 不採用。

App 自動載入一張主照片、每個相簿最多三張，其餘與菜單／官網按需開啟；並提供 Maps 入口。每次翻回舊照片、重新開啟相簿仍可能再次請求，三張是相簿大小，不是每日請求上限。

## App 資料策略

Nearby／Details 一併回傳照片清單與短效簽章（`photosExpiresAt`），不預先下載圖片。首頁只自動下載主推薦一張，備選／詳情照片按需載入；省去額外照片清單請求，過期或重試時仍用 `/v1/places/:id/photos` 更新。照片欄位不進 App 持久儲存。

真實收藏、排除與歷史只持久保存 place ID 和使用者自己的回饋／時間／偏好。首次讀取會清掉舊版真實店家快照；Demo 保留快照。店名、地址、評分、价格、營業狀態與照片只供目前執行期間使用，不進收藏資料庫。

執行期店家資料沒有時限，App 不會因為時間過了而丟棄或重查。營業狀態用 Google 回傳的 `nextCloseTime` 在本機計算「還有多久打烊」，過了就視為已打烊。只有換餐段、隔天或移動超過 500 公尺才重新搜尋；只有儲存還原、尚無資料的店家（收藏、紀錄）需要查詢，啟用分頁後先查前 5 筆，其餘可點擊更新，避免一次讀取整份歷史。未成功更新不刪除紀錄。是否允許在單次使用期間內持續顯示這些資料，取決於 Google 的快取條款，不是技術限制；正式發行前請完整檢查 [Places 資料與歸因政策](https://developers.google.com/maps/documentation/places/web-service/policies)。
