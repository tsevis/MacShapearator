import Foundation

struct ExtractionSettings: Codable, Equatable {
    var backendRoot: String = "/Users/tsevis/AI/ClaudeCode/shapearator"
    var pythonPath: String = "/Users/tsevis/.pyenv/versions/3.10.13/bin/python"
    var provider: String = "geometry"
    var ollamaURL: String = "http://127.0.0.1:11434"
    var ollamaModel: String = "qwen2.5vl:3b"
    var localModelRoot: String = "/Users/tsevis/AI/ClaudeCode/mozaix/models"
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
}

struct ExtractionResultRecord: Codable {
    let inputPath: String
    let outputDir: String
    let providerSummary: String
    let icons: [ExtractedIconRecord]
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
