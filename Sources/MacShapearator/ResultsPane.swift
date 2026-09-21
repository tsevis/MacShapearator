import SwiftUI
import AppKit

/// The right-hand column: the selected icon, anything the engine warned
/// about, and every extracted item with its naming outcome.
struct ResultsPane: View {
    @ObservedObject var viewModel: ExtractionViewModel

    var body: some View {
        VStack(spacing: 12) {
            previewCard.frame(height: 250)
            warningsCard
            resultsCard.frame(maxHeight: .infinity)
        }
    }

    private var previewCard: some View {
        GroupBox("Preview") {
            VStack(alignment: .leading, spacing: 8) {
                Text(previewMetaText)
                    .font(.headline)
                if let naming = previewNamingText {
                    Text(naming)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                    iconRow(icon)
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.selectedIcon = icon }
                }
            }
            .listStyle(.plain)
            .padding(.top, 4)
        }
    }

    /// True when the run covered several sheets, whose icons all start again
    /// at `icon_001`. Naming the sheet is the only thing that tells two rows
    /// apart; for a single-sheet run it would be noise on every line.
    private var showsSheetNames: Bool {
        Set((viewModel.result?.icons ?? []).compactMap(\.sheetFolder)).count > 1
    }

    /// One result row. The engine reports per-icon naming outcomes; a run
    /// where four of forty icons went unnamed should say which four.
    private func iconRow(_ icon: ExtractedIconRecord) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(showsSheetNames ? "\(icon.sheetFolder ?? "?")/\(icon.stem)" : icon.stem)
                        .font(.headline)
                    if icon.namingDidFail {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help(icon.namingError ?? "This icon could not be named.")
                    }
                }
                Text("\(icon.primaryFormatsText)  |  \(icon.sourceText)  |  \(icon.canvasText)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                if let reason = icon.namingError, icon.namingDidFail {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Engine warnings are informative, not fatal: a banner, never an alert.
    @ViewBuilder
    private var warningsCard: some View {
        if !viewModel.warnings.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.warnings, id: \.self) { warning in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.orange)
                            Text(warning)
                                .font(.caption)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            }
        }
    }

    private var previewMetaText: String {
        guard let icon = viewModel.selectedIcon else { return "No preview yet." }
        return "\(icon.stem)  |  source \(icon.sourceText)  |  canvas \(icon.canvasText)"
    }

    /// What the vision model made of this icon, when one was asked.
    private var previewNamingText: String? {
        guard let icon = viewModel.selectedIcon else { return nil }
        if icon.namingDidFail {
            return icon.namingError.map { "Not named: \($0)" } ?? "Not named."
        }
        guard icon.wasNamed else { return nil }
        var parts: [String] = []
        if let tags = icon.semanticTags, !tags.isEmpty {
            parts.append(tags.joined(separator: ", "))
        }
        if let confidence = icon.semanticConfidence {
            parts.append(String(format: "confidence %.0f%%", confidence * 100))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  |  ")
    }

    private var previewImage: NSImage? {
        guard let url = viewModel.selectedIcon?.previewURL else { return nil }
        return NSImage(contentsOf: url)
    }

}
