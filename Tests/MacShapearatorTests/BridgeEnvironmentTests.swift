import XCTest
@testable import MacShapearator

/// The engine runs from inside the app bundle. Python caches bytecode next to
/// the source it imports, so the first extraction writes __pycache__ into
/// Contents/Resources/BundledBackend/services -- adding files to a sealed
/// bundle. `codesign --verify` then reports "a sealed resource is missing or
/// invalid", which is a notarized app quietly invalidating itself in place.
final class BridgeEnvironmentTests: XCTestCase {
    func testTheEngineIsNotAllowedToWriteBytecodeIntoTheBundle() {
        let environment = BridgeRunner.environment(
            backend: URL(fileURLWithPath: "/Applications/MacShapearator.app/Contents/Resources/BundledBackend"),
            python: URL(fileURLWithPath: "/Applications/MacShapearator.app/Contents/Resources/BundledPython/python/bin/python3"))

        XCTAssertEqual(environment["PYTHONDONTWRITEBYTECODE"], "1")
    }
}
