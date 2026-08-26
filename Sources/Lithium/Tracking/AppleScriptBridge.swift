import AppKit
import Foundation

/// A browser Lithium knows how to interrogate over Apple events.
struct Browser: Equatable {
    enum Flavor {
        /// Chromium-family scripting dictionary: `active tab of front window`.
        case chromium
        /// Safari's scripting dictionary: `front document`.
        case safari
    }

    let bundleID: String
    let displayName: String
    let flavor: Flavor

    static let all: [Browser] = [
        Browser(bundleID: "com.apple.Safari", displayName: "Safari", flavor: .safari),
        Browser(bundleID: "com.apple.SafariTechnologyPreview", displayName: "Safari Technology Preview", flavor: .safari),
        Browser(bundleID: "com.google.Chrome", displayName: "Google Chrome", flavor: .chromium),
        Browser(bundleID: "com.google.Chrome.canary", displayName: "Chrome Canary", flavor: .chromium),
        Browser(bundleID: "org.chromium.Chromium", displayName: "Chromium", flavor: .chromium),
        Browser(bundleID: "com.brave.Browser", displayName: "Brave", flavor: .chromium),
        Browser(bundleID: "com.brave.Browser.beta", displayName: "Brave Beta", flavor: .chromium),
        Browser(bundleID: "com.microsoft.edgemac", displayName: "Microsoft Edge", flavor: .chromium),
        Browser(bundleID: "com.vivaldi.Vivaldi", displayName: "Vivaldi", flavor: .chromium),
        Browser(bundleID: "com.operasoftware.Opera", displayName: "Opera", flavor: .chromium),
        Browser(bundleID: "company.thebrowser.Browser", displayName: "Arc", flavor: .chromium),
        Browser(bundleID: "company.thebrowser.dia", displayName: "Dia", flavor: .chromium)
    ]

    static func known(bundleID: String) -> Browser? {
        all.first { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }
}

enum ScriptError: Error, Equatable {
    /// The user has not granted (or has revoked) Automation access for this browser.
    case notPermitted
    /// The target application is not running, so there is nothing to ask.
    case appNotRunning
    case failed(code: Int, message: String)

    var isPermissionProblem: Bool { self == .notPermitted }
}

/// Serializes all Apple event traffic. `NSAppleScript` is not thread safe, so every
/// script runs on this one queue, off the main thread to keep the UI responsive.
final class AppleScriptBridge {
    static let shared = AppleScriptBridge()

    private let queue = DispatchQueue(label: "com.lithium.applescript", qos: .utility)

    private init() {}

    /// Reads the URL shown in the browser's frontmost tab. An empty string means
    /// the browser has no open windows.
    func activeTabURL(of browser: Browser, completion: @escaping (Result<String, ScriptError>) -> Void) {
        let source: String
        switch browser.flavor {
        case .chromium:
            source = """
            tell application id "\(browser.bundleID)"
                if (count of windows) is 0 then return ""
                return URL of active tab of front window
            end tell
            """
        case .safari:
            source = """
            tell application id "\(browser.bundleID)"
                if (count of documents) is 0 then return ""
                return URL of front document
            end tell
            """
        }
        run(source: source, completion: completion)
    }

    /// Navigates the browser's frontmost tab somewhere else.
    func setActiveTabURL(
        of browser: Browser,
        to url: String,
        completion: @escaping (Result<String, ScriptError>) -> Void
    ) {
        let escaped = AppleScriptBridge.escape(url)
        let source: String
        switch browser.flavor {
        case .chromium:
            source = """
            tell application id "\(browser.bundleID)"
                if (count of windows) is 0 then return ""
                set URL of active tab of front window to "\(escaped)"
                return "ok"
            end tell
            """
        case .safari:
            source = """
            tell application id "\(browser.bundleID)"
                if (count of documents) is 0 then return ""
                set URL of front document to "\(escaped)"
                return "ok"
            end tell
            """
        }
        run(source: source, completion: completion)
    }

    private func run(source: String, completion: @escaping (Result<String, ScriptError>) -> Void) {
        queue.async {
            let result = AppleScriptBridge.executeSynchronously(source: source)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func executeSynchronously(source: String) -> Result<String, ScriptError> {
        guard let script = NSAppleScript(source: source) else {
            return .failure(.failed(code: -1, message: "could not compile script"))
        }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? -1
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "unknown"
            switch code {
            case -1743, -10004:
                return .failure(.notPermitted)
            case -600, -609:
                return .failure(.appNotRunning)
            default:
                return .failure(.failed(code: code, message: message))
            }
        }
        return .success(descriptor.stringValue ?? "")
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
