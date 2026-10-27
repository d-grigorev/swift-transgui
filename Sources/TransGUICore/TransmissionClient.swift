import Foundation

/// JSON-RPC client for a Transmission daemon.
///
/// Handles HTTP Basic authentication and the `X-Transmission-Session-Id`
/// handshake (the daemon answers 409 on the first request; we capture the
/// header and retry, like any compliant Transmission RPC client).
public actor TransmissionClient {
    private let endpoint: RpcEndpoint
    private let password: String
    private let session: URLSession
    private var sessionId: String?

    private static let maxRetries = 3

    public init(endpoint: RpcEndpoint, password: String, session: URLSession? = nil) {
        self.endpoint = endpoint
        self.password = password
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 300
            config.httpAdditionalHeaders = ["Accept-Encoding": "gzip"]
            self.session = URLSession(configuration: config)
        }
    }

    /// Call an RPC method without arguments.
    public func call<R: Decodable & Sendable>(method: String) async throws -> R {
        try await call(method: method, arguments: EmptyArguments())
    }

    /// Call an RPC method with typed arguments, returning decoded `arguments`.
    public func call<A: Encodable & Sendable, R: Decodable & Sendable>(
        method: String,
        arguments: A
    ) async throws -> R {
        try await invoke(method: method, arguments: arguments)
    }

    /// Fetch torrents (`torrent-get`), unwrapping the `arguments.torrents` list.
    public func getTorrents(fields: [String], ids: [Int]? = nil) async throws -> [Torrent] {
        let response: TorrentListResponse = try await invoke(
            method: "torrent-get",
            arguments: TorrentGetArgs(fields: fields, ids: ids)
        )
        return response.torrents
    }

    /// Fetch one torrent (`torrent-get` for a single id); the daemon always
    /// wraps the row in `arguments.torrents`, even for a single id.
    public func getTorrentDetails(fields: [String], ids: [Int]) async throws -> Torrent {
        let rows = try await getTorrents(fields: fields, ids: ids)
        guard let torrent = rows.first else {
            throw RpcError.server("torrent-get returned no rows")
        }
        return torrent
    }

    private func invoke<A: Encodable & Sendable, R: Decodable & Sendable>(
        method: String,
        arguments: A
    ) async throws -> R {
        let body: Data
        do {
            body = try JSONEncoder().encode(RpcRequest(method: method, arguments: arguments))
        } catch {
            throw RpcError.encoding(String(describing: error))
        }

        var lastError: RpcError = .sessionConflict
        guard let url = endpoint.rpcURL else {
            throw RpcError.notConfigured
        }

        for _ in 0..<Self.maxRetries {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let auth = Data("\(endpoint.username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
            if let sessionId {
                request.setValue(sessionId, forHTTPHeaderField: "X-Transmission-Session-Id")
            }
            request.httpBody = body

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch let error as URLError {
                throw RpcError.network(Self.describe(error))
            } catch {
                throw RpcError.network(error.localizedDescription)
            }

            guard let http = response as? HTTPURLResponse else {
                throw RpcError.invalidResponse
            }

            switch http.statusCode {
            case 200:
                return try Self.decode(data: data)
            case 401:
                throw RpcError.unauthorized
            case 409:
                if let sid = http.value(forHTTPHeaderField: "X-Transmission-Session-Id"),
                   !sid.isEmpty {
                    sessionId = sid
                    lastError = .sessionConflict
                    continue
                }
                lastError = .sessionConflict
            case 301, 302, 307, 308:
                // Redirects are followed by URLSession for GET; for POST we treat
                // it as a bad path configuration error.
                lastError = .http(http.statusCode)
            default:
                lastError = .http(http.statusCode)
            }
        }
        throw lastError
    }

    // MARK: - Helpers

    private struct RpcRequest<A: Encodable>: Encodable {
        let method: String
        let arguments: A
    }

    private struct RpcEnvelope<A: Decodable>: Decodable {
        let result: String?
        let arguments: A?
    }

    private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .cannotConnectToHost, .networkConnectionLost, .timedOut:
            return "Connection error occurred: \(error.localizedDescription)"
        case .userAuthenticationRequired, .badServerResponse:
            return error.localizedDescription
        default:
            return error.localizedDescription
        }
    }
}

// Generic decode implemented as a free function to keep the actor's method
// dispatch simple.
extension TransmissionClient {
    fileprivate static func decode<A: Decodable>(data: Data) throws -> A {
        let envelope: RpcEnvelope<A>
        do {
            envelope = try JSONDecoder().decode(RpcEnvelope<A>.self, from: data)
        } catch {
            // HTML or garbage body from an intermediary.
            let text = String(data: data, prefix: 200)
            if text.contains("<html") || text.contains("<h1>") {
                throw RpcError.invalidResponse
            }
            throw RpcError.decoding(String(describing: error))
        }

        guard let result = envelope.result?.lowercased(), result == "success" else {
            throw RpcError.server(envelope.result ?? "unknown")
        }
        guard let arguments = envelope.arguments else {
            throw RpcError.invalidResponse
        }
        return arguments
    }
}

private extension String {
    init(data: Data, prefix: Int) {
        let slice = data.prefix(prefix)
        self = String(decoding: slice, as: UTF8.self)
    }
}
