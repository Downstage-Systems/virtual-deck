// Downstage Virtual Deck: a native window on web/apps/virtual-deck.html. No server: the page talks to Companion itself.
// A browser page can't ask the network who is there, so this finds Downstage Ones over Bonjour and tells the page.
import Cocoa
import WebKit

final class OneFinder: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    let browser = NetServiceBrowser()
    var services: [NetService] = []
    var changed: ([[String: String]]) -> Void = { _ in }

    func start() {
        browser.delegate = self
        browser.searchForServices(ofType: "_downstage._tcp.", inDomain: "local.")
    }
    func netServiceBrowser(_ b: NetServiceBrowser, didFind s: NetService, moreComing: Bool) {
        services.append(s)
        s.delegate = self
        s.resolve(withTimeout: 5)
    }
    func netServiceBrowser(_ b: NetServiceBrowser, didRemove s: NetService, moreComing: Bool) {
        services.removeAll { $0 == s }
        report()
    }
    func netServiceDidResolveAddress(_ s: NetService) { report() }

    func report() {
        var out: [[String: String]] = []
        for s in services {
            guard let host = ipv4(s), let data = s.txtRecordData() else { continue }
            let txt = NetService.dictionary(fromTXTRecord: data).mapValues { String(decoding: $0, as: UTF8.self) }
            // only a One has a Companion. A One on v1.7.0 or older advertises its serial but no kind
            let serial = txt["serial"] ?? ""
            guard txt["kind"]?.lowercased() == "one" || serial.hasPrefix("DS1-") else { continue }
            out.append(["id": serial.isEmpty ? s.name : serial, "name": txt["name"] ?? s.name, "host": host])
        }
        changed(out)
    }
    func ipv4(_ s: NetService) -> String? {
        for a in s.addresses ?? [] {
            let found: String? = a.withUnsafeBytes { raw in
                guard let sa = raw.baseAddress?.assumingMemoryBound(to: sockaddr.self), sa.pointee.sa_family == UInt8(AF_INET) else { return nil }
                var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                guard getnameinfo(sa, socklen_t(a.count), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
                return String(cString: buf)
            }
            if let found = found, !found.hasPrefix("169.254.") { return found }
        }
        return nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    var web: WKWebView!
    var activity: NSObjectProtocol?
    let finder = OneFinder()
    var ones = "[]"

    func applicationDidFinishLaunching(_ note: Notification) {
        // App Nap would stall the page's pings and Companion drops a quiet surface after 5 s (Companion NOTES.md)
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                         reason: "A surface stays connected to Companion")
        buildMenu()
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "finder")   // its presence tells the page a finder is here
        web = WKWebView(frame: .zero, configuration: config)
        web.uiDelegate = self
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Downstage Virtual Deck"
        window.minSize = NSSize(width: 320, height: 260)
        window.backgroundColor = NSColor(red: 0x0B / 255.0, green: 0x0D / 255.0, blue: 0x10 / 255.0, alpha: 1)
        window.contentView = web
        window.center()
        window.setFrameAutosaveName("DownstageVirtualDeck")
        window.collectionBehavior = [.fullScreenPrimary]
        window.makeKeyAndOrderFront(nil)
        let root = Bundle.main.resourceURL!.appendingPathComponent("web")
        web.loadFileURL(root.appendingPathComponent("apps/virtual-deck.html"), allowingReadAccessTo: root)
        finder.changed = { [weak self] list in
            guard let self = self, let json = try? JSONSerialization.data(withJSONObject: list) else { return }
            self.ones = String(decoding: json, as: UTF8.self)
            self.tellPage()
        }
        finder.start()
    }

    func tellPage() { web.evaluateJavaScript("window.onesFound && window.onesFound(\(ones))", completionHandler: nil) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { tellPage() }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {}

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    // links such as Surfaces open in the browser
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Downstage Virtual Deck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "View")
        let full = view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        full.keyEquivalentModifierMask = [.command, .control]
        viewItem.submenu = view
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
