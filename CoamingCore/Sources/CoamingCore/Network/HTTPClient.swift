import Foundation

protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

enum UsageFetchError: Error, Sendable {
    case disallowedHost
    case offline
    case http(status: Int, retryAfter: TimeInterval?)
    case decode(keyTree: String)
    case semantic(String)
}

struct EphemeralHTTPClient: HTTPClient {
    private let session: URLSession
    private let redirectGate: AllowlistRedirectGate

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Constants.requestTimeout
        configuration.timeoutIntervalForResource = Constants.requestTimeout
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let gate = AllowlistRedirectGate()
        redirectGate = gate
        session = URLSession(configuration: configuration, delegate: gate, delegateQueue: nil)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try validate(request)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw UsageFetchError.offline }
            return (data, http)
        } catch let error as UsageFetchError {
            throw error
        } catch {
            throw UsageFetchError.offline
        }
    }

    private func validate(_ request: URLRequest) throws {
        guard let url = request.url, url.scheme == "https", let host = url.host?.lowercased() else {
            throw UsageFetchError.disallowedHost
        }
        if let port = url.port, port != 443 {
            throw UsageFetchError.disallowedHost
        }
        guard Constants.allowedHosts.contains(host) else {
            throw UsageFetchError.disallowedHost
        }
    }
}

final class AllowlistRedirectGate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Do not follow a redirect to another host. Cookie and Authorization would be sent along.
        guard let url = request.url, url.scheme == "https", let host = url.host?.lowercased(),
              Constants.allowedHosts.contains(host),
              url.port == nil || url.port == 443,
              host == task.originalRequest?.url?.host?.lowercased() else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
