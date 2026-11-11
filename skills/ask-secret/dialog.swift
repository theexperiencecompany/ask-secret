// Native secret prompt for ask-secret. Focused field, Return = Save, Esc = Cancel, "Show" reveals the value.
// Usage: ask-secret-dialog --title T --why W [--agent A] [--folder F] [--where URL] [--footer N]
// Prints the value to stdout (no newline); exit 1 on cancel/timeout. ASK_SECRET_SELFTEST=1 checks focus and exits.
import AppKit

var opts: [String: String] = [:]
var argv = Array(CommandLine.arguments.dropFirst())
while argv.count >= 2, argv[0].hasPrefix("--") { opts[String(argv[0].dropFirst(2))] = argv[1]; argv.removeFirst(2) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let width: CGFloat = 380

func label(_ text: String, secondary: Bool = false, size: CGFloat = NSFont.systemFontSize, weight: NSFont.Weight = .regular) -> NSTextField {
    let l = NSTextField(wrappingLabelWithString: text)
    l.font = .systemFont(ofSize: size, weight: weight)
    l.textColor = secondary ? .secondaryLabelColor : .labelColor
    l.isSelectable = true
    return l
}

func row(_ name: String, _ value: NSView) -> [NSView] {
    let n = label(name, secondary: true, size: NSFont.smallSystemFontSize, weight: .medium)
    n.alignment = .right
    return [n, value]
}

var rows: [[NSView]] = []
if let agent = opts["agent"] { rows.append(row("Asked by", label(agent, size: NSFont.smallSystemFontSize))) }
if let folder = opts["folder"] {
    let f = label(folder, size: NSFont.smallSystemFontSize)
    f.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    f.lineBreakMode = .byTruncatingMiddle
    f.maximumNumberOfLines = 1
    rows.append(row("Folder", f))
}
if let whereURL = opts["where"], let url = URL(string: whereURL) {
    let link = NSTextField(labelWithAttributedString: NSAttributedString(string: whereURL, attributes: [
        .link: url, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
    ]))
    link.isSelectable = true
    link.allowsEditingTextAttributes = true
    link.lineBreakMode = .byTruncatingMiddle
    rows.append(row("Get it at", link))
}

let grid = NSGridView(views: rows)
grid.rowSpacing = 4
grid.columnSpacing = 10
if grid.numberOfColumns > 0 {
    grid.column(at: 0).width = 62
    grid.column(at: 1).width = width - 72
}

let secure = NSSecureTextField()
let plain = NSTextField()
for f in [secure, plain] {
    f.placeholderString = "Paste here"
    f.translatesAutoresizingMaskIntoConstraints = false
    f.widthAnchor.constraint(equalToConstant: width).isActive = true
}
plain.isHidden = true

final class Toggler: NSObject {
    @objc func flip(_ b: NSButton) {
        let show = b.state == .on
        if show { plain.stringValue = secure.stringValue } else { secure.stringValue = plain.stringValue }
        plain.isHidden = !show
        secure.isHidden = show
        b.window?.makeFirstResponder(show ? plain : secure)
    }
}
let toggler = Toggler()
let toggle = NSButton(checkboxWithTitle: "Show", target: toggler, action: #selector(Toggler.flip(_:)))
toggle.controlSize = .small
toggle.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

let footer = label(opts["footer"] ?? "", secondary: true, size: NSFont.smallSystemFontSize)
let bottom = NSStackView(views: [toggle, NSView(), footer])
bottom.orientation = .horizontal

let stack = NSStackView(views: (rows.isEmpty ? [] : [grid]) + [secure, plain, bottom])
stack.orientation = .vertical
stack.alignment = .leading
stack.spacing = 8
if !rows.isEmpty { stack.setCustomSpacing(14, after: grid) }
bottom.widthAnchor.constraint(equalToConstant: width).isActive = true
stack.frame = NSRect(origin: .zero, size: stack.fittingSize)

let alert = NSAlert()
alert.messageText = opts["title"] ?? "Secret for your agent"
alert.informativeText = opts["why"] ?? ""
// Without an icon NSAlert shows this CLI's generic (Finder-like) app icon.
alert.icon = NSImage(systemSymbolName: "key.fill", accessibilityDescription: "Secret")?
    .withSymbolConfiguration(.init(pointSize: 40, weight: .regular).applying(.init(hierarchicalColor: .systemBlue)))
alert.accessoryView = stack
alert.addButton(withTitle: "Save")
alert.addButton(withTitle: "Cancel")
alert.layout()
alert.window.level = .floating

// Focus has to be taken once the modal loop is running; before that NSAlert resets it.
DispatchQueue.main.async {
    app.activate(ignoringOtherApps: true)
    alert.window.makeKeyAndOrderFront(nil)
    alert.window.makeFirstResponder(secure)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 600) { app.abortModal() }
if ProcessInfo.processInfo.environment["ASK_SECRET_SELFTEST"] != nil {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        let editor = alert.window.firstResponder as? NSTextView
        FileHandle.standardError.write("key=\(alert.window.isKeyWindow) active=\(app.isActive) editingSecure=\(editor?.delegate === secure) default=\(alert.buttons[0].keyEquivalent == "\r")\n".data(using: .utf8)!)
        app.abortModal()
    }
}
let response = alert.runModal()
let value = toggle.state == .on ? plain.stringValue : secure.stringValue
guard response == .alertFirstButtonReturn, !value.isEmpty else { exit(1) }
print(value, terminator: "")
