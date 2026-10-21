# TokenSnake 交付與驗證

此文件只記錄可公開的功能與驗證方式，不包含個人用量、帳單、來源快照或本機絕對路徑。

## 交付範圍

- macOS 14+ 選單列 App，支援 Apple Silicon 與 Intel。
- 本機 Codex／Claude Code／OpenCode 用量匯入、增量同步、去重、模型分組及標準 API 費率估算。
- tokens 自動餵養小蛇，累積等級與身長；手動訂閱管理在設定中。
- 選用的 Cursor 雲端用量匯入（預設關閉，需使用者確認後才會連線）、去重與實際費用顯示。
- 備份匯出／還原、資料驗證、讀取失敗提示及退出保存。

## 驗證

建置與測試命令列於 README。測試使用獨立暫存資料，涵蓋解析、快取計費、增量讀取、重複事件、檔案截斷、資料還原、成長門檻及介面渲染。

實際用量核對工具為 `Scripts/VerifyUsageSnapshot.py`，只輸出加總。請對隔離快照執行並將結果保留在本機；不要提交真實的 store、JSONL、OpenCode 資料庫、驗證輸出或個人帳單。

## 本機封裝

`Scripts/build-release.sh` 產出通用 App 與 ZIP，並驗證本機 ad-hoc 簽章。公開簽章及 notarization 需要發行者另外設定 Developer ID。費用為參考估算，並非實付帳單；價目表來源與核對日期列於 README。
