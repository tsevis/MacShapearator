import AppKit
import Foundation

/// Backend readiness, model discovery, and model installation — all delegated
/// to the engine.
///
/// This replaces a Swift reimplementation of those checks that only understood
/// Ollama. Asking the engine means both backends work, and future engine
/// improvements arrive without a corresponding Swift change.
@MainActor
final class ModelRuntimeViewModel: ObservableObject {
    @Published private(set) var preflight: PreflightRecord?
    @Published private(set) var models: ModelsRecord?
    @Published private(set) var setup: SetupStatusRecord?

    @Published private(set) var isRefreshing = false
    @Published private(set) var installingKey: String?
    @Published private(set) var installProgress: Double = 0
    @Published var statusMessage = "Checking local model runtimes..."
    @Published var lastError: String?

    var backends: BackendAvailability? { models?.backends ?? setup?.backends }
    var isInstalling: Bool { installingKey != nil }

    /// Vision models the engine can actually use for the active provider.
    func availableModels(for provider: String) -> [ModelDescriptorRecord] {
        switch provider {
        case "ollama": return models?.ollama.filter(\.supportsVision) ?? []
        case "llamacpp": return models?.llamacpp ?? []
        case "directory": return models?.directory ?? []
        default: return []
        }
    }

    var startableLlamaModels: [StartableModelRecord] { models?.llamacppStartable ?? [] }

    // MARK: - Queries

    func refresh(using settings: ExtractionSettings) {
        guard !isRefreshing, !isInstalling else { return }
        isRefreshing = true
        statusMessage = "Checking local model runtimes..."
        Task {
            async let discovered = query(ModelsRecord.self, tag: "MODELS", command: "models", settings: settings)
            async let status = query(SetupStatusRecord.self, tag: "SETUP", command: "setup-status", settings: settings)
            models = await discovered
            setup = await status
            await refreshPreflight(using: settings)
            isRefreshing = false
        }
    }

    /// Ask the engine whether the configured backend is ready to name icons.
    func refreshPreflight(using settings: ExtractionSettings) async {
        guard settings.provider == "ollama" || settings.provider == "llamacpp" else {
            preflight = nil
            statusMessage = "Geometry only — no model needed."
            return
        }
        preflight = await query(PreflightRecord.self, tag: "PREFLIGHT", command: "preflight", settings: settings)
        statusMessage = preflight?.message ?? statusMessage
    }

    // MARK: - Actions

    func install(candidate: SetupCandidateRecord, settings: ExtractionSettings, onComplete: @escaping (InstalledRecord) -> Void) {
        guard !isInstalling else { return }
        installingKey = candidate.id
        installProgress = 0
        lastError = nil
        statusMessage = "Downloading \(candidate.displayName)…"

        Task {
            var installed: InstalledRecord?
            var failure: String?
            do {
                try await BridgeRunner.run(
                    settings: settings,
                    scriptName: AppRuntime.engineBridgeScriptName,
                    arguments: ["install", "--key", candidate.key, "--backend", candidate.backend]
                ) { event in
                    switch event.tag {
                    case "PROGRESS":
                        if let progress = event.decode(InstallProgressRecord.self) {
                            Task { @MainActor in
                                self.installProgress = progress.fraction
                                self.statusMessage = progress.message
                            }
                        }
                    case "INSTALLED":
                        installed = event.decode(InstalledRecord.self)
                    case "ERROR":
                        failure = event.decode(BridgeErrorRecord.self)?.message
                    default:
                        break
                    }
                }
            } catch {
                failure = error.localizedDescription
            }

            installingKey = nil
            installProgress = 0
            if let installed {
                statusMessage = "\(candidate.displayName) is ready."
                onComplete(installed)
                refresh(using: settings)
            } else {
                lastError = failure ?? "The download did not complete."
                statusMessage = "Download failed."
            }
        }
    }

    /// Start llama-server for a downloaded model, so the user does not have to
    /// run it from a terminal.
    func startLlamaServer(model: String, settings: ExtractionSettings) {
        guard !isInstalling else { return }
        statusMessage = "Starting llama.cpp server…"
        Task {
            do {
                let record = try await BridgeRunner.first(
                    ServerRecord.self, tag: "SERVER",
                    settings: settings,
                    scriptName: AppRuntime.engineBridgeScriptName,
                    arguments: ["start-server", "--key", model]
                )
                statusMessage = record.message
                refresh(using: settings)
            } catch {
                lastError = error.localizedDescription
                statusMessage = "Could not start llama.cpp."
            }
        }
    }

    func openInstallPage() {
        guard let url = URL(string: "https://ollama.com/download") else { return }
        NSWorkspace.shared.open(url)
    }

    func openModelLibrary() {
        guard let url = URL(string: "https://ollama.com/library") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Internals

    private func query<T: Decodable>(
        _ type: T.Type, tag: String, command: String, settings: ExtractionSettings
    ) async -> T? {
        do {
            return try await BridgeRunner.first(
                type, tag: tag,
                settings: settings,
                scriptName: AppRuntime.engineBridgeScriptName,
                arguments: [command]
            )
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}
