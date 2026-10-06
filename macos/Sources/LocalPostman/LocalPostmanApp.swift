import AppKit
import PostmanCore
import SwiftUI

@main
struct LocalPostmanApp: App {
    @State private var model = AppModel()
    @AppStorage("appearance") private var appearance: Appearance = .system

    init() {
        // Launched as a bare executable (swift run, or Run in Xcode on the
        // package) there is no bundle telling macOS this is a regular app.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        // One window: there is one set of collections and one history, and a
        // second window editing the same files would only race the first.
        Window("Local Postman", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear {
                    appearance.apply()
                    NSApp.activate()
                }
                .onChange(of: appearance) { _, next in next.apply() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.flushPendingSaves()
                }
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(model: model, appearance: $appearance) }

        Settings {
            SettingsView()
        }
    }
}

struct AppCommands: Commands {
    let model: AppModel
    @Binding var appearance: Appearance

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Request") { model.addRequestToCurrentCollection(kind: .http) }
                .keyboardShortcut("n")
            Button("New MCP Request") { model.addRequestToCurrentCollection(kind: .mcp) }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("New Collection") { model.addGroup() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Reload from Disk") { model.reload() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandMenu("Request") {
            Button("Send") { model.sendSelected() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Cancel") { model.cancelSelected() }
                .keyboardShortcut(".", modifiers: .command)
            Divider()
            Button("Focus URL") { model.focusURLTick += 1 }
                .keyboardShortcut("l")
            Button("Duplicate") { model.duplicateSelected() }
                .keyboardShortcut("d")
            // No shortcut on purpose: ⌘⌫ belongs to the text fields.
            Button("Delete") { model.deleteSelected() }
            Divider()
            Button("Collection Settings…") { model.editSettingsOfCurrentCollection() }
                .keyboardShortcut(",", modifiers: [.command, .option])
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle History") { model.showHistory.toggle() }
                .keyboardShortcut("y")
            Button("Toggle Response Maximized") { model.responseMaximized.toggle() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            Button("Toggle Side-by-Side Layout") { model.sideBySide.toggle() }
                .keyboardShortcut("\\", modifiers: [.command])
            Divider()
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.label).tag($0) }
            }
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

struct SettingsView: View {
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.label).tag($0) }
            }
            LabeledContent("Storage") {
                Text(Storage.defaultDirectory.path)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            LabeledContent("Version") { Text(appVersion) }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
