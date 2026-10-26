import Foundation
import Testing
@testable import GlassMonitor

@Suite struct ClaudeUsageWindow {
    /// "2026-10-26T15:00:00" for a moment `offset` seconds from now, UTC, without zone or fraction.
    private func stamp(_ offset: TimeInterval) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return String(f.string(from: Date().addingTimeInterval(offset)).dropLast())   // drop "Z"
    }

    @Test(arguments: ["Z", "+00:00", ".123Z", ".123456+00:00"])
    func parsesResetFormats(_ suffix: String) throws {
        let w = try #require(ClaudeUsage.window(["utilization": 14.0, "resets_at": stamp(3600) + suffix]))
        #expect(w.percent == 14)
        #expect(abs(w.resetsAt.timeIntervalSinceNow - 3600) < 5)
    }

    @Test func pastResetMeansNoWindow() {
        #expect(ClaudeUsage.window(["utilization": 99.0, "resets_at": stamp(-60) + "Z"]) == nil)
    }

    @Test func missingFieldsMeanNoWindow() {
        #expect(ClaudeUsage.window(nil) == nil)
        #expect(ClaudeUsage.window(["utilization": 10.0]) == nil)
        #expect(ClaudeUsage.window(["resets_at": stamp(3600) + "Z"]) == nil)
    }
}
