import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var ollamaRuntime = OllamaRuntimeViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("Extractor Runtime") {
                    VStack(spacing: 10) {
                        textRow(title: "Backend Root", text: binding(\.backendRoot))
                        textRow(title: "Python Path", text: binding(\.pythonPath))
                    }
                    .padding(.top, 4)
                }
                GroupBox("Model Provider") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Provider", selection: binding(\.provider)) {
                            Text("Geometry Only").tag("geometry")
                            Text("Ollama Local").tag("ollama")
                            Text("Model Directory").tag("directory")
                        }
                        .pickerStyle(.segmented)
                        textRow(title: "Ollama URL", text: binding(\.ollamaURL))
                        textRow(title: "Ollama Model", text: binding(\.ollamaModel))
                        textRow(title: "Model Directory", text: binding(\.localModelRoot))
                        textRow(title: "Directory Model", text: binding(\.localModelName))
                        Toggle("Use selected model for semantic naming and metadata when supported", isOn: bindingBool(\.semanticNaming))
                    }
                    .padding(.top, 4)
                }
                GroupBox("Ollama Runtime") {
                    VStack(alignment: .leading, spacing: 10) {
                        statusRow("Installed", value: ollamaRuntime.status.isInstalled ? "Yes" : "No")
                        statusRow("Server Reachable", value: ollamaRuntime.status.isServerReachable ? "Yes" : "No")
                        statusRow("Recommended Model", value: ollamaRuntime.status.recommendedModel)
                        statusRow("Model Available", value: ollamaRuntime.status.hasRecommendedModel ? "Yes" : "No")
                        if let path = ollamaRuntime.status.binaryPath {
                            statusRow("Binary", value: path)
                        }
                        Text(ollamaRuntime.status.statusMessage)
                            .foregroundStyle(.secondary)
                        if !ollamaRuntime.status.isInstalled {
                            Text("Install Ollama locally, then return here and refresh. The app uses a local server only and never calls a cloud endpoint.")
                                .foregroundStyle(.secondary)
                        } else if !ollamaRuntime.status.isServerReachable {
                            Text(ollamaRuntime.status.startGuidance)
                                .foregroundStyle(.secondary)
                        } else if !ollamaRuntime.status.hasRecommendedModel {
                            Text("Download \(ollamaRuntime.status.recommendedModel) to enable the app's recommended local semantic naming workflow.")
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 10) {
                            Button(ollamaRuntime.isRefreshing ? "Refreshing..." : "Refresh Status") {
                                ollamaRuntime.refresh(using: settingsStore.settings)
                            }
                            .disabled(ollamaRuntime.isRefreshing)
                            Button("Install Ollama") {
                                ollamaRuntime.openInstallPage()
                            }
                            Button(ollamaRuntime.isDownloadingModel ? "Downloading Model..." : "Download Recommended Model") {
                                ollamaRuntime.downloadRecommendedModel(using: settingsStore.settings)
                            }
                            .disabled(!ollamaRuntime.status.isInstalled || !ollamaRuntime.status.isServerReachable || ollamaRuntime.isDownloadingModel)
                            Button("Open Model Library") {
                                ollamaRuntime.openModelLibrary()
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                Text("This native app currently uses the existing local Shapearator extraction engine behind the scenes, so it is functional immediately while we continue the full Swift migration.")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .task {
            ollamaRuntime.refresh(using: settingsStore.settings)
        }
    }

    private func textRow(title: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 110, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func statusRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
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
