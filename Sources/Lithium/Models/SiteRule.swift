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

    var isBanned: Bool { dailyLimit == nil }

    init(id: UUID = UUID(), domain: String, dailyLimit: TimeInterval?, enabled: Bool = true) {
        self.id = id
        self.domain = domain
        self.dailyLimit = dailyLimit
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        domain = try container.decode(String.self, forKey: .domain)
        dailyLimit = try? container.decodeIfPresent(TimeInterval.self, forKey: .dailyLimit)
        enabled = (try? container.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
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
        guard let limit = dailyLimit else { return "Banned" }
        return SiteRule.format(seconds: limit)
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
}
