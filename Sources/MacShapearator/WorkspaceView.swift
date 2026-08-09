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
        VStack(spacing: 12) {
            previewCard.frame(height: 250)
            resultsCard.frame(maxHeight: .infinity)
        }
        .frame(width: 500)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var sourceCard: some View {
        GroupBox("Source") {
            VStack(spacing: 8) {
                fileRow(title: "Input Sheet", text: binding(\.lastInputPath), canChooseDirectory: false)
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
                            ForEach(detectionPresets.map(\.0), id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedPreset) { value in
                            applyPreset(value)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Text("Use Padding to breathe around each icon. Use Min Area to suppress dust. Use Merge to reconnect multi-stroke marks.")
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
                Button(action: runExtraction) {
                    Text("Extract Icons")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

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

    private var previewCard: some View {
        GroupBox("Preview") {
            VStack(alignment: .leading, spacing: 8) {
                Text(previewMetaText)
                    .font(.headline)
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.gray.opacity(0.18))
                    if let image = previewImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(18)
                    } else {
                        Text("No preview yet.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 4)
        }
    }

    private var resultsCard: some View {
        GroupBox("Extracted Items") {
            List(selection: Binding(
                get: { viewModel.selectedIcon?.id },
                set: { newValue in
                    viewModel.selectedIcon = viewModel.result?.icons.first(where: { $0.id == newValue })
                }
            )) {
                ForEach(viewModel.result?.icons ?? []) { icon in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(icon.stem)
                                .font(.headline)
                            Text("\(icon.primaryFormatsText)  |  \(icon.sourceText)  |  \(icon.canvasText)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.selectedIcon = icon }
                }
            }
            .listStyle(.plain)
            .padding(.top, 4)
        }
    }

    private var previewMetaText: String {
        guard let icon = viewModel.selectedIcon else { return "No preview yet." }
        return "\(icon.stem)  |  source \(icon.sourceText)  |  canvas \(icon.canvasText)"
    }

    private var previewImage: NSImage? {
        guard let url = viewModel.selectedIcon?.previewURL else { return nil }
        return NSImage(contentsOf: url)
    }

    private var providerSummary: String {
        let settings = settingsStore.settings
        switch settings.provider {
        case "ollama":
            return "Active provider: Ollama local (\(settings.ollamaModel))"
        case "directory":
            return "Active provider: Local directory (\(settings.localModelName.isEmpty ? "directory catalog" : settings.localModelName))"
        default:
            return "Active provider: Geometry-only local extraction"
        }
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
        return "Balanced"
    }

    private func applyPreset(_ name: String) {
        guard let preset = detectionPresets.first(where: { $0.0 == name })?.1 else { return }
        settingsStore.settings.padding = preset.0
        settingsStore.settings.minArea = preset.1
        settingsStore.settings.mergeGap = preset.2
    }
}
