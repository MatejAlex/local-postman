import AppKit
import PostmanCore
import SwiftUI

/// The last 50 sends. 🔍 opens what went out and what came back; ↻ sends it again.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""
    @State private var confirmingClear = false

    private var items: [HistoryItem] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return model.history }
        return model.history.filter {
            $0.displayName.lowercased().contains(needle) || $0.url.lowercased().contains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History").font(.headline)
                Spacer()
                if !model.history.isEmpty {
                    Button("Clear") { confirmingClear = true }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            TextField("Filter", text: $filter)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            if model.history.isEmpty {
                ContentUnavailableView("No Requests Yet", systemImage: "clock", description: Text("Everything you send lands here."))
            } else {
                List(items) { item in
                    HistoryRow(item: item, isReplaying: model.replaying.contains(item.id))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { model.inspectedHistory = item }
                        .contextMenu {
                            Button("View Request and Response") { model.inspectedHistory = item }
                            Button("Send Again") { model.replay(item) }
                            Divider()
                            Button("Copy URL") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.url, forType: .string)
                            }
                        }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .confirmationDialog("Clear all history?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { model.clearHistory() }
        } message: {
            Text("The last \(model.history.count) sends, with their responses, are removed. This cannot be undone.")
        }
    }
}

struct HistoryRow: View {
    @Environment(AppModel.self) private var model
    let item: HistoryItem
    let isReplaying: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                MethodBadge(badge: item.badge, width: 40)
                if item.response.error != nil && item.response.status == 0 {
                    Text("ERR").font(.caption.weight(.bold)).foregroundStyle(.red)
                } else {
                    Text("\(item.response.status)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(item.response.error != nil ? .red : Palette.status(item.response.status))
                }
                Text(formatTime(item.response.timeMs))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if isReplaying {
                    ProgressView().controlSize(.mini)
                } else if hovering {
                    Button { model.inspectedHistory = item } label: { Image(systemName: "magnifyingglass") }
                        .help("View request and response")
                    Button { model.replay(item) } label: { Image(systemName: "arrow.clockwise") }
                        .help("Send again")
                } else {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        // The relative format reads "in 0 sec" for a send that just
                        // finished, its timestamp being a hair ahead of the clock.
                        Text(context.date.timeIntervalSince(item.date) < 60
                             ? "just now"
                             : item.date.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.borderless)

            // History recorded before v1.2 has no name.
            let unnamed = item.name?.trimmingCharacters(in: .whitespaces).isEmpty ?? true
            Text(item.displayName)
                .font(.callout)
                .italic(unnamed)
                .foregroundStyle(unnamed ? Color.secondary : Color.primary)
                .lineLimit(1)
            Text(item.url)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 3)
        .onHover { hovering = $0 }
    }
}

/// One history entry: the response exactly as the main viewer shows it, and
/// the request as it actually went out (variables substituted, auth resolved).
struct HistoryDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var item: HistoryItem
    @State private var entry: ResponseEntry
    @State private var pane = 0

    init(item: HistoryItem) {
        _item = State(initialValue: item)
        _entry = State(initialValue: ResponseEntry(response: item.response))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        MethodBadge(badge: item.badge, width: nil)
                        Text(item.displayName).font(.headline)
                        Text(item.date.formatted(date: .abbreviated, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(item.url)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    // Swap the result in here rather than re-presenting the sheet.
                    model.replay(item) { replayed in
                        item = replayed
                        entry = ResponseEntry(response: replayed.response)
                        pane = 0
                    }
                } label: {
                    Label("Send Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
                .disabled(model.replaying.contains(item.id))
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .tint(Palette.accent)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Picker("Pane", selection: $pane) {
                Text("Response").tag(0)
                Text("Request").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.bottom, 10)

            Divider()

            if pane == 0 {
                ResponseView(entry: entry, isSending: model.replaying.contains(item.id))
            } else {
                SentRequestView(item: item)
            }
        }
        .frame(minWidth: 820, idealWidth: 1000, minHeight: 560, idealHeight: 720)
    }
}

struct SentRequestView: View {
    let item: HistoryItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("URL")
                    Text(item.resolved.url).font(smallMonoFont).textSelection(.enabled)
                }

                if let mcp = item.resolved.mcp {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("MCP call")
                        Text(prettyJSON(JSONValue.object(["method": .string(mcp.method.rawValue), "params": .object(mcp.params)]).serialized()))
                            .font(smallMonoFont)
                            .textSelection(.enabled)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Headers (\(item.resolved.headers.count))")
                    if item.resolved.headers.isEmpty {
                        Text("No headers sent.").foregroundStyle(.secondary)
                    } else {
                        HeadersTable(headers: item.resolved.headers, scrolls: false)
                    }
                }

                if item.resolved.mcp == nil {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Body")
                        let sent = item.resolved.body ?? ""
                        Text(sent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(no body)" : prettyJSON(sent))
                            .font(smallMonoFont)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
    }
}
