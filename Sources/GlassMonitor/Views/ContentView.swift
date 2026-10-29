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
    @EnvironmentObject var updater: Updater

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
            } else if m.page == .settings {
                SettingsPage().transition(.opacity)
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

    /// A half-width tile: the mascot or one widget. Wi-Fi is twice as tall as the rest.
    private enum Slot: Hashable { case mascot, widget(Monitor.Widget) }
    private static let rowH: CGFloat = 90, spacing: CGFloat = 10
    private func height(_ slot: Slot) -> CGFloat { slot == .widget(.wifi) ? Self.rowH * 2 + Self.spacing : Self.rowH }

    @ViewBuilder private func slotView(_ slot: Slot) -> some View {
        switch slot {
        case .mascot: EyesPanel()
        case .widget(.disk): disk
        case .widget(.memory): memory
        case .widget(.cpu): cpu
        case .widget(.claude): claude
        case .widget(.wifi): wifi
        case .widget(.battery): battery
        case .widget(.devices): devices
        case .widget(.alerts): EmptyView()   // alerts span the bottom row, not the grid
        }
    }

    /// Greedy two-column packing in the chosen order, so a tall Wi-Fi tile sits beside stacked short ones.
    private var columns: ([Slot], [Slot]) {
        var c0: [Slot] = [.mascot], c1: [Slot] = []
        var h0 = Self.rowH + Self.spacing, h1: CGFloat = 0
        for w in m.orderedEnabled where w != .alerts {
            let slot = Slot.widget(w), h = height(slot) + Self.spacing
            if h0 <= h1 { c0.append(slot); h0 += h } else { c1.append(slot); h1 += h }
        }
        return (c0, c1)
    }

    private func column(_ slots: [Slot]) -> some View {
        VStack(spacing: Self.spacing) {
            ForEach(slots, id: \.self) { slotView($0).frame(height: height($0)) }
        }
    }

    private var mainPage: some View {
        let (c0, c1) = columns
        return GlassGroup {
            VStack(spacing: Self.spacing) {
                HStack(alignment: .top, spacing: Self.spacing) { column(c0); column(c1) }
                HStack(spacing: Self.spacing) {
                    if m.isEnabled(.alerts) { AirAlertCard(); settingsBox(wide: false) }
                    else { settingsBox(wide: true) }   // no alert card: the box fills the bottom row
                }
                if let v = updater.available { updateBanner(v) }
            }
            .padding(12)
            .background {
                Button("") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q").frame(width: 0, height: 0).opacity(0)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: m.orderedEnabled)
    }

    /// Full-width banner under all widgets when a newer version is out; tap to install.
    private func updateBanner(_ version: String) -> some View {
        let red = Color(red: 1, green: 0.27, blue: 0.23)
        let text = updater.installing ? "Updating…" : updater.failed ? "Update failed — tap to retry" : "Update to \(version) available"
        return Button { updater.install() } label: {
            HStack(spacing: 10) {
                Image(systemName: updater.failed ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill")
                    .font(.system(size: 16)).foregroundStyle(red)
                Text(text).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.primary)
                Spacer(minLength: 0)
                if updater.installing { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(.rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(red.opacity(0.5), lineWidth: 1) }
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(updater.installing)
    }

    /// Settings box in the bottom row. `wide` (no alert card): fills the row; otherwise a 58 pt icon box
    /// beside the alert card, matching its height.
    private func settingsBox(wide: Bool) -> some View {
        Button { m.page = .settings } label: {
            Image(systemName: "slider.horizontal.3").font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.85))
                .frame(maxWidth: wide ? .infinity : nil)
                .frame(width: wide ? nil : 58).frame(minHeight: 54, maxHeight: .infinity)
                .glass(.rect(cornerRadius: 16))
                .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .help("Widgets")
    }

    private var cpu: some View {
        let hot = Color(red: 1, green: 0.27, blue: 0.23)
        return Card(fill: true) {
            HStack(alignment: .top, spacing: 10) {
                CpuIcon(tint: m.cpuHot ? hot : .primary)
                VStack(alignment: .leading, spacing: 3) {
                    Title(text: "CPU")
                    Subtitle(text: "Load: \(Int((m.cpuLoad * 100).rounded()))%")
                }
                Spacer(minLength: 0)
                if let t = m.cpuTemp {
                    Text("\(Int(t.rounded()))°")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(m.cpuHot ? hot : Color.primary).lineLimit(1).fixedSize()
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
                if case .running = m.speedTest {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Subtitle(text: "Testing…") }
                } else {
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
