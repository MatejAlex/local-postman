import AppKit
import SwiftUI

enum CodeLanguage {
    case plain, json, markup
}

/// A monospaced text view backed by NSTextView.
///
/// SwiftUI's TextEditor turns `"` into curly quotes and has no find bar, and
/// SwiftUI's Text is slow on a megabyte response. NSTextView has neither
/// problem: substitutions are switched off, ⌘F opens the find bar, and it lays
/// out lazily.
struct CodeTextView: NSViewRepresentable {
    @Binding var text: String
    var language: CodeLanguage = .plain
    var isEditable = true
    var wraps = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let view = scroll.documentView as! NSTextView
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.smartInsertDeleteEnabled = false
        view.font = CodeStyle.font
        view.textColor = .labelColor
        view.typingAttributes = CodeStyle.baseAttributes
        view.textContainerInset = NSSize(width: 8, height: 10)

        context.coordinator.textView = view
        apply(to: view, scroll: scroll, context: context, force: true)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = context.coordinator.textView else { return }
        apply(to: view, scroll: scroll, context: context, force: false)
    }

    private func apply(to view: NSTextView, scroll: NSScrollView, context: Context, force: Bool) {
        view.isEditable = isEditable
        view.isSelectable = true

        let coordinator = context.coordinator
        if coordinator.wraps != wraps || force {
            coordinator.wraps = wraps
            setWrapping(wraps, view: view, scroll: scroll)
        }

        if force || view.string != text {
            // Keep the caret where it was when the text is replaced from outside
            // (Beautify, switching requests) rather than jumping to the end.
            let selection = view.selectedRanges
            view.string = text
            let length = (text as NSString).length
            view.selectedRanges = selection.compactMap { value in
                let range = value.rangeValue
                return range.location <= length ? NSValue(range: NSRange(location: range.location, length: min(range.length, length - range.location))) : nil
            }
            coordinator.language = language
            coordinator.highlightNow()
        } else if coordinator.language != language {
            coordinator.language = language
            coordinator.highlightNow()
        }
    }

    private func setWrapping(_ wraps: Bool, view: NSTextView, scroll: NSScrollView) {
        guard let container = view.textContainer else { return }
        if wraps {
            scroll.hasHorizontalScroller = false
            view.isHorizontallyResizable = false
            view.autoresizingMask = [.width]
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        } else {
            scroll.hasHorizontalScroller = true
            view.isHorizontallyResizable = true
            view.autoresizingMask = []
            container.widthTracksTextView = false
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        }
        view.needsLayout = true
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextView
        weak var textView: NSTextView?
        var language: CodeLanguage = .plain
        var wraps = true
        private var pending: DispatchWorkItem?

        init(_ parent: CodeTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            // Re-colour after typing pauses, not on every keystroke.
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.highlightNow() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }

        func highlightNow() {
            guard let storage = textView?.textStorage else { return }
            SyntaxHighlighter.apply(language, to: storage)
        }
    }
}

enum CodeStyle {
    static let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.labelColor]
    }
}

/// Colours JSON and markup. A single forward scan, no regexes, and it gives up
/// on very large bodies so a 20 MB response never stalls the main thread.
enum SyntaxHighlighter {
    static let limit = 2_000_000

    static let key = NSColor.systemPurple
    static let string = NSColor.systemGreen
    static let number = NSColor.systemOrange
    static let literal = NSColor.systemPink
    static let punctuation = NSColor.secondaryLabelColor
    static let tag = NSColor.systemBlue
    static let attribute = NSColor.systemTeal
    static let comment = NSColor.tertiaryLabelColor

    static func apply(_ language: CodeLanguage, to storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        defer { storage.endEditing() }
        storage.setAttributes(CodeStyle.baseAttributes, range: full)
        guard storage.length <= limit else { return }

        let text = storage.string as NSString
        switch language {
        case .plain: return
        case .json: json(text, storage)
        case .markup: markup(text, storage)
        }
    }

    private static func color(_ storage: NSTextStorage, _ color: NSColor, _ location: Int, _ length: Int) {
        storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: location, length: length))
    }

    private static func json(_ text: NSString, _ storage: NSTextStorage) {
        let n = text.length
        var i = 0
        while i < n {
            let c = text.character(at: i)
            switch c {
            case 0x22: // "
                var j = i + 1
                while j < n {
                    let d = text.character(at: j)
                    if d == 0x5C { j += 2; continue } // backslash
                    if d == 0x22 { break }
                    j += 1
                }
                let end = min(j + 1, n)
                // A string followed by a colon is a key.
                var k = end
                while k < n, isSpace(text.character(at: k)) { k += 1 }
                let isKey = k < n && text.character(at: k) == 0x3A
                color(storage, isKey ? key : string, i, end - i)
                i = end
            case 0x2D, 0x30...0x39: // - and digits
                var j = i + 1
                while j < n, isNumberPart(text.character(at: j)) { j += 1 }
                color(storage, number, i, j - i)
                i = j
            case 0x74, 0x66, 0x6E: // t f n
                var j = i
                while j < n, isLetter(text.character(at: j)) { j += 1 }
                let word = text.substring(with: NSRange(location: i, length: j - i))
                if word == "true" || word == "false" || word == "null" { color(storage, literal, i, j - i) }
                i = max(j, i + 1)
            case 0x7B, 0x7D, 0x5B, 0x5D, 0x3A, 0x2C: // { } [ ] : ,
                color(storage, punctuation, i, 1)
                i += 1
            default:
                i += 1
            }
        }
    }

    private static func markup(_ text: NSString, _ storage: NSTextStorage) {
        let n = text.length
        var i = 0
        while i < n {
            guard text.character(at: i) == 0x3C else { i += 1; continue } // <
            if text.length - i >= 4, text.substring(with: NSRange(location: i, length: 4)) == "<!--" {
                let end = text.range(of: "-->", range: NSRange(location: i, length: n - i))
                let stop = end.location == NSNotFound ? n : end.location + 3
                color(storage, comment, i, stop - i)
                i = stop
                continue
            }
            var j = i + 1
            var quote: unichar = 0
            while j < n {
                let d = text.character(at: j)
                if quote != 0 {
                    if d == quote { quote = 0 }
                } else if d == 0x22 || d == 0x27 {
                    quote = d
                } else if d == 0x3E {
                    break
                }
                j += 1
            }
            let stop = min(j + 1, n)
            color(storage, tag, i, stop - i)
            // Attribute values inside the tag.
            var k = i
            while k < stop {
                let d = text.character(at: k)
                if d == 0x22 || d == 0x27 {
                    var m = k + 1
                    while m < stop, text.character(at: m) != d { m += 1 }
                    color(storage, attribute, k, min(m + 1, stop) - k)
                    k = m + 1
                } else {
                    k += 1
                }
            }
            i = stop
        }
    }

    private static func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 }
    private static func isLetter(_ c: unichar) -> Bool { (0x61...0x7A).contains(c) }
    private static func isNumberPart(_ c: unichar) -> Bool {
        (0x30...0x39).contains(c) || c == 0x2E || c == 0x65 || c == 0x45 || c == 0x2B || c == 0x2D
    }
}
