// Downstage Virtual Deck for iPhone and iPad: a Stream Deck on screen. The page talks to Companion itself; this finds Ones and keeps the screen awake.
import UIKit
import WebKit

func makeShell() -> ShellController { DeckController() }

final class DeckController: ShellController {
    let finder = OneFinder()
    var ones = "[]"
    let tap = UIImpactFeedbackGenerator(style: .light)

    override var pageURL: URL {
        let page = pageRoot.appendingPathComponent("apps/virtual-deck.html")
        #if DEBUG
        // a test points the deck at a stub, so it can't join a real Companion
        if let h = ProcessInfo.processInfo.environment["DOWNSTAGE_TEST_HOST"], var c = URLComponents(url: page, resolvingAgainstBaseURL: false) {
            c.queryItems = [URLQueryItem(name: "host", value: h)]
            return c.url ?? page
        }
        #endif
        return page
    }
    // The header runs to the screen's edges and holds its controls clear of the notch. Sideways on a phone it stays
    // one row to give the deck the height
    override var appStyle: String { """
      header { padding: calc(10px + var(--sa-t)) calc(14px + var(--sa-r)) 10px calc(14px + var(--sa-l) + var(--win-l)) !important; }
      #say, #upd { padding-left: calc(14px + var(--sa-l)) !important; padding-right: calc(14px + var(--sa-r)) !important; }
      #stage { padding: 12px calc(10px + var(--sa-r)) calc(8px + var(--sa-b)) calc(10px + var(--sa-l)) !important; }
      :root { --bar-h: calc(64px + var(--sa-t)) !important; }
      #lock { width: 44px !important; padding: 0 !important; }
      input, select, button, a.btn { height: 44px; }
      #ctx button { height: auto; min-height: 44px; }
      @media (max-width: 760px) {
        .grp { display: contents !important; }
        .rule { display: none !important; }
      }
      @media (max-width: 500px) {
        header { gap: 8px !important; }
        header h1 { display: none; }
        header .sp { display: none; }
        #hostBox { font-size: 0; gap: 0; }
        input.addr { width: 130px !important; }
        #found.on { max-width: 210px; }
        header button, a.btn { padding: 4px 8px !important; font-size: 14px !important; }
        label:has(#model) { font-size: 0; gap: 0; }
        input.addr { flex: 1 1 110px; min-width: 0; }
      }
      @media (orientation: landscape) and (max-height: 500px) {
        :root { --bar-h: 56px !important; }
        .grp { display: contents !important; }
        .rule { display: none !important; }
        header { flex-wrap: nowrap !important; gap: 8px !important; padding-top: 6px !important; padding-bottom: 6px !important; overflow-x: auto; }
        header h1, #deckName { display: none; }
        #hostBox { font-size: 0; gap: 0; }
        #custom label { font-size: 12px !important; gap: 3px !important; }
        #model { max-width: 150px; min-width: 96px; flex: 0 1 150px; }
        .sp { flex: 0 0 0; }
        #found.on { max-width: 200px; min-width: 96px; flex: 0 1 200px; }
        #show { max-width: 110px; }
        #saveShow { display: none; }
        input.addr { width: 104px !important; }
        a.btn, header button { white-space: nowrap; flex: none; padding: 4px 7px !important; font-size: 14px !important; }
        input, select, button, a.btn { height: 40px; min-height: 40px !important; }
        header:has(#custom.on) { flex-wrap: wrap !important; overflow-x: visible; }
      }
    """ }
    override func configure(_ c: WKUserContentController) {
        c.add(self, name: "finder")   // its presence tells the page a finder is here
        c.add(self, name: "press")
        // the version sits at the foot of the menu. Added here because the page is shared with the Mac app and the One
        c.addUserScript(WKUserScript(source: "(function () { const open = openMenu; openMenu = function (x, y, d) { open(x, y, d); const m = document.getElementById('ctx'), v = document.createElement('div'); v.className = 'ctxh'; v.textContent = '\(versionText)'; m.appendChild(document.createElement('hr')); m.appendChild(v); m.style.top = Math.max(4, Math.min(parseFloat(m.style.top), innerHeight - m.offsetHeight - 4)) + 'px'; }; })();",
                                     injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        c.addUserScript(WKUserScript(source: "document.addEventListener('pointerdown', e => { if (e.target.closest && e.target.closest('.deckgrid [data-k]')) window.webkit.messageHandlers.press.postMessage(1); }, true);",
                                     injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        UIApplication.shared.isIdleTimerDisabled = true   // a deck that sleeps isn't a deck
        finder.changed = { [weak self] list in
            guard let self = self, let json = try? JSONSerialization.data(withJSONObject: list) else { return }
            self.ones = String(decoding: json, as: UTF8.self)
            self.pageReady()
        }
        finder.start()
    }
    override func pageReady() { call("window.onesFound && window.onesFound(\(ones))") }
    // iOS stops the socket while the app is away and Companion drops the surface, so join again straight away
    override func cameForward() { call("connect()"); finder.report() }
    override func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "press" { tap.impactOccurred() }
        #if DEBUG
        if message.name == "testlog", let line = message.body as? String { testLine(line) }
        #endif
    }
}
