import Foundation

// File storage in ~/.local-postman, in exactly the layout the web app uses:
// one group-*.json per collection, history.json, and secrets.json holding the
// Basic-auth passwords so a collection file can be handed to someone as it sits.
//
// Writes go through one serial queue, so a burst of edits lands in the order it
// was made, off the main thread, and atomically (temp file + rename).

public final class Storage: @unchecked Sendable {
    public let directory: URL
    private let queue = DispatchQueue(label: "local-postman.storage")
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return encoder
    }()

    public struct Snapshot: Sendable {
        public var groups: [RequestGroup]
        public var history: [HistoryItem]
        /// Files that exist but could not be read, so the UI can say so instead of
        /// a collection silently going missing.
        public var problems: [String]
    }

    public static var defaultDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["LOCAL_POSTMAN_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local-postman", isDirectory: true)
    }

    public init(directory: URL = Storage.defaultDirectory) {
        self.directory = directory
    }

    private var secretsFile: URL { directory.appendingPathComponent("secrets.json") }
    private var historyFile: URL { directory.appendingPathComponent("history.json") }

    private func groupFile(_ id: String) -> URL? {
        // The id becomes a file name, so it must not be able to leave the directory.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard id.hasPrefix("group-"), id.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return directory.appendingPathComponent("\(id).json")
    }

    // MARK: - Loading

    /// Read everything. Seeds the sample collection on a first run, and lifts any
    /// password still written inline (from before v1.5) into secrets.json.
    public func load() -> Snapshot {
        queue.sync {
            ensureDirectory()
            var secrets = readSecrets()
            var groups: [RequestGroup] = []
            var problems: [String] = []
            var lifted = false

            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for file in files.sorted() where file.hasPrefix("group-") && file.hasSuffix(".json") {
                let url = directory.appendingPathComponent(file)
                do {
                    var group = try JSONDecoder().decode(RequestGroup.self, from: Data(contentsOf: url))
                    let key = String(file.dropLast(".json".count))
                    if liftInlinePasswords(&group, key: key, secrets: &secrets) {
                        lifted = true
                        try? write(group, to: url)
                    }
                    applyPasswords(&group, key: key, secrets: secrets)
                    groups.append(group)
                } catch {
                    problems.append("\(file): \(error.localizedDescription)")
                }
            }
            if lifted { writeSecrets(secrets) }

            var history: [HistoryItem] = []
            if let data = try? Data(contentsOf: historyFile) {
                if let items = try? JSONDecoder().decode([Lossy<HistoryItem>].self, from: data) {
                    history = items.compactMap(\.value)
                } else {
                    problems.append("history.json could not be read")
                }
            }

            return Snapshot(groups: sortGroups(groups), history: history, problems: problems)
        }
    }

    // MARK: - Writing

    /// Write a collection, lifting its passwords into secrets.json on the way.
    public func save(_ group: RequestGroup) {
        queue.async { [self] in
            guard let url = groupFile(group.id) else { return }
            ensureDirectory()
            var secrets = readSecrets()
            var stored = group
            if extractPasswords(&stored, key: group.id, secrets: &secrets) {
                writeSecrets(secrets)
            }
            try? write(stored, to: url)
        }
    }

    public func delete(groupID: String) {
        queue.async { [self] in
            guard let url = groupFile(groupID) else { return }
            var secrets = readSecrets()
            let owned = secrets.keys.filter { $0 == groupID || $0.hasPrefix("\(groupID)/") }
            if !owned.isEmpty {
                owned.forEach { secrets.removeValue(forKey: $0) }
                writeSecrets(secrets)
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func saveHistory(_ history: [HistoryItem]) {
        queue.async { [self] in
            ensureDirectory()
            try? write(Array(history.prefix(historyLimit)), to: historyFile)
        }
    }

    /// Block until every queued write has landed. For tests and app quit.
    public func flush() {
        queue.sync {}
    }

    // MARK: - Internals

    private func ensureDirectory() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        if existing.contains(where: { $0.hasSuffix(".json") }) { return }
        // First run: one working collection, so a request can be sent straight away.
        try? Data(seedCollectionJSON.utf8).write(to: directory.appendingPathComponent("group-1.json"), options: .atomic)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    // MARK: Passwords

    /// Owner key -> password. The key is a collection's id, or `collectionId/requestId`.
    typealias Secrets = [String: String]

    private func readSecrets() -> Secrets {
        // Missing or unparseable reads as empty: a collection then arrives with a
        // blank password box rather than failing the whole load.
        guard let data = try? Data(contentsOf: secretsFile) else { return [:] }
        return (try? JSONDecoder().decode(Secrets.self, from: data)) ?? [:]
    }

    private func writeSecrets(_ secrets: Secrets) {
        try? write(secrets, to: secretsFile)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretsFile.path)
    }
}

// The password slots of a collection: its own auth, then one per request. Only
// auth blocks that exist count, exactly as the web app's storage route did.

func forEachPasswordSlot(_ group: inout RequestGroup, key: String, _ body: (String, inout BasicAuth) -> Void) {
    if var auth = group.auth {
        body(key, &auth.basic)
        group.auth = auth
    }
    for index in group.requests.indices {
        if var auth = group.requests[index].auth {
            body("\(key)/\(group.requests[index].id)", &auth.basic)
            group.requests[index].auth = auth
        }
    }
}

/// Move the passwords into the secrets map and blank them on the collection.
func extractPasswords(_ group: inout RequestGroup, key: String, secrets: inout Storage.Secrets) -> Bool {
    var changed = false
    forEachPasswordSlot(&group, key: key) { slot, basic in
        if basic.password.isEmpty {
            // Clearing the box removes the secret rather than storing a blank one.
            if secrets.removeValue(forKey: slot) != nil { changed = true }
            return
        }
        if secrets[slot] != basic.password {
            secrets[slot] = basic.password
            changed = true
        }
        basic.password = ""
    }
    return changed
}

/// A password still inline from before the split is lifted on first read. An
/// existing secret always wins, which makes the lift idempotent.
func liftInlinePasswords(_ group: inout RequestGroup, key: String, secrets: inout Storage.Secrets) -> Bool {
    var lifted = false
    forEachPasswordSlot(&group, key: key) { slot, basic in
        if !basic.password.isEmpty, secrets[slot] == nil {
            secrets[slot] = basic.password
            lifted = true
        }
    }
    if lifted {
        forEachPasswordSlot(&group, key: key) { _, basic in basic.password = "" }
    }
    return lifted
}

func applyPasswords(_ group: inout RequestGroup, key: String, secrets: Storage.Secrets) {
    forEachPasswordSlot(&group, key: key) { slot, basic in
        if let stored = secrets[slot] { basic.password = stored }
    }
}

/// Decodes to nil instead of failing the whole array, so one bad history entry
/// does not cost the other forty-nine.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// The repo's storage/group-1.json, so a fresh install can send a request immediately.
let seedCollectionJSON = #"""
{
  "id": "group-1",
  "name": "User Management",
  "requests": [
    {
      "id": "req-1",
      "name": "List users",
      "method": "GET",
      "url": "{{base_url}}/users",
      "params": [],
      "headers": [{ "key": "Accept", "value": "application/json", "enabled": true }],
      "body": "",
      "bodyType": "none"
    },
    {
      "id": "req-2",
      "name": "Create post",
      "method": "POST",
      "url": "{{base_url}}/posts",
      "params": [],
      "headers": [{ "key": "Content-Type", "value": "application/json", "enabled": true }],
      "body": "{\n  \"title\": \"Hello\",\n  \"body\": \"From local-postman\",\n  \"userId\": 1\n}",
      "bodyType": "json"
    }
  ],
  "variables": [
    { "key": "base_url", "value": "https://jsonplaceholder.typicode.com", "enabled": true }
  ],
  "color": "#3b82f6",
  "order": 0
}
"""#
