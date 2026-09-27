import Foundation

public enum CoamingLive {
    public static func makeRefresher(previous: Snapshot?) -> Refresher {
        let paths = ToolPaths.live()
        let defaults = PreferenceStore.defaults()
        let userAgent = widgetUserAgent()
        let http = EphemeralHTTPClient()
        let providers = makeProviders(paths: paths, userAgent: userAgent, http: http)
        return Refresher(providers: providers, previous: previous, backoff: DefaultsBackoffStore(defaults: defaults))
    }

    static func makeProviders(paths: ToolPaths, userAgent: String, http: any HTTPClient) -> [any UsageProvider] {
        let keychain = KeychainClient.live()
        let claude = ClaudeProvider(read: { claudeReader(paths).read() })
        let codex = CodexProvider(
            userAgent: userAgent,
            http: http,
            read: {
                CodexCredentialReader(authFileURL: paths.codexAuth, sessionsDirectoryURL: paths.codexSessions).read()
            }
        )
        let cursor = CursorProvider(
            userAgent: userAgent,
            http: http,
            supportDirectoryURL: paths.cursorSupport,
            read: {
                CursorCredentialReader(databaseURL: paths.cursorDatabase, keychain: keychain).read()
            }
        )
        return [claude, codex, cursor]
    }

    static func claudeReader(_ paths: ToolPaths) -> ClaudeRateLimitReader {
        ClaudeRateLimitReader(
            fileURL: paths.claudeRateLimits,
            desktopFileURL: paths.claudeDesktopUsageHistory,
            directoryURL: paths.claudeDirectory,
            desktopDirectoryURL: paths.claudeDesktopDirectory,
            binaryExists: paths.claudeBinaryExists
        )
    }
}

public struct CredentialReport: Sendable, Equatable {
    public var provider: String
    public var availability: String
    public var expiry: String
    public var plan: String
}

public enum CredentialChecker {
    public static func check(now: Date = Date()) -> [CredentialReport] {
        let paths = ToolPaths.live()
        let keychain = KeychainClient.live()
        let claude = CoamingLive.claudeReader(paths).read()
        let codex = CodexCredentialReader(authFileURL: paths.codexAuth, sessionsDirectoryURL: paths.codexSessions).read()
        let cursorRead = CursorCredentialReader(databaseURL: paths.cursorDatabase, keychain: keychain).read()
        let cursorInstalled = FileManager.default.fileExists(atPath: paths.cursorSupport.path)
        return [
            report("Claude", claude: claude, now: now),
            report("Codex", codex: codex, now: now),
            report("Cursor", cursor: cursorRead, installed: cursorInstalled, now: now),
        ]
    }

    public static func lines(now: Date = Date()) -> [String] {
        check(now: now).map { "\($0.provider): \($0.availability), \($0.expiry), \($0.plan)" }
    }

    private static func report(_ name: String, claude: ClaudeRead, now: Date) -> CredentialReport {
        switch claude {
        case .notInstalled:
            return CredentialReport(provider: name, availability: "not installed", expiry: "—", plan: "—")
        case .notConfigured:
            return CredentialReport(provider: name, availability: "no data yet (run Claude Desktop or set up the status line)", expiry: "—", plan: "—")
        case .found(let limits):
            return CredentialReport(provider: name, availability: "found", expiry: "updated \(DateParsing.iso8601(limits.writtenAt))", plan: "—")
        }
    }

    private static func report(_ name: String, codex: CodexRead, now: Date) -> CredentialReport {
        switch codex {
        case .notInstalled:
            return CredentialReport(provider: name, availability: "not installed", expiry: "—", plan: "—")
        case .unsupported:
            return CredentialReport(provider: name, availability: "unsupported", expiry: "—", plan: "—")
        case .needsLogin:
            return CredentialReport(provider: name, availability: "missing", expiry: "—", plan: "—")
        case .found(let credential):
            return found(name, expiresAt: credential.expiresAt, plan: "—", now: now)
        }
    }

    private static func report(_ name: String, cursor: CursorTokenRead, installed: Bool, now: Date) -> CredentialReport {
        switch cursor {
        case .busy:
            return CredentialReport(provider: name, availability: "missing", expiry: "—", plan: "—")
        case .missing:
            return CredentialReport(
                provider: name,
                availability: installed ? "missing" : "not installed",
                expiry: "—",
                plan: "—"
            )
        case .found(let credential):
            let plan = credential.membershipType.map(Constants.capitalize) ?? "—"
            return found(name, expiresAt: credential.expiresAt, plan: plan, now: now)
        }
    }

    private static func found(_ name: String, expiresAt: Date?, plan: String, now: Date) -> CredentialReport {
        let expiry: String
        if let expiresAt {
            expiry = expiresAt <= now ? "expired" : "until \(DateParsing.day(expiresAt))"
        } else {
            expiry = "expiry unknown"
        }
        return CredentialReport(provider: name, availability: "found", expiry: expiry, plan: plan)
    }
}
