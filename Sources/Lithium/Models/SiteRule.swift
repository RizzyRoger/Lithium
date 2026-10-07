import Foundation

/// A restriction on one site. The absence of a rule means no restriction at all,
/// so rules are only ever created explicitly by the user.
struct SiteRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// Registrable domain, lowercased and without scheme or `www.`, e.g. `tiktok.com`.
    var domain: String
    /// Seconds allowed per day. `nil` means banned outright for the day.
    var dailyLimit: TimeInterval?
    var enabled: Bool = true
    /// Local calendar day (`yyyy-MM-dd`) until which this site is hard-locked.
    /// Locked while `today < lockUntilDay`; unblocks at local midnight of that day.
    var lockUntilDay: String?
    /// When true, the rule itself is deleted once the lock expires (lock-only add).
    var removeWhenLockExpires: Bool = false

    var isBanned: Bool { dailyLimit == nil && !isLocked }

    var isLocked: Bool { isLocked(on: UsageStore.today()) }

    func isLocked(on today: String) -> Bool {
        guard let until = lockUntilDay else { return false }
        return today < until
    }

    init(
        id: UUID = UUID(),
        domain: String,
        dailyLimit: TimeInterval?,
        enabled: Bool = true,
        lockUntilDay: String? = nil,
        removeWhenLockExpires: Bool = false
    ) {
        self.id = id
        self.domain = domain
        self.dailyLimit = dailyLimit
        self.enabled = enabled
        self.lockUntilDay = lockUntilDay
        self.removeWhenLockExpires = removeWhenLockExpires
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        domain = try container.decode(String.self, forKey: .domain)
        dailyLimit = try? container.decodeIfPresent(TimeInterval.self, forKey: .dailyLimit)
        enabled = (try? container.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        lockUntilDay = try? container.decodeIfPresent(String.self, forKey: .lockUntilDay)
        removeWhenLockExpires = (try? container.decodeIfPresent(Bool.self, forKey: .removeWhenLockExpires)) ?? false
    }

    /// True when this rule applies to `host` (exact match or any subdomain).
    func matches(host: String) -> Bool {
        let host = host.lowercased()
        return host == domain || host.hasSuffix("." + domain)
    }
}

extension SiteRule {
    /// Human-readable limit, e.g. "1h 30m" or "Banned".
    var limitDescription: String {
        if isLocked { return lockDescription }
        guard let limit = dailyLimit else { return "Banned" }
        return SiteRule.format(seconds: limit)
    }

    var lockDescription: String {
        guard let day = lockUntilDay else { return "Locked" }
        return "until \(SiteRule.formatLockDay(day))"
    }

    static func format(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(secs)s"
    }

    /// `yyyy-MM-dd` → short weekday, e.g. "Fri".
    static func formatLockDay(_ day: String) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return day }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        guard let date = Calendar.current.date(from: components) else { return day }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    static func weekdayName(_ day: String) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return day }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        guard let date = Calendar.current.date(from: components) else { return day }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    static func dayString(from date: Date) -> String {
        UsageStore.today(date)
    }
}
