import AppKit

/// The mascot face (two tall eyes + a smile) drawn as vectors, shared by the menu-bar icon and the app icon.
enum FaceIcon {
    /// blink: 1 = open … 0 = closed. look: -1 … 1 shifts the eyes sideways.
    static func draw(in r: CGRect, blink: CGFloat = 1, look: CGFloat = 0, color: NSColor, smile: Bool = true) {
        let k = min(r.width / 100, r.height / 70)
        let ox = r.midX - 50 * k, oy = r.midY - 35 * k
        color.setFill(); color.setStroke()

        let w: CGFloat = 22, fullH: CGFloat = 34, cy: CGFloat = 23
        let h = max(fullH * blink, 4)
        for x0: CGFloat in [14, 64] {
            let rect = CGRect(x: ox + (x0 + look * 4) * k, y: oy + (70 - (cy + h / 2)) * k, width: w * k, height: h * k)
            NSBezierPath(roundedRect: rect, xRadius: min(w, h) * 0.42 * k, yRadius: min(w, h) * 0.42 * k).fill()
        }
        guard smile else { return }
        let m = NSBezierPath()
        m.move(to: NSPoint(x: ox + 37 * k, y: oy + (70 - 51) * k))
        m.curve(to: NSPoint(x: ox + 63 * k, y: oy + (70 - 51) * k),
                controlPoint1: NSPoint(x: ox + 42 * k, y: oy + (70 - 61) * k),
                controlPoint2: NSPoint(x: ox + 58 * k, y: oy + (70 - 61) * k))
        m.lineWidth = 3.4 * k; m.lineCapStyle = .round
        m.stroke()
    }

    /// Just the two eyes, close together, for the menu bar.
    static func drawEyesOnly(in r: CGRect, blink: CGFloat, look: CGFloat, color: NSColor) {
        let k = min(r.width / 54, r.height / 34)
        let ox = r.midX - 27 * k, oy = r.midY - 17 * k
        color.setFill()
        let w: CGFloat = 22, h = max(34 * blink, 4)
        for x0: CGFloat in [0, 32] {
            let rect = CGRect(x: ox + (x0 + look * 3) * k, y: oy + (17 - h / 2) * k, width: w * k, height: h * k)
            NSBezierPath(roundedRect: rect, xRadius: min(w, h) * 0.42 * k, yRadius: min(w, h) * 0.42 * k).fill()
        }
    }

    /// Menu-bar image (template, so macOS tints it for light/dark bars).
    static func menuBar(blink: CGFloat, look: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: 28, height: 18), flipped: false) { rect in
            drawEyesOnly(in: rect.insetBy(dx: 2, dy: 2), blink: blink, look: look, color: .black)
            return true
        }
        img.isTemplate = true
        return img
    }

    static func appIcon(pixels: Int) -> NSBitmapImageRep {
        let s = CGFloat(pixels)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let body = CGRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)
        let shape = NSBezierPath(roundedRect: body, xRadius: s * 0.18, yRadius: s * 0.18)
        NSColor.black.setFill(); shape.fill()
        NSColor(white: 1, alpha: 0.14).setStroke()
        shape.lineWidth = s * 0.004; shape.stroke()
        drawEyesOnly(in: body.insetBy(dx: s * 0.2, dy: s * 0.24), blink: 1, look: 0, color: .white)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
