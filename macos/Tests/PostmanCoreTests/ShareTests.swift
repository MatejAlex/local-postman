import Foundation
import Testing
@testable import PostmanCore

@Suite struct ShareTests {
    let login = ResolvedRequest(
        url: "https://x.dev/login?a=1",
        method: .POST,
        headers: ["Authorization": "Bearer abc.def", "Content-Type": "application/json"],
        body: #"{"user_name":"me","password":"it's secret"}"#
    )

    @Test func curlHidesCredentialsByDefault() {
        let curl = curlCommand(login)
        #expect(curl.hasPrefix("curl -X POST 'https://x.dev/login?a=1'"))
        #expect(curl.contains("-H 'Authorization: Bearer <redacted>'"))
        #expect(curl.contains("-H 'Content-Type: application/json'"))
        #expect(curl.contains(#""password":"<redacted>""#))
        #expect(curl.contains(#""user_name":"me""#))
        #expect(!curl.contains("abc.def"))
    }

    @Test func curlWithCredentialsQuotesForTheShell() {
        let curl = curlCommand(login, hideCredentials: false)
        #expect(curl.contains("Bearer abc.def"))
        // The apostrophe in the password closes, escapes and reopens the quote.
        #expect(curl.contains(#"it'\''s secret"#))
    }

    @Test func mcpBecomesItsJsonRpcPost() {
        let call = ResolvedRequest(
            url: "http://localhost:7801/mcp", method: .POST, headers: [:],
            mcp: McpCall(method: .toolsList, params: [:])
        )
        let curl = curlCommand(call)
        #expect(curl.contains("-X POST"))
        #expect(curl.contains("Accept: application/json, text/event-stream"))
        #expect(curl.contains(#""method":"tools/list""#))
        #expect(curl.contains(#""jsonrpc":"2.0""#))
    }

    @Test func redactsNestedSecretsAndLeavesNonJsonAlone() {
        #expect(redactedBody(#"{"a":{"api_token":"t"},"list":[{"secret":1}]}"#).contains(#""api_token":"<redacted>""#))
        #expect(!redactedBody(#"{"list":[{"secret":1}]}"#).contains("1"))
        #expect(redactedBody("password=hunter2") == "password=hunter2")
        #expect(redactedBody(#"{"ok":true}"#) == #"{"ok":true}"#)
        #expect(redactedHeader("Cookie", "s=1") == "<redacted>")
        #expect(redactedHeader("Accept", "*/*") == "*/*")
    }

    @Test func exchangeHasRequestThenResponse() {
        let item = HistoryItem(
            name: "Login", method: .POST, url: login.url, resolved: login,
            response: ApiResponse(status: 200, statusText: "OK", headers: ["Set-Cookie": "s=1"], body: #"{"token":"xyz","id":1}"#, contentType: "application/json", timeMs: 12, sizeBytes: 20)
        )
        let text = exchangeText(item)
        #expect(text.hasPrefix("POST https://x.dev/login?a=1\n"))
        #expect(text.contains("200 OK"))
        #expect(text.contains("Set-Cookie: <redacted>"))
        #expect(!text.contains("xyz"))
        #expect(!text.contains("abc.def"))
        #expect(exchangeText(item, hideCredentials: false).contains("xyz"))
    }
}
