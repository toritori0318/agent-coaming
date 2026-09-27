import Foundation

struct CodexProvider: UsageProvider {
    var id: ProviderID { .codex }
    var userAgent: String
    var http: any HTTPClient
    var read: @Sendable () -> CodexRead

    func fetch(now: Date) async -> ProviderAttempt {
        switch read() {
        case .notInstalled:
            return .terminal(.make(.codex, status: .notInstalled))
        case .unsupported:
            return .terminal(.make(.codex, status: .unsupported))
        case .needsLogin(let reason):
            return .terminal(.make(.codex, status: .needsLogin, reason: reason))
        case .found(let credential):
            if let expiresAt = credential.expiresAt, expiresAt <= now.addingTimeInterval(Constants.expiryLeeway) {
                return .terminal(.make(.codex, status: .needsLogin, reason: "token expired \(DateParsing.iso8601(expiresAt))"))
            }
            let client = CodexUsageClient(http: http, userAgent: userAgent)
            do {
                let parsed = try await client.fetch(
                    accessToken: credential.accessToken,
                    accountID: credential.accountID,
                    now: now
                )
                return .ok(.codex, plan: parsed.planLabel, windows: parsed.windows, at: now)
            } catch let error as UsageFetchError {
                return .from(error: error, id: .codex, plan: nil)
            } catch {
                return .from(error: .offline, id: .codex, plan: nil)
            }
        }
    }
}
