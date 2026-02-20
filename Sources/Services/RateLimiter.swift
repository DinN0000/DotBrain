import Foundation

/// Adaptive rate limiter with concurrent slot support per AI provider.
/// Each provider gets N slots that can fire independently, maintaining minInterval per slot.
/// Claude gets 3 slots (120 RPM headroom), Gemini gets 1 slot (conservative for free tier).
actor RateLimiter {
    static let shared = RateLimiter()

    private struct ProviderState {
        var minInterval: Duration
        var slotCount: Int
        /// Next available time for each slot
        var slotNextAvailable: [ContinuousClock.Instant]
        var consecutiveSuccesses: Int = 0
        var consecutiveFailures: Int = 0
        var backoffUntil: ContinuousClock.Instant?
    }

    /// Conservative defaults per provider (safe for free tiers)
    private let defaults: [AIProvider: Duration] = [
        .gemini: .milliseconds(4200),   // ~14 RPM (free tier: 15 RPM)
        .claude: .milliseconds(500),    // ~120 RPM
    ]

    /// Minimum allowed interval (50% of default) — acceleration floor
    private let minFloor: [AIProvider: Duration] = [
        .gemini: .milliseconds(2100),
        .claude: .milliseconds(250),
    ]

    /// Number of concurrent slots per provider
    private let defaultSlots: [AIProvider: Int] = [
        .claude: 3,   // 120 RPM allows comfortable concurrent requests
        .gemini: 1,   // Free tier 15 RPM — keep sequential to avoid 429
    ]

    private var state: [AIProvider: ProviderState] = [:]

    private init() {}

    // MARK: - Public API

    /// Wait until it's safe to make an API request for the given provider.
    /// Selects the earliest available slot and reserves it.
    func acquire(for provider: AIProvider) async {
        var ps = getState(for: provider)

        // Wait for backoff period if active, then clear it
        if let backoffUntil = ps.backoffUntil, ContinuousClock.now < backoffUntil {
            let waitTime = backoffUntil - ContinuousClock.now
            NSLog("[RateLimiter] %@ backoff 대기: %@", provider.rawValue, "\(waitTime)")
            try? await Task.sleep(for: waitTime)
            ps.backoffUntil = nil
            state[provider] = ps
        }

        // Find the slot with the earliest available time
        var earliestIndex = 0
        for i in 1..<ps.slotNextAvailable.count {
            if ps.slotNextAvailable[i] < ps.slotNextAvailable[earliestIndex] {
                earliestIndex = i
            }
        }

        let now = ContinuousClock.now
        let slotTime = ps.slotNextAvailable[earliestIndex]
        let waitUntil = slotTime > now ? slotTime : now

        // Reserve this slot's next available time BEFORE sleeping
        ps.slotNextAvailable[earliestIndex] = waitUntil + ps.minInterval
        state[provider] = ps

        // Sleep if needed
        let sleepDuration = waitUntil - now
        if sleepDuration > .zero {
            try? await Task.sleep(for: sleepDuration)
        }
    }

    /// Record a successful API call — gradually accelerate (reduce interval).
    func recordSuccess(for provider: AIProvider, duration: Duration) {
        var ps = getState(for: provider)
        ps.consecutiveFailures = 0
        ps.consecutiveSuccesses += 1
        ps.backoffUntil = nil

        // Accelerate: reduce interval by 15% every 2 consecutive successes
        if ps.consecutiveSuccesses >= 2 {
            let floor = minFloor[provider] ?? .milliseconds(250)
            let reduced = ps.minInterval * 85 / 100
            ps.minInterval = max(reduced, floor)
            ps.consecutiveSuccesses = 0
        }

        state[provider] = ps
    }

    /// Record a failed API call — back off adaptively based on error type.
    func recordFailure(for provider: AIProvider, isRateLimit: Bool) {
        var ps = getState(for: provider)
        ps.consecutiveSuccesses = 0
        ps.consecutiveFailures += 1

        let now = ContinuousClock.now

        if isRateLimit {
            // 429: aggressive backoff — double interval + exponential cooldown
            ps.minInterval = min(ps.minInterval * 2, .seconds(30))
            let capped = min(ps.consecutiveFailures, 6)  // max pow(2,6)=64 -> clamped to 60
            let cooldown = Duration.seconds(min(pow(2.0, Double(capped)), 60))
            let backoffEnd = now + cooldown
            ps.backoffUntil = backoffEnd
            // Push all slots past the backoff period to prevent concurrent 429s
            for i in 0..<ps.slotNextAvailable.count {
                ps.slotNextAvailable[i] = backoffEnd
            }
            NSLog("[RateLimiter] %@ 429 감지 — 간격: %@, cooldown: %@", provider.rawValue, "\(ps.minInterval)", "\(cooldown)")
        } else {
            // 5xx/529: moderate backoff — 1.5x interval + 5s cooldown
            ps.minInterval = min(ps.minInterval * 3 / 2, .seconds(15))
            ps.backoffUntil = now + .seconds(5)
            NSLog("[RateLimiter] %@ 서버 에러 — 간격: %@, cooldown: 5s", provider.rawValue, "\(ps.minInterval)")
        }

        state[provider] = ps
    }

    // MARK: - Internal

    private func getState(for provider: AIProvider) -> ProviderState {
        if let existing = state[provider] {
            return existing
        }
        let interval = defaults[provider] ?? .seconds(1)
        let slots = defaultSlots[provider] ?? 1
        return ProviderState(
            minInterval: interval,
            slotCount: slots,
            slotNextAvailable: Array(repeating: .now, count: slots)
        )
    }
}
