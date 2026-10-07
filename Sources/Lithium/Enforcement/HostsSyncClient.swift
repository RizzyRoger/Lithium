import Foundation

/// Publishes the set of blocked domains for the root helper to consume.
///
/// The app never edits `/etc/hosts` itself; it only replaces `blocklist.txt`,
/// which the `com.lithium.hostsd` LaunchDaemon watches. Until-locks go through
/// `pending-locks.txt` so the helper can merge them into a root-owned file.
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

    /// Appends a commitment lock. The helper merges this into root-owned locks.txt
    /// and will not shorten an existing until-day.
    func submitLock(domain: String, untilDay: String) {
        guard isReady else {
            Log.error(.enforcement, "cannot submit lock; helper directory is not writable")
            return
        }
        let line = "\(domain) \(untilDay)\n"
        let url = Paths.pendingLocksFile
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            Log.info(.enforcement, "queued lock \(domain) until \(untilDay)")
        } catch {
            Log.error(.enforcement, "failed writing pending lock: \(error)")
        }
    }

    /// Root-owned locks the helper has already committed. Used to rehydrate the
    /// UI if config.json was edited.
    func readCommittedLocks() -> [String: String] {
        guard let text = try? String(contentsOf: Paths.locksFile, encoding: .utf8) else {
            return [:]
        }
        var result: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.split(separator: "#", maxSplits: 1).first.map(String.init) ?? String(raw)
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2 else { continue }
            let domain = parts[0].lowercased()
            let day = parts[1]
            guard DomainMatcher.isValidDomain(domain), day.count == 10 else { continue }
            if let existing = result[domain], existing >= day { continue }
            result[domain] = day
        }
        return result
    }

    /// Clears the daily blocklist. Commitment locks in locks.txt stay put.
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
