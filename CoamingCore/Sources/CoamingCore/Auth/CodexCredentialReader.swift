import Foundation

enum CodexRead: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case found(CodexCredential)
    case needsLogin(String?)
    case notInstalled
    case unsupported

    var description: String {
        switch self {
        case .found: "found(<redacted>)"
        case .needsLogin(let reason): "needsLogin(\(reason ?? ""))"
        case .notInstalled: "notInstalled"
        case .unsupported: "unsupported"
        }
    }

    var debugDescription: String { description }
}

struct CodexCredentialReader: Sendable {
    var authFileURL: URL
    var sessionsDirectoryURL: URL

    func read() -> CodexRead {
        guard FileManager.default.fileExists(atPath: authFileURL.path) else {
            if FileManager.default.fileExists(atPath: sessionsDirectoryURL.path) {
                return .needsLogin(nil)
            }
            return .notInstalled
        }
        guard let data = readBounded(url: authFileURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .needsLogin("auth file unreadable")
        }
        let apiKey = (root["OPENAI_API_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = root["tokens"] as? [String: Any]
        let access = (tokens?["access_token"] as? String ?? tokens?["accessToken"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let account = (tokens?["account_id"] as? String ?? tokens?["accountId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Do not read refresh_token.
        if (access == nil || access?.isEmpty == true), let apiKey, !apiKey.isEmpty {
            return .unsupported
        }
        guard let access, !access.isEmpty else {
            return .needsLogin(nil)
        }
        return .found(
            CodexCredential(
                accessToken: access,
                accountID: account?.isEmpty == true ? nil : account,
                expiresAt: JWT.expiry(of: access)
            )
        )
    }
}
