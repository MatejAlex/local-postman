import Foundation
import Testing
@testable import PostmanCore

@Suite struct SubstitutionTests {
    @Test func replacesDefinedVariables() {
        #expect(substitute("{{base}}/users/{{ id }}", ["base": "https://x.dev", "id": "7"]) == "https://x.dev/users/7")
    }

    @Test func leavesUndefinedVariablesVerbatim() {
        #expect(substitute("{{base}}/{{missing}}", ["base": "b"]) == "b/{{missing}}")
    }

    @Test func handlesUnicodeAroundVariables() {
        #expect(substitute("čau {{name}} 👋", ["name": "Matěj"]) == "čau Matěj 👋")
    }

    @Test func reportsUndefinedVariables() {
        #expect(undefinedVariables(in: "{{a}}/{{b}}/{{a}}", ["b": "1"]) == ["a"])
    }

    @Test func disabledAndUnnamedRowsAreNotVariables() {
        let rows = [KeyValue(key: "a", value: "1"), KeyValue(key: "b", value: "2", enabled: false), KeyValue(key: " ", value: "3")]
        #expect(variableMap(rows) == ["a": "1"])
    }
}

@Suite struct ResolveTests {
    func group(auth: CollectionAuth? = nil, vars: [KeyValue] = []) -> RequestGroup {
        RequestGroup(id: "group-1", name: "G", auth: auth, variables: vars)
    }

    @Test func appendsEncodedQueryParams() {
        let url = buildURL("https://x.dev/a?z=1", params: [
            KeyValue(key: "q", value: "a b&c"),
            KeyValue(key: "off", value: "x", enabled: false),
            KeyValue(key: "v", value: "{{v}}"),
        ], vars: ["v": "é/"])
        #expect(url == "https://x.dev/a?z=1&q=a%20b%26c&v=%C3%A9%2F")
    }

    @Test func basicAuthHeaderEncodesUTF8() {
        let header = basicAuthHeader(BasicAuth(username: "ü", password: "{{pw}}"), vars: ["pw": "s"])
        #expect(header == "Basic " + Data("ü:s".utf8).base64EncodedString())
        #expect(basicAuthHeader(BasicAuth(username: "u", password: "p", base64: false), vars: [:]) == "Basic u:p")
        #expect(basicAuthHeader(BasicAuth(), vars: [:]) == nil)
    }

    @Test func requestInheritsCollectionAuth() {
        let g = group(auth: CollectionAuth(mode: .basic, basic: BasicAuth(username: "u", password: "p")))
        let resolved = resolveRequest(ApiRequest(url: "https://x.dev"), group: g)
        #expect(resolved.headers["Authorization"] == "Basic dTpw")
    }

    @Test func requestNoneOverridesCollectionAuth() {
        let g = group(auth: CollectionAuth(mode: .basic, basic: BasicAuth(username: "u", password: "p")))
        let request = ApiRequest(url: "https://x.dev", auth: RequestAuth(mode: .none))
        #expect(resolveRequest(request, group: g).headers["Authorization"] == nil)
    }

    @Test func manualAuthorizationHeaderWins() {
        let g = group(auth: CollectionAuth(mode: .basic, basic: BasicAuth(username: "u", password: "p")))
        let request = ApiRequest(url: "https://x.dev", headers: [KeyValue(key: "authorization", value: "Bearer {{t}}")])
        let resolved = resolveRequest(request, group: RequestGroup(id: g.id, auth: g.auth, variables: [KeyValue(key: "t", value: "abc")]))
        #expect(resolved.headers == ["authorization": "Bearer abc"])
    }

    @Test func jsonBodyGetsContentTypeAndGetDropsBody() {
        let post = ApiRequest(method: .POST, url: "https://x.dev", body: #"{"a":"{{v}}"}"#, bodyType: .json)
        let resolved = resolveRequest(post, group: group(vars: [KeyValue(key: "v", value: "1")]))
        #expect(resolved.body == #"{"a":"1"}"#)
        #expect(resolved.headers["Content-Type"] == "application/json")

        var get = post
        get.method = .GET
        #expect(resolveRequest(get, group: nil).body == nil)
    }

    @Test func rawBodyIsPlainTextUnlessAHeaderSaysOtherwise() {
        var raw = ApiRequest(method: .POST, url: "https://x.dev", body: #"{"a":1}"#, bodyType: .raw)
        #expect(resolveRequest(raw, group: nil).headers["Content-Type"] == "text/plain;charset=UTF-8")

        raw.headers = [KeyValue(key: "content-type", value: "application/xml")]
        #expect(resolveRequest(raw, group: nil).headers == ["content-type": "application/xml"])
    }
}

@Suite struct McpParamsTests {
    @Test func listMethodsTakeNoParams() throws {
        #expect(try mcpParams(for: McpConfig(method: .toolsList)).get() == [:])
    }

    @Test func callNeedsATarget() {
        #expect(throws: ResolveError("Tool name is required for tools/call.")) {
            try mcpParams(for: McpConfig(method: .toolsCall)).get()
        }
    }

    @Test func argumentsMustBeAnObject() {
        #expect(throws: ResolveError(#"Arguments must be a JSON object, e.g. {"query": "payrun"}."#)) {
            try mcpParams(for: McpConfig(method: .toolsCall, target: "t", args: "[1]")).get()
        }
        #expect(throws: ResolveError("Arguments are not valid JSON.")) {
            try mcpParams(for: McpConfig(method: .toolsCall, target: "t", args: "{nope")).get()
        }
    }

    @Test func callCarriesNameAndArguments() throws {
        let params = try mcpParams(for: McpConfig(method: .toolsCall, target: " search ", args: #"{"q": "x", "n": 2}"#)).get()
        #expect(params == ["name": .string("search"), "arguments": .object(["q": .string("x"), "n": .int(2)])])
    }

    @Test func resolvedMcpRequestSubstitutesAndIsAPost() throws {
        var request = ApiRequest.newMCP()
        request.url = "{{host}}/mcp"
        request.mcp = McpConfig(method: .resourcesRead, target: "file:///{{doc}}")
        let g = RequestGroup(variables: [KeyValue(key: "host", value: "http://localhost:8000"), KeyValue(key: "doc", value: "a.md")])
        let resolved = try resolveMcpRequest(request, group: g).get()
        #expect(resolved.url == "http://localhost:8000/mcp")
        #expect(resolved.method == .POST)
        #expect(resolved.body == nil)
        #expect(resolved.mcp == McpCall(method: .resourcesRead, params: ["uri": .string("file:///a.md")]))
    }
}
