import Foundation
import Network

/// Minimal loopback HTTP server that serves the "Site Blocked for the day" page.
///
/// Blocked tabs are navigated here, which is what makes the block visible and
/// legible instead of a browser connection error.
final class BlockPageServer {
    private var listener: NWListener?
    private var remainingPorts: [UInt16] = []
    private(set) var port: UInt16?

    private static let candidatePorts: [UInt16] = [8787, 8788, 8789, 8790, 8791]

    var isRunning: Bool { port != nil }

    func start() {
        guard listener == nil else { return }
        remainingPorts = BlockPageServer.candidatePorts
        startNextPort()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = nil
    }

    /// URL a blocked tab should be sent to.
    func blockURL(domain: String, reason: BlockReason, used: TimeInterval, limit: TimeInterval?) -> String? {
        guard let port else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.path = "/blocked"
        var items = [
            URLQueryItem(name: "d", value: domain),
            URLQueryItem(name: "r", value: reason.rawValue),
            URLQueryItem(name: "used", value: String(Int(used.rounded())))
        ]
        if let limit {
            items.append(URLQueryItem(name: "limit", value: String(Int(limit.rounded()))))
        }
        components.queryItems = items
        return components.string
    }

    private func startNextPort() {
        guard !remainingPorts.isEmpty else {
            Log.error(.server, "no candidate port available; block page will be unavailable")
            return
        }
        let candidate = remainingPorts.removeFirst()
        guard let nwPort = NWEndpoint.Port(rawValue: candidate) else {
            startNextPort()
            return
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Bind to loopback so nothing outside this Mac can reach the page.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)

        do {
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.port = candidate
                    Log.info(.server, "block page server listening on 127.0.0.1:\(candidate)")
                case .failed(let error):
                    Log.error(.server, "listener on port \(candidate) failed: \(error)")
                    listener.cancel()
                    self.listener = nil
                    self.startNextPort()
                case .cancelled:
                    if self.port == candidate { self.port = nil }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            Log.error(.server, "could not create listener on port \(candidate): \(error)")
            startNextPort()
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, isComplete, error in
            if let error {
                Log.verbose(.server, "receive error: \(error)")
                connection.cancel()
                return
            }
            guard let data, !data.isEmpty else {
                if isComplete { connection.cancel() }
                return
            }
            let request = String(decoding: data, as: UTF8.self)
            let target = BlockPageServer.requestTarget(from: request)
            let response = BlockPageServer.response(for: target)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    /// Pulls the path and query out of the request line, e.g. `/blocked?d=x`.
    private static func requestTarget(from request: String) -> String {
        guard let firstLine = request.split(separator: "\r\n", maxSplits: 1).first
                ?? request.split(separator: "\n", maxSplits: 1).first
        else { return "/" }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return "/" }
        return String(parts[1])
    }

    private static func response(for target: String) -> Data {
        let components = URLComponents(string: "http://127.0.0.1" + target)
        let path = components?.path ?? "/"

        if path == "/health" {
            return httpResponse(status: "200 OK", contentType: "text/plain; charset=utf-8", body: Data("ok".utf8))
        }

        let query = components?.queryItems ?? []
        func value(_ name: String) -> String? {
            query.first { $0.name == name }?.value
        }

        let domain = value("d") ?? "This site"
        let reason = BlockReason(rawValue: value("r") ?? "") ?? .banned
        let used = TimeInterval(value("used") ?? "") ?? 0
        let limit = TimeInterval(value("limit") ?? "")

        let html = BlockPage.html(domain: domain, reason: reason, used: used, limit: limit)
        return httpResponse(status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(html.utf8))
    }

    private static func httpResponse(status: String, contentType: String, body: Data) -> Data {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store, must-revalidate\r\n"
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }
}

enum BlockReason: String {
    case limitReached = "limit"
    case banned = "ban"
}
