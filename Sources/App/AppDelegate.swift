import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let appState = AppState.shared
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        observeStateForIcon()

        // Set app icon (shown in Activity Monitor, Force Quit, etc.)
        NSApp.applicationIconImage = AppIconGenerator.generate()

        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = makeMenuBarImage(appState.menuBarFace)
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopover()
                .environmentObject(appState)
        )
        self.popover = popover
    }

    private func observeStateForIcon() {
        // Observe all state changes that affect the icon, including isProcessing
        appState.$currentScreen
            .combineLatest(
                appState.$inboxFileCount,
                appState.$processedResults,
                appState.$pendingConfirmations
            )
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _, _ in
                self?.updateMenuBarIcon()
            }
            .store(in: &cancellables)

        appState.$isProcessing
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuBarIcon()
            }
            .store(in: &cancellables)
    }

    private func updateMenuBarIcon() {
        statusItem?.button?.title = ""
        statusItem?.button?.image = makeMenuBarImage(appState.menuBarFace)
    }

    /// Render face text into an NSImage for precise vertical alignment in menu bar
    private func makeMenuBarImage(_ text: String) -> NSImage {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.controlTextColor
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let imageSize = NSSize(width: ceil(size.width) + 2, height: 22)

        let image = NSImage(size: imageSize, flipped: false) { rect in
            let y = (rect.height - size.height) / 2 + 1
            (text as NSString).draw(at: NSPoint(x: 1, y: y), withAttributes: attrs)
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Bring app to front
            NSApp.activate(ignoringOtherApps: true)

            // Refresh inbox count
            Task {
                await appState.refreshInboxCount()
            }
        }
    }
}
