import Foundation
import ServiceManagement

protocol LaunchAtLoginServicing {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

struct SystemLaunchAtLogin: LaunchAtLoginServicing {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

final class MockLaunchAtLogin: LaunchAtLoginServicing {
    var isEnabled: Bool
    var shouldThrow: Bool

    init(isEnabled: Bool = false, shouldThrow: Bool = false) {
        self.isEnabled = isEnabled
        self.shouldThrow = shouldThrow
    }

    func setEnabled(_ enabled: Bool) throws {
        if shouldThrow {
            throw NSError(domain: "TokenSnake.LaunchAtLogin", code: 1)
        }
        isEnabled = enabled
    }
}
