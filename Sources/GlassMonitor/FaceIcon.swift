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

    /// Just the two eyes, close together, for the menu bar. anger 0…1 (air-raid alert): the eyes sink lower,
    /// their inner top corners drop into a frown, and a translucent plate stays where each eye used to be.
    static func drawEyesOnly(in r: CGRect, blink: CGFloat, look: CGFloat, color: NSColor, anger: CGFloat = 0) {
        let k = min(r.width / 54, r.height / 34)
        let ox = r.midX - 27 * k, oy = r.midY - 17 * k
        let w: CGFloat = 22
        for (i, x0) in [CGFloat(0), 32].enumerated() {
            let x = ox + (x0 + look * 3) * k
            if anger > 0 {                                   // ghost plate in the old place
                color.withAlphaComponent(0.3 * anger).setFill()
                NSBezierPath(roundedRect: CGRect(x: x, y: oy, width: w * k, height: 34 * k),
                             xRadius: w * 0.42 * k, yRadius: w * 0.42 * k).fill()
            }
            let fullH = 34 - 10 * anger                      // lowered: the top comes down, the bottom stays
            let h = max(fullH * blink, 4)
            let rect = CGRect(x: x, y: oy + (fullH / 2 - h / 2) * k, width: w * k, height: h * k)
            NSGraphicsContext.saveGraphicsState()
            if anger > 0 {                                   // frown: cut the inner top corner
                let inner = i == 0 ? rect.maxX : rect.minX, outer = i == 0 ? rect.minX : rect.maxX
                let drop = min(9 * anger * k, rect.height * 0.55)
                let clip = NSBezierPath()
                clip.move(to: NSPoint(x: outer, y: rect.minY - 1))
                clip.line(to: NSPoint(x: inner, y: rect.minY - 1))
                clip.line(to: NSPoint(x: inner, y: rect.maxY - drop))
                clip.line(to: NSPoint(x: outer, y: rect.maxY + 1))
                clip.close(); clip.addClip()
            }
            color.setFill()
            let rad = min(w, h) * 0.42 * k
            NSBezierPath(roundedRect: rect, xRadius: rad, yRadius: rad).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// Menu-bar image (template, so macOS tints it for light/dark bars). The red update dot is a
    /// separate coloured subview on the status button, so the eyes keep adapting to the bar.
    static func menuBar(blink: CGFloat, look: CGFloat, anger: CGFloat = 0) -> NSImage {
        let img = NSImage(size: NSSize(width: 28, height: 18), flipped: false) { rect in
            drawEyesOnly(in: rect.insetBy(dx: 2, dy: 2), blink: blink, look: look, color: .black, anger: anger)
            return true
        }
        img.isTemplate = true
        return img
    }

    static let alertColor = NSColor(srgbRed: 1, green: 0.84, blue: 0.04, alpha: 1)   // yellow

    /// Shahed-style delta-wing drone seen from above, for air-raid alerts (coloured, not a template).
    static func drawDrone(in r: CGRect, color: NSColor = alertColor) {
        let k = min(r.width, r.height) / 18
        let ox = r.midX - 9 * k, oy = r.midY - 9 * k
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: ox + x * k, y: oy + y * k) }
        color.setFill(); color.setStroke()
        let wing = NSBezierPath()
        wing.move(to: p(9, 13.2)); wing.line(to: p(17.2, 3.4)); wing.line(to: p(0.8, 3.4)); wing.close()
        wing.lineJoinStyle = .round; wing.lineWidth = 0.8 * k
        wing.fill(); wing.stroke()
        NSBezierPath(roundedRect: NSRect(origin: p(7.6, 7.4), size: NSSize(width: 2.8 * k, height: 9.8 * k)),
                     xRadius: 1.4 * k, yRadius: 1.4 * k).fill()                                   // fuselage / nose
        for x: CGFloat in [0.5, 16.7] {                                                          // wingtip fins
            NSBezierPath(roundedRect: NSRect(origin: p(x, 1.8), size: NSSize(width: 0.8 * k, height: 4.2 * k)),
                         xRadius: 0.4 * k, yRadius: 0.4 * k).fill()
        }
        NSBezierPath(rect: NSRect(origin: p(8.55, 1.4), size: NSSize(width: 0.9 * k, height: 2.4 * k))).fill()   // tail
        NSBezierPath(roundedRect: NSRect(origin: p(7.0, 0.7), size: NSSize(width: 4 * k, height: 0.8 * k)),
                     xRadius: 0.4 * k, yRadius: 0.4 * k).fill()                                    // propeller
    }

    static let alertRed = NSColor(srgbRed: 1, green: 0.27, blue: 0.23, alpha: 1)

    /// Drone in `color` (menu bar: black/white to match the bar) with a severity dot on its side (`dot`).
    /// `dot` = nil draws the drone alone (yellow by default, for the glass card inside the window).
    static func drone(size: CGFloat = 18, color: NSColor = alertColor, dot: NSColor? = nil) -> NSImage {
        let w = dot == nil ? size : size + 6
        let img = NSImage(size: NSSize(width: w, height: size), flipped: false) { rect in
            drawDrone(in: NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: 0.5, dy: 0.5), color: color)
            if let dot {
                dot.setFill()
                let d = size / 3
                NSBezierPath(ovalIn: NSRect(x: size - 1, y: size * 0.62, width: d, height: d)).fill()
            }
            return true
        }
        img.isTemplate = false
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
