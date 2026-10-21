import Foundation
@testable import TokenSnake

@MainActor
enum StoreHarness {
    static func make(launch: MockLaunchAtLogin = MockLaunchAtLogin()) -> (AppStore, URL, MockLaunchAtLogin) {
        let url = FileManager.default.temporaryDirectory.appending(path: "tokensnake-\(UUID().uuidString).json")
        let store = AppStore(fileURL: url, launchAtLogin: launch)
        return (store, url, launch)
    }

    static func cheapEntry(createdAt: Date = .now) -> TokenEntry {
        TokenEntry(
            createdAt: createdAt,
            provider: .cursor,
            model: "Cursor 包含額度",
            inputTokens: 1_000,
            outputTokens: 200
        )
    }

    static func expensiveEntry(createdAt: Date = .now) -> TokenEntry {
        TokenEntry(
            createdAt: createdAt,
            provider: .anthropic,
            model: "Claude Opus 4.1",
            inputTokens: 200_000,
            outputTokens: 40_000
        )
    }
}
