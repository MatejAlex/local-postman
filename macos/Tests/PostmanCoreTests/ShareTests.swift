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

    @Test func redactsNestedSecretsAndLeavesFreeTextAlone() {
        #expect(redactedBody(#"{"a":{"api_token":"t"},"list":[{"secret":1}]}"#).contains(#""api_token":"<redacted>""#))
        #expect(!redactedBody(#"{"list":[{"secret":1}]}"#).contains("1"))
        #expect(redactedBody("plain text, password hunter2") == "plain text, password hunter2")
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

@Suite struct RedactionGapTests {
    @Test func urlSecretsAreBlanked() {
        #expect(redactedURL("https://me:pw@x.dev/a?token=abc&page=2&api_key=k") == "https://me:REDACTED@x.dev/a?token=REDACTED&page=2&api_key=REDACTED")
        #expect(redactedURL("https://x.dev/a?page=2") == "https://x.dev/a?page=2")
        #expect(redactedURL("{{base}}/login") == "{{base}}/login")
    }

    @Test func formBodySecretsAreBlanked() {
        #expect(redactedBody("user=me&password=hunter2") == "user=me&password=<redacted>")
        #expect(redactedBody("grant_type=client_credentials&client_secret=s") == "grant_type=client_credentials&client_secret=<redacted>")
        #expect(redactedBody("just some text") == "just some text")
    }

    @Test func curlAndExchangeUseTheRedactedURL() {
        let request = ResolvedRequest(url: "https://x.dev/a?access_token=abc", method: .GET, headers: [:])
        #expect(!curlCommand(request).contains("abc"))
        let item = HistoryItem(name: nil, method: .GET, url: request.url, resolved: request, response: ApiResponse(status: 204))
        #expect(!exchangeText(item).contains("abc"))
        #expect(curlCommand(request, hideCredentials: false).contains("abc"))
    }
}

@Suite struct FailClosedRedactionTests {
    @Test func unparseableURLsAreStillRedacted() {
        // URLComponents rejects both of these; the redaction must not give up.
        #expect(redactedURL("{{base}}/login?token=abc") == "{{base}}/login?token=REDACTED")
        #expect(redactedURL("https://me:pw@x.dev/a b?Password=x#frag") == "https://me:REDACTED@x.dev/a b?Password=REDACTED#frag")
    }

    @Test func brokenJsonAndXmlAreStillRedacted() {
        let broken = #"{"user_name": "me" "Password": "hu\"nter2"}"#
        #expect(redactedBody(broken) == #"{"user_name": "me" "Password": "<redacted>"}"#)
        #expect(redactedBody("<login><user>me</user><password>pw</password></login>") == "<login><user>me</user><password><redacted></password></login>")
        #expect(redactedBody("user=me&password=pw\n") == "user=me&password=<redacted>")
    }
}
