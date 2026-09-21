import Foundation

/// What the app sees at the chosen input, for the line under the input box.
///
/// Only a folder needs explaining. Choosing the folder *above* the artwork is
/// the easy mistake, and it otherwise costs a whole run to discover, so the
/// count is shown before the run rather than after it.
///
/// The counting rules mirror `services/sheets.py`: the top level only, `.png`
/// and `.svg` only, case-insensitive. A count that disagreed with the engine's
/// would be worse than showing nothing, because the user would plan around it.
enum InputSummary {
    /// The formats the engine reads. Kept in step with `SUPPORTED_SUFFIXES`.
    static let supportedSuffixes: Set<String> = ["png", "svg"]

    /// Sheets directly inside `folder`, never descending: an earlier run's
    /// export folder is full of `.svg` files that are not input.
    static func sheetCount(inFolder folder: URL) -> Int {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return 0 }

        return entries.filter { entry in
            guard supportedSuffixes.contains(entry.pathExtension.lowercased()) else { return false }
            let values = try? entry.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true
        }.count
    }

    /// One line describing `path`, or nil when there is nothing to add.
    static func describe(path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // A folder named "drawings.svg" is still a folder: ask the filesystem,
        // never the path's own extension.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return nil }

        let count = sheetCount(inFolder: URL(fileURLWithPath: trimmed))
        guard count > 0 else {
            return "Folder selected, but there are no .png or .svg sheets directly inside it."
        }
        let sheets = count == 1 ? "sheet" : "sheets"
        return "Folder selected: \(count) \(sheets), each extracted into its own subfolder."
    }
}
