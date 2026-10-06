import SwiftUI
import ImageIO

/// A decoded GIF: white-on-transparent frames (luminance → alpha), cropped to the face area.
struct EyeClip {
    let frames: [CGImage]
    let ends: [Double]          // cumulative end time of each frame, seconds
    var total: Double { ends.last ?? 1 }

    func frame(at t: Double) -> CGImage {
        let t = min(max(t, 0), total - 0.001)
        let i = ends.firstIndex { $0 > t } ?? frames.count - 1
        return frames[i]
    }
}

enum EyeLoader {
    // Taby art is 280×456 with the face rotated 90°; keep only the face area.
    static let cropX = 0, cropY = 0, cropW = 256, cropH = 456

    static func load(_ name: String) -> EyeClip? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "gif", subdirectory: "Taby"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var frames: [CGImage] = [], ends: [Double] = []
        var unique: [Int: CGImage] = [:]
        var t = 0.0
        let cs = CGColorSpaceCreateDeviceRGB()

        for i in 0..<CGImageSourceGetCount(src) {
            guard let img = CGImageSourceCreateImageAtIndex(src, i, nil),
                  let ctx = CGContext(data: nil, width: cropW, height: cropH, bitsPerComponent: 8,
                                      bytesPerRow: cropW * 4, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { continue }
            ctx.draw(img, in: CGRect(x: -cropX, y: -(img.height - cropY - cropH), width: img.width, height: img.height))
            let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
            for k in stride(from: 0, to: cropW * cropH * 4, by: 4) {
                let r = p[k]; p[k + 1] = r; p[k + 2] = r; p[k + 3] = r
            }
            let key = Data(bytes: p, count: cropW * cropH * 4).hashValue
            let out = unique[key] ?? ctx.makeImage()!
            unique[key] = out

            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            var d = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0
            if d <= 0 { d = gif?[kCGImagePropertyGIFDelayTime] as? Double ?? 0.04 }
            t += max(d, 0.02)
            frames.append(out); ends.append(t)
        }
        return frames.isEmpty ? nil : EyeClip(frames: frames, ends: ends)
    }
}

@MainActor
final class EyesModel: ObservableObject {
    private(set) var clip: EyeClip?
    private(set) var clipStart = Date()
    private(set) var repeats = 1
    private var cache: [String: EyeClip] = [:]
    private var task: Task<Void, Never>?
    private var wasListening = false

    /// Return (clip, repeats) to override the random behaviour, e.g. angry when the CPU is stressed.
    var mood: () -> (String, Int)? = { nil }
    /// True while music/audio is playing; the mascot then wears headphones.
    var listening: () -> Bool = { false }

    private static let emotions: [(String, Int)] = [
        ("wow", 1), ("blush", 1), ("love_01", 1), ("thumbs_up", 1), ("yeah", 1),
        ("disappointed", 1), ("idle_variation_loop", 2), ("searching_loop", 2),
        ("relaxing_01_loop", 2), ("idle_02_loop", 1),
    ]

    func start() {
        guard task == nil else { return }
        task = Task { await loop() }
    }

    /// Tap on the panel: react right away.
    func poke() {
        task?.cancel()
        task = Task {
            if let e = Self.emotions.randomElement() { await play(e.0, e.1) }
            await loop()
        }
    }

    /// Speed test running: keep "thinking" until something else is requested.
    func think() {
        task?.cancel()
        task = Task { while !Task.isCancelled { await play("searching_loop", 1) } }
    }

    /// Speed test finished: celebrate (or sulk) once, then go back to normal.
    func finish(success: Bool) {
        task?.cancel()
        task = Task {
            await play(success ? ["yeah", "thumbs_up", "love_01"].randomElement()! : "disappointed", 1)
            await loop()
        }
    }

    /// Technical page: play an intro once, then repeat a loop until `resume()`.
    func hold(intro: String, loop name: String) {
        task?.cancel()
        task = Task {
            await play(intro, 1)
            while !Task.isCancelled { await play(name, 1) }
        }
    }

    /// Back to the normal idle behaviour.
    func resume() {
        task?.cancel()
        task = Task { await loop() }
    }

    private func loop() async {
        while !Task.isCancelled {
            let now = listening()
            if now != wasListening {                 // music just started or stopped
                wasListening = now
                await play(now ? "listening_in" : "wow", 1)   // headphones on / "huh, what?"
                continue
            }
            if now { await play("listening_music_loop", 1, interruptible: true); continue }
            await play("idle_01_loop", 1, interruptible: true)
            if let m = mood() { await play(m.0, m.1); continue }
            if Double.random(in: 0..<1) < 0.6, let e = Self.emotions.randomElement() {
                await play(e.0, e.1)
            }
        }
    }

    private func play(_ name: String, _ times: Int, interruptible: Bool = false) async {
        let c: EyeClip
        if let hit = cache[name] { c = hit }
        else if let loaded = await Task.detached(operation: { EyeLoader.load(name) }).value { c = loaded }
        else { try? await Task.sleep(for: .seconds(1)); return }
        if name != "idle_01_loop" && cache.count > 3 { cache = cache.filter { $0.key == "idle_01_loop" } }
        cache[name] = c
        guard !Task.isCancelled else { return }   // a newer request took over while this one was loading
        clip = c; repeats = times; clipStart = Date()
        let wasListening = listening()
        var remaining = c.total * Double(times)
        while remaining > 0 && !Task.isCancelled {
            let step = min(remaining, 0.4)
            try? await Task.sleep(for: .seconds(step))
            remaining -= step
            if interruptible && listening() != wasListening { return }   // music started/stopped
        }
    }

    func image(at date: Date) -> CGImage? {
        guard let c = clip else { return nil }
        let e = date.timeIntervalSince(clipStart)
        if e >= c.total * Double(repeats) { return c.frame(at: c.total) }   // hold last frame until next clip
        return c.frame(at: e.truncatingRemainder(dividingBy: c.total))
    }
}

struct EyesPanel: View {
    @EnvironmentObject var eyes: EyesModel

    var body: some View {
        GeometryReader { g in
            // rotated frame is cropH × cropW; fit it fully inside the card so nothing gets cut off
            let s = min(g.size.width / CGFloat(EyeLoader.cropH), g.size.height / CGFloat(EyeLoader.cropW))
            TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                if let img = eyes.image(at: ctx.date) {
                    Image(decorative: img, scale: 1)
                        .renderingMode(.template).resizable().interpolation(.high)
                        .foregroundStyle(Color.primary)
                        .frame(width: CGFloat(EyeLoader.cropW) * s, height: CGFloat(EyeLoader.cropH) * s)
                        .rotationEffect(.degrees(-90))
                        .frame(width: g.size.width, height: g.size.height)
                }
            }
        }
        .padding(6)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .contentShape(.rect(cornerRadius: 16))
        .onTapGesture { eyes.poke() }
    }
}
