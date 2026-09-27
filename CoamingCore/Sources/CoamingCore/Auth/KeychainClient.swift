#if COAMING_CURSOR
// Cursor session lookup. The default build does not read the Keychain. See ProviderID.included.
import Foundation
import Security

struct KeychainCopy: Sendable {
    var status: OSStatus
    var data: Data?
}

struct KeychainClient: Sendable {
    var copyGenericPassword: @Sendable (String) -> KeychainCopy

    static func live() -> KeychainClient {
        KeychainClient { service in
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            return KeychainCopy(status: status, data: item as? Data)
        }
    }

    static func empty() -> KeychainClient {
        KeychainClient { _ in
            KeychainCopy(status: errSecItemNotFound, data: nil)
        }
    }
}
#endif
