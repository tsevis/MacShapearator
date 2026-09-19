import Foundation

/// How a bridge process ended.
struct BridgeOutcome: Equatable, Sendable {
    let terminationStatus: Int32
    /// Everything the process wrote to stderr — a Python traceback, an OpenCV
    /// warning, a dynamic-linker error. Worth showing only when the bridge
    /// died without reporting an `ERROR` line of its own.
    let standardError: String

    var succeeded: Bool { terminationStatus == 0 }
}

/// A value written on one queue and read on another. The queue discipline
/// around it is real but invisible to the compiler; this makes it checkable.
private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

/// One running bridge process: its events, its exit, and a way to stop it.
///
/// Events arrive through an `AsyncStream`, so the consumer sees them in order
/// on its own actor rather than racing hops out of a pipe callback.
///
/// Both pipes are drained concurrently. Reading stderr only after the process
/// exits deadlocks as soon as the child writes more than a pipe buffer —
/// 64 KB, which a model download's progress output passes in seconds.
///
/// `@unchecked Sendable`: every stored property is a `let`, the two mutable
/// values cross threads inside `LockedBox`, and `Process` is touched from
/// elsewhere only by `cancel()`, whose `isRunning` and `terminate()` are
/// documented as safe to call while the process runs.
final class BridgeSession: @unchecked Sendable {
    private let task: Process
    private let group = DispatchGroup()
    private let result = LockedBox<BridgeOutcome?>(nil)

    /// Every `TAG\t{json}` line the process wrote, in order. The stream
    /// finishes when the process closes stdout.
    let events: AsyncStream<BridgeEvent>

    /// - Parameter removingOnExit: a temporary file to delete once the process
    ///   has finished with it, so no caller has to outlive the run to clean up.
    init(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        removingOnExit temporaryFile: URL? = nil
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
        let emit = eventYield!

        do {
            try process.run()
        } catch {
            emit.finish()
            if let temporaryFile { try? FileManager.default.removeItem(at: temporaryFile) }
            throw BridgeFailure.launchFailed("Could not start the engine: \(error.localizedDescription)")
        }
        task = process

        let errorText = LockedBox("")
        let errorQueue = DispatchQueue(label: "MacShapearator.bridge.stderr")
        errorQueue.async {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            errorText.set(String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines))
        }

        group.enter()
        DispatchQueue(label: "MacShapearator.bridge.stdout").async { [group, result] in
            let framer = LineFramer()
            let handle = stdout.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                for event in framer.consume(chunk) { emit.yield(event) }
            }
            for event in framer.flush() { emit.yield(event) }
            emit.finish()

            process.waitUntilExit()
            errorQueue.sync {}  // the stderr reader has reached end of file
            if let temporaryFile { try? FileManager.default.removeItem(at: temporaryFile) }
            result.set(BridgeOutcome(
                terminationStatus: process.terminationStatus,
                standardError: errorText.get()))
            group.leave()
        }
    }

    /// Wait for the process to exit. Drain `events` first, or the process may
    /// still be blocked writing to a full stdout pipe.
    func waitForExit() async -> BridgeOutcome {
        await withCheckedContinuation { continuation in
            group.notify(queue: .global(qos: .utility)) { [result] in
                continuation.resume(returning: result.get()
                    ?? BridgeOutcome(terminationStatus: -1, standardError: ""))
            }
        }
    }

    /// Stop the process. `waitForExit` then reports a non-zero status.
    func cancel() {
        guard task.isRunning else { return }
        task.terminate()
    }
}
