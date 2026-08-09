import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var runtime = ModelRuntimeViewModel()

    private var provider: String { settingsStore.settings.provider }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                providerCard
                if provider == "ollama" { ollamaCard }
                if provider == "llamacpp" { llamacppCard }
                if provider == "directory" { directoryCard }
                if provider != "geometry" { readinessCard }
                setupCard
                advancedCard
            }
            .padding(.top, 4)
        }
        .task { runtime.refresh(using: settingsStore.settings) }
        // Single-argument form: the deployment target is macOS 13.
        .onChange(of: provider) { _ in
            Task { await runtime.refreshPreflight(using: settingsStore.settings) }
        }
    }

    // MARK: - Provider

    private var providerCard: some View {
        GroupBox("Model Provider") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Provider", selection: binding(\.provider)) {
                    Text("Geometry Only").tag("geometry")
                    Text("Ollama").tag("ollama")
                    Text("llama.cpp").tag("llamacpp")
                    Text("Model Directory").tag("directory")
                }
                .pickerStyle(.segmented)

                if provider == "geometry" {
                    Text("Icons are detected and exported with generic filenames. "
                         + "Choose a model provider to name them automatically.")
                        .foregroundStyle(.secondary)
                } else {
                    Toggle("Name icons with the selected model",
                           isOn: bindingBool(\.semanticNaming))
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Backends

    private var ollamaCard: some View {
        GroupBox("Ollama") {
            VStack(alignment: .leading, spacing: 10) {
                textRow(title: "Server URL", text: binding(\.ollamaURL))
                modelPicker(
                    title: "Model",
                    selection: binding(\.ollamaModel),
                    options: runtime.availableModels(for: "ollama"),
                    emptyHint: "No vision models found. Download one below."
                )
                if runtime.backends?.ollamaReachable == false {
                    HStack(spacing: 10) {
                        Text("Ollama is not running.").foregroundStyle(.secondary)
                        Button("Install Ollama") { runtime.openInstallPage() }
                        Button("Model Library") { runtime.openModelLibrary() }
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var llamacppCard: some View {
        GroupBox("llama.cpp") {
            VStack(alignment: .leading, spacing: 10) {
                textRow(title: "Server URL", text: binding(\.llamacppURL))
                modelPicker(
                    title: "Loaded Model",
                    selection: binding(\.llamacppModel),
                    options: runtime.availableModels(for: "llamacpp"),
                    emptyHint: "No server running. Start one below, or launch llama-server yourself."
                )
                textRow(title: "Weights Folder", text: binding(\.modelsRoot))

                if !runtime.startableLlamaModels.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Downloaded models you can start:").foregroundStyle(.secondary)
                        ForEach(runtime.startableLlamaModels) { model in
                            HStack {
                                Text(model.displayName)
                                Text(model.source).foregroundStyle(.secondary).font(.caption)
                                Spacer()
                                Button("Start Server") {
                                    runtime.startLlamaServer(model: model.displayName,
                                                             settings: settingsStore.settings)
                                }
                                .disabled(runtime.isInstalling)
                            }
                        }
                    }
                } else if runtime.backends?.llamacppBinary == false {
                    Text("llama-server was not found on this Mac. Install llama.cpp to use this backend.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    private var directoryCard: some View {
        GroupBox("Model Directory") {
            VStack(alignment: .leading, spacing: 10) {
                textRow(title: "Folder", text: binding(\.localModelRoot))
                modelPicker(
                    title: "Model",
                    selection: binding(\.localModelName),
                    options: runtime.availableModels(for: "directory"),
                    emptyHint: "No models found in this folder."
                )
                Text("Directory mode is a local catalog. Semantic naming needs Ollama or llama.cpp.")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Readiness

    /// The engine's own verdict, not a second implementation of it.
    private var readinessCard: some View {
        GroupBox("Readiness") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: readinessIcon)
                        .foregroundStyle(readinessColor)
                    Text(runtime.preflight?.message ?? runtime.statusMessage)
                        .textSelection(.enabled)
                    Spacer()
                }
                if let error = runtime.lastError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
                Button(runtime.isRefreshing ? "Checking…" : "Check Again") {
                    runtime.refresh(using: settingsStore.settings)
                }
                .disabled(runtime.isRefreshing || runtime.isInstalling)
            }
            .padding(.top, 4)
        }
    }

    private var readinessIcon: String {
        guard let preflight = runtime.preflight else { return "questionmark.circle" }
        return preflight.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var readinessColor: Color {
        guard let preflight = runtime.preflight else { return .secondary }
        return preflight.ok ? .green : .orange
    }

    // MARK: - Setup

    private var setupCard: some View {
        GroupBox("Vision Models") {
            VStack(alignment: .leading, spacing: 10) {
                if let candidates = runtime.setup?.candidates, !candidates.isEmpty {
                    ForEach(candidates) { candidate in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.label)
                                if !candidate.recommendation.isEmpty {
                                    Text(candidate.recommendation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if candidate.installed {
                                Text("Installed").foregroundStyle(.secondary).font(.caption)
                            } else if runtime.installingKey == candidate.id {
                                ProgressView(value: runtime.installProgress).frame(width: 90)
                            } else {
                                Button("Download") { install(candidate) }
                                    .disabled(runtime.isInstalling)
                            }
                        }
                    }
                } else {
                    Text("No backend is available. Install Ollama, or llama.cpp, to download a vision model.")
                        .foregroundStyle(.secondary)
                }
                if runtime.isInstalling {
                    Text(runtime.statusMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    private func install(_ candidate: SetupCandidateRecord) {
        runtime.install(candidate: candidate, settings: settingsStore.settings) { installed in
            // Point the app at what was just downloaded, as the engine advises.
            settingsStore.settings.provider = installed.provider
            settingsStore.settings.semanticNaming = installed.semanticNaming
            if !installed.ollamaModel.isEmpty { settingsStore.settings.ollamaModel = installed.ollamaModel }
            if !installed.llamacppModel.isEmpty { settingsStore.settings.llamacppModel = installed.llamacppModel }
        }
    }

    // MARK: - Advanced

    private var advancedCard: some View {
        GroupBox("Advanced") {
            VStack(alignment: .leading, spacing: 10) {
                textRow(title: "Engine Root", text: binding(\.backendRoot))
                textRow(title: "Python Path", text: binding(\.pythonPath))
                Text("Leave these empty to use the versions bundled with the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Building blocks

    private func modelPicker(
        title: String,
        selection: Binding<String>,
        options: [ModelDescriptorRecord],
        emptyHint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if options.isEmpty {
                textRow(title: title, text: selection)
                Text(emptyHint).font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Text(title).frame(width: 110, alignment: .leading)
                    Picker("", selection: selection) {
                        // Keep a saved-but-missing model selectable rather than
                        // silently switching the user to something else.
                        if !options.contains(where: { $0.name == selection.wrappedValue }) {
                            Text(selection.wrappedValue.isEmpty ? "None" : selection.wrappedValue)
                                .tag(selection.wrappedValue)
                        }
                        ForEach(options) { model in
                            Text(model.recommendation.isEmpty
                                 ? model.name
                                 : "\(model.name) — \(model.recommendation)")
                                .tag(model.name)
                        }
                    }
                    .labelsHidden()
                }
            }
        }
    }

    private func textRow(title: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 110, alignment: .leading)
            TextField("", text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<ExtractionSettings, String>) -> Binding<String> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { settingsStore.settings[keyPath: keyPath] = $0 }
        )
    }

    private func bindingBool(_ keyPath: WritableKeyPath<ExtractionSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { settingsStore.settings[keyPath: keyPath] = $0 }
        )
    }
}
