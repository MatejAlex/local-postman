import PostmanCore
import SwiftUI

/// Key/value rows for params, headers and variables. There is always one blank
/// row at the end; typing into it makes it a real row. An emptied row stays
/// until its ✕ is clicked (removing it mid-edit would steal focus), and an
/// unnamed row is never sent.
struct KeyValueEditor: View {
    @Binding var rows: [KeyValue]
    var keyPlaceholder = "Key"
    var valuePlaceholder = "Value"

    var body: some View {
        let count = rows.count + 1
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                let isBlank = index == rows.count
                GridRow {
                    Toggle("Enabled", isOn: field(index, \.enabled))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .opacity(isBlank ? 0.3 : 1)
                    PlainField(placeholder: keyPlaceholder, text: field(index, \.key))
                    PlainField(placeholder: valuePlaceholder, text: field(index, \.value))
                    Button {
                        remove(index)
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                    .opacity(isBlank ? 0 : 1)
                    .disabled(isBlank)
                    .help("Remove row")
                }
            }
        }
    }

    private func isEmpty(_ row: KeyValue) -> Bool {
        row.key.trimmingCharacters(in: .whitespaces).isEmpty && row.value.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func field<T>(_ index: Int, _ path: WritableKeyPath<KeyValue, T>) -> Binding<T> {
        Binding(
            get: { index < rows.count ? rows[index][keyPath: path] : KeyValue()[keyPath: path] },
            set: { value in
                if rows.indices.contains(index) {
                    rows[index][keyPath: path] = value
                } else if index == rows.count {
                    var row = KeyValue()
                    row[keyPath: path] = value
                    if !isEmpty(row) { rows.append(row) }
                }
            }
        )
    }

    private func remove(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        rows.remove(at: index)
    }
}

/// Username and password, shared by the collection settings and a request's Auth tab.
struct BasicAuthFields: View {
    @Binding var basic: BasicAuth
    let vars: Variables
    @State private var reveal = false

    var body: some View {
        let header = basicAuthHeader(basic, vars: vars)

        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Username").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    PlainField(placeholder: "user or {{db_user}}", text: $basic.username)
                }
                GridRow {
                    Text("Password").foregroundStyle(.secondary)
                    HStack {
                        Group {
                            if reveal {
                                TextField("Password", text: $basic.password, prompt: Text("password or {{db_password}}"))
                            } else {
                                SecureField("Password", text: $basic.password, prompt: Text("password or {{db_password}}"))
                            }
                        }
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .textFieldStyle(.roundedBorder)
                        .font(smallMonoFont)
                        .autocorrectionDisabled()

                        Button(reveal ? "Hide" : "Show") { reveal.toggle() }
                            .buttonStyle(.borderless)
                    }
                }
            }

            Toggle(isOn: $basic.base64) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Base64 encode credentials")
                    Text("Standard HTTP Basic, and what ORDS expects. Leave this on unless you are debugging.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            if !basic.base64 {
                Label("Credentials will be sent verbatim. This is not valid HTTP Basic and most servers will reject it.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Header sent").font(.caption).foregroundStyle(.secondary)
                Text(header == nil
                     ? "None. Fill in a username or password."
                     : reveal ? "Authorization: \(header!)" : "Authorization: Basic ••••••••  (Show to reveal)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary, in: .rect(cornerRadius: 8))
            }
        }
    }
}

/// A monospaced, left-aligned text field whose placeholder is only a prompt.
/// Inside a grouped Form a plain TextField shows its title as a label and
/// right-aligns its text, which turned the variables table into a mess.
struct PlainField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text, prompt: Text(placeholder))
            .labelsHidden()
            .multilineTextAlignment(.leading)
            .textFieldStyle(.roundedBorder)
            .font(smallMonoFont)
            .autocorrectionDisabled()
    }
}
