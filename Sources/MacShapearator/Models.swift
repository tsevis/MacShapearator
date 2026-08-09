import Foundation

struct ExtractionSettings: Codable, Equatable {
    /// Empty means "use whatever ships in the app bundle"; AppRuntime resolves it.
    /// Never default to a developer's checkout -- the app must run on any Mac.
    var backendRoot: String = ""
    var pythonPath: String = ""
    var provider: String = "geometry"
    var ollamaURL: String = "http://127.0.0.1:11434"
    var ollamaModel: String = "qwen2.5vl:3b"
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

struct OllamaRuntimeStatus: Equatable {
    var isInstalled: Bool = false
    var binaryPath: String?
    var isServerReachable: Bool = false
    var installedModels: [String] = []
    var recommendedModel: String = "qwen2.5vl:3b"
    var statusMessage: String = "Checking local Ollama runtime..."
    var startGuidance: String = "Launch Ollama.app or run `ollama serve`, then refresh status."

    var hasRecommendedModel: Bool {
        installedModels.contains(recommendedModel)
    }
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
