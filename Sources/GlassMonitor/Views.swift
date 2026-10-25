import SwiftUI

// MARK: - Formatting

private func formatSpeed(_ bytesPerSec: Double) -> String {
    let kb = bytesPerSec / 1024
    if kb < 1024 { return String(format: "%.0f KB/sec", kb) }
    return String(format: "%.1f MB/sec", kb / 1024)
}

private func formatBytes(_ b: Int64) -> String {
    String(format: "%.2f GB", Double(b) / 1_000_000_000).replacingOccurrences(of: ".", with: ",")
}

private func formatReset(_ date: Date, long: Bool = false) -> String {
    let mins = max(0, Int(date.timeIntervalSinceNow / 60))
    if mins >= 1440 { return "\(mins / 1440)d \((mins % 1440) / 60)h" }
    if mins >= 60 { return long ? "\(mins / 60)h \(mins % 60)m" : "\(mins / 60)h" }
    return "\(mins)m"
}

private func formatDuration(_ m: Int) -> String { "\(m / 60)h \(m % 60)m" }

// MARK: - Building blocks

private struct Card<Content: View>: View {
    var fill = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: fill ? .infinity : nil, alignment: .topLeading)
            .glass(.rect(cornerRadius: 16))
    }
}

private struct Title: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary).lineLimit(1).minimumScaleFactor(0.8) }
}

private struct Subtitle: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 11.5)).foregroundStyle(Color.primary.opacity(0.62)).lineLimit(1).minimumScaleFactor(0.8) }
}

private struct ActionLink: View {
    let text: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
    }
}

private struct IconView: View {
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

// MARK: - Backdrop (gives the glass something to refract)

private struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        let blob = dark ? Color.white : Color.black
        let k = dark ? 1.0 : 0.55
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                dark ? Color.black : Color(white: 0.96)
                Circle().fill(blob.opacity(0.20 * k)).frame(width: 300)
                    .blur(radius: 80)
                    .offset(x: 130 * sin(t / 7), y: 160 * cos(t / 9))
                Circle().fill(blob.opacity(0.14 * k)).frame(width: 260)
                    .blur(radius: 70)
                    .offset(x: -140 * cos(t / 8), y: -120 * sin(t / 6))
                Circle().fill(blob.opacity(0.10 * k)).frame(width: 220)
                    .blur(radius: 60)
                    .offset(x: 100 * sin(t / 5 + 2), y: -170 * cos(t / 10))
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Main view

struct ContentView: View {
    @EnvironmentObject var m: Monitor
    @EnvironmentObject var eyes: EyesModel

    var body: some View {
        ZStack {
            Backdrop()
            if m.page == .network {
                NetworkPage().transition(.opacity)
            } else if m.page == .claude {
                ClaudePage().transition(.opacity)
            } else if m.page == .memory {
                MemoryPage().transition(.opacity)
            } else if m.page == .alerts {
                AlertsPage().transition(.opacity)
            } else {
                mainPage.transition(.opacity)
            }
        }
        .frame(width: 460)
        .animation(.easeInOut(duration: 0.2), value: m.page)
        .onChange(of: m.page) { old, new in
            if new == .claude { eyes.hold(intro: "claude_in", loop: "claude_loop") }
            else if new == .alerts { eyes.hold(intro: nil, loop: "hello_disappointed", slice: (0, 0.55)) }   // worried brows, sad sigh
            else if old == .claude || old == .alerts { eyes.resume() }
        }
        .onAppear {
            eyes.mood = { [m] in
                if m.cpuLoad > 0.85 || (m.cpuTemp ?? 0) > 90 { return ("angry_01_loop", 2) }
                if m.battery.present && m.battery.percent <= 15 && !m.battery.charging { return ("sleeping_loop", 3) }
                return nil
            }
            m.onSpeedTest = { [eyes] state in
                switch state {
                case .running: eyes.think()
                case .done: eyes.finish(success: true)
                case .failed: eyes.finish(success: false)
                case .idle: break
                }
            }
            eyes.listening = { [m] in m.audioPlaying }
            eyes.start()
        }
    }

    private var mainPage: some View {
        ZStack {
            GlassGroup {
                VStack(spacing: 10) {
                    HStack(spacing: 10) { EyesPanel(); disk }.frame(height: 90)
                    HStack(spacing: 10) { memory; claude }.frame(height: 90)
                    HStack(alignment: .top, spacing: 10) {
                        wifi.frame(height: 160)
                        VStack(spacing: 10) { battery.frame(height: 75); devices.frame(height: 75) }
                    }
                    AirAlertCard()
                }
                .padding(12)
                .background {
                    Button("") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q").frame(width: 0, height: 0).opacity(0)
                }
            }
        }
    }

    private var disk: some View {
        Card(fill: true) {
            HStack(alignment: .top, spacing: 10) {
                DriveIcon()
                VStack(alignment: .leading, spacing: 3) {
                    Title(text: m.volumeName)
                    Subtitle(text: "Available: \(formatBytes(m.disk.available))")
                }
            }
            Spacer(minLength: 14)
            HStack { Spacer(); ActionLink(text: "Free Up", action: m.openStorage) }
        }
    }

    private var memory: some View {
        Card(fill: true) {
            HStack(alignment: .top, spacing: 10) {
                MemoryCardIcon()
                VStack(alignment: .leading, spacing: 3) {
                    Title(text: "Memory")
                    Subtitle(text: "Pressure: \(m.memoryPressure)%")
                }
            }
            Spacer(minLength: 14)
            HStack { Spacer(); ActionLink(text: "Free Up", action: m.openMemory) }
        }
    }

    private var batterySymbol: String {
        if m.battery.charging { return "battery.100percent.bolt" }
        switch m.battery.percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var batteryColor: Color {
        switch m.battery.percent {
        case ..<30: return Color(red: 1.0, green: 0.27, blue: 0.23)   // iOS red
        case ..<60: return Color(red: 1.0, green: 0.84, blue: 0.04)   // iOS yellow
        default: return .primary
        }
    }

    private var battery: some View {
        Card(fill: true) {
            HStack(alignment: .top, spacing: 10) {
                IconView(name: batterySymbol, color: batteryColor)
                VStack(alignment: .leading, spacing: 3) {
                    Title(text: "Battery")
                    Subtitle(text: batterySubtitle)
                }
                Spacer(minLength: 0)
                Text("\(m.battery.percent)%")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary).lineLimit(1).fixedSize()
            }
        }
    }

    private var batterySubtitle: String {
        guard m.battery.present else { return "Power adapter" }
        guard let mins = m.battery.minutes else { return m.battery.charging ? "Charging…" : "Calculating…" }
        return m.battery.charging ? "\(formatDuration(mins)) to full" : "\(formatDuration(mins)) left"
    }

    private var claude: some View {
        Card(fill: true) {
            let w = m.claude?.fiveHour
            HStack(alignment: .top, spacing: 10) {
                ClaudeMark()
                UsageBar(title: "Session (5hr)", percent: m.claude == nil ? nil : (w?.percent ?? 0), resetsAt: w?.resetsAt,
                         compact: true, emptyText: m.claude == nil ? "No data yet" : "No active session")
            }
        }
        .contentShape(.rect(cornerRadius: 16))
        .onTapGesture { m.page = .claude }
    }

    private var wifi: some View {
        Card {
            HStack(spacing: 10) {
                Image(systemName: m.ssid == nil ? "wifi.slash" : "wifi")
                    .font(.system(size: 19, weight: .medium)).foregroundStyle(Color.primary)
                    .frame(width: 30)
                Title(text: m.ssid ?? "Wi-Fi")
            }
            VStack(alignment: .leading, spacing: 14) {
                speedRow("arrow.up", m.up)
                speedRow("arrow.down", m.down)
            }
            .padding(.top, 16).padding(.leading, 5)

            Spacer(minLength: 12)
            HStack {
                Spacer()
                switch m.speedTest {
                case .running:
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Subtitle(text: "Testing…") }
                case .failed:
                    ActionLink(text: "Test Speed", action: m.openNetwork)
                default:
                    ActionLink(text: "Test Speed", action: m.openNetwork)
                }
            }
        }
    }

    private func speedRow(_ icon: String, _ v: Double) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).frame(width: 20)
                .foregroundStyle(Color.primary)
            Text(formatSpeed(v)).font(.system(size: 11.5)).monospacedDigit()
                .foregroundStyle(Color.primary.opacity(0.62))
        }
    }

    private var devices: some View {
        Card(fill: true) {
            HStack(alignment: .top, spacing: 10) {
                if let d = m.devices.first {
                    IconView(name: d.symbol)
                    VStack(alignment: .leading, spacing: 3) {
                        Title(text: d.name)
                        Subtitle(text: m.devices.count > 1 ? "Connected · +\(m.devices.count - 1) more" : "Connected")
                    }
                } else {
                    BluetoothIcon()
                    VStack(alignment: .leading, spacing: 3) {
                        Title(text: "Connected Devices")
                        Subtitle(text: "No devices connected")
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// SF Symbols has no Bluetooth glyph, so draw the rune.
private struct BluetoothIcon: View {
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

// MARK: - Network page

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

private struct NetworkPage: View {
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


// MARK: - Claude limits

private struct UsageBar: View {
    let title: String
    let percent: Double?
    let resetsAt: Date?
    var compact = false
    var emptyText = "No data yet"

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(percent.map { "\(Int($0.rounded()))%" } ?? "–").font(.system(size: 13, weight: .semibold)).monospacedDigit()
            }
            .foregroundStyle(Color.primary)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.14))
                    if let percent {
                        Capsule().fill(Color.primary.opacity(0.7))
                            .frame(width: max(g.size.height, g.size.width * min(percent, 100) / 100))
                    }
                }
            }
            .frame(height: compact ? 6 : 8)
            Subtitle(text: resetsAt.map { "Resets in \(formatReset($0, long: !compact))" } ?? emptyText)
        }
    }
}

private struct ClaudePage: View {
    @EnvironmentObject var m: Monitor

    private func box<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { c() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(.rect(cornerRadius: 16))
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
                    Text("Claude").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.primary)
                }
                EyesPanel().frame(height: 84)
                box {
                    let w = m.claude?.fiveHour
                    UsageBar(title: "Session (5hr)", percent: m.claude == nil ? nil : (w?.percent ?? 0), resetsAt: w?.resetsAt,
                             emptyText: m.claude == nil ? "No data yet" : "No active session")
                }
                box {
                    let w = m.claude?.sevenDay
                    UsageBar(title: "Weekly (7 days)", percent: m.claude == nil ? nil : (w?.percent ?? 0), resetsAt: w?.resetsAt,
                             emptyText: m.claude == nil ? "No data yet" : "No active window")
                }
            }
            .padding(12)
        }
    }
}


/// SF Symbols has no Claude glyph, so draw a radial starburst in its spirit.
private struct ClaudeMark: View {
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
private struct DriveIcon: View {
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

// MARK: - Memory page

private func formatMemory(_ bytes: UInt64) -> String {
    let gb = Double(bytes) / 1_073_741_824
    return gb >= 1 ? String(format: "%.1f GB", gb).replacingOccurrences(of: ".", with: ",")
                   : String(format: "%.0f MB", Double(bytes) / 1_048_576)
}

private struct MemoryPage: View {
    @EnvironmentObject var m: Monitor

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
                    Text("Memory").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.primary)
                    Spacer()
                    Text("Pressure: \(m.memoryPressure)%").font(.system(size: 11.5)).foregroundStyle(Color.primary.opacity(0.62))
                }
                VStack(spacing: 0) {
                    if m.memoryApps.isEmpty {
                        Subtitle(text: "Loading…").padding(14)
                    }
                    ForEach(m.memoryApps) { a in
                        HStack(spacing: 10) {
                            Image(nsImage: a.icon).resizable().frame(width: 28, height: 28)
                            Text(a.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(formatMemory(a.bytes)).font(.system(size: 11.5)).monospacedDigit()
                                .foregroundStyle(Color.primary.opacity(0.62))
                            Button { m.quit(a) } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.primary).frame(width: 24, height: 24)
                                    .glass(.circle)
                                    .contentShape(.circle)
                            }
                            .buttonStyle(.plain)
                            .help("Quit \(a.name)")
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        if a.id != m.memoryApps.last?.id {
                            Divider().overlay(Color.primary.opacity(0.08)).padding(.leading, 52)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(.rect(cornerRadius: 16))
                .animation(.easeInOut(duration: 0.2), value: m.memoryApps.map(\.id))
            }
            .padding(12)
        }
    }
}

/// Memory card: contacts in a scalloped notch on top (see-through), a side notch,
/// and a cut-out window at the bottom. Tall and narrow.
private struct MemoryCardIcon: View {
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


// MARK: - Air-raid alert card

private struct AirAlertCard: View {
    @EnvironmentObject var air: AirAlertMonitor
    @EnvironmentObject var m: Monitor

    private static let yellow = Color(red: 1, green: 0.84, blue: 0.04)
    private static let red = Color(red: 1, green: 0.27, blue: 0.23)

    var body: some View {
        let a = air.alert
        let accent = a.map { $0.red ? Self.red : Self.yellow }
        HStack(alignment: .top, spacing: 10) {
            Group {
                if a != nil {
                    Image(nsImage: FaceIcon.drone(size: 22)).resizable().frame(width: 22, height: 22)
                } else {
                    Image(systemName: "checkmark.shield").font(.system(size: 18)).foregroundStyle(Color.primary.opacity(0.62))
                }
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Title(text: a == nil ? "Тривоги немає" : "Повітряна тривога")
                    Spacer(minLength: 6)
                    if let since = a?.since {
                        Text("з \(ukTime(since))")
                            .font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(accent ?? Color.primary)
                    }
                }
                if let a {
                    Subtitle(text: a.regionName)
                    Text(a.reason ?? (a.red ? "Червоний рівень" : "Жовтий рівень"))
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(accent ?? Color.primary)
                    if !a.threats.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(a.threats, id: \.self) { t in
                                Text(t).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.75))
                                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.top, 4)
                    }
                } else {
                    Subtitle(text: air.watchedLabel ?? "Визначаю регіон…")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.rect(cornerRadius: 16))
        .overlay {
            if let accent { RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(0.55), lineWidth: 1) }
        }
        .contentShape(.rect(cornerRadius: 16))
        .onTapGesture { m.page = .alerts }
        .animation(.easeInOut(duration: 0.25), value: a)
    }
}


// MARK: - Alerts map page

private let alertColor = Color(nsColor: FaceIcon.alertColor)

/// 24-hour Ukrainian time ("21:56", or "25 жовт., 21:56" for older alerts) regardless of the system's 12-hour setting.
private func ukTime(_ d: Date, withDate: Bool = false) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "uk_UA")
    f.dateFormat = withDate ? "d MMM, HH:mm" : "HH:mm"
    return f.string(from: d)
}

private struct AlertsPage: View {
    @EnvironmentObject var m: Monitor
    @EnvironmentObject var air: AirAlertMonitor

    var body: some View {
        let active = air.oblasts.filter { !$0.value.standing }.count
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
                    Text("Мапа тривог").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.primary)
                    Spacer()
                    Text(active == 0 ? "Тривог немає" : "Тривога в \(active) обл.")
                        .font(.system(size: 11.5)).foregroundStyle(active == 0 ? Color.primary.opacity(0.62) : alertColor)
                }
                EyesPanel().frame(height: 84)
                VStack(alignment: .leading, spacing: 10) {
                    if let map = UkraineMap.shared {
                        // fixed size: a flexible map lets the window shrink when the hover label appears
                        AlertMap(map: map, oblasts: air.oblasts, mine: air.watchedOblast)
                            .frame(width: 408, height: (408 / map.aspect).rounded())
                    } else {
                        Subtitle(text: "Мапа недоступна")
                    }
                    HStack(spacing: 12) {
                        legend(alertColor.opacity(0.95), "уся область")
                        legend(alertColor.opacity(0.62), "частина")
                        legend(alertColor.opacity(0.22), "тривала")
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).strokeBorder(Color.primary, lineWidth: 1.4).frame(width: 10, height: 10)
                            Text("твій регіон")
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 10.5)).foregroundStyle(Color.primary.opacity(0.62))
                    if let t = air.updatedAt {
                        Text("Оновлено о \(ukTime(t)) · siren.pp.ua · не замінює офіційні сповіщення")
                            .font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.45))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(.rect(cornerRadius: 16))
            }
            .padding(12)
        }
    }

    private func legend(_ c: Color, _ text: String) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10); Text(text) }
    }
}

/// Ukraine with oblasts tinted by alert state; the watched oblast is outlined; hover shows details.
private struct AlertMap: View {
    let map: UkraineMap
    let oblasts: [String: AirAlertMonitor.OblastAlert]
    let mine: String?
    // @State is a macro in the new SDK and the Command Line Tools ship no plugin for it → keep hover in a tiny object
    private final class Hover: ObservableObject { @Published var value: (name: String, at: CGPoint)? }
    @StateObject private var hoverBox = Hover()
    private var hover: (name: String, at: CGPoint)? { hoverBox.value }

    private static func path(_ r: UkraineMap.Region, _ size: CGSize) -> Path {
        var p = Path()
        for poly in r.polys {
            guard let f = poly.first else { continue }
            p.move(to: CGPoint(x: f.x * size.width, y: f.y * size.height))
            for q in poly.dropFirst() { p.addLine(to: CGPoint(x: q.x * size.width, y: q.y * size.height)) }
            p.closeSubpath()
        }
        return p
    }

    private func label(_ name: String) -> String {
        guard let o = oblasts[name] else { return "\(name)\nТривоги немає" }
        var lines = [name]
        if o.standing { lines.append("Тривала тривога") }
        else { lines.append(o.whole ? "Тривога на всю область" : "Тривога в \(o.areas) \(o.areas == 1 ? "громаді/районі" : "громадах/районах")") }
        if let since = o.since {
            lines.append("з " + ukTime(since, withDate: !Calendar.current.isDateInToday(since)))
        }
        if o.red { lines.append("Червоний рівень") }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        GeometryReader { g in
            canvas
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let pt):
                        // last match wins: м. Київ is drawn over Київська область
                        hoverBox.value = map.regions.last { Self.path($0, g.size).contains(pt) }.map { ($0.name, pt) }
                    case .ended: hoverBox.value = nil
                    }
                }
        }
    }

    private var canvas: some View {
        Canvas { ctx, size in
            func path(_ r: UkraineMap.Region) -> Path { Self.path(r, size) }
            for r in map.regions {
                let p = path(r)
                let fill: Color
                if let o = oblasts[r.name] {
                    fill = o.standing ? alertColor.opacity(0.22) : alertColor.opacity(o.whole ? 0.95 : 0.62)
                } else {
                    fill = Color.primary.opacity(0.08)
                }
                ctx.fill(p, with: .color(fill))
                ctx.stroke(p, with: .color(Color.primary.opacity(0.28)), style: StrokeStyle(lineWidth: 0.6, lineJoin: .round))
            }
            if let mine, let r = map.regions.first(where: { $0.name == mine }) {
                ctx.stroke(path(r), with: .color(.primary), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            }
            if let h = hover, let r = map.regions.last(where: { $0.name == h.name }) {
                ctx.stroke(path(r), with: .color(alertColor), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))

                // Hover label drawn inside the canvas with a solid background: a separate overlay view with a
                // material made the Liquid Glass card around the map re-render (streaks at the edges).
                let text = ctx.resolve(Text(label(h.name)).font(.system(size: 11)).foregroundStyle(Color.primary))
                let ts = text.measure(in: CGSize(width: 220, height: 200))
                let box = CGSize(width: ts.width + 16, height: ts.height + 12)
                let x = min(max(h.at.x + 12, 0), size.width - box.width)
                let y = h.at.y - box.height - 10 < 0 ? h.at.y + 16 : h.at.y - box.height - 10
                let rect = CGRect(x: x, y: min(y, size.height - box.height), width: box.width, height: box.height)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(Color(nsColor: .windowBackgroundColor).opacity(0.96)))
                ctx.stroke(Path(roundedRect: rect, cornerRadius: 8), with: .color(Color.primary.opacity(0.15)), lineWidth: 0.5)
                ctx.draw(text, in: rect.insetBy(dx: 8, dy: 6))
            }
        }
    }
}
