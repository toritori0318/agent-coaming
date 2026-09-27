import Foundation

struct CursorProvider: UsageProvider {
    var id: ProviderID { .cursor }
    var userAgent: String
    var http: any HTTPClient
    var supportDirectoryURL: URL
    var read: @Sendable () -> CursorTokenRead

    func fetch(now: Date) async -> ProviderAttempt {
        switch read() {
        case .busy:
            return .from(error: .semantic("cursor db busy"), id: .cursor, plan: nil)
        case .missing:
            let installed = FileManager.default.fileExists(atPath: supportDirectoryURL.path)
            return .terminal(.make(.cursor, status: installed ? .needsLogin : .notInstalled))
        case .found(let credential):
            if let expiresAt = credential.expiresAt, expiresAt <= now.addingTimeInterval(Constants.expiryLeeway) {
                return .terminal(.make(.cursor, status: .needsLogin, reason: "token expired \(DateParsing.iso8601(expiresAt))"))
            }
            guard CursorIdentity.isValidToken(credential.accessToken),
                  let userID = CursorIdentity.userID(from: credential.accessToken) else {
                return .terminal(.make(.cursor, status: .needsLogin, reason: "invalid session"))
            }
            let fallbackPlan = credential.membershipType.map(Constants.capitalize)
            let client = CursorUsageClient(http: http, userAgent: userAgent)
            do {
                let parsed = try await client.fetch(accessToken: credential.accessToken, userID: userID, now: now)
                return .ok(.cursor, plan: parsed.planLabel ?? fallbackPlan, windows: parsed.windows, at: now)
            } catch let error as UsageFetchError {
                return .from(error: error, id: .cursor, plan: fallbackPlan)
            } catch {
                return .from(error: .offline, id: .cursor, plan: fallbackPlan)
            }
        }
    }
}
