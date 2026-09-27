import Foundation

struct ClaudeProvider: UsageProvider {
    var id: ProviderID { .claude }
    var read: @Sendable () -> ClaudeRead

    func fetch(now: Date) async -> ProviderAttempt {
        switch read() {
        case .notInstalled:
            return .terminal(.make(.claude, status: .notInstalled))
        case .notConfigured:
            return .terminal(.make(.claude, status: .notConfigured))
        case .found(let limits):
            // Same as Claude Code: a window past its reset time is treated as absent.
            let live = limits.windows.filter { window in
                window.resetsAt.map { $0 > now } ?? true
            }
            return .terminal(.make(.claude, status: .ok, windows: live, fetchedAt: limits.writtenAt))
        }
    }
}
