// ask-secret helper: the prompt window, Keychain storage and the Touch ID gate.
// Secrets are stored by this binary in the login Keychain, so macOS only lets this binary read them silently;
// any other process (e.g. `security`) gets a visible macOS Keychain prompt.
//
//   helper prompt --title T --why W [--agent A] [--folder F] [--where URL]
//                 [--store NAME [--remember once|1h|1d|30d|forever] [--touchid on|off]]
//   helper read NAME --why W [--agent A] [--folder F]
//   helper has NAME | list | delete NAME | lock
//
// Exit codes: 0 ok, 1 cancelled or Touch ID denied, 2 usage, 3 not stored (or expired).
// ASK_SECRET_SELFTEST=1 makes `prompt` report its focus state and close.
import AppKit
import LocalAuthentication
import Security

let servicePrefix = "agent/"
let approvalWindow: TimeInterval = 15 * 60

struct Meta: Codable {
    var expires: Double?
    var touchID: Bool
    var approvedUntil: Double?
}

func fail(_ code: Int32, _ message: String) -> Never {
    if !message.isEmpty { FileHandle.standardError.write("ask-secret: \(message)\n".data(using: .utf8)!) }
    exit(code)
}

// MARK: - Arguments

var args = Array(CommandLine.arguments.dropFirst())
let command = args.isEmpty ? "" : args.removeFirst()
var positional: [String] = []
var opts: [String: String] = [:]
while !args.isEmpty {
    let a = args.removeFirst()
    if a.hasPrefix("--"), !args.isEmpty { opts[String(a.dropFirst(2))] = args.removeFirst() } else { positional.append(a) }
}

// MARK: - Keychain

func baseQuery(_ name: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servicePrefix + name]
}

func loadMeta(_ name: String) -> Meta? {
    var q = baseQuery(name)
    q[kSecReturnAttributes as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var out: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let attrs = out as? [String: Any] else { return nil }
    if let data = attrs[kSecAttrGeneric as String] as? Data, let meta = try? JSONDecoder().decode(Meta.self, from: data) { return meta }
    return Meta(expires: nil, touchID: false, approvedUntil: nil)
}

func saveMeta(_ name: String, _ meta: Meta) {
    let update = [kSecAttrGeneric as String: try! JSONEncoder().encode(meta)]
    SecItemUpdate(baseQuery(name) as CFDictionary, update as CFDictionary)
}

func delete(_ name: String) { SecItemDelete(baseQuery(name) as CFDictionary) }

/// The stored meta, or nil when missing; an expired secret is deleted and treated as missing.
func liveMeta(_ name: String) -> Meta? {
    guard let meta = loadMeta(name) else { return nil }
    if let expires = meta.expires, expires < Date().timeIntervalSince1970 { delete(name); return nil }
    return meta
}

func store(_ name: String, _ value: String, _ meta: Meta) {
    delete(name)
    let item: [String: Any] = baseQuery(name).merging([
        kSecAttrAccount as String: NSUserName(),
        kSecAttrLabel as String: servicePrefix + name,
        kSecAttrGeneric as String: try! JSONEncoder().encode(meta),
        kSecValueData as String: value.data(using: .utf8)!,
    ]) { $1 }
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else { fail(2, "couldn't save to the Keychain (\(status))") }
}

func readValue(_ name: String) -> String {
    var q = baseQuery(name)
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var out: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &out)
    guard status == errSecSuccess, let data = out as? Data, let value = String(data: data, encoding: .utf8) else {
        fail(1, "couldn't read \(name) from the Keychain (\(status))")
    }
    return value
}

func durationSeconds(_ choice: String) -> Double? {
    switch choice {
    case "1h": return 3600
    case "1d": return 86400
    case "30d": return 30 * 86400
    default: return nil
    }
}

func allNames() -> [String] {
    let q: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecReturnAttributes as String: true,
        kSecMatchLimit as String: kSecMatchLimitAll,
    ]
    var out: CFTypeRef?
    SecItemCopyMatching(q as CFDictionary, &out)
    let names = ((out as? [[String: Any]]) ?? [])
        .compactMap { $0[kSecAttrService as String] as? String }
        .filter { $0.hasPrefix(servicePrefix) }
        .map { String($0.dropFirst(servicePrefix.count)) }
    return Set(names).sorted()
}

// MARK: - Touch ID

func approveWithTouchID(_ reason: String) -> Bool {
    let context = LAContext()
    var ok = false
    let done = DispatchSemaphore(value: 0)
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
        ok = success
        done.signal()
    }
    done.wait()
    return ok
}

// MARK: - Prompt window

final class Prompt: NSObject {
    let secure = NSSecureTextField()
    let plain = NSTextField()
    let show = NSButton(checkboxWithTitle: "Show", target: nil, action: nil)
    let remember = NSPopUpButton()
    let touchID = NSButton(checkboxWithTitle: "Ask for Touch ID each time an agent uses it", target: nil, action: nil)
    static let rememberChoices = [("once", "Just this once"), ("1h", "1 hour"), ("1d", "1 day"), ("30d", "30 days"), ("forever", "Until I remove it")]

    var value: String { show.state == .on ? plain.stringValue : secure.stringValue }

    @objc func flip(_ b: NSButton) {
        let visible = b.state == .on
        if visible { plain.stringValue = secure.stringValue } else { secure.stringValue = plain.stringValue }
        plain.isHidden = !visible
        secure.isHidden = visible
        b.window?.makeFirstResponder(visible ? plain : secure)
    }

    @objc func rememberChanged(_ p: NSPopUpButton) {
        touchID.isEnabled = p.indexOfSelectedItem != 0
    }
}

func label(_ text: String, secondary: Bool = false, size: CGFloat = NSFont.systemFontSize, weight: NSFont.Weight = .regular) -> NSTextField {
    let l = NSTextField(wrappingLabelWithString: text)
    l.font = .systemFont(ofSize: size, weight: weight)
    l.textColor = secondary ? .secondaryLabelColor : .labelColor
    l.isSelectable = true
    return l
}

/// Accessory apps have no menu bar, and without an Edit menu Cmd-V/C/X/A/Z never reach text fields.
func installEditMenu(_ app: NSApplication) {
    let main = NSMenu()
    let editItem = NSMenuItem()
    main.addItem(editItem)
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit
    app.mainMenu = main
}

func runPrompt() -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    installEditMenu(app)
    let width: CGFloat = 380
    let storing = opts["store"] != nil
    let p = Prompt()

    var rows: [[NSView]] = []
    func row(_ name: String, _ value: NSView) {
        let n = label(name, secondary: true, size: NSFont.smallSystemFontSize, weight: .medium)
        n.alignment = .right
        rows.append([n, value])
    }
    if let agent = opts["agent"] { row("Asked by", label(agent, size: NSFont.smallSystemFontSize)) }
    if let folder = opts["folder"] {
        let f = label(folder, size: NSFont.smallSystemFontSize)
        f.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        f.lineBreakMode = .byTruncatingMiddle
        f.maximumNumberOfLines = 1
        row("Folder", f)
    }
    if let whereURL = opts["where"], let url = URL(string: whereURL) {
        let link = NSTextField(labelWithAttributedString: NSAttributedString(string: whereURL, attributes: [
            .link: url, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        ]))
        link.isSelectable = true
        link.allowsEditingTextAttributes = true
        link.lineBreakMode = .byTruncatingMiddle
        row("Get it at", link)
    }
    let grid = NSGridView(views: rows)
    grid.rowSpacing = 4
    grid.columnSpacing = 10
    if grid.numberOfColumns > 0 {
        grid.column(at: 0).width = 62
        grid.column(at: 1).width = width - 72
    }

    for f in [p.secure, p.plain] {
        f.placeholderString = "Paste here"
        f.translatesAutoresizingMaskIntoConstraints = false
        f.widthAnchor.constraint(equalToConstant: width).isActive = true
    }
    p.plain.isHidden = true
    for b in [p.show, p.touchID] {
        b.controlSize = .small
        b.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    }
    p.show.target = p
    p.show.action = #selector(Prompt.flip(_:))

    var bottomViews: [NSView] = [p.show, NSView()]
    var extra: [NSView] = []
    if storing {
        p.remember.controlSize = .small
        p.remember.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        p.remember.addItems(withTitles: Prompt.rememberChoices.map { $0.1 })
        let initial = Prompt.rememberChoices.firstIndex { $0.0 == (opts["remember"] ?? "forever") } ?? 4
        p.remember.selectItem(at: initial)
        p.remember.target = p
        p.remember.action = #selector(Prompt.rememberChanged(_:))
        p.touchID.state = opts["touchid"] == "on" ? .on : .off
        p.touchID.isEnabled = initial != 0
        bottomViews += [label("Remember", secondary: true, size: NSFont.smallSystemFontSize), p.remember]
        extra = [p.touchID]
    } else {
        bottomViews.append(label("Used once, never saved", secondary: true, size: NSFont.smallSystemFontSize))
    }
    let bottom = NSStackView(views: bottomViews)
    bottom.orientation = .horizontal
    bottom.widthAnchor.constraint(equalToConstant: width).isActive = true

    let stack = NSStackView(views: (rows.isEmpty ? [] : [grid]) + [p.secure, p.plain, bottom] + extra)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    if !rows.isEmpty { stack.setCustomSpacing(14, after: grid) }
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
        alert.window.makeFirstResponder(p.secure)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 600) { app.abortModal() }
    if ProcessInfo.processInfo.environment["ASK_SECRET_SELFTEST"] != nil {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let editor = alert.window.firstResponder as? NSTextView
            let pasteKey = app.mainMenu?.items.first?.submenu?.items.contains { $0.keyEquivalent == "v" } ?? false
            FileHandle.standardError.write("key=\(alert.window.isKeyWindow) active=\(app.isActive) editingSecure=\(editor?.delegate === p.secure) default=\(alert.buttons[0].keyEquivalent == "\r") paste=\(pasteKey)\n".data(using: .utf8)!)
            app.abortModal()
        }
    }

    let response = alert.runModal()
    let value = p.value
    guard response == .alertFirstButtonReturn, !value.isEmpty else { fail(1, "cancelled") }

    if let name = opts["store"] {
        let choice = Prompt.rememberChoices[p.remember.indexOfSelectedItem].0
        if choice != "once" {
            let expires = durationSeconds(choice).map { Date().timeIntervalSince1970 + $0 }
            // Typing the value counts as approving its use for the next few minutes.
            let meta = Meta(expires: expires, touchID: p.touchID.state == .on, approvedUntil: Date().timeIntervalSince1970 + approvalWindow)
            store(name, value, meta)
            FileHandle.standardError.write("ask-secret: saved \(servicePrefix)\(name)\n".data(using: .utf8)!)
        }
    }
    print(value, terminator: "")
    exit(0)
}

// MARK: - Commands

func requireName() -> String {
    guard let name = positional.first, !name.isEmpty else { fail(2, "missing NAME") }
    return name
}

switch command {
case "prompt":
    runPrompt()

case "read":
    let name = requireName()
    guard var meta = liveMeta(name) else { exit(3) }
    let now = Date().timeIntervalSince1970
    if meta.touchID, (meta.approvedUntil ?? 0) < now {
        let who = opts["agent"] ?? "An agent"
        let why = opts["why"].map { ": \($0)" } ?? ""
        guard approveWithTouchID("let \(who) use “\(name)”\(why)") else { fail(1, "Touch ID was cancelled") }
        meta.approvedUntil = now + approvalWindow
        saveMeta(name, meta)
    }
    print(readValue(name), terminator: "")

case "has":
    exit(liveMeta(requireName()) == nil ? 1 : 0)

case "delete":
    let name = requireName()
    guard loadMeta(name) != nil else { fail(1, "\(name) isn't saved") }
    delete(name)

case "lock":
    for name in allNames() {
        guard var meta = loadMeta(name), meta.approvedUntil != nil else { continue }
        meta.approvedUntil = nil
        saveMeta(name, meta)
    }

case "list":
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    for name in allNames() {
        guard let meta = liveMeta(name) else { continue }
        let until = meta.expires.map { "until " + formatter.string(from: Date(timeIntervalSince1970: $0)) } ?? "until removed"
        print("\(name)\t\(until)\(meta.touchID ? "\tTouch ID" : "")")
    }

default:
    fail(2, "unknown helper command '\(command)'")
}
