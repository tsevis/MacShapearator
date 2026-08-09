import Foundation

enum AppRuntime {
    /// Oldest engine this app knows how to talk to. The bridge relies on
    /// behaviour added in 0.4.1 (enforced preflight, per-icon naming status,
    /// staged manifest-tracked exports), so an older engine would misreport
    /// results rather than fail loudly. Keep in step with build_app.sh.
    static let minimumEngineVersion = SemanticVersion(0, 4, 1)

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

    static func bundledBridgeScript(named name: String = bridgeScriptName) -> URL? {
        if let direct = Bundle.main.resourceURL?
            .appendingPathComponent(bundledScriptsFolder, isDirectory: true)
            .appendingPathComponent(name),
           FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        if let nested = Bundle.main.resourceURL?
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(bundledScriptsFolder, isDirectory: true)
            .appendingPathComponent(name),
           FileManager.default.fileExists(atPath: nested.path) {
            return nested
        }
        return nil
    }

    static func resolveBackendRoot(from configuredPath: String) -> URL? {
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, isEngineRoot(URL(fileURLWithPath: trimmed)) {
            return URL(fileURLWithPath: trimmed)
        }
        return bundledBackendRoot() ?? developmentBackendRoot()
    }

    /// A directory is an engine root if it holds the extractor package.
    static func isEngineRoot(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("services/extractor.py").path)
    }

    /// Locate a Shapearator checkout when running from source (`swift run`),
    /// where there is no app bundle to read the engine from. Looked up by
    /// position relative to this project, and via SHAPEARATOR_SRC, so it works
    /// on any machine without a path baked into the source.
    static func developmentBackendRoot() -> URL? {
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["SHAPEARATOR_SRC"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(cwd.appendingPathComponent("../shapearator"))
        candidates.append(cwd.deletingLastPathComponent().appendingPathComponent("shapearator"))
        return candidates.first(where: isEngineRoot)?.standardizedFileURL
    }

    static func resolveBridgeScript(named name: String = bridgeScriptName) -> URL? {
        if let bundled = bundledBridgeScript(named: name) {
            return bundled
        }
        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Scripts", isDirectory: true)
            .appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: local.path) ? local : nil
    }

    static let engineBridgeScriptName = "engine_bridge.py"

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

    /// Interpreters to try when the app is run from source rather than a bundle.
    /// A packaged app always uses its own bundled interpreter and never gets here.
    static func defaultPythonCandidates() -> [String] {
        [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
    }

    /// `~/Library/Application Support/MacShapearator`, created on demand.
    static func applicationSupportDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let directory = base.appendingPathComponent("MacShapearator", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Where downloaded model weights live when the user has not chosen a folder.
    static func defaultLocalModelRoot() -> String {
        applicationSupportDirectory().appendingPathComponent("models", isDirectory: true).path
    }

    static func defaultPythonPath(existing: String) -> String {
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, FileManager.default.isExecutableFile(atPath: trimmed) {
            return trimmed
        }
        return defaultPythonCandidates().first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? existing
    }

    // MARK: - Engine version

    /// Read the engine version: from `ENGINE_VERSION` if build_app.sh wrote one,
    /// otherwise from the engine's own `APP_VERSION`.
    static func engineVersion(at root: URL) -> SemanticVersion? {
        let stamp = root.appendingPathComponent("ENGINE_VERSION")
        if let text = try? String(contentsOf: stamp, encoding: .utf8),
           let parsed = SemanticVersion(text) {
            return parsed
        }
        let extractor = root.appendingPathComponent("services/extractor.py")
        guard let source = try? String(contentsOf: extractor, encoding: .utf8),
              let assignment = source.range(of: #"APP_VERSION\s*=\s*"[^"]+""#, options: .regularExpression),
              let quoted = source[assignment].range(of: #""[^"]+""#, options: .regularExpression) else {
            return nil
        }
        return SemanticVersion(source[quoted].trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
    }

    /// Returns nil when the engine is usable, or a message explaining why not.
    ///
    /// The packaged app once shipped an engine months out of date that still
    /// imported cleanly, so extraction silently ran known-buggy code. This makes
    /// that failure loud.
    static func engineCompatibilityProblem(at root: URL) -> String? {
        guard let found = engineVersion(at: root) else {
            return "Could not determine the version of the extraction engine at \(root.path). "
                + "Rebuild the app with build_app.sh."
        }
        guard found >= minimumEngineVersion else {
            return "The bundled extraction engine is \(found), but this app needs "
                + "\(minimumEngineVersion) or newer. Rebuild the app with build_app.sh."
        }
        return nil
    }
}

/// Minimal dotted-version comparison, tolerating a leading "v".
struct SemanticVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ major: Int, _ minor: Int, _ patch: Int) {
        (self.major, self.minor, self.patch) = (major, minor, patch)
    }

    init?(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        let parts = cleaned.split(separator: ".", maxSplits: 2).map(String.init)
        guard !parts.isEmpty, let major = Int(parts[0]) else { return nil }
        self.major = major
        self.minor = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        // Tolerate suffixes such as "1-rc2".
        self.patch = parts.count > 2 ? Int(parts[2].prefix(while: \.isNumber)) ?? 0 : 0
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
