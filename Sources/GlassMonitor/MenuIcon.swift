import SwiftUI

/// Drives the animated menu-bar face: blinks every few seconds, sometimes glances left/right.
@MainActor
final class MenuIconModel: ObservableObject {
    @Published private(set) var image = FaceIcon.menuBar(blink: 1, look: 0)
    private var cache: [String: NSImage] = [:]
    private var current: (CGFloat, CGFloat) = (1, 0)

    /// Yellow eyes while there is an air-raid alert in the user's area.
    var alert = false {
        didSet { if alert != oldValue { show(current.0, current.1) } }
    }
    private static let yellow = NSColor(srgbRed: 1, green: 0.84, blue: 0.04, alpha: 1)

    init() { Task { await run() } }

    private func show(_ blink: CGFloat, _ look: CGFloat) {
        current = (blink, look)
        let key = "\(blink)|\(look)|\(alert)"
        if cache[key] == nil { cache[key] = FaceIcon.menuBar(blink: blink, look: look, tint: alert ? Self.yellow : nil) }
        image = cache[key]!
    }

    private func blink(look: CGFloat) async {
        for b: CGFloat in [0.55, 0.12, 0.55, 1] {
            show(b, look)
            try? await Task.sleep(for: .milliseconds(55))
        }
    }

    private func run() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 2.5...6)))
            let r = Int.random(in: 0..<10)
            if r < 2 {                                  // glance aside, then back
                let dir: CGFloat = Bool.random() ? 1 : -1
                show(1, dir)
                try? await Task.sleep(for: .seconds(0.9))
                await blink(look: dir)
                show(1, 0)
            } else {
                await blink(look: 0)
                if r < 4 { try? await Task.sleep(for: .milliseconds(120)); await blink(look: 0) }   // double blink
            }
        }
    }
}
