import Foundation

// Turning a sent request into text a colleague can use: a cURL command, or the
// whole exchange. Credentials are hidden by default, because the usual
// destination is a chat window, and a pasted token outlives the message.

/// Header names whose value is a credential.
private let credentialHeaders: Set<String> = ["authorization", "proxy-authorization", "cookie", "set-cookie", "x-api-key", "api-key"]

/// Body keys and header names that hold a secret by their name alone.
private func looksSecret(_ name: String) -> Bool {
    let lower = name.lowercased()
    return ["password", "passwd", "secret", "token", "apikey", "api_key"].contains { lower.contains($0) }
}

public let redactedValue = "<redacted>"

/// A header value with its credential replaced. An Authorization header keeps
/// its scheme, so the reader still sees it was Basic or Bearer.
public func redactedHeader(_ name: String, _ value: String) -> String {
    let lower = name.lowercased()
    guard credentialHeaders.contains(lower) || looksSecret(lower) else { return value }
    if lower == "authorization" || lower == "proxy-authorization",
       let space = value.firstIndex(of: " ") {
        return String(value[..<space]) + " " + redactedValue
    }
    return redactedValue
}

/// A JSON body with every secret-looking key blanked, at any depth. Anything
/// that is not JSON comes back unchanged: there is no telling where its secrets are.
public func redactedBody(_ body: String) -> String {
    guard let value = JSONValue.parse(body) else { return body }
    func scrub(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let fields):
            var out: [String: JSONValue] = [:]
            for (key, field) in fields {
                out[key] = looksSecret(key) ? .string(redactedValue) : scrub(field)
            }
            return .object(out)
        case .array(let items):
            return .array(items.map(scrub))
        default:
            return value
        }
    }
    let scrubbed = scrub(value)
    return scrubbed == value ? body : scrubbed.serialized()
}

/// What actually went on the wire for an MCP call: one JSON-RPC POST.
private func mcpBody(_ call: McpCall) -> String {
    JSONValue.object([
        "jsonrpc": .string("2.0"),
        "id": .int(1),
        "method": .string(call.method.rawValue),
        "params": .object(call.params),
    ]).serialized()
}

private func shellQuoted(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// The request as a cURL command. An MCP call becomes its single JSON-RPC
/// POST, which a stateless server answers as it is; one that insists on a
/// session needs the initialize handshake first, which cURL cannot carry.
public func curlCommand(_ request: ResolvedRequest, hideCredentials: Bool = true) -> String {
    var headers = request.headers
    var body = request.body
    let method: String
    if let mcp = request.mcp {
        method = "POST"
        body = mcpBody(mcp)
        if !headers.keys.contains(where: { $0.lowercased() == "content-type" }) {
            headers["Content-Type"] = "application/json"
        }
        if !headers.keys.contains(where: { $0.lowercased() == "accept" }) {
            headers["Accept"] = "application/json, text/event-stream"
        }
    } else {
        method = request.method.rawValue
    }

    var lines = ["curl -X \(method) \(shellQuoted(request.url))"]
    for key in headers.keys.sorted(by: { $0.lowercased() < $1.lowercased() }) {
        let value = hideCredentials ? redactedHeader(key, headers[key]!) : headers[key]!
        lines.append("-H \(shellQuoted("\(key): \(value)"))")
    }
    if let body, !body.isEmpty {
        lines.append("--data-raw \(shellQuoted(hideCredentials ? redactedBody(body) : body))")
    }
    return lines.joined(separator: " \\\n  ")
}

/// The request and its response as plain text, for pasting into a chat or a ticket.
public func exchangeText(_ item: HistoryItem, hideCredentials: Bool = true) -> String {
    func headerLines(_ headers: [String: String]) -> [String] {
        headers.keys.sorted(by: { $0.lowercased() < $1.lowercased() }).map { key in
            "\(key): \(hideCredentials ? redactedHeader(key, headers[key]!) : headers[key]!)"
        }
    }

    let request = item.resolved
    var out: [String] = []
    if let mcp = request.mcp {
        out.append("MCP \(mcp.method.rawValue) \(request.url)")
    } else {
        out.append("\(request.method.rawValue) \(request.url)")
    }
    out += headerLines(request.headers)
    let sentBody = request.mcp.map(mcpBody) ?? request.body ?? ""
    if !sentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        out.append("")
        out.append(prettyJSON(hideCredentials ? redactedBody(sentBody) : sentBody))
    }

    out.append("")
    out.append("---")
    out.append("")

    let response = item.response
    if response.status == 0 {
        out.append("No response: \(response.error ?? "request failed")")
    } else {
        let status = "\(response.status) \(response.statusText)".trimmingCharacters(in: .whitespaces)
        out.append("\(status)  (\(formatTime(response.timeMs)), \(formatSize(response.sizeBytes)))")
        if let error = response.error { out.append("Error: \(error)") }
        out += headerLines(response.headers)
        if !response.body.isEmpty {
            out.append("")
            out.append(prettyBody(hideCredentials ? redactedBody(response.body) : response.body, contentType: response.contentType))
        }
    }
    return out.joined(separator: "\n")
}
