import Foundation

// The data model. Field names and optionality mirror the web app's JSON one to
// one, so both apps read and write the same files in ~/.local-postman and can
// run side by side while one replaces the other. Every optional here is a field
// that older collections do not have; the `…Value` accessors supply the default.

public let appVersion = "2.0"

public enum HTTPMethod: String, Codable, CaseIterable, Sendable {
    case GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS
}

/// An MCP request is still an HTTP POST, so it keeps the URL, headers and auth
/// and only swaps what goes in the body. Making it a kind rather than a separate
/// entity is what lets collections, variables, auth and history stay one
/// implementation instead of two.
public enum RequestKind: String, Codable, Sendable {
    case http, mcp
}

public enum BodyType: String, Codable, CaseIterable, Sendable {
    case none, json, raw
}

public struct KeyValue: Codable, Hashable, Sendable {
    public var key: String
    public var value: String
    public var enabled: Bool

    public init(key: String = "", value: String = "", enabled: Bool = true) {
        self.key = key
        self.value = value
        self.enabled = enabled
    }

    /// Counts towards a request: switched on and named.
    public var isActive: Bool { enabled && !key.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// The colours a collection can be tagged with. Green for development, red for
/// production, and so on - the meaning is the user's, only the palette is ours.
public let collectionColors: [String] = [
    "#22c55e", // green
    "#3b82f6", // blue
    "#f59e0b", // amber
    "#ef4444", // red
    "#a855f7", // purple
    "#14b8a6", // teal
    "#6b7280", // grey
]

public enum AuthMode: String, Codable, CaseIterable, Sendable {
    case none, basic
}

/// A request may also defer to its collection, which is the default.
public enum RequestAuthMode: String, Codable, CaseIterable, Sendable {
    case inherit, none, basic
}

public struct BasicAuth: Codable, Hashable, Sendable {
    public var username: String
    public var password: String
    /// Standard HTTP Basic, and what ORDS expects. Off sends the raw `user:pass` instead.
    public var base64: Bool

    public init(username: String = "", password: String = "", base64: Bool = true) {
        self.username = username
        self.password = password
        self.base64 = base64
    }
}

public struct CollectionAuth: Codable, Hashable, Sendable {
    public var mode: AuthMode
    public var basic: BasicAuth

    public init(mode: AuthMode = .none, basic: BasicAuth = BasicAuth()) {
        self.mode = mode
        self.basic = basic
    }
}

public struct RequestAuth: Codable, Hashable, Sendable {
    public var mode: RequestAuthMode
    public var basic: BasicAuth

    public init(mode: RequestAuthMode = .inherit, basic: BasicAuth = BasicAuth()) {
        self.mode = mode
        self.basic = basic
    }
}

public struct ApiRequest: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var method: HTTPMethod
    public var url: String
    public var params: [KeyValue]
    public var headers: [KeyValue]
    public var body: String
    public var bodyType: BodyType
    public var auth: RequestAuth?   // absent in collections saved before v1.1
    public var kind: RequestKind?   // absent before v1.6, meaning .http
    public var mcp: McpConfig?      // only meaningful when kind == .mcp

    public init(
        id: String = newID("req"),
        name: String = "New Request",
        method: HTTPMethod = .GET,
        url: String = "",
        params: [KeyValue] = [],
        headers: [KeyValue] = [],
        body: String = "",
        bodyType: BodyType = .none,
        auth: RequestAuth? = RequestAuth(),
        kind: RequestKind? = nil,
        mcp: McpConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.method = method
        self.url = url
        self.params = params
        self.headers = headers
        self.body = body
        self.bodyType = bodyType
        self.auth = auth
        self.kind = kind
        self.mcp = mcp
    }

    public static func newHTTP() -> ApiRequest { ApiRequest() }

    /// Equal when every field is, with the body compared byte for byte.
    ///
    /// The synthesised == compares strings by Unicode canonical equivalence,
    /// which normalises both sides; on a megabyte body coming out of a text view
    /// that is tens of milliseconds per keystroke. Bytes are also the better
    /// question here: they are what gets sent.
    public static func == (a: ApiRequest, b: ApiRequest) -> Bool {
        a.id == b.id && a.name == b.name && a.method == b.method && a.url == b.url
            && a.params == b.params && a.headers == b.headers && a.bodyType == b.bodyType
            && a.auth == b.auth && a.kind == b.kind && a.mcp == b.mcp
            && sameBytes(a.body, b.body)
    }

    public static func newMCP() -> ApiRequest {
        // The transport is always a POST; only the body differs from an HTTP request.
        ApiRequest(name: "New MCP Request", method: .POST, kind: .mcp, mcp: McpConfig())
    }

    public var kindValue: RequestKind { kind ?? .http }
    public var isMCP: Bool { kindValue == .mcp }

    public var authValue: RequestAuth {
        get { auth ?? RequestAuth() }
        set { auth = newValue }
    }

    public var mcpValue: McpConfig {
        get { mcp ?? McpConfig() }
        set { mcp = newValue }
    }

    /// What the method column shows. MCP requests are POSTs but never read as one.
    public var badge: String { isMCP ? "MCP" : method.rawValue }

    /// A copy with a fresh id, for Duplicate.
    public func duplicated() -> ApiRequest {
        var copy = self
        copy.id = newID("req")
        copy.name = name + " copy"
        return copy
    }
}

public struct RequestGroup: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var requests: [ApiRequest]
    public var auth: CollectionAuth?   // absent before v1.1
    public var variables: [KeyValue]?  // absent before v1.3
    public var color: String?          // absent before v1.7, meaning untagged
    /// Sidebar position. Collections are one file each and arrive in directory
    /// order, which is neither insertion order nor stable between machines, so
    /// they need an explicit one. Requests do not: they are an array in one file.
    public var order: Int?

    public init(
        id: String = newID("group"),
        name: String = "New Collection",
        requests: [ApiRequest] = [],
        auth: CollectionAuth? = CollectionAuth(),
        variables: [KeyValue]? = [],
        color: String? = collectionColors[0],
        order: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.requests = requests
        self.auth = auth
        self.variables = variables
        self.color = color
        self.order = order
    }

    public var authValue: CollectionAuth {
        get { auth ?? CollectionAuth() }
        set { auth = newValue }
    }

    public var variablesValue: [KeyValue] {
        get { variables ?? [] }
        set { variables = newValue }
    }

    public var activeVariableCount: Int { variablesValue.filter(\.isActive).count }

    /// Either variables or auth set: what turns the ⚙ accent-coloured.
    public var isConfigured: Bool { authValue.mode == .basic || activeVariableCount > 0 }
}

/// Sidebar order: explicit where set, and everything unordered trails it by name.
public func sortGroups(_ groups: [RequestGroup]) -> [RequestGroup] {
    groups.sorted { a, b in
        let ao = a.order ?? Int.max
        let bo = b.order ?? Int.max
        if ao == bo { return a.name.localizedCompare(b.name) == .orderedAscending }
        return ao < bo
    }
}

public struct ApiResponse: Codable, Hashable, Sendable {
    public var status: Int
    public var statusText: String
    public var headers: [String: String]
    public var body: String
    public var contentType: String
    public var timeMs: Double
    public var sizeBytes: Int
    public var error: String?

    public init(
        status: Int,
        statusText: String = "",
        headers: [String: String] = [:],
        body: String = "",
        contentType: String = "",
        timeMs: Double = 0,
        sizeBytes: Int = 0,
        error: String? = nil
    ) {
        self.status = status
        self.statusText = statusText
        self.headers = headers
        self.body = body
        self.contentType = contentType
        self.timeMs = timeMs
        self.sizeBytes = sizeBytes
        self.error = error
    }

    /// Nothing came back at all: DNS, refused connection, timeout, or a request
    /// this app rejected before sending. The viewer shows only the message then.
    public var isBareFailure: Bool { error != nil && status == 0 }

    public static func failure(_ message: String, timeMs: Double = 0) -> ApiResponse {
        ApiResponse(status: 0, timeMs: timeMs, error: message)
    }
}

/// The JSON-RPC method and params an MCP request resolved to. It lives on the
/// resolved request so a history replay of an MCP call replays as MCP.
public struct McpCall: Codable, Hashable, Sendable {
    public var method: McpMethod
    public var params: [String: JSONValue]

    public init(method: McpMethod, params: [String: JSONValue]) {
        self.method = method
        self.params = params
    }
}

public struct ResolvedRequest: Codable, Hashable, Sendable {
    public var url: String
    public var method: HTTPMethod
    public var headers: [String: String]
    public var body: String?
    public var mcp: McpCall?

    public init(url: String, method: HTTPMethod, headers: [String: String], body: String? = nil, mcp: McpCall? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.mcp = mcp
    }
}

public struct HistoryItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    /// Milliseconds since 1970, as the web app wrote it.
    public var timestamp: Double
    public var name: String?   // absent in history recorded before v1.2
    public var method: HTTPMethod
    public var url: String
    public var resolved: ResolvedRequest
    public var response: ApiResponse

    public init(
        id: String = newID("h"),
        timestamp: Double = Date().timeIntervalSince1970 * 1000,
        name: String?,
        method: HTTPMethod,
        url: String,
        resolved: ResolvedRequest,
        response: ApiResponse
    ) {
        self.id = id
        self.timestamp = timestamp
        self.name = name
        self.method = method
        self.url = url
        self.resolved = resolved
        self.response = response
    }

    public var date: Date { Date(timeIntervalSince1970: timestamp / 1000) }

    /// A replayed MCP call is a POST on the wire; the badge must not say so.
    public var badge: String { resolved.mcp != nil ? "MCP" : method.rawValue }

    public var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? "Unnamed request" : trimmed
    }
}

public let historyLimit = 50

/// `prefix-<ms>-<random>`, the same shape the web app mints.
public func newID(_ prefix: String) -> String {
    let ms = Int(Date().timeIntervalSince1970 * 1000)
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    let suffix = String((0..<5).map { _ in alphabet.randomElement()! })
    return "\(prefix)-\(ms)-\(suffix)"
}

extension Array {
    /// Move one element to another index, as a drag in a list does.
    public func moving(from: Int, to: Int) -> [Element] {
        guard from != to, indices.contains(from), indices.contains(to) else { return self }
        var next = self
        let item = next.remove(at: from)
        next.insert(item, at: to)
        return next
    }
}

/// Byte equality of two strings: a stricter test than ==, and without its
/// Unicode normalisation, so it costs a memory compare on large text.
public func sameBytes(_ a: String, _ b: String) -> Bool {
    var a = a, b = b
    return a.withUTF8 { x in b.withUTF8 { y in x.count == y.count && (x.count == 0 || memcmp(x.baseAddress!, y.baseAddress!, x.count) == 0) } }
}
