import Foundation

// The MCP client for Streamable HTTP servers.
//
// One MCP call is several HTTP requests: the server will not answer
// `tools/list` until it has seen `initialize` and the `notifications/initialized`
// after it, and it names the session with a header it mints in the middle.
// Every send opens a fresh session and closes it again. That costs a round-trip
// and buys statelessness: a result never depends on what was clicked earlier.

/// MCP requires the client to accept both; servers pick per response.
let mcpAccept = "application/json, text/event-stream"

public struct McpClient: Sendable {
    public var transport: HTTPTransport

    public init(transport: HTTPTransport) {
        self.transport = transport
    }

    struct Hop {
        var status: Int
        var headers: [String: String]
        var raw: String
        /// The JSON-RPC payload text, unwrapped from SSE when it came that way.
        var payload: String?
        var json: JSONValue?
    }

    func post(_ url: URL, headers: [String: String], message: JSONValue) async throws -> Hop {
        var all = headers
        all["Content-Type"] = "application/json"
        all["Accept"] = mcpAccept
        let request = WireRequest(url: url, method: "POST", headers: all, body: Data(message.serialized().utf8))
        let response = try await performFollowingRedirects(request, transport: transport)
        let raw = response.text
        let payload = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : mcpPayload(raw, contentType: response.headers["content-type"] ?? "")
        return Hop(status: response.status, headers: response.headers, raw: raw, payload: payload, json: payload.flatMap(JSONValue.parse))
    }

    public func call(url urlText: String, headers: [String: String], call: McpCall) async -> ApiResponse {
        let started = Date()
        let url: URL
        switch httpURL(urlText) {
        case .success(let value): url = value
        case .failure(let error): return .failure(error.message)
        }

        do {
            return try await withTimeout(requestTimeout) {
                try await run(url: url, headers: headers, call: call, started: started)
            }
        } catch SendError.timedOut {
            return .failure("MCP call timed out after \(Int(requestTimeout))s", timeMs: milliseconds(since: started))
        } catch {
            return .failure(message(for: error), timeMs: milliseconds(since: started))
        }
    }

    private func run(url: URL, headers: [String: String], call: McpCall, started: Date) async throws -> ApiResponse {
        // 1. initialize
        let initialize: JSONValue = .object([
            "jsonrpc": .string("2.0"),
            "id": .int(1),
            "method": .string("initialize"),
            "params": .object([
                "protocolVersion": .string(mcpProtocolVersion),
                "capabilities": .object([:]),
                "clientInfo": .object(["name": .string("local-postman"), "version": .string(appVersion)]),
            ]),
        ])
        let initHop = try await post(url, headers: headers, message: initialize)

        if initHop.status >= 400 {
            // Say which thing went wrong and stop. The body and WWW-Authenticate
            // carry the server's own reason, always more specific than ours.
            let why = initHop.status == 401 || initHop.status == 403
                ? "the server rejected the credentials (\(initHop.status))"
                : "the server answered \(initHop.status)"
            return ApiResponse(
                status: initHop.status,
                statusText: reasonPhrase(initHop.status),
                headers: initHop.headers,
                body: initHop.raw,
                contentType: initHop.headers["content-type"] ?? "",
                timeMs: milliseconds(since: started),
                sizeBytes: initHop.raw.utf8.count,
                error: "MCP initialize failed: \(why)."
            )
        }

        // A refusal arrives as HTTP 200 carrying a JSON-RPC error: the reason
        // goes in the banner and the payload still fills the body.
        if let refusal = rpcError(initHop.json) {
            let shown = initHop.payload.map(prettyJSON) ?? initHop.raw
            return ApiResponse(
                status: initHop.status,
                statusText: reasonPhrase(initHop.status),
                headers: initHop.headers,
                body: shown,
                contentType: "application/json",
                timeMs: milliseconds(since: started),
                sizeBytes: shown.utf8.count,
                error: "initialize refused: \(refusal)"
            )
        }

        // A stateless server mints no session; then there is no header to echo.
        let sessionID = initHop.headers["mcp-session-id"]
        var session = headers
        session["MCP-Protocol-Version"] = mcpProtocolVersion
        if let sessionID { session["Mcp-Session-Id"] = sessionID }

        // 2. notifications/initialized: a notification, so no id and no reply.
        _ = try await post(url, headers: session, message: .object([
            "jsonrpc": .string("2.0"),
            "method": .string("notifications/initialized"),
        ]))

        // 3. The call that was actually asked for.
        let callHop = try await post(url, headers: session, message: .object([
            "jsonrpc": .string("2.0"),
            "id": .int(2),
            "method": .string(call.method.rawValue),
            "params": .object(call.params),
        ]))

        // 4. Close the session. Best-effort: a server without DELETE has not
        //    failed the call that already succeeded.
        if sessionID != nil {
            _ = try? await transport.perform(WireRequest(url: url, method: "DELETE", headers: session))
        }

        let shown = callHop.payload.map(prettyJSON) ?? callHop.raw
        return ApiResponse(
            status: callHop.status,
            statusText: reasonPhrase(callHop.status),
            headers: callHop.headers,
            body: shown,
            // Always JSON: the SSE framing was a transport detail and is unwrapped.
            contentType: "application/json",
            timeMs: milliseconds(since: started),
            sizeBytes: shown.utf8.count,
            // A tool that raises is a successful call carrying isError; that is
            // the body's business. Only a protocol-level error is surfaced here.
            error: rpcError(callHop.json)
        )
    }
}

/// The JSON-RPC payload of a response that is either plain JSON or an SSE
/// stream. For a stream, the last `data:` line that parses: a stream may carry
/// comments, pings and several events, and the reply is the last thing sent.
public func mcpPayload(_ text: String, contentType: String) -> String? {
    guard contentType.lowercased().contains("text/event-stream") else {
        return JSONValue.parse(text) != nil ? text : nil
    }
    var last: String?
    for line in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
        let line = line.hasSuffix("\r") ? line.dropLast() : line
        guard line.hasPrefix("data:") else { continue }
        let chunk = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if !chunk.isEmpty, JSONValue.parse(chunk) != nil { last = chunk }
    }
    return last
}

/// A JSON-RPC failure rendered for a human, or nil if it succeeded.
public func rpcError(_ json: JSONValue?) -> String? {
    guard let error = json?["error"], case .object(let fields) = error else { return nil }
    let code: String
    switch fields["code"] {
    case .int(let value)?: code = String(value)
    case .double(let value)?: code = String(value)
    default: code = "?"
    }
    let message = fields["message"]?.stringValue ?? error.serialized()
    return "MCP error \(code): \(message)"
}
