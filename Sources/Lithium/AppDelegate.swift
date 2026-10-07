import AppKit
import Combine
import SwiftUI

/// Owns the menu bar status item and the popover that hosts the SwiftUI UI.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables: Set<AnyCancellable> = []
    private var titleRefreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info(.app, "Lithium launching")

        model.config.launchAtLogin = LoginItem.isEnabled
        model.start()

        setUpStatusItem()
        setUpPopover()

        // Reflect the most urgent rule in the menu bar itself.
        titleRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshStatusItemAppearance()
        }
        model.$usage
            .combineLatest(model.$config)
            .sink { [weak self] _, _ in self?.refreshStatusItemAppearance() }
            .store(in: &cancellables)

        refreshStatusItemAppearance()

        if !model.config.hasCompletedFirstRun {
            model.config.hasCompletedFirstRun = true
            runFirstLaunchSetup()
        }
    }

    /// On a first launch, open the popover so the app is discoverable and trigger
    /// the Automation prompts up front.
    private func runFirstLaunchSetup() {
        Log.info(.app, "first launch, showing popover and probing permissions")
        model.probeAutomationPermissions()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.popover.isShown else { return }
            self.showPopover()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        titleRefreshTimer?.invalidate()
        model.shutDown()
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Lithium")
        button.imagePosition = .imageLeading
        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setUpPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: MenuBarView(model: model))
    }

    @objc private func statusItemClicked() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }

        // Both states can change outside the app, so re-read them on every open.
        model.refreshHelperStatus()
        model.config.launchAtLogin = LoginItem.isEnabled

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Without this the text fields inside the popover cannot take focus.
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Shows a count of blocked sites, or the time left on whatever is closest to
    /// its limit, so the state is legible without opening the popover.
    private func refreshStatusItemAppearance() {
        guard let button = statusItem?.button else { return }

        let activeRules = model.config.rules.filter { $0.enabled }
        let blocked = activeRules.filter { model.isBlockedNow($0) }

        if !blocked.isEmpty {
            button.image = NSImage(systemSymbolName: "hourglass.badge.plus", accessibilityDescription: "Lithium")
            button.title = " \(blocked.count)"
            button.toolTip = "Blocked today: " + blocked.map(\.domain).sorted().joined(separator: ", ")
            return
        }

        button.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Lithium")

        let closest = activeRules
            .filter { !$0.isBanned && !$0.isLocked }
            .min { lhs, rhs in
                (model.usage.remaining(for: lhs) ?? .greatestFiniteMagnitude)
                    < (model.usage.remaining(for: rhs) ?? .greatestFiniteMagnitude)
            }

        if let closest, let remaining = model.usage.remaining(for: closest), remaining < 15 * 60 {
            button.title = " \(SiteRule.format(seconds: remaining))"
            button.toolTip = "\(closest.domain): \(SiteRule.format(seconds: remaining)) left today"
        } else {
            button.title = ""
            button.toolTip = activeRules.isEmpty
                ? "Lithium — no limits set"
                : "Lithium — \(activeRules.count) site\(activeRules.count == 1 ? "" : "s") limited"
        }
    }
}
