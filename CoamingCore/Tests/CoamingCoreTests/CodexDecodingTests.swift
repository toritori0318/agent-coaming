import XCTest
@testable import CoamingCore

final class CodexDecodingTests: XCTestCase {
    func testCodexBucketWinsOverTheCombinedSnapshot() throws {
        let parsed = try CodexUsageParser.parse(Fixtures.data("codex_usage_primary_weekly"), now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(parsed.planLabel, "Codex plus")
        XCTAssertEqual(parsed.windows.map(\.kind), [.fiveHour, .weekly])
        XCTAssertEqual(parsed.windows[0].usedFraction, 0.04, accuracy: 0.0001)
        XCTAssertEqual(parsed.windows[1].usedFraction, 0.19, accuracy: 0.0001)
        XCTAssertEqual(parsed.windows[0].resetsAt, Date(timeIntervalSince1970: 1_700_004_140))
        XCTAssertEqual(parsed.windows[1].resetsAt, Date(timeIntervalSince1970: 1_700_546_240))
        XCTAssertFalse(String(describing: parsed).contains("do-not-keep"))
    }

    func testSingleWindow() throws {
        let parsed = try CodexUsageParser.parse(Fixtures.data("codex_usage_single_window"), now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(parsed.windows.count, 1)
        XCTAssertEqual(parsed.windows[0].kind, .fiveHour)
        XCTAssertEqual(parsed.windows[0].usedFraction, 0.04, accuracy: 0.0001)
        XCTAssertEqual(parsed.planLabel, "Codex pro")
    }

    func testMissingResetStaysNil() throws {
        let json = #"{"rateLimits":{"planType":"plus","primary":{"usedPercent":8,"windowDurationMins":300}}}"#
        let parsed = try CodexUsageParser.parse(Data(json.utf8), now: Date(timeIntervalSince1970: 10))
        XCTAssertNil(parsed.windows[0].resetsAt)
    }

    func testAPIKeyLoginIsUnsupported() {
        guard case .unsupported = CodexUsageParser.reply(forRPCMessage: "chatgpt authentication required to read rate limits") else {
            return XCTFail("expected unsupported")
        }
    }

    func testMissingChatGPTLoginNeedsSignIn() {
        guard case .needsLogin(let reason) = CodexUsageParser.reply(forRPCMessage: "codex account authentication required to read rate limits") else {
            return XCTFail("expected needs login")
        }
        XCTAssertEqual(reason, "sign in with ChatGPT in Codex")
    }

    func testOtherRPCFailureStaysSemantic() {
        guard case .failed(.semantic(let message)) = CodexUsageParser.reply(forRPCMessage: "failed to fetch codex rate limits: no snapshots returned") else {
            return XCTFail("expected semantic failure")
        }
        XCTAssertEqual(message, "codex app-server failed")
    }

    func testRateLimitReplyIsHTTP429() {
        guard case .failed(.http(let status, let retryAfter)) = CodexUsageParser.reply(forRPCMessage: "rate limit exceeded: try again later") else {
            return XCTFail("expected http 429")
        }
        XCTAssertEqual(status, 429)
        XCTAssertNil(retryAfter)
        guard case .failed(.http(let coded, _)) = CodexUsageParser.reply(forRPCMessage: "upstream returned http_429") else {
            return XCTFail("expected http 429")
        }
        XCTAssertEqual(coded, 429)
    }

    func testPathCandidateAndVendorBinary() throws {
        let directory = try temporaryDirectory()
        let binary = directory.appendingPathComponent("codex")
        try Data("#!/bin/sh\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let found = CodexBinary.candidates(home: directory, environment: ["PATH": directory.path])
        XCTAssertEqual(found.first, binary.path)

        let root = try temporaryDirectory()
        let wrapper = root.appending(path: "bin/codex")
        try FileManager.default.createDirectory(at: wrapper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/usr/bin/env node\n".utf8).write(to: wrapper)
        let native = root.appending(path: "node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex")
        try FileManager.default.createDirectory(at: native.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("native".utf8).write(to: native)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: native.path)
        XCTAssertEqual(CodexBinary.launchURL(for: wrapper).path, native.path)
    }
}
