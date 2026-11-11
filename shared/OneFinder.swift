// Finds Downstage Ones over Bonjour for the Mac and iOS apps: a web page can't ask the network who is there.
// With findCompanions on (the Mac app), it also finds every Companion that advertises its Satellite WebSocket.
import Foundation

final class OneFinder: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    let browser = NetServiceBrowser()
    var services: [NetService] = []
    var names: [String: String] = [:]      // by address: what each One calls itself. It can be renamed at any time
    var changed: ([[String: String]]) -> Void = { _ in }
    var findCompanions = false
    let companionBrowser = NetServiceBrowser()
    var companions: [NetService] = []
    var companionsChanged: ([[String: String]]) -> Void = { _ in }

    func start() {
        browser.delegate = self
        browser.searchForServices(ofType: "_downstage._tcp.", inDomain: "local.")
        if findCompanions {
            // Companion 4 and later advertise the port Virtual Deck joins on, 16623
            companionBrowser.delegate = self
            companionBrowser.searchForServices(ofType: "_companion-satellite-ws._tcp.", inDomain: "local.")
        }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.report() }
    }
    // Bonjour only carries the network name, like downstage-0001. The One's own page knows the name people gave it
    func askName(_ host: String, port: Int) {
        guard let u = URL(string: "http://\(host):\(port)/status") else { return }
        var r = URLRequest(url: u); r.timeoutInterval = 3
        URLSession.shared.dataTask(with: r) { data, _, _ in
            guard let data = data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let n = o["name"] as? String, !n.isEmpty else { return }
            DispatchQueue.main.async {
                if self.names[host] != n { self.names[host] = n; self.send() }
            }
        }.resume()
    }
    func netServiceBrowser(_ b: NetServiceBrowser, didFind s: NetService, moreComing: Bool) {
        if b === companionBrowser { companions.append(s) } else { services.append(s) }
        s.delegate = self
        s.resolve(withTimeout: 5)
    }
    func netServiceBrowser(_ b: NetServiceBrowser, didRemove s: NetService, moreComing: Bool) {
        services.removeAll { $0 == s }
        companions.removeAll { $0 == s }
        report()
    }
    func netServiceDidResolveAddress(_ s: NetService) { report() }

    func report() {
        send()
        for s in services { if let host = ipv4(s) { askName(host, port: s.port) } }
    }
    func send() {
        var out: [[String: String]] = []
        for s in services {
            guard let host = ipv4(s), let data = s.txtRecordData() else { continue }
            let txt = NetService.dictionary(fromTXTRecord: data).mapValues { String(decoding: $0, as: UTF8.self) }
            // only a One has a Companion. A One on v1.7.0 or older advertises its serial but no kind
            let serial = txt["serial"] ?? ""
            guard txt["kind"]?.lowercased() == "one" || serial.hasPrefix("DS1-") else { continue }
            out.append(["id": serial.isEmpty ? s.name : serial, "name": names[host] ?? txt["name"] ?? s.name, "host": host])
        }
        changed(out)
        guard findCompanions else { return }
        // "local" marks a Companion on this Mac, which the page joins at 127.0.0.1 so a new venue address doesn't matter
        let mine = localAddresses()
        var list: [[String: String]] = []
        for s in companions {
            guard let host = ipv4(s) else { continue }
            let txt = s.txtRecordData().map { NetService.dictionary(fromTXTRecord: $0).mapValues { String(decoding: $0, as: UTF8.self) } } ?? [:]
            list.append(["id": txt["id"] ?? s.name, "name": s.name, "host": host, "local": mine.contains(host) ? "1" : ""])
        }
        companionsChanged(list)
    }
    func localAddresses() -> Set<String> {
        var out: Set<String> = ["127.0.0.1"], head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return out }
        defer { freeifaddrs(head) }
        var p = head
        while let i = p {
            defer { p = i.pointee.ifa_next }
            guard let a = i.pointee.ifa_addr, a.pointee.sa_family == UInt8(AF_INET) else { continue }
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(a, socklen_t(a.pointee.sa_len), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 { out.insert(String(cString: buf)) }
        }
        return out
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

// Ticks "Allow page arrows" on one of our own surfaces, through the private connection Companion's web page uses. It refuses
// a page's origin, so this can only come from the app. If an update ever breaks it, the page tells the user where the box is
func allowPageArrows(host: String, surface: String) {
    guard let url = URL(string: "ws://\(host):8000/trpc"), let body = try? JSONSerialization.data(withJSONObject: [
        "id": 1, "jsonrpc": "2.0", "method": "mutation",
        "params": ["path": "surfaces.surfaceSetConfigKey", "input": ["surfaceId": surface, "key": "canChangePage", "value": true]],
    ] as [String: Any]) else { return }
    let socket = URLSession.shared.webSocketTask(with: url)
    socket.resume()
    socket.send(.string(String(decoding: body, as: UTF8.self))) { _ in }
    socket.receive { _ in socket.cancel(with: .normalClosure, reason: nil) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { socket.cancel(with: .normalClosure, reason: nil) }
}
