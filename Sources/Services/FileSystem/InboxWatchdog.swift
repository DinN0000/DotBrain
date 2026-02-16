import Foundation

/// Monitors _Inbox folder for changes using DispatchSource file system events.
/// Note: DispatchSource.makeFileSystemObjectSource is a kernel-level API with no
/// Swift Concurrency equivalent, so we keep it for the FS monitoring itself.
/// Debounce and retry logic use Task-based patterns to minimize GCD surface.
@MainActor
final class InboxWatchdog {
    private var source: DispatchSourceFileSystemObject?
    private let folderPath: String
    private let onChange: @MainActor () -> Void
    private var debounceTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryCount = 0
    private static let maxRetries = 3
    private static let retryInterval: TimeInterval = 10.0

    /// Debounce interval in seconds (avoid rapid-fire refreshes)
    private let debounceInterval: TimeInterval = 2.0

    init(folderPath: String, onChange: @MainActor @escaping () -> Void) {
        self.folderPath = folderPath
        self.onChange = onChange
    }

    deinit {
        debounceTask?.cancel()
        retryTask?.cancel()
        source?.cancel()
    }

    /// Start watching the inbox folder
    func start() {
        // Only watch if folder already exists — never create it
        guard FileManager.default.fileExists(atPath: folderPath) else {
            scheduleRetry()
            return
        }
        retryCount = 0
        cancelRetry()

        let fd = open(folderPath, O_EVTONLY)
        guard fd >= 0 else {
            print("[InboxWatchdog] Failed to open folder: \(folderPath)")
            return
        }

        // DispatchSource requires a GCD queue — use utility QoS, minimal surface
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            // Bridge from GCD to MainActor
            Task { @MainActor [weak self] in
                self?.handleChange()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        self.source = source
        source.resume()

        print("[InboxWatchdog] Watching: \(folderPath)")
    }

    /// Stop watching
    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        cancelRetry()
        source?.cancel()
        source = nil
    }

    private func scheduleRetry() {
        guard retryCount < Self.maxRetries else {
            print("[InboxWatchdog] Gave up waiting for folder (\(Self.maxRetries) attempts): \(folderPath)")
            return
        }
        retryCount += 1
        print("[InboxWatchdog] Folder missing, retry in \(Self.retryInterval)s (\(retryCount)/\(Self.maxRetries))")

        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.retryInterval))
            guard !Task.isCancelled else { return }
            self?.start()
        }
    }

    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
    }

    private func handleChange() {
        // Debounce: cancel any pending callback and schedule a new one
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.debounceInterval ?? 2.0))
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }
}
