import Foundation

/// Launch at login via a per-user LaunchAgent.
///
/// `SMAppService.mainApp` needs a stable Developer ID signature to be reliable;
/// a LaunchAgent plist works for an ad-hoc signed app in any location.
enum LoginItem {
    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: Paths.launchAgentPlist.path)
    }

    static func setEnabled(_ enabled: Bool) {
        enabled ? enable() : disable()
    }

    private static func enable() {
        guard let executable = currentExecutablePath() else {
            Log.error(.app, "cannot enable launch at login: executable path unknown")
            return
        }
        let plist: [String: Any] = [
            "Label": "com.lithium.app",
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive"
        ]
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try FileManager.default.createDirectory(
                at: Paths.launchAgentPlist.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: Paths.launchAgentPlist, options: .atomic)
            Log.info(.app, "launch at login enabled for \(executable)")
        } catch {
            Log.error(.app, "failed writing launch agent: \(error)")
        }
    }

    private static func disable() {
        do {
            if FileManager.default.fileExists(atPath: Paths.launchAgentPlist.path) {
                try FileManager.default.removeItem(at: Paths.launchAgentPlist)
            }
            Log.info(.app, "launch at login disabled")
        } catch {
            Log.error(.app, "failed removing launch agent: \(error)")
        }
    }

    /// Path to the executable inside the bundle, which is what launchd must run.
    private static func currentExecutablePath() -> String? {
        if let executable = Bundle.main.executableURL {
            return executable.resolvingSymlinksInPath().path
        }
        return CommandLine.arguments.first
    }
}
