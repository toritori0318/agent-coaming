import Foundation

public struct ReleaseInfo: Sendable, Equatable {
    public var version: String
    public var pageURL: URL
}

public enum UpdateCheck {
    /// Reads `tag_name` only. The release page is built here so a field in the response cannot redirect the browser.
    public static func parse(_ data: Data) throws -> ReleaseInfo {
        let file = try JSONDecoder().decode(ReleaseFile.self, from: data)
        guard let version = version(from: file.tagName) else {
            throw UsageFetchError.semantic("release tag")
        }
        let page = "https://github.com/\(Constants.releaseRepository)/releases/tag/\(file.tagName)"
        guard let pageURL = URL(string: page) else {
            throw UsageFetchError.semantic("release tag")
        }
        return ReleaseInfo(version: version, pageURL: pageURL)
    }

    /// True when every numeric part of `remote` is newer than `local`. `v` is ignored. Missing parts count as 0.
    public static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = components(remote)
        let localParts = components(local)
        guard !remoteParts.isEmpty, !localParts.isEmpty else { return false }
        let count = max(remoteParts.count, localParts.count)
        for index in 0..<count {
            let remotePart = index < remoteParts.count ? remoteParts[index] : 0
            let localPart = index < localParts.count ? localParts[index] : 0
            if remotePart != localPart { return remotePart > localPart }
        }
        return false
    }

    static func version(from tag: String) -> String? {
        guard tag.hasPrefix("v"), tag.count > 1 else { return nil }
        let rest = tag.dropFirst()
        let parts = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ part in !part.isEmpty && part.allSatisfy(\.isNumber) }) else { return nil }
        return String(rest)
    }

    private static func components(_ version: String) -> [Int] {
        let text = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return [] }
        return parts.compactMap { $0 }
    }
}

public enum ReleaseChecker {
    public static func latest(userAgent: String) async throws -> ReleaseInfo {
        try await latest(http: EphemeralHTTPClient(), userAgent: userAgent)
    }

    static func latest(http: any HTTPClient, userAgent: String) async throws -> ReleaseInfo {
        var request = URLRequest(url: Constants.releaseAPIURL)
        request.httpMethod = "GET"
        request.timeoutInterval = Constants.requestTimeout
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await http.send(request)
        try UsageHTTP.reject(response, data: data, provider: "release", now: Date())
        return try UpdateCheck.parse(data)
    }
}

private struct ReleaseFile: Decodable {
    var tagName: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}
