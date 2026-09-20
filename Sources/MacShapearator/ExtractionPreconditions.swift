import Foundation

/// What must be true before an extraction is worth starting.
enum ExtractionPreconditions {
    /// The model a provider needs, and nil for one that needs none.
    ///
    /// A function rather than a stored table: a static dictionary of key paths
    /// is shared mutable state as far as the concurrency checker is concerned,
    /// and this needs no state at all.
    private static func selectedModel(in settings: ExtractionSettings) -> String? {
        switch settings.provider {
        case "ollama": return settings.ollamaModel
        case "llamacpp": return settings.llamacppModel
        case "directory": return settings.localModelName
        default: return nil
        }
    }

    private static func backendName(for provider: String) -> String {
        switch provider {
        case "ollama": return "Ollama"
        case "llamacpp": return "llama.cpp"
        case "directory": return "model directory"
        default: return provider
        }
    }

    /// `nil` when the run can go ahead, otherwise what the user has to fix.
    ///
    /// The engine does not treat a missing model as an error: it decides
    /// naming was never requested, exports icon_001 upward, and says nothing.
    /// That is defensible engine-side, but the naming toggle belongs to the
    /// app, so the app owes the user the explanation.
    static func problem(with settings: ExtractionSettings) -> String? {
        guard settings.semanticNaming,
              let model = selectedModel(in: settings),
              model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        return "Naming icons is switched on, but no \(backendName(for: settings.provider)) model is selected. "
            + "Choose one in Settings, or switch naming off to export with generic filenames."
    }
}
