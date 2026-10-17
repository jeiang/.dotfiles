// Default handler for magnet links and .torrent files on zakkart: opens atrium's
// add page in the default browser, which asks whether to file it in the library.
import AppKit

let atrium = Bundle.main.object(forInfoDictionaryKey: "AtriumURL") as! String

// Characters left unescaped must be safe inside a query value or fragment.
let valueAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

func encode(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: valueAllowed) ?? s
}

func base64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

// The torrent bytes ride in the fragment so no server or proxy log sees them.
func addPage(for url: URL) -> URL? {
    if url.isFileURL {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return URL(string: "\(atrium)/media/add#torrent=\(base64url(data))&name=\(encode(url.lastPathComponent))")
    }
    return URL(string: "\(atrium)/media/add?magnet=\(encode(url.absoluteString))")
}

func notify(_ title: String, _ body: String) {
    let quote = { (s: String) in "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", "display notification \(quote(body)) with title \(quote(title))"]
    try? p.run()
    p.waitUntilExit()
}

final class Delegate: NSObject, NSApplicationDelegate {
    func application(_ app: NSApplication, open urls: [URL]) {
        for url in urls {
            if let page = addPage(for: url) {
                NSWorkspace.shared.open(page)
            } else {
                notify("Not sent to atrium", "cannot read \(url.lastPathComponent)")
            }
        }
        // Let LaunchServices finish handing the URL to the browser.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
    }

    // Launched without a link (opened by hand): there is nothing to do.
    func applicationDidFinishLaunching(_: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
    }
}

let delegate = Delegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
