import Foundation

/// Reads the plan limits (5-hour and 7-day windows) that Claude Code itself shows in /usage.
/// Uses the OAuth token Claude Code keeps in the macOS Keychain; the token never leaves
/// the Mac except in the request to api.anthropic.com. This endpoint is undocumented and may change.
enum ClaudeUsage {
    private static var token: (value: String, expires: Date)?

    /// Tries the usage endpoint first; if it is rate-limited (429) falls back to reading the
    /// rate-limit headers of a 1-token request, which is where Claude Code gets the same numbers.
    static func fetch() -> Monitor.ClaudeLimits? {
        for attempt in 0..<2 {
            guard let tok = currentToken(forceReload: attempt > 0) else { return nil }
            let usage = request(usageRequest(tok))
            if usage.status == 401 { token = nil; continue }   // token rotated, re-read the Keychain once
            if usage.status == 200, let data = usage.data,
               let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                return Monitor.ClaudeLimits(fiveHour: window(root["five_hour"]), sevenDay: window(root["seven_day"]))
            }
            let probe = request(probeRequest(tok))
            if probe.status == 401 { token = nil; continue }
            guard probe.status == 200, let h = probe.headers else { return nil }
            return Monitor.ClaudeLimits(fiveHour: headerWindow(h, "5h"), sevenDay: headerWindow(h, "7d"))
        }
        return nil
    }

    private static func usageRequest(_ tok: String) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 10)
        req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        return req
    }

    private static func probeRequest(_ tok: String) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001", "max_tokens": 1,
            "system": "You are Claude Code, Anthropic's official CLI for Claude.",
            "messages": [["role": "user", "content": "hi"]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    private static func request(_ req: URLRequest) -> (status: Int, data: Data?, headers: HTTPURLResponse?) {
        let sem = DispatchSemaphore(value: 0)
        var out: (Int, Data?, HTTPURLResponse?) = (0, nil, nil)
        URLSession.shared.dataTask(with: req) { d, r, _ in
            let h = r as? HTTPURLResponse
            out = (h?.statusCode ?? 0, d, h); sem.signal()
        }.resume()
        sem.wait()
        return out
    }

    /// Headers carry utilization as a 0…1 fraction and the reset as epoch seconds.
    private static func headerWindow(_ r: HTTPURLResponse, _ name: String) -> Monitor.ClaudeWindow? {
        guard let u = r.value(forHTTPHeaderField: "anthropic-ratelimit-unified-\(name)-utilization").flatMap(Double.init),
              let t = r.value(forHTTPHeaderField: "anthropic-ratelimit-unified-\(name)-reset").flatMap(Double.init),
              Date(timeIntervalSince1970: t) > Date() else { return nil }
        return Monitor.ClaudeWindow(percent: u * 100, resetsAt: Date(timeIntervalSince1970: t))
    }

    private static func window(_ any: Any?) -> Monitor.ClaudeWindow? {
        guard let w = any as? [String: Any], let pct = w["utilization"] as? Double,
              let str = w["resets_at"] as? String, let date = parse(str), date > Date() else { return nil }
        return Monitor.ClaudeWindow(percent: pct, resetsAt: date)
    }

    private static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        // microsecond precision isn't always accepted; drop the fraction
        let trimmed = s.replacingOccurrences(of: "\\.\\d+", with: "", options: .regularExpression)
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: trimmed)
    }

    private static func currentToken(forceReload: Bool) -> String? {
        if !forceReload, let t = token, t.expires > Date().addingTimeInterval(60) { return t.value }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let o = root["claudeAiOauth"] as? [String: Any],
              let value = o["accessToken"] as? String else { return nil }
        let exp = (o["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantPast
        guard exp > Date() else { return nil }   // Claude Code refreshes it when you use it
        token = (value, exp)
        return value
    }
}
