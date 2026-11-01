// Finds Downstage Ones over Bonjour for the Mac and iOS apps: a web page can't ask the network who is there.
import Foundation

final class OneFinder: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    let browser = NetServiceBrowser()
    var services: [NetService] = []
    var names: [String: String] = [:]      // by address: what each One calls itself. It can be renamed at any time
    var changed: ([[String: String]]) -> Void = { _ in }

    func start() {
        browser.delegate = self
        browser.searchForServices(ofType: "_downstage._tcp.", inDomain: "local.")
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
