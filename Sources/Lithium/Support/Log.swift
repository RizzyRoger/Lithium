import Foundation
import os

/// Logging goes to both the unified log and `~/Library/Logs/Lithium.log`, since a
/// menu bar app has no console to watch and `tail -f` on the file is the fastest
/// way to see what the watcher is doing.
enum Log {
    enum Category: String {
        case app, store, tracking, enforcement, server, helper, ui
    }

    /// Verbose per-tick tracking output, off unless LITHIUM_VERBOSE is set.
    static var verboseEnabled: Bool = ProcessInfo.processInfo.environment["LITHIUM_VERBOSE"] != nil

    private static let loggers: [Category: Logger] = {
        var result: [Category: Logger] = [:]
        for category in [Category.app, .store, .tracking, .enforcement, .server, .helper, .ui] {
            result[category] = Logger(subsystem: Paths.bundleIdentifier, category: category.rawValue)
        }
        return result
    }()

    private static let fileQueue = DispatchQueue(label: "com.lithium.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func info(_ category: Category, _ message: String) {
        loggers[category]?.info("\(message, privacy: .public)")
        append(level: "INFO ", category: category, message: message)
    }

    static func error(_ category: Category, _ message: String) {
        loggers[category]?.error("\(message, privacy: .public)")
        append(level: "ERROR", category: category, message: message)
    }

    static func verbose(_ category: Category, _ message: @autoclosure () -> String) {
        guard verboseEnabled else { return }
        let text = message()
        loggers[category]?.debug("\(text, privacy: .public)")
        append(level: "DEBUG", category: category, message: text)
    }

    private static func append(level: String, category: Category, message: String) {
        let line = "\(formatter.string(from: Date())) \(level) [\(category.rawValue)] \(message)\n"
        fileQueue.async {
            guard let data = line.data(using: .utf8) else { return }
            let url = Paths.logFile
            let fm = FileManager.default
            if !fm.fileExists(atPath: url.path) {
                try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                fm.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            // Keep the log from growing without bound across long uptimes.
            if let size = try? handle.seekToEnd(), size > 4_000_000 {
                try? handle.truncate(atOffset: 0)
            }
            try? handle.write(contentsOf: data)
        }
    }
}
