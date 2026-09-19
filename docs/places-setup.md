# Google Places 金鑰申請與最後接線流程

更新：2026-09-19。已依使用者後續指示，將現有金鑰綁定至本機後端並測試真實 Google API；尚未雲端部署。金鑰不記錄於本文件或 Git，實際計費以 Cloud Billing 為準。

## 申請順序

1. 登入 [Google Cloud Console](https://console.cloud.google.com/)，建立 EatSet 專案。
2. 建立或連結 Cloud Billing 帳單帳戶。Places 需要啟用計費；不要把免費用量當作永遠不會收費的保證。
3. 到「API 和服務 → 程式庫」啟用 **Places API (New)**。附近搜尋、店家詳情及照片現在都使用 New，不必為本程式啟用 Legacy。
4. 到「API 和服務 → 憑證 → 建立憑證 → API 金鑰」，命名如 `eatset-server`。
5. 編輯金鑰的 API 限制，只允許 **Places API (New)**。
6. 選定後端主機後，將應用程式限制設為後端固定出口 IP。這是伺服器 REST 金鑰，不使用 Android 套件／SHA-1、iOS Bundle ID 或 Web referrer 限制；若主機沒有固定出口，先規劃固定出口再接正式流量。
7. 在 Billing 設預算通知，在 API 配額頁設定可接受的配額。**預算通知不會自動停止計費**；再搭配本專案後端的每日請求上限。
8. 把金鑰放入後端主機的 secret／環境變數 `GOOGLE_PLACES_API_KEY`，不要貼到聊天或提交 Git。另產生至少 32 字元隨機 `SERVER_SECRET`，用於照片短效憑證與用量識別雜湊；這不是向 Google 申請的金鑰。

官方依據：[建立專案與 API 金鑰](https://developers.google.com/maps/documentation/places/web-service/get-api-key)、[API 安全與 IP 限制](https://developers.google.com/maps/api-security-best-practices)、[成本與配額管理](https://developers.google.com/maps/billing-and-pricing/manage-costs)。

## 設定位置

```text
Flutter App → EatSet HTTPS 後端 → Google Places API (New)
               保存私密金鑰
```

App 只帶公開後端位址：

```bash
flutter run --dart-define=EATSET_API_BASE_URL=https://api.example.com
```

`api.example.com` 是範例，須換成部署後的實際網址。原本 `--dart-define=GOOGLE_PLACES_API_KEY` 與 `lib/config/api_keys.local.dart` 已不再使用；若曾發布含金鑰的舊 App，切換後應撤銷／輪替舊金鑰。

本機 iOS Simulator 可使用 `http://127.0.0.1:8787`，Android Emulator 可使用 `http://10.0.2.2:8787`。HTTP 僅限 Debug 本機測試，正式版要求 HTTPS。啟動、限制參數、用量查詢及部署條件見 [後端說明](../server/README.md)。

## 接線後驗收

| 情況 | 預期 |
| --- | --- |
| 未設定後端位址 | Demo，可完整操作，不查 Google |
| 尚無裝置定位 | Demo 並提示開啟定位；Debug 備援座標不查真店 |
| 後端、金鑰、定位均正常 | 附近真實店家、Google 來源說明與直線距離 |
| 後端失敗／配額用盡 | 明確錯誤與重試；不把示範店家冒充真資料 |
| 舊收藏／歷史 | 保存店家 ID、個人回饋與日期；重新取店名、價格、營業資訊 |
| 更新失敗 | 紀錄仍保留；顯示待更新，不展示過期價格／營業狀態 |
| 照片 | 對應正確店家、作者及来源連結；不能保證全是食物照 |

最後用真實 iPhone／Android 驗證定位、平價店家、飯店排除、歸因及 Maps 對應，並核對 Cloud Billing 實際 SKU 用量。本機測試不代表已完成這些驗收。
