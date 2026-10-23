import AppKit
import Observation
import Sparkle

enum UpdateConfiguration {
    static func feedURL(architecture: String) -> URL {
        let slice = architecture == "x86_64" ? "x86_64" : "arm64"
        return URL(string: "https://github.com/irons163/TokenSnake/releases/latest/download/appcast-\(slice).xml")!
    }

    static var architecture: String {
        #if arch(x86_64)
        "x86_64"
        #else
        "arm64"
        #endif
    }

    static var isTesting: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["TOKEN_SNAKE_TEST_MODE"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.arguments.contains("--data-directory")
    }
}

@Observable
@MainActor
final class AppUpdater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = AppUpdater(enabled: !UpdateConfiguration.isTesting)

    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = false
    private(set) var automaticallyDownloadsUpdates = false
    private(set) var availableVersion: String?
    private(set) var errorMessage: String?
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private let enabled: Bool
    @ObservationIgnored var beforeInstalling: (() -> Void)?

    init(enabled: Bool) {
        self.enabled = enabled
        super.init()
    }

    func start() {
        guard enabled, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false,
                                                      updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates }
            }
        ]
        do { try updater.start() }
        catch { errorMessage = "無法啟動更新：\(error.localizedDescription)" }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        errorMessage = nil
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        controller?.updater.automaticallyDownloadsUpdates = enabled
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        UpdateConfiguration.feedURL(architecture: UpdateConfiguration.architecture).absoluteString
    }

    // Keep background reminders inside the menu bar app until the user opens them.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        beforeInstalling?()
    }
}
