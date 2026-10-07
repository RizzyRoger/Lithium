import AppKit
import Combine
import Foundation

/// Owns all state and wires the watcher to the two enforcement layers.
final class AppModel: ObservableObject {
    @Published var config: Config
    @Published var usage: UsageStore

    /// What the watcher last saw, shown in the popover footer.
    @Published private(set) var statusLine: String = "Starting up"
    /// Browsers that are frontmost but unreadable because Automation was denied.
    @Published private(set) var automationDeniedBrowsers: Set<String> = []
    @Published private(set) var helperStatus: PrivilegedInstaller.Status
    @Published var helperBusy: Bool = false
    @Published var helperMessage: String?

    private let configFile = JSONFile<Config>(url: Paths.configFile, label: "config")
    private let usageFile = JSONFile<UsageStore>(url: Paths.usageFile, label: "usage")

    private let watcher = BrowserWatcher()
    private let server = BlockPageServer()
    private let hosts = HostsSyncClient()

    /// The last countable observation, used to credit elapsed time.
    private var lastObservedDomain: String?
    private var lastObservationTime: Date?
    /// Never credit more than this from a single gap, so sleep and wake do not
    /// burn a whole day's allowance.
    private var maxCreditPerSample: TimeInterval { watcher.interval * 3 }

    private var saveWorkItem: DispatchWorkItem?
    private var usageSaveTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        Paths.ensureUserDirectories()
        var loadedConfig = configFile.load(default: Config())
        var loadedUsage = usageFile.load(default: UsageStore())
        loadedUsage.rolloverIfNeeded()
        loadedConfig.helperInstalled = PrivilegedInstaller.status().isFullyInstalled

        config = loadedConfig
        usage = loadedUsage
        helperStatus = PrivilegedInstaller.status()
        hydrateLocksFromHelper()
        expireLocksIfNeeded()

        Log.info(.app, "loaded \(config.rules.count) rule(s), \(config.presets.count) preset(s), usage day \(usage.day)")
    }

    // MARK: - Lifecycle

    func start() {
        server.start()
        watcher.onSample = { [weak self] sample in
            self?.handle(sample: sample)
        }
        watcher.start()

        // Persist counters periodically so a crash costs at most a few seconds.
        usageSaveTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.usageFile.save(self.usage)
        }

        $config
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleConfigSave() }
            .store(in: &cancellables)

        expireLocksIfNeeded()
        syncHosts(force: true)
    }

    func shutDown() {
        watcher.stop()
        server.stop()
        usageSaveTimer?.invalidate()
        saveWorkItem?.cancel()
        configFile.save(config)
        usageFile.save(usage)
        Log.info(.app, "shut down cleanly")
    }

    // MARK: - Sampling

    private func handle(sample: WatchSample) {
        let now = Date()

        if usage.rolloverIfNeeded(now: now) {
            usageFile.save(usage)
            expireLocksIfNeeded()
            syncHosts(force: true)
        } else {
            expireLocksIfNeeded()
        }

        creditElapsedTime(now: now)

        switch sample {
        case .idle(let reason):
            lastObservedDomain = nil
            lastObservationTime = now
            statusLine = reason.prefix(1).uppercased() + reason.dropFirst()

        case .permissionDenied(let browser):
            lastObservedDomain = nil
            lastObservationTime = now
            automationDeniedBrowsers.insert(browser.displayName)
            statusLine = "Needs Automation access for \(browser.displayName)"

        case .tab(let tab):
            lastObservationTime = now
            // Only a successful read clears the warning for that browser.
            automationDeniedBrowsers.remove(tab.browser.displayName)

            switch Enforcer.decide(host: tab.host, config: config, usage: usage) {
            case .untracked:
                lastObservedDomain = nil
                statusLine = "\(tab.host) — no limit set"

            case .allow(let rule, let remaining):
                lastObservedDomain = rule.domain
                statusLine = "\(rule.domain) — \(SiteRule.format(seconds: remaining)) left"

            case .block(let rule, let reason):
                lastObservedDomain = nil
                if reason == .until, let until = rule.lockUntilDay {
                    statusLine = "\(rule.domain) — \(SiteRule.formatLockDay(until))"
                } else {
                    statusLine = "\(rule.domain) — blocked"
                }
                block(tab: tab, rule: rule, reason: reason)
            }
        }
    }

    /// Credits the time between the previous observation and now to whatever site
    /// was being looked at then.
    private func creditElapsedTime(now: Date) {
        guard let domain = lastObservedDomain, let last = lastObservationTime else { return }
        let elapsed = now.timeIntervalSince(last)
        guard elapsed > 0 else { return }
        let credited = min(elapsed, maxCreditPerSample)
        if elapsed > maxCreditPerSample {
            Log.info(.tracking, "gap of \(Int(elapsed))s for \(domain) capped at \(Int(credited))s")
        }
        if let rule = config.rules.first(where: { $0.domain == domain && $0.enabled }),
           rule.isLocked(on: usage.day) {
            return
        }
        usage.add(credited, to: domain)
        Log.verbose(.tracking, "credited \(String(format: "%.2f", credited))s to \(domain), total \(Int(usage.spent(on: domain)))s")

        // Crossing the limit is the moment to publish the hosts entry.
        if let rule = config.rules.first(where: { $0.domain == domain && $0.enabled }),
           usage.isExhausted(rule) {
            Log.info(.enforcement, "\(domain) reached its daily limit")
            syncHosts()
        }
    }

    private func block(tab: ActiveTab, rule: SiteRule, reason: BlockReason) {
        syncHosts()

        guard let url = server.blockURL(
            domain: rule.domain,
            reason: reason,
            used: usage.spent(on: rule.domain),
            limit: rule.dailyLimit,
            untilDay: rule.lockUntilDay
        ) else {
            Log.error(.enforcement, "block page server not running; relying on /etc/hosts only")
            return
        }

        Log.info(.enforcement, "redirecting \(tab.browser.displayName) from \(tab.host) to block page (\(reason.rawValue))")
        AppleScriptBridge.shared.setActiveTabURL(of: tab.browser, to: url) { result in
            if case .failure(let error) = result {
                Log.error(.enforcement, "redirect failed: \(error)")
            }
        }
    }

    // MARK: - Hosts layer

    func syncHosts(force: Bool = false) {
        if !config.hostsEnforcementEnabled && !hasActiveLocks {
            hosts.clear()
            return
        }
        let domains = Enforcer.blockedDomains(config: config, usage: usage)
        hosts.sync(domains: domains, force: force)
    }

    var hasActiveLocks: Bool {
        config.rules.contains { $0.isLocked(on: usage.day) }
    }

    // MARK: - Rules

    func addRule(domain: String, limit: TimeInterval?, lockUntilDay: String? = nil) {
        guard let normalized = DomainMatcher.normalize(userInput: domain) else {
            Log.error(.ui, "rejected invalid domain input: \(domain)")
            return
        }
        let existingIndex = config.rules.firstIndex(where: { $0.domain == normalized })
        if let existingIndex, config.rules[existingIndex].isLocked(on: usage.day) {
            Log.error(.ui, "refused to edit locked rule for \(normalized)")
            return
        }

        if let lockUntilDay {
            guard helperStatus.isFullyInstalled else {
                Log.error(.ui, "until-lock requires the hard-blocking helper")
                return
            }
            guard lockUntilDay > usage.day else {
                Log.error(.ui, "lock until-day \(lockUntilDay) is not in the future")
                return
            }
            if let existingIndex {
                let previous = config.rules[existingIndex].lockUntilDay
                if previous == nil || lockUntilDay > previous! {
                    config.rules[existingIndex].lockUntilDay = lockUntilDay
                }
                config.rules[existingIndex].enabled = true
                Log.info(.ui, "locked \(normalized) until \(lockUntilDay) over existing rule")
            } else {
                config.rules.append(SiteRule(
                    domain: normalized,
                    dailyLimit: nil,
                    lockUntilDay: lockUntilDay,
                    removeWhenLockExpires: true
                ))
                Log.info(.ui, "locked \(normalized) until \(lockUntilDay)")
            }
            hosts.submitLock(domain: normalized, untilDay: lockUntilDay)
        } else if let existingIndex {
            config.rules[existingIndex].dailyLimit = limit
            config.rules[existingIndex].enabled = true
            Log.info(.ui, "updated rule for \(normalized) to \(limit.map { SiteRule.format(seconds: $0) } ?? "banned")")
        } else {
            config.rules.append(SiteRule(domain: normalized, dailyLimit: limit))
            Log.info(.ui, "added rule for \(normalized): \(limit.map { SiteRule.format(seconds: $0) } ?? "banned")")
        }
        config.rules.sort { $0.domain < $1.domain }
        config.noteRecentDomain(normalized)
        config.activePresetID = nil
        syncHosts()
    }

    func removeRule(_ rule: SiteRule) {
        guard !rule.isLocked(on: usage.day) else {
            Log.error(.ui, "refused to remove locked rule for \(rule.domain)")
            return
        }
        config.rules.removeAll { $0.id == rule.id }
        config.activePresetID = nil
        Log.info(.ui, "removed rule for \(rule.domain)")
        syncHosts()
    }

    func setEnabled(_ enabled: Bool, for rule: SiteRule) {
        guard !rule.isLocked(on: usage.day) else {
            Log.error(.ui, "refused to pause locked rule for \(rule.domain)")
            return
        }
        guard let index = config.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        config.rules[index].enabled = enabled
        config.activePresetID = nil
        syncHosts()
    }

    /// Gives back the rest of the day for one site, useful after a deliberate override.
    func resetUsage(for rule: SiteRule) {
        guard !rule.isLocked(on: usage.day) else {
            Log.error(.ui, "refused to reset usage on locked rule for \(rule.domain)")
            return
        }
        usage.reset(domain: rule.domain)
        usageFile.save(usage)
        Log.info(.ui, "reset today's usage for \(rule.domain)")
        syncHosts()
    }

    // MARK: - Presets

    func savePreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = config.presets.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            config.presets[index].rules = config.rules
            config.presets[index].createdAt = Date()
            config.activePresetID = config.presets[index].id
            Log.info(.ui, "overwrote preset '\(trimmed)' with \(config.rules.count) rule(s)")
        } else {
            let preset = Preset(name: trimmed, rules: config.rules)
            config.presets.append(preset)
            config.activePresetID = preset.id
            Log.info(.ui, "saved preset '\(trimmed)' with \(config.rules.count) rule(s)")
        }
        config.presets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func applyPreset(_ preset: Preset) {
        let locked = config.rules.filter { $0.isLocked(on: usage.day) }
        let lockedDomains = Set(locked.map(\.domain))
        var next = preset.rules.compactMap { rule -> SiteRule? in
            guard !lockedDomains.contains(rule.domain) else { return nil }
            var copy = rule
            copy.id = UUID()
            copy.lockUntilDay = nil
            copy.removeWhenLockExpires = false
            return copy
        }
        next.append(contentsOf: locked)
        next.sort { $0.domain < $1.domain }
        config.rules = next
        config.activePresetID = preset.id
        Log.info(.ui, "applied preset '\(preset.name)' (kept \(locked.count) locked rule(s))")
        syncHosts()
    }

    func deletePreset(_ preset: Preset) {
        config.presets.removeAll { $0.id == preset.id }
        if config.activePresetID == preset.id { config.activePresetID = nil }
        Log.info(.ui, "deleted preset '\(preset.name)'")
    }

    // MARK: - Helper installation

    func refreshHelperStatus() {
        helperStatus = PrivilegedInstaller.status()
        config.helperInstalled = helperStatus.isFullyInstalled
    }

    func installHelper() {
        guard !helperBusy else { return }
        helperBusy = true
        helperMessage = nil
        PrivilegedInstaller.install { [weak self] result in
            guard let self else { return }
            self.helperBusy = false
            switch result {
            case .success:
                self.refreshHelperStatus()
                self.hosts.invalidateCache()
                self.syncHosts(force: true)
                self.helperMessage = "Hard blocking is active."
            case .failure(let error):
                self.helperMessage = error.localizedDescription
            }
        }
    }

    func uninstallHelper() {
        guard !helperBusy else { return }
        if hasActiveLocks {
            helperMessage = "Cannot remove the helper while a hard lock is active."
            return
        }
        helperBusy = true
        helperMessage = nil
        PrivilegedInstaller.uninstall { [weak self] result in
            guard let self else { return }
            self.helperBusy = false
            self.hosts.invalidateCache()
            switch result {
            case .success:
                self.refreshHelperStatus()
                self.helperMessage = "Hard blocking removed."
            case .failure(let error):
                self.helperMessage = error.localizedDescription
            }
        }
    }

    /// Re-checks Automation access on the next tick after the user changes it in
    /// System Settings.
    func recheckAutomationPermission() {
        watcher.resetPermissionCache()
        automationDeniedBrowsers.removeAll()
    }

    /// Asks every running browser for its active tab once, which is what makes
    /// macOS show the Automation prompts during setup rather than later, at the
    /// moment a limit would first have been enforced.
    func probeAutomationPermissions() {
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let browsers = Browser.all.filter { runningBundleIDs.contains($0.bundleID) }
        guard !browsers.isEmpty else {
            Log.info(.app, "no known browser running, skipping permission probe")
            return
        }
        Log.info(.app, "probing Automation access for \(browsers.map(\.displayName).joined(separator: ", "))")
        for browser in browsers {
            AppleScriptBridge.shared.activeTabURL(of: browser) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.automationDeniedBrowsers.remove(browser.displayName)
                case .failure(.notPermitted):
                    self.automationDeniedBrowsers.insert(browser.displayName)
                case .failure:
                    break
                }
            }
        }
    }

    // MARK: - Derived values for the UI

    var blockPagePort: UInt16? { server.port }

    func spent(on rule: SiteRule) -> TimeInterval { usage.spent(on: rule.domain) }

    func progress(for rule: SiteRule) -> Double {
        guard let limit = rule.dailyLimit, limit > 0 else { return 1 }
        return min(1, usage.spent(on: rule.domain) / limit)
    }

    func isBlockedNow(_ rule: SiteRule) -> Bool {
        guard rule.enabled else { return false }
        if rule.isLocked(on: usage.day) { return true }
        if rule.dailyLimit == nil { return true }
        return usage.isExhausted(rule)
    }

    func setHostsEnforcementEnabled(_ enabled: Bool) {
        if !enabled && hasActiveLocks {
            helperMessage = "Cannot turn off hard blocking while a lock is active."
            return
        }
        config.hostsEnforcementEnabled = enabled
        syncHosts(force: true)
    }

    /// Re-reads root-owned locks so deleting a rule in config.json cannot hide it.
    func hydrateLocksFromHelper() {
        let committed = hosts.readCommittedLocks()
        guard !committed.isEmpty else { return }
        let today = usage.day
        for (domain, day) in committed where today < day {
            if let index = config.rules.firstIndex(where: { $0.domain == domain }) {
                let current = config.rules[index].lockUntilDay
                if current == nil || day > current! {
                    config.rules[index].lockUntilDay = day
                    config.rules[index].enabled = true
                }
            } else {
                config.rules.append(SiteRule(
                    domain: domain,
                    dailyLimit: nil,
                    lockUntilDay: day,
                    removeWhenLockExpires: true
                ))
            }
        }
        config.rules.sort { $0.domain < $1.domain }
    }

    @discardableResult
    func expireLocksIfNeeded() -> Bool {
        let today = usage.day
        var changed = false
        let next = config.rules.compactMap { rule -> SiteRule? in
            guard let until = rule.lockUntilDay, today >= until else { return rule }
            changed = true
            Log.info(.enforcement, "lock expired for \(rule.domain) (was until \(until))")
            if rule.removeWhenLockExpires { return nil }
            var copy = rule
            copy.lockUntilDay = nil
            copy.removeWhenLockExpires = false
            return copy
        }
        if changed {
            config.rules = next
            syncHosts(force: true)
        }
        return changed
    }

    // MARK: - Saving

    private func scheduleConfigSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.configFile.save(self.config)
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }
}
