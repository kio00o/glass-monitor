import SwiftUI

/// Drives the animated menu-bar face: blinks every few seconds, sometimes glances left/right.
@MainActor
final class MenuIconModel: ObservableObject {
    @Published private(set) var image = FaceIcon.menuBar(blink: 1, look: 0)
    private var cache: [String: NSImage] = [:]

    init() { Task { await run() } }

    private func show(_ blink: CGFloat, _ look: CGFloat) {
        let key = "\(blink)|\(look)"
        if cache[key] == nil { cache[key] = FaceIcon.menuBar(blink: blink, look: look) }
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
