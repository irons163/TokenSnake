<p align="center">
  <img src="TokenSnake/Assets.xcassets/AppIcon.appiconset/icon_128@2x.png" width="112" height="112" alt="TokenSnake：小蛇環抱 T token">
</p>

<h1 align="center">TokenSnake</h1>

<p align="center">在 macOS 選單列追蹤 AI 用量，讓每一筆 tokens 餵養小蛇。</p>

<p align="center">
  <a href="https://github.com/irons163/TokenSnake/releases/latest">下載最新版</a> ·
  <a href="SECURITY.md">隱私與安全</a>
</p>

macOS 選單列上的 AI 用量儀表板，以 SwiftUI 製作。自動讀取本機 Codex、Claude Code 與 OpenCode 用量，並可選擇連線 Cursor 讀取雲端用量，讓真實使用的 tokens 餵養小蛇、累積成長，也可手動管理訂閱月費。

## 畫面

| 用量總覽 | 小蛇成長 |
| :---: | :---: |
| <img src="docs/images/usage.png" width="360" alt="用量頁面：今日與本月 tokens、14 天趨勢及依模型分組的費用估算"> | <img src="docs/images/snake.png" width="360" alt="小蛇頁面：累積 tokens、等級、升級進度與今日進食"> |

## 安裝

需要 **macOS 14 或更新版本**，支援 Apple Silicon 與 Intel。直接安裝 Release 版本即可使用。

1. 前往 [下載最新版](https://github.com/irons163/TokenSnake/releases/latest)，依 Mac 晶片選擇 DMG：

   | Mac 晶片 | 下載檔案 |
   | --- | --- |
   | Apple Silicon（M 系列） | `TokenSnake-<版本>-apple-silicon.dmg` |
   | Intel | `TokenSnake-<版本>-intel.dmg` |

2. 開啟 DMG，將 `TokenSnake.app` 拖進 **Applications**。
3. 開啟 App，點選選單列的小蛇即可查看用量。App 不會出現在 Dock。
4. 若紀錄位於外接磁碟或受保護目錄，依 macOS 提示允許讀取，或到齒輪設定選擇紀錄目錄。

正式 Release 已使用 Developer ID 簽章並通過 Apple 公證。安裝後可從齒輪設定的「App 更新」檢查新版；預設每小時自動檢查，不自動下載。

## 功能

- **選單列**：與 App icon 一致的 S 形小蛇及 T token，使用 18pt 單色圖示適應深淺色背景。可選擇顯示小蛇等級、今日 tokens、今日／本月花費或最近續費。
- **用量**：啟動後掃描歷史紀錄，之後每 30 秒增量更新。顯示今日、本月、最近 14 天與來源篩選；清單依模型分組，彙總全部紀錄的筆數、tokens 與估算費用，點擊可展開單筆明細。可精確輸入 tokens，或用快速估算按鈕手動記錄。
- **小蛇**：每筆用量自動進食，累積 tokens 決定等級與身長。顯示升級進度、今日進食、最近食物與 13 週用量熱圖；新用量出現時播放吃食物的動畫。休息會保留成長，預算及模型費率不影響餵養。
- **設定**：選擇來源、變更紀錄目錄、立即同步、重新匯入、預算、選單列顯示、登入時啟動，以及 JSON 備份匯出／還原。「訂閱管理」預設收合，可選填月費與續費日，保留範本、自訂帳號、編輯與手動額度管理。進入新月度週期後會重設已用額度；範本請依實際帳單調整。

主介面分為「用量／小蛇」，訂閱資料在齒輪設定的「訂閱管理」。

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

同步只保留用量、模型、時間與去重識別，對話內容、工具輸出與認證檔不會存入 TokenSnake。用量同步只有 Cursor 來源需要網路；Cursor 預設關閉，只有在你確認後才會向 `cursor.com` 讀取你自己的用量。App 另可向 GitHub 檢查與下載新版，不會傳送用量紀錄，亦未啟用 Sparkle 系統資訊回報。

- Codex 以回應識別碼追蹤逐次用量，並對應舊版累計事件，避免壓縮對話、分叉歷史與封存副本重複計數。
- Claude Code 以訊息識別碼合併串流與重複內容區塊；輸入包括一般輸入、快取讀取及快取寫入，推理 tokens 不會再次加進輸出。
- OpenCode 以資料庫中的訊息識別碼合併串流更新；輸入包括一般輸入、快取讀取及快取寫入，推理 tokens 計入輸出。供應商依 OpenCode 的 provider 與模型名稱對應；費用優先保留訊息中的 `cost` 美元估算，模型不在 TokenSnake 價目表也可顯示。
- Cursor 已不再把 token 寫進本機資料庫，因此改用 Cursor 儀表板自己的用量介面：讀取本機 `state.vscdb` 的登入憑證，只送出日期範圍，取回近 90 天的用量事件，並以事件識別碼去重。開啟時會先顯示提示；自動同步每 5 分鐘最多查詢一次，「立即同步」可手動重試。
- 讀取游標與用量一起保存，重啟後接續讀取。尚未寫完的一行會等下一次掃描；檔案截斷或替換後重新解析並去重。
- 刪除匯入紀錄會將它隱藏，後續同步不會恢復；「重新匯入」會恢復隱藏項目。停用來源會保留已匯入的歷史。
- 「清除所有紀錄」會暫停自動同步。還原備份會先保留原資料，並暫停同步，方便核對後再開啟。

本機同步不包含 ChatGPT 網頁、Claude 網頁的用量或任何帳戶的剩餘訂閱額度查詢；Cursor 需個別開啟，其餘帳號仍可手動管理。

## 費用

Codex、Claude Code 依內建 API 費率估算；OpenCode 優先採用來源提供的估算；Cursor 使用來源回傳的帳單費用。API 估算不等同訂閱費或實際扣款，價目表隨 App 版本更新。

「費率未收錄」代表目前缺少可用的計價資料，不代表免費；tokens 仍會完整統計。選單列金額後的 `+` 表示總額尚不完整。

## 資料與備份

資料位於 `~/Library/Application Support/TokenSnake/store.json`，舊版資料會自動讀取。退出 App 時會立即保存。寫入失敗會在介面提示；無法讀取的資料會先保留 `.corrupt-*.json` 副本。備份還原前，原檔會保留為 `.backup-*.json`。

設定中可匯出 JSON 備份，再用「還原資料備份」恢復。清除或載入示範資料前，建議先匯出。

App 對啟動資料與還原備份使用相同驗證，拒絕異常 tokens、快取、額度與同步游標。單個快照讀取上限為 256 MiB；資料及備份使用僅擁有者可讀寫的權限。備份內含目錄路徑及用量資訊，請保留在私人位置。公開範圍與回報方式見 [SECURITY.md](SECURITY.md)。

## 從原始碼建置

開發環境需求：

- macOS 14 或更新版本
- Xcode 26 或更新版本（Swift 6 與明確的並行隔離）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

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
