import Foundation

struct ParsedUsage: Sendable {
    var windows: [UsageWindow]
    var planLabel: String?
}

enum UsageHTTP {
    static func reject(_ response: HTTPURLResponse, data: Data, provider: String, now: Date) throws {
        let status = response.statusCode
        guard (200...299).contains(status) else {
            let retry = status == 429
                ? RetryAfterParser.parse(header: response.value(forHTTPHeaderField: "Retry-After"), now: now)
                : nil
            throw UsageFetchError.http(status: status, retryAfter: retry)
        }
    }

    static func decodeFailure(_ data: Data, provider: String) -> UsageFetchError {
        let tree = JSONKeyTree.describe(data)
        Log.usage.error("\(provider, privacy: .public) decode error keys=\(tree, privacy: .public)")
        return .decode(keyTree: tree)
    }
}
