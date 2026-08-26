import Foundation

/// Everything persisted in `config.json`.
struct Config: Codable, Equatable {
    var rules: [SiteRule] = []
    var presets: [Preset] = []
    /// Set when a preset is applied, cleared as soon as the rules diverge from it.
    var activePresetID: UUID?
    /// Domains the user has typed before, most recent first. Feeds autocomplete.
    var recentDomains: [String] = []
    /// True once the root helper and LaunchDaemon have been installed.
    var helperInstalled: Bool = false
    /// Whether to mirror blocked domains into /etc/hosts as a hard backstop.
    var hostsEnforcementEnabled: Bool = true
    var launchAtLogin: Bool = false
    /// Cleared only once, so the popover and permission prompts appear on the
    /// very first launch and never again.
    var hasCompletedFirstRun: Bool = false

    // Decoded leniently so a config written by an older or newer build still
    // loads instead of being quarantined as corrupt.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rules = (try? container.decodeIfPresent([SiteRule].self, forKey: .rules)) ?? []
        presets = (try? container.decodeIfPresent([Preset].self, forKey: .presets)) ?? []
        activePresetID = try? container.decodeIfPresent(UUID.self, forKey: .activePresetID)
        recentDomains = (try? container.decodeIfPresent([String].self, forKey: .recentDomains)) ?? []
        helperInstalled = (try? container.decodeIfPresent(Bool.self, forKey: .helperInstalled)) ?? false
        hostsEnforcementEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .hostsEnforcementEnabled)) ?? true
        launchAtLogin = (try? container.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? false
        hasCompletedFirstRun = (try? container.decodeIfPresent(Bool.self, forKey: .hasCompletedFirstRun)) ?? false
    }

    init() {}

    func rule(matching host: String) -> SiteRule? {
        // Longest domain wins, so a rule for `docs.google.com` beats one for
        // `google.com` when both are present.
        rules
            .filter { $0.enabled && $0.matches(host: host) }
            .max { $0.domain.count < $1.domain.count }
    }

    mutating func noteRecentDomain(_ domain: String) {
        recentDomains.removeAll { $0 == domain }
        recentDomains.insert(domain, at: 0)
        if recentDomains.count > 40 { recentDomains.removeLast(recentDomains.count - 40) }
    }
}
