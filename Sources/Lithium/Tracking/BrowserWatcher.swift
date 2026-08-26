import AppKit
import CoreGraphics
import Foundation

struct ActiveTab: Equatable {
    let browser: Browser
    let urlString: String
    let host: String
}

/// One observation of what the user is looking at.
enum WatchSample {
    /// A browser is frontmost and showing a web page.
    case tab(ActiveTab)
    /// Nothing countable is on screen, with a reason for the log.
    case idle(reason: String)
    /// A browser is frontmost but Automation access is missing, so we are blind.
    case permissionDenied(Browser)
}

/// Polls once a second for the active tab of the frontmost browser. Only the
/// frontmost window's active tab counts, which is what makes the daily limits
/// measure attention rather than merely having a tab open.
final class BrowserWatcher {
    private(set) var isRunning = false
    private var timer: Timer?
    private var queryInFlight = false
    /// Browsers already known to lack Automation access, to keep the log quiet.
    private var permissionDeniedBundleIDs: Set<String> = []

    var onSample: ((WatchSample) -> Void)?

    let interval: TimeInterval

    init(interval: TimeInterval = 1.0) {
        self.interval = interval
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // A short tolerance lets the timer coalesce with other work and keeps the
        // energy cost of a once-a-second poll negligible.
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Log.info(.tracking, "watcher started, interval \(interval)s")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        Log.info(.tracking, "watcher stopped")
    }

    /// Forget cached permission failures, e.g. after the user grants access.
    func resetPermissionCache() {
        permissionDeniedBundleIDs.removeAll()
    }

    private func tick() {
        guard !queryInFlight else {
            Log.verbose(.tracking, "skipping tick, previous query still in flight")
            return
        }

        if BrowserWatcher.isScreenLocked() {
            emit(.idle(reason: "screen locked"))
            return
        }

        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontmost.bundleIdentifier
        else {
            emit(.idle(reason: "no frontmost app"))
            return
        }

        guard let browser = Browser.known(bundleID: bundleID) else {
            emit(.idle(reason: "Not browsing — \(frontmost.localizedName ?? bundleID) is in front"))
            return
        }

        queryInFlight = true
        AppleScriptBridge.shared.activeTabURL(of: browser) { [weak self] result in
            guard let self else { return }
            self.queryInFlight = false
            switch result {
            case .success(let urlString):
                self.permissionDeniedBundleIDs.remove(browser.bundleID)
                guard !urlString.isEmpty else {
                    self.emit(.idle(reason: "\(browser.displayName) has no open windows"))
                    return
                }
                guard let host = DomainMatcher.host(fromURLString: urlString) else {
                    self.emit(.idle(reason: "non-web URL in \(browser.displayName)"))
                    return
                }
                self.emit(.tab(ActiveTab(browser: browser, urlString: urlString, host: host)))
            case .failure(.notPermitted):
                if self.permissionDeniedBundleIDs.insert(browser.bundleID).inserted {
                    Log.error(.tracking, "Automation access denied for \(browser.displayName); cannot read tabs")
                }
                self.emit(.permissionDenied(browser))
            case .failure(.appNotRunning):
                self.emit(.idle(reason: "\(browser.displayName) not running"))
            case .failure(.failed(let code, let message)):
                Log.error(.tracking, "script error \(code) for \(browser.displayName): \(message)")
                self.emit(.idle(reason: "script error \(code)"))
            }
        }
    }

    private func emit(_ sample: WatchSample) {
        switch sample {
        case .tab(let tab):
            Log.verbose(.tracking, "active tab: \(tab.host) in \(tab.browser.displayName)")
        case .idle(let reason):
            Log.verbose(.tracking, "idle: \(reason)")
        case .permissionDenied(let browser):
            Log.verbose(.tracking, "permission denied: \(browser.displayName)")
        }
        onSample?(sample)
    }

    static func isScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as NSDictionary? else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
