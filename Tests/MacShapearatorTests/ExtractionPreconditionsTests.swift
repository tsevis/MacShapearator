import XCTest
@testable import MacShapearator

/// Found by the Python contract tests: with naming switched on, a provider
/// that needs a model, and no model chosen, the engine neither fails nor
/// warns. It reports `naming.requested: false`, exports icon_001, icon_002,
/// and summarises the run as "Ollama local + " with nothing after the plus.
/// The user asked to have their icons named and gets a numbered pile.
///
/// The toggle belongs to the app, so the app is where this is caught.
final class ExtractionPreconditionsTests: XCTestCase {
    private func settings(_ provider: String, naming: Bool, adjust: (inout ExtractionSettings) -> Void = { _ in }) -> ExtractionSettings {
        var settings = ExtractionSettings()
        settings.provider = provider
        settings.semanticNaming = naming
        adjust(&settings)
        return settings
    }

    func testNamingWithoutAnOllamaModelIsRefused() throws {
        let problem = try XCTUnwrap(
            ExtractionPreconditions.problem(with: settings("ollama", naming: true) { $0.ollamaModel = "" }),
            "the run would export generic names with the naming toggle on")
        XCTAssertTrue(problem.lowercased().contains("model"), problem)
    }

    func testNamingWithoutALlamacppModelIsRefused() throws {
        let problem = try XCTUnwrap(
            ExtractionPreconditions.problem(with: settings("llamacpp", naming: true) { $0.llamacppModel = "   " }),
            "whitespace is not a model name")
        XCTAssertTrue(problem.lowercased().contains("model"), problem)
    }

    func testAChosenModelPasses() {
        XCTAssertNil(ExtractionPreconditions.problem(
            with: settings("ollama", naming: true) { $0.ollamaModel = "qwen2.5vl:3b" }))
    }

    func testGeometryNeedsNoModel() {
        XCTAssertNil(ExtractionPreconditions.problem(with: settings("geometry", naming: false)))
    }

    /// Naming off is a deliberate geometry run; the empty model is irrelevant.
    func testAnUnusedEmptyModelIsNotAProblem() {
        XCTAssertNil(ExtractionPreconditions.problem(with: settings("ollama", naming: false)))
    }
}
