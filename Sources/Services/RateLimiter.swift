import Foundation

/// Adaptive rate limiter that automatically adjusts request pacing per AI provider.
/// Starts with conservative defaults, accelerates on success, backs off on 429/5xx errors.
actor RateLimiter {
    static let shared = RateLimiter()

    private struct ProviderState {
        var minInterval: Duration
        var lastRequestTime: ContinuousClock.Instant?
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

    private var state: [AIProvider: ProviderState] = [:]

    private init() {}

    // MARK: - Public API

    /// Wait until it's safe to make an API request for the given provider.
    func acquire(for provider: AIProvider) async {
        let now = ContinuousClock.now
        var ps = getState(for: provider)

        // Wait for backoff period if active
        if let backoffUntil = ps.backoffUntil, now < backoffUntil {
            let waitTime = backoffUntil - now
            print("[RateLimiter] \(provider.rawValue) backoff 대기: \(waitTime)")
            try? await Task.sleep(for: waitTime)
        }

        // Enforce minimum interval between requests
        if let lastTime = ps.lastRequestTime {
            let elapsed = ContinuousClock.now - lastTime
            if elapsed < ps.minInterval {
                let waitTime = ps.minInterval - elapsed
                try? await Task.sleep(for: waitTime)
            }
        }

        // Record request time
        ps.lastRequestTime = ContinuousClock.now
        state[provider] = ps
    }

    /// Record a successful API call — gradually accelerate (reduce interval).
    func recordSuccess(for provider: AIProvider, duration: Duration) {
        var ps = getState(for: provider)
        ps.consecutiveFailures = 0
        ps.consecutiveSuccesses += 1
        ps.backoffUntil = nil

        // Accelerate: reduce interval by 5% every 3 consecutive successes
        if ps.consecutiveSuccesses >= 3 {
            let floor = minFloor[provider] ?? .milliseconds(250)
            let reduced = ps.minInterval * 95 / 100
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
            let capped = min(ps.consecutiveFailures, 6)  // max pow(2,6)=64 → clamped to 60
            let cooldown = Duration.seconds(min(pow(2.0, Double(capped)), 60))
            ps.backoffUntil = now + cooldown
            print("[RateLimiter] \(provider.rawValue) 429 감지 — 간격: \(ps.minInterval), cooldown: \(cooldown)")
        } else {
            // 5xx/529: moderate backoff — 1.5x interval + 5s cooldown
            ps.minInterval = min(ps.minInterval * 3 / 2, .seconds(15))
            ps.backoffUntil = now + .seconds(5)
            print("[RateLimiter] \(provider.rawValue) 서버 에러 — 간격: \(ps.minInterval), cooldown: 5s")
        }

        state[provider] = ps
    }

    // MARK: - Internal

    private func getState(for provider: AIProvider) -> ProviderState {
        if let existing = state[provider] {
            return existing
        }
        let defaultInterval = defaults[provider] ?? .seconds(1)
        let newState = ProviderState(minInterval: defaultInterval)
        return newState
    }
}
