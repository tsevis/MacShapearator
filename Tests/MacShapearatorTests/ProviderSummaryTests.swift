import XCTest
@testable import MacShapearator

/// Settings offers four providers. A summary that only knows three tells the
/// user the missing one is doing something else entirely.
final class ProviderSummaryTests: XCTestCase {
    private func settings(provider: String, adjust: (inout ExtractionSettings) -> Void = { _ in }) -> ExtractionSettings {
        var settings = ExtractionSettings()
        settings.provider = provider
        adjust(&settings)
        return settings
    }

    func testNamesTheLlamacppModel() {
        let summary = ProviderSummary.text(for: settings(provider: "llamacpp") { $0.llamacppModel = "Qwen3-VL" })
        XCTAssertTrue(summary.contains("llama.cpp"), summary)
        XCTAssertTrue(summary.contains("Qwen3-VL"), summary)
        XCTAssertFalse(summary.contains("Geometry"), "llama.cpp was reported as geometry-only")
    }

    func testEveryProviderInTheSettingsPickerIsDescribed() {
        // The picker's tags; a provider added there and forgotten here shows
        // the geometry-only text while a model is actually doing the naming.
        for provider in ["ollama", "llamacpp", "directory"] {
            let summary = ProviderSummary.text(for: settings(provider: provider))
            XCTAssertFalse(summary.contains("Geometry-only"), "\(provider) falls through to the default")
        }
    }
}
