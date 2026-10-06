import PostmanCore
import SwiftUI

/// The ⚙ sheet: name, colour, variables and auth of one collection. Edits a
/// draft and applies it on Save, so Cancel really cancels.
struct CollectionSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RequestGroup

    init(group: RequestGroup) {
        _draft = State(initialValue: group)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                }

                Section {
                    HStack(spacing: 12) {
                        ForEach(collectionColors, id: \.self) { hex in
                            Button {
                                draft.color = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 22, height: 22)
                                    .overlay {
                                        if draft.color == hex {
                                            Circle().strokeBorder(.primary, lineWidth: 2).padding(-4)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(hex)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Colour")
                } footer: {
                    Text("Tags the collection in the sidebar and tints the URL bar and toolbar while one of its requests is open. Green for development, red for production; the meaning is yours.")
                }

                Section {
                    KeyValueEditor(rows: $draft.variablesValue, keyPlaceholder: "token", valuePlaceholder: "value")
                } header: {
                    Text("Variables — reference with {{key}}")
                } footer: {
                    Text("Available to every request in this collection, in the URL, params, headers, body and MCP arguments. A collection is the only place a variable can come from. Variables are stored in the collection file, so blank tokens before sharing it.")
                }

                Section {
                    Picker("Auth", selection: $draft.authValue.mode) {
                        Text("No auth").tag(AuthMode.none)
                        Text("Basic").tag(AuthMode.basic)
                    }
                    .pickerStyle(.segmented)

                    if draft.authValue.mode == .basic {
                        BasicAuthFields(basic: $draft.authValue.basic, vars: variableMap(draft.variablesValue))
                    } else {
                        Text("Requests in this collection send no Authorization header unless they set their own.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Auth")
                } footer: {
                    Text("The password is kept in secrets.json, not in the collection file, so the file can be shared as it is.")
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    model.applySettings(draft)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 620, height: 680)
    }
}
