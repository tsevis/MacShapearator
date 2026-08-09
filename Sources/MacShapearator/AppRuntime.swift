import Foundation

enum AppRuntime {
    static let bundledBackendFolder = "BundledBackend"
    static let bundledPythonFolder = "BundledPython"
    static let bundledPythonExecutable = "python/bin/python3"
    static let bundledBinFolder = "BundledBin"
    static let bundledThirdPartyFolder = "ThirdParty"
    static let bundledInkscapeAppFolder = "Inkscape.app"
    static let bundledScriptsFolder = "Scripts"
    static let bridgeScriptName = "extract_bridge.py"

    static func bundledBackendRoot() -> URL? {
        if let direct = Bundle.main.resourceURL?.appendingPathComponent(bundledBackendFolder, isDirectory: true),
           FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        if let nested = Bundle.main.resourceURL?
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(bundledBackendFolder, isDirectory: true),
           FileManager.default.fileExists(atPath: nested.path) {
            return nested
        }
        return nil
    }

    static func bundledBridgeScript() -> URL? {
        if let direct = Bundle.main.resourceURL?
            .appendingPathComponent(bundledScriptsFolder, isDirectory: true)
            .appendingPathComponent(bridgeScriptName),
           FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        if let nested = Bundle.main.resourceURL?
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(bundledScriptsFolder, isDirectory: true)
            .appendingPathComponent(bridgeScriptName),
           FileManager.default.fileExists(atPath: nested.path) {
            return nested
        }
        return nil
    }

    static func resolveBackendRoot(from configuredPath: String) -> URL? {
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let configuredURL = URL(fileURLWithPath: trimmed)
            if FileManager.default.fileExists(atPath: configuredURL.path) {
                return configuredURL
            }
        }
        return bundledBackendRoot()
    }

    static func resolveBridgeScript() -> URL? {
        if let bundled = bundledBridgeScript(), FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Scripts", isDirectory: true)
            .appendingPathComponent(bridgeScriptName)
        if FileManager.default.fileExists(atPath: local.path) {
            return local
        }
        return nil
    }

    static func bundledPythonRoot() -> URL? {
        if let direct = Bundle.main.resourceURL?.appendingPathComponent(bundledPythonFolder, isDirectory: true),
           FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        if let nested = Bundle.main.resourceURL?
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(bundledPythonFolder, isDirectory: true),
           FileManager.default.fileExists(atPath: nested.path) {
            return nested
        }
        return nil
    }

    static func bundledPythonExecutableURL() -> URL? {
        guard let root = bundledPythonRoot() else { return nil }
        let executable = root.appendingPathComponent(bundledPythonExecutable)
        return FileManager.default.isExecutableFile(atPath: executable.path) ? executable : nil
    }

    static func bundledBinDirectory() -> URL? {
        if let direct = Bundle.main.resourceURL?.appendingPathComponent(bundledBinFolder, isDirectory: true),
           FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        if let nested = Bundle.main.resourceURL?
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(bundledBinFolder, isDirectory: true),
           FileManager.default.fileExists(atPath: nested.path) {
            return nested
        }
        return nil
    }

    static func bundledInkscapeExecutable() -> URL? {
        let candidates: [URL?] = [
            Bundle.main.resourceURL?
                .appendingPathComponent(bundledThirdPartyFolder, isDirectory: true)
                .appendingPathComponent(bundledInkscapeAppFolder, isDirectory: true)
                .appendingPathComponent("Contents/MacOS/inkscape"),
            Bundle.main.resourceURL?
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(bundledThirdPartyFolder, isDirectory: true)
                .appendingPathComponent(bundledInkscapeAppFolder, isDirectory: true)
                .appendingPathComponent("Contents/MacOS/inkscape"),
        ]
        for candidate in candidates {
            if let candidate, FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static func resolvePythonExecutable(from configuredPath: String) -> URL? {
        if let bundled = bundledPythonExecutableURL() {
            return bundled
        }
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, FileManager.default.isExecutableFile(atPath: trimmed) {
            return URL(fileURLWithPath: trimmed)
        }
        if let fallback = defaultPythonCandidates().first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: fallback)
        }
        return nil
    }

    static func defaultPythonCandidates() -> [String] {
        [
            "/Users/tsevis/.pyenv/versions/3.10.13/bin/python",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
    }

    static func defaultPythonPath(existing: String) -> String {
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, FileManager.default.isExecutableFile(atPath: trimmed) {
            return trimmed
        }
        return defaultPythonCandidates().first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? existing
    }
}
