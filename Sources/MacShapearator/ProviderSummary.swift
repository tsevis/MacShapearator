import Foundation

/// The one-line "what will name these icons" summary shown above the run
/// controls. Kept out of the view so the provider list has a single spelling.
enum ProviderSummary {
    static func text(for settings: ExtractionSettings) -> String {
        switch settings.provider {
        case "ollama":
            return "Active provider: Ollama local (\(settings.ollamaModel))"
        case "llamacpp":
            return "Active provider: llama.cpp local (\(named(settings.llamacppModel, fallback: "no model selected")))"
        case "directory":
            return "Active provider: Local directory (\(named(settings.localModelName, fallback: "directory catalog")))"
        case "geometry":
            return "Active provider: Geometry-only local extraction"
        default:
            // A settings file from a newer build. Say what it holds rather
            // than claiming a provider that is not the one in effect.
            return "Active provider: \(settings.provider)"
        }
    }

    private static func named(_ model: String, fallback: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
