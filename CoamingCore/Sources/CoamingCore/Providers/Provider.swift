import Foundation

protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetch(now: Date) async -> ProviderAttempt
}

struct ProviderAttempt: Sendable {
    var snapshot: ProviderSnapshot
    var keepPrevious: Bool
    var rateLimited: Bool
    var retryAfter: TimeInterval?

    static func terminal(_ snapshot: ProviderSnapshot) -> ProviderAttempt {
        ProviderAttempt(snapshot: snapshot, keepPrevious: false, rateLimited: false, retryAfter: nil)
    }

    static func ok(_ id: ProviderID, plan: String?, windows: [UsageWindow], at now: Date) -> ProviderAttempt {
        .terminal(.make(id, status: .ok, plan: plan, windows: windows, fetchedAt: now))
    }

    static func from(error: UsageFetchError, id: ProviderID, plan: String?) -> ProviderAttempt {
        switch error {
        case .http(let status, _) where status == 401 || status == 403:
            return .terminal(.make(id, status: .needsLogin, reason: "HTTP \(status)"))
        case .http(let status, let retry) where status == 429:
            return ProviderAttempt(
                snapshot: .make(id, status: .stale, plan: plan, reason: "HTTP 429"),
                keepPrevious: true,
                rateLimited: true,
                retryAfter: retry
            )
        case .http(let status, _):
            return ProviderAttempt(
                snapshot: .make(id, status: .stale, plan: plan, reason: "HTTP \(status)"),
                keepPrevious: true,
                rateLimited: false,
                retryAfter: nil
            )
        case .offline:
            return ProviderAttempt(
                snapshot: .make(id, status: .stale, plan: plan, reason: "offline"),
                keepPrevious: true,
                rateLimited: false,
                retryAfter: nil
            )
        case .decode:
            return ProviderAttempt(
                snapshot: .make(id, status: .stale, plan: plan, reason: "decode error"),
                keepPrevious: true,
                rateLimited: false,
                retryAfter: nil
            )
        case .disallowedHost:
            return ProviderAttempt(
                snapshot: .make(id, status: .stale, plan: plan, reason: "disallowed host"),
                keepPrevious: true,
                rateLimited: false,
                retryAfter: nil
            )
        case .semantic(let reason):
            return ProviderAttempt(
                snapshot: .make(id, status: .stale, plan: plan, reason: reason),
                keepPrevious: true,
                rateLimited: false,
                retryAfter: nil
            )
        }
    }
}
