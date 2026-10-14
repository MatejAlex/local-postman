import Foundation
import Testing
@testable import PostmanCore

@Suite struct StorageTests {
    let dir: URL
    let storage: Storage

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("lp-\(UUID().uuidString)", isDirectory: true)
        storage = Storage(directory: dir)
    }

    func json(_ file: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: dir.appendingPathComponent(file)))
    }

    @Test func seedsTheSampleCollectionOnFirstRun() {
        let snapshot = storage.load()
        #expect(snapshot.groups.map(\.name) == ["User Management"])
        #expect(snapshot.groups[0].requests.count == 2)
        #expect(snapshot.problems.isEmpty)
    }

    @Test func passwordsLiveInSecretsNotInTheCollection() throws {
        var group = RequestGroup(id: "group-a", name: "A", auth: CollectionAuth(mode: .basic, basic: BasicAuth(username: "u", password: "collection-pw")))
        var request = ApiRequest(id: "req-1")
        request.auth = RequestAuth(mode: .basic, basic: BasicAuth(username: "r", password: "request-pw"))
        group.requests = [request]

        storage.save(group)
        storage.flush()

        let file = try String(contentsOf: dir.appendingPathComponent("group-a.json"), encoding: .utf8)
        #expect(!file.contains("collection-pw"))
        #expect(!file.contains("request-pw"))
        #expect(try json("secrets.json") == .object([
            "group-a": .string("collection-pw"),
            "group-a/req-1": .string("request-pw"),
        ]))

        let loaded = storage.load().groups.first { $0.id == "group-a" }
        #expect(loaded == group)
    }

    @Test func clearingAPasswordRemovesTheSecret() throws {
        var group = RequestGroup(id: "group-a", auth: CollectionAuth(mode: .basic, basic: BasicAuth(username: "u", password: "pw")))
        storage.save(group)
        group.auth?.basic.password = ""
        storage.save(group)
        storage.flush()
        #expect(try json("secrets.json") == .object([:]))
    }

    @Test func inlinePasswordsFromOldFilesAreLiftedOnLoad() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // A pre-v1.5 file: password inline, and none of the later optional fields.
        let old = #"""
        {"id":"group-old","name":"Old","requests":[{"id":"r1","name":"R","method":"GET","url":"x","params":[],"headers":[],"body":"","bodyType":"none"}],
         "auth":{"mode":"basic","basic":{"username":"u","password":"inline","base64":true}}}
        """#
        try Data(old.utf8).write(to: dir.appendingPathComponent("group-old.json"))

        let loaded = storage.load()
        let group = try #require(loaded.groups.first)
        #expect(group.authValue.basic.password == "inline")
        #expect(group.requests[0].kindValue == .http)
        #expect(group.requests[0].auth == nil)
        #expect(group.order == nil)

        let file = try String(contentsOf: dir.appendingPathComponent("group-old.json"), encoding: .utf8)
        #expect(!file.contains("inline"))
        #expect(try json("secrets.json") == .object(["group-old": .string("inline")]))
    }

    @Test func deletingACollectionDropsItsSecrets() throws {
        let group = RequestGroup(id: "group-a", auth: CollectionAuth(mode: .basic, basic: BasicAuth(password: "pw")))
        let other = RequestGroup(id: "group-ab", auth: CollectionAuth(mode: .basic, basic: BasicAuth(password: "keep")))
        storage.save(group)
        storage.save(other)
        storage.delete(groupID: "group-a")
        storage.flush()
        #expect(try json("secrets.json") == .object(["group-ab": .string("keep")]))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("group-a.json").path))
    }

    @Test func refusesIdsThatWouldLeaveTheDirectory() {
        storage.save(RequestGroup(id: "group-../../evil"))
        storage.save(RequestGroup(id: "secrets"))
        storage.flush()
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("secrets.json").path))
    }

    @Test func historyRoundTripsAndSkipsBadEntries() throws {
        let item = HistoryItem(
            name: "List",
            method: .POST,
            url: "http://x/mcp",
            resolved: ResolvedRequest(url: "http://x/mcp", method: .POST, headers: ["a": "b"], mcp: McpCall(method: .toolsCall, params: ["name": .string("t"), "arguments": .object(["n": .int(1)])])),
            response: ApiResponse(status: 200, body: "{}", timeMs: 12.5, sizeBytes: 2)
        )
        storage.saveHistory([item])
        storage.flush()

        var raw = try json("history.json")
        if case .array(var items) = raw {
            items.append(.object(["broken": .bool(true)]))
            raw = .array(items)
        }
        try Data(raw.serialized().utf8).write(to: dir.appendingPathComponent("history.json"))

        let history = storage.load().history
        #expect(history == [item])
        #expect(history[0].badge == "MCP")
    }

    @Test func readsTheRepositorysSeedFile() throws {
        let seed = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("storage/group-1.json")
        try #require(FileManager.default.fileExists(atPath: seed.path))
        let group = try JSONDecoder().decode(RequestGroup.self, from: Data(contentsOf: seed))
        #expect(group.id == "group-1")
        #expect(group.variablesValue.first?.key == "base_url")
    }

    @Test func ordersCollectionsExplicitlyThenByName() {
        let groups = [RequestGroup(name: "b"), RequestGroup(name: "a"), RequestGroup(name: "z", order: 0)]
        #expect(sortGroups(groups).map(\.name) == ["z", "a", "b"])
    }
}
