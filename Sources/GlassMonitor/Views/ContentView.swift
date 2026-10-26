import SwiftUI

private func formatBytes(_ b: Int64) -> String {
    String(format: "%.2f GB", Double(b) / 1_000_000_000).replacingOccurrences(of: ".", with: ",")
}

private func formatDuration(_ m: Int) -> String { "\(m / 60)h \(m % 60)m" }

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
                if m.cpuHot { return ("angry_01_loop", 2) }
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
