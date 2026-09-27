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
        let claude = ClaudeProvider(read: { claudeReader(paths).read() })
        let codex = CodexProvider(
            locate: {
                CodexBinary.candidates(home: paths.home, environment: paths.environment).first.map { URL(fileURLWithPath: $0) }
            },
            ask: { executable, now in
                await CodexAppServer.ask(executable: executable, now: now)
            }
        )
        var providers: [any UsageProvider] = [claude, codex]
        // Optional Cursor path. The default build does not read Cursor or call cursor.com. See ProviderID.included.
        #if COAMING_CURSOR
        let keychain = KeychainClient.live()
        providers.append(CursorProvider(
            userAgent: userAgent,
            http: http,
            supportDirectoryURL: paths.cursorSupport,
            read: {
                CursorCredentialReader(databaseURL: paths.cursorDatabase, keychain: keychain).read()
            }
        ))
        #endif
        return providers
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
    public static func check(now: Date = Date()) async -> [CredentialReport] {
        let paths = ToolPaths.live()
        let claude = CoamingLive.claudeReader(paths).read()
        let codex = await codexReport(paths: paths, now: now)
        var reports = [
            report("Claude", claude: claude, now: now),
            codex,
        ]
        #if COAMING_CURSOR
        let keychain = KeychainClient.live()
        let cursorRead = CursorCredentialReader(databaseURL: paths.cursorDatabase, keychain: keychain).read()
        let cursorInstalled = FileManager.default.fileExists(atPath: paths.cursorSupport.path)
        reports.append(report("Cursor", cursor: cursorRead, installed: cursorInstalled, now: now))
        #endif
        return reports
    }

    public static func lines(now: Date = Date()) async -> [String] {
        await check(now: now).map { "\($0.provider): \($0.availability), \($0.expiry), \($0.plan)" }
    }

    private static func codexReport(paths: ToolPaths, now: Date) async -> CredentialReport {
        guard let path = CodexBinary.candidates(home: paths.home, environment: paths.environment).first else {
            return CredentialReport(provider: "Codex", availability: "not installed", expiry: "—", plan: "—")
        }
        switch await CodexAppServer.ask(executable: URL(fileURLWithPath: path), now: now) {
        case .usage(let parsed):
            return CredentialReport(provider: "Codex", availability: "found", expiry: "—", plan: parsed.planLabel ?? "—")
        case .needsLogin:
            return CredentialReport(provider: "Codex", availability: "missing", expiry: "—", plan: "—")
        case .unsupported:
            return CredentialReport(provider: "Codex", availability: "unsupported", expiry: "—", plan: "—")
        case .failed:
            return CredentialReport(provider: "Codex", availability: "unavailable", expiry: "—", plan: "—")
        }
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

    #if COAMING_CURSOR
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
    #endif
}
