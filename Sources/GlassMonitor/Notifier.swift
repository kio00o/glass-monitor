import Foundation
import UserNotifications

/// macOS notifications when Claude plan usage first crosses 20 / 40 / 80 % in a window.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    nonisolated static let thresholds = [20, 40, 80]

    func setup() {
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // Show banners even while the app is "active" (it has no Dock presence, so it often is).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound])
    }

    func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "Claude 5-hour session: 40% used"
        content.body = "Test notification · this is how limit alerts will look"
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "claude-test-\(Date().timeIntervalSince1970)",
                                                                     content: content, trigger: nil))
    }

    func check(_ limits: Monitor.ClaudeLimits) {
        handle(limits.fiveHour, key: "five", name: "5-hour session")
        handle(limits.sevenDay, key: "seven", name: "weekly limit")
    }

    private func handle(_ w: Monitor.ClaudeWindow?, key: String, name: String) {
        guard let w else { return }
        let d = UserDefaults.standard
        let stateKey = "notify.\(key)"
        let state = d.dictionary(forKey: stateKey)
        let reset = Int((w.resetsAt.timeIntervalSince1970 / 60).rounded())
        let r = Self.decide(percent: w.percent, reset: reset, prevReset: state?["reset"] as? Int,
                            fired: Set((state?["fired"] as? [Int]) ?? []))
        if let top = r.announce { send(threshold: top, window: w, name: name, key: key) }
        d.set(["reset": reset, "fired": Array(r.fired)], forKey: stateKey)
    }

    /// `reset` is the window's reset time in minutes; resets within 10 min of the stored one are the same window.
    /// Returns the threshold to announce (if any) and the thresholds to remember as already crossed.
    nonisolated static func decide(percent: Double, reset: Int, prevReset: Int?, fired: Set<Int>) -> (announce: Int?, fired: Set<Int>) {
        let crossed = thresholds.filter { percent >= Double($0) }
        // new window or first run: what's already crossed isn't news
        guard let prevReset, abs(prevReset - reset) <= 10 else { return (nil, Set(crossed)) }
        // same window: announce only the highest threshold newly crossed
        return (crossed.filter { !fired.contains($0) }.max(), fired.union(crossed))
    }

    private func send(threshold: Int, window w: Monitor.ClaudeWindow, name: String, key: String) {
        let mins = max(0, Int(w.resetsAt.timeIntervalSinceNow / 60))
        let left = mins >= 1440 ? "\(mins / 1440)d \((mins % 1440) / 60)h" : mins >= 60 ? "\(mins / 60)h \(mins % 60)m" : "\(mins)m"
        let content = UNMutableNotificationContent()
        content.title = "Claude \(name): \(threshold)% used"
        content.body = "Now at \(Int(w.percent.rounded()))% · resets in \(left)"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "claude-\(key)-\(threshold)-\(Int(Date().timeIntervalSince1970))",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
