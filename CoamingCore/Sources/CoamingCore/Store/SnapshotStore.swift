import Foundation
import Security

public struct SnapshotStore: Sendable {
    public var fileURL: URL?

    public init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    public static func live() -> SnapshotStore {
        guard let container = AppGroupLocator.containerURL() else {
            return SnapshotStore(fileURL: nil)
        }
        return SnapshotStore(fileURL: container.appendingPathComponent("snapshot.json"))
    }

    public func read() -> Snapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return Snapshot.decode(data)
    }

    public func write(_ snapshot: Snapshot) throws {
        guard let fileURL else { throw SnapshotStoreError.containerUnavailable }
        let data = try snapshot.encode()
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent("snapshot.json.tmp")
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: fileURL)
        }
    }
}

public enum SnapshotStoreError: Error, Sendable {
    case containerUnavailable
}

enum AppGroupLocator {
    static func containerURL() -> URL? {
        guard let identifier = groupIdentifier() else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static func groupIdentifier() -> String? {
        if let signed = signedGroupIdentifier() { return signed }
        if let team = Bundle.main.object(forInfoDictionaryKey: "CoamingTeamID") as? String {
            let trimmed = team.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.contains("$") {
                return "\(trimmed).\(Constants.appGroupName)"
            }
        }
        return nil
    }

    private static func signedGroupIdentifier() -> String? {
        var code: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code)
        guard status == errSecSuccess, let code else { return nil }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation))
        guard SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String] else {
            return nil
        }
        return groups.first
    }
}
