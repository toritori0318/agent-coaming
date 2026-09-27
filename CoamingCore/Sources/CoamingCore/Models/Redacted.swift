import Foundation

// Do not read refreshToken / refresh_token. description is always masked.

#if COAMING_CURSOR
// Cursor access token held in memory. The default build omits this. See ProviderID.included.
public struct CursorCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    var accessToken: String
    var expiresAt: Date?
    var membershipType: String?

    public var description: String { "<redacted>" }
    public var debugDescription: String { "<redacted>" }
}
#endif
