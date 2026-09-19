import XCTest
@testable import MacShapearator

final class BackendAvailabilityTests: XCTestCase {
    /// Observed: one refresh reported `ollamaReachable: false` from `models`
    /// and `true` from `setup-status` seconds later, with Ollama answering in
    /// 8 ms throughout. Preferring the first report puts "Ollama is not
    /// running" in front of a user whose Ollama is running; a probe that
    /// timed out is the likely cause, and a timeout can only produce a false
    /// negative. A false positive costs nothing — preflight says so at once.
    func testAPositiveProbeOutweighsANegativeOne() {
        let quiet = BackendAvailability(ollamaReachable: false, llamacppBinary: false)
        let answered = BackendAvailability(ollamaReachable: true, llamacppBinary: true)

        XCTAssertEqual(BackendAvailability.merged(quiet, answered), answered)
        XCTAssertEqual(BackendAvailability.merged(answered, quiet), answered)
    }
}
