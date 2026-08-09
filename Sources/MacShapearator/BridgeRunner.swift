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
    /// Resolve the engine and interpreter, and write the settings payload the
    /// scripts read. Throws with a user-facing message when anything is missing.
    static func prepare(settings: ExtractionSettings, scriptName: String) throws -> (
        script: URL, python: URL, backend: URL, settingsFile: URL, environment: [String: String]
    ) {
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

        return (script, python, backend, settingsFile, environment(backend: backend, python: python))
    }

    /// Run a bridge script to completion, delivering each event as it arrives.
    ///
    /// Long-running commands (a model download) report through `onEvent`, so the
    /// caller sees progress rather than a frozen window.
    static func run(
        settings: ExtractionSettings,
        scriptName: String,
        arguments: [String],
        onEvent: @escaping (BridgeEvent) -> Void
    ) async throws {
        let context = try prepare(settings: settings, scriptName: scriptName)
        defer { try? FileManager.default.removeItem(at: context.settingsFile) }

        let task = Process()
        task.executableURL = context.python
        task.currentDirectoryURL = context.backend
        task.arguments = [context.script.path, "--settings", context.settingsFile.path] + arguments
        task.environment = context.environment

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        do {
            try task.run()
        } catch {
            throw BridgeFailure.launchFailed("Could not start the engine: \(error.localizedDescription)")
        }

        var buffer = Data()
        let handle = stdout.fileHandleForReading
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if let event = parse(line: Data(line)) { onEvent(event) }
            }
        }
        if let event = parse(line: buffer) { onEvent(event) }

        task.waitUntilExit()
        _ = stderr.fileHandleForReading.readDataToEndOfFile()
    }

    /// Run a script and return the first event carrying `tag`.
    static func first<T: Decodable>(
        _ type: T.Type,
        tag: String,
        settings: ExtractionSettings,
        scriptName: String,
        arguments: [String]
    ) async throws -> T {
        var decoded: T?
        var reported: BridgeErrorRecord?
        try await run(settings: settings, scriptName: scriptName, arguments: arguments) { event in
            if event.tag == tag, decoded == nil {
                decoded = event.decode(type)
            } else if event.tag == "ERROR", reported == nil {
                reported = event.decode(BridgeErrorRecord.self)
            }
        }
        if let decoded { return decoded }
        if let reported { throw BridgeFailure.reported(reported) }
        throw BridgeFailure.launchFailed("The engine returned no \(tag) response.")
    }

    private static func parse(line: Data) -> BridgeEvent? {
        guard let tab = line.firstIndex(of: UInt8(ascii: "\t")) else { return nil }
        let tag = String(decoding: line[line.startIndex..<tab], as: UTF8.self)
        guard !tag.isEmpty else { return nil }
        return BridgeEvent(tag: tag, data: Data(line[line.index(after: tab)...]))
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
