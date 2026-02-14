import Foundation

/// Monitors _Inbox folder for changes using DispatchSource file system events
final class InboxWatchdog {
    private var source: DispatchSourceFileSystemObject?
    private let folderPath: String
    private let onChange: () -> Void
    private var debounceWorkItem: DispatchWorkItem?
    private var retryCount = 0
    private var retryTimer: DispatchSourceTimer?
    private static let maxRetries = 3
    private static let retryInterval: TimeInterval = 10.0

    /// Debounce interval in seconds (avoid rapid-fire refreshes)
    private let debounceInterval: TimeInterval = 2.0

    init(folderPath: String, onChange: @escaping () -> Void) {
        self.folderPath = folderPath
        self.onChange = onChange
    }

    deinit {
        stop()
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
            print("[InboxWatchdog] 폴더 열기 실패: \(folderPath)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            self?.handleChange()
        }

        source.setCancelHandler {
            close(fd)
        }

        self.source = source
        source.resume()

        print("[InboxWatchdog] 감시 시작: \(folderPath)")
    }

    /// Stop watching
    func stop() {
        debounceWorkItem?.cancel()
        cancelRetry()
        source?.cancel()
        source = nil
        print("[InboxWatchdog] 감시 중지")
    }

    private func scheduleRetry() {
        guard retryCount < Self.maxRetries else {
            print("[InboxWatchdog] 폴더 대기 포기 (\(Self.maxRetries)회 시도): \(folderPath)")
            return
        }
        retryCount += 1
        print("[InboxWatchdog] 폴더 없음, \(Self.retryInterval)초 후 재시도 (\(retryCount)/\(Self.maxRetries))")

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + Self.retryInterval)
        timer.setEventHandler { [weak self] in
            self?.start()
        }
        retryTimer = timer
        timer.resume()
    }

    private func cancelRetry() {
        retryTimer?.cancel()
        retryTimer = nil
    }

    private func handleChange() {
        // Debounce: cancel any pending callback and schedule a new one
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}
