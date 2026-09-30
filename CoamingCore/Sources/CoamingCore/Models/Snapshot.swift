import Foundation

public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case claude, codex, cursor

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }

    /// Services this build fetches.
    ///
    /// Cursor is omitted unless the binary was built with `COAMING_CURSOR`.
    /// Cursor does not publish a personal usage API. The optional path reads the local
    /// session and polls cursor.com, the call closest to Cursor's rules against automated
    /// access. The default build leaves that out. Passing `COAMING_CURSOR=1` at build time
    /// compiles it in, and that choice belongs to the person building.
    public static var included: [ProviderID] {
        #if COAMING_CURSOR
        [.claude, .codex, .cursor]
        #else
        [.claude, .codex]
        #endif
    }
}

public enum ProviderStatus: String, Codable, Sendable {
    case ok
    case stale
    case needsLogin
    case notInstalled
    case unsupported
    /// Claude: the status line script is not set up and the rate_limits file is missing.
    case notConfigured
}

public enum WindowKind: String, Codable, Sendable {
    case fiveHour, weekly, weeklyModel, billingPlan, billingOnDemand
}

public struct UsageWindow: Codable, Sendable, Equatable {
    public var kind: WindowKind
    public var label: String
    public var usedFraction: Double
    public var resetsAt: Date?

    public init(kind: WindowKind, label: String, usedFraction: Double, resetsAt: Date?) {
        self.kind = kind
        self.label = label
        self.usedFraction = clamp01(usedFraction)
        self.resetsAt = resetsAt
    }
}

public struct ProviderSnapshot: Codable, Sendable, Equatable {
    public var id: ProviderID
    public var displayName: String
    public var status: ProviderStatus
    public var planLabel: String?
    public var windows: [UsageWindow]
    public var fetchedAt: Date?
    public var staleReason: String?

    public init(
        id: ProviderID,
        displayName: String,
        status: ProviderStatus,
        planLabel: String?,
        windows: [UsageWindow],
        fetchedAt: Date?,
        staleReason: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.status = status
        self.planLabel = planLabel
        self.windows = windows
        self.fetchedAt = fetchedAt
        self.staleReason = staleReason
    }

    /// Claude Desktop, including Cowork, writes used percents without reset times and leaves status `.ok`.
    /// The status line setup stays useful until every 5-hour and weekly window has a reset time.
    /// An `.ok` snapshot with no windows means every window passed its reset, and only status line
    /// records carry resets, so it does not ask for the setup again.
    public var needsClaudeResetSetup: Bool {
        guard status == .ok else { return true }
        return windows.contains { ($0.kind == .fiveHour || $0.kind == .weekly) && $0.resetsAt == nil }
    }

    static func make(
        _ id: ProviderID,
        status: ProviderStatus,
        plan: String? = nil,
        windows: [UsageWindow] = [],
        fetchedAt: Date? = nil,
        reason: String? = nil
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            id: id,
            displayName: id.displayName,
            status: status,
            planLabel: plan,
            windows: windows,
            fetchedAt: fetchedAt,
            staleReason: reason
        )
    }
}

public struct Snapshot: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var generatedAt: Date
    public var providers: [ProviderSnapshot]

    public init(schemaVersion: Int, generatedAt: Date, providers: [ProviderSnapshot]) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.providers = providers
    }

    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) -> Snapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = DateParsing.parseISO8601(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "date")
            }
            return date
        }
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data) else { return nil }
        guard snapshot.schemaVersion == currentSchemaVersion else { return nil }
        guard Set(snapshot.providers.map(\.id)).count == snapshot.providers.count else { return nil }
        return snapshot
    }

    public static func waiting(now: Date = Date()) -> Snapshot {
        Snapshot(
            schemaVersion: currentSchemaVersion,
            generatedAt: now,
            providers: ProviderID.included.map {
                .make($0, status: .stale, reason: "waiting")
            }
        )
    }

    public func provider(_ id: ProviderID) -> ProviderSnapshot? {
        providers.first { $0.id == id }
    }

    /// Drops services this build does not fetch, so an older snapshot cannot show them.
    public func keepingIncluded() -> Snapshot {
        let allowed = Set(ProviderID.included)
        return Snapshot(
            schemaVersion: schemaVersion,
            generatedAt: generatedAt,
            providers: providers.filter { allowed.contains($0.id) }
        )
    }
}
