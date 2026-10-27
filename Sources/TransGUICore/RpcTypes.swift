import Foundation

// MARK: - Endpoint

/// Describes how to reach a Transmission daemon's RPC endpoint.
public struct RpcEndpoint: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var host: String
    public var port: Int
    public var useSSL: Bool
    public var path: String
    public var username: String

    public init(
        name: String,
        host: String,
        port: Int = 9091,
        useSSL: Bool = false,
        path: String = "/transmission/rpc",
        username: String = ""
    ) {
        self.name = name
        self.host = host
        self.port = port
        self.useSSL = useSSL
        self.path = path
        self.username = username
    }

    /// The built-in default endpoint. **Intentionally empty** — no server
    /// address ships with the app; the user configures one in the
    /// connections dialog (profiles persist in UserDefaults).
    public static let `default` = RpcEndpoint(
        name: "Transmission Server",
        host: "",
        port: 9091,
        useSSL: false,
        path: "/transmission/rpc",
        username: ""
    )

    /// True once a server address has been configured.
    public var isConfigured: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The RPC URL, or `nil` when no server address is configured.
    public var rpcURL: URL? {
        guard isConfigured else { return nil }
        var components = URLComponents()
        components.scheme = useSSL ? "https" : "http"
        components.host = host
        components.port = port
        components.path = path.isEmpty ? "/transmission/rpc" : path
        return components.url
    }

    /// Stable account name used for Keychain lookups.
    public var keychainAccount: String {
        "\(username)@\(host):\(port)\(path)"
    }

    /// "Transmission 3.00 at host:port" style caption for the status bar.
    public func statusCaption(version: String?) -> String {
        let v = version.map { "\($0) at " } ?? ""
        return "Transmission \(v)\(host):\(port)"
    }
}

// MARK: - Errors

public enum RpcError: Error, LocalizedError, Equatable {
    case unauthorized
    case sessionConflict
    case notConfigured
    case http(Int)
    case server(String)
    case invalidResponse
    case network(String)
    case encoding(String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Unauthorized. Check the user name and password."
        case .sessionConflict:
            return "Session ID error."
        case .notConfigured:
            return "No server address specified."
        case .http(let code):
            return "HTTP error \(code)."
        case .server(let result):
            return "Server error: \(result)"
        case .invalidResponse:
            return "Invalid server response."
        case .network(let message):
            return message
        case .encoding(let message):
            return "Request encoding failed. (\(message))"
        case .decoding(let message):
            return "Invalid server response. (\(message))"
        }
    }
}
