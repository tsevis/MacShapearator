import XCTest
@testable import MacShapearator

/// Icons from a folder run must stay distinguishable.
///
/// Every sheet numbers its icons from one, so a five-sheet run holds five
/// icons called `icon_001` with `index == 1`. The results list is a SwiftUI
/// `ForEach` over `Identifiable`, and `List(selection:)` resolves a click by
/// searching for the first record with a matching id — so an id that repeats
/// drops rows and selects the wrong icon's preview.
final class IconIdentityTests: XCTestCase {
    private func icon(index: Int, stem: String, svg: String) -> ExtractedIconRecord {
        ExtractedIconRecord(
            index: index, stem: stem, outputs: ["svg": svg], previewPath: nil,
            canvasSize: [512, 512], sourceSize: [10, 10], sourceBounds: [0, 0, 10, 10],
            metadataPath: nil, namingStatus: nil, namingError: nil,
            semanticTags: nil, semanticConfidence: nil)
    }

    func testTwoSheetsFirstIconsAreNotTheSameRow() {
        let first = icon(index: 1, stem: "icon_001", svg: "/out/Many1/svg/icon_001.svg")
        let second = icon(index: 1, stem: "icon_001", svg: "/out/Many2/svg/icon_001.svg")
        XCTAssertNotEqual(first.id, second.id)
    }

    func testSelectingByIdFindsTheIconThatWasClicked() {
        let icons = [
            icon(index: 1, stem: "icon_001", svg: "/out/Many1/svg/icon_001.svg"),
            icon(index: 1, stem: "icon_001", svg: "/out/Many2/svg/icon_001.svg"),
        ]
        let picked = icons.first { $0.id == icons[1].id }
        XCTAssertEqual(picked?.outputs["svg"], "/out/Many2/svg/icon_001.svg")
    }

    func testAnIconKnowsWhichSheetItCameFrom() {
        let one = icon(index: 1, stem: "icon_001", svg: "/out/Many3/svg/icon_001.svg")
        XCTAssertEqual(one.sheetFolder, "Many3")
    }

    func testAnIconWithNoOutputsStillHasAnId() {
        let bare = ExtractedIconRecord(
            index: 7, stem: "icon_007", outputs: [:], previewPath: nil,
            canvasSize: [512, 512], sourceSize: [10, 10], sourceBounds: [0, 0, 10, 10],
            metadataPath: nil, namingStatus: nil, namingError: nil,
            semanticTags: nil, semanticConfidence: nil)
        XCTAssertFalse(bare.id.isEmpty)
    }
}
