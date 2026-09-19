import Foundation
import AppKit

@MainActor
final class ExtractionViewModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var progressMessage: String = "Idle"
    @Published var state: ExtractionPhaseState = .idle
    @Published var result: ExtractionResultRecord?
    @Published var selectedIcon: ExtractedIconRecord?

    /// Non-fatal notes from the engine: worth showing, never worth blocking on.
    @Published var warnings: [String] = []

    /// Set when the backend reported not-ready; drives the "export anyway?" prompt.
    @Published var preflight: PreflightRecord?
    /// A recoverable failure awaiting the user's answer.
    @Published var pendingUnnamedPrompt: BridgeErrorRecord?

    /// Set the moment a run is requested, not when the process appears, so a
    /// second click cannot slip past the guard while the first is starting.
    @Published private(set) var isRunning = false

    private var session: BridgeSession?
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

    /// Stop the running extraction.
    ///
    /// Measured: the engine stages everything and commits at the end, so a run
    /// stopped mid-export publishes nothing and leaves files the user put in
    /// the output folder untouched. It does leave a `.shapearator-staging`
    /// directory behind, which the next run clears.
    func cancel() {
        guard let session else { return }
        progressMessage = "Stopping…"
        session.cancel()
    }

    func runExtraction(settingsStore: SettingsStore, formats: Set<String>, allowUnnamed: Bool = false) {
        // Two extractions writing the same output folder would fight over it.
        guard !isRunning else { return }
        lastRun = (settingsStore, formats)

        let settings = settingsStore.settings
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

        isRunning = true
        Task { await start(settings: settings, input: input, output: output,
                           formats: formats, allowUnnamed: allowUnnamed) }
    }

    // MARK: - Running

    private func start(
        settings: ExtractionSettings,
        input: String,
        output: String,
        formats: Set<String>,
        allowUnnamed: Bool
    ) async {
        defer { isRunning = false }

        let previewDir = makePreviewDirectory()
        let arguments = [
            "--input", input,
            "--output", output,
            "--preview-dir", previewDir.path,
        ] + (allowUnnamed ? ["--allow-unnamed"] : []) + ["--formats"] + formats.sorted()

        progress = 0
        progressMessage = "Preparing extraction..."
        result = nil
        selectedIcon = nil
        warnings = []
        state = .running

        let running: BridgeSession
        do {
            // Resolving the engine, the interpreter and the engine version is
            // the same work every bridge call does; it lives in one place so
            // the two call sites cannot drift apart.
            running = try BridgeRunner.start(
                settings: settings,
                scriptName: AppRuntime.bridgeScriptName,
                arguments: arguments)
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        session = running
        defer { session = nil }

        // Events arrive in order, already on this actor: no interleaving with
        // the exit handling below, which is what used to lose the last line.
        for await event in running.events {
            handle(event)
        }
        let outcome = await running.waitForExit()
        finish(outcome)
    }

    private func handle(_ event: BridgeEvent) {
        switch event.tag {
        case "PROGRESS":
            if let progressEvent = event.decode(ProgressEvent.self) {
                progress = progressEvent.fraction
                progressMessage = progressEvent.message
            }
        case "PREFLIGHT":
            preflight = event.decode(PreflightRecord.self)
        case "RESULT":
            if let extraction = event.decode(ExtractionResultRecord.self) {
                result = extraction
                selectedIcon = extraction.icons.first
                warnings = extraction.warnings ?? []
                progress = 1
                progressMessage = completionMessage(for: extraction)
                state = .success(extraction.providerSummary)
            }
        case "ERROR":
            if let failure = event.decode(BridgeErrorRecord.self) {
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
            break
        }
    }

    private func finish(_ outcome: BridgeOutcome) {
        guard !outcome.succeeded else { return }
        // A structured ERROR line has already set a precise state, and a
        // recoverable one is waiting on the user; only fall back to stderr
        // when the bridge died without reporting anything.
        if case .failed = state { return }
        if pendingUnnamedPrompt != nil { return }
        if outcome.terminationStatus == SIGTERM {
            state = .idle
            progress = 0
            progressMessage = "Extraction cancelled."
            return
        }
        let detail = outcome.standardError.isEmpty
            ? "Extraction failed with status \(outcome.terminationStatus)."
            : String(outcome.standardError.suffix(2000))
        state = .failed(detail)
        progressMessage = "Extraction failed."
    }

    /// Thumbnails are scratch data. They used to be written into the user's
    /// export folder, where nothing ever cleaned them up; now each run gets a
    /// temporary directory and takes the previous one with it.
    private func makePreviewDirectory() -> URL {
        if let previous = previewDirectory {
            try? FileManager.default.removeItem(at: previous)
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MacShapearator", isDirectory: true)
            .appendingPathComponent("previews-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        previewDirectory = directory
        return directory
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
