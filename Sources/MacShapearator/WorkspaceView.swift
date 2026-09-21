import SwiftUI
import AppKit

private let canvasModeLabels: [(String, String)] = [
    ("original", "A. Keep every icon at its original isolated size on the common canvas."),
    ("uniform_to_largest", "B. Scale the largest icon to fit the canvas, then apply that same scale to all icons."),
    ("individual_fit", "C. Scale each icon individually to fit the canvas while keeping proportions."),
]

private let bitmapModeLabels: [(String, String)] = [
    ("keep_background", "A. Keep the original background color across the bitmap canvas."),
    ("transparent_preserve_interior", "B. Export transparent bitmaps while preserving enclosed white details."),
]

/// Mirrors SVG_SPLIT_MODES in the engine's settings schema.
private let svgSplitLabels: [(String, String)] = [
    ("auto", "Auto"),
    ("shape", "Every shape"),
    ("cluster", "Group by touch"),
]

private let svgSplitHints: [String: String] = [
    "auto": "Groups in the artwork become icons; loose shapes are clustered by pixels.",
    "shape": "Every path, polygon or group is its own file. Use this for mosaics and tessellations, whose tiles touch.",
    "cluster": "Shapes that touch become one icon, even where the artwork groups them otherwise.",
]

private let customPresetName = "Custom"

private let detectionPresets: [(String, (Int, Int, Int))] = [
    ("Balanced", (12, 200, 13)),
    ("Tiny Details", (8, 70, 9)),
    ("Loose Sketches", (16, 140, 19)),
    ("Bold Shapes", (14, 320, 15)),
]

struct WorkspaceView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @ObservedObject var viewModel: ExtractionViewModel

    @State private var exportPNG = true
    @State private var exportJPG = false
    @State private var exportTIFF = false
    @State private var exportSVG = true
    @State private var selectedPreset = "Balanced"

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            leftColumn
            rightColumn
        }
        .onAppear {
            syncFormatState()
            selectedPreset = detectedPresetName()
        }
        // The vision backend is unreachable. Offer the same choice the CLI's
        // --allow-unnamed gives, rather than just reporting a failure.
        .alert(
            "Model Not Ready",
            isPresented: Binding(
                get: { viewModel.pendingUnnamedPrompt != nil },
                set: { if !$0 { viewModel.dismissUnnamedPrompt() } }
            ),
            presenting: viewModel.pendingUnnamedPrompt
        ) { _ in
            Button("Cancel", role: .cancel) { viewModel.dismissUnnamedPrompt() }
            Button("Export With Generic Names") { viewModel.retryAllowingUnnamed() }
        } message: { failure in
            Text("\(failure.message)\n\nExport anyway with generic filenames "
                 + "(icon_001, icon_002, ...)? The metadata will record that no model named these icons.")
        }
    }

    private var leftColumn: some View {
        VStack(spacing: 12) {
            sourceCard
            detectionCard
            outputCard
            runCard
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var rightColumn: some View {
        ResultsPane(viewModel: viewModel)
            .frame(width: 500)
            .frame(maxHeight: .infinity, alignment: .top)
    }

    private var sourceCard: some View {
        GroupBox("Source") {
            VStack(spacing: 8) {
                inputRow
                fileRow(title: "Output Folder", text: binding(\.lastOutputDir), canChooseDirectory: true)
                Text(providerSummary)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                Text("Tip: SVG input preserves vector cleanliness best. PNG input works beautifully when the shapes are clearly separated.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 4)
        }
    }

    private var detectionCard: some View {
        GroupBox("Detection") {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    smallNumberField(title: "Padding", value: bindingInt(\.padding))
                    smallNumberField(title: "Min Area", value: bindingInt(\.minArea))
                    smallNumberField(title: "Merge", value: bindingInt(\.mergeGap))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preset")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Preset", selection: $selectedPreset) {
                            // Hand-tuned values are not one of the presets;
                            // showing "Balanced" for them is simply untrue.
                            if selectedPreset == customPresetName {
                                Text(customPresetName).tag(customPresetName)
                            }
                            ForEach(detectionPresets.map(\.0), id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedPreset) { _, value in
                            applyPreset(value)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Split (SVG)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Split", selection: binding(\.svgSplit)) {
                            ForEach(svgSplitLabels, id: \.0) { key, label in
                                Text(label).tag(key)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    Spacer(minLength: 0)
                }
                Text("Use Padding to breathe around each icon. Use Min Area to suppress dust. Use Merge to reconnect multi-stroke marks.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(svgSplitHints[settingsStore.settings.svgSplit] ?? "")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 4)
        }
    }

    private var outputCard: some View {
        GroupBox("Output Studio") {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 10) {
                    GroupBox("Formats") {
                        HStack(spacing: 14) {
                            Toggle("PNG", isOn: $exportPNG)
                            Toggle("JPG", isOn: $exportJPG)
                            Toggle("TIFF", isOn: $exportTIFF)
                            Toggle("SVG", isOn: $exportSVG)
                        }
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("Common Output Canvas") {
                        VStack(spacing: 8) {
                            smallNumberField(title: "Width (px)", value: bindingInt(\.outputWidth))
                            smallNumberField(title: "Height (px)", value: bindingInt(\.outputHeight))
                            Text("These dimensions define the final canvas for every bitmap export and the width and height of SVG exports.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    GroupBox("Bitmap Export") {
                        Picker("Bitmap Export", selection: binding(\.bitmapExportMode)) {
                            ForEach(bitmapModeLabels, id: \.0) { key, label in
                                Text(label).tag(key)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 10) {
                    GroupBox("Canvas Behavior") {
                        Picker("Canvas Behavior", selection: binding(\.canvasMode)) {
                            ForEach(canvasModeLabels, id: \.0) { key, label in
                                Text(label).tag(key)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 4)
        }
    }

    private var runCard: some View {
        GroupBox("Run") {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button(action: runExtraction) {
                        Text(viewModel.isRunning ? "Extracting…" : "Extract Icons")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    // A second run would write the same output folder as the
                    // first, from a second engine process.
                    .disabled(viewModel.isRunning)

                    if viewModel.isRunning {
                        Button("Stop") { viewModel.cancel() }
                            .controlSize(.large)
                    }
                }

                Text(statusLine)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(viewModel.progressMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ProgressView(value: viewModel.progress)
                    .progressViewStyle(.linear)
            }
            .padding(.top, 4)
        }
    }

    private var providerSummary: String {
        ProviderSummary.text(for: settingsStore.settings)
    }

    private var statusLine: String {
        switch viewModel.state {
        case .idle:
            return "Choose a sheet, confirm your output canvas, then extract."
        case .running:
            return "Extraction running..."
        case .success(let summary):
            return summary
        case .failed(let message):
            return message
        }
    }

    private func runExtraction() {
        settingsStore.settings.defaultFormats = selectedFormats.sorted()
        viewModel.runExtraction(settingsStore: settingsStore, formats: selectedFormats)
    }

    private var selectedFormats: Set<String> {
        var formats = Set<String>()
        if exportPNG { formats.insert("png") }
        if exportJPG { formats.insert("jpg") }
        if exportTIFF { formats.insert("tiff") }
        if exportSVG { formats.insert("svg") }
        return formats.isEmpty ? ["png"] : formats
    }

    /// Input takes either one sheet or a folder of them, so it gets two
    /// buttons rather than the single Browse the output row needs.
    private var inputRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("Input")
                    .frame(width: 96, alignment: .leading)
                TextField("", text: binding(\.lastInputPath))
                    .textFieldStyle(.roundedBorder)
                Button("Sheet") {
                    choosePath(for: binding(\.lastInputPath), canChooseDirectory: false)
                }
                Button("Folder") {
                    chooseInputFolder()
                }
            }
            if let summary = InputSummary.describe(path: settingsStore.settings.lastInputPath) {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 106)
            }
        }
    }

    /// A folder of sheets: every one inside is extracted in a single run, each
    /// into its own subfolder of the output folder.
    private func chooseInputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.message = "Select a folder of sheets. Every .png and .svg directly inside it is extracted."
        let current = settingsStore.settings.lastInputPath
        if !current.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: current)
        }
        if panel.runModal() == .OK, let chosen = panel.url?.path {
            settingsStore.settings.lastInputPath = chosen
        }
    }

    private func fileRow(title: String, text: Binding<String>, canChooseDirectory: Bool) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 96, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
            Button("Browse") {
                choosePath(for: text, canChooseDirectory: canChooseDirectory)
            }
        }
    }

    private func smallNumberField(title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, value: value, formatter: integerFormatter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 96)
        }
    }

    private var integerFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        return formatter
    }

    private func choosePath(for binding: Binding<String>, canChooseDirectory: Bool) {
        if canChooseDirectory {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Choose Output Folder"
            panel.message = "Select an output folder, or create a new one here."
            if !binding.wrappedValue.isEmpty {
                panel.directoryURL = URL(fileURLWithPath: binding.wrappedValue)
            }
            if panel.runModal() == .OK {
                binding.wrappedValue = panel.url?.path ?? binding.wrappedValue
            }
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .svg]
        if !binding.wrappedValue.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: binding.wrappedValue).deletingLastPathComponent()
        }
        if panel.runModal() == .OK {
            binding.wrappedValue = panel.url?.path ?? binding.wrappedValue
        }
    }

    private func binding(_ keyPath: WritableKeyPath<ExtractionSettings, String>) -> Binding<String> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { settingsStore.settings[keyPath: keyPath] = $0 }
        )
    }

    private func bindingInt(_ keyPath: WritableKeyPath<ExtractionSettings, Int>) -> Binding<Int> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: {
                settingsStore.settings[keyPath: keyPath] = max(0, $0)
                selectedPreset = detectedPresetName()
            }
        )
    }

    private func syncFormatState() {
        let formats = Set(settingsStore.settings.defaultFormats)
        exportPNG = formats.contains("png")
        exportJPG = formats.contains("jpg")
        exportTIFF = formats.contains("tiff")
        exportSVG = formats.contains("svg")
    }

    private func detectedPresetName() -> String {
        let settings = settingsStore.settings
        for (name, values) in detectionPresets where values.0 == settings.padding && values.1 == settings.minArea && values.2 == settings.mergeGap {
            return name
        }
        return customPresetName
    }

    private func applyPreset(_ name: String) {
        guard let preset = detectionPresets.first(where: { $0.0 == name })?.1 else { return }
        settingsStore.settings.padding = preset.0
        settingsStore.settings.minArea = preset.1
        settingsStore.settings.mergeGap = preset.2
    }
}
