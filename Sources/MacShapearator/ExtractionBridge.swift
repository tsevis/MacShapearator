import Foundation
import AppKit

@MainActor
final class ExtractionViewModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var progressMessage: String = "Idle"
    @Published var state: ExtractionPhaseState = .idle
    @Published var result: ExtractionResultRecord?
    @Published var selectedIcon: ExtractedIconRecord?

    /// Set when the backend reported not-ready; drives the "export anyway?" prompt.
    @Published var preflight: PreflightRecord?
    /// A recoverable failure awaiting the user's answer.
    @Published var pendingUnnamedPrompt: BridgeErrorRecord?

    private var process: Process?
    private var decoder = JSONDecoder()
    private var previewDirectory: URL?
    private var lastRun: (store: SettingsStore, formats: Set<String>)?

    /// Re-run the last extraction, accepting generic filenames.
    func retryAllowingUnnamed() {
        guard let lastRun else { return }
        pendingUnnamedPrompt = nil
        runExtraction(settingsStore: lastRun.store, formats: lastRun.formats, allowUnnamed: true)
    }

    func dismissUnnamedPrompt() {
        pendingUnnamedPrompt = nil
        state = .idle
        progressMessage = "Idle"
    }

    func runExtraction(settingsStore: SettingsStore, formats: Set<String>, allowUnnamed: Bool = false) {
        lastRun = (settingsStore, formats)
        var settings = settingsStore.settings
        let input = settings.lastInputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = settings.lastOutputDir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !output.isEmpty else {
            state = .failed("Choose an input sheet and output folder first.")
            return
        }
        guard FileManager.default.fileExists(atPath: input) else {
            state = .failed("Input sheet was not found.")
            return
        }
        guard let backendRoot = AppRuntime.resolveBackendRoot(from: settings.backendRoot) else {
            state = .failed("The bundled or configured extractor backend could not be found.")
            return
        }
        guard let scriptURL = AppRuntime.resolveBridgeScript() else {
            state = .failed("The bundled bridge script could not be found.")
            return
        }
        guard let pythonExecutable = AppRuntime.resolvePythonExecutable(from: settings.pythonPath) else {
            state = .failed("No usable Python runtime was found. Rebuild the app bundle or choose a valid Python path.")
            return
        }
        // Refuse to run against an engine older than this app understands, rather
        // than silently producing results from known-buggy code.
        if let problem = AppRuntime.engineCompatibilityProblem(at: backendRoot) {
            state = .failed(problem)
            return
        }
        settings.backendRoot = backendRoot.path
        settings.pythonPath = pythonExecutable.path

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MacShapearator", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let settingsURL = tempDir.appendingPathComponent("settings.json")

        // UI thumbnails are scratch data. They used to be written into the user's
        // export folder, where nothing ever cleaned them up.
        let previewDir = tempDir.appendingPathComponent("previews-\(UUID().uuidString)", isDirectory: true)
        previewDirectory = previewDir
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            state = .failed("Could not write temporary settings: \(error.localizedDescription)")
            return
        }

        let task = Process()
        task.executableURL = pythonExecutable
        task.currentDirectoryURL = backendRoot
        task.arguments = [
            scriptURL.path,
            "--settings", settingsURL.path,
            "--input", input,
            "--output", output,
            "--preview-dir", previewDir.path,
        ] + (allowUnnamed ? ["--allow-unnamed"] : []) + ["--formats"] + formats.sorted()
        task.environment = buildEnvironment(backendRoot: backendRoot, pythonExecutable: pythonExecutable)

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        var buffer = ""
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.consumeOutput(chunk: chunk, buffer: &buffer)
            }
        }

        task.terminationHandler = { [weak self] process in
            stdout.fileHandleForReading.readabilityHandler = nil
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Task { @MainActor in
                guard let self else { return }
                self.process = nil
                guard process.terminationStatus != 0 else { return }
                // A structured ERROR line has already set a precise state; only
                // fall back to stderr when the bridge died without reporting.
                if case .failed = self.state { return }
                if self.pendingUnnamedPrompt != nil { return }
                self.state = .failed(errText.isEmpty ? "Extraction failed." : errText)
            }
        }

        do {
            progress = 0
            progressMessage = "Preparing extraction..."
            result = nil
            selectedIcon = nil
            state = .running
            process = task
            try task.run()
        } catch {
            state = .failed("Could not start extractor: \(error.localizedDescription)")
        }
    }

    private func consumeOutput(chunk: String, buffer: inout String) {
        buffer += chunk
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(buffer.startIndex...range.lowerBound)
            guard !line.isEmpty else { continue }
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let tag = String(line[..<tab])
            guard let data = String(line[line.index(after: tab)...]).data(using: .utf8) else { continue }

            switch tag {
            case "PROGRESS":
                if let event = try? decoder.decode(ProgressEvent.self, from: data) {
                    progress = event.fraction
                    progressMessage = event.message
                }
            case "PREFLIGHT":
                preflight = try? decoder.decode(PreflightRecord.self, from: data)
            case "RESULT":
                if let extraction = try? decoder.decode(ExtractionResultRecord.self, from: data) {
                    result = extraction
                    selectedIcon = extraction.icons.first
                    progress = 1
                    progressMessage = completionMessage(for: extraction)
                    state = .success(extraction.providerSummary)
                }
            case "ERROR":
                if let failure = try? decoder.decode(BridgeErrorRecord.self, from: data) {
                    if failure.recoverable == true {
                        // The model is unreachable. Let the user decide whether to
                        // export with generic filenames instead of just failing.
                        pendingUnnamedPrompt = failure
                        progressMessage = "Waiting for your choice..."
                    } else {
                        state = .failed(failure.message)
                        progressMessage = "Extraction failed."
                    }
                }
            default:
                continue
            }
        }
    }

    /// Report what actually happened, not just the icon count: naming outcome
    /// and whether a previous export was replaced both matter to the user.
    private func completionMessage(for extraction: ExtractionResultRecord) -> String {
        var parts = ["Exported \(extraction.icons.count) items"]
        if let naming = extraction.naming, naming.requested {
            parts.append(naming.failed > 0
                ? "\(naming.named) named, \(naming.failed) failed"
                : "\(naming.named) named")
        }
        if let commit = extraction.commit, commit.replaced > 0 {
            parts.append("replaced \(commit.replaced) files from the previous run")
        }
        return parts.joined(separator: " · ")
    }

    private func buildEnvironment(backendRoot: URL, pythonExecutable: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        var pathEntries: [String] = []
        pathEntries.append(pythonExecutable.deletingLastPathComponent().path)
        if let bundledBin = AppRuntime.bundledBinDirectory()?.path {
            pathEntries.append(bundledBin)
        }
        if let inkscapeExecutable = AppRuntime.bundledInkscapeExecutable()?.deletingLastPathComponent().path {
            pathEntries.append(inkscapeExecutable)
        }
        pathEntries.append(currentPath)
        env["PATH"] = pathEntries.joined(separator: ":")
        if let bundledPythonRoot = AppRuntime.bundledPythonRoot()?.appendingPathComponent("python").path {
            env["PYTHONHOME"] = bundledPythonRoot
        }
        env["PYTHONNOUSERSITE"] = "1"
        env["SHAPEARATOR_BUNDLED_BACKEND"] = backendRoot.path
        return env
    }
}

extension ExtractedIconRecord {
    var previewURL: URL? {
        guard let previewPath, !previewPath.isEmpty else { return nil }
        return URL(fileURLWithPath: previewPath)
    }

    var primaryFormatsText: String {
        outputs.keys.sorted().joined(separator: ", ")
    }

    var sourceText: String {
        guard sourceSize.count >= 2 else { return "-" }
        return "\(sourceSize[0]) x \(sourceSize[1])"
    }

    var canvasText: String {
        guard canvasSize.count >= 2 else { return "-" }
        return "\(canvasSize[0]) x \(canvasSize[1])"
    }
}
