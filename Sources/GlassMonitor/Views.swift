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
            } else {
                mainPage.transition(.opacity)
            }
        }
        .frame(width: 460)
        .animation(.easeInOut(duration: 0.2), value: m.page)
        .onChange(of: m.page) { old, new in
            if new == .claude { eyes.hold(intro: "claude_in", loop: "claude_loop") }
            else if old == .claude { eyes.resume() }
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
                MemoryChipIcon()
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
                UsageBar(title: "Session (5hr)", percent: w?.percent, resetsAt: w?.resetsAt, compact: true)
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
            Subtitle(text: resetsAt.map { "Resets in \(formatReset($0, long: !compact))" } ?? "No data yet")
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
                    UsageBar(title: "Session (5hr)", percent: w?.percent, resetsAt: w?.resetsAt)
                }
                box {
                    let w = m.claude?.sevenDay
                    UsageBar(title: "Weekly (7 days)", percent: w?.percent, resetsAt: w?.resetsAt)
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

/// Drive with a see-through base; the SF Symbol is a single layer, so it is drawn by hand.
private struct DriveIcon: View {
    var body: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 6.5, y: 0.8)); p.addLine(to: CGPoint(x: 15.5, y: 0.8))
                p.addLine(to: CGPoint(x: 20.2, y: 9.6)); p.addLine(to: CGPoint(x: 1.8, y: 9.6)); p.closeSubpath()
            }
            .fill(Color.primary)
            .overlay(Path { p in
                p.move(to: CGPoint(x: 6.5, y: 0.8)); p.addLine(to: CGPoint(x: 15.5, y: 0.8))
                p.addLine(to: CGPoint(x: 20.2, y: 9.6)); p.addLine(to: CGPoint(x: 1.8, y: 9.6)); p.closeSubpath()
            }.stroke(Color.primary, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round)))
            .frame(width: 22, height: 10.4).offset(y: -3.8)

            RoundedRectangle(cornerRadius: 3.4).frame(width: 22, height: 7.4)
                .foregroundStyle(Color.primary.opacity(0.5))
                .offset(y: 5.4)
            HStack(spacing: 1.9) {
                ForEach(0..<5, id: \.self) { _ in Capsule().frame(width: 1.1, height: 2.6) }
            }
            .foregroundStyle(Color.primary)
            .offset(x: 1.5, y: 5.4)
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

/// Memory chip with see-through pins (the SF Symbol is a single layer, so its pins can't be dimmed).
private struct MemoryChipIcon: View {
    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                let x = (CGFloat(i) - 2) * 4.6
                Capsule().frame(width: 1.8, height: 3.4).offset(x: x, y: -7.2)
                Capsule().frame(width: 1.8, height: 3.4).offset(x: x, y: 7.2)
            }
            .opacity(0.5)
            RoundedRectangle(cornerRadius: 3.2).frame(width: 22, height: 12.5)
        }
        .foregroundStyle(Color.primary)
        .frame(width: 30, height: 30)
    }
}
