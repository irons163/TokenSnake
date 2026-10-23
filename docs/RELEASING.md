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

版本不符、測試失敗、架構或 dSYM UUID 不符、簽章失敗、公證未獲 Accepted，都會阻止 assets 上傳。發布流程不會自動 bump 版本或建立下一個 Release。

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

設定完成後，可用 `signing_mode=developer-id` 手動試建以驗證簽章及公證，仍只上傳 Actions artifacts。簽章憑證與 API key 僅在建置步驟使用；臨時 keychain 和私鑰檔由 script 的退出清理移除。請勿提交 P12、P8、私鑰或真實密碼。

## 本機驗證

```bash
python3 -m unittest discover -s Scripts/tests -v
bash -n Scripts/package-ci-release.sh Scripts/select-release-xcode.sh
TOKENSNAKE_ARCH=arm64 TOKENSNAKE_SIGNING_MODE=ad-hoc bash Scripts/package-ci-release.sh
```

本機試建使用目前的 Xcode 選擇；Actions 會額外執行 `Scripts/select-release-xcode.sh`，將支援的穩定 Xcode 路徑寫入 `GITHUB_ENV`。`dist/` 與 `build/ci-release/` 為產物目錄，均不提交。
