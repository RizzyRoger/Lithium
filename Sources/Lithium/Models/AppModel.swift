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

        Log.info(.app, "loaded \(loadedConfig.rules.count) rule(s), \(loadedConfig.presets.count) preset(s), usage day \(loadedUsage.day)")
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
            syncHosts(force: true)
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
                statusLine = "\(rule.domain) — blocked"
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
            limit: rule.dailyLimit
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
        guard config.hostsEnforcementEnabled else {
            hosts.clear()
            return
        }
        let domains = Enforcer.blockedDomains(config: config, usage: usage)
        hosts.sync(domains: domains, force: force)
    }

    // MARK: - Rules

    func addRule(domain: String, limit: TimeInterval?) {
        guard let normalized = DomainMatcher.normalize(userInput: domain) else {
            Log.error(.ui, "rejected invalid domain input: \(domain)")
            return
        }
        if let index = config.rules.firstIndex(where: { $0.domain == normalized }) {
            config.rules[index].dailyLimit = limit
            config.rules[index].enabled = true
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
        config.rules.removeAll { $0.id == rule.id }
        config.activePresetID = nil
        Log.info(.ui, "removed rule for \(rule.domain)")
        syncHosts()
    }

    func setEnabled(_ enabled: Bool, for rule: SiteRule) {
        guard let index = config.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        config.rules[index].enabled = enabled
        config.activePresetID = nil
        syncHosts()
    }

    /// Gives back the rest of the day for one site, useful after a deliberate override.
    func resetUsage(for rule: SiteRule) {
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
        // Fresh identifiers keep the applied copy independent of the stored preset.
        config.rules = preset.rules.map { rule in
            var copy = rule
            copy.id = UUID()
            return copy
        }
        config.activePresetID = preset.id
        Log.info(.ui, "applied preset '\(preset.name)' (\(preset.rules.count) rule(s))")
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
        return rule.isBanned || usage.isExhausted(rule)
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
