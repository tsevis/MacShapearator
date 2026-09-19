import XCTest
@testable import MacShapearator

/// Process plumbing, against a real child process.
///
/// Each case below is a way the app has to lose the engine's answer: a pipe
/// that fills and stops the child, a result written without a trailing
/// newline, and a run the user asked to stop.
final class BridgeSessionTests: XCTestCase {
    private let shell = URL(fileURLWithPath: "/bin/sh")

    private func session(_ script: String) throws -> BridgeSession {
        try BridgeSession(executable: shell, arguments: ["-c", script])
    }

    private func collect(_ session: BridgeSession) async -> [BridgeEvent] {
        var events: [BridgeEvent] = []
        for await event in session.events { events.append(event) }
        return events
    }

    /// stderr is a 64 KB pipe. A child that fills it blocks in `write` and
    /// never finishes, so reading stderr only after the process exits is a
    /// deadlock — reached in practice by a model download's progress output.
    func testDoesNotStallWhenTheProcessFloodsStandardError() async throws {
        let script = """
        printf 'PROGRESS\\t{"phase":"download"}\\n'
        awk 'BEGIN { while (i++ < 4000) print "downloading a model, chunk " i }' >&2
        printf 'RESULT\\t{"icons":[]}\\n'
        """
        let session = try session(script)
        let events = await collect(session)
        let outcome = await session.waitForExit()

        XCTAssertEqual(events.map(\.tag), ["PROGRESS", "RESULT"])
        XCTAssertTrue(outcome.succeeded, "status \(outcome.terminationStatus)")
        XCTAssertGreaterThan(outcome.standardError.count, 64 * 1024)
    }

    func testDeliversAResultWrittenWithoutATrailingNewline() async throws {
        let session = try session(#"printf 'RESULT\t{"icons":[]}'"#)
        let events = await collect(session)

        XCTAssertEqual(events.map(\.tag), ["RESULT"])
    }

    func testCancelStopsTheProcess() async throws {
        // `exec` so the signal reaches the sleep itself, as it reaches the
        // Python bridge in the app rather than an intervening shell.
        let session = try session("printf 'PROGRESS\\t{}\\n'; exec sleep 30")
        let started = Date()
        var seen = 0
        for await _ in session.events {
            seen += 1
            session.cancel()
        }
        let outcome = await session.waitForExit()

        XCTAssertEqual(seen, 1)
        XCTAssertFalse(outcome.succeeded, "a cancelled run must not report success")
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "cancel did not stop the run")
    }
}
