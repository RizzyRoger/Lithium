import Foundation

/// Pure decision logic: given the rules and today's counters, what should happen.
enum Enforcer {
    enum Decision: Equatable {
        /// No rule covers this host, so there is nothing to restrict.
        case untracked
        /// A rule covers it and time is left.
        case allow(rule: SiteRule, remaining: TimeInterval)
        /// Out of time, banned for the day, or locked until a date.
        case block(rule: SiteRule, reason: BlockReason)
    }

    static func decide(host: String, config: Config, usage: UsageStore) -> Decision {
        guard let rule = config.rule(matching: host) else { return .untracked }
        if rule.isLocked(on: usage.day) {
            return .block(rule: rule, reason: .until)
        }
        if rule.dailyLimit == nil {
            return .block(rule: rule, reason: .banned)
        }
        if usage.isExhausted(rule) {
            return .block(rule: rule, reason: .limitReached)
        }
        return .allow(rule: rule, remaining: usage.remaining(for: rule) ?? 0)
    }

    /// Domains that should be in `/etc/hosts` right now.
    static func blockedDomains(config: Config, usage: UsageStore) -> Set<String> {
        var result: Set<String> = []
        for rule in config.rules where rule.enabled {
            if rule.isLocked(on: usage.day) || rule.dailyLimit == nil || usage.isExhausted(rule) {
                result.insert(rule.domain)
            }
        }
        return result
    }
}
