import PostmanCore
import SwiftUI

enum EditorTab: String, CaseIterable, Identifiable {
    case mcp, params, auth, headers, body

    var id: String { rawValue }

    // An MCP call has no query params and no body of its own, so those tabs
    // would only ever be empty. Fewer tabs is the point.
    static let http: [EditorTab] = [.params, .auth, .headers, .body]
    static let mcpTabs: [EditorTab] = [.mcp, .auth, .headers]
}

struct RequestEditorView: View {
    @Environment(AppModel.self) private var model
    @Binding var request: ApiRequest
    let group: RequestGroup?

    @State private var tab: EditorTab = .params
    @FocusState private var urlFocused: Bool

    private var tabs: [EditorTab] { request.isMCP ? EditorTab.mcpTabs : EditorTab.http }
    private var activeTab: EditorTab { tabs.contains(tab) ? tab : tabs[0] }
    private var vars: Variables { requestVariables(group) }
    private var isSending: Bool { model.isSending(request.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Request name", text: $request.name)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 10)

            urlBar
                .padding(.horizontal, 14)

            ResolvedURLLine(url: request.url, params: request.isMCP ? [] : request.params, vars: vars)
                .padding(.horizontal, 22)
                .padding(.top, 6)

            Picker("Section", selection: Binding(get: { activeTab }, set: { tab = $0 })) {
                ForEach(tabs) { Text(label(for: $0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { tab = tabs[0] }
        .onChange(of: model.focusURLTick) { urlFocused = true }
    }

    // MARK: URL bar

    private var urlBar: some View {
        HStack(spacing: 10) {
            if request.isMCP {
                MethodBadge(badge: "MCP", width: nil)
                    .font(.system(.body, design: .monospaced).weight(.bold))
                    .padding(.leading, 6)
                    .help("MCP over Streamable HTTP. The transport is a POST; the session handshake is handled for you.")
            } else {
                Menu {
                    ForEach(HTTPMethod.allCases, id: \.self) { method in
                        Button(method.rawValue) { request.method = method }
                    }
                } label: {
                    Text(request.method.rawValue)
                        .font(.system(.body, design: .monospaced).weight(.bold))
                        .foregroundStyle(Palette.method(request.method.rawValue))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.leading, 6)
            }

            TextField(request.isMCP ? "http://localhost:8000/mcp" : "https://api.example.com/{{path}}", text: $request.url)
                .textFieldStyle(.plain)
                .font(monoFont)
                .focused($urlFocused)
                .onSubmit { model.sendSelected() }

            if isSending {
                Button("Cancel", role: .cancel) { model.cancelSelected() }
                    .buttonStyle(.glass)
                    .help("Cancel (⌘.)")
            } else {
                Button {
                    model.send(request)
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                        .labelStyle(.titleAndIcon)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.accent)
                .disabled(request.url.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Send (⌘↩)")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .glassEffect(.regular.tint((Palette.collection(group) ?? .clear).opacity(0.12)), in: .capsule)
    }

    private func label(for tab: EditorTab) -> String {
        switch tab {
        case .mcp: return "MCP"
        case .params:
            let n = request.params.filter(\.isActive).count
            return n > 0 ? "Params \(n)" : "Params"
        case .headers:
            let n = request.headers.filter(\.isActive).count
            return n > 0 ? "Headers \(n)" : "Headers"
        case .body:
            return request.bodyType == .none ? "Body" : "Body ●"
        case .auth:
            let auth = request.authValue
            let active = auth.mode == .basic || (auth.mode == .inherit && group?.authValue.mode == .basic)
            return active ? "Auth ●" : "Auth"
        }
    }

    // MARK: Tab content

    @ViewBuilder
    private var content: some View {
        switch activeTab {
        case .mcp:
            ScrollView { McpPanel(config: $request.mcpValue).padding(18) }
        case .params:
            ScrollView {
                KeyValueEditor(rows: $request.params)
                    .padding(18)
            }
        case .headers:
            ScrollView {
                KeyValueEditor(rows: $request.headers, keyPlaceholder: "Header")
                    .padding(18)
            }
        case .auth:
            ScrollView {
                RequestAuthPanel(auth: $request.authValue, collectionAuth: group?.authValue, vars: vars)
                    .padding(18)
            }
        case .body:
            BodyPanel(request: $request)
        }
    }
}

/// The URL as it will go out, shown only when it differs from what was typed:
/// variables substituted, params appended, and anything undefined called out.
struct ResolvedURLLine: View {
    let url: String
    let params: [KeyValue]
    let vars: Variables

    var body: some View {
        let resolved = buildURL(url, params: params, vars: vars)
        let missing = undefinedVariables(in: url, vars)
        if !missing.isEmpty {
            Text("Undefined: " + missing.map { "{{\($0)}}" }.joined(separator: ", ") + ", sent as typed. Define it in the collection's settings.")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if resolved != url && !url.isEmpty {
            Text(resolved)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

struct BodyPanel: View {
    @Binding var request: ApiRequest
    /// Checked after typing pauses and off the main thread: parsing a large body
    /// on every keystroke was most of the cost of typing into it.
    @State private var invalidJSON = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Body type", selection: $request.bodyType) {
                    Text("None").tag(BodyType.none)
                    Text("JSON").tag(BodyType.json)
                    Text("Raw").tag(BodyType.raw)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Spacer()

                if request.bodyType == .json {
                    if invalidJSON {
                        Label("Not valid JSON", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Button("Beautify") { request.body = prettyJSON(request.body) }
                        .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .task(id: JSONCheck(body: request.body, isJSON: request.bodyType == .json)) {
                let body = request.body
                guard request.bodyType == .json, !body.isEmpty else { invalidJSON = false; return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let invalid = await Task.detached(priority: .utility) { JSONValue.parse(body) == nil }.value
                if !Task.isCancelled { invalidJSON = invalid }
            }

            if request.bodyType == .none {
                Text("This request has no body.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                Spacer()
            } else {
                if request.method == .GET || request.method == .HEAD {
                    Text("\(request.method.rawValue) requests are sent without a body.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 18)
                }
                CodeTextView(text: $request.body, language: request.bodyType == .json ? .json : .plain)
                    .background(.background.secondary, in: .rect(cornerRadius: 10))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
    }
}

/// The task key for the JSON check. Equality is by bytes, the same cheap test
/// ApiRequest uses, so a keystroke is not also a normalising string compare.
private struct JSONCheck: Equatable {
    let body: String
    let isJSON: Bool
    static func == (a: JSONCheck, b: JSONCheck) -> Bool { a.isJSON == b.isJSON && sameBytes(a.body, b.body) }
}

struct RequestAuthPanel: View {
    @Binding var auth: RequestAuth
    let collectionAuth: CollectionAuth?
    let vars: Variables

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Auth", selection: $auth.mode) {
                Text("Inherit").tag(RequestAuthMode.inherit)
                Text("Basic").tag(RequestAuthMode.basic)
                Text("No auth").tag(RequestAuthMode.none)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            switch auth.mode {
            case .inherit:
                inheritNote
            case .basic:
                BasicAuthFields(basic: $auth.basic, vars: vars)
            case .none:
                Text("No Authorization header is sent, even when the collection sets one.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    @ViewBuilder
    private var inheritNote: some View {
        if let collectionAuth, collectionAuth.mode == .basic {
            let who = collectionAuth.basic.username.trimmingCharacters(in: .whitespaces)
            let ending = collectionAuth.basic.base64 ? "." : ", sent unencoded."
            Group {
                if who.isEmpty {
                    Text("Using the collection's Basic auth\(ending)")
                } else {
                    Text("Using the collection's Basic auth as \(Text(who).bold().font(smallMonoFont))\(ending)")
                }
            }
            .foregroundStyle(.secondary)
        } else {
            Text("This collection has no auth set, so this request sends none. Set it on the collection to cover every request at once.")
                .foregroundStyle(.secondary)
        }
    }
}

/// The whole MCP surface: which call, what it targets, and its arguments.
/// Deliberately absent: a connect step (every send opens and closes its own
/// session), an OAuth dance, and launching servers.
struct McpPanel: View {
    @Binding var config: McpConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Method", selection: $config.method) {
                ForEach(McpMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).font(monoFont).tag(method)
                }
            }
            .frame(maxWidth: 320)

            if let label = config.method.targetLabel {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    TextField(config.method == .resourcesRead ? "file:///…" : "read_document", text: $config.target)
                        .textFieldStyle(.roundedBorder)
                        .font(monoFont)
                }
            }

            if config.method.takesArguments {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Arguments (JSON)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Beautify") { config.args = prettyJSON(config.args) }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                    }
                    CodeTextView(text: $config.args, language: .json)
                        .frame(minHeight: 160)
                        .background(.background.secondary, in: .rect(cornerRadius: 10))
                }
            }

            Text(config.method.takesArguments
                 ? "Run the matching list method first to see the exact argument names. {{variables}} work here too."
                 : "Takes no arguments. Send it to see what this server offers.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 720, alignment: .leading)
    }
}
