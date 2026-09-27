import Foundation

public enum PreferenceKey {
    public static let suiteName = "io.github.toritori0318.agentcoaming"
    public static let menuBarVisible = "menuBarVisible"
    public static let overlayVisible = "overlayVisible"
    public static let overlayOriginX = "overlayOriginX"
    public static let overlayOriginY = "overlayOriginY"
    public static let language = "language"

    public static func providerEnabled(_ id: ProviderID) -> String {
        "enabled.\(id.rawValue)"
    }

    public static func rateLimit(_ id: ProviderID) -> String {
        "rateLimit.\(id.rawValue)"
    }
}

public enum PreferenceStore {
    public static func defaults() -> UserDefaults {
        UserDefaults(suiteName: PreferenceKey.suiteName) ?? .standard
    }
}

struct BackoffState: Codable, Sendable, Equatable {
    var blockedUntil: Date?
    var consecutive429: Int
    var lastAttemptAt: Date?

    static let empty = BackoffState(blockedUntil: nil, consecutive429: 0, lastAttemptAt: nil)
}

protocol BackoffStore: Sendable {
    func load(_ id: ProviderID) -> BackoffState
    func save(_ id: ProviderID, _ state: BackoffState)
}

final class MemoryBackoffStore: BackoffStore, @unchecked Sendable {
    private let lock = NSLock()
    private var states: [ProviderID: BackoffState] = [:]

    func load(_ id: ProviderID) -> BackoffState {
        lock.lock()
        defer { lock.unlock() }
        return states[id] ?? .empty
    }

    func save(_ id: ProviderID, _ state: BackoffState) {
        lock.lock()
        defer { lock.unlock() }
        states[id] = state
    }
}

final class DefaultsBackoffStore: BackoffStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load(_ id: ProviderID) -> BackoffState {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: PreferenceKey.rateLimit(id)) else { return .empty }
        return (try? JSONDecoder().decode(BackoffState.self, from: data)) ?? .empty
    }

    func save(_ id: ProviderID, _ state: BackoffState) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: PreferenceKey.rateLimit(id))
    }
}
