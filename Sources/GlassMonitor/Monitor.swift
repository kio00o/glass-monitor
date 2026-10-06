import SwiftUI
import CoreLocation

@MainActor
final class Monitor: ObservableObject {
    enum SpeedTest: Equatable { case idle, running, done(down: Double, up: Double), failed }

    @Published var volumeName = "Macintosh HD"
    @Published var disk = Sensors.Disk(available: 0, total: 0)
    @Published var memoryPressure = 0
    @Published var battery = Sensors.Battery(percent: 0, charging: false, minutes: nil, present: true)
    @Published var cpuLoad = 0.0
    @Published var cpuTemp: Double?
    @Published var ssid: String?
    @Published var down = 0.0
    @Published var up = 0.0
    @Published var devices: [Sensors.Device] = []
    @Published var audioPlaying = false
    @Published var speedTest: SpeedTest = .idle { didSet { onSpeedTest?(speedTest) } }
    var onSpeedTest: ((SpeedTest) -> Void)?

    struct ClaudeWindow { var percent: Double; var resetsAt: Date }
    struct ClaudeLimits { var fiveHour: ClaudeWindow?; var sevenDay: ClaudeWindow? }
    @Published var claude: ClaudeLimits?
    enum Page { case main, network, claude }
    @Published var page: Page = .main
    @Published var downHistory = [Double](repeating: 0, count: 40)
    @Published var upHistory = [Double](repeating: 0, count: 40)
    @Published var totalDown: UInt64 = 0
    @Published var totalUp: UInt64 = 0
    @Published var security = ""
    @Published var linkRate = 0

    private var timer: Timer?

    // Spotify announces play-state changes; paused apps still keep the audio device open,
    // so the device alone can't tell "paused" from "playing".
    private static let players: [(bundle: String, notification: String)] = [
        ("com.spotify.client", "com.spotify.client.PlaybackStateChanged"),
    ]
    private var playerState: [String: String] = [:]    // bundle id → "Playing" / "Paused" / "Stopped"
    private let location = CLLocationManager()

    init() {
        for p in Self.players {
            DistributedNotificationCenter.default().addObserver(forName: Notification.Name(p.notification),
                                                                object: nil, queue: .main) { [weak self] n in
                let state = n.userInfo?["Player State"] as? String ?? n.userInfo?["PlayerState"] as? String
                MainActor.assumeIsolated {
                    self?.playerState[p.bundle] = state
                    self?.updateAudio()
                }
            }
        }
        loadClaudeCache()
        location.requestWhenInUseAuthorization() // macOS hides the SSID without it
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func updateAudio() {
        // Only trust a player's last announcement while that app is still running.
        let known = Self.players.compactMap { p -> String? in
            NSRunningApplication.runningApplications(withBundleIdentifier: p.bundle).isEmpty ? nil : playerState[p.bundle]
        }
        if known.contains("Playing") { audioPlaying = true }
        else if !known.isEmpty { audioPlaying = false }     // a player says paused/stopped
        else { audioPlaying = Sensors.audioPlaying() }      // no player info: fall back to the audio device
    }

    func refresh() {
        volumeName = Sensors.volumeName()
        disk = Sensors.disk()
        memoryPressure = Sensors.memoryPressure()
        battery = Sensors.battery()
        cpuLoad = Sensors.cpuLoad()
        cpuTemp = Sensors.cpuTemperature()
        ssid = Sensors.ssid()
        let t = Sensors.throughput()
        down = t.down; up = t.up
        downHistory.removeFirst(); downHistory.append(t.down)
        upHistory.removeFirst(); upHistory.append(t.up)
        totalDown = Sensors.totalRx; totalUp = Sensors.totalTx
        security = Sensors.security(); linkRate = Sensors.linkRate()
        devices = Sensors.bluetoothDevices()
        updateAudio()
        refreshClaude()
    }

    /// Uses Apple's built-in `networkQuality` tool.
    func runSpeedTest() {
        guard speedTest != .running else { return }
        speedTest = .running
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
            p.arguments = ["-c"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            var result: SpeedTest = .failed
            do {
                try p.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let d = j["dl_throughput"] as? Double, let u = j["ul_throughput"] as? Double {
                    result = .done(down: d / 8, up: u / 8) // bits → bytes
                }
            } catch {}
            let final = result
            await MainActor.run { self.speedTest = final }
        }
    }

    // MARK: Claude plan limits

    // The usage endpoint rate-limits hard (429), so poll rarely, back off on failure,
    // and keep the last good value on disk so the card isn't empty after a relaunch.
    private static let cacheKey = "claudeLimitsCache"
    private var nextClaudeFetch = Date.distantPast
    private var claudeInterval: TimeInterval = 300
    private var fetchingClaude = false

    private func loadClaudeCache() {
        guard let d = UserDefaults.standard.dictionary(forKey: Self.cacheKey) else { return }
        func win(_ k: String) -> ClaudeWindow? {
            guard let p = d["\(k)Pct"] as? Double, let r = d["\(k)Reset"] as? Double,
                  Date(timeIntervalSince1970: r) > Date() else { return nil }
            return ClaudeWindow(percent: p, resetsAt: Date(timeIntervalSince1970: r))
        }
        claude = ClaudeLimits(fiveHour: win("five"), sevenDay: win("seven"))
        if let t = d["fetchedAt"] as? Double { nextClaudeFetch = Date(timeIntervalSince1970: t + claudeInterval) }
    }

    private func saveClaudeCache(_ c: ClaudeLimits) {
        var d: [String: Double] = ["fetchedAt": Date().timeIntervalSince1970]
        if let w = c.fiveHour { d["fivePct"] = w.percent; d["fiveReset"] = w.resetsAt.timeIntervalSince1970 }
        if let w = c.sevenDay { d["sevenPct"] = w.percent; d["sevenReset"] = w.resetsAt.timeIntervalSince1970 }
        UserDefaults.standard.set(d, forKey: Self.cacheKey)
    }

    private func refreshClaude() {
        guard !fetchingClaude, Date() >= nextClaudeFetch else { return }
        fetchingClaude = true
        Task.detached {
            let result = ClaudeUsage.fetch()
            await MainActor.run {
                self.fetchingClaude = false
                if let result {
                    self.claude = result
                    self.saveClaudeCache(result)
                    Notifier.shared.check(result)
                    self.claudeInterval = 300
                } else {
                    self.claudeInterval = min(self.claudeInterval * 2, 1800)   // 5 → 10 → 20 → 30 min
                }
                self.nextClaudeFetch = Date().addingTimeInterval(self.claudeInterval)
            }
        }
    }

    func openNetwork() {
        page = .network
        if speedTest == .idle { runSpeedTest() }
    }

    func openStorage() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!)
    }

    func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }
}
