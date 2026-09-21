import XCTest
@testable import MacShapearator

/// The line under the input box when a folder is chosen.
///
/// Choosing the folder *above* the artwork is the easy mistake, and without
/// this line it costs a whole run to discover. A count that disagreed with
/// what the engine will actually extract would be worse than no line at all,
/// so these pin the counting rules against the engine's: top level only,
/// `.png` and `.svg` only, case-insensitive.
final class InputSummaryTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("InputSummaryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(_ names: [String]) throws {
        for name in names {
            try "x".write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }

    func testASheetNeedsNoExplanation() throws {
        try write(["one.svg"])
        XCTAssertNil(InputSummary.describe(path: folder.appendingPathComponent("one.svg").path))
    }

    func testAFolderReportsHowManySheetsItWillExtract() throws {
        try write(["Many1.svg", "Many2.svg", "Many3.png", "notes.txt", ".DS_Store"])
        let text = try XCTUnwrap(InputSummary.describe(path: folder.path))
        XCTAssertTrue(text.contains("3 sheets"), text)
    }

    func testASubfolderOfAPreviousExportIsNotCounted() throws {
        try write(["Many1.svg"])
        let previous = folder.appendingPathComponent("previous_export")
        try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: true)
        try "x".write(to: previous.appendingPathComponent("icon_001.svg"),
                      atomically: true, encoding: .utf8)
        let text = try XCTUnwrap(InputSummary.describe(path: folder.path))
        XCTAssertTrue(text.contains("1 sheet"), text)
        XCTAssertFalse(text.contains("2"), text)
    }

    func testOneSheetIsNotDescribedAsOneSheets() throws {
        try write(["only.SVG"])
        let text = try XCTUnwrap(InputSummary.describe(path: folder.path))
        XCTAssertTrue(text.contains("1 sheet"), text)
        XCTAssertFalse(text.contains("1 sheets"), text)
    }

    func testAnEmptyFolderReadsAsAMistakeNotACountOfZero() throws {
        try write(["notes.txt"])
        let text = try XCTUnwrap(InputSummary.describe(path: folder.path))
        XCTAssertFalse(text.contains("0"), text)
        XCTAssertTrue(text.lowercased().contains("no "), text)
    }

    func testAFolderIsNotJudgedByItsOwnName() throws {
        // A folder called "drawings.svg" is still a folder.
        let named = folder.appendingPathComponent("drawings.svg")
        try FileManager.default.createDirectory(at: named, withIntermediateDirectories: true)
        XCTAssertNotNil(InputSummary.describe(path: named.path))
    }
}
