// Downstage Virtual Deck: a native window on web/apps/virtual-deck.html. No server: the page talks to Companion itself.
// A browser page can't ask the network who is there, so this finds Companion and Downstage Ones over Bonjour and tells the page.
// The window follows the Mac app standard (downstage-clients docs/mac-app-standard.md), built like Show Builder's.
import Cocoa
import WebKit

let ground = NSColor(srgbRed: 0x0B / 255.0, green: 0x0D / 255.0, blue: 0x10 / 255.0, alpha: 1)   // brand Ground: no white flash
let toolbarHeight: CGFloat = 52                     // the page's toolbar is the window's title bar

// The page draws the title bar, so the web view moves the window: a press on the toolbar's empty space drags it,
// a double-click zooms or minimizes as System Settings says. The page reports where its controls are.
final class DragWebView: WKWebView {
    var barHeight: CGFloat = toolbarHeight          // in the page's own pixels
    var controls: [NSRect] = []                     // the toolbar's buttons and fields, top-left origin, page pixels
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let z = max(pageZoom, 0.1)
        let x = p.x / z, y = (isFlipped ? p.y : bounds.height - p.y) / z
        if let w = window, y < barHeight, !controls.contains(where: { $0.contains(NSPoint(x: x, y: y)) }) {
            if e.clickCount == 2 {
                let act = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
                if act == "Minimize" { w.performMiniaturize(nil) } else if act != "None" { w.performZoom(nil) }
            } else {
                w.performDrag(with: e)
            }
            return
        }
        super.mouseDown(with: e)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, NSMenuItemValidation,
                         WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    var web: DragWebView!
    var activity: NSObjectProtocol?
    let finder = OneFinder()
    let updater = Updater()
    var ones = "[]"
    var companions = "[]"
    var state: [String: Any] = [:]        // what the page last said: its shows, the open one, the lock, snapping, decks
    let showsMenu = NSMenu(title: "Open Show")
    var asking: (id: Int, alert: NSAlert)?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // App Nap would stall the page's pings and Companion drops a quiet surface after 5 s (Companion NOTES.md)
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                         reason: "A surface stays connected to Companion")
        buildMenu()
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "finder")   // its presence tells the page a finder is here
        config.userContentController.add(updater, name: "updates")
        config.userContentController.add(self, name: "pagearrows")
        config.userContentController.add(self, name: "menu")     // and this one that the window and menu bar carry the show
        web = DragWebView(frame: .zero, configuration: config)
        updater.web = web
        web.uiDelegate = self
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Untitled show"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        if #available(macOS 11.0, *) { window.titlebarSeparatorStyle = .none }
        window.tabbingMode = .disallowed
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 320, height: 260)
        window.backgroundColor = ground
        window.contentView = web
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("DownstageVirtualDeck")
        window.collectionBehavior = [.fullScreenPrimary]
        placeLights()
        window.makeKeyAndOrderFront(nil)
        let root = Bundle.main.resourceURL!.appendingPathComponent("web")
        web.loadFileURL(root.appendingPathComponent("apps/virtual-deck.html"), allowingReadAccessTo: root)
        finder.changed = { [weak self] list in
            guard let self = self, let json = try? JSONSerialization.data(withJSONObject: list) else { return }
            self.ones = String(decoding: json, as: UTF8.self)
            self.tellPage()
        }
        finder.findCompanions = true
        finder.companionsChanged = { [weak self] list in
            guard let self = self, let json = try? JSONSerialization.data(withJSONObject: list) else { return }
            self.companions = String(decoding: json, as: UTF8.self)
            self.tellPage()
        }
        finder.start()
    }

    // the traffic lights sit in the middle of the page's 52 pt toolbar, not in a 28 pt strip above it
    func placeLights() {
        guard let close = window.standardWindowButton(.closeButton), let bar = close.superview?.superview,
              !window.styleMask.contains(.fullScreen) else { return }
        var f = bar.frame; f.size.height = toolbarHeight; f.origin.y = window.frame.height - toolbarHeight; bar.frame = f
        for (i, t) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let b = window.standardWindowButton(t) else { continue }
            b.setFrameOrigin(NSPoint(x: 20 + CGFloat(i) * 20, y: (toolbarHeight - b.frame.height) / 2))
        }
    }
    func windowDidResize(_ n: Notification) { placeLights() }
    func windowDidEndLiveResize(_ n: Notification) { placeLights() }
    func windowWillEnterFullScreen(_ n: Notification) { web.evaluateJavaScript("document.body.classList.add('macfs')") }
    func windowDidExitFullScreen(_ n: Notification) { web.evaluateJavaScript("document.body.classList.remove('macfs')"); placeLights() }

    func tellPage() {
        #if UPDATE_TEST
        if ProcessInfo.processInfo.environment["DOWNSTAGE_TEST_LOG"] != nil { print(ones); fflush(stdout) }
        #endif
        web.evaluateJavaScript("window.onesFound && window.onesFound(\(ones)); window.companionsFound && window.companionsFound(\(companions))", completionHandler: nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { tellPage() }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "pagearrows", let m = message.body as? [String: String], let host = m["host"], let surface = m["surface"] { allowPageArrows(host: host, surface: surface) }
        guard message.name == "menu", let b = message.body as? [String: Any], let action = b["action"] as? String else { return }
        switch action {
        case "title":
            // the page shows the name in its toolbar; the title is for the Window menu and Mission Control, the dot is the close button's
            let t = (b["title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            window.title = t.isEmpty ? "Untitled show" : t
            window.isDocumentEdited = b["edited"] as? Bool ?? false
            placeLights()
        case "dragzone":
            web.barHeight = CGFloat(b["height"] as? Double ?? Double(toolbarHeight))
            web.controls = (b["rects"] as? [[Double]] ?? []).filter { $0.count == 4 }.map { NSRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
        case "state":
            for (k, v) in b where k != "action" { state[k] = v }
        case "ask": ask(b)
        case "askClose":
            if let a = asking, a.id == b["id"] as? Int { asking = nil; window.endSheet(a.alert.window, returnCode: .abort) }
        default: break
        }
    }

    // The page's questions (save first, name a show, delete it, where Companion is) drop down from the window as sheets.
    // The answer goes back by its id, so a question the page has since withdrawn is never answered twice
    func ask(_ b: [String: Any]) {
        guard let id = b["id"] as? Int else { return }
        let a = NSAlert()
        a.messageText = b["title"] as? String ?? ""
        a.informativeText = b["text"] as? String ?? ""
        let go = a.addButton(withTitle: b["go"] as? String ?? "OK")
        if #available(macOS 11.0, *), b["danger"] as? Bool == true { go.hasDestructiveAction = true }
        if (b["go"] as? String) != "OK" || (b["alt"] as? String ?? "") != "" { a.addButton(withTitle: "Cancel") }
        if let alt = b["alt"] as? String, !alt.isEmpty { a.addButton(withTitle: alt) }
        var field: NSTextField?
        if let name = b["name"] as? String {
            let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            f.stringValue = name
            f.placeholderString = b["placeholder"] as? String
            a.accessoryView = f
            field = f
        }
        if let w = window.attachedSheet { window.endSheet(w, returnCode: .abort) }
        asking = (id, a)
        a.beginSheetModal(for: window) { [weak self] r in
            guard let self = self, r != .abort, self.asking?.id == id else { return }
            self.asking = nil
            let how = r == .alertFirstButtonReturn ? "go" : r == .alertThirdButtonReturn ? "alt" : "cancel"
            let value = field?.stringValue ?? ""
            guard let d = try? JSONSerialization.data(withJSONObject: [how, value]), let args = String(data: d, encoding: .utf8) else { return }
            self.web.evaluateJavaScript("window.vdAnswer && window.vdAnswer(\(id), ...\(args))")
        }
        if let f = field { a.window.initialFirstResponder = f; a.window.makeFirstResponder(f); f.selectText(nil) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    // links such as Surfaces open in the browser
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    // ---- menus: each item asks the page to do what its own controls do
    func page(_ cmd: String, _ arg: String = "") {
        guard let d = try? JSONSerialization.data(withJSONObject: [cmd, arg]), let args = String(data: d, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.vdMenu && window.vdMenu(...\(args))")
    }
    @objc func newShow() { page("new") }
    @objc func saveShow() { page("save") }
    @objc func saveAs() { page("saveas") }
    @objc func renameShow() { page("rename") }
    @objc func deleteShow() { page("delete") }
    @objc func openShow(_ s: NSMenuItem) { page("open", s.representedObject as? String ?? "") }
    @objc func addDeck() { page("add") }
    @objc func removeDeck() { page("remove") }
    @objc func arrange() { page("arrange") }
    @objc func lock() { page("lock") }
    @objc func snap() { page("snap") }
    @objc func connection() { page("conn") }
    @objc func surfaces() { page("surfaces") }
    @objc func zoomIn() { web.pageZoom = min(2, (web.pageZoom * 10 + 1).rounded() / 10) }
    @objc func zoomOut() { web.pageZoom = max(0.6, (web.pageZoom * 10 - 1).rounded() / 10) }
    @objc func zoomReset() { web.pageZoom = 1 }
    @objc func link(_ s: NSMenuItem) { if let u = s.representedObject as? URL { NSWorkspace.shared.open(u) } }
    @objc func checkForUpdates() {
        web.evaluateJavaScript("window.updAsked = true") { _, _ in self.updater.check() }
    }
    @objc func about() {
        let p = NSMutableParagraphStyle(); p.alignment = .center
        let credits = NSAttributedString(string: "Built by Rob Spradling, Downstage Systems LLC.\nA Stream Deck on screen for Bitfocus Companion, free open-source software (MIT).",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: p])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let hasShow = !(state["now"] as? String ?? "").isEmpty
        switch item.action {
        case #selector(renameShow), #selector(deleteShow): return hasShow
        case #selector(removeDeck): return (state["decks"] as? Int ?? 1) > 1
        case #selector(addDeck): return (state["decks"] as? Int ?? 1) < 8
        case #selector(arrange): return state["canArrange"] as? Bool ?? false
        case #selector(lock): item.state = (state["locked"] as? Bool ?? false) ? .on : .off; return true
        case #selector(snap): item.state = (state["snap"] as? Bool ?? true) ? .on : .off; return true
        case #selector(surfaces): return state["host"] as? Bool ?? false
        case #selector(openShow(_:)): item.state = (item.representedObject as? String) == (state["now"] as? String) ? .on : .off; return true
        case #selector(zoomReset): return web.pageZoom != 1
        default: return true
        }
    }

    // Open Show: the shows saved in this app, by name. They live in the app, not as files, so there's no Open Recent
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === showsMenu else { return }
        menu.removeAllItems()
        let names = state["shows"] as? [String] ?? []
        for n in names {
            let i = NSMenuItem(title: n, action: #selector(openShow(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = n; menu.addItem(i)
        }
        if names.isEmpty { let i = NSMenuItem(title: "No Saved Shows", action: nil, keyEquivalent: ""); i.isEnabled = false; menu.addItem(i) }
    }

    func buildMenu() {
        func item(_ title: String, _ sel: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: key); i.target = self; i.keyEquivalentModifierMask = mods; return i
        }
        func linkItem(_ title: String, _ url: String) -> NSMenuItem {
            let i = item(title, #selector(link(_:))); i.representedObject = URL(string: url); return i
        }
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(item("About Downstage Virtual Deck", #selector(about)))
        appMenu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Downstage Virtual Deck", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]; appMenu.addItem(others)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Downstage Virtual Deck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let file = NSMenu(title: "File")
        file.addItem(item("New Show", #selector(newShow), "n"))
        let open = NSMenuItem(title: "Open Show", action: nil, keyEquivalent: ""); showsMenu.delegate = self
        open.submenu = showsMenu; file.addItem(open)
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(item("Save", #selector(saveShow), "s"))
        file.addItem(item("Save As…", #selector(saveAs), "s", [.command, .shift]))
        file.addItem(item("Rename Show…", #selector(renameShow)))
        file.addItem(.separator())
        file.addItem(item("Delete Show…", #selector(deleteShow)))
        fileItem.submenu = file

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(item("Add Deck", #selector(addDeck)))
        edit.addItem(item("Remove Selected Deck", #selector(removeDeck)))
        edit.addItem(item("Arrange Decks", #selector(arrange)))
        editItem.submenu = edit

        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "View")
        view.addItem(item("Lock Layout", #selector(lock), "l"))
        view.addItem(item("Snapping", #selector(snap)))
        view.addItem(.separator())
        view.addItem(item("Zoom In", #selector(zoomIn), "+"))
        view.addItem(item("Zoom Out", #selector(zoomOut), "-"))
        view.addItem(item("Actual Size", #selector(zoomReset), "0"))
        view.addItem(.separator())
        let fs = NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]; view.addItem(fs)
        viewItem.submenu = view

        let compItem = NSMenuItem(); main.addItem(compItem)
        let comp = NSMenu(title: "Companion")
        comp.addItem(item("Connection…", #selector(connection), "k"))
        comp.addItem(item("Open Surfaces in Companion", #selector(surfaces)))
        compItem.submenu = comp

        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        winItem.submenu = win
        NSApp.windowsMenu = win

        let helpItem = NSMenuItem(); main.addItem(helpItem)
        let help = NSMenu(title: "Help")
        help.addItem(linkItem("Virtual Deck Help", "https://downstage.systems/support/apps/virtual-deck/"))
        help.addItem(.separator())
        help.addItem(linkItem("Suggest a Feature…", "https://github.com/Downstage-Systems/virtual-deck/discussions/new?category=ideas&body=What%20would%20you%20like%20it%20to%20do%3F%0A%0AWhat%20are%20you%20running%3F%20(Stream%20Deck%20model%2C%20Companion%20version)%0A"))
        help.addItem(linkItem("See Ideas", "https://github.com/Downstage-Systems/virtual-deck/discussions/categories/ideas"))
        help.addItem(linkItem("Email Us", "mailto:hello@downstage.systems?subject=Virtual%20Deck%20idea"))
        help.addItem(.separator())
        help.addItem(linkItem("downstage.systems", "https://downstage.systems/"))
        helpItem.submenu = help
        NSApp.helpMenu = help
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
