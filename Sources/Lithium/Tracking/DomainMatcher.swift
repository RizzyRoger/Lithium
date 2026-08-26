import Foundation

/// Turns whatever the user typed, or whatever a browser reports as the current
/// URL, into a bare lowercase domain.
enum DomainMatcher {
    /// Extracts the host from a full URL string. Returns nil for non-web URLs
    /// such as `chrome://`, `about:`, or the local block page.
    static func host(fromURLString raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty
        else { return nil }
        return strippingWWW(host)
    }

    /// Normalizes free-form user input into a domain, or nil if it cannot be one.
    static func normalize(userInput raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }

        if let range = text.range(of: "://") {
            text = String(text[range.upperBound...])
        }
        // Drop userinfo, path, query and fragment.
        if let at = text.lastIndex(of: "@"), text.firstIndex(of: "/").map({ at < $0 }) ?? true {
            text = String(text[text.index(after: at)...])
        }
        for separator in ["/", "?", "#"] {
            if let index = text.firstIndex(of: Character(separator)) {
                text = String(text[..<index])
            }
        }
        if let colon = text.firstIndex(of: ":") {
            text = String(text[..<colon])
        }
        text = strippingWWW(text)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        return isValidDomain(text) ? text : nil
    }

    static func strippingWWW(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func isValidDomain(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 253 else { return false }
        let labels = text.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        for label in labels {
            guard (1...63).contains(label.count) else { return false }
            guard !label.hasPrefix("-"), !label.hasSuffix("-") else { return false }
            let allowed = label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
            guard allowed else { return false }
        }
        // Require a plausible alphabetic TLD so "1.2" is not treated as a site.
        guard let tld = labels.last, tld.count >= 2,
              tld.allSatisfy({ $0.isASCII && $0.isLetter })
        else { return false }
        return true
    }
}
