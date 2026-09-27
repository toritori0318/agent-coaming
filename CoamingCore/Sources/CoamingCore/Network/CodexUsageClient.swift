import Foundation

struct CodexUsageClient: Sendable {
    var http: any HTTPClient
    var userAgent: String

    func fetch(accessToken: String, accountID: String?, now: Date) async throws -> ParsedUsage {
        var request = URLRequest(url: Constants.codexUsageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = Constants.requestTimeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await http.send(request)
        try UsageHTTP.reject(response, data: data, provider: "codex", now: now)
        do {
            return try Self.parse(data, fetchedAt: now)
        } catch let error as UsageFetchError {
            throw error
        } catch {
            throw UsageHTTP.decodeFailure(data, provider: "codex")
        }
    }

    static func parse(_ data: Data, fetchedAt: Date) throws -> ParsedUsage {
        let decoder = JSONDecoder()
        let dto = try decoder.decode(CodexUsageDTO.self, from: data)
        var windows: [UsageWindow] = []
        if let window = dto.rateLimit?.primaryWindow {
            windows.append(contentsOf: [make(window, fetchedAt: fetchedAt)].compactMap { $0 })
        }
        if let window = dto.rateLimit?.secondaryWindow {
            windows.append(contentsOf: [make(window, fetchedAt: fetchedAt)].compactMap { $0 })
        }
        windows.sort { lhs, rhs in
            rank(lhs.kind) < rank(rhs.kind)
        }
        if windows.isEmpty { throw UsageFetchError.semantic("empty usage") }
        let plan = dto.planType.map { "Codex \($0)" }
        return ParsedUsage(windows: windows, planLabel: plan)
    }

    private static func make(_ window: CodexWindowDTO, fetchedAt: Date) -> UsageWindow? {
        guard let used = window.usedPercent else { return nil }
        let seconds = window.limitWindowSeconds ?? 0
        let weekly = seconds >= Double(Constants.weeklyWindowMinimumSeconds)
        let resets: Date?
        if let after = window.resetAfterSeconds {
            resets = fetchedAt.addingTimeInterval(after)
        } else if let resetAt = window.resetAt {
            resets = Date(timeIntervalSince1970: resetAt)
        } else {
            resets = nil
        }
        return UsageWindow(
            kind: weekly ? .weekly : .fiveHour,
            label: weekly ? "Weekly" : "5h",
            usedFraction: used / 100,
            resetsAt: resets
        )
    }

    private static func rank(_ kind: WindowKind) -> Int {
        kind == .weekly ? 1 : 0
    }
}

private struct CodexUsageDTO: Decodable {
    var planType: String?
    var rateLimit: CodexRateLimitDTO?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }
}

private struct CodexRateLimitDTO: Decodable {
    var primaryWindow: CodexWindowDTO?
    var secondaryWindow: CodexWindowDTO?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct CodexWindowDTO: Decodable {
    var usedPercent: Double?
    var limitWindowSeconds: Double?
    var resetAfterSeconds: Double?
    var resetAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try container.decodeFlexibleDoubleIfPresent(forKey: .usedPercent)
        limitWindowSeconds = try container.decodeFlexibleDoubleIfPresent(forKey: .limitWindowSeconds)
        resetAfterSeconds = try container.decodeFlexibleDoubleIfPresent(forKey: .resetAfterSeconds)
        resetAt = try container.decodeFlexibleDoubleIfPresent(forKey: .resetAt)
    }
}
