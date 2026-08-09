import Foundation
import AppKit

@MainActor
final class ExtractionViewModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var progressMessage: String = "Idle"
    @Published var state: ExtractionPhaseState = .idle
    @Published var result: ExtractionResultRecord?
    @Published var selectedIcon: ExtractedIconRecord?

    private var process: Process?
    private var progressDecoder = JSONDecoder()
    private var resultDecoder = JSONDecoder()

    func runExtraction(settingsStore: SettingsStore, formats: Set<String>) {
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
        settings.backendRoot = backendRoot.path
        settings.pythonPath = pythonExecutable.path

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MacShapearator", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let settingsURL = tempDir.appendingPathComponent("settings.json")
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
            "--formats"
        ] + formats.sorted()
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
                if process.terminationStatus != 0 {
                    self?.state = .failed(errText.isEmpty ? "Extraction failed." : errText)
                }
                self?.process = nil
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
            if line.hasPrefix("PROGRESS\t") {
                let payload = String(line.dropFirst(9))
                if let data = payload.data(using: .utf8),
                   let event = try? progressDecoder.decode(ProgressEvent.self, from: data) {
                    progress = event.fraction
                    progressMessage = event.message
                }
            } else if line.hasPrefix("RESULT\t") {
                let payload = String(line.dropFirst(7))
                if let data = payload.data(using: .utf8),
                   let extraction = try? resultDecoder.decode(ExtractionResultRecord.self, from: data) {
                    result = extraction
                    selectedIcon = extraction.icons.first
                    progress = 1
                    progressMessage = "Done. Exported \(extraction.icons.count) items."
                    state = .success(extraction.providerSummary)
                }
            }
        }
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
