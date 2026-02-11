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

        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.title = appState.menuBarFace
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
        statusItem?.button?.title = appState.menuBarFace
        statusItem?.button?.image = nil
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
