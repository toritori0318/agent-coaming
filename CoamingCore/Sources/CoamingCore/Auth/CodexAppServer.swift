import Foundation

// Do not read auth.json or refresh_token. The Codex CLI keeps both and answers account/rateLimits/read.

enum CodexServerReply: Sendable {
    case usage(ParsedUsage)
    case needsLogin(String)
    case unsupported
    case failed(UsageFetchError)
}

enum CodexBinary {
    static func candidates(home: URL, environment: [String: String]) -> [String] {
        var found: [String] = []
        if let path = environment["PATH"] {
            for directory in path.split(separator: ":") {
                let binary = URL(fileURLWithPath: String(directory)).appendingPathComponent("codex").path
                if FileManager.default.isExecutableFile(atPath: binary), !found.contains(binary) {
                    found.append(binary)
                }
            }
        }
        let extras = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            home.appendingPathComponent(".local/bin/codex").path,
            "/opt/homebrew/var/nodebrew/current/bin/codex",
        ]
        for binary in extras where FileManager.default.isExecutableFile(atPath: binary) && !found.contains(binary) {
            found.append(binary)
        }
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(at: nvm, includingPropertiesForKeys: nil) {
            for version in versions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                let binary = version.appending(path: "bin/codex").path
                if FileManager.default.isExecutableFile(atPath: binary), !found.contains(binary) {
                    found.append(binary)
                }
            }
        }
        return found
    }

    /// npm and nodebrew publish a `#!/usr/bin/env node` wrapper. GUI apps do not have node on PATH, so launch the vendor binary beside that wrapper when it exists.
    static func launchURL(for candidate: URL) -> URL {
        let root = candidate.resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relatives = [
            "node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex",
            "node_modules/@openai/codex-darwin-x64/vendor/x86_64-apple-darwin/bin/codex",
        ]
        for relative in relatives {
            let url = root.appending(path: relative)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return candidate
    }
}

enum CodexAppServer {
    static func ask(executable: URL, now: Date) async -> CodexServerReply {
        let outcome = await Task.detached(priority: .userInitiated) {
            exchangeOutcome(executable: executable)
        }.value
        switch outcome {
        case .data(let data):
            do {
                return .usage(try CodexUsageParser.parse(data, now: now))
            } catch let error as UsageFetchError {
                return .failed(error)
            } catch {
                return .failed(.semantic("empty usage"))
            }
        case .rpc(let message):
            return CodexUsageParser.reply(forRPCMessage: message)
        case .failed(let error):
            return .failed(error)
        }
    }

    private static func exchangeOutcome(executable: URL) -> ExchangeOutcome {
        do {
            return .data(try exchange(executable: executable))
        } catch let error as CodexRPCError {
            return .rpc(error.message)
        } catch let error as UsageFetchError {
            return .failed(error)
        } catch {
            return .failed(.offline)
        }
    }

    private static func exchange(executable: URL) throws -> Data {
        let process = Process()
        let launch = CodexBinary.launchURL(for: executable)
        process.executableURL = launch
        process.arguments = ["app-server"]
        process.environment = launchEnvironment(executable: launch)
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let stdout = output.fileHandleForReading
        let lines = LineQueue(handle: stdout)
        try process.run()
        defer {
            lines.stop()
            if process.isRunning { process.terminate() }
            try? input.fileHandleForWriting.close()
        }

        let deadline = Date().addingTimeInterval(Constants.requestTimeout)
        let writer = input.fileHandleForWriting
        try write(["method": "initialize", "id": 0, "params": ["clientInfo": clientInfo()]], to: writer)
        _ = try lines.waitForID(0, deadline: deadline)
        try write(["method": "initialized"], to: writer)
        try write(
            ["method": "account/rateLimits/read", "id": 1, "params": ["excludeResetCreditDetails": true]],
            to: writer
        )
        let response = try lines.waitForID(1, deadline: deadline)
        guard let result = response["result"] else { throw UsageFetchError.semantic("empty usage") }
        return try JSONSerialization.data(withJSONObject: result)
    }

    private static func launchEnvironment(executable: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        var prefix = [
            executable.deletingLastPathComponent().path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/homebrew/var/nodebrew/current/bin",
        ]
        if let home = environment["HOME"], !home.isEmpty {
            prefix.append((home as NSString).appendingPathComponent(".local/bin"))
        }
        let current = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = (prefix + [current]).joined(separator: ":")
        return environment
    }

    private static func clientInfo() -> [String: String] {
        ["name": "agent_coaming", "title": "Agent Coaming", "version": Constants.appVersion]
    }

    private static func write(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }
}

private enum ExchangeOutcome: Sendable {
    case data(Data)
    case rpc(String)
    case failed(UsageFetchError)
}

private struct CodexRPCError: Error {
    var message: String
}

private final class LineQueue: @unchecked Sendable {
    private let lock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private var pending = Data()
    private var lines: [Data] = []
    private var closed = false
    private let handle: FileHandle

    init(handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let chunk = handle.availableData
            self.lock.lock()
            if chunk.isEmpty {
                self.closed = true
                if !self.pending.isEmpty {
                    self.lines.append(self.pending)
                    self.pending.removeAll()
                }
            } else {
                self.pending.append(chunk)
                while let newline = self.pending.firstIndex(of: 10) {
                    var line = Data(self.pending[..<newline])
                    self.pending.removeSubrange(self.pending.startIndex ... newline)
                    if line.last == 13 { line.removeLast() }
                    if !line.isEmpty { self.lines.append(line) }
                }
            }
            self.lock.unlock()
            self.ready.signal()
        }
    }

    func stop() {
        handle.readabilityHandler = nil
    }

    func waitForID(_ id: Int, deadline: Date) throws -> [String: Any] {
        while true {
            let object = try nextObject(deadline: deadline)
            guard (object["id"] as? NSNumber)?.intValue == id else { continue }
            if let error = object["error"] as? [String: Any] {
                throw CodexRPCError(message: error["message"] as? String ?? "codex app-server failed")
            }
            return object
        }
    }

    private func nextObject(deadline: Date) throws -> [String: Any] {
        while true {
            let line = try nextLine(deadline: deadline)
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                return object
            }
        }
    }

    private func nextLine(deadline: Date) throws -> Data {
        while true {
            lock.lock()
            if !lines.isEmpty {
                let line = lines.removeFirst()
                lock.unlock()
                return line
            }
            let ended = closed
            lock.unlock()
            if ended { throw UsageFetchError.offline }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { throw UsageFetchError.offline }
            if ready.wait(timeout: .now() + remaining) == .timedOut {
                throw UsageFetchError.offline
            }
        }
    }
}

enum CodexUsageParser {
    static func parse(_ data: Data, now: Date) throws -> ParsedUsage {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageFetchError.semantic("empty usage")
        }
        return try parse(object, now: now)
    }

    static func parse(_ object: [String: Any], now: Date) throws -> ParsedUsage {
        guard let snapshot = snapshot(from: object) else { throw UsageFetchError.semantic("empty usage") }
        var windows: [UsageWindow] = []
        if let primary = snapshot["primary"] as? [String: Any], let window = make(primary) {
            windows.append(window)
        }
        if let secondary = snapshot["secondary"] as? [String: Any], let window = make(secondary) {
            windows.append(window)
        }
        windows.sort { rank($0.kind) < rank($1.kind) }
        if windows.isEmpty { throw UsageFetchError.semantic("empty usage") }
        let plan = (snapshot["planType"] as? String).map { "Codex \($0)" }
        return ParsedUsage(windows: windows, planLabel: plan)
    }

    static func reply(forRPCMessage message: String) -> CodexServerReply {
        let folded = message.lowercased()
        if folded.contains("chatgpt authentication required") {
            return .unsupported
        }
        if folded.contains("authentication required") {
            return .needsLogin("sign in with ChatGPT in Codex")
        }
        return .failed(.semantic("codex app-server failed"))
    }

    private static func snapshot(from object: [String: Any]) -> [String: Any]? {
        if let buckets = object["rateLimitsByLimitId"] as? [String: Any],
           let codex = buckets["codex"] as? [String: Any] {
            return codex
        }
        return object["rateLimits"] as? [String: Any]
    }

    private static func make(_ window: [String: Any]) -> UsageWindow? {
        guard let used = number(window["usedPercent"]) else { return nil }
        let minutes = number(window["windowDurationMins"]) ?? 0
        let weekly = minutes * 60 >= Double(Constants.weeklyWindowMinimumSeconds)
        let resets = number(window["resetsAt"]).map { Date(timeIntervalSince1970: $0) }
        return UsageWindow(
            kind: weekly ? .weekly : .fiveHour,
            label: weekly ? "Weekly" : "5h",
            usedFraction: used / 100,
            resetsAt: resets
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func rank(_ kind: WindowKind) -> Int {
        kind == .weekly ? 1 : 0
    }
}
