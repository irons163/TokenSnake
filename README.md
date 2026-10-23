# TokenSnake

macOS 選單列上的 AI 用量儀表板，以 SwiftUI 製作。自動讀取本機 Codex、Claude Code 與 OpenCode 用量，並可選擇連線 Cursor 讀取雲端用量，讓真實使用的 tokens 餵養小蛇、累積成長，也可手動管理訂閱月費。

## 功能

- **用量**：啟動後掃描歷史紀錄，之後每 30 秒增量更新。顯示今日、本月、最近 14 天與來源篩選；清單依模型分組，彙總全部紀錄的筆數、tokens 與估算費用，點擊可展開單筆明細。可精確輸入 tokens，或用快速估算按鈕手動記錄。
- **小蛇**：每筆用量自動進食，累積 tokens 決定等級與身長。顯示升級進度、今日進食、最近食物與 13 週用量熱圖；新用量出現時播放吃食物的動畫。休息會保留成長，預算及模型費率不影響餵養。
- **設定**：選擇來源、變更紀錄目錄、立即同步、重新匯入、預算、選單列顯示、登入時啟動，以及 JSON 備份匯出／還原。「訂閱管理」預設收合，可選填月費與續費日，保留範本、自訂帳號、編輯與手動額度管理。進入新月度週期後會重設已用額度；範本請依實際帳單調整。

開啟 `TokenSnake.app`，點選選單列的小蛇即可使用。主介面只有「用量／小蛇」，訂閱資料在齒輪設定的「訂閱管理」。App 不會出現在 Dock。

## 自動餵養與成長

所有已記錄的有效用量都會計入累積食物，包含歷史匯入與手動用量；每筆食物是輸入加輸出 tokens，輸入中的快取不會額外重複計入。重複同步、重啟及重新匯入會沿用去重紀錄，不會再餵一次。未來日期的紀錄要到當天才計入。

Lv.1 從蛇蛋開始，第一筆用量即可孵化。升級門檻為 `1,000,000 × (等級 − 1)²`：Lv.2 為 1M、Lv.3 為 4M、Lv.4 為 9M tokens；隨等級增加身長，並經歷幼蛇、長蛇、靈蛇與星蛇階段。畫面直接顯示距下級所需的 tokens。

成長直接由用量紀錄計算，不依賴打卡、習慣完成數、價格或預算。沒有使用的日子只會休息；刪除／隱藏用量或還原備份時，成長會跟著有效紀錄修正。舊版習慣資料會保留在備份中，但不再控制餵養。

## 自動同步

| 來源 | 預設資料目錄 | 讀取內容 |
| --- | --- | --- |
| Codex | `CODEX_HOME`，未設定時為 `~/.codex` | `sessions/**/*.jsonl` 與 `archived_sessions/**/*.jsonl` |
| Claude Code | `CLAUDE_CONFIG_DIR`，未設定時為 `~/.claude` | `projects/**/*.jsonl`，包含子代理紀錄 |
| OpenCode | `XDG_DATA_HOME/opencode`，未設定時為 `~/.local/share/opencode` | `opencode.db` 的 assistant 訊息（唯讀） |
| Cursor | `~/Library/Application Support/Cursor` | **預設關閉。** 讀取本機 Cursor 登入憑證，連線 `cursor.com` 取得近 90 天的用量事件 |

從 Finder 開啟 App 時，不一定會繼承終端機的環境變數；可在設定直接選擇包含 `sessions`、`projects` 或 `opencode.db` 的資料目錄。標準紀錄目錄透過符號連結移到外接磁碟也可讀取。找不到目錄、權限不足或無效資料會顯示在各來源狀態中。

首次讀取外接磁碟或受保護目錄時，macOS 可能顯示存取提示；請在系統提示中允許 TokenSnake 讀取紀錄所在位置。等待系統授權時會維持「正在同步」狀態。重新建置的本機 ad-hoc 版本可能需要重新授權。

同步只保留用量、模型、時間與去重識別，對話內容、工具輸出與認證檔不會存入 TokenSnake。除 Cursor 外，App 沒有網路請求或雲端帳號；Cursor 來源預設關閉，只有在你確認後才會向 `cursor.com` 讀取你自己的用量。

- Codex 以回應識別碼追蹤逐次用量，並對應舊版累計事件，避免壓縮對話、分叉歷史與封存副本重複計數。
- Claude Code 以訊息識別碼合併串流與重複內容區塊；輸入包括一般輸入、快取讀取及快取寫入，推理 tokens 不會再次加進輸出。
- OpenCode 以資料庫中的訊息識別碼合併串流更新；輸入包括一般輸入、快取讀取及快取寫入，推理 tokens 計入輸出。供應商依 OpenCode 的 provider 與模型名稱對應，未收錄的模型仍會計入 tokens。
- Cursor 已不再把 token 寫進本機資料庫，因此改用 Cursor 儀表板自己的用量介面：讀取本機 `state.vscdb` 的登入憑證，只送出日期範圍，取回近 90 天的用量事件，並以事件識別碼去重。開啟時會先顯示提示；自動同步每 5 分鐘最多查詢一次，「立即同步」可手動重試。
- 讀取游標與用量一起保存，重啟後接續讀取。尚未寫完的一行會等下一次掃描；檔案截斷或替換後重新解析並去重。
- 刪除匯入紀錄會將它隱藏，後續同步不會恢復；「重新匯入」會恢復隱藏項目。停用來源會保留已匯入的歷史。
- 「清除所有紀錄」會暫停自動同步。還原備份會先保留原資料，並暫停同步，方便核對後再開啟。

本機同步不包含 ChatGPT 網頁、Claude 網頁的用量或任何帳戶的剩餘訂閱額度查詢；Cursor 需個別開啟，其餘帳號仍可手動管理。

1.3.0 於 2026/10/21 新增 OpenCode 與 Cursor 兩個來源。OpenCode 讀取 `opencode.db`；Cursor 因官方已不再寫入本機 token，改為預設關閉、經使用者確認後連線 `cursor.com` 讀取雲端用量事件。既有來源與紀錄不受影響。

## 費用

費用為內建靜態 **標準 API 費率的參考估算**，不是訂閱帳單或實際扣款。已處理快取讀取、Claude 的 5 分鐘／1 小時快取寫入，以及已收錄 GPT-5.5／5.6／6 模型的大型提示門檻；不包含 Fast／Ultrafast、區域加價、工具費用或帳戶折扣。

「費率未收錄」表示 App 的內建價目表尚未對應該模型，不代表供應商沒有公開價格，也不代表免費。這些紀錄仍會計入 tokens，總覽列出待補費率筆數與已知估算；選單列金額後的 `+` 表示總額尚不完整。模型名稱不會被猜成其他模型。參考價目表位於 `TokenSnake/Models/Pricing.swift`。更新價目表後會直接重新計算既有紀錄，不需要重新匯入。

Cursor 事件會帶回 Cursor 帳單的實際費用（`totalCents`），App 直接顯示該金額，不用內建費率推估；若 Cursor 未回傳費用才顯示「費率未收錄」。

Codex／Claude 新增費率核對於 2026/10/14：[GPT-6.1 Sol](https://developers.openai.com/api/docs/models/gpt-6.1-sol)、[GPT-6 Astra](https://developers.openai.com/api/docs/models/gpt-6-astra)、[Claude 快取費率](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)。其餘內建範本需按實際使用情況更新。

1.1.2 於 2026/10/15 補齊目前紀錄中缺少的四個模型（USD／百萬 tokens）：

| 模型／官方來源 | 輸入 | 快取讀取 | 輸出 |
| --- | ---: | ---: | ---: |
| [GPT-5.5](https://developers.openai.com/api/docs/models/gpt-5.5) | $5.00 | $0.50 | $30.00 |
| [GPT-5.6 Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol) | $4.00 | $0.40 | $20.00 |
| [GPT-5.6 Terra](https://developers.openai.com/api/docs/models/gpt-5.6-terra) | $2.00 | $0.20 | $12.00 |
| [GPT-5.6 Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna) | $0.20 | $0.02 | $1.20 |

以上模型估算時以每次回應的輸入套用 272k 門檻，超過時使用 2 倍輸入／快取讀取及 1.5 倍輸出費率。GPT-5.6 快取寫入為輸入費率的 1.25 倍。Sol 採官方目前促銷價，官方保證至少適用至 2026/11/21；內建費率需要隨官方調整而更新。歷史紀錄同樣按此價目表估算，並非還原歷史帳單。

1.2.2 於 2026/10/21 補上 [Claude Opus 5.5](https://platform.claude.com/docs/en/models/opus-5-5/overview)（`claude-opus-5-5`）：每百萬 tokens 的標準輸入 $4、輸出 $20、快取讀取 $0.20、5 分鐘快取寫入 $5、1 小時快取寫入 $8。套用原有紀錄即可估算，不需重新匯入。App 的價目表隨版本更新，尚未自動從官方網站更新。

## 資料與備份

資料位於 `~/Library/Application Support/TokenSnake/store.json`，舊版資料會自動讀取。退出 App 時會立即保存。寫入失敗會在介面提示；無法讀取的資料會先保留 `.corrupt-*.json` 副本。備份還原前，原檔會保留為 `.backup-*.json`。

設定中可匯出 JSON 備份，再用「還原資料備份」恢復。清除或載入示範資料前，建議先匯出。

App 對啟動資料與還原備份使用相同驗證，拒絕異常 tokens、快取、額度與同步游標。單個快照讀取上限為 256 MiB；資料及備份使用僅擁有者可讀寫的權限。備份內含目錄路徑及用量資訊，請保留在私人位置。公開範圍與回報方式見 [SECURITY.md](SECURITY.md)。

## 需求

- macOS 14 或更新版本
- Xcode 26 或更新版本（Swift 6 與明確的並行隔離）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## 建置

```bash
brew install xcodegen
xcodegen generate
xcodebuild test -project TokenSnake.xcodeproj -scheme TokenSnake \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

產出 Apple Silicon／Intel 通用本機版 App 與 ZIP：

```bash
./Scripts/build-release.sh
open build/TokenSnake.app
```

產物使用 ad-hoc 簽章，供本機使用；對外散布時需自行使用 Developer ID 簽章與 notarization。

## GitHub Release

Actions 的 **Release DMG** 可手動試建 Apple Silicon／Intel 的 DMG、ZIP、dSYM 與 SHA-256。發布 GitHub Release 後會自動執行測試、版本核對、Developer ID 簽章與 Apple 公證，再附加兩個架構的產物。正式發布前需設定 Apple repository secrets；手動 `ad-hoc` 試建不需要憑證。

操作與 secrets 清單見 [發布指南](docs/RELEASING.md)。

## 隔離驗證

可讓 App 在指定資料目錄執行，並直接顯示儀表板，方便驗證而不改動既有資料：

```bash
open -n build/TokenSnake.app --args \
  --data-directory /tmp/tokensnake-verification --show-dashboard
python3 Scripts/VerifyUsageSnapshot.py /tmp/tokensnake-verification/store.json
```

`--show-dashboard` 會額外開啟獨立驗證視窗，與選單列面板同時存在。驗證請使用隔離資料目錄，完成後結束驗證 App；正式使用以 `open build/TokenSnake.app` 啟動，不附加此參數。

核對腳本依快照已提交的讀取游標，獨立重新加總 Codex、Claude Code 與 OpenCode 的回應數與輸入、輸出、快取讀取及寫入 tokens；只輸出總數。請使用尚未隱藏匯入紀錄的新快照。
