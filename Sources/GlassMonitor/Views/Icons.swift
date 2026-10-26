import SwiftUI

struct IconView: View {
    let name: String
    var color: Color = .primary
    var body: some View {
        Image(systemName: name)
            .font(.system(size: 19))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .frame(width: 30, height: 30)
    }
}

/// SF Symbols has no Bluetooth glyph, so draw the rune.
struct BluetoothIcon: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0.0, y: 0.30)); p.addLine(to: CGPoint(x: 1.0, y: 0.72))
            p.addLine(to: CGPoint(x: 0.5, y: 1.0)); p.addLine(to: CGPoint(x: 0.5, y: 0.0))
            p.addLine(to: CGPoint(x: 1.0, y: 0.28)); p.addLine(to: CGPoint(x: 0.0, y: 0.70))
        }
        .applying(CGAffineTransform(scaleX: 11, y: 18))
        .stroke(Color.primary, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        .frame(width: 11, height: 18)
        .frame(width: 30, height: 30)
    }
}

/// SF Symbols has no Claude glyph, so draw a radial starburst in its spirit.
struct ClaudeMark: View {
    private static let lengths: [CGFloat] = [1, 0.62, 0.9, 0.55, 1, 0.7, 0.85, 0.6, 1, 0.58, 0.92, 0.66]

    private func rays(long: Bool) -> some View {
        Path { p in
            for (i, l) in Self.lengths.enumerated() where (l >= 0.75) == long {
                let a = Double(i) / Double(Self.lengths.count) * 2 * .pi
                p.move(to: CGPoint(x: 0.5 + 0.1 * CGFloat(cos(a)), y: 0.5 + 0.1 * CGFloat(sin(a))))
                p.addLine(to: CGPoint(x: 0.5 + 0.5 * l * CGFloat(cos(a)), y: 0.5 + 0.5 * l * CGFloat(sin(a))))
            }
        }
        .applying(CGAffineTransform(scaleX: 20, y: 20))
        .stroke(Color.primary, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        .opacity(long ? 1 : 0.5)
    }

    var body: some View {
        ZStack { rays(long: false); rays(long: true) }
            .frame(width: 20, height: 20)
            .frame(width: 30, height: 30)
    }
}

/// Drive: solid cap, small gap, solid base with a cut-out slot and status light
/// (drawn by hand: the SF Symbol is a single flat layer).
struct DriveIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let ox = (size.width - 22) / 2, oy = (size.height - 16) / 2
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x, y: oy + y) }
            let solid = GraphicsContext.Shading.color(.primary)

            var cap = Path()                          // flared lid with rounded top corners
            cap.move(to: p(0.8, 7.4))
            cap.addLine(to: p(3.7, 2.4))
            cap.addQuadCurve(to: p(5.9, 1.1), control: p(4.4, 1.1))
            cap.addLine(to: p(16.1, 1.1))
            cap.addQuadCurve(to: p(18.3, 2.4), control: p(17.6, 1.1))
            cap.addLine(to: p(21.2, 7.4))
            cap.closeSubpath()
            ctx.fill(cap, with: solid)

            ctx.fill(Path(roundedRect: CGRect(origin: p(0.8, 8.7), size: CGSize(width: 20.4, height: 6.6)), cornerRadius: 2.6), with: solid)

            ctx.blendMode = .destinationOut           // slot + light are holes, so the glass shows through
            ctx.fill(Path(roundedRect: CGRect(origin: p(3.4, 11.3), size: CGSize(width: 11.6, height: 1.4)), cornerRadius: 0.7), with: solid)
            ctx.fill(Path(ellipseIn: CGRect(origin: p(16.6, 11.05), size: CGSize(width: 1.9, height: 1.9))), with: solid)
        }
        .frame(width: 30, height: 30)
    }
}

/// Memory card: contacts in a scalloped notch on top (see-through), a side notch,
/// and a cut-out window at the bottom. Tall and narrow.
struct MemoryCardIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w: CGFloat = 15, h: CGFloat = 22
            let ox = (size.width - w) / 2, oy = (size.height - h) / 2
            func r(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat) -> CGRect { CGRect(x: ox + x, y: oy + y, width: rw, height: rh) }
            let solid = GraphicsContext.Shading.color(.primary)
            let pinsX: [CGFloat] = [4.8, 7.5, 10.2]

            ctx.drawLayer { l in                      // body + holes in their own layer
                l.fill(Path(roundedRect: r(0, 0, w, h), cornerRadius: 3.6), with: solid)
                l.blendMode = .destinationOut
                for x in pinsX {                       // overlapping capsules → scalloped notch around the pins
                    l.fill(Path(roundedRect: r(x - 1.75, -2, 3.5, 6.6), cornerRadius: 1.75), with: solid)
                }
                l.fill(Path(roundedRect: r(w - 1.7, 8.4, 4, 4.4), cornerRadius: 1.3), with: solid)        // side notch
                l.fill(Path(roundedRect: r(2.5, h - 7.4, w - 5, 9), cornerRadius: 2.8), with: solid)       // window ring…
                l.blendMode = .normal
                l.fill(Path(roundedRect: r(3.5, h - 6.3, w - 7, 5.6), cornerRadius: 1.8), with: solid)     // …around a solid block
            }
            for x in pinsX {                           // see-through contacts
                ctx.fill(Path(roundedRect: r(x - 0.8, 0.2, 1.6, 3.6), cornerRadius: 0.8), with: .color(.primary.opacity(0.5)))
            }
        }
        .frame(width: 30, height: 30)
    }
}
