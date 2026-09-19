import Foundation

/// How a bridge process ended.
struct BridgeOutcome: Equatable {
    let terminationStatus: Int32
    /// Everything the process wrote to stderr — a Python traceback, an OpenCV
    /// warning, a dynamic-linker error. Worth showing only when the bridge
    /// died without reporting an `ERROR` line of its own.
    let standardError: String

    var succeeded: Bool { terminationStatus == 0 }
}

/// One running bridge process: its events, its exit, and a way to stop it.
///
/// Events arrive through an `AsyncStream`, so the consumer sees them in order
/// on its own actor rather than racing hops out of a pipe callback.
///
/// Both pipes are drained concurrently. Reading stderr only after the process
/// exits deadlocks as soon as the child writes more than a pipe buffer —
/// 64 KB, which a model download's progress output passes in seconds.
final class BridgeSession {
    private let task: Process
    private let outcomes: AsyncStream<BridgeOutcome>
    private var finished: BridgeOutcome?

    /// Every `TAG\t{json}` line the process wrote, in order. The stream
    /// finishes when the process closes stdout.
    let events: AsyncStream<BridgeEvent>

    init(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        var eventYield: AsyncStream<BridgeEvent>.Continuation!
        events = AsyncStream { eventYield = $0 }
        var outcomeYield: AsyncStream<BridgeOutcome>.Continuation!
        outcomes = AsyncStream { outcomeYield = $0 }
        let emitEvent = eventYield!
        let emitOutcome = outcomeYield!

        do {
            try process.run()
        } catch {
            emitEvent.finish()
            emitOutcome.finish()
            throw BridgeFailure.launchFailed("Could not start the engine: \(error.localizedDescription)")
        }
        task = process

        let errorQueue = DispatchQueue(label: "MacShapearator.bridge.stderr")
        var errorData = Data()
        errorQueue.async { errorData = stderr.fileHandleForReading.readDataToEndOfFile() }

        DispatchQueue(label: "MacShapearator.bridge.stdout").async {
            let framer = LineFramer()
            let handle = stdout.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                for event in framer.consume(chunk) { emitEvent.yield(event) }
            }
            for event in framer.flush() { emitEvent.yield(event) }
            emitEvent.finish()

            process.waitUntilExit()
            errorQueue.sync {}  // the stderr reader has reached end of file
            emitOutcome.yield(BridgeOutcome(
                terminationStatus: process.terminationStatus,
                standardError: String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)))
            emitOutcome.finish()
        }
    }

    /// Wait for the process to exit. Drain `events` first, or the process may
    /// still be blocked writing to a full stdout pipe.
    func waitForExit() async -> BridgeOutcome {
        if let finished { return finished }
        for await outcome in outcomes {
            finished = outcome
            return outcome
        }
        return finished ?? BridgeOutcome(terminationStatus: -1, standardError: "")
    }

    /// Stop the process. `waitForExit` then reports a non-zero status.
    func cancel() {
        guard task.isRunning else { return }
        task.terminate()
    }
}
