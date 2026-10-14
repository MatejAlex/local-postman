import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Sending a resolved request. The web app needed a server-side proxy to get
// around browser CORS; a native app has no CORS, so this is just the client.
// What the proxy did beyond that is kept: a 30 s timeout, redirects followed by
// hand so credentials are dropped when a hop changes origin, and failures that
// come back as a structured response instead of a thrown error.

public let requestTimeout: TimeInterval = 30
let maxRedirects = 5
let sensitiveHeaders: Set<String> = ["authorization", "cookie", "proxy-authorization"]

/// One HTTP exchange, as the transport sees it.
public struct WireRequest: Sendable, Equatable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?

    public init(url: URL, method: String, headers: [String: String], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct WireResponse: Sendable {
    public var status: Int
    /// Header names lowercased, as fetch() reported them in the web app.
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public var text: String { String(decoding: body, as: UTF8.self) }
}

/// Performs exactly one exchange and never follows a redirect itself. Tests
/// substitute a fake; the app uses `URLSessionTransport`.
public protocol HTTPTransport: Sendable {
    func perform(_ request: WireRequest) async throws -> WireResponse
}

public final class URLSessionTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    public override init() { super.init() }

    public func perform(_ request: WireRequest) async throws -> WireResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<WireResponse, Error>) in
                let task = session.dataTask(with: urlRequest) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let http = response as? HTTPURLResponse else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    var headers: [String: String] = [:]
                    for (key, value) in http.allHeaderFields {
                        headers[String(describing: key).lowercased()] = String(describing: value)
                    }
                    continuation.resume(returning: WireResponse(status: http.statusCode, headers: headers, body: data ?? Data()))
                }
                box.task = task
                task.resume()
            }
        } onCancel: {
            box.task?.cancel()
        }
    }

    // Hand every redirect back to the caller instead of following it.
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    #if canImport(Security)
    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              !SecTrustEvaluateWithError(trust, nil),
              let result = SecTrustCopyResult(trust) as? [String: Any],
              let details = result["TrustResultDetails"] as? [[String: Any]],
              failsOnlyOnValidityPeriod(details.flatMap { $0["StatusCodes"] as? [Int] ?? [] })
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    #endif
}

/// The status Apple's TLS check reports for a server certificate valid for more
/// than 825 days. It applies even to a private CA, where internal certificates
/// are routinely issued for years; node, and so the web app, never enforced it.
public let validityPeriodTooLongStatus = -2147409651

/// Whether a failed trust evaluation failed on nothing but the validity-period
/// rule. The chain, its anchor and the hostname are all still checked: any of
/// those failing adds its own status, and the certificate is rejected.
public func failsOnlyOnValidityPeriod(_ statusCodes: [Int]) -> Bool {
    !statusCodes.isEmpty && statusCodes.allSatisfy { $0 == validityPeriodTooLongStatus }
}

private final class TaskBox: @unchecked Sendable {
    var task: URLSessionTask?
}

public enum SendError: Error, LocalizedError, Equatable {
    case tooManyRedirects
    case nonHTTPRedirect
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .tooManyRedirects: "Too many redirects"
        case .nonHTTPRedirect: "Redirect to non-http(s) URL"
        case .timedOut: "Request timed out after \(Int(requestTimeout))s"
        }
    }
}

/// An absolute http(s) URL, or the message explaining why it is not one.
func httpURL(_ text: String) -> Result<URL, ResolveError> {
    guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)),
          let scheme = url.scheme?.lowercased(), url.host != nil
    else { return .failure(ResolveError("URL must be an absolute http(s) address.")) }
    guard scheme == "http" || scheme == "https" else {
        return .failure(ResolveError("Only http(s) URLs are supported."))
    }
    return .success(url)
}

func origin(of url: URL) -> String {
    "\(url.scheme?.lowercased() ?? "")://\(url.host?.lowercased() ?? ""):\(url.port ?? -1)"
}

/// Follow redirects by hand so credentials can be dropped when a hop crosses
/// origins. 303 (and POST on 301/302) downgrade to GET; 307/308 keep method and body.
public func performFollowingRedirects(_ start: WireRequest, transport: HTTPTransport) async throws -> WireResponse {
    var request = start
    for hop in 0...maxRedirects {
        let response = try await transport.perform(request)
        guard (300..<400).contains(response.status), let location = response.headers["location"] else {
            return response
        }
        if hop == maxRedirects { throw SendError.tooManyRedirects }
        guard let next = URL(string: location, relativeTo: request.url)?.absoluteURL,
              let scheme = next.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { throw SendError.nonHTTPRedirect }

        if origin(of: next) != origin(of: request.url) {
            // Cross-origin hop: never carry the original credentials onward.
            request.headers = request.headers.filter { !sensitiveHeaders.contains($0.key.lowercased()) }
        }
        if response.status == 303 || ((response.status == 301 || response.status == 302) && request.method == "POST") {
            request.method = "GET"
            request.body = nil
        }
        request.url = next
    }
    throw SendError.tooManyRedirects
}

/// Run `operation`, failing with `SendError.timedOut` once `seconds` have passed.
func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw SendError.timedOut
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

public func reasonPhrase(_ status: Int) -> String {
    let phrases: [Int: String] = [
        200: "OK", 201: "Created", 202: "Accepted", 204: "No Content",
        301: "Moved Permanently", 302: "Found", 303: "See Other", 304: "Not Modified",
        307: "Temporary Redirect", 308: "Permanent Redirect",
        400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
        405: "Method Not Allowed", 406: "Not Acceptable", 408: "Request Timeout", 409: "Conflict",
        410: "Gone", 413: "Payload Too Large", 415: "Unsupported Media Type",
        422: "Unprocessable Entity", 429: "Too Many Requests",
        500: "Internal Server Error", 501: "Not Implemented", 502: "Bad Gateway",
        503: "Service Unavailable", 504: "Gateway Timeout",
    ]
    return phrases[status] ?? ""
}

func message(for error: Error) -> String {
    if let error = error as? SendError { return error.errorDescription ?? "Request failed" }
    if let error = error as? URLError {
        switch error.code {
        case .timedOut: return SendError.timedOut.errorDescription!
        case .cancelled: return ApiResponse.cancelledMessage
        default: break
        }
    }
    if error is CancellationError { return ApiResponse.cancelledMessage }
    return error.localizedDescription
}

func milliseconds(since start: Date) -> Double {
    Date().timeIntervalSince(start) * 1000
}

/// Sends resolved requests, either kind, and always answers with a response.
public struct Sender: Sendable {
    public var transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    /// Dispatching on the resolved request rather than the editor's state is
    /// what makes a history replay of an MCP call replay as MCP.
    public func send(_ resolved: ResolvedRequest) async -> ApiResponse {
        if let call = resolved.mcp {
            return await McpClient(transport: transport).call(url: resolved.url, headers: resolved.headers, call: call)
        }
        return await sendHTTP(resolved)
    }

    func sendHTTP(_ resolved: ResolvedRequest) async -> ApiResponse {
        let started = Date()
        let url: URL
        switch httpURL(resolved.url) {
        case .success(let value): url = value
        case .failure(let error): return .failure(error.message)
        }

        let wire = WireRequest(
            url: url,
            method: resolved.method.rawValue,
            headers: resolved.headers,
            body: resolved.method == .GET || resolved.method == .HEAD ? nil : resolved.body.map { Data($0.utf8) }
        )
        let transport = self.transport
        do {
            let response = try await withTimeout(requestTimeout) {
                try await performFollowingRedirects(wire, transport: transport)
            }
            return ApiResponse(
                status: response.status,
                statusText: reasonPhrase(response.status),
                headers: response.headers,
                body: response.text,
                contentType: response.headers["content-type"] ?? "",
                timeMs: milliseconds(since: started),
                sizeBytes: response.body.count
            )
        } catch {
            return .failure(message(for: error), timeMs: milliseconds(since: started))
        }
    }
}
