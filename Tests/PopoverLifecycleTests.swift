import AppKit
import XCTest
@testable import DotBrain

@MainActor
final class PopoverLifecycleTests: XCTestCase {

    // Closing the popover must release the hosting content so a wedged
    // SwiftUI graph (e.g. a hover-update loop) dies with it.
    func testCloseReleasesContentAndShowRebuildsIt() {
        var buildCount = 0
        let lifecycle = PopoverLifecycle(makeContent: {
            buildCount += 1
            return NSViewController()
        })

        lifecycle.prepareForShow()
        XCTAssertNotNil(lifecycle.popover.contentViewController)
        XCTAssertEqual(buildCount, 1)

        lifecycle.popoverDidClose(
            Notification(name: NSPopover.didCloseNotification, object: lifecycle.popover)
        )
        XCTAssertNil(lifecycle.popover.contentViewController, "content must be torn down on close")

        lifecycle.prepareForShow()
        XCTAssertNotNil(lifecycle.popover.contentViewController)
        XCTAssertEqual(buildCount, 2, "content is rebuilt fresh on reopen")
    }

    func testPrepareForShowDoesNotRebuildWhileContentAlive() {
        var buildCount = 0
        let lifecycle = PopoverLifecycle(makeContent: {
            buildCount += 1
            return NSViewController()
        })

        lifecycle.prepareForShow()
        lifecycle.prepareForShow()
        XCTAssertEqual(buildCount, 1)
    }
}
