import XCTest
@testable import CoamingCore

final class UpdateCheckTests: XCTestCase {
    func testParseKeepsOnlyTheTag() throws {
        let data = Data(#"{"tag_name":"v1.3.0","html_url":"https://evil.example/phish"}"#.utf8)
        let release = try UpdateCheck.parse(data)
        XCTAssertEqual(release.version, "1.3.0")
        XCTAssertEqual(
            release.pageURL.absoluteString,
            "https://github.com/toritori0318/agent-coaming/releases/tag/v1.3.0"
        )
    }

    func testParseRejectsATagThatIsNotAVersion() {
        for tag in ["latest", "v1.2.1-beta", "v1.", "../v1.2.1", "1.2.1"] {
            let data = Data(#"{"tag_name":"\#(tag)"}"#.utf8)
            XCTAssertThrowsError(try UpdateCheck.parse(data), "\(tag)")
        }
    }

    func testNewerComparesEachNumericPart() {
        XCTAssertTrue(UpdateCheck.isNewer("1.2.10", than: "1.2.9"))
        XCTAssertTrue(UpdateCheck.isNewer("1.3", than: "1.2.1"))
        XCTAssertTrue(UpdateCheck.isNewer("v1.2.1", than: "1.2.0"))
        XCTAssertFalse(UpdateCheck.isNewer("1.2.1", than: "1.2.1"))
        XCTAssertFalse(UpdateCheck.isNewer("1.2", than: "1.2.0"))
        XCTAssertFalse(UpdateCheck.isNewer("1.2.0", than: "1.2.1"))
    }

    func testLatestAsksTheReleaseAPI() async throws {
        let http = MockHTTP()
        http.bodies["api.github.com"] = Data(#"{"tag_name":"v9.0.0"}"#.utf8)
        let release = try await ReleaseChecker.latest(http: http, userAgent: "AgentCoaming/1.2.1 (macOS)")
        XCTAssertEqual(http.count, 1)
        XCTAssertEqual(release.version, "9.0.0")
    }
}
