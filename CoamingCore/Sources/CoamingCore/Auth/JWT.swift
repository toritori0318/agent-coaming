import Foundation

enum JWT {
    static func payload(of token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        guard let data = base64URLDecode(String(parts[1])) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    static func expiry(of token: String) -> Date? {
        guard let payload = payload(of: token) else { return nil }
        if let number = payload["exp"] as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        return nil
    }

    static func subject(of token: String) -> String? {
        guard let payload = payload(of: token) else { return nil }
        return payload["sub"] as? String
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var encoded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = encoded.count % 4
        if remainder > 0 {
            encoded.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: encoded)
    }
}

#if COAMING_CURSOR
// Cursor cookie built from the access token. The default build omits this. See ProviderID.included.
enum CursorIdentity {
    static func userID(from accessToken: String) -> String? {
        guard let subject = JWT.subject(of: accessToken) else { return nil }
        let identifier = subject.split(separator: "|", omittingEmptySubsequences: false).last.map(String.init) ?? subject
        guard !identifier.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        guard identifier.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return identifier
    }

    /// The token is placed in a cookie, so reject anything outside the JWT character set (`;` or a newline).
    static func isValidToken(_ accessToken: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        return !accessToken.isEmpty && accessToken.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func cookie(userID: String, accessToken: String) -> String {
        "WorkosCursorSessionToken=\(userID)%3A%3A\(accessToken)"
    }
}
#endif
