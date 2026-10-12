import PostmanCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    /// Collapsed rather than expanded, so a new collection arrives open.
    @AppStorage("collapsedCollections") private var collapsedStore = ""
    /// The window opens with the sidebar focused. Otherwise AppKit hands focus to
    /// the first text field it finds, the request name, and the first stray
    /// keystroke renames the request.
    @FocusState private var listFocused: Bool

    var body: some View {
        @Bindable var model = model

        List(selection: $model.selection) {
            if !model.loadProblems.isEmpty {
                Section {
                    ForEach(model.loadProblems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(3)
                    }
                }
            }

            ForEach(model.groups) { group in
                Section(isExpanded: expanded(group.id)) {
                    ForEach(group.requests) { request in
                        RequestRow(request: request, isSending: model.isSending(request.id))
                            .tag(request.id)
                            .contextMenu { requestMenu(request) }
                    }
                    .onMove { model.moveRequests(in: group.id, from: $0, to: $1) }

                    if group.requests.isEmpty {
                        EmptyCollectionRow(groupID: group.id)
                    }
                } header: {
                    CollectionRow(group: group)
                        .contextMenu { collectionMenu(group) }
                }
            }
            .onMove { model.moveGroups(from: $0, to: $1) }
        }
        .listStyle(.sidebar)
        .focused($listFocused)
        // defaultFocus alone loses to AppKit's initial key view; claim it once the
        // window has made its own choice.
        .onAppear { DispatchQueue.main.async { listFocused = true } }
        .overlay {
            if model.groups.isEmpty {
                ContentUnavailableView("No Collections", systemImage: "folder", description: Text("Create one to start adding requests."))
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    model.addGroup()
                } label: {
                    Label("New Collection", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.glass)
                .help("New collection (⇧⌘N)")
                Spacer()
            }
            .padding(10)
        }
    }

    private var collapsed: Set<String> {
        Set(collapsedStore.split(separator: ",").map(String.init))
    }

    private func expanded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(id) },
            set: { open in
                var next = collapsed
                if open { next.remove(id) } else { next.insert(id) }
                collapsedStore = next.sorted().joined(separator: ",")
            }
        )
    }

    @ViewBuilder
    private func requestMenu(_ request: ApiRequest) -> some View {
        Button("Send") {
            model.selection = request.id
            model.send(request)
        }
        Button("Duplicate") { model.duplicate(request.id) }
        Divider()
        Button("Delete", role: .destructive) { model.deleteRequest(request.id) }
    }

    @ViewBuilder
    private func collectionMenu(_ group: RequestGroup) -> some View {
        Button("New Request") { model.addRequest(to: group.id, kind: .http) }
        Button("New MCP Request") { model.addRequest(to: group.id, kind: .mcp) }
        Divider()
        Button("Settings…") { model.editingCollection = GroupRef(id: group.id) }
        Divider()
        Button("Move Up") { model.moveGroup(group.id, by: -1) }
            .disabled(model.groups.first?.id == group.id)
        Button("Move Down") { model.moveGroup(group.id, by: 1) }
            .disabled(model.groups.last?.id == group.id)
        Divider()
        Button("Delete Collection…", role: .destructive) { model.pendingDelete = GroupRef(id: group.id) }
    }
}

struct RequestRow: View {
    let request: ApiRequest
    let isSending: Bool

    var body: some View {
        HStack(spacing: 6) {
            MethodBadge(badge: request.badge)
            Text(request.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if isSending {
                ProgressView().controlSize(.mini)
            }
        }
        .help(request.url)
    }
}

struct EmptyCollectionRow: View {
    @Environment(AppModel.self) private var model
    let groupID: String

    var body: some View {
        HStack(spacing: 12) {
            Button("Add request") { model.addRequest(to: groupID, kind: .http) }
            Button("Add MCP request") { model.addRequest(to: groupID, kind: .mcp) }
        }
        .buttonStyle(.link)
        .font(.caption)
        .selectionDisabled()
    }
}

/// A collection's header: colour, name (double-click to rename), and on hover
/// the settings, add and add-MCP buttons.
struct CollectionRow: View {
    @Environment(AppModel.self) private var model
    let group: RequestGroup

    @State private var hovering = false
    @State private var renaming = false
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Palette.collection(group) ?? .clear)
                .frame(width: 9, height: 9)

            if renaming {
                TextField("Name", text: $draftName)
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { renaming = false }
                    .onChange(of: nameFocused) { _, focused in if !focused { commitRename() } }
            } else {
                Text(group.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .onTapGesture(count: 2) { startRename() }
            }

            Spacer(minLength: 4)

            if hovering && !renaming {
                Button { model.addRequest(to: group.id, kind: .http) } label: {
                    Image(systemName: "plus")
                }
                .help("Add request")
                Button { model.addRequest(to: group.id, kind: .mcp) } label: {
                    Text("M").font(.caption.weight(.heavy))
                }
                .help("Add MCP request")
            }

            if hovering || group.isConfigured {
                Button { model.editingCollection = GroupRef(id: group.id) } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(group.isConfigured ? Palette.accent : .secondary)
                }
                .help(settingsHint)
            }

            Text("\(group.requests.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var settingsHint: String {
        var set: [String] = []
        if group.authValue.mode == .basic { set.append("Basic auth") }
        let count = group.activeVariableCount
        if count > 0 { set.append("\(count) variable\(count == 1 ? "" : "s")") }
        return set.isEmpty ? "Collection settings" : "Collection settings — " + set.joined(separator: ", ")
    }

    private func startRename() {
        draftName = group.name
        renaming = true
        // The field does not exist until this update lands; focus it on the next.
        DispatchQueue.main.async { nameFocused = true }
    }

    private func commitRename() {
        guard renaming else { return }
        renaming = false
        model.renameGroup(group.id, to: draftName)
    }
}
