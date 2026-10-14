import Foundation

// Turning a sent request into text a colleague can use: a cURL command, or the
// whole exchange. Both are exactly what was sent, credentials included.

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
public func curlCommand(_ request: ResolvedRequest) -> String {
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
        lines.append("-H \(shellQuoted("\(key): \(headers[key]!)"))")
    }
    if let body, !body.isEmpty {
        lines.append("--data-raw \(shellQuoted(body))")
    }
    return lines.joined(separator: " \\\n  ")
}

/// The request and its response as plain text, for pasting into a chat or a ticket.
public func exchangeText(_ item: HistoryItem) -> String {
    func headerLines(_ headers: [String: String]) -> [String] {
        headers.keys.sorted(by: { $0.lowercased() < $1.lowercased() }).map { key in
            "\(key): \(headers[key]!)"
        }
    }

    let request = item.resolved
    let url = request.url
    var out: [String] = []
    if let mcp = request.mcp {
        out.append("MCP \(mcp.method.rawValue) \(url)")
    } else {
        out.append("\(request.method.rawValue) \(url)")
    }
    out += headerLines(request.headers)
    let sentBody = request.mcp.map(mcpBody) ?? request.body ?? ""
    if !sentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        out.append("")
        out.append(prettyJSON(sentBody))
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
            out.append(prettyBody(response.body, contentType: response.contentType))
        }
    }
    return out.joined(separator: "\n")
}
