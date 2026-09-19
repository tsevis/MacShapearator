import Foundation

/// Reassembles `TAG\t{json}` lines from the arbitrary chunks a pipe delivers.
///
/// A read boundary falls wherever the kernel happens to put it: mid-line, and
/// mid-character. Framing is therefore incremental and works on bytes —
/// decoding each chunk as text first drops any character the boundary split,
/// and with it the whole line, which for a `RESULT` means an export that
/// finished but was never shown.
final class LineFramer {
    private var buffer = Data()

    /// Feed one chunk read from the pipe; returns every complete line in it.
    func consume(_ data: Data) -> [BridgeEvent] {
        buffer.append(contentsOf: data)
        var events: [BridgeEvent] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let event = Self.parse(line: line) { events.append(event) }
        }
        return events
    }

    /// Deliver whatever is left once the pipe reaches end of file. A bridge
    /// that exits without a trailing newline still reported its result.
    func flush() -> [BridgeEvent] {
        defer { buffer.removeAll() }
        guard let event = Self.parse(line: buffer) else { return [] }
        return [event]
    }

    private static func parse<Bytes: DataProtocol>(line: Bytes) -> BridgeEvent? {
        let bytes = Data(line)
        guard let tab = bytes.firstIndex(of: UInt8(ascii: "\t")) else { return nil }
        let tag = String(decoding: bytes[bytes.startIndex..<tab], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return nil }
        var payload = Data(bytes[bytes.index(after: tab)...])
        // A CRLF line ending would otherwise leave \r inside the JSON.
        if payload.last == UInt8(ascii: "\r") { payload.removeLast() }
        return BridgeEvent(tag: tag, data: payload)
    }
}
