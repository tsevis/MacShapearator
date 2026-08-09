import Foundation
import AppKit

@MainActor
final class OllamaRuntimeViewModel: ObservableObject {
    @Published var status = OllamaRuntimeStatus()
    @Published var isRefreshing = false
    @Published var isDownloadingModel = false

    func refresh(using settings: ExtractionSettings) {
        guard !isRefreshing else { return }
        isRefreshing = true
        status.statusMessage = "Checking local Ollama runtime..."
        Task.detached {
            let refreshed = await Self.inspect(using: settings)
            await MainActor.run {
                self.status = refreshed
                self.isRefreshing = false
            }
        }
    }

    func downloadRecommendedModel(using settings: ExtractionSettings) {
        guard !isDownloadingModel else { return }
        isDownloadingModel = true
        status.statusMessage = "Downloading \(status.recommendedModel)..."
        Task.detached {
            let binaryPath = await Self.findOllamaBinary()
            guard let binaryPath else {
                await MainActor.run {
                    self.isDownloadingModel = false
                    self.status.statusMessage = "Ollama is not installed locally."
                }
                return
            }
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binaryPath)
                process.arguments = ["pull", settings.ollamaModel]
                try process.run()
                process.waitUntilExit()
            } catch {
                await MainActor.run {
                    self.isDownloadingModel = false
                    self.status.statusMessage = "Could not start model download: \(error.localizedDescription)"
                }
                return
            }
            let refreshed = await Self.inspect(using: settings)
            await MainActor.run {
                self.status = refreshed
                self.isDownloadingModel = false
            }
        }
    }

    func openInstallPage() {
        guard let url = URL(string: "https://ollama.com/download") else { return }
        NSWorkspace.shared.open(url)
    }

    func openModelLibrary() {
        guard let url = URL(string: "https://ollama.com/library/qwen2.5vl:3b") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func inspect(using settings: ExtractionSettings) async -> OllamaRuntimeStatus {
        var result = OllamaRuntimeStatus(recommendedModel: settings.ollamaModel.isEmpty ? "qwen2.5vl:3b" : settings.ollamaModel)
        let binaryPath = await findOllamaBinary()
        result.binaryPath = binaryPath
        result.isInstalled = binaryPath != nil
        guard let binaryPath else {
            result.statusMessage = "Ollama is not installed. Install Ollama to enable local semantic naming."
            return result
        }

        result.isServerReachable = await isServerReachable(baseURL: settings.ollamaURL)
        result.installedModels = await listModels(binaryPath: binaryPath)

        if !result.isServerReachable {
            result.statusMessage = "Ollama is installed, but the local server is not reachable at \(settings.ollamaURL)."
        } else if !result.hasRecommendedModel {
            result.statusMessage = "Ollama is running, but \(result.recommendedModel) is not downloaded yet."
        } else {
            result.statusMessage = "Ollama is installed, running, and ready with \(result.recommendedModel)."
        }
        return result
    }

    private static func findOllamaBinary() async -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ollama"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (path?.isEmpty == false) ? path : nil
        } catch {
            return nil
        }
    }

    private static func listModels(binaryPath: String) async -> [String] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["list"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output
                .split(separator: "\n")
                .dropFirst()
                .compactMap { line in
                    let name = line.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
                    return name.isEmpty || name.hasSuffix(":cloud") ? nil : name
                }
                .sorted()
        } catch {
            return []
        }
    }

    private static func isServerReachable(baseURL: String) async -> Bool {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines) + "/api/tags") else {
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
