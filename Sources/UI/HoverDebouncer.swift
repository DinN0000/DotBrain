import SwiftUI

/// Debounces onHover state writes.
///
/// macOS SwiftUI re-evaluates every hover responder on each graph update and
/// requests another hover pass afterwards; a hover write that itself triggers
/// a layout change can therefore oscillate into a self-sustaining update loop
/// that pins the main thread (observed as the popover freezing during fast
/// cursor movement). Collapsing rapid flips into one commit after a quiet
/// window starves that feedback loop by construction.
///
/// Hold an instance in `@State` (class identity is stable across view
/// updates) and route every `onHover` through `submit`.
@MainActor
final class HoverDebouncer {
    private var task: Task<Void, Never>?
    private var lastCommitted: Bool?
    private let delay: Duration

    init(delay: Duration = .milliseconds(30)) {
        self.delay = delay
    }

    /// Commits are also deduplicated: the same value is never delivered twice
    /// in a row, so paired side effects (NSCursor push/pop) stay balanced.
    func submit(_ hovering: Bool, commit: @escaping @MainActor (Bool) -> Void) {
        task?.cancel()
        task = Task { @MainActor [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            guard hovering != lastCommitted else { return }
            lastCommitted = hovering
            commit(hovering)
        }
    }

    /// Drop any pending commit (call from onDisappear next to cursor cleanup).
    func cancel() {
        task?.cancel()
        task = nil
    }
}

extension View {
    /// `onHover` variant whose state writes are debounced via HoverDebouncer.
    func debouncedHover(_ debouncer: HoverDebouncer, commit: @escaping @MainActor (Bool) -> Void) -> some View {
        onHover { hovering in
            debouncer.submit(hovering, commit: commit)
        }
    }
}
