import Foundation

// Turning a stored request into what goes on the wire: variables substituted,
// query params appended, auth applied.

public typealias Variables = [String: String]

/// Flatten key/value rows into a lookup, skipping the disabled and the unnamed.
public func variableMap(_ rows: [KeyValue]) -> Variables {
    var map: Variables = [:]
    for row in rows where row.isActive {
        map[row.key] = row.value
    }
    return map
}

/// Everything a request can reference: its collection's variables, and nothing
/// else. A collection is the only place a `{{key}}` can come from.
public func requestVariables(_ group: RequestGroup?) -> Variables {
    group.map { variableMap($0.variablesValue) } ?? [:]
}

// ASCII word characters, dot and dash: the same set the web app's `[\w.-]` matched.
private let variablePattern = try! NSRegularExpression(pattern: #"\{\{\s*([A-Za-z0-9_.\-]+)\s*\}\}"#)

/// Replace every `{{key}}` with its value. A key defined nowhere is left
/// verbatim rather than blanked, so the gap is visible on the wire.
public func substitute(_ text: String, _ vars: Variables) -> String {
    guard text.contains("{{") else { return text }
    let ns = text as NSString
    var result = ""
    var cursor = 0
    for match in variablePattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
        result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
        let key = ns.substring(with: match.range(at: 1))
        result += vars[key] ?? ns.substring(with: match.range)
        cursor = match.range.location + match.range.length
    }
    result += ns.substring(from: cursor)
    return result
}

/// The `{{keys}}` a text references that the map does not define.
public func undefinedVariables(in text: String, _ vars: Variables) -> [String] {
    let ns = text as NSString
    var missing: [String] = []
    for match in variablePattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
        let key = ns.substring(with: match.range(at: 1))
        if vars[key] == nil, !missing.contains(key) { missing.append(key) }
    }
    return missing
}

/// What JavaScript's encodeURIComponent leaves alone.
private let uriComponentAllowed: CharacterSet = {
    var set = CharacterSet()
    set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
    return set
}()

public func encodeURIComponent(_ text: String) -> String {
    text.addingPercentEncoding(withAllowedCharacters: uriComponentAllowed) ?? text
}

/// Append enabled query params to a URL string.
public func buildURL(_ url: String, params: [KeyValue], vars: Variables) -> String {
    let resolved = substitute(url, vars)
    let active = params.filter(\.isActive)
    if active.isEmpty { return resolved }
    let separator = resolved.contains("?") ? "&" : "?"
    let query = active
        .map { "\(encodeURIComponent(substitute($0.key, vars)))=\(encodeURIComponent(substitute($0.value, vars)))" }
        .joined(separator: "&")
    return resolved + separator + query
}

/// The Authorization value for a credential pair, or nil when nothing is filled
/// in. With base64 off the credentials go out verbatim, which is not valid HTTP
/// Basic but is useful for seeing what a gateway actually receives.
public func basicAuthHeader(_ basic: BasicAuth, vars: Variables) -> String? {
    let username = substitute(basic.username, vars)
    let password = substitute(basic.password, vars)
    if username.isEmpty && password.isEmpty { return nil }
    let pair = "\(username):\(password)"
    return "Basic " + (basic.base64 ? Data(pair.utf8).base64EncodedString() : pair)
}

/// The request's own setting wins; inherit falls back to the collection, none sends nothing.
public func authHeader(for request: ApiRequest, collectionAuth: CollectionAuth?, vars: Variables) -> String? {
    let auth = request.authValue
    switch auth.mode {
    case .none:
        return nil
    case .basic:
        return basicAuthHeader(auth.basic, vars: vars)
    case .inherit:
        guard let collectionAuth, collectionAuth.mode == .basic else { return nil }
        return basicAuthHeader(collectionAuth.basic, vars: vars)
    }
}

/// Resolve an HTTP request into a concrete URL, headers and body.
public func resolveRequest(_ request: ApiRequest, group: RequestGroup?) -> ResolvedRequest {
    let vars = requestVariables(group)
    let url = buildURL(request.url, params: request.params, vars: vars)

    var headers: [String: String] = [:]
    for header in request.headers where header.isActive {
        headers[substitute(header.key, vars)] = substitute(header.value, vars)
    }

    // An Authorization header typed by hand wins over the auth panels.
    if !headers.keys.contains(where: { $0.lowercased() == "authorization" }),
       let value = authHeader(for: request, collectionAuth: group?.authValue, vars: vars) {
        headers["Authorization"] = value
    }

    var body: String?
    if request.method != .GET, request.method != .HEAD, request.bodyType != .none {
        body = substitute(request.body, vars)
        if request.bodyType == .json, !headers.keys.contains(where: { $0.lowercased() == "content-type" }) {
            headers["Content-Type"] = "application/json"
        }
    }

    return ResolvedRequest(url: url, method: request.method, headers: headers, body: body)
}

/// Resolve an MCP request, or explain what is wrong with it. URL, headers and
/// auth resolve exactly as an HTTP request's do; `{{variables}}` also reach the
/// target and the arguments.
public func resolveMcpRequest(_ request: ApiRequest, group: RequestGroup?) -> Result<ResolvedRequest, ResolveError> {
    let vars = requestVariables(group)
    var config = request.mcpValue
    config.target = substitute(config.target, vars)
    config.args = substitute(config.args, vars)

    switch mcpParams(for: config) {
    case .failure(let error):
        return .failure(error)
    case .success(let params):
        var plain = request
        plain.bodyType = .none
        var resolved = resolveRequest(plain, group: group)
        resolved.method = .POST
        resolved.body = nil
        resolved.mcp = McpCall(method: config.method, params: params)
        return .success(resolved)
    }
}

/// Resolve either kind.
public func resolve(_ request: ApiRequest, group: RequestGroup?) -> Result<ResolvedRequest, ResolveError> {
    request.isMCP ? resolveMcpRequest(request, group: group) : .success(resolveRequest(request, group: group))
}
