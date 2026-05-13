import XCTest
@testable import FreakLogCore

final class FreakLogCoreSmokeTests: XCTestCase {
    func test_packageHasVersion() {
        XCTAssertFalse(FreakLogCore.version.isEmpty)
    }
}
