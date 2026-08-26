import AppKit
import Foundation

/// Installs (and removes) the root helper and its LaunchDaemon.
///
/// There is no Developer ID certificate here, so `SMAppService` is unavailable.
/// Instead a generated script is run once through `do shell script ... with
/// administrator privileges`, which costs exactly one admin prompt.
enum PrivilegedInstaller {
    enum InstallError: LocalizedError {
        case resourcesMissing
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .resourcesMissing:
                return "The bundled helper files are missing. Rebuild Lithium with Scripts/build-app.sh."
            case .cancelled:
                return "Authorization was cancelled."
            case .failed(let message):
                return message
            }
        }
    }

    struct Status {
        var helperInstalled: Bool
        var daemonInstalled: Bool
        var blocklistWritable: Bool

        var isFullyInstalled: Bool { helperInstalled && daemonInstalled && blocklistWritable }
    }

    static func status() -> Status {
        let fm = FileManager.default
        return Status(
            helperInstalled: fm.isExecutableFile(atPath: Paths.helperExecutable.path),
            daemonInstalled: fm.fileExists(atPath: Paths.daemonPlist.path),
            blocklistWritable: fm.isWritableFile(atPath: Paths.sharedSupportDirectory.path)
        )
    }

    static func install(completion: @escaping (Result<Void, InstallError>) -> Void) {
        guard let helperSource = bundledResource(named: "lithium-hostsd"),
              let plistSource = bundledResource(named: "com.lithium.hostsd.plist")
        else {
            Log.error(.helper, "bundled helper resources not found")
            completion(.failure(.resourcesMissing))
            return
        }

        let uid = getuid()
        let gid = getgid()
        let supportDir = Paths.sharedSupportDirectory.path
        let blocklist = Paths.blocklistFile.path

        let script = """
        #!/bin/bash
        set -euo pipefail

        install -d -m 755 /usr/local/libexec
        install -m 755 -o root -g wheel \(quote(helperSource.path)) \(quote(Paths.helperExecutable.path))

        install -d -m 755 \(quote(supportDir))
        chown \(uid):\(gid) \(quote(supportDir))
        if [ ! -f \(quote(blocklist)) ]; then
            : > \(quote(blocklist))
        fi
        chown \(uid):\(gid) \(quote(blocklist))
        chmod 644 \(quote(blocklist))

        touch /var/log/lithium-hostsd.log
        chmod 644 /var/log/lithium-hostsd.log

        install -m 644 -o root -g wheel \(quote(plistSource.path)) \(quote(Paths.daemonPlist.path))
        launchctl bootout system/\(Paths.daemonLabel) 2>/dev/null || true
        launchctl bootstrap system \(quote(Paths.daemonPlist.path))
        """

        run(script: script, describedAs: "install") { result in
            switch result {
            case .success:
                Log.info(.helper, "helper and daemon installed")
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    static func uninstall(completion: @escaping (Result<Void, InstallError>) -> Void) {
        let blocklist = Paths.blocklistFile.path
        let script = """
        #!/bin/bash
        set -uo pipefail

        # Clear our /etc/hosts section before the helper goes away.
        if [ -f \(quote(blocklist)) ]; then
            : > \(quote(blocklist))
        fi
        if [ -x \(quote(Paths.helperExecutable.path)) ]; then
            \(quote(Paths.helperExecutable.path)) || true
        fi

        launchctl bootout system/\(Paths.daemonLabel) 2>/dev/null || true
        rm -f \(quote(Paths.daemonPlist.path))
        rm -f \(quote(Paths.helperExecutable.path))
        rm -rf \(quote(Paths.sharedSupportDirectory.path))
        exit 0
        """

        run(script: script, describedAs: "uninstall") { result in
            switch result {
            case .success:
                Log.info(.helper, "helper and daemon removed")
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Writes the script to a path with no shell-special characters and runs it
    /// as root through one authorization prompt.
    private static func run(
        script: String,
        describedAs label: String,
        completion: @escaping (Result<Void, InstallError>) -> Void
    ) {
        let scriptURL = URL(fileURLWithPath: "/tmp/lithium-\(label)-\(UUID().uuidString).sh")
        do {
            try Data(script.utf8).write(to: scriptURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        } catch {
            completion(.failure(.failed("Could not stage the \(label) script: \(error.localizedDescription)")))
            return
        }

        // The prompt must be able to come to the front from an accessory app.
        NSApp.activate(ignoringOtherApps: true)

        let source = """
        do shell script "/bin/bash \(scriptURL.path)" with administrator privileges
        """

        DispatchQueue.global(qos: .userInitiated).async {
            var errorInfo: NSDictionary?
            let appleScript = NSAppleScript(source: source)
            _ = appleScript?.executeAndReturnError(&errorInfo)
            try? FileManager.default.removeItem(at: scriptURL)

            let outcome: Result<Void, InstallError>
            if let errorInfo {
                let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? -1
                let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "unknown error"
                if code == -128 {
                    Log.info(.helper, "\(label) cancelled by user")
                    outcome = .failure(.cancelled)
                } else {
                    Log.error(.helper, "\(label) failed (\(code)): \(message)")
                    outcome = .failure(.failed(message))
                }
            } else {
                outcome = .success(())
            }
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    /// Bundled resources live in `Contents/Resources`; when running the bare
    /// SwiftPM binary they sit next to the executable or in `Scripts/`.
    private static func bundledResource(named name: String) -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent(name))
        }
        let executableDir = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        candidates.append(executableDir.appendingPathComponent(name))
        candidates.append(
            executableDir
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Scripts/\(name)")
        )
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }

    private static func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
