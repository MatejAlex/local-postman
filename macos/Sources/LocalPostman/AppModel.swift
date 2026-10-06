import Foundation
import Observation
import PostmanCore
import SwiftUI

/// A response, with an identity so the viewer can reset its tab per response
/// without comparing whole bodies.
struct ResponseEntry: Identifiable, Equatable {
    let id = UUID()
    let response: ApiResponse
}

/// Which collection a sheet or dialog is about.
struct GroupRef: Identifiable, Equatable {
    let id: String
}

/// All app state, and every mutation of it. Views read from here and call in;
/// persistence happens here, so no view has to remember to save.
@MainActor
@Observable
final class AppModel {
    var groups: [RequestGroup] = []
    var history: [HistoryItem] = []
    var loadProblems: [String] = []

    var selection: String?
    /// The last response of each request, kept for the session, so switching
    /// between requests does not throw away what came back.
    var responses: [String: ResponseEntry] = [:]
    var sending: Set<String> = []
    var replaying: Set<String> = []

    var showHistory = true
    var responseMaximized = false
    var sideBySide = UserDefaults.standard.bool(forKey: "sideBySide") {
        didSet { UserDefaults.standard.set(sideBySide, forKey: "sideBySide") }
    }
    var inspectedHistory: HistoryItem?
    var editingCollection: GroupRef?
    var pendingDelete: GroupRef?
    var focusURLTick = 0

    @ObservationIgnored let storage: Storage
    @ObservationIgnored private let sender = Sender()
    @ObservationIgnored private var sendTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var saveTasks: [String: Task<Void, Never>] = [:]

    init(storage: Storage = Storage()) {
        self.storage = storage
        reload()
    }

    // MARK: - Lookups

    var selectedRequest: ApiRequest? {
        guard let selection else { return nil }
        return groups.lazy.flatMap(\.requests).first { $0.id == selection }
    }

    var selectedGroup: RequestGroup? {
        guard let selection else { return nil }
        return group(containing: selection)
    }

    func group(containing requestID: String) -> RequestGroup? {
        groups.first { $0.requests.contains { $0.id == requestID } }
    }

    func group(_ id: String) -> RequestGroup? {
        groups.first { $0.id == id }
    }

    private func groupIndex(_ id: String) -> Int? {
        groups.firstIndex { $0.id == id }
    }

    /// A binding straight into the stored request, so editing it edits the
    /// collection and schedules the save.
    func binding(forRequest id: String) -> Binding<ApiRequest>? {
        guard let current = groups.lazy.flatMap(\.requests).first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in
                self?.groups.lazy.flatMap(\.requests).first { $0.id == id } ?? current
            },
            set: { [weak self] in self?.update($0) }
        )
    }

    // MARK: - Loading and saving

    func reload() {
        flushPendingSaves()
        let snapshot = storage.load()
        groups = snapshot.groups
        history = snapshot.history
        loadProblems = snapshot.problems
        if selection != nil, selectedRequest == nil { selection = nil }
    }

    /// Persist a collection after a short pause, so a burst of typing is one write.
    private func queueSave(_ groupID: String) {
        saveTasks[groupID]?.cancel()
        saveTasks[groupID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.saveTasks[groupID] = nil
            if let group = self.group(groupID) { self.storage.save(group) }
        }
    }

    private func saveNow(_ groupID: String) {
        saveTasks[groupID]?.cancel()
        saveTasks[groupID] = nil
        if let group = group(groupID) { storage.save(group) }
    }

    func flushPendingSaves() {
        for id in Array(saveTasks.keys) { saveNow(id) }
        storage.flush()
    }

    // MARK: - Requests

    func update(_ request: ApiRequest) {
        for g in groups.indices {
            if let r = groups[g].requests.firstIndex(where: { $0.id == request.id }) {
                guard groups[g].requests[r] != request else { return }
                groups[g].requests[r] = request
                queueSave(groups[g].id)
                return
            }
        }
    }

    func addRequest(to groupID: String, kind: RequestKind) {
        guard let g = groupIndex(groupID) else { return }
        let request = kind == .mcp ? ApiRequest.newMCP() : ApiRequest.newHTTP()
        groups[g].requests.append(request)
        saveNow(groupID)
        selection = request.id
        focusURLTick += 1
    }

    func addRequestToCurrentCollection(kind: RequestKind) {
        if let group = selectedGroup ?? groups.first {
            addRequest(to: group.id, kind: kind)
        } else {
            addGroup()
            if let group = groups.last { addRequest(to: group.id, kind: kind) }
        }
    }

    func duplicate(_ requestID: String) {
        for g in groups.indices {
            if let r = groups[g].requests.firstIndex(where: { $0.id == requestID }) {
                let copy = groups[g].requests[r].duplicated()
                groups[g].requests.insert(copy, at: r + 1)
                saveNow(groups[g].id)
                selection = copy.id
                return
            }
        }
    }

    func duplicateSelected() {
        if let selection { duplicate(selection) }
    }

    func deleteRequest(_ requestID: String) {
        for g in groups.indices {
            if let r = groups[g].requests.firstIndex(where: { $0.id == requestID }) {
                groups[g].requests.remove(at: r)
                saveNow(groups[g].id)
                responses[requestID] = nil
                if selection == requestID {
                    // Land on a neighbour rather than on nothing.
                    let remaining = groups[g].requests
                    selection = remaining.isEmpty ? nil : remaining[min(r, remaining.count - 1)].id
                }
                return
            }
        }
    }

    func deleteSelected() {
        if let selection { deleteRequest(selection) }
    }

    /// Requests are an array inside one file, so their order is just that array.
    /// A move never crosses collections: each collection's list moves on its own.
    func moveRequests(in groupID: String, from source: IndexSet, to destination: Int) {
        guard let g = groupIndex(groupID) else { return }
        groups[g].requests.move(fromOffsets: source, toOffset: destination)
        saveNow(groupID)
    }

    // MARK: - Collections

    func addGroup() {
        var group = RequestGroup()
        group.order = groups.count
        groups.append(group)
        saveNow(group.id)
        editingCollection = GroupRef(id: group.id)
    }

    func renameGroup(_ id: String, to name: String) {
        guard let g = groupIndex(id) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != groups[g].name else { return }
        groups[g].name = trimmed
        saveNow(id)
    }

    /// Settings only: the requests are whatever is current, not what the sheet opened with.
    func applySettings(_ draft: RequestGroup) {
        guard let g = groupIndex(draft.id) else { return }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { groups[g].name = name }
        groups[g].auth = draft.auth
        groups[g].variables = draft.variables
        groups[g].color = draft.color
        saveNow(draft.id)
    }

    func editSettingsOfCurrentCollection() {
        if let group = selectedGroup { editingCollection = GroupRef(id: group.id) }
    }

    func deleteGroup(_ id: String) {
        guard let g = groupIndex(id) else { return }
        let removed = groups.remove(at: g)
        saveTasks[id]?.cancel()
        saveTasks[id] = nil
        storage.delete(groupID: id)
        for request in removed.requests { responses[request.id] = nil }
        if let selection, removed.requests.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    /// Every collection is rewritten: `order` is a position, and moving one row
    /// shifts all the rows after it.
    func moveGroups(from source: IndexSet, to destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        renumberGroups()
    }

    func moveGroup(_ id: String, by offset: Int) {
        guard let from = groupIndex(id) else { return }
        let to = from + offset
        guard groups.indices.contains(to) else { return }
        groups = groups.moving(from: from, to: to)
        renumberGroups()
    }

    private func renumberGroups() {
        for index in groups.indices {
            groups[index].order = index
            saveNow(groups[index].id)
        }
    }

    // MARK: - Sending

    func isSending(_ requestID: String) -> Bool { sending.contains(requestID) }

    func sendSelected() {
        guard let request = selectedRequest, !sending.contains(request.id) else { return }
        send(request)
    }

    func send(_ request: ApiRequest) {
        let group = group(containing: request.id)
        let resolved: ResolvedRequest
        switch resolve(request, group: group) {
        case .failure(let error):
            // A malformed arguments box is a typo, not a failed request: it never
            // reaches the network and never lands in history.
            responses[request.id] = ResponseEntry(response: .failure(error.message))
            return
        case .success(let value):
            resolved = value
        }

        let id = request.id
        let name = request.name
        let method = request.method
        sending.insert(id)
        sendTasks[id] = Task { [weak self, sender] in
            let response = await sender.send(resolved)
            guard let self else { return }
            self.sending.remove(id)
            self.sendTasks[id] = nil
            self.responses[id] = ResponseEntry(response: response)
            if Task.isCancelled { return }
            self.record(HistoryItem(name: name, method: method, url: resolved.url, resolved: resolved, response: response))
        }
    }

    func cancelSelected() {
        if let selection { sendTasks[selection]?.cancel() }
    }

    /// Send a history entry again, exactly as it went out the first time. The
    /// result opens in the detail sheet unless the caller handles it.
    func replay(_ item: HistoryItem, onResult: ((HistoryItem) -> Void)? = nil) {
        replaying.insert(item.id)
        Task { [weak self, sender] in
            let response = await sender.send(item.resolved)
            guard let self else { return }
            self.replaying.remove(item.id)
            var replayed = item
            replayed.id = newID("h")
            replayed.timestamp = Date().timeIntervalSince1970 * 1000
            replayed.response = response
            self.record(replayed)
            if let onResult { onResult(replayed) } else { self.inspectedHistory = replayed }
        }
    }

    private func record(_ item: HistoryItem) {
        history.insert(item, at: 0)
        if history.count > historyLimit { history.removeLast(history.count - historyLimit) }
        storage.saveHistory(history)
    }

    func clearHistory() {
        history = []
        storage.saveHistory([])
    }
}
