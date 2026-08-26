import Foundation

/// Focused-time counters for a single local day. Anything from a previous day is
/// discarded on first access, which is what makes limits reset at midnight.
struct UsageStore: Codable, Equatable {
    /// Local calendar day these counters belong to, as `yyyy-MM-dd`.
    var day: String = UsageStore.today()
    /// Domain (the rule's domain, not the visited host) to seconds spent.
    var seconds: [String: TimeInterval] = [:]

    init(day: String = UsageStore.today(), seconds: [String: TimeInterval] = [:]) {
        self.day = day
        self.seconds = seconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = (try? container.decodeIfPresent(String.self, forKey: .day)) ?? UsageStore.today()
        seconds = (try? container.decodeIfPresent([String: TimeInterval].self, forKey: .seconds)) ?? [:]
    }

    static func today(_ date: Date = Date()) -> String {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Clears counters if the local day has changed. Returns true when it rolled over.
    @discardableResult
    mutating func rolloverIfNeeded(now: Date = Date()) -> Bool {
        let current = UsageStore.today(now)
        guard current != day else { return false }
        Log.info(.store, "day rolled over from \(day) to \(current), clearing \(seconds.count) counter(s)")
        day = current
        seconds.removeAll()
        return true
    }

    func spent(on domain: String) -> TimeInterval { seconds[domain] ?? 0 }

    mutating func add(_ interval: TimeInterval, to domain: String) {
        seconds[domain, default: 0] += interval
    }

    mutating func reset(domain: String) { seconds[domain] = 0 }

    /// Seconds left before a rule is exhausted. `nil` for banned rules, which have
    /// no remaining time by definition.
    func remaining(for rule: SiteRule) -> TimeInterval? {
        guard let limit = rule.dailyLimit else { return nil }
        return max(0, limit - spent(on: rule.domain))
    }

    func isExhausted(_ rule: SiteRule) -> Bool {
        guard let limit = rule.dailyLimit else { return true }
        return spent(on: rule.domain) >= limit
    }
}
