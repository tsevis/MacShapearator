import Foundation

/// What must be true before an extraction is worth starting.
enum ExtractionPreconditions {
    /// Providers that cannot name anything without being told which model.
    private static let modelKeyPaths: [String: KeyPath<ExtractionSettings, String>] = [
        "ollama": \.ollamaModel,
        "llamacpp": \.llamacppModel,
        "directory": \.localModelName,
    ]

    private static let backendNames = [
        "ollama": "Ollama",
        "llamacpp": "llama.cpp",
        "directory": "model directory",
    ]

    /// `nil` when the run can go ahead, otherwise what the user has to fix.
    ///
    /// The engine does not treat a missing model as an error: it decides
    /// naming was never requested, exports icon_001 upward, and says nothing.
    /// That is defensible engine-side, but the naming toggle belongs to the
    /// app, so the app owes the user the explanation.
    static func problem(with settings: ExtractionSettings) -> String? {
        guard settings.semanticNaming,
              let keyPath = modelKeyPaths[settings.provider],
              settings[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        let backend = backendNames[settings.provider] ?? settings.provider
        return "Naming icons is switched on, but no \(backend) model is selected. "
            + "Choose one in Settings, or switch naming off to export with generic filenames."
    }
}
