import AppKit

/// Owns the menubar NSPopover and tears its SwiftUI content down on close.
///
/// The hosting controller used to live for the whole app lifetime, so a
/// wedged view graph (e.g. a hover-update loop saturating the main thread)
/// kept spinning at 100% CPU even after the popover closed. Releasing the
/// content on close guarantees any such loop dies with it; the content is
/// rebuilt on the next show (all real state lives in AppState).
@MainActor
final class PopoverLifecycle: NSObject, NSPopoverDelegate {
    let popover: NSPopover
    private let makeContent: () -> NSViewController

    init(makeContent: @escaping () -> NSViewController) {
        self.makeContent = makeContent
        self.popover = NSPopover()
        super.init()
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.behavior = .transient
        popover.delegate = self
    }

    /// Call before every show — rebuilds the content if it was torn down.
    func prepareForShow() {
        if popover.contentViewController == nil {
            popover.contentViewController = makeContent()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }
}
