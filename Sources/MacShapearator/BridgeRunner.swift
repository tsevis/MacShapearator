import Foundation

/// One tagged line from a bridge script: `TAG\t{json}`.
struct BridgeEvent {
    let tag: String
    let data: Data

    func decode<T: Decodable>(_ type: T.Type) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
}

enum BridgeFailure: Error, LocalizedError {
    case engineUnavailable(String)
    case launchFailed(String)
    case reported(BridgeErrorRecord)

    var errorDescription: String? {
        switch self {
        case .engineUnavailable(let message), .launchFailed(let message):
            return message
        case .reported(let record):
            return record.message
        }
    }
}

/// Runs a Python bridge script and streams its tagged output.
///
/// Both bridges — extraction and engine services — speak the same protocol, so
/// process setup, environment, and line framing live here once.
enum BridgeRunner {
    /// Everything a bridge process needs to start.
    struct Context {
        let script: URL
        let python: URL
        let backend: URL
        /// Temporary; the caller deletes it when the process has finished.
        let settingsFile: URL
        let environment: [String: String]
    }

    /// Resolve the engine and interpreter, and write the settings payload the
    /// scripts read. Throws with a user-facing message when anything is missing.
    static func prepare(settings: ExtractionSettings, scriptName: String) throws -> Context {
        guard let backend = AppRuntime.resolveBackendRoot(from: settings.backendRoot) else {
            throw BridgeFailure.engineUnavailable(
                "The bundled or configured extractor backend could not be found.")
        }
        if let problem = AppRuntime.engineCompatibilityProblem(at: backend) {
            throw BridgeFailure.engineUnavailable(problem)
        }
        guard let script = AppRuntime.resolveBridgeScript(named: scriptName) else {
            throw BridgeFailure.engineUnavailable("The bundled bridge script \(scriptName) could not be found.")
        }
        guard let python = AppRuntime.resolvePythonExecutable(from: settings.pythonPath) else {
            throw BridgeFailure.engineUnavailable(
                "No usable Python runtime was found. Rebuild the app bundle or choose a valid Python path.")
        }

        var payload = settings
        payload.backendRoot = backend.path
        payload.pythonPath = python.path

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MacShapearator", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settingsFile = directory.appendingPathComponent("settings-\(UUID().uuidString).json")
        do {
            try JSONEncoder().encode(payload).write(to: settingsFile, options: .atomic)
        } catch {
            throw BridgeFailure.launchFailed("Could not write temporary settings: \(error.localizedDescription)")
        }

        return Context(
            script: script, python: python, backend: backend, settingsFile: settingsFile,
            environment: environment(backend: backend, python: python))
    }

    /// Run a bridge script to completion, delivering each event as it arrives.
    ///
    /// Long-running commands (a model download) report through `onEvent`, so
    /// the caller sees progress rather than a frozen window.
    @discardableResult
    static func run(
        settings: ExtractionSettings,
        scriptName: String,
        arguments: [String],
        onEvent: (BridgeEvent) async -> Void
    ) async throws -> BridgeOutcome {
        let context = try prepare(settings: settings, scriptName: scriptName)
        defer { try? FileManager.default.removeItem(at: context.settingsFile) }

        let session = try BridgeSession(
            executable: context.python,
            arguments: [context.script.path, "--settings", context.settingsFile.path] + arguments,
            currentDirectory: context.backend,
            environment: context.environment)
        for await event in session.events {
            await onEvent(event)
        }
        return await session.waitForExit()
    }

    /// Run a script and return the first event carrying `tag`.
    static func first<T: Decodable>(
        _ type: T.Type,
        tag: String,
        settings: ExtractionSettings,
        scriptName: String,
        arguments: [String]
    ) async throws -> T {
        var collected: [BridgeEvent] = []
        let outcome = try await run(settings: settings, scriptName: scriptName, arguments: arguments) {
            collected.append($0)
        }
        return try firstEvent(type, tag: tag, in: collected, outcome: outcome)
    }

    /// Pick the answer out of a finished run, or explain why there is none.
    static func firstEvent<T: Decodable>(
        _ type: T.Type,
        tag: String,
        in events: [BridgeEvent],
        outcome: BridgeOutcome
    ) throws -> T {
        if let decoded = events.first(where: { $0.tag == tag })?.decode(type) {
            return decoded
        }
        // The engine's own words outrank the exit code: an ERROR line is
        // written for the user, stderr is written for whoever built the app.
        if let reported = events.first(where: { $0.tag == "ERROR" })?.decode(BridgeErrorRecord.self) {
            throw BridgeFailure.reported(reported)
        }
        var message = "The engine returned no \(tag) response."
        if !outcome.succeeded {
            message += " It exited with status \(outcome.terminationStatus)."
        }
        if !outcome.standardError.isEmpty {
            message += "\n\n\(outcome.standardError.suffix(2000))"
        }
        throw BridgeFailure.launchFailed(message)
    }

    static func environment(backend: URL, python: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        var entries = [python.deletingLastPathComponent().path]
        if let bundledBin = AppRuntime.bundledBinDirectory()?.path {
            entries.append(bundledBin)
        }
        if let inkscape = AppRuntime.bundledInkscapeExecutable()?.deletingLastPathComponent().path {
            entries.append(inkscape)
        }
        entries.append(currentPath)
        env["PATH"] = entries.joined(separator: ":")
        if let pythonRoot = AppRuntime.bundledPythonRoot()?.appendingPathComponent("python").path {
            env["PYTHONHOME"] = pythonRoot
        }
        env["PYTHONNOUSERSITE"] = "1"
        env["SHAPEARATOR_BUNDLED_BACKEND"] = backend.path
        return env
    }
}
