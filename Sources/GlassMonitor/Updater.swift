import AppKit
import Combine

/// In-app update from GitHub Releases: check `/releases/latest`, and on click replace this
/// `.app` with the `GlassMonitor.dmg` from that release, then relaunch.
@MainActor
final class Updater: ObservableObject {
    struct Release: Equatable, Sendable {
        var version: String
        var dmg: URL
        var bytes: Int
    }

    /// Set when GitHub has a newer tag than `CFBundleShortVersionString`; drives the menu item.
    @Published private(set) var available: String?
    @Published private(set) var installing = false
    @Published private(set) var failed = false

    private var release: Release?
    private var timer: Timer?

    private static let api = URL(string: "https://api.github.com/repos/kio00o/glass-monitor/releases/latest")!
    nonisolated private static let bundleId = "dev.local.glassmonitor"
    nonisolated private static let userAgent = "GlassMonitor (github.com/kio00o/glass-monitor)"
    /// Current release DMG is ~5 MB; anything much larger is not our asset.
    nonisolated private static let maxDmgBytes = 80_000_000

    /// Ephemeral: the default session caches HTTPS GETs and has a 7-day resource timeout.
    nonisolated private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 120
        c.httpCookieAcceptPolicy = .never
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    func start() {
        guard Bundle.main.bundleIdentifier == Self.bundleId else { return }
        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    func install() {
        guard !installing else { return }
        failed = false
        #if DEBUG
        guard available != nil else { return }
        installing = true
        Task { try? await Task.sleep(for: .seconds(1)); self.installing = false }
        #else
        guard let r = release else { return }
        installing = true
        Task.detached {
            let ok = Self.replace(with: r)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard ok else { self.installing = false; self.failed = true; return }
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.createsNewApplicationInstance = true   // without -n, Launch Services activates this process, then terminate leaves nothing running
                NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { [weak self] _, err in
                    Task { @MainActor in
                        guard let self else { return }
                        guard err == nil else { self.installing = false; self.failed = true; return }
                        NSApp.terminate(nil)
                    }
                }
            }
        }
        #endif
    }

    #if DEBUG
    /// Debug menu: show (or hide) "Update to 9.9.9" without talking to GitHub.
    func simulate(_ on: Bool) {
        failed = false
        if on, let url = Self.dmgURL("https://github.com/kio00o/glass-monitor/releases/download/v9.9.9/GlassMonitor.dmg", tag: "v9.9.9") {
            release = Release(version: "9.9.9", dmg: url, bytes: 1)
            available = "9.9.9"
        } else {
            release = nil
            available = nil
        }
    }
    #endif

    // MARK: Check

    private func check() async {
        var req = URLRequest(url: Self.api, timeoutInterval: 10)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await Self.session.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme?.lowercased() == "https",
              http.url?.host?.lowercased() == "api.github.com",
              let rel = Self.parse(data) else { return }   // keep last good offer on failure
        if Self.isNewer(rel.version, than: Self.currentVersion()) {
            release = rel
            available = rel.version
        } else {
            release = nil
            available = nil
        }
    }

    nonisolated static func currentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// GitHub `GET /releases/latest` body; nil unless there is a `GlassMonitor.dmg` on our repo
    /// whose download path tag matches `tag_name` (so a v99 JSON cannot point at an old DMG).
    nonisolated static func parse(_ data: Data) -> Release? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = root["tag_name"] as? String,
              let version = normalized(tag),
              let assets = root["assets"] as? [[String: Any]] else { return nil }
        for a in assets {
            guard (a["name"] as? String) == "GlassMonitor.dmg",
                  let raw = a["browser_download_url"] as? String,
                  let url = dmgURL(raw, tag: tag),
                  let bytes = a["size"] as? Int, bytes > 0, bytes <= maxDmgBytes else { continue }
            return Release(version: version, dmg: url, bytes: bytes)
        }
        return nil
    }

    /// Only our GitHub repo's `GlassMonitor.dmg` for this tag. A hostile JSON cannot point the download elsewhere.
    nonisolated static func dmgURL(_ raw: String, tag: String) -> URL? {
        guard let u = URL(string: raw), u.scheme?.lowercased() == "https",
              u.host?.lowercased() == "github.com",
              u.lastPathComponent == "GlassMonitor.dmg" else { return nil }
        let p = u.pathComponents   // ["/", "kio00o", "glass-monitor", "releases", "download", tag, "GlassMonitor.dmg"]
        guard p.count == 7, p[1] == "kio00o", p[2] == "glass-monitor",
              p[3] == "releases", p[4] == "download" else { return nil }
        let version = normalized(tag) ?? tag
        guard p[5] == tag || p[5] == version || p[5] == "v\(version)" else { return nil }
        return u
    }

    /// Final URL after GitHub's CDN redirect. Tests cover this; the download uses it on the response.
    nonisolated static func allowedDownloadHost(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com"
            || host == "objects.githubusercontent.com"
            || host == "github-releases.githubusercontent.com"
            || host == "release-assets.githubusercontent.com"
    }

    nonisolated static func normalized(_ tag: String) -> String? {
        let s = tag.first.map { $0 == "v" || $0 == "V" } == true ? String(tag.dropFirst()) : tag
        return versionParts(s) == nil ? nil : s
    }

    nonisolated static func isNewer(_ latest: String, than current: String) -> Bool {
        guard let a = versionParts(latest), let b = versionParts(current) else { return false }
        let n = max(a.count, b.count)
        let aa = a + Array(repeating: 0, count: n - a.count)
        let bb = b + Array(repeating: 0, count: n - b.count)
        return bb.lexicographicallyPrecedes(aa)
    }

    nonisolated static func versionParts(_ s: String) -> [Int]? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var nums: [Int] = []
        for p in parts {
            guard let n = Int(p), n >= 0 else { return nil }
            nums.append(n)
        }
        return nums
    }

    // MARK: Install

    #if !DEBUG
    /// Download, mount, verify bundle id + version, swap this `.app`, strip quarantine. False leaves the running app alone.
    nonisolated private static func replace(with rel: Release) -> Bool {
        guard Bundle.main.bundleIdentifier == bundleId else { return false }
        let dest = Bundle.main.bundleURL
        guard dest.pathExtension == "app" else { return false }
        let fm = FileManager.default
        let stamp = UUID().uuidString
        let tmp = fm.temporaryDirectory.appendingPathComponent("gm-update-\(stamp)", isDirectory: true)
        guard (try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)) != nil else { return false }
        defer { try? fm.removeItem(at: tmp) }
        let dmg = tmp.appendingPathComponent("GlassMonitor.dmg")
        guard download(rel.dmg, to: dmg, expected: rel.bytes) else { return false }
        let mount = tmp.appendingPathComponent("mnt", isDirectory: true)
        guard (try? fm.createDirectory(at: mount, withIntermediateDirectories: true)) != nil else { return false }
        guard run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mount.path]) == 0 else { return false }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"]) }
        let bundled = mount.appendingPathComponent("GlassMonitor.app")
        guard !((try? bundled.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false) else { return false }
        let info = bundled.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: info) as? [String: Any],
              dict["CFBundleIdentifier"] as? String == bundleId,
              let ver = dict["CFBundleShortVersionString"] as? String,
              normalized(ver) == rel.version,
              isNewer(ver, than: currentVersion()) else { return false }
        let unpacked = tmp.appendingPathComponent("GlassMonitor.app")
        guard (try? fm.copyItem(at: bundled, to: unpacked)) != nil else { return false }
        let staged = dest.deletingLastPathComponent().appendingPathComponent("GlassMonitor.app.new")
        try? fm.removeItem(at: staged)
        guard (try? fm.copyItem(at: unpacked, to: staged)) != nil else { return false }
        guard (try? fm.replaceItemAt(dest, withItemAt: staged)) != nil else {
            try? fm.removeItem(at: staged)
            return false
        }
        _ = run("/usr/bin/xattr", ["-cr", dest.path])
        return true
    }

    nonisolated private static func download(_ url: URL, to dest: URL, expected: Int) -> Bool {
        guard expected > 0, expected <= maxDmgBytes else { return false }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        session.downloadTask(with: req) { loc, resp, _ in
            defer { sem.signal() }
            // GitHub 302s the asset onto *.githubusercontent.com; a hostile redirect must not land elsewhere.
            guard let loc, let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let final = http.url, allowedDownloadHost(final) else { return }
            try? FileManager.default.removeItem(at: dest)
            guard (try? FileManager.default.moveItem(at: loc, to: dest)) != nil else { return }
            let n = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
            guard n == expected, n <= maxDmgBytes else { try? FileManager.default.removeItem(at: dest); return }
            ok = true
        }.resume()
        sem.wait()
        return ok
    }

    @discardableResult
    nonisolated private static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        let deadline = Date().addingTimeInterval(30)
        while p.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if p.isRunning { p.terminate(); p.waitUntilExit(); return -1 }
        return p.terminationStatus
    }
    #endif
}
