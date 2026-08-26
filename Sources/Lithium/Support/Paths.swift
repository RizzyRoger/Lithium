import Foundation

/// Every on-disk location Lithium touches.
enum Paths {
    static let bundleIdentifier = "com.lithium.app"
    static let daemonLabel = "com.lithium.hostsd"

    /// Per-user state: rules, presets, usage counters.
    static var userSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Lithium", isDirectory: true)
    }

    static var configFile: URL { userSupportDirectory.appendingPathComponent("config.json") }
    static var usageFile: URL { userSupportDirectory.appendingPathComponent("usage.json") }

    /// Shared with the root helper. Created by the installer and chowned to the
    /// installing user so the unprivileged app can replace the blocklist.
    static let sharedSupportDirectory = URL(fileURLWithPath: "/Library/Application Support/Lithium", isDirectory: true)
    static var blocklistFile: URL { sharedSupportDirectory.appendingPathComponent("blocklist.txt") }

    static let helperExecutable = URL(fileURLWithPath: "/usr/local/libexec/lithium-hostsd")
    static let daemonPlist = URL(fileURLWithPath: "/Library/LaunchDaemons/com.lithium.hostsd.plist")

    static var launchAgentPlist: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/com.lithium.app.plist")
    }

    static var logFile: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Logs/Lithium.log")
    }

    static func ensureUserDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: userSupportDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
}
