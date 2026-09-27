import Foundation

struct CursorUsageClient: Sendable {
    var http: any HTTPClient
    var userAgent: String

    func fetch(accessToken: String, userID: String, now: Date) async throws -> ParsedUsage {
        var request = URLRequest(url: Constants.cursorUsageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = Constants.requestTimeout
        request.setValue(CursorIdentity.cookie(userID: userID, accessToken: accessToken), forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await http.send(request)
        try UsageHTTP.reject(response, data: data, provider: "cursor", now: now)
        do {
            return try Self.parse(data)
        } catch let error as UsageFetchError {
            throw error
        } catch {
            throw UsageHTTP.decodeFailure(data, provider: "cursor")
        }
    }

    static func parse(_ data: Data) throws -> ParsedUsage {
        let decoder = JSONDecoder()
        let dto = try decoder.decode(CursorSummaryDTO.self, from: data)
        let resets = dto.billingCycleEnd.flatMap(DateParsing.parseISO8601)
        let plan = dto.membershipType.map(Constants.capitalize)

        if dto.isUnlimited == true {
            return ParsedUsage(
                windows: [UsageWindow(kind: .billingPlan, label: "∞", usedFraction: 0, resetsAt: resets)],
                planLabel: plan
            )
        }
        if isLegacy(dto) {
            throw UsageFetchError.semantic("legacy plan")
        }

        var windows: [UsageWindow] = []
        if let percent = dto.individualUsage?.plan?.totalPercentUsed {
            windows.append(planWindow(percent / 100, label: "Plan", resets: resets))
        } else if let limit = dto.individualUsage?.plan?.limit, limit > 0, let used = dto.individualUsage?.plan?.used {
            windows.append(planWindow(used / limit, label: "Plan", resets: resets))
        } else if let limit = dto.individualUsage?.overall?.limit, limit > 0, let used = dto.individualUsage?.overall?.used {
            windows.append(planWindow(used / limit, label: "Plan", resets: resets))
        } else if let limit = dto.teamUsage?.pooled?.limit, limit > 0, let used = dto.teamUsage?.pooled?.used {
            windows.append(planWindow(used / limit, label: "Team", resets: resets))
        }

        if windows.isEmpty {
            throw UsageFetchError.semantic("empty usage")
        }

        if dto.individualUsage?.onDemand?.enabled == true,
           let limit = dto.individualUsage?.onDemand?.limit, limit > 0,
           let used = dto.individualUsage?.onDemand?.used {
            windows.append(
                UsageWindow(kind: .billingOnDemand, label: "On-demand", usedFraction: used / limit, resetsAt: resets)
            )
        }
        return ParsedUsage(windows: windows, planLabel: plan)
    }

    private static func isLegacy(_ dto: CursorSummaryDTO) -> Bool {
        guard let limitType = dto.limitType?.lowercased(), limitType.hasPrefix("request") else { return false }
        return dto.individualUsage?.plan == nil
    }

    private static func planWindow(_ fraction: Double, label: String, resets: Date?) -> UsageWindow {
        UsageWindow(kind: .billingPlan, label: label, usedFraction: fraction, resetsAt: resets)
    }
}

private struct CursorSummaryDTO: Decodable {
    var billingCycleEnd: String?
    var membershipType: String?
    var limitType: String?
    var isUnlimited: Bool?
    var individualUsage: CursorIndividualDTO?
    var teamUsage: CursorTeamDTO?
}

private struct CursorIndividualDTO: Decodable {
    var plan: CursorBucketDTO?
    var onDemand: CursorBucketDTO?
    var overall: CursorBucketDTO?
}

private struct CursorTeamDTO: Decodable {
    var pooled: CursorBucketDTO?
}

private struct CursorBucketDTO: Decodable {
    var enabled: Bool?
    var used: Double?
    var limit: Double?
    var totalPercentUsed: Double?

    enum CodingKeys: String, CodingKey {
        case enabled, used, limit, totalPercentUsed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        used = try container.decodeFlexibleDoubleIfPresent(forKey: .used)
        limit = try container.decodeFlexibleDoubleIfPresent(forKey: .limit)
        totalPercentUsed = try container.decodeFlexibleDoubleIfPresent(forKey: .totalPercentUsed)
    }
}
