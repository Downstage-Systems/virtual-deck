// Downstage Virtual Deck for iPhone and iPad: a Stream Deck on screen. The page talks to Companion itself; this finds Ones and keeps the screen awake.
// The keys are the shared page. Everything around them is the app's own (iOS app standard, downstage-clients docs/ios-app-standard.md):
// the page hides its toolbar and tray when the "chrome" handler is here, tells the app its state, and takes commands through vdMenu.
import CoreText
import UIKit
import WebKit

func makeShell() -> ShellController { DeckController() }

let rajdhani: (CGFloat) -> UIFont = { size in
    UIFont(name: "Rajdhani-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
}

// The bar at the foot, upright: who the deck is joined to and which deck, the lock, and "..." for everything else.
// Sideways it hides, so the keys have the screen, and a tap beside the deck brings it back for a few seconds
final class DeckBar: UIView {
    let dot = UIView()
    let who = UIButton(type: .custom)
    let name = UILabel()
    let deck = UILabel()
    let lock = UIButton(type: .system)
    let more = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0x12 / 255.0, green: 0x16 / 255.0, blue: 0x1B / 255.0, alpha: 0.96)
        layer.cornerRadius = 26
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor(red: 0x23 / 255.0, green: 0x2A / 255.0, blue: 0x32 / 255.0, alpha: 1).cgColor
        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        name.font = rajdhani(19)
        name.textColor = UIColor(red: 0xE8 / 255.0, green: 0xEC / 255.0, blue: 0xEF / 255.0, alpha: 1)
        name.setContentHuggingPriority(.required, for: .horizontal)
        name.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        deck.font = .preferredFont(forTextStyle: .footnote)
        deck.adjustsFontForContentSizeCategory = true
        deck.textColor = UIColor(red: 0xA3 / 255.0, green: 0xAD / 255.0, blue: 0xB6 / 255.0, alpha: 1)
        deck.lineBreakMode = .byTruncatingTail
        let text = UIStackView(arrangedSubviews: [name, deck])
        text.spacing = 8
        text.alignment = .firstBaseline
        text.isUserInteractionEnabled = false
        let left = UIStackView(arrangedSubviews: [dot, text])
        left.spacing = 10
        left.alignment = .center
        left.isUserInteractionEnabled = false
        left.translatesAutoresizingMaskIntoConstraints = false
        who.addSubview(left)
        who.isAccessibilityElement = true
        for (b, symbol, label) in [(lock, "lock.open", "Lock layout"), (more, "ellipsis", "More")] {
            b.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)), for: .normal)
            b.tintColor = UIColor(red: 0xA3 / 255.0, green: 0xAD / 255.0, blue: 0xB6 / 255.0, alpha: 1)
            b.accessibilityLabel = label
        }
        let row = UIStackView(arrangedSubviews: [who, lock, more])
        row.spacing = 2
        row.alignment = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18), row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            left.leadingAnchor.constraint(equalTo: who.leadingAnchor), left.trailingAnchor.constraint(lessThanOrEqualTo: who.trailingAnchor),
            left.centerYAnchor.constraint(equalTo: who.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8), dot.heightAnchor.constraint(equalToConstant: 8),
            lock.widthAnchor.constraint(equalToConstant: 44), more.widthAnchor.constraint(equalToConstant: 44),
        ])
        show(live: false, word: "Finding Companion…", name: "", deck: "", locked: false)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(live: Bool, word: String, name n: String, deck d: String, locked: Bool) {
        dot.backgroundColor = live ? UIColor(red: 0x2F / 255.0, green: 0xD9 / 255.0, blue: 0x7B / 255.0, alpha: 1)
                                   : UIColor(red: 0xF7 / 255.0, green: 0xC0 / 255.0, blue: 0x66 / 255.0, alpha: 1)
        // joined: the Companion's name, in Rajdhani. Not yet: what it's doing, in the system face
        name.text = live ? n : word
        name.font = live ? rajdhani(19) : .preferredFont(forTextStyle: .subheadline)
        deck.text = d
        who.accessibilityLabel = (live ? "Joined to \(n)" : word) + (d.isEmpty ? "" : ", \(d)")
        who.accessibilityHint = "Companion and deck settings"
        lock.setImage(UIImage(systemName: locked ? "lock.fill" : "lock.open", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)), for: .normal)
        lock.tintColor = locked ? UIColor(red: 0x2F / 255.0, green: 0xD9 / 255.0, blue: 0x7B / 255.0, alpha: 1) : UIColor(red: 0xA3 / 255.0, green: 0xAD / 255.0, blue: 0xB6 / 255.0, alpha: 1)
        lock.accessibilityLabel = "Lock layout"
        lock.accessibilityValue = locked ? "On" : "Off"
    }
}

final class DeckController: ShellController {
    let finder = OneFinder()
    var ones = "[]"
    let tap = UIImpactFeedbackGenerator(style: .light)
    let bar = DeckBar()
    var upright = true
    var barTimer: Timer?
    static let barHeight: CGFloat = 52, barGap: CGFloat = 6

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
    override func configure(_ c: WKUserContentController) {
        c.add(self, name: "finder")   // its presence tells the page a finder is here
        c.add(self, name: "press")
        c.add(self, name: "pagearrows")
        c.add(self, name: "chrome")   // and this one that the app draws the bar and the sheet
        // the version sits at the foot of the menu. Added here because the page is shared with the Mac app and the One
        c.addUserScript(WKUserScript(source: "(function () { const open = openMenu; openMenu = function (x, y, d) { open(x, y, d); const m = document.getElementById('ctx'), v = document.createElement('div'); v.className = 'ctxh'; v.textContent = '\(versionText)'; m.appendChild(document.createElement('hr')); m.appendChild(v); m.style.top = Math.max(4, Math.min(parseFloat(m.style.top), innerHeight - m.offsetHeight - 4)) + 'px'; }; })();",
                                     injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        c.addUserScript(WKUserScript(source: "document.addEventListener('pointerdown', e => { if (e.target.closest && e.target.closest('.deckgrid [data-k]')) window.webkit.messageHandlers.press.postMessage(1); }, true);",
                                     injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }
    override func viewDidLoad() {
        registerFonts()
        super.viewDidLoad()
        UIApplication.shared.isIdleTimerDisabled = true   // a deck that sleeps isn't a deck
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 12), bar.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -12),
            bar.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -Self.barGap), bar.heightAnchor.constraint(equalToConstant: Self.barHeight),
        ])
        bar.who.addAction(UIAction { [weak self] _ in self?.tap.impactOccurred(); self?.call("vdMenu('conn')") }, for: .touchUpInside)
        bar.lock.addAction(UIAction { [weak self] _ in self?.tap.impactOccurred(); self?.call("vdMenu('lock')") }, for: .touchUpInside)
        bar.more.addAction(UIAction { [weak self] _ in self?.tap.impactOccurred(); self?.call("vdMenu('more')") }, for: .touchUpInside)
        finder.changed = { [weak self] list in
            guard let self = self, let json = try? JSONSerialization.data(withJSONObject: list) else { return }
            self.ones = String(decoding: json, as: UTF8.self)
            self.pageReady()
        }
        finder.start()
    }
    // Rajdhani for names, from the same file the page uses
    func registerFonts() {
        guard UIFont(name: "Rajdhani-Bold", size: 12) == nil else { return }
        let url = Bundle.main.resourceURL!.appendingPathComponent("web/fonts/rajdhani-700.woff2")
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let up = view.bounds.height >= view.bounds.width
        if up != upright { upright = up; placeBar() }
    }
    override func viewSafeAreaInsetsDidChange() { super.viewSafeAreaInsetsDidChange(); placeBar() }
    // upright the bar is always there and the decks sit above it; sideways it's away and the decks take the room
    func placeBar() {
        barTimer?.invalidate()
        setBar(visible: upright, animated: false)
        call("document.documentElement.style.setProperty('--bar', '\(upright ? Self.barHeight + Self.barGap : 0)px')")
    }
    func setBar(visible: Bool, animated: Bool) {
        let change = { self.bar.alpha = visible ? 1 : 0 }
        bar.isUserInteractionEnabled = visible
        if animated { UIView.animate(withDuration: 0.18, animations: change) } else { change() }
    }
    func peekBar() {
        guard !upright else { return }
        setBar(visible: true, animated: true)
        barTimer?.invalidate()
        barTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self = self, !self.upright else { return }
            self.setBar(visible: false, animated: true)
        }
    }
    override func pageReady() { placeBar(); call("window.onesFound && window.onesFound(\(ones))") }
    // iOS stops the socket while the app is away and Companion drops the surface, so join again straight away
    override func cameForward() { call("connect()"); finder.report() }
    override func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "press" { tap.impactOccurred() }
        if message.name == "pagearrows", let m = message.body as? [String: String], let host = m["host"], let surface = m["surface"] { allowPageArrows(host: host, surface: surface) }
        if message.name == "chrome", let m = message.body as? [String: Any] {
            switch m["action"] as? String {
            case "state":
                let decks = m["decks"] as? Int ?? 1, no = m["deckNo"] as? Int ?? 1
                // one deck: its full name. Several: the short name and which one, so it fits beside the Companion's name
                let full = m["deck"] as? String ?? ""
                let deck = decks > 1 ? "Deck \(no) · " + full.replacingOccurrences(of: "Stream Deck ", with: "") : full
                bar.show(live: m["live"] as? Bool ?? false, word: m["word"] as? String ?? "", name: m["name"] as? String ?? "", deck: deck, locked: m["locked"] as? Bool ?? false)
            case "edge": peekBar()
            default: break
            }
        }
        #if DEBUG
        if message.name == "testlog", let line = message.body as? String { testLine(line) }
        #endif
    }
}
