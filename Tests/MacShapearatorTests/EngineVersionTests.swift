import XCTest
@testable import MacShapearator

/// The packaged app once shipped an engine months out of date that still
/// imported cleanly, so extraction silently ran known-buggy code. These cover
/// the guard that makes that failure loud.
final class SemanticVersionTests: XCTestCase {
    func testParsesPlainVersions() {
        XCTAssertEqual(SemanticVersion("0.4.1")?.description, "0.4.1")
        XCTAssertEqual(SemanticVersion("1.0.0")?.description, "1.0.0")
    }

    func testToleratesLeadingV() {
        XCTAssertEqual(SemanticVersion("v0.4.1"), SemanticVersion(0, 4, 1))
    }

    func testToleratesSurroundingWhitespace() {
        XCTAssertEqual(SemanticVersion(" v0.4.1\n"), SemanticVersion(0, 4, 1))
    }

    func testFillsMissingComponents() {
        XCTAssertEqual(SemanticVersion("2"), SemanticVersion(2, 0, 0))
        XCTAssertEqual(SemanticVersion("2.3"), SemanticVersion(2, 3, 0))
    }

    func testToleratesPreReleaseSuffix() {
        XCTAssertEqual(SemanticVersion("0.4.1-rc2"), SemanticVersion(0, 4, 1))
    }

    func testRejectsNonVersions() {
        XCTAssertNil(SemanticVersion("unknown"))
        XCTAssertNil(SemanticVersion(""))
    }

    func testOrdersByComponent() {
        XCTAssertLessThan(SemanticVersion(0, 3, 2), SemanticVersion(0, 4, 1))
        XCTAssertLessThan(SemanticVersion(0, 4, 1), SemanticVersion(0, 4, 2))
        XCTAssertLessThan(SemanticVersion(0, 9, 9), SemanticVersion(1, 0, 0))
        XCTAssertFalse(SemanticVersion(0, 4, 1) < SemanticVersion(0, 4, 1))
    }
}

final class EngineCompatibilityTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("engine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("services"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeExtractor(version: String) throws {
        let source = """
        from __future__ import annotations
        __all__ = ["APP_VERSION", "IconExtractor"]
        APP_VERSION = "\(version)"
        """
        try source.write(
            to: root.appendingPathComponent("services/extractor.py"),
            atomically: true, encoding: .utf8)
    }

    private func writeStamp(_ text: String) throws {
        try text.write(
            to: root.appendingPathComponent("ENGINE_VERSION"),
            atomically: true, encoding: .utf8)
    }

    func testReadsVersionFromStampFile() throws {
        try writeExtractor(version: "0.3.2")
        try writeStamp("v0.4.1\n")
        // The stamp build_app.sh writes wins over the source constant.
        XCTAssertEqual(AppRuntime.engineVersion(at: root), SemanticVersion(0, 4, 1))
    }

    func testFallsBackToTheSourceConstant() throws {
        try writeExtractor(version: "0.4.1")
        XCTAssertEqual(AppRuntime.engineVersion(at: root), SemanticVersion(0, 4, 1))
    }

    func testDoesNotMistakeTheNameInDunderAllForTheValue() throws {
        // __all__ lists "APP_VERSION" as a string before the real assignment.
        try writeExtractor(version: "1.2.3")
        XCTAssertEqual(AppRuntime.engineVersion(at: root), SemanticVersion(1, 2, 3))
    }

    func testCurrentEngineIsAccepted() throws {
        try writeExtractor(version: "0.4.1")
        XCTAssertNil(AppRuntime.engineCompatibilityProblem(at: root))
    }

    func testNewerEngineIsAccepted() throws {
        try writeExtractor(version: "1.0.0")
        XCTAssertNil(AppRuntime.engineCompatibilityProblem(at: root))
    }

    func testStaleEngineIsRejectedWithBothVersions() throws {
        try writeExtractor(version: "0.3.2")
        let problem = try XCTUnwrap(AppRuntime.engineCompatibilityProblem(at: root))
        XCTAssertTrue(problem.contains("0.3.2"), problem)
        XCTAssertTrue(problem.contains("0.4.1"), problem)
        XCTAssertTrue(problem.contains("build_app.sh"), problem)
    }

    func testUnreadableEngineIsRejected() throws {
        let problem = try XCTUnwrap(AppRuntime.engineCompatibilityProblem(at: root))
        XCTAssertTrue(problem.contains("Could not determine"), problem)
    }

    func testEngineRootDetection() throws {
        XCTAssertFalse(AppRuntime.isEngineRoot(root))
        try writeExtractor(version: "0.4.1")
        XCTAssertTrue(AppRuntime.isEngineRoot(root))
    }

    func testMinimumMatchesTheShippedEngine() {
        // Guards against bumping one of build_app.sh / AppRuntime without the other.
        XCTAssertEqual(AppRuntime.minimumEngineVersion, SemanticVersion(0, 4, 1))
    }
}
