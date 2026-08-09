import XCTest
@testable import MacShapearator

/// Decode payloads captured from real bridge runs.
///
/// The hand-written cases in BridgeProtocolTests pin what we *believe* the
/// bridges emit; these pin what they actually emitted, so an engine-side field
/// rename fails here instead of silently arriving as nil at runtime.
///
/// Regenerate with the bridges after an engine upgrade; see PORTING_PLAN.md §9.
final class FixtureContractTests: XCTestCase {
    private func fixture<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // MacShapearatorTests
            .deletingLastPathComponent()   // Tests
            .appendingPathComponent("Fixtures/\(name)")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }

    func testRealPreflightDecodes() throws {
        let record = try fixture(PreflightRecord.self, "preflight.json")
        XCTAssertEqual(record.provider, "ollama")
        XCTAssertFalse(record.message.isEmpty)
    }

    func testRealModelDiscoveryDecodes() throws {
        let record = try fixture(ModelsRecord.self, "models.json")
        XCTAssertFalse(record.ollama.isEmpty, "the captured run had Ollama models")
        XCTAssertTrue(record.ollama.contains { $0.supportsVision },
                      "at least one discovered model should be vision-capable")
        // Non-vision models must still decode; the UI filters them out itself.
        XCTAssertTrue(record.ollama.contains { !$0.supportsVision })
    }

    func testRealSetupStatusDecodes() throws {
        let record = try fixture(SetupStatusRecord.self, "setup_status.json")
        XCTAssertFalse(record.candidates.isEmpty)
        XCTAssertTrue(record.candidates.contains { $0.backend == "llamacpp" },
                      "llama.cpp candidates must survive decoding — the gap Phase 2 closes")
        XCTAssertTrue(record.candidates.allSatisfy { !$0.label.isEmpty })
    }

    func testRealExtractionResultDecodes() throws {
        let record = try fixture(ExtractionResultRecord.self, "result.json")
        XCTAssertFalse(record.icons.isEmpty)
        XCTAssertNotNil(record.engineVersion)
        XCTAssertNotNil(record.naming)
        XCTAssertNotNil(record.commit)
        // The capture is a real Ollama naming run: every icon was named, and the
        // duplicate label was disambiguated by the engine.
        let naming = try XCTUnwrap(record.naming)
        XCTAssertTrue(naming.requested)
        XCTAssertEqual(naming.named, record.icons.count)
        XCTAssertEqual(naming.failed, 0)
        XCTAssertTrue(record.icons.allSatisfy { $0.wasNamed })
        XCTAssertTrue(record.icons.contains { $0.stem.hasSuffix("-02") },
                      "duplicate labels should arrive already disambiguated")
        XCTAssertEqual(record.commit?.written, 8)
    }

    func testFixturesCarryNoLocalPaths() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains(NSHomeDirectory()),
                           "\(file.lastPathComponent) leaks a real home directory")
        }
    }
}
