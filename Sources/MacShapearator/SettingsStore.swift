import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: ExtractionSettings {
        didSet { save() }
    }

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("MacShapearator", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(ExtractionSettings.self, from: data) {
            self.settings = Self.normalize(decoded)
        } else {
            self.settings = Self.normalize(ExtractionSettings())
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
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
