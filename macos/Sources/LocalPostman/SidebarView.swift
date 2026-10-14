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
                // Not Section(isExpanded:): its system chevron appears on hover and
                // takes width from the header, shifting the gear under the pointer.
                let isExpanded = expanded(group.id)
                Section {
                    if isExpanded.wrappedValue {
                        ForEach(group.requests) { request in
                            RequestRow(request: request, isSending: model.isSending(request.id))
                                .tag(request.id)
                        }
                        .onMove { model.moveRequests(in: group.id, from: $0, to: $1) }

                        if group.requests.isEmpty {
                            EmptyCollectionRow(groupID: group.id)
                        }
                    }
                } header: {
                    CollectionRow(group: group, isExpanded: isExpanded)
                        .contextMenu { collectionMenu(group) }
                }
            }
            .onMove { model.moveGroups(from: $0, to: $1) }
        }
        .listStyle(.sidebar)
        // The primary action is the double-click. A tap gesture on the row loses
        // to the table's own click handling.
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count == 1, let id = ids.first, let request = model.binding(forRequest: id)?.wrappedValue {
                requestMenu(request)
            }
        } primaryAction: { ids in
            if ids.count == 1 { model.renamingRequest = ids.first }
        }
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
        Button("Rename") { model.renamingRequest = request.id }
        Button("Duplicate") { model.duplicate(request.id) }
        Divider()
        Button("Delete", role: .destructive) { model.deleteRequest(request.id) }
    }

    @ViewBuilder
    private func collectionMenu(_ group: RequestGroup) -> some View {
        Button("New Request") { model.addRequest(to: group.id, kind: .http) }
        Button("New MCP Request") { model.addRequest(to: group.id, kind: .mcp) }
        Divider()
        Button("Rename") { model.renamingCollection = group.id }
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
    @Environment(AppModel.self) private var model
    let request: ApiRequest
    let isSending: Bool

    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    private var renaming: Bool { model.renamingRequest == request.id }

    var body: some View {
        HStack(spacing: 6) {
            MethodBadge(badge: request.badge)
            if renaming {
                TextField("Name", text: $draftName)
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { model.renamingRequest = nil }
                    .onChange(of: nameFocused) { _, focused in if !focused { commitRename() } }
                    .onAppear {
                        draftName = request.name
                        // The field does not exist until this update lands; focus it on the next.
                        DispatchQueue.main.async { nameFocused = true }
                    }
            } else {
                Text(request.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            if isSending {
                ProgressView().controlSize(.mini)
            }
        }
        .help(request.url)
    }

    private func commitRename() {
        guard renaming else { return }
        model.renamingRequest = nil
        model.renameRequest(request.id, to: draftName)
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

/// A collection's header: colour, name, and on hover the add, add-MCP and
/// settings buttons. Double-click collapses it; Rename is in its menu.
struct CollectionRow: View {
    @Environment(AppModel.self) private var model
    let group: RequestGroup
    @Binding var isExpanded: Bool

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

            // Always laid out, only shown on hover, so nothing to its left moves.
            Button { withAnimation(.snappy) { isExpanded.toggle() } } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .opacity(hovering || !isExpanded ? 1 : 0)
            .help(isExpanded ? "Collapse" : "Expand")
        }
        .buttonStyle(.borderless)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if !renaming { withAnimation(.snappy) { isExpanded.toggle() } }
        }
        .onHover { hovering = $0 }
        .onChange(of: model.renamingCollection) { _, id in
            if id == group.id {
                model.renamingCollection = nil
                startRename()
            }
        }
    }

    private var settingsHint: String {
        var set: [String] = []
        if group.authValue.mode == .basic { set.append("Basic auth") }
        let count = group.activeVariableCount
        if count > 0 { set.append("\(count) variable\(count == 1 ? "" : "s")") }
        return set.isEmpty ? "Collection settings" : "Collection settings: " + set.joined(separator: ", ")
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
