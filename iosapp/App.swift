// Downstage Virtual Deck for iPhone and iPad: a Stream Deck on screen. The page talks to Companion itself; this finds Ones and keeps the screen awake.
// The keys are the shared page. Everything around them is the app's own (iOS app standard, downstage-clients docs/ios-app-standard.md):
// the page hides its toolbar and tray when the "chrome" handler is here, tells the app its state, and takes commands through vdMenu.
import CoreText
import SafariServices
import UIKit
import WebKit

func makeShell() -> ShellController { registerFonts(); return DeckController() }

// Rajdhani for names, from the same file the page uses. Before any view is made, so none of them caches the fallback
func registerFonts() {
    guard UIFont(name: "Rajdhani-Bold", size: 12) == nil else { return }
    let url = Bundle.main.resourceURL!.appendingPathComponent("web/fonts/rajdhani-700.woff2")
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
}

let rajdhani: (CGFloat) -> UIFont = { size in
    UIFont(name: "Rajdhani-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
}

// The bar at the foot, upright: who the deck is joined to, which deck or its Companion page with arrows, the lock, and
// "..." for everything else. Sideways it hides, so the keys have the screen, and a tap beside the deck brings it back
final class DeckBar: UIView {
    let dot = UIView()
    let who = UIButton(type: .custom)
    let name = UILabel()
    let deck = UILabel()
    let prevPage = UIButton(type: .system), nextPage = UIButton(type: .system), page = UILabel()
    let pages = UIStackView()
    let lock = UIButton(type: .system)
    let more = UIButton(type: .system)
    static let nameFont = UIFontMetrics(forTextStyle: .headline).scaledFont(for: rajdhani(19))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0x12 / 255.0, green: 0x16 / 255.0, blue: 0x1B / 255.0, alpha: 0.96)
        layer.cornerRadius = 26
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor(red: 0x23 / 255.0, green: 0x2A / 255.0, blue: 0x32 / 255.0, alpha: 1).cgColor
        maximumContentSizeCategory = .accessibilityMedium      // Dynamic Type up to the first accessibility size
        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        name.adjustsFontForContentSizeCategory = true
        name.textColor = UIColor(red: 0xE8 / 255.0, green: 0xEC / 255.0, blue: 0xEF / 255.0, alpha: 1)
        name.setContentHuggingPriority(.required, for: .horizontal)
        name.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        for l in [deck, page] {
            l.font = .preferredFont(forTextStyle: .footnote)
            l.adjustsFontForContentSizeCategory = true
            l.textColor = UIColor(red: 0xA3 / 255.0, green: 0xAD / 255.0, blue: 0xB6 / 255.0, alpha: 1)
            l.lineBreakMode = .byTruncatingTail
        }
        page.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .monospacedDigitSystemFont(ofSize: 13, weight: .semibold))
        page.textColor = UIColor(red: 0xE8 / 255.0, green: 0xEC / 255.0, blue: 0xEF / 255.0, alpha: 1)
        page.isAccessibilityElement = false
        page.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        name.setContentCompressionResistancePriority(.defaultHigh + 1, for: .horizontal)
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
        // the selected deck's Companion page: arrows with a full 44 pt target each, the number between them
        for (b, symbol, label) in [(prevPage, "chevron.left", "Previous page"), (nextPage, "chevron.right", "Next page")] {
            b.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(textStyle: .footnote, scale: .medium)), for: .normal)
            b.tintColor = UIColor(red: 0xE8 / 255.0, green: 0xEC / 255.0, blue: 0xEF / 255.0, alpha: 1)
            b.accessibilityLabel = label
            b.widthAnchor.constraint(equalToConstant: 44).isActive = true
        }
        pages.addArrangedSubview(prevPage); pages.addArrangedSubview(page); pages.addArrangedSubview(nextPage)
        pages.alignment = .center
        pages.isHidden = true
        for (b, symbol, label) in [(lock, "lock.open", "Lock layout"), (more, "ellipsis", "More")] {
            b.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)), for: .normal)
            b.tintColor = UIColor(red: 0xA3 / 255.0, green: 0xAD / 255.0, blue: 0xB6 / 255.0, alpha: 1)
            b.accessibilityLabel = label
        }
        let row = UIStackView(arrangedSubviews: [who, pages, lock, more])
        row.spacing = 2
        row.alignment = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        who.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pages.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18), row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4), row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            left.leadingAnchor.constraint(equalTo: who.leadingAnchor), left.trailingAnchor.constraint(lessThanOrEqualTo: who.trailingAnchor),
            left.centerYAnchor.constraint(equalTo: who.centerYAnchor), left.topAnchor.constraint(greaterThanOrEqualTo: who.topAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8), dot.heightAnchor.constraint(equalToConstant: 8),
            lock.widthAnchor.constraint(equalToConstant: 44), more.widthAnchor.constraint(equalToConstant: 44),
        ])
        show(live: false, word: "Finding Companion…", name: "", deck: "", page: "", locked: false)
    }
    required init?(coder: NSCoder) { fatalError() }

    // page: what the selected deck's page reads, like "Page 2" or "Deck 2 · Page 2", or empty when no page is known
    func show(live: Bool, word: String, name n: String, deck d: String, page p: String, locked: Bool) {
        dot.backgroundColor = live ? UIColor(red: 0x2F / 255.0, green: 0xD9 / 255.0, blue: 0x7B / 255.0, alpha: 1)
                                   : UIColor(red: 0xF7 / 255.0, green: 0xC0 / 255.0, blue: 0x66 / 255.0, alpha: 1)
        // joined: the Companion's name, in Rajdhani. Not yet: what it's doing, in the system face
        name.text = live ? n : word
        name.font = live ? Self.nameFont : .preferredFont(forTextStyle: .subheadline)
        deck.text = d
        deck.isHidden = !p.isEmpty
        // at the large text sizes the number alone sits between the arrows; VoiceOver still hears the whole line
        let big = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        page.text = big ? (p.components(separatedBy: "Page ").last ?? p) : p
        pages.isHidden = p.isEmpty
        prevPage.accessibilityValue = p; nextPage.accessibilityValue = p
        who.accessibilityLabel = (live ? "Joined to \(n)" : word) + (d.isEmpty ? "" : ", \(d)")
        who.accessibilityHint = "Companion and deck settings"
        lock.setImage(UIImage(systemName: locked ? "lock.fill" : "lock.open", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)), for: .normal)
        lock.tintColor = locked ? UIColor(red: 0x2F / 255.0, green: 0xD9 / 255.0, blue: 0x7B / 255.0, alpha: 1) : UIColor(red: 0xA3 / 255.0, green: 0xAD / 255.0, blue: 0xB6 / 255.0, alpha: 1)
        lock.accessibilityLabel = "Lock layout"
        lock.accessibilityValue = locked ? "On" : "Off"
    }
}

// The first time a Companion turns up: one card and one tap, because joining adds a surface to a real Companion.
// After that the deck joins it again by itself. Two of a kind found: it asks which
final class JoinCard: UIView {
    let picture = UIImageView(), title = UILabel(), detail = UILabel()
    let join = UIButton(type: .system), other = UIButton(type: .system)
    var id = ""
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = panel
        layer.cornerRadius = 24; layer.cornerCurve = .continuous; layer.borderWidth = 1; layer.borderColor = edge.cgColor
        maximumContentSizeCategory = .accessibilityMedium
        picture.contentMode = .scaleAspectFit
        picture.tintColor = secondaryInk
        picture.heightAnchor.constraint(equalToConstant: 64).isActive = true
        picture.isAccessibilityElement = false
        title.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: rajdhani(28)); title.adjustsFontForContentSizeCategory = true
        title.textColor = ink; title.textAlignment = .center
        detail.font = .preferredFont(forTextStyle: .subheadline); detail.adjustsFontForContentSizeCategory = true
        detail.textColor = secondaryInk; detail.textAlignment = .center; detail.numberOfLines = 0
        var j = UIButton.Configuration.filled()
        j.baseBackgroundColor = runGreen; j.baseForegroundColor = rgb(0x06140C); j.cornerStyle = .large
        j.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var a = $0; a.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 17, weight: .semibold)); return a }
        join.configuration = j
        join.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        other.tintColor = runGreen
        other.titleLabel?.font = .preferredFont(forTextStyle: .body); other.titleLabel?.adjustsFontForContentSizeCategory = true
        other.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let stack = UIStackView(arrangedSubviews: [picture, title, detail, join, other])
        stack.axis = .vertical; stack.spacing = 8; stack.alignment = .fill
        stack.setCustomSpacing(4, after: title); stack.setCustomSpacing(16, after: detail)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
                                     stack.topAnchor.constraint(equalTo: topAnchor, constant: 22), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)])
    }
    required init?(coder: NSCoder) { fatalError() }
    func offer(_ m: [String: Any]) {
        id = m["id"] as? String ?? ""
        let choose = m["choose"] as? Bool ?? false, one = (m["kind"] as? String) == "one"
        picture.image = one ? UIImage(named: "One") : UIImage(systemName: "square.grid.3x3.square", withConfiguration: UIImage.SymbolConfiguration(pointSize: 48, weight: .light))
        if choose {
            title.text = "\(m["count"] as? Int ?? 2) \(one ? "Downstage Ones" : "Companions") found"
            detail.text = "Choose which one this deck joins."
            join.setTitle("Choose", for: .normal); other.setTitle("Not now", for: .normal)
        } else {
            title.text = m["name"] as? String
            detail.text = (one ? "Downstage One" : "Companion") + " found on this network"
            join.setTitle("Join", for: .normal); other.setTitle("Use another Companion", for: .normal)
        }
        join.accessibilityHint = choose ? nil : "Adds this deck to \(m["name"] as? String ?? "Companion") as a surface"
    }
}

final class DeckController: ShellController {
    let finder = OneFinder()
    var ones = "[]"
    var companions = "[]"
    let card = JoinCard()
    var declined: Set<String> = []              // offers turned down this time, so the card doesn't come straight back
    let tap = UIImpactFeedbackGenerator(style: .light)
    let bar = DeckBar()
    var upright = true
    var barTimer: Timer?
    static let barHeight: CGFloat = 52, barGap: CGFloat = 6
    var st: [String: Any] = [:]                 // the page's last word on its state, for the sheet and the menus
    weak var sheet: UINavigationController?
    var asking: (id: Int, alert: UIAlertController)?
    var answering: ((String) -> Void)?          // the open alert's answer, for a test script
    var gridTimer: Timer?
    var ranTest = false
    var barShown: CGFloat = 0

    func feel() { if Prefs.feel { tap.impactOccurred() } }
    // a command for the page, the same ones the Mac's menus send
    func cmd(_ c: String, _ arg: String = "") {
        guard let d = try? JSONSerialization.data(withJSONObject: [c, arg]), let args = String(data: d, encoding: .utf8) else { return }
        call("window.vdMenu && window.vdMenu(...\(args))")
    }
    var top: UIViewController { var v: UIViewController = self; while let p = v.presentedViewController, !p.isBeingDismissed { v = p }; return v }

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
        c.add(self, name: "chrome")   // and this one that the app draws the bar, the sheet, the menus and the questions
        c.addUserScript(WKUserScript(source: "document.addEventListener('pointerdown', e => { if (e.target.closest && e.target.closest('.deckgrid [data-k]')) window.webkit.messageHandlers.press.postMessage(1); }, true);",
                                     injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        UIApplication.shared.isIdleTimerDisabled = Prefs.awake   // a deck that sleeps isn't a deck, unless it was asked to
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 12), bar.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -12),
            bar.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -Self.barGap), bar.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.barHeight),
        ])
        card.translatesAutoresizingMaskIntoConstraints = false
        card.isHidden = true
        view.addSubview(card)
        let wide = card.widthAnchor.constraint(equalTo: g.widthAnchor, constant: -24); wide.priority = .defaultHigh
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: g.centerXAnchor), wide, card.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
            card.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -Self.barGap),
        ])
        card.join.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.feel()
            if self.card.id.isEmpty { self.hideCard(); self.openSheet(.companion) } else { self.cmd("pick", self.card.id); self.hideCard() }
        }, for: .touchUpInside)
        card.other.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            let choosing = self.card.id.isEmpty
            self.declined.insert(choosing ? "choose" : self.card.id)
            self.hideCard()
            if !choosing { self.openSheet(.companion) }
        }, for: .touchUpInside)
        // the selected deck's page, from the bar. Sideways, a press keeps the bar up for another five seconds
        for (b, up) in [(bar.prevPage, "0"), (bar.nextPage, "1")] {
            b.addAction(UIAction { [weak self] _ in
                guard let self = self else { return }
                self.feel()
                self.cmd("page", "\(self.st["deckNo"] as? Int ?? 1):\(up)")
                if !self.upright { self.peekBar() }
            }, for: .touchUpInside)
        }
        bar.who.addAction(UIAction { [weak self] _ in self?.feel(); self?.openSheet(.companion) }, for: .touchUpInside)
        bar.lock.addAction(UIAction { [weak self] _ in self?.feel(); self?.cmd("lock") }, for: .touchUpInside)
        bar.more.addAction(UIAction { [weak self] _ in self?.feel(); self?.openSheet(nil) }, for: .touchUpInside)
        finder.changed = { [weak self] list in
            guard let self = self, let json = try? JSONSerialization.data(withJSONObject: list) else { return }
            self.ones = String(decoding: json, as: UTF8.self)
            self.pageReady()
        }
        // the same finding as the Mac: Companion on the network, then a One. A test can switch it off and hand the page made-up finds
        finder.findCompanions = true
        #if DEBUG
        if ProcessInfo.processInfo.environment["DOWNSTAGE_TEST_NOFIND"] != nil { return }
        #endif
        finder.companionsChanged = { [weak self] list in
            guard let self = self, let json = try? JSONSerialization.data(withJSONObject: list) else { return }
            self.companions = String(decoding: json, as: UTF8.self)
            self.pageReady()
        }
        finder.start()
    }
    func showCard(_ m: [String: Any]) {
        let id = m["id"] as? String ?? ""
        guard !declined.contains(m["choose"] as? Bool == true ? "choose" : id), card.isHidden || card.id != id else { return }
        card.offer(m)
        card.isHidden = false
        card.alpha = 0
        UIView.animate(withDuration: 0.2) { self.card.alpha = 1; self.bar.alpha = 0 }
        bar.isUserInteractionEnabled = false
        UIAccessibility.post(notification: .screenChanged, argument: card.title)
    }
    func hideCard() {
        guard !card.isHidden else { return }
        UIView.animate(withDuration: 0.2, animations: { self.card.alpha = 0 }) { _ in self.card.isHidden = true }
        placeBar()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let up = view.bounds.height >= view.bounds.width
        if up != upright || bar.bounds.height != barShown { upright = up; barShown = bar.bounds.height; placeBar() }
    }
    override func viewSafeAreaInsetsDidChange() { super.viewSafeAreaInsetsDidChange(); placeBar() }
    // upright the bar is always there and the decks sit above it; sideways it's away and the decks take the room
    func placeBar() {
        barTimer?.invalidate()
        setBar(visible: upright && card.isHidden, animated: false)
        call("document.documentElement.style.setProperty('--bar', '\(upright ? max(Self.barHeight, bar.bounds.height) + Self.barGap : 0)px')")
    }
    func setBar(visible: Bool, animated: Bool) {
        let change = { self.bar.alpha = visible ? 1 : 0 }
        bar.isUserInteractionEnabled = visible
        if animated { UIView.animate(withDuration: 0.18, animations: change) } else { change() }
    }
    func peekBar() {
        guard !upright, card.isHidden else { return }
        setBar(visible: true, animated: true)
        barTimer?.invalidate()
        barTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self = self, !self.upright else { return }
            self.setBar(visible: false, animated: true)
        }
    }
    override func pageReady() {
        placeBar(); call("window.onesFound && window.onesFound(\(ones)); window.companionsFound && window.companionsFound(\(companions))")
        #if DEBUG
        runTestSteps()
        #endif
    }
    #if DEBUG
    // A test walks the sheet the way a finger would, through the same code a tap runs: DOWNSTAGE_TEST_SHEET is steps
    // a second and a half apart, like "open;row:1:0;row:0:3;back;alert:go:Ballroom". Each step logs the page's state
    func runTestSteps() {
        guard let script = ProcessInfo.processInfo.environment["DOWNSTAGE_TEST_SHEET"], !ranTest else { return }
        ranTest = true
        for (i, step) in script.split(separator: ";").map(String.init).enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3 + Double(i) * 1.5) { [weak self] in self?.testStep(step) }
        }
    }
    func testStep(_ step: String) {
        let p = step.split(separator: ":", maxSplits: 2).map(String.init)
        switch p[0] {
        case "open": openSheet(p.count < 2 ? nil : p[1] == "companion" ? .companion : p[1] == "shows" ? .shows : .deck(Int(p[1].dropFirst(4)) ?? 1))
        case "row":
            if let list = sheet?.topViewController as? SheetList, p.count > 1, let r = Int(p.count > 2 ? p[2] : "0"), let sec = Int(p[1]) {
                list.tableView(list.tableView, didSelectRowAt: IndexPath(row: r, section: sec))
            }
        case "back": sheet?.popViewController(animated: true)
        case "close": sheet?.dismiss(animated: true)
        case "large": sheet?.sheetPresentationController?.animateChanges { sheet?.sheetPresentationController?.selectedDetentIdentifier = .large }
        case "alert":
            if let a = asking?.alert { if p.count > 2 { a.textFields?.first?.text = p[2] }; a.dismiss(animated: true) }
            answering?(p.count > 1 ? p[1] : "go")
        case "deckmenu": deckMenu(["n": Int(p.count > 1 ? p[1] : "1") ?? 1, "x": 100.0, "y": 300.0])
        case "dismiss": top.dismiss(animated: true)
        case "host": cmd("host", p.count > 1 ? p[1] : "")
        case "join": card.join.sendActions(for: .touchUpInside)
        case "other": card.other.sendActions(for: .touchUpInside)
        case "barnext": bar.nextPage.sendActions(for: .touchUpInside)
        case "barprev": bar.prevPage.sendActions(for: .touchUpInside)
        case "js": call(String(step.dropFirst(3)))
        default: break
        }
        call("window.webkit.messageHandlers.testlog && window.webkit.messageHandlers.testlog.postMessage(JSON.stringify({ step: \(String(reflecting: step)), now: shows.now, shows: showNames(), decks: S.decks.map(d => d.model), page: S.decks.map(d => d.page || ''), joined: JSON.parse(localStorage.getItem('ds_vdeck_joined') || '[]'), card: \(card.isHidden ? "''" : String(reflecting: card.title.text ?? "")), bar: \(String(reflecting: bar.page.isHidden ? (bar.deck.text ?? "") : (bar.page.text ?? ""))), keys: [...document.querySelectorAll('.deckgrid .key')].slice(0, 3).map(k => k.getAttribute('aria-label') + (k.querySelector('img') ? '+img' : '')), sel: S.decks.indexOf(S.sel) + 1, locked: !!S.locked, host: S.host, live: S.state === 'ok', say: document.getElementById('say').textContent }))")
    }
    #endif
    // iOS stops the socket while the app is away and Companion drops the surface, so join again straight away
    override func cameForward() { call("connect()"); finder.report() }
    override func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "press" { feel() }
        if message.name == "pagearrows", let m = message.body as? [String: String], let host = m["host"], let surface = m["surface"] { allowPageArrows(host: host, surface: surface) }
        if message.name == "chrome", let m = message.body as? [String: Any] {
            switch m["action"] as? String {
            case "state":
                st = m
                refreshSheet()
                let decks = m["count"] as? Int ?? 1, no = m["deckNo"] as? Int ?? 1
                // one deck: its full name. Several: the short name and which one, so it fits beside the Companion's name
                let full = m["deck"] as? String ?? ""
                let deck = decks > 1 ? "Deck \(no) · " + full.replacingOccurrences(of: "Stream Deck ", with: "") : full
                // a known Companion page puts the arrows in the bar, in place of the deck's type (that's in the sheet)
                let list = m["decks"] as? [[String: Any]] ?? [], p = no >= 1 && no <= list.count ? list[no - 1]["page"] as? String ?? "" : ""
                let page = p.isEmpty ? "" : (decks > 1 ? "Deck \(no) · Page \(p)" : "Page \(p)")
                let live = m["live"] as? Bool ?? false
                bar.show(live: live, word: m["word"] as? String ?? "", name: m["name"] as? String ?? "", deck: deck, page: page, locked: m["locked"] as? Bool ?? false)
                if live { hideCard() }
            case "edge": peekBar()
            case "ask": ask(m)
            case "askClose": if let a = asking, a.id == m["id"] as? Int { asking = nil; a.alert.presentingViewController?.dismiss(animated: true) }
            case "deckmenu": deckMenu(m)
            case "offer": showCard(m)
            default: break
            }
        }
        #if DEBUG
        if message.name == "testlog", let line = message.body as? String { testLine(line) }
        #endif
    }
}

// ---- the switches under "This iPhone": the app's own, kept on this device ----
enum Prefs {
    static var feel: Bool { get { UserDefaults.standard.object(forKey: "feel") as? Bool ?? true } set { UserDefaults.standard.set(newValue, forKey: "feel") } }
    static var awake: Bool { get { UserDefaults.standard.object(forKey: "awake") as? Bool ?? true } set { UserDefaults.standard.set(newValue, forKey: "awake") } }
}

func rgb(_ v: UInt32) -> UIColor { UIColor(red: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1) }
let ink = rgb(0xE8ECEF), secondaryInk = rgb(0xA3ADB6), metaInk = rgb(0x7C8791), runGreen = rgb(0x2FD97B), panel = rgb(0x12161B), edge = rgb(0x232A32)
var deviceWord: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }

// a pale status pill, as on the Mac: live, warning or quiet
final class Pill: UILabel {
    override var intrinsicContentSize: CGSize { let s = super.intrinsicContentSize; return CGSize(width: s.width + 18, height: s.height + 6) }
    override func drawText(in rect: CGRect) { super.drawText(in: rect.insetBy(dx: 9, dy: 3)) }
    func set(_ text: String, _ kind: String) {
        self.text = text
        font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13, weight: .semibold))
        layer.cornerRadius = 11; layer.masksToBounds = true
        let tint: (UInt32, UInt32) = kind == "live" ? (0x10301D, 0x74E8A8) : kind == "warn" ? (0x33270F, 0xF7C066) : (0x181D23, 0x7C8791)
        backgroundColor = rgb(tint.0); textColor = rgb(tint.1)
        invalidateIntrinsicContentSize()
    }
}

extension DeckController {
    enum Screen { case companion, deck(Int), shows }

    // the sheet: medium and large on an iPhone, a form sheet on an iPad. It can open straight onto one of its screens
    func openSheet(_ to: Screen?) {
        if let s = sheet { s.dismiss(animated: false) }
        let home = SheetHome(owner: self)
        let nav = UINavigationController(rootViewController: home)
        nav.navigationBar.tintColor = runGreen
        nav.view.maximumContentSizeCategory = .accessibilityMedium     // Dynamic Type up to the first accessibility size
        nav.view.tintColor = runGreen
        if UIDevice.current.userInterfaceIdiom == .pad { nav.modalPresentationStyle = .formSheet }
        else if let p = nav.sheetPresentationController {
            p.detents = [.medium(), .large()]
            p.prefersGrabberVisible = true
            p.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        switch to {
        case .companion: nav.pushViewController(CompanionScreen(owner: self), animated: false)
        case .deck(let n): nav.pushViewController(DeckScreen(owner: self, n: n), animated: false)
        case .shows: nav.pushViewController(ShowsScreen(owner: self), animated: false)
        case nil: break
        }
        sheet = nav
        top.present(nav, animated: true)
    }
    func refreshSheet() { sheet?.viewControllers.forEach { ($0 as? Refreshing)?.refresh() } }

    // The page's questions (save first, a show's name, delete it, where Companion is) as the system's own alerts.
    // The answer goes back by its id, so a question the page has withdrawn is never answered
    func ask(_ m: [String: Any]) {
        guard let id = m["id"] as? Int else { return }
        if let a = asking { asking = nil; a.alert.presentingViewController?.dismiss(animated: false) }
        let text = m["text"] as? String ?? ""
        let a = UIAlertController(title: m["title"] as? String, message: text.isEmpty ? nil : text, preferredStyle: .alert)
        let named = m["name"] is String
        if named {
            a.addTextField { f in
                f.text = m["name"] as? String; f.placeholder = m["placeholder"] as? String
                f.autocapitalizationType = .words; f.clearButtonMode = .whileEditing; f.returnKeyType = .done
                if (m["placeholder"] as? String ?? "").contains("address") { f.keyboardType = .numbersAndPunctuation; f.autocapitalizationType = .none; f.autocorrectionType = .no }
            }
        }
        let answer: (String) -> Void = { [weak self, weak a] how in
            guard let self = self, self.asking?.id == id else { return }
            self.asking = nil
            let value = named ? (a?.textFields?.first?.text ?? "") : ""
            guard let d = try? JSONSerialization.data(withJSONObject: [how, value]), let args = String(data: d, encoding: .utf8) else { return }
            self.call("window.vdAnswer && window.vdAnswer(\(id), ...\(args))")
        }
        let goTitle = m["go"] as? String ?? "OK", alt = m["alt"] as? String ?? ""
        if goTitle != "OK" || !alt.isEmpty { a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in answer("cancel") }) }
        if !alt.isEmpty { a.addAction(UIAlertAction(title: alt, style: .destructive) { _ in answer("alt") }) }
        let go = UIAlertAction(title: goTitle, style: m["danger"] as? Bool == true ? .destructive : .default) { _ in answer("go") }
        a.addAction(go)
        if m["danger"] as? Bool != true { a.preferredAction = go }
        a.view.tintColor = runGreen
        asking = (id, a)
        answering = answer
        top.present(a, animated: true)
    }

    // A long press on a deck's frame: the deck's own commands, as the system's menu
    func deckMenu(_ m: [String: Any]) {
        let n = m["n"] as? Int ?? 0
        let decks = st["decks"] as? [[String: Any]] ?? []
        guard n > 0, n <= decks.count else { openSheet(nil); return }
        let d = decks[n - 1], count = decks.count, locked = st["locked"] as? Bool ?? false
        let a = UIAlertController(title: (count > 1 ? "Deck \(n) · " : "") + (d["name"] as? String ?? ""), message: nil, preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(title: "Deck type…", style: .default) { [weak self] _ in self?.openSheet(.deck(n)) })
        if !(d["page"] as? String ?? "").isEmpty {
            a.addAction(UIAlertAction(title: "Next page", style: .default) { [weak self] _ in self?.cmd("page", "\(n):1") })
            a.addAction(UIAlertAction(title: "Previous page", style: .default) { [weak self] _ in self?.cmd("page", "\(n):0") })
        }
        if st["canArrange"] as? Bool == true { a.addAction(UIAlertAction(title: "Arrange decks", style: .default) { [weak self] _ in self?.cmd("arrange") }) }
        a.addAction(UIAlertAction(title: locked ? "Unlock layout" : "Lock layout", style: .default) { [weak self] _ in self?.cmd("lock") })
        if count > 1 { a.addAction(UIAlertAction(title: "Remove this deck", style: .destructive) { [weak self] _ in self?.cmd("removeN", "\(n)") }) }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let p = a.popoverPresentationController {
            p.sourceView = web
            p.sourceRect = CGRect(x: m["x"] as? Double ?? 0, y: m["y"] as? Double ?? 0, width: 1, height: 1)
        }
        feel()
        top.present(a, animated: true)
    }
    // a custom grid's size: sent once the steppers rest, because each change joins Companion as a new layout
    func sendGrid(_ n: Int, _ cols: Int, _ rows: Int) {
        gridTimer?.invalidate()
        gridTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in self?.cmd("grid", "\(n):\(cols):\(rows)") }
    }
}

protocol Refreshing: AnyObject { func refresh() }

// the sheet's screens share one look: inset grouped rows on Panel, over Ground
class SheetList: UITableViewController, Refreshing {
    unowned let owner: DeckController
    var st: [String: Any] { owner.st }
    init(owner: DeckController) { self.owner = owner; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = rgb(0x0B0D10)
        tableView.separatorColor = edge
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
    }
    func refresh() { if isViewLoaded { tableView.reloadData() } }
    func cell(_ text: String, _ detail: String? = nil, chevron: Bool = false, tint: UIColor? = nil, value: Bool = true) -> UITableViewCell {
        let c = UITableViewCell(style: value ? .value1 : .subtitle, reuseIdentifier: nil)
        var conf = value ? UIListContentConfiguration.valueCell() : UIListContentConfiguration.subtitleCell()
        conf.text = text; conf.secondaryText = detail
        conf.textProperties.color = tint ?? ink
        conf.secondaryTextProperties.color = secondaryInk
        c.contentConfiguration = conf
        c.backgroundColor = panel
        c.accessoryType = chevron ? .disclosureIndicator : .none
        return c
    }
    func toggle(_ text: String, on: Bool, label: String? = nil, _ changed: @escaping (Bool) -> Void) -> UITableViewCell {
        let c = cell(text)
        let sw = UISwitch(); sw.isOn = on; sw.onTintColor = runGreen
        sw.accessibilityLabel = label ?? text
        sw.addAction(UIAction { [weak sw] _ in changed(sw?.isOn ?? false) }, for: .valueChanged)
        c.accessoryView = sw
        c.selectionStyle = .none
        return c
    }
    func checked(_ c: UITableViewCell, _ on: Bool) -> UITableViewCell { c.accessoryType = on ? .checkmark : .none; c.tintColor = runGreen; return c }
}

// Home: Companion, the decks, the show, and this iPhone's switches. Version at the foot
final class SheetHome: SheetList {
    enum Row { case companion, deck(Int), addDeck, arrange, snap, show, lock, feel, awake }
    var sections: [(String?, [Row])] {
        let count = (st["decks"] as? [Any])?.count ?? 1, locked = st["locked"] as? Bool ?? false
        var decks: [Row] = (1...max(1, count)).map { .deck($0) }
        if count < 8 { decks.append(.addDeck) }
        if st["canArrange"] as? Bool == true { decks.append(.arrange) }
        if !locked { decks.append(.snap) }
        return [(nil, [.companion]), (count > 1 ? "Decks" : nil, decks), ("Show", [.show]), ("This \(deviceWord)", [.lock, .feel, .awake])]
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Virtual Deck"
        // a quiet close, not the filled Done: the sheet has no main action of its own, and a swipe down closes it too
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    }
    override func numberOfSections(in t: UITableView) -> Int { sections.count }
    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { sections[s].1.count }
    override func tableView(_ t: UITableView, titleForHeaderInSection s: Int) -> String? { sections[s].0 }
    override func tableView(_ t: UITableView, titleForFooterInSection s: Int) -> String? { s == sections.count - 1 ? versionText : nil }
    override func tableView(_ t: UITableView, cellForRowAt i: IndexPath) -> UITableViewCell {
        let decks = st["decks"] as? [[String: Any]] ?? []
        switch sections[i.section].1[i.row] {
        case .companion: return companionCell()
        case .deck(let n):
            let d = n <= decks.count ? decks[n - 1] : [:]
            return cell(decks.count > 1 ? "Deck \(n)" : "Deck", deckName(d), chevron: true)
        case .addDeck: return cell("Add a deck", tint: runGreen)
        case .arrange: return cell("Arrange decks", tint: runGreen)
        case .snap: return toggle("Snap decks into line", on: st["snap"] as? Bool ?? true) { [weak self] _ in self?.owner.cmd("snap") }
        case .show:
            let c = cell(st["title"] as? String ?? "Untitled show", st["docState"] as? String, chevron: true)
            if var conf = c.contentConfiguration as? UIListContentConfiguration { conf.textProperties.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: rajdhani(19)); c.contentConfiguration = conf }
            return c
        case .lock: return toggle("Lock layout", on: st["locked"] as? Bool ?? false) { [weak self] _ in self?.owner.cmd("lock") }
        case .feel: return toggle("Feel each press", on: Prefs.feel) { on in Prefs.feel = on }
        case .awake: return toggle("Keep the screen awake", on: Prefs.awake) { on in Prefs.awake = on; UIApplication.shared.isIdleTimerDisabled = on }
        }
    }
    // "Companion", then its status pill and name at the right; at the large text sizes they stack under it instead
    func companionCell() -> UITableViewCell {
        let c = UITableViewCell(style: .default, reuseIdentifier: nil)
        c.backgroundColor = panel
        c.accessoryType = .disclosureIndicator
        let live = st["live"] as? Bool ?? false, host = st["host"] as? String ?? "", word = st["word"] as? String ?? ""
        let title = UILabel(); title.text = "Companion"; title.textColor = ink
        title.font = .preferredFont(forTextStyle: .body); title.adjustsFontForContentSizeCategory = true
        title.setContentHuggingPriority(.required, for: .horizontal); title.setContentCompressionResistancePriority(.required, for: .horizontal)
        let pill = Pill()
        pill.set(live ? "Joined" : host.isEmpty ? (word.hasPrefix("Choose") ? "Choose" : "Not set") : word.hasPrefix("Joining") ? "Joining" : "Not answering",
                 live ? "live" : host.isEmpty ? "quiet" : "warn")
        pill.setContentCompressionResistancePriority(.required, for: .horizontal)
        let name = UILabel(); name.text = host.isEmpty ? "" : st["name"] as? String; name.textColor = secondaryInk
        name.font = .preferredFont(forTextStyle: .body); name.adjustsFontForContentSizeCategory = true; name.lineBreakMode = .byTruncatingMiddle
        let right = UIStackView(arrangedSubviews: [pill, name]); right.spacing = 8; right.alignment = .center
        let big = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        let row = UIStackView(arrangedSubviews: big ? [title, right] : [title, UIView(), right])
        row.axis = big ? .vertical : .horizontal; row.spacing = 8; row.alignment = big ? .leading : .center
        row.translatesAutoresizingMaskIntoConstraints = false
        c.contentView.addSubview(row)
        let m = c.contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: m.leadingAnchor), row.trailingAnchor.constraint(equalTo: m.trailingAnchor),
                                     row.topAnchor.constraint(equalTo: m.topAnchor), row.bottomAnchor.constraint(equalTo: m.bottomAnchor)])
        c.isAccessibilityElement = true
        c.accessibilityLabel = "Companion, " + (pill.text ?? "") + ((name.text ?? "").isEmpty ? "" : ", " + (name.text ?? ""))
        c.accessibilityTraits = .button
        return c
    }
    override func tableView(_ t: UITableView, didSelectRowAt i: IndexPath) {
        t.deselectRow(at: i, animated: true)
        switch sections[i.section].1[i.row] {
        case .companion: navigationController?.pushViewController(CompanionScreen(owner: owner), animated: true)
        case .deck(let n): navigationController?.pushViewController(DeckScreen(owner: owner, n: n), animated: true)
        case .addDeck: owner.feel(); owner.cmd("add")
        case .arrange: owner.feel(); owner.cmd("arrange")
        case .show: navigationController?.pushViewController(ShowsScreen(owner: owner), animated: true)
        default: break
        }
    }
    // a deck row swipes to remove, when there's more than one
    override func tableView(_ t: UITableView, trailingSwipeActionsConfigurationForRowAt i: IndexPath) -> UISwipeActionsConfiguration? {
        guard case .deck(let n) = sections[i.section].1[i.row], ((st["decks"] as? [Any])?.count ?? 1) > 1 else { return nil }
        return UISwipeActionsConfiguration(actions: [UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, done in self?.owner.cmd("removeN", "\(n)"); done(true) }])
    }
}

func deckName(_ d: [String: Any]) -> String {
    (d["model"] as? String) == "custom" ? "Custom grid \(d["cols"] as? Int ?? 8) x \(d["rows"] as? Int ?? 4)" : d["name"] as? String ?? ""
}

// Companion: what was found on the network, or an address. A typed address beats what was found
final class CompanionScreen: SheetList, UITextFieldDelegate {
    let field = UITextField()
    var found: [[String: Any]] { st["found"] as? [[String: Any]] ?? [] }
    var hasSurfaces: Bool { !(st["surfaces"] as? String ?? "").isEmpty }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Companion"
        field.placeholder = "Like 192.168.1.20"
        field.keyboardType = .numbersAndPunctuation; field.autocapitalizationType = .none; field.autocorrectionType = .no
        field.returnKeyType = .go; field.clearButtonMode = .whileEditing; field.textColor = ink
        field.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        field.accessibilityLabel = "Companion address"
        field.delegate = self
    }
    override func refresh() {
        guard isViewLoaded else { return }
        if field.isFirstResponder { tableView.reloadSections([0], with: .none) } else { tableView.reloadData() }
    }
    override func numberOfSections(in t: UITableView) -> Int { hasSurfaces ? 3 : 2 }
    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { s == 0 ? max(1, found.count) : 1 }
    override func tableView(_ t: UITableView, titleForHeaderInSection s: Int) -> String? { ["Found on this network", "Address", nil][s] }
    override func tableView(_ t: UITableView, titleForFooterInSection s: Int) -> String? {
        s == 0 ? st["text"] as? String : s == 1 ? "A typed address is used instead of anything found." : nil
    }
    override func tableView(_ t: UITableView, cellForRowAt i: IndexPath) -> UITableViewCell {
        switch i.section {
        case 0:
            guard !found.isEmpty else { let c = cell("Nothing found yet"); c.selectionStyle = .none; return c }
            let o = found[i.row], pick = st["pick"] as? String ?? "", host = st["host"] as? String ?? ""
            let kind = o["kind"] as? String == "one" ? "Downstage One" : "Companion"
            return checked(cell(o["name"] as? String ?? "", "\(kind) · \(o["host"] as? String ?? "")", value: false),
                           (o["id"] as? String) == pick && (o["host"] as? String) == host)
        case 1:
            let c = cell("")
            field.text = (st["pick"] as? String ?? "").isEmpty ? st["host"] as? String : ""
            field.translatesAutoresizingMaskIntoConstraints = false
            c.contentView.addSubview(field)
            NSLayoutConstraint.activate([field.leadingAnchor.constraint(equalTo: c.contentView.layoutMarginsGuide.leadingAnchor),
                                         field.trailingAnchor.constraint(equalTo: c.contentView.layoutMarginsGuide.trailingAnchor),
                                         field.topAnchor.constraint(equalTo: c.contentView.topAnchor), field.bottomAnchor.constraint(equalTo: c.contentView.bottomAnchor),
                                         field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)])
            c.selectionStyle = .none
            return c
        default: return cell("Open Surfaces in Companion", tint: runGreen)
        }
    }
    override func tableView(_ t: UITableView, didSelectRowAt i: IndexPath) {
        t.deselectRow(at: i, animated: true)
        if i.section == 0, i.row < found.count, let id = found[i.row]["id"] as? String { owner.feel(); owner.cmd("pick", id) }
        if i.section == 2, let u = URL(string: st["surfaces"] as? String ?? "") { present(SFSafariViewController(url: u), animated: true) }
    }
    func textFieldShouldReturn(_ f: UITextField) -> Bool {
        let v = (f.text ?? "").trimmingCharacters(in: .whitespaces)
        f.resignFirstResponder()
        if !v.isEmpty { owner.cmd("host", v) }
        return true
    }
}

// One deck: its type, a custom grid's size, its Companion page, and removing it
final class DeckScreen: SheetList {
    let n: Int
    init(owner: DeckController, n: Int) { self.n = n; super.init(owner: owner) }
    required init?(coder: NSCoder) { fatalError() }
    var deck: [String: Any] { let d = st["decks"] as? [[String: Any]] ?? []; return n <= d.count ? d[n - 1] : [:] }
    var models: [[String: Any]] { st["models"] as? [[String: Any]] ?? [] }
    var count: Int { (st["decks"] as? [Any])?.count ?? 1 }
    enum Part { case types, grid, page, remove }
    var parts: [Part] {
        var p: [Part] = [.types]
        if deck["model"] as? String == "custom" { p.append(.grid) }
        if !(deck["page"] as? String ?? "").isEmpty { p.append(.page) }
        if count > 1 { p.append(.remove) }
        return p
    }
    override func viewDidLoad() { super.viewDidLoad(); title = count > 1 ? "Deck \(n)" : "Deck" }
    override func refresh() {
        guard isViewLoaded else { return }
        if n > count { navigationController?.popToRootViewController(animated: true); return }
        tableView.reloadData()
    }
    override func numberOfSections(in t: UITableView) -> Int { parts.count }
    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { [models.count, 2, 2, 1][[Part.types, .grid, .page, .remove].firstIndex(of: parts[s])!] }
    override func tableView(_ t: UITableView, titleForHeaderInSection s: Int) -> String? {
        switch parts[s] { case .types: return "Type"; case .grid: return "Custom grid"; case .page: return "Companion page \(deck["page"] as? String ?? "")"; case .remove: return nil }
    }
    override func tableView(_ t: UITableView, titleForFooterInSection s: Int) -> String? {
        parts[s] == .types ? "Each deck joins Companion as its own surface. A new type joins again with the new layout." : nil
    }
    override func tableView(_ t: UITableView, cellForRowAt i: IndexPath) -> UITableViewCell {
        switch parts[i.section] {
        case .types:
            let m = models[i.row]
            return checked(cell(m["label"] as? String ?? ""), (m["id"] as? String) == (deck["model"] as? String))
        case .grid:
            let cols = deck["cols"] as? Int ?? 8, rows = deck["rows"] as? Int ?? 4
            let isCols = i.row == 0, v = isCols ? cols : rows
            let c = cell(isCols ? "Columns" : "Rows", "\(v)")
            let step = UIStepper(); step.minimumValue = 1; step.maximumValue = isCols ? 32 : 16; step.value = Double(v)
            step.accessibilityLabel = isCols ? "Columns" : "Rows"
            step.addAction(UIAction { [weak self, weak step, weak c] _ in
                guard let self = self, let step = step else { return }
                let nv = Int(step.value)
                if var conf = c?.contentConfiguration as? UIListContentConfiguration { conf.secondaryText = "\(nv)"; c?.contentConfiguration = conf }
                self.owner.sendGrid(self.n, isCols ? nv : cols, isCols ? rows : nv)
            }, for: .valueChanged)
            c.accessoryView = step
            c.selectionStyle = .none
            return c
        case .page: return cell(i.row == 0 ? "Next page" : "Previous page", tint: runGreen)
        case .remove: return cell("Remove this deck", tint: .systemRed)
        }
    }
    override func tableView(_ t: UITableView, didSelectRowAt i: IndexPath) {
        t.deselectRow(at: i, animated: true)
        switch parts[i.section] {
        case .types: if let id = models[i.row]["id"] as? String { owner.feel(); owner.cmd("model", "\(n):\(id)") }
        case .page: owner.feel(); owner.cmd("page", "\(n):\(i.row == 0 ? 1 : 0)")
        case .remove: owner.cmd("removeN", "\(n)"); navigationController?.popToRootViewController(animated: true)
        case .grid: break
        }
    }
}

// Shows: the saved ones, and New, Save, Save as, Rename and Delete. Questions come up as alerts
final class ShowsScreen: SheetList {
    var names: [String] { st["shows"] as? [String] ?? [] }
    var now: String { st["now"] as? String ?? "" }
    var actions: [(String, String, Bool)] {
        var a: [(String, String, Bool)] = [("New show", "new", false), ("Save show", "save", false), ("Save show as…", "saveas", false)]
        if !now.isEmpty { a += [("Rename show…", "rename", false), ("Delete show…", "delete", true)] }
        return a
    }
    override func viewDidLoad() { super.viewDidLoad(); title = "Shows" }
    override func numberOfSections(in t: UITableView) -> Int { 2 }
    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { s == 0 ? max(1, names.count) : actions.count }
    override func tableView(_ t: UITableView, titleForHeaderInSection s: Int) -> String? { s == 0 ? "Saved shows" : nil }
    override func tableView(_ t: UITableView, titleForFooterInSection s: Int) -> String? { s == 0 ? "A show keeps its decks and where they sit. The Companion it joins is found again at each venue." : nil }
    override func tableView(_ t: UITableView, cellForRowAt i: IndexPath) -> UITableViewCell {
        if i.section == 0 {
            guard !names.isEmpty else { let c = cell("No saved shows yet"); c.selectionStyle = .none; return c }
            let c = checked(cell(names[i.row]), names[i.row] == now)
            if var conf = c.contentConfiguration as? UIListContentConfiguration { conf.textProperties.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: rajdhani(19)); c.contentConfiguration = conf }
            return c
        }
        let a = actions[i.row]
        return cell(a.0, tint: a.2 ? .systemRed : runGreen)
    }
    override func tableView(_ t: UITableView, didSelectRowAt i: IndexPath) {
        t.deselectRow(at: i, animated: true)
        if i.section == 0, i.row < names.count { owner.feel(); owner.cmd("open", names[i.row]) }
        if i.section == 1 { owner.cmd(actions[i.row].1) }
    }
}
