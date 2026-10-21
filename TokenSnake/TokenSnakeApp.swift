import SwiftUI

@main
struct TokenSnakeApp: App {
    @NSApplicationDelegateAdaptor(TokenSnakeDelegate.self) private var appDelegate
    @State private var store: AppStore

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let environment = ProcessInfo.processInfo.environment
        let isTesting = environment["TOKEN_SNAKE_TEST_MODE"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        let directory: URL?
        if isTesting {
            directory = URL.temporaryDirectory.appending(path: "tokensnake-test-host-\(ProcessInfo.processInfo.processIdentifier)")
        } else if let index = arguments.firstIndex(of: "--data-directory"), arguments.indices.contains(index + 1) {
            directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else { directory = nil }
        let store = AppStore(fileURL: directory?.appending(path: "store.json"))
        if isTesting { store.updateSyncSettings { $0.enabled = false } }
        _store = State(initialValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverRoot()
                .environment(store)
        } label: {
            MenuBarLabel()
                .environment(store)
                .task {
                    appDelegate.store = store
                    if ProcessInfo.processInfo.arguments.contains("--show-dashboard") { appDelegate.showDashboard() }
                    await store.runAutomaticSync()
                }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class TokenSnakeDelegate: NSObject, NSApplicationDelegate {
    weak var store: AppStore?
    private var dashboard: NSWindow?

    func showDashboard() {
        guard let store else { return }
        if dashboard == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Theme.popoverWidth, height: Theme.popoverHeight),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "TokenSnake"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PopoverRoot().environment(store))
            window.center()
            dashboard = window
        }
        dashboard?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.flushPersistence()
    }
}
