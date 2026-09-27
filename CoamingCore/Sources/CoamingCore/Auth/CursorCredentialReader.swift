import Foundation
import SQLite3

enum CursorTokenRead: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case found(CursorCredential)
    case missing
    case busy

    var description: String {
        switch self {
        case .found: "found(<redacted>)"
        case .missing: "missing"
        case .busy: "busy"
        }
    }

    var debugDescription: String { description }
}

struct CursorCredentialReader: Sendable {
    var databaseURL: URL
    var keychain: KeychainClient

    func read() -> CursorTokenRead {
        switch CursorDatabase.read(path: databaseURL.path) {
        case .busy:
            return .busy
        case .values(let rows):
            if let token = rows["cursorAuth/accessToken"], !token.isEmpty {
                return .found(credential(token: token, membership: rows["cursorAuth/stripeMembershipType"]))
            }
            return keychainFallback()
        case .unavailable:
            return keychainFallback()
        }
    }

    private func keychainFallback() -> CursorTokenRead {
        let copy = keychain.copyGenericPassword(Constants.cursorKeychainService)
        guard copy.status == errSecSuccess, let data = copy.data, let token = decodeStored(data), !token.isEmpty else {
            return .missing
        }
        return .found(credential(token: token, membership: nil))
    }

    private func credential(token: String, membership: String?) -> CursorCredential {
        let trimmedMembership = membership?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CursorCredential(
            accessToken: token,
            expiresAt: JWT.expiry(of: token),
            membershipType: trimmedMembership?.isEmpty == true ? nil : trimmedMembership
        )
    }
}

private enum CursorDBRead {
    case values([String: String])
    case unavailable
    case busy
}

private enum QueryResult {
    case values([String: String])
    case busy
    case cantOpen
    case failed
}

private enum SQLiteOpen {
    case opened(OpaquePointer)
    case cantOpen
    case busy
}

private enum CursorDatabase {
    static let keys = ["cursorAuth/accessToken", "cursorAuth/stripeMembershipType"]
    // Query only the keys above. Do not read refreshToken.

    static func read(path: String) -> CursorDBRead {
        let first = attempt(openReadonly(path))
        // CANTOPEN can come from prepare, not only open. Fall back to immutable only when the sidecars are absent.
        if case .cantOpen = first, !sidecarsExist(path) {
            return finish(attempt(openImmutable(path)), path: path)
        }
        return finish(first, path: path)
    }

    private static func sidecarsExist(_ path: String) -> Bool {
        let wal = FileManager.default.fileExists(atPath: path + "-wal")
        let shm = FileManager.default.fileExists(atPath: path + "-shm")
        return wal || shm
    }

    private static func attempt(_ opened: SQLiteOpen) -> QueryResult {
        switch opened {
        case .opened(let db):
            return query(db)
        case .busy:
            return .busy
        case .cantOpen:
            return .cantOpen
        }
    }

    private static func finish(_ result: QueryResult, path: String) -> CursorDBRead {
        switch result {
        case .values(let rows):
            return .values(rows)
        case .busy:
            return .busy
        case .cantOpen:
            return FileManager.default.fileExists(atPath: path) ? .busy : .unavailable
        case .failed:
            return .unavailable
        }
    }

    private static func openReadonly(_ path: String) -> SQLiteOpen {
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
        return classify(rc, db: db)
    }

    private static func openImmutable(_ path: String) -> SQLiteOpen {
        var db: OpaquePointer?
        let uri = immutableURI(path)
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        let rc = sqlite3_open_v2(uri, &db, flags, nil)
        return classify(rc, db: db)
    }

    private static func classify(_ rc: Int32, db: OpaquePointer?) -> SQLiteOpen {
        let code = rc & 0xFF
        if code == SQLITE_OK, let db {
            sqlite3_busy_timeout(db, Constants.sqliteBusyTimeoutMillis)
            return .opened(db)
        }
        if let db { sqlite3_close(db) }
        if code == SQLITE_BUSY || code == SQLITE_LOCKED { return .busy }
        return .cantOpen
    }

    private static func query(_ db: OpaquePointer) -> QueryResult {
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1"
        let prepare = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        if base(prepare) == SQLITE_BUSY || base(prepare) == SQLITE_LOCKED { return .busy }
        if base(prepare) == SQLITE_CANTOPEN { return .cantOpen }
        guard base(prepare) == SQLITE_OK, let statement else {
            Log.auth.error("cursor db prepare failed code=\(prepare, privacy: .public)")
            return base(prepare) == SQLITE_CANTOPEN ? .cantOpen : .failed
        }
        var rows: [String: String] = [:]
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for key in keys {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            let bound = key.withCString { sqlite3_bind_text(statement, 1, $0, -1, transient) }
            if base(bound) == SQLITE_BUSY || base(bound) == SQLITE_LOCKED { return .busy }
            if base(bound) == SQLITE_CANTOPEN { return .cantOpen }
            let step = sqlite3_step(statement)
            if base(step) == SQLITE_BUSY || base(step) == SQLITE_LOCKED { return .busy }
            if base(step) == SQLITE_CANTOPEN { return .cantOpen }
            if base(step) == SQLITE_ROW, let value = columnText(statement) {
                rows[key] = value
            } else if base(step) != SQLITE_DONE && base(step) != SQLITE_ROW {
                Log.auth.error("cursor db step failed code=\(step, privacy: .public)")
                return .failed
            }
        }
        return .values(rows)
    }

    private static func columnText(_ statement: OpaquePointer) -> String? {
        switch sqlite3_column_type(statement, 0) {
        case SQLITE_TEXT:
            guard let cString = sqlite3_column_text(statement, 0) else { return "" }
            return String(cString: cString)
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard count > 0, let pointer = sqlite3_column_blob(statement, 0) else { return "" }
            return decodeStored(Data(bytes: pointer, count: count))
        case SQLITE_NULL:
            return nil
        default:
            guard let cString = sqlite3_column_text(statement, 0) else { return nil }
            return String(cString: cString)
        }
    }

    private static func base(_ code: Int32) -> Int32 { code & 0xFF }

    private static func immutableURI(_ path: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "/-._~")
        let encoded = path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
        return "file:\(encoded)?immutable=1"
    }
}

func decodeStored(_ data: Data) -> String? {
    if data.starts(with: [0xFF, 0xFE]) {
        return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
    }
    if let utf8 = String(data: data, encoding: .utf8), !utf8.contains("\0") {
        return utf8
    }
    if let utf16 = String(data: data, encoding: .utf16LittleEndian) {
        return utf16
    }
    return String(data: data, encoding: .utf8)
}
