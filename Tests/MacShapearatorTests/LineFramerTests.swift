import XCTest
@testable import MacShapearator

/// A pipe hands over whatever the kernel had ready, which is not lines and not
/// even whole characters. Both cases below lose a `RESULT` line in production:
/// the app reports nothing and the user sees an export that never finished.
final class LineFramerTests: XCTestCase {
    private func payload(_ event: BridgeEvent) -> String {
        String(decoding: event.data, as: UTF8.self)
    }

    func testKeepsALineWhoseCharacterIsSplitAcrossChunks() throws {
        let framer = LineFramer()
        let line = Data("RESULT\t{\"stem\":\"καρδιά\"}\n".utf8)
        // Cut inside the multi-byte "ά": neither half decodes as UTF-8 alone.
        let cut = line.count - 5
        let events = framer.consume(line.prefix(cut)) + framer.consume(line.suffix(from: cut))

        XCTAssertEqual(events.count, 1, "the line was dropped at the chunk boundary")
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.tag, "RESULT")
        XCTAssertEqual(payload(event), "{\"stem\":\"καρδιά\"}")
    }

    func testDeliversTheFinalLineWhenTheStreamEndsWithoutANewline() throws {
        let framer = LineFramer()
        XCTAssertTrue(framer.consume(Data("RESULT\t{\"icons\":[]}".utf8)).isEmpty)

        let tail = framer.flush()
        XCTAssertEqual(tail.count, 1, "the last line never reached the app")
        let event = try XCTUnwrap(tail.first)
        XCTAssertEqual(event.tag, "RESULT")
        XCTAssertEqual(payload(event), "{\"icons\":[]}")
    }
}
