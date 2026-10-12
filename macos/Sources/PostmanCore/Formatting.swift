import Foundation

// Formatting for the response viewer: sizes, times, and re-indenting bodies.

public func formatTime(_ ms: Double) -> String {
    ms < 1000 ? "\(Int(ms.rounded())) ms" : String(format: "%.2f s", ms / 1000)
}

public func formatSize(_ bytes: Int) -> String {
    if bytes < 1024 { return "\(bytes) B" }
    if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
    return String(format: "%.2f MB", Double(bytes) / (1024 * 1024))
}

public enum StatusClass: Sendable {
    case success, redirect, clientError, serverError, none

    public init(_ status: Int) {
        switch status {
        case 200..<300: self = .success
        case 300..<400: self = .redirect
        case 400..<500: self = .clientError
        case 500...: self = .serverError
        default: self = .none
        }
    }
}

// MARK: - Body sniffing

public func looksJSON(_ body: String) -> Bool {
    let trimmed = body.drop(while: \.isWhitespace)
    return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
}

public func looksHTML(contentType: String, body: String) -> Bool {
    if contentType.lowercased().contains("html") { return true }
    let head = body.drop(while: \.isWhitespace).prefix(100).lowercased()
    return head.hasPrefix("<!doctype html") || head.hasPrefix("<html")
}

public func looksXML(contentType: String, body: String) -> Bool {
    if contentType.lowercased().contains("xml") { return true }
    return body.drop(while: \.isWhitespace).hasPrefix("<?xml")
}

/// Indent whatever the body turns out to be; anything unrecognised comes back as it arrived.
public func prettyBody(_ body: String, contentType: String) -> String {
    if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "" }
    if looksHTML(contentType: contentType, body: body) || looksXML(contentType: contentType, body: body) {
        return prettyMarkup(body)
    }
    if contentType.lowercased().contains("json") || looksJSON(body) {
        return prettyJSON(body)
    }
    return body
}

// MARK: - JSON

/// Re-indent JSON with two spaces, keeping keys in the order the server sent
/// them (a dictionary round-trip would shuffle them). Text that is not valid
/// JSON comes back unchanged.
public func prettyJSON(_ text: String) -> String {
    guard let data = text.data(using: .utf8),
          (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    else { return text }

    var out = String.UnicodeScalarView()
    let scalars = Array(text.unicodeScalars)
    var depth = 0
    var inString = false
    var escaped = false
    var i = 0

    func newline() {
        out.append("\n")
        for _ in 0..<(depth * 2) { out.append(" ") }
    }

    func nextSignificant(after index: Int) -> Unicode.Scalar? {
        var j = index + 1
        while j < scalars.count {
            let c = scalars[j]
            if c != " " && c != "\n" && c != "\r" && c != "\t" { return c }
            j += 1
        }
        return nil
    }

    func hexValue(at index: Int) -> UInt32? {
        guard index + 4 <= scalars.count else { return nil }
        var value: UInt32 = 0
        for k in index..<(index + 4) {
            guard scalars[k].isASCII, let digit = UInt32(String(scalars[k]), radix: 16) else { return nil }
            value = value * 16 + digit
        }
        return value
    }

    /// `\u0159` comes out as `ř`, as JSON.stringify(JSON.parse()) does in the web
    /// app. Control characters, quotes and backslashes stay escaped, because the
    /// result has to remain valid JSON; a lone surrogate is left as it was.
    func decodedEscape(at index: Int) -> (Unicode.Scalar, Int)? {
        guard let unit = hexValue(at: index + 2) else { return nil }
        if (0xD800...0xDBFF).contains(unit) {
            guard index + 7 < scalars.count,
                  scalars[index + 6] == "\\", scalars[index + 7] == "u",
                  let low = hexValue(at: index + 8), (0xDC00...0xDFFF).contains(low),
                  let scalar = Unicode.Scalar(0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00))
            else { return nil }
            return (scalar, 12)
        }
        guard unit >= 0x20, unit != 0x22, unit != 0x5C, let scalar = Unicode.Scalar(unit) else { return nil }
        return (scalar, 6)
    }

    while i < scalars.count {
        let c = scalars[i]
        if inString {
            if escaped {
                escaped = false
            } else if c == "\\" {
                if i + 1 < scalars.count, scalars[i + 1] == "u", let (scalar, length) = decodedEscape(at: i) {
                    out.append(scalar)
                    i += length
                    continue
                }
                escaped = true
            } else if c == "\"" {
                inString = false
            }
            out.append(c)
            i += 1
            continue
        }
        switch c {
        case "\"":
            inString = true
            out.append(c)
        case "{", "[":
            out.append(c)
            let closer: Unicode.Scalar = c == "{" ? "}" : "]"
            if nextSignificant(after: i) == closer {
                // Keep empty containers on one line, as JSON.stringify does.
                var j = i + 1
                while scalars[j] != closer { j += 1 }
                out.append(closer)
                i = j
            } else {
                depth += 1
                newline()
            }
        case "}", "]":
            depth -= 1
            newline()
            out.append(c)
        case ",":
            out.append(c)
            newline()
        case ":":
            out.append(":")
            out.append(" ")
        case " ", "\n", "\r", "\t":
            break
        default:
            out.append(c)
        }
        i += 1
    }
    return String(out)
}

// MARK: - Markup

private let voidTags: Set<String> = [
    "area", "base", "br", "col", "embed", "hr", "img",
    "input", "link", "meta", "param", "source", "track", "wbr",
]

/// Their content is text, not markup, so it is copied through instead of re-indented.
private let rawTextTags: Set<String> = ["script", "style", "pre", "textarea"]

/// HTML lets you omit these closing tags: opening a listed sibling closes the previous one.
private let implicitClose: [String: Set<String>] = [
    "li": ["li"], "p": ["p"], "dt": ["dt", "dd"], "dd": ["dt", "dd"],
    "tr": ["tr"], "td": ["td", "th"], "th": ["td", "th"], "option": ["option"],
]

/// Re-indent HTML or XML so a wall-of-markup error page can be read. A source
/// formatter, not a parser: it never drops content, but badly nested markup
/// comes out with odd indentation.
public func prettyMarkup(_ markup: String) -> String {
    let s = Array(markup.utf16)
    var lines: [String] = []
    var openTags: [String] = []
    var cursor = 0

    func slice(_ from: Int, _ to: Int) -> String {
        String(decoding: s[from..<min(to, s.count)], as: UTF16.self)
    }
    func matches(_ hay: [UInt16], _ n: [UInt16], at i: Int) -> Bool {
        guard i + n.count <= hay.count else { return false }
        for k in 0..<n.count where hay[i + k] != n[k] { return false }
        return true
    }
    func indexOf(_ needle: String, from: Int, in hay: [UInt16]? = nil) -> Int? {
        let hay = hay ?? s
        let n = Array(needle.utf16)
        guard !n.isEmpty, hay.count >= n.count, from <= hay.count - n.count else { return nil }
        for i in from...(hay.count - n.count) where hay[i] == n[0] && matches(hay, n, at: i) { return i }
        return nil
    }
    // Lowercased once, and only if a raw-text tag needs it. Lowercasing can change
    // the UTF-16 length of exotic text; then the close tag is simply not found.
    var lowerCache: [UInt16]?
    func lower() -> [UInt16] {
        if let lowerCache { return lowerCache }
        let made = Array(markup.lowercased().utf16)
        lowerCache = made
        return made
    }
    func push(_ text: String) {
        lines.append(text.isEmpty ? "" : String(repeating: "  ", count: min(openTags.count, 30)) + text)
    }
    func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    while cursor < s.count {
        guard let tagStart = indexOf("<", from: cursor) else {
            push(trimmed(slice(cursor, s.count)))
            break
        }
        let text = trimmed(slice(cursor, tagStart))
        if !text.isEmpty { push(text) }

        if slice(tagStart, tagStart + 4) == "<!--" {
            let stop = indexOf("-->", from: tagStart).map { $0 + 3 } ?? s.count
            push(trimmed(slice(tagStart, stop)))
            cursor = stop
            continue
        }

        guard let tagEnd = indexOf(">", from: tagStart) else {
            push(trimmed(slice(tagStart, s.count)))
            break
        }

        let tag = slice(tagStart, tagEnd + 1)
        let name = tagName(tag)
        cursor = tagEnd + 1

        if tag.hasPrefix("</") {
            if let openedAt = openTags.lastIndex(of: name) {
                openTags.removeSubrange(openedAt...)
            }
            push(tag)
            continue
        }

        if let previous = openTags.last, implicitClose[name]?.contains(previous) == true {
            openTags.removeLast()
        }
        push(tag)

        let closesItself = tag.hasSuffix("/>") || tag.hasPrefix("<!") || tag.hasPrefix("<?") || voidTags.contains(name)
        if closesItself { continue }
        openTags.append(name)

        if rawTextTags.contains(name) {
            let folded = lower()
            var stop = s.count
            if folded.count == s.count, let found = indexOf("</\(name)", from: cursor, in: folded) {
                stop = found
            }
            for line in dedent(slice(cursor, stop)) { push(line) }
            cursor = stop
        }
    }
    return lines.joined(separator: "\n")
}

private func tagName(_ tag: String) -> String {
    var chars = tag.dropFirst() // "<"
    if chars.first == "/" { chars = chars.dropFirst() }
    chars = chars.drop(while: \.isWhitespace)
    let name = chars.prefix { $0.isLetter || $0.isNumber || $0 == ":" || $0 == "_" || $0 == "-" }
    return name.lowercased()
}

/// Strip the blank edges and the shared leading whitespace off a raw text block.
private func dedent(_ block: String) -> [String] {
    var lines = block.components(separatedBy: "\n").map { line -> String in
        var l = Substring(line)
        while let last = l.last, last.isWhitespace { l = l.dropLast() }
        return String(l)
    }
    while lines.first == "" { lines.removeFirst() }
    while lines.last == "" { lines.removeLast() }
    let shared = lines.filter { !$0.isEmpty }.map { $0.prefix(while: \.isWhitespace).count }.min()
    guard let shared else { return lines }
    return lines.map { String($0.dropFirst(shared)) }
}
