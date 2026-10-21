import XCTest

final class TestHostExitObserver: NSObject, XCTestObservation {
    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        DispatchQueue.main.async {
            Darwin.exit(0)
        }
    }
}

private let testHostExitObserver = TestHostExitObserver()
