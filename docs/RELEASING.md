# GitHub Actions 發布流程

流程參考 AIAgentPool／[codex-pool-manager 的 Release DMG](https://github.com/irons163/codex-pool-manager/blob/main/.github/workflows/release-dmg.yml)，對應檔案為 `.github/workflows/release-dmg.yml`。

## 手動試建

在 Actions → **Release DMG** → **Run workflow** 選擇 `ad-hoc`，或執行：

```bash
gh workflow run release-dmg.yml --repo irons163/TokenSnake --ref main -f signing_mode=ad-hoc
```

試建不需要 Apple secrets。流程先選擇 Xcode 26+、產生專案、驗證版本並執行測試，再分別建置 Apple Silicon 和 Intel。完成後可在該次 run 下載 `release-apple-silicon` 和 `release-intel` artifacts。手動試建只產生 artifacts，不建立或修改 GitHub Release。

每個架構各包含 DMG、App ZIP、dSYM ZIP、SHA-256 清單及建置資訊 JSON。DMG 含 `TokenSnake.app` 與 Applications 捷徑。JSON 記錄來源 commit、版本、架構、簽章模式與公證狀態。`ad-hoc` 產物供測試用，不具有 Developer ID 或 Apple 公證。

## 正式發布

1. 更新 `project.yml` 的 `MARKETING_VERSION` 與 `CURRENT_PROJECT_VERSION`，執行 `xcodegen generate`，提交並推送至 GitHub。
2. 在 GitHub 發布對應的 Release，例如版本 `1.3.0` 使用 `v1.3.0` tag；`v1.3.0-rc.1` 必須勾選 prerelease，基礎版本仍為 `1.3.0`。
3. Release 的 `published` 事件自動執行流程。正式發布一律使用 Developer ID 簽章與 Apple 公證；憑證不足會停止，不會上傳未公證的測試版本。
4. 兩個架構均通過後，自動核對 tag 指向的 commit、建置資訊與 SHA-256，再把產物附加到該 Release。重跑會覆蓋同名 assets。

版本不符、測試失敗、架構或 dSYM UUID 不符、簽章失敗、公證未獲 Accepted，都會阻止 assets 上傳。公證核准後，票證下載及驗證遇到失敗時最多嘗試三次，仍失敗就停止。發布流程不會自動 bump 版本或建立下一個 Release。

## Apple 憑證設定

在 TokenSnake 的 **Settings → Secrets and variables → Actions** 設定以下 repository secrets；名稱沿用 AIAgentPool。其他倉庫的 repository secrets 不會自動提供給 TokenSnake，也無法透過 GitHub API 讀回其明文。

| Secret | 內容 |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | Developer ID Application 憑證及私鑰的 P12，以 Base64 編碼 |
| `APPLE_CERTIFICATE_PASSWORD` | P12 密碼 |
| `APPLE_TEAM_ID` | 憑證所屬 Apple Team ID |
| `APPLE_API_KEY_ID` | App Store Connect API Key ID，需具備公證權限 |
| `APPLE_API_ISSUER_ID` | 該 API key 的 Issuer ID |
| `APPLE_API_PRIVATE_KEY_BASE64` | API 私鑰 P8，以 Base64 編碼 |
| `KEYCHAIN_PASSWORD` | 選填；未設定時每次執行產生臨時密碼 |
| `SPARKLE_PRIVATE_KEY` | TokenSnake 專用 Ed25519 私鑰，由 Sparkle `generate_keys` 匯出；公鑰須與 App 的 `SUPublicEDKey` 相符 |

設定完成後，可用 `signing_mode=developer-id` 手動試建以驗證簽章及公證，仍只上傳 Actions artifacts。簽章憑證與 API key 僅在建置步驟使用；簽章期間會將臨時 keychain 加入原有使用者搜尋清單，結束時還原清單並移除臨時 keychain 和私鑰檔，不變更預設 keychain。請勿提交 P12、P8、私鑰或真實密碼。

## Sparkle 更新來源

從 1.4.0 起，Developer ID 建置也會產生 `appcast-arm64.xml` 與 `appcast-x86_64.xml`。流程使用已固定版本的 Sparkle 套件內工具，對公證後的 DMG 與 appcast 進行 Ed25519 簽章，核對版本、架構、檔案大小及 build number，加入 SHA-256 清單，再上傳 Release。`releases/latest/download/` 僅導向最新穩定 Release，預發版不會變成穩定更新來源。

正式建置會依序重簽 Sparkle 的 Mach-O、XPC、Updater.app 及框架，確保與主 App 使用相同 Developer ID。更新以遞增的 `CURRENT_PROJECT_VERSION` 比較版本，不能只更新行銷版本。App 必須保留 `SUPublicEDKey`、`SURequireSignedFeed` 與 `SUVerifyUpdateBeforeExtraction`；請勿啟用不安全更新或刪除簽章驗證。

本機私鑰保留在登入 keychain 的 Sparkle 帳戶 `app.tokensnake.TokenSnake`；可使用官方 `generate_keys --account app.tokensnake.TokenSnake -p` 讀取公鑰。匯出私鑰只應用於受保護的備份或 GitHub Secret 設定，不要貼在 issue、Release 或儲存庫。維持此金鑰，後續版本才能更新既有安裝。

## 本機驗證

```bash
python3 -m unittest discover -s Scripts/tests -v
bash -n Scripts/package-ci-release.sh Scripts/select-release-xcode.sh
TOKENSNAKE_ARCH=arm64 TOKENSNAKE_SIGNING_MODE=ad-hoc bash Scripts/package-ci-release.sh
```

本機試建使用目前的 Xcode 選擇；Actions 會額外執行 `Scripts/select-release-xcode.sh`，將支援的穩定 Xcode 路徑寫入 `GITHUB_ENV`。`dist/` 與 `build/ci-release/` 為產物目錄，均不提交。
