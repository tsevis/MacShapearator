import XCTest
@testable import MacShapearator

/// The bridge protocol is the interface most likely to break silently: a field
/// renamed engine-side simply stops arriving. These pin the payloads the
/// Python bridges actually emit — the JSON below is copied from real runs.
final class BridgeProtocolTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Extraction

    func testDecodesPreflight() throws {
        let record = try decode(PreflightRecord.self, """
        {"ok": true, "provider": "ollama",
         "message": "Ollama ready with vision model 'qwen2.5vl:3b'.",
         "model": "qwen2.5vl:3b", "visionCapable": true}
        """)
        XCTAssertTrue(record.ok)
        XCTAssertEqual(record.model, "qwen2.5vl:3b")
        XCTAssertEqual(record.visionCapable, true)
    }

    func testDecodesPreflightWithNullModel() throws {
        let record = try decode(PreflightRecord.self, """
        {"ok": false, "provider": "ollama",
         "message": "Ollama is not reachable at http://127.0.0.1:9.",
         "model": null, "visionCapable": null}
        """)
        XCTAssertFalse(record.ok)
        XCTAssertNil(record.model)
    }

    func testDecodesRecoverableError() throws {
        let record = try decode(BridgeErrorRecord.self, """
        {"kind": "preflight", "message": "Ollama is not reachable.",
         "provider": "ollama", "recoverable": true}
        """)
        XCTAssertEqual(record.recoverable, true)
        XCTAssertEqual(record.kind, "preflight")
    }

    func testDecodesFatalErrorWithoutOptionalFields() throws {
        let record = try decode(BridgeErrorRecord.self, """
        {"kind": "extraction", "message": "Supported inputs are .png and .svg"}
        """)
        XCTAssertNil(record.recoverable)
        XCTAssertNil(record.provider)
    }

    func testDecodesResultWithNamingAndCommit() throws {
        let record = try decode(ExtractionResultRecord.self, """
        {"inputPath": "/tmp/sheet.png", "outputDir": "/tmp/out",
         "providerSummary": "Ollama local + qwen2.5vl:3b", "engineVersion": "0.4.1",
         "icons": [{"index": 1, "stem": "heart", "outputs": {"png": "/tmp/out/png/heart.png"},
                    "previewPath": "/tmp/out/png/heart.png", "canvasSize": [512, 512],
                    "sourceSize": [64, 64], "sourceBounds": [0, 0, 64, 64],
                    "metadataPath": "/tmp/out/metadata/heart.json",
                    "namingStatus": "named", "namingError": null,
                    "semanticTags": ["love"], "semanticConfidence": 0.9}],
         "naming": {"requested": true, "provider": "ollama", "model": "qwen2.5vl:3b",
                    "named": 1, "failed": 0, "errors": [],
                    "summary": "Semantic naming: 1 named via ollama/qwen2.5vl:3b."},
         "commit": {"written": 2, "replaced": 94, "preserved": 1},
         "warnings": []}
        """)
        XCTAssertEqual(record.engineVersion, "0.4.1")
        XCTAssertEqual(record.naming?.named, 1)
        XCTAssertEqual(record.commit?.replaced, 94)
        XCTAssertTrue(record.icons[0].wasNamed)
        XCTAssertFalse(record.icons[0].namingDidFail)
    }

    func testDecodesAFailedIconWithItsReason() throws {
        let record = try decode(ExtractedIconRecord.self, """
        {"index": 2, "stem": "icon_002", "outputs": {}, "previewPath": null,
         "canvasSize": [512, 512], "sourceSize": [10, 10], "sourceBounds": [0, 0, 10, 10],
         "metadataPath": null, "namingStatus": "failed",
         "namingError": "no image was available to label this icon",
         "semanticTags": [], "semanticConfidence": null}
        """)
        XCTAssertTrue(record.namingDidFail)
        XCTAssertEqual(record.namingError, "no image was available to label this icon")
    }

    // MARK: - Engine services

    func testDecodesModelDiscovery() throws {
        let record = try decode(ModelsRecord.self, """
        {"backends": {"ollamaReachable": true, "llamacppBinary": true},
         "ollama": [{"name": "qwen2.5vl:3b", "source": "ollama", "location": "local ollama",
                     "priority": 20, "recommendation": "Best overall", "supportsVision": true},
                    {"name": "bge-m3:latest", "source": "ollama", "location": "local ollama",
                     "priority": 999, "recommendation": "", "supportsVision": false}],
         "llamacpp": [], "directory": [],
         "llamacppStartable": [{"displayName": "Qwen3-VL", "priority": 10, "source": "cache"}]}
        """)
        XCTAssertTrue(record.backends.llamacppBinary)
        XCTAssertEqual(record.ollama.count, 2)
        XCTAssertEqual(record.llamacppStartable.first?.displayName, "Qwen3-VL")
    }

    func testDecodesSetupStatus() throws {
        let record = try decode(SetupStatusRecord.self, """
        {"backends": {"ollamaReachable": true, "llamacppBinary": true},
         "setupMarked": true, "needsFirstRun": false,
         "candidates": [{"key": "qwen3-vl", "displayName": "Qwen3-VL",
                         "recommendation": "Newest", "backend": "llamacpp",
                         "installed": false, "approxGB": 6.5,
                         "defaultSelected": false,
                         "label": "Qwen3-VL · llama.cpp · ~6.5 GB download"}]}
        """)
        XCTAssertFalse(record.needsFirstRun)
        XCTAssertEqual(record.candidates.first?.approxGB, 6.5)
        XCTAssertEqual(record.candidates.first?.id, "llamacpp/qwen3-vl")
    }

    func testDecodesInstallProgressAndCompletion() throws {
        let progress = try decode(InstallProgressRecord.self, """
        {"backend": "ollama", "modelKey": "qwen2.5-vl", "phase": "download",
         "completed": 512, "total": 1024, "fraction": 0.5, "message": "Pulling qwen2.5vl:3b"}
        """)
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.0001)

        let installed = try decode(InstalledRecord.self, """
        {"key": "qwen2.5-vl", "backend": "ollama", "provider": "ollama",
         "ollamaModel": "qwen2.5vl:3b", "llamacppModel": "", "semanticNaming": true}
        """)
        XCTAssertTrue(installed.semanticNaming)
        XCTAssertEqual(installed.provider, "ollama")
    }

    func testDecodesServerStatus() throws {
        let record = try decode(ServerRecord.self, """
        {"running": true, "model": "Qwen3-VL", "message": "Started llama-server with Qwen3-VL."}
        """)
        XCTAssertTrue(record.running)
        XCTAssertEqual(record.model, "Qwen3-VL")
    }

    // MARK: - Settings round-trip

    func testSettingsCarryBothBackends() throws {
        var settings = ExtractionSettings()
        settings.llamacppURL = "http://127.0.0.1:8080"
        settings.llamacppModel = "Qwen3-VL"
        let data = try JSONEncoder().encode(settings)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // The engine bridge maps these by name; a rename here silently drops them.
        for key in ["llamacppURL", "llamacppModel", "modelsRoot", "ollamaURL", "ollamaModel"] {
            XCTAssertNotNil(json[key], "settings payload is missing \(key)")
        }
        let decoded = try JSONDecoder().decode(ExtractionSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }

    func testSettingsDefaultToNoDeveloperPaths() {
        let settings = ExtractionSettings()
        XCTAssertTrue(settings.backendRoot.isEmpty)
        XCTAssertTrue(settings.pythonPath.isEmpty)
        XCTAssertFalse(settings.localModelRoot.contains("/AI/ClaudeCode"))
    }
}
