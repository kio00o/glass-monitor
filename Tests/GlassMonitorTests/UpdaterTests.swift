import Foundation
import Testing
@testable import GlassMonitor

@Suite struct UpdaterParse {
    private func json(_ tag: String, assets: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "assets": assets])
    }

    private func dmg(_ url: String, size: Int = 12_345) -> [String: Any] {
        ["name": "GlassMonitor.dmg", "browser_download_url": url, "size": size]
    }

    private let good = "https://github.com/kio00o/glass-monitor/releases/download/v1.6.2/GlassMonitor.dmg"

    @Test func readsTagAndDmg() throws {
        let r = try #require(Updater.parse(json("v1.6.2", assets: [dmg(good)])))
        #expect(r.version == "1.6.2")
        #expect(r.dmg.absoluteString == good)
        #expect(r.bytes == 12_345)
    }

    @Test func tagWithoutV() throws {
        let r = try #require(Updater.parse(json("1.6.2", assets: [dmg(good)])))
        #expect(r.version == "1.6.2")
    }

    @Test func skipsOtherAssets() throws {
        let notes = ["name": "notes.txt", "browser_download_url": "https://github.com/kio00o/glass-monitor/releases/download/v1.6.2/notes.txt"]
        let r = try #require(Updater.parse(json("v1.6.2", assets: [notes, dmg(good)])))
        #expect(r.dmg.lastPathComponent == "GlassMonitor.dmg")
    }

    @Test func rejectsMissingDmg() {
        #expect(Updater.parse(json("v1.6.2", assets: [])) == nil)
    }

    @Test func rejectsNonNumericTag() {
        #expect(Updater.parse(json("nightly", assets: [dmg(good)])) == nil)
        #expect(Updater.parse(json("v1.6.2-beta", assets: [dmg(good)])) == nil)
    }

    @Test func rejectsForeignDownloadURL() {
        #expect(Updater.parse(json("v1.6.2", assets: [dmg("http://github.com/kio00o/glass-monitor/releases/download/v1.6.2/GlassMonitor.dmg")])) == nil)
        #expect(Updater.parse(json("v1.6.2", assets: [dmg("https://evil.example/GlassMonitor.dmg")])) == nil)
        #expect(Updater.parse(json("v1.6.2", assets: [dmg("https://github.com/other/repo/releases/download/v1.6.2/GlassMonitor.dmg")])) == nil)
        #expect(Updater.parse(json("v1.6.2", assets: [dmg("https://github.com.evil/kio00o/glass-monitor/releases/download/v1.6.2/GlassMonitor.dmg")])) == nil)
    }

    @Test func rejectsMismatchedTagInURL() {
        let old = "https://github.com/kio00o/glass-monitor/releases/download/v1.0.0/GlassMonitor.dmg"
        #expect(Updater.parse(json("v99.0.0", assets: [dmg(old)])) == nil)
    }

    @Test func rejectsMissingOrHugeSize() {
        #expect(Updater.parse(json("v1.6.2", assets: [dmg(good, size: 0)])) == nil)
        #expect(Updater.parse(json("v1.6.2", assets: [dmg(good, size: 200_000_000)])) == nil)
        #expect(Updater.parse(json("v1.6.2", assets: [["name": "GlassMonitor.dmg", "browser_download_url": good]])) == nil)
    }

    @Test func rejectsGarbage() {
        #expect(Updater.parse(Data("{}".utf8)) == nil)
        #expect(Updater.parse(Data("not json".utf8)) == nil)
    }

    @Test func allowsGitHubCdnHosts() {
        #expect(Updater.allowedDownloadHost(URL(string: "https://github.com/kio00o/glass-monitor/releases/download/v1/GlassMonitor.dmg")!))
        #expect(Updater.allowedDownloadHost(URL(string: "https://objects.githubusercontent.com/foo")!))
        #expect(Updater.allowedDownloadHost(URL(string: "https://release-assets.githubusercontent.com/foo")!))
        #expect(Updater.allowedDownloadHost(URL(string: "https://github-releases.githubusercontent.com/foo")!))
        #expect(!Updater.allowedDownloadHost(URL(string: "http://github.com/foo")!))
        #expect(!Updater.allowedDownloadHost(URL(string: "https://evil.example/GlassMonitor.dmg")!))
        #expect(!Updater.allowedDownloadHost(URL(string: "https://githubusercontent.com.evil.example/foo")!))
    }
}

@Suite struct UpdaterVersion {
    @Test func newerRelease() {
        #expect(Updater.isNewer("1.6.2", than: "1.6.1"))
        #expect(Updater.isNewer("1.7.0", than: "1.6.9"))
        #expect(Updater.isNewer("2.0.0", than: "1.9.9"))
        #expect(Updater.isNewer("1.10.0", than: "1.9.0"))
        #expect(Updater.isNewer("1.6.1", than: "1.6"))
    }

    @Test func notNewer() {
        #expect(!Updater.isNewer("1.6.1", than: "1.6.1"))
        #expect(!Updater.isNewer("1.6.0", than: "1.6.1"))
        #expect(!Updater.isNewer("1.6", than: "1.6.0"))
        #expect(!Updater.isNewer("1.6.1", than: "dev"))
        #expect(!Updater.isNewer("nope", than: "1.6.1"))
        #expect(!Updater.isNewer("1..2", than: "1.0.0"))
    }

    @Test func notifyOncePerVersion() {
        #expect(Updater.shouldNotify(version: "1.6.2", lastNotified: nil))        // never announced
        #expect(!Updater.shouldNotify(version: "1.6.2", lastNotified: "1.6.2"))   // already announced this one
        #expect(Updater.shouldNotify(version: "1.6.3", lastNotified: "1.6.2"))    // a later version announces again
    }
}
