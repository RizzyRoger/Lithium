import Foundation

/// A single JSON file on disk holding one `Codable` value.
struct JSONFile<Value: Codable> {
    let url: URL
    let label: String

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func load(default fallback: Value) -> Value {
        guard FileManager.default.fileExists(atPath: url.path) else {
            Log.info(.store, "\(label): no file at \(url.path), starting fresh")
            return fallback
        }
        do {
            let data = try Data(contentsOf: url)
            return try Self.decoder.decode(Value.self, from: data)
        } catch {
            // Keep the unreadable file around instead of silently overwriting it.
            let backup = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: backup)
            Log.error(.store, "\(label): decode failed (\(error)), moved to \(backup.lastPathComponent)")
            return fallback
        }
    }

    func save(_ value: Value) {
        do {
            Paths.ensureUserDirectories()
            let data = try Self.encoder.encode(value)
            try data.write(to: url, options: .atomic)
            Log.verbose(.store, "\(label): wrote \(data.count) bytes")
        } catch {
            Log.error(.store, "\(label): write failed: \(error)")
        }
    }
}
