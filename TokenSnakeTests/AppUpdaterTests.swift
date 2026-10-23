import Foundation
import Sparkle
import Testing
@testable import TokenSnake

@MainActor
struct AppUpdaterTests {
    @Test func productionBundleHasCompleteSecureUpdaterConfiguration() throws {
        let bundle = Bundle.main
        let feed = try #require(bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String)
        #expect(feed == UpdateConfiguration.feedURL(architecture: UpdateConfiguration.architecture).absoluteString)
        let key = try #require(bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
        #expect(Data(base64Encoded: key)?.count == 32)
        #expect(bundle.object(forInfoDictionaryKey: "SURequireSignedFeed") as? Bool == true)
        #expect(bundle.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool == true)
        #expect(bundle.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool == true)
        #expect(bundle.object(forInfoDictionaryKey: "SUAutomaticallyUpdate") as? Bool == false)
        #expect(bundle.object(forInfoDictionaryKey: "SUEnableSystemProfiling") as? Bool == false)
        #expect(bundle.object(forInfoDictionaryKey: "SUScheduledCheckInterval") as? Int == 3600)
        #expect(bundle.object(forInfoDictionaryKey: "SUAllowsInsecureUpdates") == nil)
        let framework = bundle.bundleURL.appending(path: "Contents/Frameworks/Sparkle.framework")
        #expect(FileManager.default.fileExists(atPath: framework.path))
    }

    @Test func feedRoutesEachArchitectureToItsOwnSignedArchive() {
        #expect(UpdateConfiguration.feedURL(architecture: "arm64").lastPathComponent == "appcast-arm64.xml")
        #expect(UpdateConfiguration.feedURL(architecture: "x86_64").lastPathComponent == "appcast-x86_64.xml")
        #expect(UpdateConfiguration.feedURL(architecture: "arm64").scheme == "https")
        #expect(UpdateConfiguration.feedURL(architecture: "x86_64").host == "github.com")
    }

    @Test func testsDoNotStartNetworkChecksOrInstaller() {
        #expect(UpdateConfiguration.isTesting)
        let updater = AppUpdater(enabled: false)
        updater.start()
        updater.start()
        updater.checkForUpdates()
        updater.setAutomaticChecks(true)
        updater.setAutomaticDownloads(true)
        #expect(!updater.canCheckForUpdates)
        #expect(!updater.automaticallyChecksForUpdates)
        #expect(!updater.automaticallyDownloadsUpdates)
        #expect(updater.availableVersion == nil)
        #expect(updater.errorMessage == nil)
    }

    @Test func sparkleUsesBuildNumbersToPreventDowngrades() {
        let comparator = SUStandardVersionComparator.default
        #expect(comparator.compareVersion("12", toVersion: "11") == .orderedDescending)
        #expect(comparator.compareVersion("12", toVersion: "12") == .orderedSame)
        #expect(comparator.compareVersion("12", toVersion: "13") == .orderedAscending)
    }
}
