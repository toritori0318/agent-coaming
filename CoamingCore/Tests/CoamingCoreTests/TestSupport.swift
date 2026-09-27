import Foundation
import Synchronization
import XCTest
@testable import CoamingCore

enum Fixtures {
    static func data(_ name: String) throws -> Data {
        let bundle = Bundle.module
        let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: "json")
        guard let url else {
            throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(name)"])
        }
        return try Data(contentsOf: url)
    }

    static func json(_ name: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: data(name)) as? [String: Any] ?? [:]
    }
}

final class MockHTTP: HTTPClient, @unchecked Sendable {
    var bodies: [String: Data] = [:]
    var status = 200
    var headers: [String: String] = [:]
    private let counter = Mutex(0)
    var count: Int { counter.withLock { $0 } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        counter.withLock { $0 += 1 }
        let host = request.url?.host ?? ""
        let body = bodies[host] ?? Data("{}".utf8)
        let response = HTTPURLResponse(url: request.url ?? URL(string: "https://cursor.com/")!, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (body, response)
    }
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeJWT(payload: [String: Any], padding: Bool = false) throws -> String {
    let header = try JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
    let body = try JSONSerialization.data(withJSONObject: payload)
    func encode(_ data: Data) -> String {
        var text = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        if !padding {
            text = text.replacingOccurrences(of: "=", with: "")
        }
        return text
    }
    return "\(encode(header)).\(encode(body)).sig"
}
