import Foundation
import Testing
@testable import PostmanCore

/// A transport that answers from a script and records what it was asked.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [WireRequest] = []
    let handler: @Sendable (WireRequest, Int) throws -> WireResponse

    init(_ handler: @escaping @Sendable (WireRequest, Int) throws -> WireResponse) {
        self.handler = handler
    }

    var requests: [WireRequest] { lock.withLock { _requests } }

    func perform(_ request: WireRequest) async throws -> WireResponse {
        let index = lock.withLock { () -> Int in
            _requests.append(request)
            return _requests.count - 1
        }
        return try handler(request, index)
    }
}

func reply(_ status: Int, _ body: String = "", headers: [String: String] = [:]) -> WireResponse {
    WireResponse(status: status, headers: headers, body: Data(body.utf8))
}

func bodyJSON(_ request: WireRequest) -> JSONValue? {
    request.body.flatMap { JSONValue.parse(String(decoding: $0, as: UTF8.self)) }
}

@Suite struct RedirectTests {
    @Test func crossOriginHopDropsCredentials() async throws {
        let fake = FakeTransport { request, index in
            index == 0 ? reply(302, headers: ["location": "https://other.dev/landing"]) : reply(200, "ok")
        }
        let start = WireRequest(url: URL(string: "https://a.dev/x")!, method: "GET", headers: ["Authorization": "Basic x", "Cookie": "c", "Accept": "*/*"])
        let response = try await performFollowingRedirects(start, transport: fake)
        #expect(response.status == 200)
        #expect(fake.requests[1].url.absoluteString == "https://other.dev/landing")
        #expect(fake.requests[1].headers == ["Accept": "*/*"])
    }

    @Test func sameOriginHopKeepsCredentialsAnd303BecomesGet() async throws {
        let fake = FakeTransport { _, index in
            index == 0 ? reply(303, headers: ["location": "/done"]) : reply(200)
        }
        let start = WireRequest(url: URL(string: "https://a.dev/x")!, method: "POST", headers: ["Authorization": "t"], body: Data("b".utf8))
        _ = try await performFollowingRedirects(start, transport: fake)
        #expect(fake.requests[1].method == "GET")
        #expect(fake.requests[1].body == nil)
        #expect(fake.requests[1].headers["Authorization"] == "t")
        #expect(fake.requests[1].url.absoluteString == "https://a.dev/done")
    }

    @Test func stopsAfterFiveRedirects() async {
        let fake = FakeTransport { _, _ in reply(307, headers: ["location": "/again"]) }
        let response = await Sender(transport: fake).send(ResolvedRequest(url: "https://a.dev/", method: .GET, headers: [:]))
        #expect(response.error == "Too many redirects")
        #expect(response.status == 0)
        #expect(fake.requests.count == 6)
    }

    @Test func rejectsNonHTTPURLsBeforeSending() async {
        let fake = FakeTransport { _, _ in reply(200) }
        let response = await Sender(transport: fake).send(ResolvedRequest(url: "ftp://a.dev", method: .GET, headers: [:]))
        #expect(response.error == "Only http(s) URLs are supported.")
        let relative = await Sender(transport: fake).send(ResolvedRequest(url: "{{base}}/x", method: .GET, headers: [:]))
        #expect(relative.error == "URL must be an absolute http(s) address.")
        #expect(fake.requests.isEmpty)
    }

    @Test func reportsStatusBodyAndSize() async {
        let fake = FakeTransport { _, _ in reply(404, "nope ✓", headers: ["content-type": "text/plain"]) }
        let response = await Sender(transport: fake).send(ResolvedRequest(url: "https://a.dev", method: .GET, headers: [:]))
        #expect(response.status == 404)
        #expect(response.statusText == "Not Found")
        #expect(response.body == "nope ✓")
        #expect(response.sizeBytes == 8)
        #expect(response.contentType == "text/plain")
        #expect(response.error == nil)
    }
}

@Suite struct McpClientTests {
    let call = McpCall(method: .toolsList, params: [:])

    @Test func runsTheWholeHandshakeAndClosesTheSession() async throws {
        let fake = FakeTransport { request, index in
            switch index {
            case 0: return reply(200, #"{"jsonrpc":"2.0","id":1,"result":{}}"#, headers: ["content-type": "application/json", "mcp-session-id": "s-1"])
            case 1: return reply(202)
            case 2: return reply(200, "event: message\r\ndata: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"tools\":[]}}\r\n\r\n", headers: ["content-type": "text/event-stream"])
            default: return reply(200)
            }
        }
        let response = await McpClient(transport: fake).call(url: "http://localhost:8000/mcp", headers: ["Authorization": "Basic x"], call: call)

        #expect(response.error == nil)
        #expect(response.contentType == "application/json")
        #expect(response.body == "{\n  \"jsonrpc\": \"2.0\",\n  \"id\": 2,\n  \"result\": {\n    \"tools\": []\n  }\n}")

        let sent = fake.requests
        #expect(sent.map(\.method) == ["POST", "POST", "POST", "DELETE"])
        #expect(bodyJSON(sent[0])?["method"] == .string("initialize"))
        #expect(bodyJSON(sent[1])?["method"] == .string("notifications/initialized"))
        #expect(bodyJSON(sent[1])?["id"] == nil)
        #expect(bodyJSON(sent[2])?["method"] == .string("tools/list"))
        #expect(sent[0].headers["Mcp-Session-Id"] == nil)
        for later in sent.dropFirst() {
            #expect(later.headers["Mcp-Session-Id"] == "s-1")
            #expect(later.headers["MCP-Protocol-Version"] == mcpProtocolVersion)
            #expect(later.headers["Authorization"] == "Basic x")
        }
        #expect(sent[0].headers["Accept"] == "application/json, text/event-stream")
    }

    @Test func statelessServerGetsNoDelete() async {
        let fake = FakeTransport { _, _ in reply(200, #"{"jsonrpc":"2.0","id":1,"result":{}}"#, headers: ["content-type": "application/json"]) }
        _ = await McpClient(transport: fake).call(url: "http://localhost/mcp", headers: [:], call: call)
        #expect(fake.requests.count == 3)
    }

    @Test func rejectedCredentialsKeepTheServersBody() async {
        let fake = FakeTransport { _, _ in reply(401, #"{"detail":"bad token for user x"}"#, headers: ["content-type": "application/json"]) }
        let response = await McpClient(transport: fake).call(url: "http://localhost/mcp", headers: [:], call: call)
        #expect(response.status == 401)
        #expect(response.error == "MCP initialize failed: the server rejected the credentials (401).")
        #expect(response.body.contains("bad token for user x"))
        #expect(fake.requests.count == 1)
    }

    @Test func jsonRpcErrorBecomesTheBannerAndKeepsThePayload() async {
        let fake = FakeTransport { _, index in
            index == 0
                ? reply(200, #"{"jsonrpc":"2.0","id":1,"result":{}}"#, headers: ["content-type": "application/json"])
                : reply(200, #"{"jsonrpc":"2.0","id":2,"error":{"code":-32601,"message":"Method not found"}}"#, headers: ["content-type": "application/json"])
        }
        let response = await McpClient(transport: fake).call(url: "http://localhost/mcp", headers: [:], call: call)
        #expect(response.error == "MCP error -32601: Method not found")
        #expect(response.body.contains("Method not found"))
    }

    @Test func toolIsErrorIsASuccessfulCall() async {
        let fake = FakeTransport { _, index in
            index == 0
                ? reply(200, #"{"jsonrpc":"2.0","id":1,"result":{}}"#, headers: ["content-type": "application/json"])
                : reply(200, #"{"jsonrpc":"2.0","id":2,"result":{"isError":true,"content":[]}}"#, headers: ["content-type": "application/json"])
        }
        let response = await McpClient(transport: fake).call(url: "http://localhost/mcp", headers: [:], call: call)
        #expect(response.error == nil)
    }

    @Test func ssePayloadTakesTheLastParsableEvent() {
        let stream = ": ping\ndata: {\"id\":1}\n\ndata: not json\n\ndata: {\"id\":2}\n"
        #expect(mcpPayload(stream, contentType: "text/event-stream; charset=utf-8") == #"{"id":2}"#)
        #expect(mcpPayload("garbage", contentType: "application/json") == nil)
    }
}

/// Hits a real server through URLSession. Opt-in: set LP_SMOKE_URL to a URL
/// that answers 200 (e.g. `python3 -m http.server`).
@Suite struct LiveSmokeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LP_SMOKE_URL"] != nil))
    func sendsThroughURLSession() async {
        let url = ProcessInfo.processInfo.environment["LP_SMOKE_URL"]!
        let response = await Sender().send(ResolvedRequest(url: url, method: .GET, headers: ["Accept": "*/*"]))
        #expect(response.error == nil)
        #expect(response.status == 200)
        #expect(response.sizeBytes > 0)
    }
}

@Suite struct ServerTrustTests {
    @Test func acceptsOnlyTheValidityPeriodFailure() {
        #expect(failsOnlyOnValidityPeriod([validityPeriodTooLongStatus]))
        #expect(failsOnlyOnValidityPeriod([validityPeriodTooLongStatus, validityPeriodTooLongStatus]))
        // An untrusted anchor or a hostname mismatch alongside it: still rejected.
        #expect(!failsOnlyOnValidityPeriod([validityPeriodTooLongStatus, -2147408896]))
        #expect(!failsOnlyOnValidityPeriod([-2147409622]))
        #expect(!failsOnlyOnValidityPeriod([]))
    }
}
