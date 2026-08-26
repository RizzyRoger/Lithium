import Foundation

/// A named snapshot of the whole rule set, so a configuration can be saved and
/// swapped back in later.
struct Preset: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var rules: [SiteRule]
    var createdAt: Date = Date()

    var summary: String {
        let banned = rules.filter { $0.isBanned }.count
        let limited = rules.count - banned
        switch (limited, banned) {
        case (0, 0): return "No rules"
        case (let l, 0): return "\(l) limited"
        case (0, let b): return "\(b) banned"
        case (let l, let b): return "\(l) limited, \(b) banned"
        }
    }
}
