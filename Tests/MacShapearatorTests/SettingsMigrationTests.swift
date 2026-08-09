import XCTest
@testable import MacShapearator

/// A settings file written by an older build lacks the keys added since.
/// Swift's synthesized Decodable does *not* fall back to a property's default
/// value for a missing key, so without care an upgrade silently discards
/// everything the user had configured.
final class SettingsMigrationTests: XCTestCase {
    /// Exactly the shape written by the build before llama.cpp support existed.
    private let legacy = """
    {"lastInputPath": "/Users/example/sheet.png",
     "defaultFormats": ["jpg", "png"],
     "pythonPath": "/Applications/MacShapearator.app/Contents/Resources/BundledPython/python/bin/python3",
     "ollamaModel": "qwen2.5vl:3b", "mergeGap": 13,
     "backendRoot": "/Users/example/shapearator", "provider": "directory",
     "localModelName": "", "ollamaURL": "http://127.0.0.1:11434", "minArea": 200,
     "localModelRoot": "/Users/example/models", "canvasMode": "uniform_to_largest",
     "lastOutputDir": "/Users/example/out", "semanticNaming": false,
     "outputHeight": 512, "outputWidth": 512, "padding": 12,
     "bitmapExportMode": "transparent_preserve_interior"}
    """

    func testALegacySettingsFileStillDecodes() throws {
        let settings = try JSONDecoder().decode(ExtractionSettings.self, from: Data(legacy.utf8))
        // Preserved from the file:
        XCTAssertEqual(settings.provider, "directory")
        XCTAssertEqual(settings.ollamaModel, "qwen2.5vl:3b")
        XCTAssertEqual(settings.defaultFormats, ["jpg", "png"])
        XCTAssertEqual(settings.lastOutputDir, "/Users/example/out")
        // Filled in for keys the old build never wrote:
        XCTAssertEqual(settings.llamacppURL, "http://127.0.0.1:8080")
        XCTAssertTrue(settings.llamacppModel.isEmpty)
        XCTAssertFalse(settings.modelsRoot.isEmpty)
    }

    func testAnEmptyObjectDecodesToDefaults() throws {
        let settings = try JSONDecoder().decode(ExtractionSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings, ExtractionSettings())
    }
}
