import Foundation

enum HTTPKind {
    case billingGET
    case refreshPOST
}

struct HTTPResult {
    var status: Int
    var body: Data
    var connectionFailed: Bool
}

final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    let kind: HTTPKind
    private var hops = 0

    init(kind: HTTPKind) {
        self.kind = kind
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if kind == .refreshPOST {
            completionHandler(nil)
            return
        }
        hops += 1
        guard hops <= 1, let url = request.url, url.scheme == "https" else {
            completionHandler(nil)
            return
        }
        guard url.host == "cli-chat-proxy.grok.com" else {
            completionHandler(nil)
            return
        }
        let port = url.port ?? 443
        guard port == 443 else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

enum HTTPClient {
    static func perform(
        request: URLRequest,
        kind: HTTPKind,
        proxyPort: Int?
    ) -> HTTPResult {
        let config = URLSessionConfiguration.ephemeral
        let seconds: TimeInterval = kind == .refreshPOST ? 10 : 20
        config.timeoutIntervalForRequest = seconds
        config.timeoutIntervalForResource = seconds
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.urlCredentialStorage = nil
        if let proxyPort {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: "127.0.0.1",
                kCFNetworkProxiesHTTPPort as String: proxyPort,
                kCFNetworkProxiesHTTPSEnable as String: true,
                kCFNetworkProxiesHTTPSProxy as String: "127.0.0.1",
                kCFNetworkProxiesHTTPSPort as String: proxyPort,
            ]
        }
        let guardDelegate = RedirectGuard(kind: kind)
        let session = URLSession(configuration: config, delegate: guardDelegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let box = SyncBox()
        let task = session.dataTask(with: request) { data, response, error in
            box.finish(data: data, response: response, error: error)
        }
        task.resume()
        box.wait()

        if box.error != nil, box.response == nil {
            return HTTPResult(status: -1, body: Data(), connectionFailed: true)
        }
        let status = (box.response as? HTTPURLResponse)?.statusCode ?? -1
        return HTTPResult(status: status, body: box.data ?? Data(), connectionFailed: false)
    }

    static func billingRequest(accessToken: String) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!)
        req.httpMethod = "GET"
        applyCommonHeaders(&req, bearer: accessToken)
        return req
    }

    static func refreshRequest(clientID: String, refreshToken: String) -> URLRequest? {
        guard
            let encodedRefresh = AuthStore.formEncode(refreshToken),
            let encodedClient = AuthStore.formEncode(clientID),
            !encodedRefresh.isEmpty,
            !encodedClient.isEmpty
        else {
            return nil
        }
        var req = URLRequest(url: URL(string: "https://auth.x.ai/oauth2/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        applyCommonHeaders(&req, bearer: nil)
        let body =
            "grant_type=refresh_token&refresh_token=\(encodedRefresh)&client_id=\(encodedClient)"
        req.httpBody = body.data(using: .utf8)
        return req
    }

    private static func applyCommonHeaders(_ req: inout URLRequest, bearer: String?) {
        req.setValue("GrokQuota/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("grok-shell", forHTTPHeaderField: "x-grok-client-identifier")
        req.setValue("1.0.5", forHTTPHeaderField: "x-grok-client-version")
        req.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        if let bearer {
            req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
    }
}

private final class SyncBox: @unchecked Sendable {
    private let lock = NSCondition()
    private var done = false
    var data: Data?
    var response: URLResponse?
    var error: Error?

    func finish(data: Data?, response: URLResponse?, error: Error?) {
        lock.lock()
        self.data = data
        self.response = response
        self.error = error
        done = true
        lock.broadcast()
        lock.unlock()
    }

    func wait() {
        lock.lock()
        while !done { lock.wait() }
        lock.unlock()
    }
}
