import Security
import XCTest
@testable import CoamingCore

final class JWTTests: XCTestCase {
    func testExpiry() throws {
        let token = try makeJWT(payload: ["exp": 1_759_000_000, "sub": "user"])
        XCTAssertEqual(JWT.expiry(of: token), Date(timeIntervalSince1970: 1_759_000_000))
        XCTAssertEqual(JWT.subject(of: token), "user")
    }

    func testPaddingDifferences() throws {
        let padded = try makeJWT(payload: ["exp": 1_759_000_000], padding: true)
        let stripped = try makeJWT(payload: ["exp": 1_759_000_000], padding: false)
        XCTAssertEqual(JWT.expiry(of: padded), JWT.expiry(of: stripped))
    }

    func testTooFewSegments() {
        XCTAssertNil(JWT.expiry(of: "abc"))
        XCTAssertNil(JWT.payload(of: ""))
    }

    func testMissingExp() throws {
        let token = try makeJWT(payload: ["sub": "only"])
        XCTAssertNil(JWT.expiry(of: token))
        XCTAssertEqual(JWT.subject(of: token), "only")
    }
}

final class CredentialReaderTests: XCTestCase {
    func testCodexKeyStyles() throws {
        let snake = try codexRead("codex_auth_snake")
        guard case .found(let snakeCredential) = snake else { return XCTFail("\(snake)") }
        XCTAssertEqual(snakeCredential.accountID, "acc_snake")
        XCTAssertEqual(snakeCredential.expiresAt, Date(timeIntervalSince1970: 1_759_000_000))
        XCTAssertFalse(String(reflecting: snakeCredential).contains("DO_NOT_KEEP_9f3a"))

        let camel = try codexRead("codex_auth_camel")
        guard case .found(let camelCredential) = camel else { return XCTFail("\(camel)") }
        XCTAssertEqual(camelCredential.accountID, "acc_camel")

        let api = try codexRead("codex_auth_apikey")
        guard case .unsupported = api else { return XCTFail("\(api)") }
    }

    func testCodexInstalledDetection() throws {
        let directory = try temporaryDirectory()
        let missing = CodexCredentialReader(
            authFileURL: directory.appendingPathComponent("auth.json"),
            sessionsDirectoryURL: directory.appendingPathComponent("sessions")
        )
        guard case .notInstalled = missing.read() else { return XCTFail("expected not installed") }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        guard case .needsLogin = missing.read() else { return XCTFail("expected needs login") }
    }

    func testCursorReadonlyBlobAndBusyAndWAL() throws {
        let plain = try temporaryDirectory()
        let plainDB = plain.appendingPathComponent("state.vscdb")
        try runPython(deleteModeScript, path: plainDB.path)
        let before = try directoryStamp(plain)
        let plainRead = CursorCredentialReader(databaseURL: plainDB, keychain: .empty()).read()
        guard case .found(let plainCredential) = plainRead else { return XCTFail("\(plainRead)") }
        XCTAssertEqual(plainCredential.accessToken, "PLAIN")
        XCTAssertEqual(plainCredential.membershipType, "pro")
        XCTAssertEqual(try directoryStamp(plain), before)

        let blobs = try temporaryDirectory()
        let blobDB = blobs.appendingPathComponent("state.vscdb")
        try runPython(blobScript, path: blobDB.path)
        let blobRead = CursorCredentialReader(databaseURL: blobDB, keychain: .empty()).read()
        guard case .found(let blobCredential) = blobRead else { return XCTFail("\(blobRead)") }
        XCTAssertEqual(blobCredential.accessToken, "Hi")

        let utf8 = try temporaryDirectory()
        let utf8DB = utf8.appendingPathComponent("state.vscdb")
        try runPython(utf8BlobScript, path: utf8DB.path)
        let utf8Read = CursorCredentialReader(databaseURL: utf8DB, keychain: .empty()).read()
        guard case .found(let utf8Credential) = utf8Read else { return XCTFail("\(utf8Read)") }
        XCTAssertEqual(utf8Credential.accessToken, "Hello")

        let walDir = try temporaryDirectory()
        let walDB = walDir.appendingPathComponent("state.vscdb")
        let holder = try holdPython(walScript, path: walDB.path)
        defer { holder.terminate() }
        let walBefore = try directoryStamp(walDir)
        let walRead = CursorCredentialReader(databaseURL: walDB, keychain: .empty()).read()
        guard case .found(let walCredential) = walRead else { return XCTFail("\(walRead)") }
        XCTAssertEqual(walCredential.accessToken, "NEW_TOKEN")
        let walAfter = try directoryStamp(walDir)
        XCTAssertEqual(Set(walBefore.keys), Set(walAfter.keys))
        XCTAssertNil(walAfter.keys.first { $0.hasSuffix("-journal") })
        XCTAssertEqual(walBefore["state.vscdb"], walAfter["state.vscdb"])
        XCTAssertEqual(walBefore["state.vscdb-wal"], walAfter["state.vscdb-wal"])
        XCTAssertEqual(walBefore["state.vscdb-shm"], walAfter["state.vscdb-shm"])

        let fallbackDir = try temporaryDirectory()
        let fallbackDB = fallbackDir.appendingPathComponent("state.vscdb")
        try runPython(immutableScript, path: fallbackDB.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fallbackDB.path + "-wal"))
        let fallback = CursorCredentialReader(databaseURL: fallbackDB, keychain: .empty()).read()
        guard case .found(let fallbackCredential) = fallback else { return XCTFail("\(fallback)") }
        XCTAssertEqual(fallbackCredential.accessToken, "IMMUTABLE_TOKEN")

        let busyDir = try temporaryDirectory()
        let busyDB = busyDir.appendingPathComponent("state.vscdb")
        let lock = try holdPython(busyScript, path: busyDB.path)
        defer { lock.terminate() }
        let busy = CursorCredentialReader(databaseURL: busyDB, keychain: .empty()).read()
        guard case .busy = busy else { return XCTFail("expected busy, got \(busy)") }
    }

    func testCursorDatabaseWithoutItemTableIsMissingNotBusy() throws {
        let directory = try temporaryDirectory()
        let db = directory.appendingPathComponent("state.vscdb")
        try runPython(noTableScript, path: db.path)
        let read = CursorCredentialReader(databaseURL: db, keychain: .empty()).read()
        guard case .missing = read else { return XCTFail("expected missing, got \(read)") }
    }

    func testCursorTokenCharactersAreChecked() throws {
        let token = try makeJWT(payload: ["sub": "auth0|user_abc", "exp": 2_000_000_000])
        XCTAssertTrue(CursorIdentity.isValidToken(token))
        XCTAssertFalse(CursorIdentity.isValidToken(token + "; Path=/"))
        XCTAssertFalse(CursorIdentity.isValidToken("a\r\nb"))
        XCTAssertFalse(CursorIdentity.isValidToken(""))
    }

    private func codexRead(_ name: String) throws -> CodexRead {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("auth.json")
        try Fixtures.data(name).write(to: file)
        return CodexCredentialReader(authFileURL: file, sessionsDirectoryURL: directory.appendingPathComponent("sessions")).read()
    }
}

final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private struct FileStamp: Equatable {
    var modified: TimeInterval
    var size: Int
}

private func directoryStamp(_ directory: URL) throws -> [String: FileStamp] {
    var stamp: [String: FileStamp] = [:]
    for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
        let url = directory.appendingPathComponent(name)
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        stamp[name] = FileStamp(
            modified: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
            size: values.fileSize ?? 0
        )
    }
    return stamp
}

@discardableResult
private func runPython(_ source: String, path: String) throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", "-c", source, path]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    return process
}

private func holdPython(_ source: String, path: String) throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", "-c", source, path]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()
    try process.run()
    let handle = output.fileHandleForReading
    var data = Data()
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        let chunk = handle.availableData
        if chunk.isEmpty { break }
        data.append(chunk)
        if String(data: data, encoding: .utf8)?.contains("READY") == true {
            return process
        }
    }
    process.terminate()
    XCTFail("python did not become ready")
    return process
}

private let deleteModeScript = """
import sqlite3, sys
path = sys.argv[1]
conn = sqlite3.connect(path)
conn.execute("PRAGMA journal_mode=DELETE")
conn.execute("CREATE TABLE ItemTable(key TEXT PRIMARY KEY, value TEXT)")
conn.execute("INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', 'PLAIN')")
conn.execute("INSERT INTO ItemTable VALUES ('cursorAuth/stripeMembershipType', 'pro')")
conn.commit()
conn.close()
"""

private let blobScript = """
import sqlite3, sys
path = sys.argv[1]
conn = sqlite3.connect(path)
conn.execute("CREATE TABLE ItemTable(key TEXT PRIMARY KEY, value BLOB)")
conn.execute("INSERT INTO ItemTable VALUES (?, ?)", ("cursorAuth/accessToken", sqlite3.Binary(bytes([0x48, 0x00, 0x69, 0x00]))))
conn.commit()
conn.close()
"""

private let utf8BlobScript = """
import sqlite3, sys
path = sys.argv[1]
conn = sqlite3.connect(path)
conn.execute("CREATE TABLE ItemTable(key TEXT PRIMARY KEY, value BLOB)")
conn.execute("INSERT INTO ItemTable VALUES (?, ?)", ("cursorAuth/accessToken", sqlite3.Binary(b"Hello")))
conn.commit()
conn.close()
"""

private let walScript = """
import sqlite3, sys, time
path = sys.argv[1]
conn = sqlite3.connect(path)
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("CREATE TABLE ItemTable(key TEXT PRIMARY KEY, value TEXT)")
conn.execute("INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', 'OLD_TOKEN')")
conn.commit()
conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
conn.execute("PRAGMA wal_autocheckpoint=0")
conn.execute("UPDATE ItemTable SET value='NEW_TOKEN' WHERE key='cursorAuth/accessToken'")
conn.commit()
print("READY", flush=True)
time.sleep(30)
"""

private let immutableScript = """
import os, sqlite3, sys
path = sys.argv[1]
conn = sqlite3.connect(path)
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("CREATE TABLE ItemTable(key TEXT PRIMARY KEY, value TEXT)")
conn.execute("INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', 'IMMUTABLE_TOKEN')")
conn.commit()
conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
conn.close()
for suffix in ("-wal", "-shm"):
    sidecar = path + suffix
    if os.path.exists(sidecar):
        os.remove(sidecar)
print("READY", flush=True)
"""

private let busyScript = """
import sqlite3, sys, time
path = sys.argv[1]
conn = sqlite3.connect(path)
conn.execute("CREATE TABLE ItemTable(key TEXT PRIMARY KEY, value TEXT)")
conn.execute("INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', 'LOCKED')")
conn.commit()
conn.execute("BEGIN EXCLUSIVE")
print("READY", flush=True)
time.sleep(30)
"""

private let noTableScript = """
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("CREATE TABLE Other(key TEXT PRIMARY KEY, value TEXT)")
conn.commit()
conn.close()
"""
