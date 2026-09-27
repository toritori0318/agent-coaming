import Foundation

struct CodexProvider: UsageProvider {
    var id: ProviderID { .codex }
    var locate: @Sendable () -> URL?
    var ask: @Sendable (URL, Date) async -> CodexServerReply

    func fetch(now: Date) async -> ProviderAttempt {
        guard let executable = locate() else {
            return .terminal(.make(.codex, status: .notInstalled))
        }
        switch await ask(executable, now) {
        case .usage(let parsed):
            return .ok(.codex, plan: parsed.planLabel, windows: parsed.windows, at: now)
        case .needsLogin(let reason):
            return .terminal(.make(.codex, status: .needsLogin, reason: reason))
        case .unsupported:
            return .terminal(.make(.codex, status: .unsupported))
        case .failed(let error):
            return .from(error: error, id: .codex, plan: nil)
        }
    }
}
