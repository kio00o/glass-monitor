import SwiftUI

private func formatTotal(_ b: UInt64) -> String {
    let mb = Double(b) / 1_000_000
    return mb < 1000 ? String(format: "%.1f MB", mb).replacingOccurrences(of: ".", with: ",")
                     : String(format: "%.2f GB", mb / 1000).replacingOccurrences(of: ".", with: ",")
}

private struct Sparkline: View {
    let values: [Double]
    var body: some View {
        GeometryReader { g in
            let mx = max(values.max() ?? 1, 10_000)
            let pts = values.enumerated().map { i, v in
                CGPoint(x: g.size.width * CGFloat(i) / CGFloat(values.count - 1),
                        y: g.size.height - 3 - (g.size.height - 8) * CGFloat(v / mx))
            }
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: g.size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: g.size.width, y: g.size.height))
                }.fill(LinearGradient(colors: [Color.primary.opacity(0.28), Color.primary.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { p in
                    p.move(to: pts[0]); pts.dropFirst().forEach { p.addLine(to: $0) }
                }.stroke(Color.primary.opacity(0.9), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            }
        }
    }
}

private struct DotRing: View {
    let running: Bool
    let done: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let head = Int((ctx.date.timeIntervalSinceReferenceDate * 30).truncatingRemainder(dividingBy: 60))
            ZStack {
                ForEach(0..<60, id: \.self) { i in
                    let d = (head - i + 60) % 60
                    Capsule().fill(Color.primary)
                        .frame(width: 2.5, height: 6)
                        .opacity(done ? 0.85 : running ? max(0.12, 1 - Double(d) / 30) : 0.2)
                        .offset(y: -52)
                        .rotationEffect(.degrees(Double(i) * 6))
                }
                Circle().fill(Color.primary.opacity(0.08)).frame(width: 86, height: 86)
                    .glass(.circle)
                VStack(spacing: 4) {
                    Image(systemName: done ? "checkmark.circle" : "arrow.up.arrow.down")
                        .font(.system(size: 18)).foregroundStyle(Color.primary)
                    Text(done ? "Done" : running ? "Testing…" : "Idle")
                        .font(.system(size: 10.5)).foregroundStyle(Color.primary)
                }
            }
        }
        .frame(width: 130, height: 130)
    }
}

struct NetworkPage: View {
    @EnvironmentObject var m: Monitor

    private func box<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { c() }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(.rect(cornerRadius: 16))
    }

    private func chart(_ title: String, _ total: UInt64, _ speed: Double, _ h: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 13, weight: .semibold))
            HStack {
                Text(formatTotal(total)); Spacer(); Text(formatSpeed(speed)).monospacedDigit()
            }
            .font(.system(size: 10.5)).foregroundStyle(Color.primary.opacity(0.6)).padding(.top, 2)
            Sparkline(values: h).frame(height: 40).padding(.top, 8)
        }
        .foregroundStyle(Color.primary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.rect(cornerRadius: 16))
    }

    private var mbps: Double? {
        if case .done(let d, _) = m.speedTest { return d * 8 / 1_000_000 }
        return nil
    }

    private var goodFor: [String] {
        guard let v = mbps else { return [] }
        return [("Messaging", 0.5), ("Audio calls", 1), ("Music streaming", 2),
                ("Video calls", 5), ("Video streaming", 15), ("Online gaming", 25)]
            .filter { v >= $0.1 }.map(\.0)
    }

    var body: some View {
        GlassGroup {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Button { m.page = .main } label: {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.primary).frame(width: 28, height: 28)
                            .glass(.circle)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    Text("Network").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.primary)
                }
                EyesPanel().frame(height: 84)
                box {
                    HStack(spacing: 10) {
                        Image(systemName: m.ssid == nil ? "wifi.slash" : "wifi").font(.system(size: 17))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.ssid ?? "Wi-Fi").font(.system(size: 13, weight: .semibold))
                            Text("Wi-Fi connection · \(m.security)").font(.system(size: 10.5)).foregroundStyle(Color.primary.opacity(0.6))
                        }
                        Spacer()
                        if m.linkRate > 0 { Text("\(m.linkRate) Mbps").font(.system(size: 11.5, weight: .semibold)) }
                    }
                    .foregroundStyle(Color.primary)
                }
                HStack(spacing: 10) {
                    chart("Download", m.totalDown, m.down, m.downHistory)
                    chart("Upload", m.totalUp, m.up, m.upHistory)
                }
                box {
                    Text("Test Your Connection").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary)
                    HStack(alignment: .center, spacing: 14) {
                        DotRing(running: m.speedTest == .running, done: mbps != nil)
                        VStack(alignment: .leading, spacing: 6) {
                            if let v = mbps {
                                Text(String(format: "%.1f Mbps", v).replacingOccurrences(of: ".", with: ","))
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Good for:").font(.system(size: 10.5)).foregroundStyle(Color.primary.opacity(0.6))
                                ForEach(goodFor, id: \.self) { g in
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                        Text(g)
                                    }.font(.system(size: 10.5))
                                }
                            } else if m.speedTest == .failed {
                                Text("Test failed").font(.system(size: 12))
                            } else {
                                Text("Measuring…").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.6))
                            }
                            Button(m.speedTest == .running ? "Running…" : "Run again") { m.runSpeedTest() }
                                .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                                .opacity(m.speedTest == .running ? 0.4 : 1).padding(.top, 2)
                        }
                        .foregroundStyle(Color.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 6)
                }
            }
            .padding(12)
        }
    }
}
