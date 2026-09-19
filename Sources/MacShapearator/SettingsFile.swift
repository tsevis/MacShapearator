import Foundation

/// Reads and writes the settings JSON.
///
/// Every edit in the UI is one mutation of `ExtractionSettings`, and typing a
/// path is one per keystroke. Writing each of those to disk on the main thread
/// is needless work, so writes are coalesced onto a background queue — with a
/// synchronous flush for quit, because a debounce that loses the last edit is
/// worse than the churn it saves.
final class SettingsFile: @unchecked Sendable {
    /// Long enough to swallow a burst of typing, short enough to be invisible.
    private static let delay: DispatchTimeInterval = .milliseconds(400)

    private let url: URL
    private let queue = DispatchQueue(label: "MacShapearator.settings")
    private let lock = NSLock()
    private var pending: ExtractionSettings?
    private var scheduled: DispatchWorkItem?
    private var observer: NSObjectProtocol?

    init(url: URL) {
        self.url = url
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Flush whenever `notification` arrives — the app is about to quit, and
    /// a coalescing window that swallows the last edit is worse than the
    /// churn it saves. Takes the name rather than importing AppKit, so
    /// persistence stays independent of the UI framework.
    func flush(on notification: Notification.Name) {
        observer = NotificationCenter.default.addObserver(
            forName: notification, object: nil, queue: nil
        ) { [weak self] _ in self?.flush() }
    }

    func load() -> ExtractionSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ExtractionSettings.self, from: data)
    }

    /// Record an edit. The write happens shortly afterwards, off this thread.
    func save(_ settings: ExtractionSettings) {
        lock.lock()
        pending = settings
        scheduled?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.writePending() }
        scheduled = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + Self.delay, execute: item)
    }

    /// Write any pending edit now and wait for it. Safe from any thread.
    func flush() {
        lock.lock()
        scheduled?.cancel()
        scheduled = nil
        lock.unlock()
        queue.sync { self.writePending() }
    }

    private func writePending() {
        lock.lock()
        let settings = pending
        pending = nil
        lock.unlock()
        guard let settings, let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
