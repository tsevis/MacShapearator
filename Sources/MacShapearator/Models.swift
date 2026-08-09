import Foundation

struct ExtractionSettings: Codable, Equatable {
    /// Empty means "use whatever ships in the app bundle"; AppRuntime resolves it.
    /// Never default to a developer's checkout -- the app must run on any Mac.
    var backendRoot: String = ""
    var pythonPath: String = ""
    var provider: String = "geometry"
    var ollamaURL: String = "http://127.0.0.1:11434"
    var ollamaModel: String = "qwen2.5vl:3b"
    var llamacppURL: String = "http://127.0.0.1:8080"
    var llamacppModel: String = ""
    /// Where downloaded llama.cpp GGUF weights live.
    var modelsRoot: String = AppRuntime.defaultLocalModelRoot()
    var localModelRoot: String = AppRuntime.defaultLocalModelRoot()
    var localModelName: String = ""
    var semanticNaming: Bool = false
    var defaultFormats: [String] = ["png", "svg"]
    var outputWidth: Int = 512
    var outputHeight: Int = 512
    var canvasMode: String = "uniform_to_largest"
    var bitmapExportMode: String = "transparent_preserve_interior"
    var padding: Int = 12
    var minArea: Int = 200
    var mergeGap: Int = 13
    var lastInputPath: String = ""
    var lastOutputDir: String = ""
}

// MARK: - Engine-reported model runtime
//
// These mirror services/model_registry.py and services/first_run.py. Discovery
// and readiness are the engine's job -- reimplementing them in Swift is what
// left the Mac app Ollama-only while the engine gained a second backend.

struct ModelDescriptorRecord: Codable, Hashable, Identifiable {
    let name: String
    let source: String
    let location: String
    let priority: Int
    let recommendation: String
    let supportsVision: Bool

    var id: String { "\(source)/\(name)" }
}

struct StartableModelRecord: Codable, Hashable, Identifiable {
    let displayName: String
    let priority: Int
    let source: String

    var id: String { displayName }
}

struct BackendAvailability: Codable, Equatable {
    let ollamaReachable: Bool
    let llamacppBinary: Bool
}

struct ModelsRecord: Codable {
    let backends: BackendAvailability
    let ollama: [ModelDescriptorRecord]
    let llamacpp: [ModelDescriptorRecord]
    let llamacppStartable: [StartableModelRecord]
    let directory: [ModelDescriptorRecord]
}

struct SetupCandidateRecord: Codable, Hashable, Identifiable {
    let key: String
    let displayName: String
    let recommendation: String
    let backend: String
    let installed: Bool
    let approxGB: Double
    let defaultSelected: Bool
    let label: String

    var id: String { "\(backend)/\(key)" }
}

struct SetupStatusRecord: Codable {
    let backends: BackendAvailability
    let setupMarked: Bool
    let needsFirstRun: Bool
    let candidates: [SetupCandidateRecord]
}

struct InstallProgressRecord: Codable {
    let backend: String
    let modelKey: String
    let phase: String
    let completed: Int
    let total: Int
    let fraction: Double
    let message: String
}

struct InstalledRecord: Codable {
    let key: String
    let backend: String
    let provider: String
    let ollamaModel: String
    let llamacppModel: String
    let semanticNaming: Bool
}

struct ServerRecord: Codable {
    let running: Bool
    let model: String?
    let message: String
}

struct ExtractedIconRecord: Codable, Identifiable, Hashable {
    let index: Int
    var id: Int { index }
    let stem: String
    let outputs: [String: String]
    let previewPath: String?
    let canvasSize: [Int]
    let sourceSize: [Int]
    let sourceBounds: [Int]
    let metadataPath: String?
    /// "named", "failed", or "not_requested" -- see the engine's extraction_types.
    let namingStatus: String?
    let namingError: String?
    let semanticTags: [String]?
    let semanticConfidence: Double?

    var wasNamed: Bool { namingStatus == "named" }
    var namingDidFail: Bool { namingStatus == "failed" }
}

/// What semantic naming was asked to do, and what it achieved.
struct NamingSummaryRecord: Codable, Equatable {
    let requested: Bool
    let provider: String?
    let model: String?
    let named: Int
    let failed: Int
    let errors: [String]
    let summary: String
}

/// What the export commit changed in the output folder.
struct CommitReportRecord: Codable, Equatable {
    let written: Int
    let replaced: Int
    let preserved: Int
}

struct ExtractionResultRecord: Codable {
    let inputPath: String
    let outputDir: String
    let providerSummary: String
    let icons: [ExtractedIconRecord]
    let engineVersion: String?
    let naming: NamingSummaryRecord?
    let commit: CommitReportRecord?
    let warnings: [String]?
}

/// Backend readiness, reported before extraction begins.
struct PreflightRecord: Codable {
    let ok: Bool
    let provider: String
    let message: String
    let model: String?
    let visionCapable: Bool?
}

/// A structured failure from the bridge. `recoverable` marks the case the user
/// can answer -- an unreachable model, which they may choose to export past.
struct BridgeErrorRecord: Codable {
    let kind: String
    let message: String
    let provider: String?
    let recoverable: Bool?
}

struct ProgressEvent: Codable {
    let phase: String
    let current: Int
    let total: Int
    let message: String

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(current) / Double(total), 0), 1)
    }
}

enum ExtractionPhaseState: Equatable {
    case idle
    case running
    case success(String)
    case failed(String)
}
