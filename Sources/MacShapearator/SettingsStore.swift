import Foundation
import AppKit

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: ExtractionSettings {
        didSet { file.save(settings) }
    }

    private let file: SettingsFile

    init() {
        let store = SettingsFile(
            url: AppRuntime.applicationSupportDirectory().appendingPathComponent("settings.json"))
        file = store
        settings = Self.normalize(store.load() ?? ExtractionSettings())
        store.flush(on: NSApplication.willTerminateNotification)
    }

    /// Write immediately rather than waiting for the coalescing window.
    func save() {
        file.save(settings)
        file.flush()
    }

    private static func normalize(_ settings: ExtractionSettings) -> ExtractionSettings {
        var normalized = settings
        if let bundledPython = AppRuntime.bundledPythonExecutableURL() {
            normalized.pythonPath = bundledPython.path
        } else {
            normalized.pythonPath = AppRuntime.defaultPythonPath(existing: normalized.pythonPath)
        }
        if !AppRuntime.isEngineRoot(URL(fileURLWithPath: normalized.backendRoot)),
           let resolved = AppRuntime.resolveBackendRoot(from: "") {
            normalized.backendRoot = resolved.path
        }
        if normalized.localModelRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized.localModelRoot = AppRuntime.defaultLocalModelRoot()
        }
        return normalized
    }
}
