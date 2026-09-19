import XCTest
@testable import MacShapearator

final class BridgeRunnerTests: XCTestCase {
    private func event(_ tag: String, _ json: String) -> BridgeEvent {
        BridgeEvent(tag: tag, data: Data(json.utf8))
    }

    /// A bridge that dies before printing anything — a missing dependency in
    /// the bundled interpreter, say — says why on stderr and nowhere else.
    /// Throwing it away leaves the user with "the engine returned no MODELS
    /// response", which names no cause and suggests no fix.
    func testAFailedRunExplainsItselfWithTheEnginesStandardError() {
        let outcome = BridgeOutcome(
            terminationStatus: 1,
            standardError: "ModuleNotFoundError: No module named 'cv2'")

        XCTAssertThrowsError(
            try BridgeRunner.firstEvent(ModelsRecord.self, tag: "MODELS", in: [], outcome: outcome)
        ) { error in
            let message = (error as? BridgeFailure)?.errorDescription ?? "\(error)"
            XCTAssertTrue(message.contains("No module named 'cv2'"), message)
        }
    }
}
