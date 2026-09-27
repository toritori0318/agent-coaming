import XCTest
@testable import CoamingCore

final class RefresherTests: XCTestCase {
    func testOneFailureDoesNotDropTheOthers() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let kept = UsageWindow(kind: .fiveHour, label: "5h", usedFraction: 0.2, resetsAt: nil)
        let previous = Snapshot(
            schemaVersion: 1,
            generatedAt: now.addingTimeInterval(-600),
            providers: [
                .make(.claude, status: .ok, plan: "Pro", windows: [kept], fetchedAt: now.addingTimeInterval(-600)),
                .make(.codex, status: .notInstalled),
                .make(.cursor, status: .notInstalled),
            ]
        )
        let claude = ScriptedProvider(id: .claude, attempt: .from(error: .offline, id: .claude, plan: nil))
        let codex = ScriptedProvider(id: .codex, attempt: .ok(.codex, plan: "Codex plus", windows: [kept], at: now))
        let cursor = ScriptedProvider(id: .cursor, attempt: .ok(.cursor, plan: "Pro", windows: [kept], at: now))
        let refresher = Refresher(providers: [claude, codex, cursor], previous: previous, backoff: MemoryBackoffStore())
        let snapshot = await refresher.refresh(at: now, force: false)
        let claudeRow = try XCTUnwrap(snapshot.provider(.claude))
        XCTAssertEqual(claudeRow.status, .stale)
        XCTAssertEqual(claudeRow.staleReason, "offline")
        XCTAssertEqual(claudeRow.windows, [kept])
        XCTAssertEqual(claudeRow.planLabel, "Pro")
        XCTAssertEqual(snapshot.provider(.codex)?.status, .ok)
        XCTAssertEqual(snapshot.provider(.cursor)?.status, .ok)
    }

    func testSemanticErrorKeepsPreviousValue() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let kept = UsageWindow(kind: .fiveHour, label: "5h", usedFraction: 0.62, resetsAt: nil)
        let previous = Snapshot(
            schemaVersion: 1,
            generatedAt: now.addingTimeInterval(-600),
            providers: [
                .make(.claude, status: .notInstalled),
                .make(.codex, status: .ok, plan: "Codex plus", windows: [kept], fetchedAt: now.addingTimeInterval(-600)),
                .make(.cursor, status: .notInstalled),
            ]
        )
        let codex = ScriptedProvider(id: .codex, attempt: .from(error: .semantic("empty usage"), id: .codex, plan: nil))
        let refresher = Refresher(providers: [idleClaude(), codex, idleCursor(MockHTTP())], previous: previous, backoff: MemoryBackoffStore())
        let snapshot = await refresher.refresh(at: now, force: false)
        let row = try XCTUnwrap(snapshot.provider(.codex))
        XCTAssertEqual(row.status, .stale)
        XCTAssertEqual(row.staleReason, "empty usage")
        XCTAssertEqual(row.windows, [kept])
        XCTAssertEqual(row.planLabel, "Codex plus")
    }

    func testRateLimitBackoffThenSuccess() async {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let http = MockHTTP()
        http.status = 429
        let store = MemoryBackoffStore()
        let refresher = Refresher(providers: [idleClaude(), codex(http), idleCursor(http)], previous: nil, backoff: store)

        _ = await refresher.refresh(at: start, force: false)
        var state = await refresher.backoffState(.codex)
        XCTAssertEqual(state.blockedUntil, start.addingTimeInterval(Constants.retryAfterDefault))
        XCTAssertEqual(http.count, 1)

        _ = await refresher.refresh(at: start.addingTimeInterval(10), force: false)
        XCTAssertEqual(http.count, 1)

        let second = start.addingTimeInterval(Constants.retryAfterDefault + 1)
        _ = await refresher.refresh(at: second, force: false)
        state = await refresher.backoffState(.codex)
        XCTAssertEqual(state.blockedUntil, second.addingTimeInterval(Constants.retryAfterConsecutive))
        XCTAssertEqual(http.count, 2)

        let third = second.addingTimeInterval(Constants.retryAfterConsecutive + 1)
        _ = await refresher.refresh(at: third, force: false)
        state = await refresher.backoffState(.codex)
        XCTAssertEqual(state.blockedUntil, third.addingTimeInterval(Constants.retryAfterConsecutive))

        http.status = 200
        http.bodies["chatgpt.com"] = codexBody
        let fourth = third.addingTimeInterval(Constants.retryAfterConsecutive + 1)
        let snapshot = await refresher.refresh(at: fourth, force: false)
        state = await refresher.backoffState(.codex)
        XCTAssertNil(state.blockedUntil)
        XCTAssertEqual(state.consecutive429, 0)
        XCTAssertEqual(snapshot.provider(.codex)?.status, .ok)
        XCTAssertEqual(Constants.pollInterval, 300)
    }

    func testDisabledProviderIsHiddenAndRestoredOnEnable() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let kept = UsageWindow(kind: .fiveHour, label: "5h", usedFraction: 0.2, resetsAt: nil)
        let previous = Snapshot(
            schemaVersion: 1,
            generatedAt: now.addingTimeInterval(-600),
            providers: [
                .make(.claude, status: .ok, plan: "Pro", windows: [kept], fetchedAt: now.addingTimeInterval(-600)),
                .make(.codex, status: .notInstalled),
                .make(.cursor, status: .notInstalled),
            ]
        )
        let claude = ScriptedProvider(id: .claude, attempt: .from(error: .offline, id: .claude, plan: nil))
        let codex = ScriptedProvider(id: .codex, attempt: .ok(.codex, plan: "Codex plus", windows: [kept], at: now))
        let cursor = ScriptedProvider(id: .cursor, attempt: .ok(.cursor, plan: "Pro", windows: [kept], at: now))
        let refresher = Refresher(providers: [claude, codex, cursor], previous: previous, backoff: MemoryBackoffStore())
        let disabled = await refresher.refresh(at: now, force: true, enabled: [.codex, .cursor])
        XCTAssertEqual(disabled.provider(.claude)?.status, .notInstalled)
        XCTAssertEqual(disabled.provider(.claude)?.windows, [])
        XCTAssertEqual(disabled.provider(.codex)?.status, .ok)

        let restored = await refresher.refresh(at: now.addingTimeInterval(61), force: true)
        let claudeRow = try XCTUnwrap(restored.provider(.claude))
        XCTAssertEqual(claudeRow.status, .stale)
        XCTAssertEqual(claudeRow.planLabel, "Pro")
        XCTAssertEqual(claudeRow.windows, [kept])
    }

    func testRetryAfterIsClamped() async {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let http = MockHTTP()
        http.status = 429
        http.headers = ["Retry-After": "7200"]
        let refresher = Refresher(providers: [idleClaude(), codex(http), idleCursor(http)], previous: nil, backoff: MemoryBackoffStore())
        _ = await refresher.refresh(at: now, force: false)
        let state = await refresher.backoffState(.codex)
        XCTAssertEqual(state.blockedUntil, now.addingTimeInterval(Constants.retryAfterMax))
    }

    func testNeedsLoginDoesNotUseNetwork() async {
        let now = Date()
        let http = MockHTTP()
        let provider = CodexProvider(userAgent: "AgentCoaming/1 (macOS)", http: http, read: {
            .found(CodexCredential(accessToken: "expired", accountID: nil, expiresAt: now.addingTimeInterval(-120)))
        })
        let refresher = Refresher(providers: [idleClaude(), provider, idleCursor(http)], previous: nil, backoff: MemoryBackoffStore())
        let snapshot = await refresher.refresh(at: now, force: true)
        XCTAssertEqual(http.count, 0)
        XCTAssertEqual(snapshot.provider(.codex)?.status, .needsLogin)
        XCTAssertTrue(snapshot.provider(.codex)?.staleReason?.contains("token expired") == true)
    }

    func testManualRefreshRespectsRecentAttempt() async {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let http = MockHTTP()
        http.status = 429
        let refresher = Refresher(providers: [idleClaude(), codex(http), idleCursor(http)], previous: nil, backoff: MemoryBackoffStore())
        _ = await refresher.refresh(at: now, force: false)
        XCTAssertEqual(http.count, 1)
        _ = await refresher.refresh(at: now.addingTimeInterval(10), force: true)
        XCTAssertEqual(http.count, 1)
        _ = await refresher.refresh(at: now.addingTimeInterval(61), force: true)
        XCTAssertEqual(http.count, 2)
    }

    func testFreshProcessIgnoresPersistedRecentAttempt() async {
        // coaming CLI: no previous snapshot, but the backoff store still has lastAttemptAt from an earlier process.
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let http = MockHTTP()
        http.bodies["chatgpt.com"] = codexBody
        let store = MemoryBackoffStore()
        store.save(.codex, BackoffState(blockedUntil: nil, consecutive429: 0, lastAttemptAt: now.addingTimeInterval(-10)))
        let refresher = Refresher(providers: [idleClaude(), codex(http), idleCursor(http)], previous: nil, backoff: store)
        let snapshot = await refresher.refresh(at: now, force: true)
        XCTAssertEqual(http.count, 1)
        XCTAssertEqual(snapshot.provider(.codex)?.status, .ok)
    }

    func testFreshProcessStillRespectsRateLimitBlock() async {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let http = MockHTTP()
        let store = MemoryBackoffStore()
        store.save(.codex, BackoffState(blockedUntil: now.addingTimeInterval(600), consecutive429: 1, lastAttemptAt: now.addingTimeInterval(-120)))
        let refresher = Refresher(providers: [idleClaude(), codex(http), idleCursor(http)], previous: nil, backoff: store)
        _ = await refresher.refresh(at: now, force: true)
        XCTAssertEqual(http.count, 0)
    }

    func testConcurrentRefreshFetchesOnce() async {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let counting = CountingProvider(id: .codex)
        let refresher = Refresher(providers: [idleClaude(), counting, idleCursor(MockHTTP())], previous: nil, backoff: MemoryBackoffStore())
        async let first = refresher.refresh(at: now, force: true)
        async let second = refresher.refresh(at: now, force: true)
        _ = await (first, second)
        XCTAssertEqual(counting.counter.value, 1)
    }

    func testDisallowedHostIsAnError() async {
        let client = EphemeralHTTPClient()
        var request = URLRequest(url: URL(string: "https://example.com/usage")!)
        do {
            _ = try await client.send(request)
            XCTFail("expected rejection")
        } catch UsageFetchError.disallowedHost {
        } catch {
            XCTFail("unexpected \(error)")
        }
        request = URLRequest(url: URL(string: "http://chatgpt.com/backend-api/wham/usage")!)
        do {
            _ = try await client.send(request)
            XCTFail("expected rejection")
        } catch UsageFetchError.disallowedHost {
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testRedirectMustStayOnSameHost() {
        let gate = AllowlistRedirectGate()
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URLRequest(url: URL(string: "https://chatgpt.com/a")!))
        let response = HTTPURLResponse(url: URL(string: "https://chatgpt.com/a")!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let crossHost = expectation(description: "cross host")
        gate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "https://cursor.com/b")!)) { request in
            XCTAssertNil(request)
            crossHost.fulfill()
        }
        let sameHost = expectation(description: "same host")
        gate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "https://chatgpt.com/b")!)) { request in
            XCTAssertNotNil(request)
            sameHost.fulfill()
        }
        let otherPort = expectation(description: "other port")
        gate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "https://chatgpt.com:8443/b")!)) { request in
            XCTAssertNil(request)
            otherPort.fulfill()
        }
        wait(for: [crossHost, sameHost, otherPort], timeout: 1)
    }
}

private struct ScriptedProvider: UsageProvider {
    var id: ProviderID
    var attempt: ProviderAttempt
    func fetch(now: Date) async -> ProviderAttempt { attempt }
}

private final class CountingProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let counter = CallCounter()
    init(id: ProviderID) { self.id = id }
    func fetch(now: Date) async -> ProviderAttempt {
        counter.increment()
        try? await Task.sleep(for: .milliseconds(100))
        return .ok(id, plan: nil, windows: [], at: now)
    }
}

private let codexBody = Data(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":4,"limit_window_seconds":18000,"reset_after_seconds":10}}}"#.utf8)

private func codex(_ http: MockHTTP) -> CodexProvider {
    CodexProvider(userAgent: "AgentCoaming/1 (macOS)", http: http, read: {
        .found(CodexCredential(accessToken: "token", accountID: nil, expiresAt: nil))
    })
}

private func idleClaude() -> ClaudeProvider {
    ClaudeProvider(read: { .notInstalled })
}

private func idleCursor(_ http: MockHTTP) -> CursorProvider {
    CursorProvider(
        userAgent: "AgentCoaming/1 (macOS)",
        http: http,
        supportDirectoryURL: URL(fileURLWithPath: "/tmp/coaming-missing-cursor"),
        read: { .missing }
    )
}
