import Foundation

/// Monitors _Inbox folder for changes using DispatchSource file system events
final class InboxWatchdog {
    private var source: DispatchSourceFileSystemObject?
    private let folderPath: String
    private let onChange: () -> Void
    private var debounceWorkItem: DispatchWorkItem?

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
        // Ensure folder exists
        let fm = FileManager.default
        try? fm.createDirectory(atPath: folderPath, withIntermediateDirectories: true)

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
        source?.cancel()
        source = nil
        print("[InboxWatchdog] 감시 중지")
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
