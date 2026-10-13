// Default handler for magnet links and .torrent files on zakkart: hands each
// one to qBittorrent on artemis and reports the result as a notification.
import AppKit

let endpoint = URL(string: Bundle.main.object(forInfoDictionaryKey: "QBittorrentURL") as! String)!
    .appendingPathComponent("api/v2/torrents/add")

func notify(_ title: String, _ body: String) {
    let quote = { (s: String) in "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", "display notification \(quote(body)) with title \(quote(title))"]
    try? p.run()
    p.waitUntilExit()
}

func multipart(_ boundary: String, name: String, filename: String?, data: Data) -> Data {
    var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"".utf8)
    if let filename { body.append(Data("; filename=\"\(filename)\"\r\nContent-Type: application/x-bittorrent".utf8)) }
    body.append(Data("\r\n\r\n".utf8))
    body.append(data)
    body.append(Data("\r\n--\(boundary)--\r\n".utf8))
    return body
}

func send(_ url: URL) async -> String? {
    let boundary = UUID().uuidString
    var req = URLRequest(url: endpoint, timeoutInterval: 15)
    req.httpMethod = "POST"
    req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    if url.isFileURL {
        guard let data = try? Data(contentsOf: url) else { return "cannot read \(url.lastPathComponent)" }
        req.httpBody = multipart(boundary, name: "torrents", filename: url.lastPathComponent, data: data)
    } else {
        req.httpBody = multipart(boundary, name: "urls", filename: nil, data: Data(url.absoluteString.utf8))
    }
    do {
        let (data, resp) = try await URLSession.shared.data(for: req)
        let text = String(decoding: data, as: UTF8.self)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, text != "Fails." else {
            return "qBittorrent refused it: \(text.isEmpty ? "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)" : text)"
        }
        return nil
    } catch {
        return "artemis is unreachable (is NetBird up?): \(error.localizedDescription)"
    }
}

func label(_ url: URL) -> String {
    if url.isFileURL { return url.lastPathComponent }
    let dn = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "dn" }?.value
    return dn ?? "magnet link"
}

final class Delegate: NSObject, NSApplicationDelegate {
    var pending = 0

    func application(_ app: NSApplication, open urls: [URL]) {
        for url in urls {
            pending += 1
            Task { @MainActor in
                if let err = await send(url) {
                    notify("Not sent to artemis", "\(label(url)): \(err)")
                } else {
                    notify("Sent to artemis", label(url))
                }
                self.pending -= 1
                self.quitIfIdle()
            }
        }
    }

    // Launched without a link (opened by hand): there is nothing to do.
    func applicationDidFinishLaunching(_: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.quitIfIdle() }
    }

    func quitIfIdle() {
        if pending == 0 { NSApp.terminate(nil) }
    }
}

let delegate = Delegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
