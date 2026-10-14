import PostmanCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
        } detail: {
            DetailView()
        }
        .inspector(isPresented: $model.showHistory) {
            HistoryView()
                .inspectorColumnWidth(min: 260, ideal: 320, max: 520)
        }
        .navigationTitle(model.selectedRequest?.name ?? "Local Postman")
        .navigationSubtitle(model.selectedGroup?.name ?? "")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                CollectionIndicator(group: model.selectedGroup)
            }
            // The indicator is its own tinted capsule; the toolbar's glass behind
            // it drew a second pill around the first.
            .sharedBackgroundVisibility(.hidden)
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    withAnimation(.smooth) { model.sideBySide.toggle() }
                } label: {
                    Label("Layout", systemImage: model.sideBySide ? "rectangle.split.2x1" : "rectangle.split.1x2")
                }
                .help(model.sideBySide ? "Stack request above response (⌘\\)" : "Request and response side by side (⌘\\)")

                Button {
                    withAnimation(.smooth) { model.showHistory.toggle() }
                } label: {
                    Label("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }
                .help("Show or hide history (⌘Y)")
            }
        }
        .sheet(item: $model.inspectedHistory) { item in
            HistoryDetailView(item: item)
                .environment(model)
        }
        .sheet(item: $model.editingCollection) { ref in
            if let group = model.group(ref.id) {
                CollectionSettingsView(group: group)
                    .environment(model)
            }
        }
        .alert(
            deleteTitle,
            isPresented: Binding(get: { model.pendingDelete != nil }, set: { if !$0 { model.pendingDelete = nil } }),
            presenting: model.pendingDelete
        ) { ref in
            Button("Delete", role: .destructive) { model.deleteGroup(ref.id) }
            Button("Cancel", role: .cancel) {}
        } message: { ref in
            Text(deleteWarning(model.group(ref.id)))
        }
    }

    private var deleteTitle: String {
        guard let ref = model.pendingDelete, let group = model.group(ref.id) else { return "Delete collection?" }
        return "Delete “\(group.name)”?"
    }

    private func deleteWarning(_ group: RequestGroup?) -> String {
        let count = group?.requests.count ?? 0
        if count == 0 { return "This collection is empty. Deleting it cannot be undone." }
        return "Its \(count) request\(count == 1 ? "" : "s") go with it, along with the collection's auth and variables. This cannot be undone."
    }
}

/// The collection's colour and name in the toolbar, so which estate the open
/// request points at is visible without reading the URL.
struct CollectionIndicator: View {
    let group: RequestGroup?

    var body: some View {
        if let group, let color = Palette.collection(group) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(group.name).font(.callout.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(color.opacity(0.35)), in: .capsule)
            .help("Collection: \(group.name)")
        }
    }
}

struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let id = model.selection, let request = model.binding(forRequest: id) {
            RequestWorkspace(request: request, group: model.group(containing: id))
                .id(id)
        } else {
            ContentUnavailableView {
                Label(model.groups.isEmpty ? "No Collections" : "No Request Selected", systemImage: "bolt.horizontal")
            } description: {
                Text(model.groups.isEmpty
                     ? "Create a collection to get started."
                     : "Select a request in the sidebar, or add one with ⌘N.")
            } actions: {
                if model.groups.isEmpty {
                    Button("New Collection") { model.addGroup() }
                        .buttonStyle(.glassProminent)
                        .tint(Palette.accent)
                } else {
                    Button("New Request") { model.addRequestToCurrentCollection(kind: .http) }
                        .buttonStyle(.glass)
                }
            }
        }
    }
}

/// The editor and the response, split either way, with the response able to
/// take the whole pane.
struct RequestWorkspace: View {
    @Environment(AppModel.self) private var model
    @Binding var request: ApiRequest
    let group: RequestGroup?
    @AppStorage("splitFraction.stacked") private var stackFraction = 0.45
    @AppStorage("splitFraction.sideBySide") private var sideFraction = 0.5

    var body: some View {
        let response = ResponseView(
            entry: model.responses[request.id],
            isSending: model.isSending(request.id),
            isMaximized: model.responseMaximized,
            onToggleMaximize: { withAnimation(.snappy) { model.responseMaximized.toggle() } }
        )

        Group {
            if model.responseMaximized {
                response
            } else if model.sideBySide {
                PaneSplit(axis: .horizontal, fraction: $sideFraction, minFirst: 380, minSecond: 360) {
                    RequestEditorView(request: $request, group: group)
                } second: {
                    response
                }
            } else {
                PaneSplit(axis: .vertical, fraction: $stackFraction, minFirst: 220, minSecond: 180) {
                    RequestEditorView(request: $request, group: group)
                } second: {
                    response
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
