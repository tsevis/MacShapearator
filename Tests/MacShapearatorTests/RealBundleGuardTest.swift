import XCTest
@testable import MacShapearator

/// Regression guard against the specific bundle that was shipping.
final class RealBundleGuardTests: XCTestCase {
    func testTheStaleVendoredBundleWouldBeRejected() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/BundledBackend")
        try XCTSkipUnless(AppRuntime.isEngineRoot(root), "no vendored bundle present")
        let found = AppRuntime.engineVersion(at: root)
        if let found, found >= AppRuntime.minimumEngineVersion {
            XCTAssertNil(AppRuntime.engineCompatibilityProblem(at: root))
        } else {
            XCTAssertNotNil(AppRuntime.engineCompatibilityProblem(at: root),
                            "a stale bundle (\(found?.description ?? "unknown")) must be rejected")
        }
    }
}
