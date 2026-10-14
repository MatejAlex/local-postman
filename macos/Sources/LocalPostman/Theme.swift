import PostmanCore
import SwiftUI

extension Color {
    /// `#rrggbb`, as collections store their colour.
    init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        let value = UInt64(text, radix: 16) ?? 0x6b7280
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}

enum Palette {
    /// The web app's indigo, kept so the two read as the same tool.
    static let accent = Color(red: 0.39, green: 0.40, blue: 0.95)

    static func method(_ badge: String) -> Color {
        switch badge {
        case "GET": .green
        case "POST": .orange
        case "PUT": .blue
        case "PATCH": .purple
        case "DELETE": .red
        case "MCP": accent
        default: .secondary
        }
    }

    static func status(_ status: Int) -> Color {
        switch StatusClass(status) {
        case .success: .green
        case .redirect: .blue
        case .clientError: .orange
        case .serverError: .red
        case .none: .secondary
        }
    }

    static func collection(_ group: RequestGroup?) -> Color? {
        group?.color.map(Color.init(hex:))
    }
}

/// The method label used in the sidebar, history and title bar.
struct MethodBadge: View {
    let badge: String
    var width: CGFloat? = 46

    var body: some View {
        Text(badge)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(Palette.method(badge))
            .frame(width: width, alignment: .leading)
    }
}

/// `200 OK` in a tinted capsule.
struct StatusPill: View {
    let status: Int
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.callout, design: .monospaced).weight(.semibold))
            .foregroundStyle(Palette.status(status))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Palette.status(status).opacity(0.14), in: .capsule)
    }
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }
}

let monoFont = Font.system(.body, design: .monospaced)
let smallMonoFont = Font.system(.callout, design: .monospaced)

/// Lets the user drag a sheet larger. SwiftUI presents sheets fixed-size on
/// macOS whatever their frame says, so this sets the window's own flag.
struct ResizableSheet: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.styleMask.insert(.resizable)
        }
    }
}

extension View {
    func resizableSheet() -> some View { background(ResizableSheet()) }
}
