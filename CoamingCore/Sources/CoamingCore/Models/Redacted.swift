import Foundation

// Do not read refreshToken / refresh_token. description is always masked.

public struct CodexCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    var accessToken: String
    var accountID: String?
    var expiresAt: Date?

    public var description: String { "<redacted>" }
    public var debugDescription: String { "<redacted>" }
}

public struct CursorCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    var accessToken: String
    var expiresAt: Date?
    var membershipType: String?

    public var description: String { "<redacted>" }
    public var debugDescription: String { "<redacted>" }
}
