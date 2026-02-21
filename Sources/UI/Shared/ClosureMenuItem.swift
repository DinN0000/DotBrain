import AppKit

/// Reusable NSMenuItem that invokes a closure on selection.
/// Replaces per-view duplicates (FolderMenuItem, VaultMenuItem).
final class ClosureMenuItem: NSMenuItem {
    var callback: (() -> Void)?

    @objc func invoke() {
        callback?()
    }
}
