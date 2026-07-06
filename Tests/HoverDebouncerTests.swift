import XCTest
@testable import DotBrain

@MainActor
final class HoverDebouncerTests: XCTestCase {

    // A burst of rapid flips (the oscillation signature) must collapse into
    // a single commit of the final value.
    func testRapidFlipsCommitOnlyFinalValue() async {
        let debouncer = HoverDebouncer(delay: .milliseconds(20))
        var commits: [Bool] = []

        for value in [true, false, true, false] {
            debouncer.submit(value) { commits.append($0) }
        }

        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(commits, [false])
    }

    // Repeated commits of the same value must be suppressed so side effects
    // like NSCursor.push()/pop() stay strictly alternating.
    func testEqualValueIsNotCommittedTwice() async {
        let debouncer = HoverDebouncer(delay: .milliseconds(20))
        var commits: [Bool] = []

        debouncer.submit(true) { commits.append($0) }
        try? await Task.sleep(for: .milliseconds(100))

        debouncer.submit(false) { commits.append($0) }
        debouncer.submit(true) { commits.append($0) }
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(commits, [true])
    }

    func testSingleHoverCommitsAfterDelay() async {
        let debouncer = HoverDebouncer(delay: .milliseconds(20))
        var commits: [Bool] = []

        debouncer.submit(true) { commits.append($0) }
        XCTAssertEqual(commits, [], "must not commit synchronously")

        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(commits, [true])
    }
}
