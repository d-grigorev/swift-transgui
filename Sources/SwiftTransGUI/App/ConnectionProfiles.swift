import Foundation
import TransGUICore

/// One saved connection to a Transmission daemon (the reference app keeps
/// these in its ini file's `Connection.<name>` sections; here they are a
/// JSON array in UserDefaults under the `connections` key).
struct ConnectionProfile: Codable, Sendable, Identifiable, Equatable {
    /// Stable identifier (used for the last-used profile and the menu
    /// checkmark; it survives renames).
    var id: String
    var name: String
    var host: String
    var port: Int
    var useSSL: Bool
    var rpcPath: String
    var username: String
    /// Reserved like the reference's `Autoreconnect` setting (unused yet).
    var alwaysReconnect: Bool
    /// The built-in profile for `RpcEndpoint.default`: always present in
    /// the list and never deletable.
    var isDefault: Bool

    static let defaultId = "builtin"

    init(
        id: String = UUID().uuidString,
        name: String,
        host: String,
        port: Int = 9091,
        useSSL: Bool = false,
        rpcPath: String = "/transmission/rpc",
        username: String = "",
        alwaysReconnect: Bool = false,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.useSSL = useSSL
        self.rpcPath = rpcPath
        self.username = username
        self.alwaysReconnect = alwaysReconnect
        self.isDefault = isDefault
    }

    /// The profile for `RpcEndpoint.default` (empty address and username
    /// by default — configured through the connections dialog).
    static let builtin = ConnectionProfile(
        id: defaultId,
        name: RpcEndpoint.default.name,
        host: RpcEndpoint.default.host,
        port: RpcEndpoint.default.port,
        useSSL: RpcEndpoint.default.useSSL,
        rpcPath: RpcEndpoint.default.path,
        username: RpcEndpoint.default.username,
        alwaysReconnect: false,
        isDefault: true
    )

    /// A blank profile for the "New connection to Transmission" dialog
    /// (port 9091 like the reference's spin-edit default).
    static func blank() -> ConnectionProfile {
        ConnectionProfile(name: "", host: "", port: 9091)
    }

    /// The RPC path with the Transmission default filled in for blanks.
    var normalizedRpcPath: String {
        rpcPath.isEmpty ? "/transmission/rpc" : rpcPath
    }

    var endpoint: RpcEndpoint {
        RpcEndpoint(
            name: name,
            host: host,
            port: port,
            useSSL: useSSL,
            path: normalizedRpcPath,
            username: username
        )
    }

    /// True when both profiles would talk to the same daemon with the same
    /// credentials (the display name is irrelevant for connecting).
    func hasSameConnection(as other: ConnectionProfile) -> Bool {
        host == other.host
            && port == other.port
            && useSSL == other.useSSL
            && normalizedRpcPath == other.normalizedRpcPath
            && username == other.username
    }

    /// Same question against a live endpoint (the path falls back to the
    /// default RPC path when the endpoint stores an empty one).
    func hasSameConnection(as endpoint: RpcEndpoint) -> Bool {
        host == endpoint.host
            && port == endpoint.port
            && useSSL == endpoint.useSSL
            && normalizedRpcPath == (endpoint.path.isEmpty ? "/transmission/rpc" : endpoint.path)
            && username == endpoint.username
    }

    /// The name shown by the combo box (a blank new profile falls back to
    /// its host like the reference app).
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return host.trimmingCharacters(in: .whitespaces)
    }
}

/// Which dialog flavor the "Manage connections" sheet opens in.
enum ManageConnectionsMode: Sendable {
    /// Caption `Manage connections to Transmission`.
    case manage
    /// Caption `New connection to Transmission`, starting with a blank
    /// profile in rename mode.
    case new
}

/// Persistence for the connection profiles (UserDefaults key `connections`).
enum ConnectionProfileStore {
    static let key = "connections"
    static let lastProfileKey = "LastConnectionProfile"

    /// The stored profiles with the built-in default guaranteed to be
    /// present (prepended when missing or when the store was never written).
    static func load() -> [ConnectionProfile] {
        var profiles: [ConnectionProfile] = []
        if let data = UserDefaults.standard.data(forKey: key) {
            profiles = (try? JSONDecoder().decode([ConnectionProfile].self, from: data)) ?? []
        }
        if let index = profiles.firstIndex(where: { $0.isDefault }) {
            // Keep the built-in profile first, whatever order it was saved in.
            let builtin = profiles.remove(at: index)
            profiles.insert(builtin, at: 0)
        } else {
            profiles.insert(.builtin, at: 0)
        }
        return profiles
    }

    static func save(_ profiles: [ConnectionProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static var lastProfileId: String? {
        get { UserDefaults.standard.string(forKey: lastProfileKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastProfileKey) }
    }
}

// MARK: - AppModel: profiles

extension AppModel {
    /// Present the connections dialog (`new` starts with a blank profile).
    func presentManageConnections(mode: ManageConnectionsMode) {
        manageConnectionsMode = mode
        showManageConnections = true
    }

    /// Connect to `profile`: switches the endpoint (disconnecting first when
    /// a live session would change) and prompts for a password when none is
    /// stored for the profile's Keychain account.
    func connect(to profile: ConnectionProfile) async {
        if case .connecting = phase {
            disconnect()
        }
        if phase.isConnected {
            // Clicking the already-connected profile does nothing (like the
            // reference app's connection menu).
            if profile.id == currentProfileId, profile.hasSameConnection(as: endpoint) {
                return
            }
            disconnect()
        }
        activate(profile)
        await connect()
    }

    /// The connections dialog was confirmed: persist the (possibly edited,
    /// renamed or deleted) list and reconnect when the live session's
    /// endpoint changed.
    func updateProfiles(_ newProfiles: [ConnectionProfile]) async {
        let oldActive = profiles.first { $0.id == currentProfileId }
        ConnectionProfileStore.save(newProfiles)
        profiles = newProfiles

        let active: ConnectionProfile
        if let existing = newProfiles.first(where: { $0.id == currentProfileId }) {
            active = existing
        } else {
            // The active profile was deleted: fall back to the built-in one.
            active = newProfiles.first { $0.isDefault } ?? newProfiles[0]
            activate(active)
            if phase.isConnected {
                disconnect()
                await connect()
            }
            return
        }

        let endpointChanged = oldActive.map { !$0.hasSameConnection(as: active) } ?? false
        let wasConfigured = oldActive?.endpoint.isConfigured ?? false
        activate(active)
        if endpointChanged {
            if phase.isConnected {
                disconnect()
                await connect()
            } else if !wasConfigured, active.endpoint.isConfigured {
                // First-run flow: the address was just configured — continue
                // with the connection (prompts for the password if needed).
                await connect()
            }
        }
    }

    /// Remember `profile` as the current one and point `endpoint` at it.
    private func activate(_ profile: ConnectionProfile) {
        currentProfileId = profile.id
        ConnectionProfileStore.lastProfileId = profile.id
        endpoint = profile.endpoint
    }

    /// The profile whose endpoint `endpoint` currently describes.
    var activeProfile: ConnectionProfile {
        profiles.first { $0.id == currentProfileId } ?? .builtin
    }
}
