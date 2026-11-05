#if os(macOS)
import AppKit
import ShowreadyCore

/// Release notes as formatted text for an alert.
///
/// `NSAlert.informativeText` is plain, so the markdown the notes are written
/// in — `**bold**`, `- ` bullets — would show up as literal asterisks and
/// dashes. This renders the inline markdown and swaps list dashes for bullets,
/// inside a scrolling view so several versions' worth fits.
enum ReleaseNotesView {
    static func make(markdown: String, width: CGFloat = 440, height: CGFloat = 240) -> NSView {
        let prepared = markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("- ") ? "•  " + trimmed.dropFirst(2) : String(line)
            }
            .joined(separator: "\n")

        let rendered: NSAttributedString
        if let attributed = try? AttributedString(
            markdown: prepared,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            rendered = NSAttributedString(attributed)
        } else {
            rendered = NSAttributedString(string: prepared)
        }

        let body = NSMutableAttributedString(attributedString: rendered)
        let whole = NSRange(location: 0, length: body.length)
        body.addAttribute(.foregroundColor, value: NSColor.labelColor, range: whole)
        // Keep the bold the markdown asked for; set size and family underneath.
        body.enumerateAttribute(.font, in: whole) { value, range, _ in
            let existing = value as? NSFont
            let bold = existing?.fontDescriptor.symbolicTraits.contains(.bold) == true
            body.addAttribute(.font, value: bold
                ? NSFont.systemFont(ofSize: 12, weight: .semibold)
                : NSFont.systemFont(ofSize: 12), range: range)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 2
        body.addAttribute(.paragraphStyle, value: paragraph, range: whole)

        // Bullet points get a hanging indent, so a wrapped line sits under the
        // text rather than back at the margin under the bullet.
        let bulletIndent = ("•  " as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width
        let hanging = NSMutableParagraphStyle()
        hanging.paragraphSpacing = 2
        hanging.headIndent = bulletIndent
        // Version headings get a little air above them.
        let heading = NSMutableParagraphStyle()
        heading.paragraphSpacingBefore = 6
        heading.paragraphSpacing = 2
        let string = body.string as NSString
        string.enumerateSubstrings(in: whole, options: .byParagraphs) { sub, range, _, _ in
            guard let sub else { return }
            if sub.hasPrefix("•") {
                body.addAttribute(.paragraphStyle, value: hanging, range: range)
            } else if sub.hasPrefix("Showready ") {
                body.addAttribute(.paragraphStyle, value: heading, range: range)
            }
        }

        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 4, height: 6)
        text.textStorage?.setAttributedString(body)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        text.autoresizingMask = [.width]
        return scroll
    }
}

/// The alert that offers an update, with the notes rendered rather than shown
/// as raw markdown.
@MainActor
enum UpdateOfferAlert {
    /// Returns true if the user chose to update.
    static func ask(version: String, notes: String) -> Bool {
        let alert = make(version: version, notes: notes)
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func make(version: String, notes: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Showready \(version) is available"
        alert.informativeText = "Here's everything that's changed since your version."
        alert.accessoryView = ReleaseNotesView.make(markdown: notes)
        alert.addButton(withTitle: "Update and Restart")
        alert.addButton(withTitle: "Later")
        return alert
    }
}

/// A small window that says what the updater is doing. Silent seconds during
/// an update read as a hang, and a hang during an update is the one thing
/// that makes people force-quit — which is the one thing that would break it.
@MainActor
final class UpdateProgressWindow {
    private let window: NSWindow
    private let label = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()

    init(version: String) {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 96))

        let title = NSTextField(labelWithString: "Updating Showready to \(version)")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.frame = NSRect(x: 20, y: 62, width: 340, height: 18)

        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 20, y: 42, width: 340, height: 16)

        bar.style = .bar
        bar.isIndeterminate = true
        bar.minValue = 0
        bar.maxValue = 1
        bar.frame = NSRect(x: 20, y: 18, width: 340, height: 20)
        bar.startAnimation(nil)

        content.addSubview(title)
        content.addSubview(label)
        content.addSubview(bar)

        window = NSWindow(
            contentRect: content.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = content
        window.title = "Showready"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()
    }

    func show(_ progress: UpdateProgress) {
        label.stringValue = progress.phase
        if let fraction = progress.fraction {
            bar.isIndeterminate = false
            bar.doubleValue = fraction
        } else {
            bar.isIndeterminate = true
            bar.startAnimation(nil)
        }
        if !window.isVisible { window.orderFrontRegardless() }
    }

    func close() {
        window.orderOut(nil)
    }
}
#endif
