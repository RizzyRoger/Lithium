import Foundation

/// Publishes the set of blocked domains for the root helper to consume.
///
/// The app never edits `/etc/hosts` itself; it only replaces `blocklist.txt`,
/// which the `com.lithium.hostsd` LaunchDaemon watches.
final class HostsSyncClient {
    private var lastWritten: Set<String>?

    /// True when the shared directory exists and is writable by this user, which
    /// is how the app knows the privileged helper has been installed.
    var isReady: Bool {
        FileManager.default.isWritableFile(atPath: Paths.sharedSupportDirectory.path)
    }

    /// Writes the blocklist if it changed. Returns true when a write happened.
    @discardableResult
    func sync(domains: Set<String>, force: Bool = false) -> Bool {
        guard force || domains != lastWritten else {
            Log.verbose(.enforcement, "blocklist unchanged (\(domains.count) domain(s))")
            return false
        }

        guard isReady else {
            // Expected before first-run setup; the redirect layer still works.
            Log.verbose(.enforcement, "blocklist not writable at \(Paths.blocklistFile.path), skipping hosts sync")
            return false
        }

        let header = """
        # Managed by Lithium. Edits here are overwritten.
        # One domain per line; the helper adds www and IPv6 variants.
        """
        let body = domains.sorted().joined(separator: "\n")
        let contents = body.isEmpty ? header + "\n" : header + "\n" + body + "\n"

        do {
            // Atomic replacement also bumps the directory mtime, which is the
            // second WatchPaths trigger for the daemon.
            try Data(contents.utf8).write(to: Paths.blocklistFile, options: .atomic)
            lastWritten = domains
            Log.info(.enforcement, "wrote blocklist with \(domains.count) domain(s): \(domains.sorted().joined(separator: ", "))")
            return true
        } catch {
            Log.error(.enforcement, "failed writing blocklist: \(error)")
            return false
        }
    }

    /// Clears the blocklist, e.g. at midnight or when hosts enforcement is turned off.
    func clear() {
        sync(domains: [], force: true)
    }

    /// Whether `/etc/hosts` currently contains our managed section.
    func hostsFileContainsManagedSection() -> Bool {
        guard let contents = try? String(contentsOf: URL(fileURLWithPath: "/etc/hosts"), encoding: .utf8) else {
            return false
        }
        return contents.contains("# BEGIN LITHIUM")
    }

    func invalidateCache() {
        lastWritten = nil
    }
}
