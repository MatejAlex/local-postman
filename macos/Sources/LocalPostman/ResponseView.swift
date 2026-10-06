import AppKit
import PostmanCore
import SwiftUI
import WebKit

enum ResponseTab: String, CaseIterable, Identifiable {
    case preview, pretty, raw, headers
    var id: String { rawValue }
}

/// The response pane. A failed request still shows its response: only when
/// nothing came back at all (status 0) does it collapse to the bare message,
/// because a server's own explanation is nearly always more specific than ours.
struct ResponseView: View {
    let entry: ResponseEntry?
    let isSending: Bool
    var isMaximized = false
    var onToggleMaximize: (() -> Void)?

    var body: some View {
        Group {
            if isSending {
                ProgressView("Sending…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let entry {
                if entry.response.isBareFailure {
                    BareFailure(message: entry.response.error ?? "Request failed")
                } else {
                    // Keyed by the entry, so each new response opens on its own default tab.
                    LoadedResponse(response: entry.response, isMaximized: isMaximized, onToggleMaximize: onToggleMaximize)
                        .id(entry.id)
                }
            } else {
                ContentUnavailableView(
                    "No Response Yet",
                    systemImage: "arrow.down.left.circle",
                    description: Text("Send the request with ⌘↩ to see what comes back.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

private struct BareFailure: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Request failed", systemImage: "xmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(monoFont)
                .foregroundStyle(.red)
                .textSelection(.enabled)
            Text("Nothing came back: no status, no headers, no body.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct LoadedResponse: View {
    let response: ApiResponse
    let isMaximized: Bool
    let onToggleMaximize: (() -> Void)?

    @State private var tab: ResponseTab
    @State private var pretty: String?
    @State private var wrap = true
    @State private var copied = false

    init(response: ApiResponse, isMaximized: Bool, onToggleMaximize: (() -> Void)?) {
        self.response = response
        self.isMaximized = isMaximized
        self.onToggleMaximize = onToggleMaximize
        // An HTML page is unreadable as source, so it opens on the rendered preview.
        _tab = State(initialValue: looksHTML(contentType: response.contentType, body: response.body) ? .preview : .pretty)
    }

    private var isHTML: Bool { looksHTML(contentType: response.contentType, body: response.body) }
    private var tabs: [ResponseTab] { isHTML ? [.preview, .pretty, .raw, .headers] : [.pretty, .raw, .headers] }

    private var language: CodeLanguage {
        if isHTML || looksXML(contentType: response.contentType, body: response.body) { return .markup }
        if response.contentType.lowercased().contains("json") || looksJSON(response.body) { return .json }
        return .plain
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = response.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(error).font(smallMonoFont).foregroundStyle(.red).textSelection(.enabled)
                        Text("The server's own response is below.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.red.opacity(0.08))
            }

            statusBar
            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: response.body) {
            // Formatting a large body is real work; do it off the main thread.
            let body = response.body
            let contentType = response.contentType
            pretty = await Task.detached(priority: .userInitiated) {
                prettyBody(body, contentType: contentType)
            }.value
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            StatusPill(status: response.status, text: "\(response.status) \(response.statusText)".trimmingCharacters(in: .whitespaces))
            Label(formatTime(response.timeMs), systemImage: "clock")
                .foregroundStyle(.secondary)
            Label(formatSize(response.sizeBytes), systemImage: "doc")
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Picker("View", selection: $tab) {
                ForEach(tabs) { tab in
                    Text(tab == .headers ? "Headers \(response.headers.count)" : tab.rawValue.capitalized).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Button {
                wrap.toggle()
            } label: {
                Image(systemName: wrap ? "text.word.spacing" : "arrow.left.and.right.text.vertical")
            }
            .help(wrap ? "Don't wrap lines" : "Wrap lines")
            .disabled(tab == .preview || tab == .headers)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(response.body, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .help("Copy body")

            if let onToggleMaximize {
                Button(action: onToggleMaximize) {
                    Image(systemName: isMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .help(isMaximized ? "Restore the editor (⇧⌘↩)" : "Give the response the whole pane (⇧⌘↩)")
            }
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .preview:
            HTMLPreview(html: response.body)
        case .pretty:
            if let pretty {
                CodeTextView(text: .constant(pretty.isEmpty ? "(empty body)" : pretty), language: language, isEditable: false, wraps: wrap)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .raw:
            CodeTextView(text: .constant(response.body.isEmpty ? "(empty body)" : response.body), language: .plain, isEditable: false, wraps: wrap)
        case .headers:
            HeadersTable(headers: response.headers)
        }
    }
}

struct HeadersTable: View {
    let headers: [String: String]
    /// Off when the table sits inside a scroll view of its own.
    var scrolls = true

    var body: some View {
        if headers.isEmpty {
            Text("No headers.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if scrolls {
            ScrollView { grid.padding(14) }
        } else {
            grid
        }
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            ForEach(headers.keys.sorted(), id: \.self) { name in
                GridRow(alignment: .firstTextBaseline) {
                    Text(name)
                        .font(smallMonoFont.weight(.medium))
                        .foregroundStyle(Palette.accent)
                        .textSelection(.enabled)
                    Text(headers[name] ?? "")
                        .font(smallMonoFont)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
            }
        }
    }
}

/// Renders an HTML body the way the web app's sandboxed iframe did: no
/// JavaScript, no cookies or storage that outlive it, and links do not navigate.
/// This is what makes an ORDS/APEX error page readable.
struct HTMLPreview: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != html else { return }
        context.coordinator.loaded = html
        view.loadHTMLString(html, baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: String?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            // The initial load only. A clicked link or a submitted form would
            // otherwise turn the preview into a browser.
            decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
        }
    }
}
